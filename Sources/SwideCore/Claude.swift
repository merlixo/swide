import Foundation

public enum ClaudeState: Int, Codable, Comparable, Sendable {
    case idle, waiting, working

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct ClaudeSession: Codable, Equatable, Sendable {
    public let sessionId: String
    public let cwd: String
    public let state: ClaudeState
    public let updatedAt: Date
}

/// Handles `Swide --claude-hook`, called by Claude Code hooks with the event JSON on stdin.
public enum ClaudeHook {
    public static let events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "Notification", "SessionEnd"]

    enum Action: Equatable { case set(ClaudeState), remove, ignore }

    static func action(for event: String) -> Action {
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": return .set(.working)
        case "Notification": return .set(.waiting)
        case "Stop": return .set(.idle)
        case "SessionEnd": return .remove
        default: return .ignore
        }
    }

    public static func handle(input: Data, dir: URL = Paths.claudeDir, now: Date = Date()) throws {
        struct Payload: Decodable {
            let session_id: String
            let cwd: String
            let hook_event_name: String
        }
        let p = try JSONDecoder().decode(Payload.self, from: input)
        let safeId = p.session_id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !safeId.isEmpty else { return }
        let file = dir.appendingPathComponent("\(safeId).json")

        switch action(for: p.hook_event_name) {
        case .set(let state):
            let session = ClaudeSession(sessionId: p.session_id, cwd: p.cwd, state: state, updatedAt: now)
            try ClaudeSessions.encoder.encode(session).writeAtomically(to: file)
        case .remove:
            try? FileManager.default.removeItem(at: file)
        case .ignore:
            break
        }
    }
}

public enum ClaudeSessions {
    /// A "working" session with no event for this long is considered stuck (crash, kill).
    public static let workingTimeout: TimeInterval = 10 * 60
    static let maxAge: TimeInterval = 24 * 3600

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public static func load(dir: URL = Paths.claudeDir, now: Date = Date()) -> [ClaudeSession] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var out: [ClaudeSession] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let s = try? decoder.decode(ClaudeSession.self, from: data) else { continue }
            if now.timeIntervalSince(s.updatedAt) > maxAge {
                try? fm.removeItem(at: file)
            } else {
                out.append(s)
            }
        }
        return out
    }

    /// Strongest state among sessions running in the project folder or below.
    public static func state(for path: String, in sessions: [ClaudeSession], now: Date = Date()) -> ClaudeState {
        sessions
            .filter { $0.cwd == path || $0.cwd.hasPrefix(path + "/") }
            .map { s -> ClaudeState in
                if s.state == .working && now.timeIntervalSince(s.updatedAt) > workingTimeout { return .idle }
                return s.state
            }
            .max() ?? .idle
    }
}
