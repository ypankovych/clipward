import AppKit
import ClipwardCore

/// The Settings window: startup, pasting, privacy/security options and ignored apps.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let clearOptions: [(seconds: Int, title: String)] = [
        (0, "Never"), (15, "After 15 seconds"), (30, "After 30 seconds"), (60, "After 1 minute"),
        (120, "After 2 minutes"), (300, "After 5 minutes"), (600, "After 10 minutes"),
    ]
    private static let retentionOptions: [(seconds: Int, title: String)] = [
        (86_400, "1 day"), (7 * 86_400, "1 week"), (30 * 86_400, "1 month"), (90 * 86_400, "3 months"), (0, "Forever"),
    ]
    private static let sizeOptions = [50, 100, 200, 500, 1000]
    private static let labelColumnWidth: CGFloat = 150
    /// Display names for the default ignored apps when they aren't installed.
    private static let knownAppNames = [
        "com.apple.keychainaccess": "Keychain Access",
        "com.apple.Passwords": "Passwords",
        "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7",
        "com.bitwarden.desktop": "Bitwarden",
    ]

    private let settings: AppSettings
    private let loginItem: LoginItemService
    private let shortcuts: ShortcutRegistering
    private let onClearHistory: () -> Void

    private let shortcutRecorder = ShortcutRecorder()
    private let resetShortcutButton = NSButton(title: "Reset", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Open Clipward when you log in", target: nil, action: nil)
    private let pasteDirectlyCheckbox = NSButton(checkboxWithTitle: "Paste into the active app after choosing an item", target: nil, action: nil)
    private let accessibilityStatus = NSTextField(labelWithString: "")
    private let accessibilityButton = NSButton(title: "Open Privacy Settings…", target: nil, action: nil)
    private let clearPopup = NSPopUpButton()
    private let retentionPopup = NSPopUpButton()
    private let sizePopup = NSPopUpButton()
    private let persistCheckbox = NSButton(checkboxWithTitle: "Save history to disk, encrypted", target: nil, action: nil)
    private let confidentialCheckbox = NSButton(checkboxWithTitle: "Ignore passwords and other concealed content", target: nil, action: nil)
    private let ignoredAppsTable = NSTableView()
    private let ignoredAppsButtons = NSSegmentedControl()

    init(settings: AppSettings, loginItem: LoginItemService, shortcuts: ShortcutRegistering,
         onClearHistory: @escaping () -> Void) {
        self.settings = settings
        self.loginItem = loginItem
        self.shortcuts = shortcuts
        self.onClearHistory = onClearHistory
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Clipward Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = buildContent()
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Brings the window to the front, activating the app (it has no Dock icon).
    func present() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refresh() // Accessibility may have been granted in System Settings meanwhile
    }

    func windowDidResignKey(_ notification: Notification) {
        shortcutRecorder.stopRecording()
    }

    private func refresh() {
        launchAtLoginCheckbox.state = loginItem.isEnabled ? .on : .off
        shortcutRecorder.shortcut = shortcuts.shortcut
        resetShortcutButton.isEnabled = shortcuts.shortcut != .defaultShortcut
        pasteDirectlyCheckbox.state = settings.pasteDirectly ? .on : .off
        let trusted = Accessibility.isTrusted()
        accessibilityStatus.stringValue = trusted ? "Accessibility access granted." : "Needs Accessibility access to paste."
        accessibilityButton.isHidden = trusted
        select(Int(settings.clearClipboardAfter), in: clearPopup, title: { "After \($0) seconds" })
        select(Int(settings.retentionSeconds), in: retentionPopup, title: { "\($0 / 86_400) days" })
        select(settings.maxHistoryItems, in: sizePopup, title: { "\($0) items" })
        persistCheckbox.state = settings.persistHistory ? .on : .off
        confidentialCheckbox.state = settings.ignoreConfidentialContent ? .on : .off
        ignoredAppsTable.reloadData()
        updateRemoveButton()
    }

    /// Selects the item tagged `value`, adding one if the stored value isn't a preset.
    private func select(_ value: Int, in popup: NSPopUpButton, title: (Int) -> String) {
        if popup.selectItem(withTag: value) { return }
        popup.addItem(withTitle: title(value))
        popup.lastItem?.tag = value
        popup.selectItem(withTag: value)
    }

    // MARK: - Actions

    @objc private func launchAtLoginChanged() {
        let enable = launchAtLoginCheckbox.state == .on
        do {
            try loginItem.setEnabled(enable)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't \(enable ? "enable" : "disable") launch at login"
            alert.beginSheetModal(for: window!)
        }
        refresh()
    }

    private func recordShortcut(_ shortcut: HotKeyShortcut) -> Bool {
        guard shortcuts.change(to: shortcut) else {
            let alert = NSAlert()
            alert.messageText = "\(shortcut.displayString) is already in use"
            alert.informativeText = "Another app has registered this shortcut. Try a different combination."
            alert.beginSheetModal(for: window!)
            return false
        }
        refresh()
        return true
    }

    @objc private func resetShortcut() {
        _ = recordShortcut(.defaultShortcut)
    }

    @objc private func pasteDirectlyChanged() {
        settings.pasteDirectly = pasteDirectlyCheckbox.state == .on
        if settings.pasteDirectly && !Accessibility.isTrusted(prompt: true) { refresh() }
    }

    @objc private func openAccessibilitySettings() {
        _ = Accessibility.isTrusted(prompt: true) // adds Clipward to the list so it can be switched on
        Accessibility.openSystemSettings()
    }

    @objc private func clearAfterChanged() {
        settings.clearClipboardAfter = TimeInterval(clearPopup.selectedTag())
    }

    @objc private func retentionChanged() {
        settings.retentionSeconds = TimeInterval(retentionPopup.selectedTag())
    }

    @objc private func sizeChanged() {
        settings.maxHistoryItems = sizePopup.selectedTag()
    }

    @objc private func persistChanged() {
        settings.persistHistory = persistCheckbox.state == .on
    }

    @objc private func confidentialChanged() {
        settings.ignoreConfidentialContent = confidentialCheckbox.state == .on
    }

    @objc private func clearHistoryClicked() {
        onClearHistory()
    }

    @objc private func ignoredAppsButtonClicked() {
        if ignoredAppsButtons.selectedSegment == 0 { addIgnoredApp() } else { removeIgnoredApp() }
    }

    private func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["app"]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Ignore"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self = self, response == .OK else { return }
            let newIDs = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            self.settings.ignoredBundleIDs = Array(NSOrderedSet(array: self.settings.ignoredBundleIDs + newIDs)) as? [String] ?? []
            self.refresh()
        }
    }

    private func removeIgnoredApp() {
        let rows = ignoredAppsTable.selectedRowIndexes
        settings.ignoredBundleIDs = settings.ignoredBundleIDs.enumerated().filter { !rows.contains($0.offset) }.map(\.element)
        refresh()
    }

    private func updateRemoveButton() {
        ignoredAppsButtons.setEnabled(ignoredAppsTable.selectedRow >= 0, forSegment: 1)
    }

    // MARK: - Layout

    private func buildContent() -> NSView {
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)
        pasteDirectlyCheckbox.target = self
        pasteDirectlyCheckbox.action = #selector(pasteDirectlyChanged)
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibilitySettings)
        accessibilityButton.controlSize = .small
        accessibilityButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        persistCheckbox.target = self
        persistCheckbox.action = #selector(persistChanged)
        confidentialCheckbox.target = self
        confidentialCheckbox.action = #selector(confidentialChanged)

        configure(clearPopup, options: Self.clearOptions, action: #selector(clearAfterChanged))
        configure(retentionPopup, options: Self.retentionOptions, action: #selector(retentionChanged))
        configure(sizePopup, options: Self.sizeOptions.map { ($0, "\($0) items") }, action: #selector(sizeChanged))

        shortcutRecorder.onRecord = { [weak self] in self?.recordShortcut($0) ?? false }
        shortcutRecorder.onRecordingChanged = { [weak self] in self?.shortcuts.setSuspended($0) }
        resetShortcutButton.target = self
        resetShortcutButton.action = #selector(resetShortcut)

        let general = grid([
            ("Startup:", launchAtLoginCheckbox),
            ("Open history:", row(shortcutRecorder, resetShortcutButton)),
            (nil, note("Click, then press a new combination using ⌘, ⌃ or ⌥.")),
            ("Pasting:", pasteDirectlyCheckbox),
            (nil, row(accessibilityStatus, accessibilityButton)),
        ])
        let security = grid([
            ("Clear clipboard:", clearPopup),
            (nil, note("How long an item pasted from Clipward stays on the clipboard.")),
            ("Keep history for:", retentionPopup),
            ("History size:", sizePopup),
            ("Storage:", persistCheckbox),
            (nil, note("Encrypted with AES-256; the key is kept in your login Keychain.\nWhen off, history lives in memory only and is lost on quit.")),
            ("Privacy:", confidentialCheckbox),
        ])
        let clearButton = NSButton(title: "Clear History…", target: self, action: #selector(clearHistoryClicked))
        let apps = grid([
            ("Ignored apps:", ignoredAppsList()),
            (nil, note("Nothing copied in these apps is recorded.")),
            (nil, clearButton),
        ])

        let stack = NSStackView(views: [general, separator(), security, separator(), apps])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 28)
        return stack
    }

    private func configure(_ popup: NSPopUpButton, options: [(Int, String)], action: Selector) {
        for (tag, title) in options {
            popup.addItem(withTitle: title)
            popup.lastItem?.tag = tag
        }
        popup.target = self
        popup.action = action
    }

    private func grid(_ rows: [(String?, NSView)]) -> NSGridView {
        let grid = NSGridView(views: rows.map { label, control in
            [label.map { NSTextField(labelWithString: $0) } ?? NSGridCell.emptyContentView, control]
        })
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = Self.labelColumnWidth
        grid.column(at: 1).xPlacement = .leading
        return grid
    }

    private func row(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.spacing = 8
        stack.alignment = .firstBaseline
        return stack
    }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 340
        return label
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: Self.labelColumnWidth + 360).isActive = true
        return box
    }

    private func ignoredAppsList() -> NSView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        ignoredAppsTable.addTableColumn(column)
        ignoredAppsTable.headerView = nil
        ignoredAppsTable.rowHeight = 22
        ignoredAppsTable.allowsMultipleSelection = true
        ignoredAppsTable.dataSource = self
        ignoredAppsTable.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = ignoredAppsTable
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        ignoredAppsButtons.segmentCount = 2
        ignoredAppsButtons.setImage(NSImage(named: NSImage.addTemplateName), forSegment: 0)
        ignoredAppsButtons.setImage(NSImage(named: NSImage.removeTemplateName), forSegment: 1)
        ignoredAppsButtons.setWidth(24, forSegment: 0)
        ignoredAppsButtons.setWidth(24, forSegment: 1)
        ignoredAppsButtons.trackingMode = .momentary
        ignoredAppsButtons.segmentStyle = .smallSquare
        ignoredAppsButtons.target = self
        ignoredAppsButtons.action = #selector(ignoredAppsButtonClicked)

        let container = NSStackView(views: [scrollView, ignoredAppsButtons])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 0
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalToConstant: 340),
            scrollView.heightAnchor.constraint(equalToConstant: 110),
        ])
        return container
    }
}

extension SettingsWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        settings.ignoredBundleIDs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let bundleID = settings.ignoredBundleIDs[row]
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let name = appURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? Self.knownAppNames[bundleID]
        let icon = appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? Icons.symbol("app.dashed", description: "Not installed")
            ?? NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon)))

        let imageView = NSImageView(image: icon)
        if #available(macOS 10.14, *), icon.isTemplate { imageView.contentTintColor = .tertiaryLabelColor }
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let label = NSTextField(labelWithString: name ?? bundleID)
        label.lineBreakMode = .byTruncatingTail
        if appURL == nil { label.textColor = .secondaryLabelColor } // not installed

        let cell = NSStackView(views: [imageView, label])
        cell.spacing = 6
        cell.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        cell.toolTip = bundleID
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveButton()
    }
}
