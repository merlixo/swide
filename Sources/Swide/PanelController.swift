import AppKit
import SwiftUI

final class SwidePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Floating glass panel. Built once at launch, then only shown and hidden, so it opens instantly.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: SwidePanel
    private let model: AppModel
    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    init(model: AppModel) {
        self.model = model
        panel = SwidePanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.delegate = self

        let glass = NSGlassEffectView()
        glass.cornerRadius = Layout.cornerRadius
        glass.contentView = NSHostingView(rootView: PanelView(model: model))
        panel.contentView = glass

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.model.handleKey(event) ? nil : event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            if self?.panel.isVisible == true { self?.model.mouseArmed = true }
            return event
        }
    }

    var isVisible: Bool { panel.isVisible }

    func show(on screen: NSScreen?) {
        if let frame = (screen ?? NSScreen.main)?.frame {
            // Slightly above center, like Spotlight.
            let origin = NSPoint(
                x: frame.midX - Layout.width / 2,
                y: frame.midY - Layout.height / 2 + frame.height * 0.06)
            panel.setFrame(NSRect(origin: origin, size: NSSize(width: Layout.width, height: Layout.height)), display: false)
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        focusSearch()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func focusSearch() {
        if let field = model.searchField {
            panel.makeFirstResponder(field)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, let field = self.model.searchField else { return }
                self.panel.makeFirstResponder(field)
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
