import Carbon
import Foundation

/// Global shortcut through Carbon, which needs no Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var action: (() -> Void)?

    let registered: Bool

    init?(spec: String, action: @escaping () -> Void) {
        guard let (keyCode, modifiers) = HotKey.parse(spec) else { return nil }
        HotKey.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &eventType, nil, &handler)

        let id = EventHotKeyID(signature: OSType(0x5357_4445), id: 1)
        registered = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Parses "option+space", "cmd+shift+k"…
    static func parse(_ spec: String) -> (UInt32, UInt32)? {
        var modifiers: UInt32 = 0
        var key: UInt32?
        for token in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch token {
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case "opt", "option", "alt": modifiers |= UInt32(optionKey)
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            case "shift": modifiers |= UInt32(shiftKey)
            default: key = keyCodes[token]
            }
        }
        guard let key, modifiers != 0 else { return nil }
        return (key, modifiers)
    }

    private static let keyCodes: [String: UInt32] = {
        var map: [String: UInt32] = [
            "space": UInt32(kVK_Space), "return": UInt32(kVK_Return), "tab": UInt32(kVK_Tab),
            "escape": UInt32(kVK_Escape), "`": UInt32(kVK_ANSI_Grave), ";": UInt32(kVK_ANSI_Semicolon),
        ]
        let letters: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D), ("e", kVK_ANSI_E),
            ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I), ("j", kVK_ANSI_J),
            ("k", kVK_ANSI_K), ("l", kVK_ANSI_L), ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O),
            ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X), ("y", kVK_ANSI_Y),
            ("z", kVK_ANSI_Z), ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
            ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8),
            ("9", kVK_ANSI_9),
        ]
        for (name, code) in letters { map[name] = UInt32(code) }
        return map
    }()
}
