import AppKit
import ClipwardCore

/// Shows and hides the history popup and turns a chosen item into a copy (and paste).
final class HistoryPanelController: NSObject {
    private let store: HistoryStore
    private let settings: AppSettings
    private let pasteService: PasteService
    private let onOpenSettings: () -> Void
    private let panel: HistoryPanel
    private let viewController: HistoryViewController
    /// The app that was frontmost when the popup opened; it receives the paste.
    private var previousApp: NSRunningApplication?

    init(store: HistoryStore, settings: AppSettings, pasteService: PasteService, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.pasteService = pasteService
        self.onOpenSettings = onOpenSettings
        viewController = HistoryViewController(store: store, settings: settings)
        panel = HistoryPanel(size: HistoryViewController.preferredSize)
        super.init()
        panel.contentViewController = viewController
        panel.setContentSize(HistoryViewController.preferredSize)
        panel.delegate = self
        panel.keyDownHandler = { [weak self] event in self?.viewController.handleKeyDown(event) ?? false }
        viewController.delegate = self
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        position()
        panel.makeKeyAndOrderFront(nil)
        viewController.prepareForDisplay() // needs the panel to be key to focus the search field
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Centres the panel horizontally, a little above the middle of the screen under the mouse.
    private func position() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: max(visible.minY, visible.minY + visible.height * 0.6 - size.height / 2))
        panel.setFrameOrigin(origin)
    }

    private func choose(_ item: ClipMetadata, plainTextOnly: Bool) {
        guard let payload = store.payload(for: item.id) else {
            NSSound.beep()
            store.remove(id: item.id) // unreadable, e.g. deleted from disk
            return
        }
        pasteService.copy(payload, plainTextOnly: plainTextOnly)
        store.markUsed(id: item.id)
        hide()
        guard settings.pasteDirectly else { return }
        if NSApp.isActive { previousApp?.activate(options: []) }
        // Give the target app a moment to regain key focus before sending ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [pasteService] in
            pasteService.pasteIntoFrontmostApp()
        }
    }
}

extension HistoryPanelController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

extension HistoryPanelController: HistoryViewControllerDelegate {
    func historyViewController(_ controller: HistoryViewController, didChoose item: ClipMetadata, plainTextOnly: Bool) {
        choose(item, plainTextOnly: plainTextOnly)
    }

    func historyViewControllerDidCancel(_ controller: HistoryViewController) {
        hide()
    }

    func historyViewControllerDidRequestSettings(_ controller: HistoryViewController) {
        hide()
        onOpenSettings()
    }
}
