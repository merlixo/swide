import Foundation
import SQLite3

public struct Project: Hashable, Identifiable, Sendable {
    public let path: String
    public let name: String
    /// Folder the project lives in, relative to the search root ("work", "work/labs").
    public let group: String
    /// Position in Cursor's recent list; nil if never opened in Cursor.
    public let recentRank: Int?

    public var id: String { path }
    public var isRecent: Bool { recentRank != nil }

    public init(path: String, name: String, group: String, recentRank: Int?) {
        self.path = path
        self.name = name
        self.group = group
        self.recentRank = recentRank
    }
}

public struct ProjectHit: Identifiable, Equatable, Sendable {
    public let project: Project
    public let indices: [Int]
    public var id: String { project.path }
}

public enum ProjectScanner {
    private static let skipped: Set<String> = ["node_modules", ".venv", "venv", "target", "build", "dist", "__pycache__"]

    /// A project is: a direct child of a group folder (`root/work/x`), a top-level
    /// folder that is a git repo or has no subfolders (`root/sandbox`), or any git
    /// repo nested up to 4 levels deep (`root/work/labs/x`).
    public static func scan(root: String) -> [String] {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root)

        func subdirs(_ url: URL) -> [URL] {
            let items = (try? fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            return items
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .filter { !skipped.contains($0.lastPathComponent) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        func isRepo(_ url: URL) -> Bool { fm.fileExists(atPath: url.appendingPathComponent(".git").path) }

        var out: [String] = []
        for d1 in subdirs(rootURL) {
            let children = subdirs(d1)
            if isRepo(d1) || children.isEmpty {
                out.append(d1.path)
                continue
            }
            for d2 in children {
                out.append(d2.path)
                if isRepo(d2) { continue }
                for d3 in subdirs(d2) {
                    if isRepo(d3) { out.append(d3.path); continue }
                    for d4 in subdirs(d3) where isRepo(d4) { out.append(d4.path) }
                }
            }
        }
        return out.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }
}

public enum RecentFolders {
    /// Folder paths from the IDE's "recently opened" list, most recent first.
    public static func load(dbPath: String) -> [String] {
        if let paths = read(dbPath, flags: SQLITE_OPEN_READONLY) { return paths }
        // The DB is in WAL mode: once the IDE has quit, its -wal/-shm files are gone and a
        // read-only connection can't recreate them. Nothing writes then, so immutable is safe.
        let uri = URL(fileURLWithPath: dbPath).absoluteString + "?immutable=1"
        return read(uri, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI) ?? []
    }

    /// nil when the database can't be read.
    private static func read(_ path: String, flags: Int32) -> [String]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        switch sqlite3_step(stmt) {
        case SQLITE_ROW:
            guard let bytes = sqlite3_column_blob(stmt, 0) else { return [] }
            return parse(Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
        case SQLITE_DONE:
            return []
        default:
            return nil
        }
    }

    public static func parse(_ data: Data) -> [String] {
        struct List: Decodable {
            struct Entry: Decodable { let folderUri: String? }
            let entries: [Entry]
        }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else { return [] }
        return list.entries
            .compactMap { $0.folderUri.flatMap(URL.init(string:)) }
            .filter(\.isFileURL)
            .map { $0.standardizedFileURL.path }
    }
}

public enum ProjectCatalog {
    public static func build(
        recents: [String], scanned: [String], root: String,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [Project] {
        var seen = Set<String>()
        var out: [Project] = []
        for (rank, path) in recents.enumerated() where exists(path) && seen.insert(path).inserted {
            out.append(make(path, root: root, rank: rank))
        }
        for path in scanned where seen.insert(path).inserted {
            out.append(make(path, root: root, rank: nil))
        }
        return out
    }

    static func make(_ path: String, root: String, rank: Int?) -> Project {
        let url = URL(fileURLWithPath: path)
        return Project(path: path, name: url.lastPathComponent, group: group(of: path, root: root), recentRank: rank)
    }

    public static func group(of path: String, root: String) -> String {
        let rootURL = URL(fileURLWithPath: root)
        if path.hasPrefix(root + "/") {
            let parents = path.dropFirst(root.count + 1).split(separator: "/").dropLast()
            return parents.isEmpty ? rootURL.lastPathComponent : parents.joined(separator: "/")
        }
        return URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
    }

    /// Without a query: recent projects that aren't open. With a query: every project.
    public static func search(_ projects: [Project], query: String, excluding open: Set<String>, limit: Int = 8) -> [ProjectHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return projects
                .filter { $0.isRecent && !open.contains($0.path) }
                .sorted { ($0.recentRank ?? .max) < ($1.recentRank ?? .max) }
                .prefix(limit)
                .map { ProjectHit(project: $0, indices: []) }
        }

        var scored: [(hit: ProjectHit, score: Double)] = []
        for p in projects {
            var score: Double
            var indices: [Int] = []
            if let m = Fuzzy.match(p.name, q) {
                score = m.score
                indices = m.indices
            } else if let m = Fuzzy.match(p.group + "/" + p.name, q) {
                score = m.score - 3
            } else {
                continue
            }
            // Recent projects win ties, the most recent slightly more.
            if let rank = p.recentRank { score += 2 + max(0, 1 - Double(rank) / 20) }
            scored.append((ProjectHit(project: p, indices: indices), score))
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.hit.project.name < $1.hit.project.name }
            .prefix(limit)
            .map(\.hit)
    }
}
