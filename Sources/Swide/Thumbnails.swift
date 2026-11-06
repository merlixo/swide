import AppKit
import ScreenCaptureKit
import SwideCore

/// Window previews. Optional: needs the Screen Recording permission, and only
/// captures windows visible on a current desktop; others keep their last capture.
enum Thumbnails {
    static var enabled: Bool { CGPreflightScreenCaptureAccess() }

    static func capture(_ targets: [(path: String, name: String)], ide: IDE) async -> [String: NSImage] {
        guard enabled, !targets.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        else { return [:] }

        var images: [String: NSImage] = [:]
        for window in content.windows
        where window.owningApplication?.bundleIdentifier == ide.bundleID && window.frame.width > 400 {
            guard let title = window.title,
                  let target = targets.first(where: { WindowTitle.matches(title, name: $0.name) }),
                  images[target.path] == nil else { continue }

            let config = SCStreamConfiguration()
            let scale = 720 / window.frame.width
            config.width = 720
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                images[target.path] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }
        return images
    }
}
