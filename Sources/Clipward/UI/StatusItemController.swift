import AppKit
import ClipwardCore

/// The menu bar icon and its menu.
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        let openHistory: () -> Void
        let clearHistory: () -> Void
        let openSettings: () -> Void
    }

    private let settings: AppSettings
    private let actions: Actions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let openItem = NSMenuItem(title: "Show Clipboard History", action: #selector(openHistory), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Recording", action: #selector(togglePause), keyEquivalent: "")

    init(settings: AppSettings, actions: Actions) {
        self.settings = settings
        self.actions = actions
        super.init()
        statusItem.button?.image = Icons.statusBar
        statusItem.button?.toolTip = "Clipward"
        statusItem.menu = buildMenu()
        refresh()
    }

    /// Re-reads settings (dims the icon while recording is paused).
    func refresh() {
        statusItem.button?.appearsDisabled = settings.isCapturePaused
        pauseItem.state = settings.isCapturePaused ? .on : .off
        let shortcut = settings.hotKey
        openItem.keyEquivalent = shortcut.menuKeyEquivalent ?? ""
        openItem.keyEquivalentModifierMask = shortcut.modifierFlags
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(pauseItem)
        menu.addItem(withTitle: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Clipward", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        return menu
    }

    @objc private func openHistory() { actions.openHistory() }
    @objc private func clearHistory() { actions.clearHistory() }
    @objc private func openSettings() { actions.openSettings() }

    @objc private func togglePause() {
        settings.isCapturePaused.toggle()
        refresh()
    }
}
