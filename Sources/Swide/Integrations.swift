import Foundation
import SwideCore

/// One-time setup of the IDE bridge extension and the Claude Code hooks.
enum Integrations {
    static let bridgeID = "swide.swide-bridge"
    static var claudeSettings: URL { Paths.home.appendingPathComponent(".claude/settings.json") }

    static func bridgeInstalled(in ide: IDE) -> Bool {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: ide.extensionsDir.path)) ?? []
        return items.contains { $0.hasPrefix(bridgeID + "-") }
    }

    static var hooksInstalled: Bool {
        guard let text = try? String(contentsOf: claudeSettings, encoding: .utf8) else { return false }
        return text.contains(hookCommand)
    }

    static var hookCommand: String {
        "\"\(Bundle.main.executablePath ?? "Swide")\" --claude-hook"
    }

    static func installBridge(in ide: IDE) throws {
        guard let cli = ide.cli else {
            throw SetupError("\(ide.displayName) est introuvable.")
        }
        guard let vsix = Bundle.main.url(forResource: "swide-bridge", withExtension: "vsix") else {
            throw SetupError("swide-bridge.vsix est absent du bundle. Lance scripts/build.sh.")
        }
        let process = Process()
        process.executableURL = cli
        process.arguments = ["--install-extension", vsix.path, "--force"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SetupError("Échec de l'installation de l'extension : \(output)")
        }
    }

    /// Adds Swide's hook to each event, replacing older Swide entries and keeping everything else.
    static func installClaudeHooks() throws {
        let fm = FileManager.default
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: claudeSettings) {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SetupError("~/.claude/settings.json n'est pas un objet JSON.")
            }
            root = parsed
            let backup = claudeSettings.appendingPathExtension("swide-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: claudeSettings, to: backup)
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in ClaudeHook.events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.removeAll { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).contains {
                    ($0["command"] as? String)?.contains("--claude-hook") == true
                }
            }
            var entry: [String: Any] = ["hooks": [["type": "command", "command": hookCommand, "timeout": 5]]]
            if event == "PreToolUse" || event == "PostToolUse" { entry["matcher"] = "*" }
            entries.append(entry)
            hooks[event] = entries
        }
        root["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.writeAtomically(to: claudeSettings)
    }

    struct SetupError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
