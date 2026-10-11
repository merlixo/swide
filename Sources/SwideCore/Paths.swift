import Foundation

public enum Paths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Shared with the Cursor bridge extension and the Claude Code hook.
    public static var support: URL { home.appendingPathComponent("Library/Application Support/Swide") }
    public static var windowsDir: URL { support.appendingPathComponent("windows") }
    public static var claudeDir: URL { support.appendingPathComponent("claude") }
    public static var stateFile: URL { support.appendingPathComponent("state.json") }

    public static var configFile: URL { home.appendingPathComponent(".config/swide/config.json") }

    public static var cursorStateDB: String {
        home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
    }

    public static func expand(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL.path
    }

    public static func ensure(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

extension Data {
    /// Write via a temp file so readers never see a partial file.
    public func writeAtomically(to url: URL) throws {
        Paths.ensure(url.deletingLastPathComponent())
        try write(to: url, options: .atomic)
    }
}
