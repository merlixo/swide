import AppKit
import Observation
import SwideCore

struct OpenWindow: Identifiable, Equatable {
    let id: String
    let path: String
    let name: String
    let lastUsed: Date?
    let focused: Bool
    var pinned: Bool
    var claude: ClaudeState
    let socket: String
}

enum Selection: Hashable {
    case project(String)
    case window(String)
}

enum Direction { case up, down, left, right }

@MainActor
@Observable
final class AppModel {
    static let columns = 4

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            confirmProject = nil
            selection = hits.first.map { .project($0.project.path) } ?? windows.first.map { .window($0.id) }
        }
    }
    var projects: [Project] = []
    var windows: [OpenWindow] = []
    var selection: Selection?
    var confirmProject: Project?
    var thumbnails: [String: NSImage] = [:]
    var config = Config.load()
    /// Hover only selects after a real mouse move, so the pointer resting
    /// where the panel appears doesn't steal the default selection.
    var mouseArmed = false

    @ObservationIgnored weak var panel: PanelController?
    @ObservationIgnored weak var searchField: NSTextField?
    @ObservationIgnored var targetScreen: NSScreen?
    @ObservationIgnored private var state = AppState.load()
    @ObservationIgnored private let mover = WindowMover()
    @ObservationIgnored private var scanned: [String] = []

    var root: String { Paths.expand(config.searchRoot) }

    var hits: [ProjectHit] {
        ProjectCatalog.search(projects, query: query, excluding: Set(windows.map(\.path)))
    }

    var openPaths: Set<String> { Set(windows.map(\.path)) }

    // MARK: Data

    func bootstrap() {
        scanned = ProjectScanner.scan(root: root)
        refreshProjects()
        refreshWindows()
    }

    func refreshProjects() {
        projects = ProjectCatalog.build(recents: CursorRecents.load(), scanned: scanned, root: root)
    }

    /// Rescans the search root off the main thread; ~60 folders, a few ms.
    func rescanInBackground() {
        let root = self.root
        Task.detached(priority: .utility) {
            let found = ProjectScanner.scan(root: root)
            await MainActor.run {
                self.scanned = found
                self.refreshProjects()
            }
        }
    }

    func refreshWindows() {
        let now = Date()
        let sessions = ClaudeSessions.load(now: now)
        var changed = false
        var list: [OpenWindow] = []
        for b in BridgeRegistry.load() {
            guard let path = b.folders.first else { continue }
            let known = state.lastActive[path] ?? 0
            let reported = b.focused ? now.timeIntervalSince1970 : b.lastFocus / 1000
            let last = max(known, reported)
            if last > known {
                state.lastActive[path] = last
                changed = true
            }
            list.append(OpenWindow(
                id: b.id, path: path, name: URL(fileURLWithPath: path).lastPathComponent,
                lastUsed: last > 0 ? Date(timeIntervalSince1970: last) : nil, focused: b.focused,
                pinned: state.pinned.contains(path),
                claude: ClaudeSessions.state(for: path, in: sessions, now: now), socket: b.socket))
        }
        if changed { state.save() }
        windows = list.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
    }

    func lastActive(_ path: String) -> Date? {
        state.lastActive[path].map { Date(timeIntervalSince1970: $0) }
    }

    // MARK: Panel lifecycle

    func prepareForShow(screen: NSScreen?) {
        targetScreen = screen
        config = Config.load()
        query = ""
        confirmProject = nil
        mouseArmed = false
        refreshProjects()
        refreshWindows()

        // Like ⌘Tab: from Cursor, preselect the previous window; from elsewhere, the last one.
        let index = Cursor.isFrontmost ? 1 : 0
        if windows.indices.contains(index) {
            selection = .window(windows[index].id)
        } else {
            selection = hits.first.map { .project($0.project.path) } ?? windows.first.map { .window($0.id) }
        }
    }

    func didShow() {
        rescanInBackground()
        let targets = windows.map { (path: $0.path, name: $0.name) }
        Task {
            let images = await Thumbnails.capture(targets)
            thumbnails.merge(images) { _, new in new }
        }
    }

    func hide() {
        panel?.hide()
    }

    // MARK: Rules

    func isProtected(_ w: OpenWindow) -> Bool {
        (config.protect.pinned && w.pinned) || (config.protect.claudeWorking && w.claude == .working)
    }

    private func eviction() -> EvictionDecision {
        Eviction.decide(
            mru: windows.map { WindowSnapshot(id: $0.id, isProtected: isProtected($0)) },
            max: config.maxWindows)
    }

    /// The window that would close if the selected project were opened now.
    var doomedWindowID: String? {
        guard case .project(let path) = selection, !openPaths.contains(path),
              case .close(let id) = eviction() else { return nil }
        return id
    }

    // MARK: Actions

    func activateSelection(force: Bool) {
        if let project = confirmProject {
            open(project, force: true)
            return
        }
        switch selection {
        case .project(let path):
            if let project = projects.first(where: { $0.path == path }) { open(project, force: force) }
        case .window(let id):
            if let w = windows.first(where: { $0.id == id }) { switchTo(w) }
        case nil:
            break
        }
    }

    func switchTo(_ w: OpenWindow) {
        hide()
        touch(w.path)
        let screen = targetScreen
        Task { await mover.focus(path: w.path, name: w.name, on: screen) }
    }

    func open(_ project: Project, force: Bool) {
        if let w = windows.first(where: { $0.path == project.path }) {
            switchTo(w)
            return
        }
        var victim: OpenWindow?
        if !force {
            switch eviction() {
            case .room: break
            case .close(let id): victim = windows.first { $0.id == id }
            case .allProtected:
                confirmProject = project
                return
            }
        }
        confirmProject = nil
        hide()
        touch(project.path)
        let screen = targetScreen
        Task {
            // Open first, close after: the screen never goes empty.
            await mover.focus(path: project.path, name: project.name, on: screen)
            if let victim { BridgeClient.send("close", socket: victim.socket) }
        }
    }

    func close(_ w: OpenWindow) {
        BridgeClient.send("close", socket: w.socket)
        windows.removeAll { $0.id == w.id }
        if selection == .window(w.id) {
            selection = windows.first.map { .window($0.id) } ?? hits.first.map { .project($0.project.path) }
        }
    }

    func togglePin(_ w: OpenWindow) {
        if state.pinned.contains(w.path) { state.pinned.remove(w.path) } else { state.pinned.insert(w.path) }
        state.save()
        if let i = windows.firstIndex(where: { $0.id == w.id }) { windows[i].pinned.toggle() }
    }

    private func touch(_ path: String) {
        state.lastActive[path] = Date().timeIntervalSince1970
        state.save()
    }

    var selectedWindow: OpenWindow? {
        guard case .window(let id) = selection else { return nil }
        return windows.first { $0.id == id }
    }

    // MARK: Keyboard

    /// Returns true when the key was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case 125: move(.down)
        case 126: move(.up)
        case 123: move(.left)
        case 124: move(.right)
        case 36, 76: activateSelection(force: command)
        case 53:
            if confirmProject != nil {
                confirmProject = nil
            } else if !query.isEmpty {
                query = ""
            } else {
                hide()
            }
        case 51 where command:
            guard let w = selectedWindow else { return false }
            close(w)
        default:
            guard command, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
            if key == "p", let w = selectedWindow {
                togglePin(w)
            } else if let n = Int(key), (1...9).contains(n), windows.indices.contains(n - 1) {
                switchTo(windows[n - 1])
            } else {
                return false
            }
        }
        return true
    }

    func move(_ direction: Direction) {
        let tiles = hits
        let cols = Self.columns
        switch selection {
        case .project(let path):
            guard let i = tiles.firstIndex(where: { $0.project.path == path }) else { return }
            let col = i % cols
            switch direction {
            case .left where col > 0: selection = .project(tiles[i - 1].project.path)
            case .right where col < cols - 1 && i + 1 < tiles.count: selection = .project(tiles[i + 1].project.path)
            case .up where i >= cols: selection = .project(tiles[i - cols].project.path)
            case .down:
                if i + cols < tiles.count {
                    selection = .project(tiles[i + cols].project.path)
                } else if !windows.isEmpty {
                    let j = min(windows.count - 1, col * windows.count / cols)
                    selection = .window(windows[j].id)
                }
            default: break
            }
        case .window(let id):
            guard let j = windows.firstIndex(where: { $0.id == id }) else { return }
            switch direction {
            case .left where j > 0: selection = .window(windows[j - 1].id)
            case .right where j + 1 < windows.count: selection = .window(windows[j + 1].id)
            case .up where !tiles.isEmpty:
                let col = min(cols - 1, Int((Double(j) + 0.5) / Double(windows.count) * Double(cols)))
                let lastRow = (tiles.count - 1) / cols * cols
                selection = .project(tiles[min(tiles.count - 1, lastRow + col)].project.path)
            default: break
            }
        case nil:
            selection = tiles.first.map { .project($0.project.path) } ?? windows.first.map { .window($0.id) }
        }
    }
}
