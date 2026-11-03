import AppKit
import ServiceManagement
import SwideCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private var panel: PanelController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PanelController(model: model)
        model.panel = panel
        model.bootstrap()
        registerHotKey()
        setupStatusItem()
        enableLaunchAtLoginOnce()

        if !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    /// Turns on launch at login the first time only, so a later opt-out from the menu sticks.
    private func enableLaunchAtLoginOnce() {
        let key = "launchAtLoginConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            UserDefaults.standard.set(true, forKey: key)
            NSLog("Swide: launch at login enabled")
        } catch {
            NSLog("Swide: launch at login failed: \(error)")
        }
    }

    private func registerHotKey() {
        hotKey = HotKey(spec: model.config.hotkey) { [weak self] in self?.toggle() }
        if hotKey?.registered != true {
            alert("Raccourci indisponible",
                  "« \(model.config.hotkey) » est invalide ou déjà utilisé. Modifie « hotkey » dans \(Paths.configFile.path) puis relance Swide.")
        }
    }

    func toggle() {
        if panel.isVisible {
            panel.hide()
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        model.prepareForShow(screen: screen)
        panel.show(on: screen)
        model.didShow()
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Swide")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Ouvrir Swide", #selector(menuToggle)))
        menu.addItem(.separator())

        let setup = NSMenuItem(title: "Configuration", action: nil, keyEquivalent: "")
        setup.isEnabled = false
        menu.addItem(setup)
        menu.addItem(item("Accessibilité (obligatoire)", #selector(openAccessibility), done: AXIsProcessTrusted()))
        menu.addItem(item("Extension Cursor swide-bridge", #selector(installBridge), done: Integrations.bridgeInstalled))
        menu.addItem(item("Hooks Claude Code", #selector(installHooks), done: Integrations.hooksInstalled))
        menu.addItem(item("Aperçus des fenêtres (Enregistrement de l'écran)", #selector(enableThumbnails), done: Thumbnails.enabled))
        menu.addItem(.separator())

        menu.addItem(item("Lancer à la connexion", #selector(toggleLoginItem), done: SMAppService.mainApp.status == .enabled))
        menu.addItem(item("Ouvrir la configuration…", #selector(openConfig)))
        menu.addItem(.separator())
        menu.addItem(item("Quitter Swide", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, done: Bool? = nil, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let done { item.state = done ? .on : .off }
        return item
    }

    @objc private func menuToggle() { toggle() }

    @objc private func openAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    @objc private func installBridge() {
        Task.detached {
            do {
                try Integrations.installBridge()
                await self.alert("Extension installée",
                                 "Les fenêtres Cursor déjà ouvertes apparaîtront dans Swide après quelques secondes. Si ce n'est pas le cas, recharge-les (Developer: Reload Window).")
            } catch {
                await self.alert("Échec de l'installation", error.localizedDescription)
            }
        }
    }

    @objc private func installHooks() {
        do {
            try Integrations.installClaudeHooks()
            alert("Hooks Claude Code installés",
                  "Ajoutés à ~/.claude/settings.json (sauvegarde : settings.json.swide-backup). Ils s'appliquent aux nouvelles sessions Claude.")
        } catch {
            alert("Échec de l'installation des hooks", error.localizedDescription)
        }
    }

    @objc private func enableThumbnails() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Lancement à la connexion", error.localizedDescription)
        }
    }

    @objc private func openConfig() {
        _ = Config.load()
        NSWorkspace.shared.open(Paths.configFile)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
