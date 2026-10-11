import AppKit
import SwideCore

let arguments = CommandLine.arguments

// Called by Claude Code hooks: must be fast and never fail the hook.
if arguments.contains("--claude-hook") {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    try? ClaudeHook.handle(input: input)
    exit(0)
}

MainActor.assumeIsolated {
    if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
        Snapshot.render(to: arguments[i + 1])
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
