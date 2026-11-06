import AppKit
import ApplicationServices
import SwideCore

extension IDE {
    var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }
    var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }
    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var isInstalled: Bool { appURL != nil }
    var cli: URL? { appURL?.appendingPathComponent(cliPath) }
}

/// Opens or focuses a project in the IDE, then maximizes its window on the target screen.
@MainActor
final class WindowMover {
    func focus(path: String, name: String, ide: IDE, on screen: NSScreen?) async {
        guard let appURL = ide.appURL else {
            NSLog("Swide: \(ide.displayName) not found")
            return
        }
        let coldStart = ide.running == nil
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        do {
            _ = try await NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appURL, configuration: config)
        } catch {
            NSLog("Swide: open failed: \(error)")
            return
        }
        guard let screen else { return }
        guard AXIsProcessTrusted() else {
            NSLog("Swide: no Accessibility permission, window not placed")
            Accessibility.promptOnce()
            return
        }

        // New windows, and above all a cold start that restores the previous session, take a while.
        let deadline = Date().addingTimeInterval(coldStart ? 40 : 15)
        var bridgeConfirmations = 0
        while Date() < deadline {
            if let pid = ide.running?.processIdentifier, let window = AX.focusedWindow(pid: pid) {
                if AX.window(window, matches: path, name: name) {
                    await place(window, ide: ide, on: screen)
                    return
                }
                // Title not recognizable: trust the bridge once it has reported focus for a few polls.
                let bridgeFocused = BridgeRegistry.load().contains { ide.owns($0) && $0.focused && $0.folders.contains(path) }
                bridgeConfirmations = bridgeFocused ? bridgeConfirmations + 1 : 0
                if bridgeConfirmations >= 4 {
                    await place(window, ide: ide, on: screen)
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        NSLog("Swide: window for \(name) not found in time")
    }

    private func place(_ window: AXUIElement, ide: IDE, on screen: NSScreen) async {
        if AX.bool(window, "AXFullScreen") == true {
            AX.set(window, "AXFullScreen", kCFBooleanFalse)
            try? await Task.sleep(for: .milliseconds(900))
        }
        let target = AX.topLeftFrame(screen.visibleFrame)
        AX.move(window, to: target)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        ide.running?.activate()

        // Activation switches to the Space the window came from, on its old screen, and that
        // can undo a move across screens: re-apply until the window stays on the target screen.
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(100))
            guard let frame = AX.frame(window) else { return }
            if AX.isPlaced(frame, at: target) { return }
            AX.move(window, to: target)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        NSLog("Swide: could not keep the window on the target screen")
    }
}

/// The system Accessibility prompt, shown only when it is really needed.
@MainActor
enum Accessibility {
    private static var promptedThisLaunch = false

    /// Shows the system prompt unless already trusted. Returns whether trusted.
    @discardableResult
    static func prompt() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// First launch only. Later launches don't check: at login, the permission can briefly
    /// read as missing while it is granted, which showed a needless prompt.
    static func promptOnFirstLaunch() {
        let key = "accessibilityPromptShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if !AXIsProcessTrusted() { promptOnce() }
    }

    /// When a window can't be placed for lack of permission; at most once per launch.
    static func promptOnce() {
        guard !promptedThisLaunch else { return }
        promptedThisLaunch = true
        prompt()
    }
}

enum AX {
    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func copy(_ el: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        element(copy(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute))
    }

    static func string(_ el: AXUIElement, _ attribute: String) -> String? { copy(el, attribute) as? String }
    static func bool(_ el: AXUIElement, _ attribute: String) -> Bool? { copy(el, attribute) as? Bool }

    @discardableResult
    static func set(_ el: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(el, attribute as CFString, value) == .success
    }

    static func window(_ window: AXUIElement, matches path: String, name: String) -> Bool {
        // AXDocument is the active editor's file URL, when one is open.
        if let doc = string(window, kAXDocumentAttribute), let url = URL(string: doc), url.path.hasPrefix(path + "/") {
            return true
        }
        if let title = string(window, kAXTitleAttribute) {
            return WindowTitle.matches(title, name: name)
        }
        return false
    }

    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = copy(window, kAXPositionAttribute), let s = copy(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) { set(window, kAXPositionAttribute, v) }
    }

    static func setSize(_ window: AXUIElement, _ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { set(window, kAXSizeAttribute, v) }
    }

    static func move(_ window: AXUIElement, to target: CGRect) {
        guard frame(window) != target else { return }
        // Position, size, position again: crossing screens can clamp the first move.
        setPosition(window, target.origin)
        setSize(window, target.size)
        setPosition(window, target.origin)
    }

    /// Same origin, give or take rounding. Size isn't checked: an app may enforce its own limits.
    static func isPlaced(_ frame: CGRect, at target: CGRect) -> Bool {
        abs(frame.minX - target.minX) <= 2 && abs(frame.minY - target.minY) <= 2
    }

    /// AppKit uses a bottom-left origin; Accessibility uses the primary screen's top-left.
    static func topLeftFrame(_ rect: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Talks to the swide-bridge extension over its Unix socket.
enum BridgeClient {
    @discardableResult
    static func send(_ command: String, socket path: String) -> Bool {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return false }
        let line = Array((command + "\n").utf8)
        return Darwin.write(fd, line, line.count) == line.count
    }
}
