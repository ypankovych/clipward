import AppKit
import Carbon.HIToolbox

/// Puts history items back on the clipboard, optionally pastes them into the frontmost app,
/// and wipes the clipboard again once the configured timeout passes.
public final class PasteService {
    private let pasteboard: NSPasteboard
    private let settings: AppSettings
    private let monitor: ClipboardMonitor
    private var pendingClear: DispatchWorkItem?
    /// `changeCount` right after our last write; the clipboard is only cleared if nobody copied since.
    private var ownedChangeCount: Int?
    private var hasPromptedForAccessibility = false

    public init(pasteboard: NSPasteboard = .general, settings: AppSettings, monitor: ClipboardMonitor) {
        self.pasteboard = pasteboard
        self.settings = settings
        self.monitor = monitor
    }

    /// Writes `payload` to the clipboard and starts the auto-clear countdown.
    /// - Parameter plainTextOnly: write only the plain-text representation, dropping formatting.
    @discardableResult
    public func copy(_ payload: ClipPayload, plainTextOnly: Bool = false) -> Bool {
        var items = payload.items
        if plainTextOnly, let text = payload.data(forType: PasteboardTypes.plainText) {
            items = [[ClipRepresentation(type: PasteboardTypes.plainText, data: text)]]
        }
        let pasteboardItems: [NSPasteboardItem] = items.map { representations in
            let item = NSPasteboardItem()
            representations.forEach { item.setData($0.data, forType: NSPasteboard.PasteboardType($0.type)) }
            return item
        }
        pasteboard.clearContents()
        let written = pasteboard.writeObjects(pasteboardItems)
        monitor.ignoreCurrentContents()
        scheduleClear()
        return written
    }

    /// Sends ⌘V to the frontmost app. Requires Accessibility access; asks for it once if missing.
    public func pasteIntoFrontmostApp() {
        guard Accessibility.isTrusted(prompt: !hasPromptedForAccessibility) else {
            hasPromptedForAccessibility = true
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Clears the clipboard now if it still holds what we put there. Called on quit.
    public func clearIfStillOwned() {
        pendingClear?.cancel()
        pendingClear = nil
        defer { ownedChangeCount = nil }
        guard let owned = ownedChangeCount, pasteboard.changeCount == owned else { return }
        pasteboard.clearContents()
        monitor.ignoreCurrentContents()
    }

    private func scheduleClear() {
        pendingClear?.cancel()
        ownedChangeCount = pasteboard.changeCount
        let delay = settings.clearClipboardAfter
        guard delay > 0 else { return }
        let work = DispatchWorkItem { [weak self] in self?.clearIfStillOwned() }
        pendingClear = work
        // Wall-clock deadline so time spent asleep counts towards the timeout.
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + delay, execute: work)
    }
}

/// Accessibility (synthetic keyboard input) permission helpers.
public enum Accessibility {
    public static func isTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
