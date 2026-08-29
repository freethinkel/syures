import Carbon.HIToolbox

/// A system-wide hotkey. Uses Carbon, which — unlike an `NSEvent` global monitor —
/// needs no Accessibility permission.
final class HotKey {
    struct Combo {
        let keyCode: UInt32
        let modifiers: UInt32

        init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        static let optionSpace = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

        /// Parses `"cmd+shift+k"`, `"opt+space"`. Returns nil if no key name is recognised.
        init?(_ text: String) {
            var modifiers: UInt32 = 0
            var keyCode: UInt32?

            for part in text.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                switch part {
                case "cmd", "command": modifiers |= UInt32(cmdKey)
                case "opt", "option", "alt": modifiers |= UInt32(optionKey)
                case "ctrl", "control": modifiers |= UInt32(controlKey)
                case "shift": modifiers |= UInt32(shiftKey)
                default: keyCode = Combo.keyCodes[part]
                }
            }

            guard let keyCode else { return nil }
            self.init(keyCode: keyCode, modifiers: modifiers)
        }

        private static let keyCodes: [String: UInt32] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
            "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
            "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
            "return": 36, "tab": 48, "space": 49, "escape": 53,
        ]
    }

    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private var ref: EventHotKeyRef?

    init(_ combo: Combo, action: @escaping () -> Void) {
        Self.installHandler()
        id = Self.nextID
        Self.nextID += 1
        Self.actions[id] = action
        RegisterEventHotKey(combo.keyCode, combo.modifiers,
                            EventHotKeyID(signature: OSType(0x5359_5552), id: id),
                            GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.actions[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKey.actions[id.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
