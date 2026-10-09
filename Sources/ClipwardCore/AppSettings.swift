import Foundation

/// User preferences, persisted in `UserDefaults`.
/// Every change posts `didChangeNotification` so the app can re-apply them.
public final class AppSettings {
    public static let didChangeNotification = Notification.Name("Clipward.SettingsDidChange")

    public static let defaultIgnoredBundleIDs = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
    ]

    private enum Key {
        static let clearClipboardAfter = "clearClipboardAfter"
        static let maxHistoryItems = "maxHistoryItems"
        static let retention = "retentionSeconds"
        static let persistHistory = "persistHistory"
        static let pasteDirectly = "pasteDirectly"
        static let ignoreConfidential = "ignoreConfidentialContent"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let capturePaused = "capturePaused"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
    }

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    public init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        defaults.register(defaults: [
            Key.clearClipboardAfter: 60.0,
            Key.maxHistoryItems: 200,
            Key.retention: 30.0 * 86_400,
            Key.persistHistory: true,
            Key.pasteDirectly: true,
            Key.ignoreConfidential: true,
            Key.ignoredBundleIDs: Self.defaultIgnoredBundleIDs,
            Key.capturePaused: false,
            Key.hotKeyCode: HotKeyShortcut.defaultShortcut.keyCode,
            Key.hotKeyModifiers: HotKeyShortcut.defaultShortcut.carbonModifiers,
        ])
    }

    /// Seconds an item pasted from the history stays on the clipboard. `0` means forever.
    public var clearClipboardAfter: TimeInterval {
        get { defaults.double(forKey: Key.clearClipboardAfter) }
        set { set(newValue, for: Key.clearClipboardAfter) }
    }

    public var maxHistoryItems: Int {
        get { max(1, defaults.integer(forKey: Key.maxHistoryItems)) }
        set { set(newValue, for: Key.maxHistoryItems) }
    }

    /// Seconds after which unused items are deleted. `0` means keep forever.
    public var retentionSeconds: TimeInterval {
        get { defaults.double(forKey: Key.retention) }
        set { set(newValue, for: Key.retention) }
    }

    /// `retentionSeconds` as an optional, as `HistoryStore` expects.
    public var retention: TimeInterval? {
        retentionSeconds > 0 ? retentionSeconds : nil
    }

    /// Whether history is written (encrypted) to disk or kept in memory only.
    public var persistHistory: Bool {
        get { defaults.bool(forKey: Key.persistHistory) }
        set { set(newValue, for: Key.persistHistory) }
    }

    /// Whether choosing an item also pastes it into the frontmost app (needs Accessibility access).
    public var pasteDirectly: Bool {
        get { defaults.bool(forKey: Key.pasteDirectly) }
        set { set(newValue, for: Key.pasteDirectly) }
    }

    /// Whether to skip content that password managers mark as concealed or transient.
    public var ignoreConfidentialContent: Bool {
        get { defaults.bool(forKey: Key.ignoreConfidential) }
        set { set(newValue, for: Key.ignoreConfidential) }
    }

    /// Bundle identifiers of apps whose copies are never recorded.
    public var ignoredBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? [] }
        set { set(newValue, for: Key.ignoredBundleIDs) }
    }

    public var isCapturePaused: Bool {
        get { defaults.bool(forKey: Key.capturePaused) }
        set { set(newValue, for: Key.capturePaused) }
    }

    /// The global shortcut that opens the history.
    public var hotKey: HotKeyShortcut {
        get {
            HotKeyShortcut(keyCode: defaults.integer(forKey: Key.hotKeyCode),
                           carbonModifiers: defaults.integer(forKey: Key.hotKeyModifiers))
        }
        set {
            defaults.set(newValue.keyCode, forKey: Key.hotKeyCode)
            set(newValue.carbonModifiers, for: Key.hotKeyModifiers) // posts the change once both are stored
        }
    }

    /// Returns `true` exactly once, on the very first launch.
    public func consumeFirstLaunch() -> Bool {
        guard !defaults.bool(forKey: Key.hasLaunchedBefore) else { return false }
        defaults.set(true, forKey: Key.hasLaunchedBefore)
        return true
    }

    private func set(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }
}
