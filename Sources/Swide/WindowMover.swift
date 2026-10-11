import AppKit
import ApplicationServices
import SwideCore

enum Cursor {
    static let bundleID = "com.todesktop.230313mzl4w4u92"
    static let cli = "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"

    static var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }
    static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }
}

/// Opens or focuses a project in Cursor, then maximizes its window on the target screen.
@MainActor
final class WindowMover {
    func focus(path: String, name: String, on screen: NSScreen?) async {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Cursor.bundleID) else {
            NSLog("Swide: Cursor not found")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        do {
            _ = try await NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appURL, configuration: config)
        } catch {
            NSLog("Swide: open failed: \(error)")
            return
        }
        guard AXIsProcessTrusted(), let screen else { return }

        // New windows (or a cold Cursor start) can take a while to appear.
        let deadline = Date().addingTimeInterval(15)
        var bridgeConfirmations = 0
        while Date() < deadline {
            if let pid = Cursor.running?.processIdentifier, let window = AX.focusedWindow(pid: pid) {
                if AX.window(window, matches: path, name: name) {
                    await place(window, on: screen)
                    return
                }
                // Title not recognizable: trust the bridge once it has reported focus for a few polls.
                let bridgeFocused = BridgeRegistry.load().contains { $0.focused && $0.folders.contains(path) }
                bridgeConfirmations = bridgeFocused ? bridgeConfirmations + 1 : 0
                if bridgeConfirmations >= 4 {
                    await place(window, on: screen)
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        NSLog("Swide: window for \(name) not found in time")
    }

    private func place(_ window: AXUIElement, on screen: NSScreen) async {
        if AX.bool(window, "AXFullScreen") == true {
            AX.set(window, "AXFullScreen", kCFBooleanFalse)
            try? await Task.sleep(for: .milliseconds(900))
        }
        let target = AX.topLeftFrame(screen.visibleFrame)
        if AX.frame(window) != target {
            // Position, size, position again: crossing screens can clamp the first move.
            AX.setPosition(window, target.origin)
            AX.setSize(window, target.size)
            AX.setPosition(window, target.origin)
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        Cursor.running?.activate()
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
