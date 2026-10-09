import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut as a physical key code plus Carbon modifier flags,
/// the form `RegisterEventHotKey` expects.
public struct HotKeyShortcut: Codable, Equatable {
    public static let defaultShortcut = HotKeyShortcut(keyCode: kVK_ANSI_C, carbonModifiers: cmdKey | optionKey)

    public let keyCode: Int
    public let carbonModifiers: Int

    public init(keyCode: Int, carbonModifiers: Int) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Builds a shortcut from a key press. Returns `nil` unless it uses ⌘, ⌃ or ⌥
    /// (or is a function key), since a bare letter would hijack normal typing.
    public init?(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags.intersection([.command, .control, .option, .shift])
        guard !flags.intersection([.command, .control, .option]).isEmpty || Self.functionKeys[keyCode] != nil else { return nil }
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        self.init(keyCode: keyCode, carbonModifiers: carbon)
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & cmdKey != 0 { flags.insert(.command) }
        if carbonModifiers & controlKey != 0 { flags.insert(.control) }
        if carbonModifiers & optionKey != 0 { flags.insert(.option) }
        if carbonModifiers & shiftKey != 0 { flags.insert(.shift) }
        return flags
    }

    /// E.g. "⌥⌘C", with modifiers in the standard macOS order.
    public var displayString: String {
        Self.modifierSymbols(modifierFlags) + keyName
    }

    /// Symbols for `flags` in the order macOS menus use: ⌃⌥⇧⌘.
    public static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { flags.contains($0.0) }.map(\.1).joined()
    }

    /// The key's label: a symbol for special keys, otherwise the character the key
    /// produces in the current Latin keyboard layout.
    public var keyName: String {
        if let special = Self.specialKeys[keyCode] { return special.name }
        if let function = Self.functionKeys[keyCode] { return "F\(function)" }
        return Self.character(forKeyCode: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// Value for `NSMenuItem.keyEquivalent`, or `nil` if the key can't be shown in a menu.
    public var menuKeyEquivalent: String? {
        if let special = Self.specialKeys[keyCode] { return special.menuKey }
        if let function = Self.functionKeys[keyCode], let scalar = UnicodeScalar(NSF1FunctionKey + function - 1) {
            return String(Character(scalar))
        }
        return Self.character(forKeyCode: keyCode)?.lowercased()
    }

    // MARK: - Key tables

    private static let specialKeys: [Int: (name: String, menuKey: String?)] = [
        kVK_Return: ("↩", "\r"), kVK_ANSI_KeypadEnter: ("⌅", "\u{3}"), kVK_Tab: ("⇥", "\t"),
        kVK_Space: ("Space", " "), kVK_Delete: ("⌫", "\u{8}"), kVK_ForwardDelete: ("⌦", "\u{7f}"),
        kVK_Escape: ("⎋", "\u{1b}"),
        kVK_LeftArrow: ("←", String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))),
        kVK_RightArrow: ("→", String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))),
        kVK_UpArrow: ("↑", String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))),
        kVK_DownArrow: ("↓", String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))),
        kVK_Home: ("↖", nil), kVK_End: ("↘", nil), kVK_PageUp: ("⇞", nil), kVK_PageDown: ("⇟", nil),
    ]

    private static let functionKeys: [Int: Int] = [
        kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6, kVK_F7: 7, kVK_F8: 8,
        kVK_F9: 9, kVK_F10: 10, kVK_F11: 11, kVK_F12: 12, kVK_F13: 13, kVK_F14: 14, kVK_F15: 15,
        kVK_F16: 16, kVK_F17: 17, kVK_F18: 18, kVK_F19: 19, kVK_F20: 20,
    ]

    /// Translates a key code through the current ASCII-capable layout, so a Cyrillic
    /// layout still shows "C" for the key that types "C" in English.
    private static func character(forKeyCode keyCode: Int) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length)
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
    }
}
