import Foundation

/// Supported VS Code–based editors.
public enum IDE: String, Codable, CaseIterable, Sendable {
    case cursor, vscode

    public var displayName: String {
        switch self {
        case .cursor: "Cursor"
        case .vscode: "VS Code"
        }
    }

    public var bundleID: String {
        switch self {
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .vscode: "com.microsoft.VSCode"
        }
    }

    /// `vscode.env.appName`, as reported by the bridge.
    public var appName: String {
        switch self {
        case .cursor: "Cursor"
        case .vscode: "Visual Studio Code"
        }
    }

    /// CLI, relative to the app bundle.
    public var cliPath: String {
        switch self {
        case .cursor: "Contents/Resources/app/bin/cursor"
        case .vscode: "Contents/Resources/app/bin/code"
        }
    }

    private var supportFolder: String {
        switch self {
        case .cursor: "Cursor"
        case .vscode: "Code"
        }
    }

    public var stateDB: String {
        Paths.home.appendingPathComponent("Library/Application Support/\(supportFolder)/User/globalStorage/state.vscdb").path
    }

    public var extensionsDir: URL {
        Paths.home.appendingPathComponent(self == .cursor ? ".cursor/extensions" : ".vscode/extensions")
    }

    /// Bridges before 0.2 didn't report the app; they only ran in Cursor.
    public func owns(_ window: BridgeWindow) -> Bool {
        window.app.map { $0 == appName } ?? (self == .cursor)
    }
}
