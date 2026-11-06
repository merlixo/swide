import Foundation
import SQLite3
import Testing
@testable import SwideCore

@Suite struct FuzzyTests {
    @Test func substringBeatsScatteredMatch() throws {
        let m = try #require(Fuzzy.match("api-service", "serv"))
        #expect(m.indices == [4, 5, 6, 7])
    }

    @Test func subsequenceMatches() throws {
        let m = try #require(Fuzzy.match("web-dashboard-api", "wda"))
        #expect(m.indices == [0, 4, 5])
    }

    @Test func noMatch() {
        #expect(Fuzzy.match("swide", "xyz") == nil)
    }

    @Test func monogramUsesWordStarts() {
        #expect(monogram("api-service") == "AS")
        #expect(monogram("swide") == "SW")
    }
}

@Suite struct ProjectTests {
    func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swide-\(UUID().uuidString)")
        let dirs = [
            "work/api-service/.git", "work/api-service/src",
            "work/no-git-project/src",
            "work/labs/cli-x/.git",
            "perso/swide/.git",
            "sandbox/.git",
            "loose",
            "work/api-service/node_modules/pkg/.git",
        ]
        for d in dirs {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        return root
    }

    @Test func scanFindsProjectsAtAllLevels() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.standardizedFileURL.path
        let found = Set(ProjectScanner.scan(root: base).map { String($0.dropFirst(base.count + 1)) })
        #expect(found == ["loose", "sandbox", "perso/swide", "work/api-service", "work/no-git-project",
                          "work/labs", "work/labs/cli-x"])
    }

    @Test func parsesCursorRecents() {
        let json = #"{"entries":[{"folderUri":"file:///Users/me/dev/work/a%20b"},{"fileUri":"file:///x.txt"},{"folderUri":"vscode-remote://ssh/x"}]}"#
        #expect(RecentFolders.parse(Data(json.utf8)) == ["/Users/me/dev/work/a b"])
    }

    /// Regression: with the IDE closed, its WAL database has no -wal/-shm and a plain
    /// read-only open fails, which emptied the panel at login.
    @Test func readsRecentsWhileIDEIsClosed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swide-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("state.vscdb").path

        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        let json = #"{"entries":[{"folderUri":"file:///d/dev/a"}]}"#
        let sql = "PRAGMA journal_mode=wal; CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);"
            + "INSERT INTO ItemTable VALUES ('history.recentlyOpenedPathsList', '\(json)');"
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }

        #expect(RecentFolders.load(dbPath: path) == ["/d/dev/a"])
    }

    @Test func missingDatabaseGivesNoRecents() {
        #expect(RecentFolders.load(dbPath: "/nonexistent/state.vscdb").isEmpty)
    }

    @Test func groups() {
        #expect(ProjectCatalog.group(of: "/d/dev/work/x", root: "/d/dev") == "work")
        #expect(ProjectCatalog.group(of: "/d/dev/work/labs/x", root: "/d/dev") == "work/labs")
        #expect(ProjectCatalog.group(of: "/d/dev/sandbox", root: "/d/dev") == "dev")
        #expect(ProjectCatalog.group(of: "/elsewhere/proj", root: "/d/dev") == "elsewhere")
    }

    @Test func catalogDedupesAndDropsMissingRecents() {
        let projects = ProjectCatalog.build(
            recents: ["/d/dev/a/one", "/d/dev/a/gone"], scanned: ["/d/dev/a/one", "/d/dev/a/two"],
            root: "/d/dev", exists: { $0 != "/d/dev/a/gone" })
        #expect(projects.map(\.name) == ["one", "two"])
        #expect(projects[0].recentRank == 0)
        #expect(projects[1].recentRank == nil)
    }

    @Test func emptyQueryShowsRecentNonOpenOnly() {
        let projects = ProjectCatalog.build(
            recents: ["/r/a/one", "/r/a/two"], scanned: ["/r/a/three"], root: "/r", exists: { _ in true })
        let hits = ProjectCatalog.search(projects, query: "", excluding: ["/r/a/one"])
        #expect(hits.map(\.project.name) == ["two"])
    }

    @Test func searchCoversAllAndPrefersRecent() {
        let projects = ProjectCatalog.build(
            recents: ["/r/a/data-x"], scanned: ["/r/b/data-y"], root: "/r", exists: { _ in true })
        let hits = ProjectCatalog.search(projects, query: "data", excluding: ["/r/a/data-x"])
        #expect(hits.map(\.project.name) == ["data-x", "data-y"])
    }
}

@Suite struct EvictionTests {
    func w(_ id: String, _ p: Bool = false) -> WindowSnapshot { WindowSnapshot(id: id, isProtected: p) }

    @Test func roomBelowMax() {
        #expect(Eviction.decide(mru: [w("a"), w("b")], max: 3) == .room)
    }

    @Test func closesLeastRecent() {
        #expect(Eviction.decide(mru: [w("a"), w("b"), w("c")], max: 3) == .close("c"))
    }

    @Test func skipsProtected() {
        #expect(Eviction.decide(mru: [w("a"), w("b"), w("c", true)], max: 3) == .close("b"))
    }

    @Test func allProtected() {
        #expect(Eviction.decide(mru: [w("a", true), w("b", true), w("c", true)], max: 3) == .allProtected)
    }

    @Test func closesOnlyOneWhenOverLimit() {
        #expect(Eviction.decide(mru: [w("a"), w("b"), w("c"), w("d"), w("e")], max: 3) == .close("e"))
    }
}

@Suite struct WindowTitleTests {
    @Test func matchesSegments() {
        #expect(WindowTitle.matches("models.sql — web-dashboard — Cursor", name: "web-dashboard"))
        #expect(WindowTitle.matches("web-dashboard", name: "web-dashboard"))
        #expect(WindowTitle.matches("● main.py - swide - Cursor", name: "swide"))
        #expect(!WindowTitle.matches("models.sql — web-dashboard — Cursor", name: "web"))
    }
}

@Suite struct ClaudeTests {
    @Test func hookWritesAndRemovesSessions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swide-claude-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        func send(_ event: String) throws {
            let json = #"{"session_id":"abc-1","cwd":"/d/proj/sub","hook_event_name":"\#(event)"}"#
            try ClaudeHook.handle(input: Data(json.utf8), dir: dir)
        }
        try send("UserPromptSubmit")
        #expect(ClaudeSessions.state(for: "/d/proj", in: ClaudeSessions.load(dir: dir)) == .working)
        try send("Notification")
        #expect(ClaudeSessions.state(for: "/d/proj", in: ClaudeSessions.load(dir: dir)) == .waiting)
        try send("Stop")
        #expect(ClaudeSessions.state(for: "/d/proj", in: ClaudeSessions.load(dir: dir)) == .idle)
        try send("SessionEnd")
        #expect(ClaudeSessions.load(dir: dir).isEmpty)
    }

    @Test func staleWorkingBecomesIdle() {
        let old = ClaudeSession(sessionId: "x", cwd: "/p", state: .working, updatedAt: Date(timeIntervalSinceNow: -3600))
        #expect(ClaudeSessions.state(for: "/p", in: [old]) == .idle)
    }

    @Test func ignoresSiblingFolders() {
        let s = ClaudeSession(sessionId: "x", cwd: "/d/proj-other", state: .working, updatedAt: Date())
        #expect(ClaudeSessions.state(for: "/d/proj", in: [s]) == .idle)
    }

    @Test func strongestStateWins() {
        let a = ClaudeSession(sessionId: "a", cwd: "/p", state: .waiting, updatedAt: Date())
        let b = ClaudeSession(sessionId: "b", cwd: "/p", state: .working, updatedAt: Date())
        #expect(ClaudeSessions.state(for: "/p", in: [a, b]) == .working)
    }
}

@Suite struct ConfigTests {
    @Test func partialConfigKeepsDefaults() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"maxWindows":4,"protect":{"pinned":false}}"#.utf8))
        #expect(c.maxWindows == 4)
        #expect(c.hotkey == "option+space")
        #expect(c.ide == .cursor)
        #expect(c.autoOpenDelay == 0.8)
        #expect(c.protect.pinned == false)
        #expect(c.protect.claudeWorking == true)
    }

    @Test func ideAndDelay() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"ide":"vscode","autoOpenDelay":0}"#.utf8))
        #expect(c.ide == .vscode)
        #expect(c.autoOpenDelay == 0)
    }

    @Test func unknownIDEFallsBackToDefault() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"ide":"zed","maxWindows":2}"#.utf8))
        #expect(c.ide == .cursor)
        #expect(c.maxWindows == 2)
    }

    @Test func saveRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swide-config-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var c = Config()
        c.ide = .vscode
        c.save(to: url)
        #expect(Config.load(from: url) == c)
    }
}

@Suite struct IDETests {
    func window(app: String?) -> BridgeWindow {
        BridgeWindow(id: "x", pid: 1, folders: ["/p"], focused: false, lastFocus: 0, socket: "", app: app)
    }

    @Test func windowsBelongToTheirIDE() {
        #expect(IDE.cursor.owns(window(app: "Cursor")))
        #expect(!IDE.cursor.owns(window(app: "Visual Studio Code")))
        #expect(IDE.vscode.owns(window(app: "Visual Studio Code")))
        #expect(!IDE.vscode.owns(window(app: "Cursor")))
    }

    @Test func oldBridgesAreCursor() throws {
        let json = #"{"id":"a","pid":1,"folders":[],"focused":false,"lastFocus":0,"socket":"s"}"#
        let w = try JSONDecoder().decode(BridgeWindow.self, from: Data(json.utf8))
        #expect(IDE.cursor.owns(w))
        #expect(!IDE.vscode.owns(w))
    }
}
