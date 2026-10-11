import AppKit
import SwiftUI
import SwideCore

/// `Swide --snapshot out.png`: renders the panel with real projects and sample
/// windows, to check the layout without the hotkey or permissions.
@MainActor
enum Snapshot {
    static func render(to path: String) {
        let model = AppModel()
        model.bootstrap()
        let recents = model.projects.filter(\.isRecent).prefix(3)
        let states: [ClaudeState] = [.working, .waiting, .idle]
        model.windows = recents.enumerated().map { i, p in
            OpenWindow(id: p.path, path: p.path, name: p.name,
                       lastUsed: Date(timeIntervalSinceNow: Double(i * i) * -600), focused: i == 0,
                       pinned: false, claude: states[i], socket: "")
        }
        if model.windows.count > 1 { model.selection = .window(model.windows[1].id) }
        if let q = ProcessInfo.processInfo.environment["SWIDE_QUERY"] { model.query = q }

        let host = NSHostingView(rootView: PanelView(model: model)
            .background(Color(white: 0.13))
            .environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
