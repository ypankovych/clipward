import AppKit
import ClipwardCore

/// Composes the app's parts and reacts to settings changes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let analyzer = ClipAnalyzer()
    private let analysisQueue = DispatchQueue(label: "Clipward.analysis", qos: .userInitiated)
    private let loginItem = LoginItem.makeService()

    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var pasteService: PasteService!
    private var historyController: HistoryPanelController!
    private var statusItemController: StatusItemController!
    private var settingsController: SettingsWindowController?
    private var hotKeys: HotKeyManager!
    private var maintenanceTimer: Timer?
    private var isPersisting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isAnotherInstanceRunning() else {
            NSApp.terminate(nil)
            return
        }
        NSApp.mainMenu = MainMenu.make(settingsTarget: self, settingsAction: #selector(openSettings))

        isPersisting = settings.persistHistory
        store = HistoryStore(repository: makeRepository(persistent: isPersisting),
                             maxItems: settings.maxHistoryItems, retention: settings.retention)
        monitor = ClipboardMonitor(settings: settings) { [weak self] payload, source in
            self?.record(payload, from: source)
        }
        pasteService = PasteService(settings: settings, monitor: monitor)
        historyController = HistoryPanelController(store: store, settings: settings, pasteService: pasteService) { [weak self] in
            self?.openSettings()
        }
        statusItemController = StatusItemController(settings: settings, actions: .init(
            openHistory: { [weak self] in self?.historyController.show() },
            clearHistory: { [weak self] in self?.confirmClearHistory() },
            openSettings: { [weak self] in self?.openSettings() }
        ))

        registerHotKey()
        monitor.start()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange),
                                               name: AppSettings.didChangeNotification, object: settings)
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            self?.store.enforceLimits() // expire old items even when nothing new is copied
        }
        if settings.consumeFirstLaunch() { openSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pasteService?.clearIfStillOwned()
        store?.flush()
    }

    // MARK: - Capturing

    private func record(_ payload: ClipPayload, from source: ClipSource) {
        analysisQueue.async { [analyzer] in
            let metadata = analyzer.metadata(for: payload, source: source)
            DispatchQueue.main.async { [weak self] in self?.store.add(metadata, payload: payload) }
        }
    }

    private func makeRepository(persistent: Bool) -> HistoryRepository {
        guard persistent else { return InMemoryHistoryRepository() }
        do {
            let key = try KeychainKeyStore(service: bundleIdentifier).key()
            let directory = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Clipward/History", isDirectory: true)
            return try EncryptedFileHistoryRepository(directory: directory, cipher: AuthenticatedCipher(key: key))
        } catch {
            // Never fall back to plaintext on disk; keep history in memory instead.
            NSLog("Clipward: encrypted storage unavailable, keeping history in memory: \(error)")
            return InMemoryHistoryRepository()
        }
    }

    @objc private func settingsDidChange() {
        store.maxItems = settings.maxHistoryItems
        store.retention = settings.retention
        if settings.persistHistory != isPersisting {
            isPersisting = settings.persistHistory
            store.replaceRepository(with: makeRepository(persistent: isPersisting))
        }
        statusItemController.refresh()
    }

    // MARK: - Commands

    @objc func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(settings: settings, loginItem: loginItem, shortcuts: hotKeys) { [weak self] in
                self?.confirmClearHistory()
            }
        }
        settingsController?.present()
    }

    private func confirmClearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "All \(store.items.count) items will be permanently deleted. This can't be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { store.removeAll() }
    }

    private func registerHotKey() {
        hotKeys = HotKeyManager(settings: settings) { [weak self] in self?.historyController.toggle() }
        guard !hotKeys.start() else { return }
        let alert = NSAlert()
        alert.messageText = "\(settings.hotKey.displayString) is already in use"
        alert.informativeText = "Another app has registered this shortcut. Choose a different one in Settings, "
            + "or open the history from the menu bar icon."
        alert.runModal()
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "io.github.ypankovych.Clipward"
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let current = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { $0.processIdentifier != current }
    }
}
