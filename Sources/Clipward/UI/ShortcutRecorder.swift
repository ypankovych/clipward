import AppKit
import Carbon.HIToolbox
import ClipwardCore

/// A button that shows a shortcut and, when clicked, records the next key combination.
/// Esc cancels; combinations without ⌘, ⌃ or ⌥ (other than function keys) are rejected.
final class ShortcutRecorder: NSButton {
    /// Called with a newly recorded shortcut; return `false` to reject it (e.g. it's taken).
    var onRecord: ((HotKeyShortcut) -> Bool)?
    /// Called when recording starts and stops.
    var onRecordingChanged: ((Bool) -> Void)?

    var shortcut: HotKeyShortcut? {
        didSet { updateTitle() }
    }

    private var eventMonitor: Any?
    private var isRecording: Bool { eventMonitor != nil }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { stopRecording() }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    /// Stops recording without changing the shortcut, e.g. when the window loses focus.
    func stopRecording() {
        guard let monitor = eventMonitor else { return }
        NSEvent.removeMonitor(monitor)
        eventMonitor = nil
        updateTitle()
        onRecordingChanged?(false)
    }

    @objc private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        // Key presses only reach a local monitor while this window is key in the active app.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        onRecordingChanged?(true)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event) ?? event
        }
        title = "Type shortcut…"
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .flagsChanged {
            let symbols = HotKeyShortcut.modifierSymbols(event.modifierFlags)
            title = symbols.isEmpty ? "Type shortcut…" : symbols + "…"
            return nil
        }
        let keyCode = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if keyCode == kVK_Escape && modifiers.isEmpty {
            stopRecording()
            return nil
        }
        guard let recorded = HotKeyShortcut(keyCode: keyCode, modifierFlags: event.modifierFlags) else {
            NSSound.beep() // needs ⌘, ⌃ or ⌥
            return nil
        }
        if onRecord?(recorded) ?? true {
            shortcut = recorded
        } else {
            NSSound.beep()
        }
        stopRecording()
        return nil
    }

    private func updateTitle() {
        title = shortcut?.displayString ?? "Record Shortcut"
    }
}
