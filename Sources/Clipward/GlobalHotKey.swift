import Carbon.HIToolbox
import ClipwardCore

/// A system-wide keyboard shortcut registered through Carbon's `RegisterEventHotKey`.
///
/// Carbon hot keys work on every macOS version and, unlike event taps,
/// need no Accessibility permission.
final class GlobalHotKey {
    private static let signature: OSType = 0x434C_5057 // "CLPW"

    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    deinit {
        unregister()
        if let eventHandlerRef = eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    /// Replaces any current registration with `shortcut`.
    /// Returns `false` if the shortcut is already taken by another app.
    @discardableResult
    func register(_ shortcut: HotKeyShortcut) -> Bool {
        unregister()
        guard installEventHandlerIfNeeded() else { return false }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.carbonModifiers), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installEventHandlerIfNeeded() -> Bool {
        guard eventHandlerRef == nil else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context = context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().handler()
            return noErr
        }, 1, &eventType, context, &eventHandlerRef)
        return status == noErr
    }
}

/// Changes and temporarily suspends the "open history" shortcut.
protocol ShortcutRegistering: AnyObject {
    var shortcut: HotKeyShortcut { get }
    /// Registers `shortcut` and saves it. Returns `false` (keeping the old one) if it's unavailable.
    func change(to shortcut: HotKeyShortcut) -> Bool
    /// While suspended the shortcut does nothing, so it can be typed into a shortcut recorder.
    func setSuspended(_ suspended: Bool)
}

/// Keeps the global hot key in sync with the saved setting.
final class HotKeyManager: ShortcutRegistering {
    private let settings: AppSettings
    private let hotKey: GlobalHotKey

    init(settings: AppSettings, onPress: @escaping () -> Void) {
        self.settings = settings
        hotKey = GlobalHotKey(handler: onPress)
    }

    var shortcut: HotKeyShortcut { settings.hotKey }

    /// Registers the saved shortcut. Returns `false` if it's taken.
    func start() -> Bool {
        hotKey.register(settings.hotKey)
    }

    func change(to shortcut: HotKeyShortcut) -> Bool {
        guard hotKey.register(shortcut) else {
            hotKey.register(settings.hotKey)
            return false
        }
        settings.hotKey = shortcut
        return true
    }

    func setSuspended(_ suspended: Bool) {
        if suspended { hotKey.unregister() } else { hotKey.register(settings.hotKey) }
    }
}
