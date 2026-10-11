import Foundation

/// One Cursor window, as reported by the swide-bridge extension.
public struct BridgeWindow: Codable, Equatable, Sendable {
    public let id: String
    public let pid: Int32
    public let folders: [String]
    public let focused: Bool
    /// Epoch milliseconds of the last focus change (gained or lost); 0 if unknown.
    public let lastFocus: Double
    public let socket: String

    public init(id: String, pid: Int32, folders: [String], focused: Bool, lastFocus: Double, socket: String) {
        self.id = id
        self.pid = pid
        self.folders = folders
        self.focused = focused
        self.lastFocus = lastFocus
        self.socket = socket
    }
}

public enum BridgeRegistry {
    /// Live windows only; files left by dead extension hosts are removed.
    public static func load(dir: URL = Paths.windowsDir, isAlive: (Int32) -> Bool = processIsAlive) -> [BridgeWindow] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var out: [BridgeWindow] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let w = try? JSONDecoder().decode(BridgeWindow.self, from: data) else { continue }
            if isAlive(w.pid) {
                out.append(w)
            } else {
                try? fm.removeItem(at: file)
            }
        }
        return out
    }

    public static func processIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

public struct WindowSnapshot: Equatable, Sendable {
    public let id: String
    public let isProtected: Bool
    public init(id: String, isProtected: Bool) {
        self.id = id
        self.isProtected = isProtected
    }
}

public enum EvictionDecision: Equatable, Sendable {
    case room
    case close(String)
    case allProtected
}

public enum Eviction {
    /// `mru` is ordered most recently used first. Closes at most one window.
    public static func decide(mru: [WindowSnapshot], max: Int) -> EvictionDecision {
        guard mru.count >= max else { return .room }
        if let victim = mru.last(where: { !$0.isProtected }) { return .close(victim.id) }
        return .allProtected
    }
}

public enum WindowTitle {
    private static let separators = [" — ", " – ", " - "]

    /// Cursor titles look like "file.py — project — Cursor". Matches a whole segment.
    public static func matches(_ title: String, name: String) -> Bool {
        var parts = [title]
        for sep in separators {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        return parts.contains { segment in
            let s = segment.trimmingCharacters(in: .whitespaces)
            return s == name || s == "● \(name)" || s.hasPrefix("\(name) [")
        }
    }
}
