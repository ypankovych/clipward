import AppKit
import Carbon.HIToolbox
import ClipwardCore

protocol HistoryViewControllerDelegate: AnyObject {
    func historyViewController(_ controller: HistoryViewController, didChoose item: ClipMetadata, plainTextOnly: Bool)
    func historyViewControllerDidCancel(_ controller: HistoryViewController)
    func historyViewControllerDidRequestSettings(_ controller: HistoryViewController)
}

/// Content of the history popup: a search field, the list of captures and a hint bar.
final class HistoryViewController: NSViewController {
    static let preferredSize = NSSize(width: 460, height: 440)

    /// Number-row key codes (layout independent) for the ⌘1…⌘9 shortcuts.
    private static let digitKeys = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9,
    ]

    weak var delegate: HistoryViewControllerDelegate?

    private let store: HistoryStore
    private let settings: AppSettings
    private var visibleItems: [ClipMetadata] = []
    private let iconCache = NSCache<NSUUID, NSImage>()

    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    init(store: HistoryStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(storeDidChange),
                                               name: HistoryStore.didChangeNotification, object: store)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func loadView() {
        let background = RoundedVisualEffectView(cornerRadius: 12)
        background.frame = NSRect(origin: .zero, size: Self.preferredSize)
        view = background
        buildLayout()
    }

    /// Resets the search and selection; call before showing the panel.
    func prepareForDisplay() {
        _ = view
        searchField.stringValue = ""
        hintLabel.stringValue = settings.pasteDirectly
            ? "↩ Paste    ⇧↩ Paste as plain text    ⌘⌫ Delete"
            : "↩ Copy    ⇧↩ Copy as plain text    ⌘⌫ Delete"
        reload()
        view.window?.makeFirstResponder(searchField)
    }

    /// Keyboard navigation and shortcuts. Returns `true` if the event was handled.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = modifiers.contains(.command)
        switch Int(event.keyCode) {
        case kVK_UpArrow: moveSelection(by: -1)
        case kVK_DownArrow: moveSelection(by: 1)
        case kVK_PageUp: moveSelection(by: -8)
        case kVK_PageDown: moveSelection(by: 8)
        case kVK_Return, kVK_ANSI_KeypadEnter: chooseSelected(plainTextOnly: modifiers.contains(.shift))
        case kVK_Escape:
            if searchField.stringValue.isEmpty {
                delegate?.historyViewControllerDidCancel(self)
            } else {
                searchField.stringValue = ""
                reload()
            }
        case kVK_Delete where command: deleteSelected()
        case kVK_ANSI_Comma where command: delegate?.historyViewControllerDidRequestSettings(self)
        default:
            guard command, let digit = Self.digitKeys[Int(event.keyCode)], digit <= visibleItems.count else { return false }
            delegate?.historyViewController(self, didChoose: visibleItems[digit - 1], plainTextOnly: modifiers.contains(.shift))
        }
        return true
    }

    // MARK: - Actions

    @objc private func storeDidChange() {
        guard isViewLoaded else { return }
        let selectedID = selectedItem?.id
        reload()
        if let id = selectedID, let row = visibleItems.firstIndex(where: { $0.id == id }) { select(row: row) }
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard visibleItems.indices.contains(row) else { return }
        delegate?.historyViewController(self, didChoose: visibleItems[row], plainTextOnly: false)
    }

    @objc private func settingsClicked() {
        delegate?.historyViewControllerDidRequestSettings(self)
    }

    private var selectedItem: ClipMetadata? {
        visibleItems.indices.contains(tableView.selectedRow) ? visibleItems[tableView.selectedRow] : nil
    }

    private func chooseSelected(plainTextOnly: Bool) {
        guard let item = selectedItem else { NSSound.beep(); return }
        delegate?.historyViewController(self, didChoose: item, plainTextOnly: plainTextOnly)
    }

    private func deleteSelected() {
        guard let item = selectedItem else { return }
        let row = tableView.selectedRow
        store.remove(id: item.id) // triggers reload via notification
        select(row: min(row, visibleItems.count - 1))
    }

    private func moveSelection(by delta: Int) {
        guard !visibleItems.isEmpty else { return }
        select(row: min(max(tableView.selectedRow + delta, 0), visibleItems.count - 1))
    }

    private func select(row: Int) {
        guard visibleItems.indices.contains(row) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func reload() {
        visibleItems = store.items(matching: searchField.stringValue)
        tableView.reloadData()
        emptyLabel.stringValue = store.items.isEmpty ? "Copied items will appear here" : "No matches"
        emptyLabel.isHidden = !visibleItems.isEmpty
        select(row: 0)
    }

    private func icon(for item: ClipMetadata) -> NSImage {
        if let cached = iconCache.object(forKey: item.id as NSUUID) { return cached }
        let image: NSImage
        if let thumbnail = item.thumbnail.flatMap(NSImage.init(data:)) {
            image = thumbnail
        } else if item.kind == .file, let path = item.filePaths.first, FileManager.default.fileExists(atPath: path) {
            image = NSWorkspace.shared.icon(forFile: path)
        } else {
            image = Icons.kind(item.kind)
        }
        iconCache.setObject(image, forKey: item.id as NSUUID)
        return image
    }

    // MARK: - Layout

    private func buildLayout() {
        searchField.placeholderString = "Search clipboard history"
        searchField.font = .systemFont(ofSize: 18)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.cell?.isScrollable = true
        searchField.cell?.wraps = false

        let searchIcon = NSImageView()
        searchIcon.image = Icons.search
        searchIcon.isHidden = Icons.search == nil
        if #available(macOS 10.14, *) { searchIcon.contentTintColor = .secondaryLabelColor }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.refusesFirstResponder = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        if #available(macOS 11, *) { tableView.style = .inset }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let settingsButton = NSButton(image: Icons.settings, target: self, action: #selector(settingsClicked))
        settingsButton.isBordered = false
        settingsButton.toolTip = "Settings (⌘,)"
        if #available(macOS 10.14, *) { settingsButton.contentTintColor = .secondaryLabelColor }

        let topSeparator = separator()
        let bottomSeparator = separator()
        let views: [NSView] = [searchIcon, searchField, topSeparator, scrollView, emptyLabel, bottomSeparator, hintLabel, settingsButton]
        for subview in views {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        let searchLeading = Icons.search == nil
            ? searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
            : searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8)

        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchIcon.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 18),
            searchIcon.heightAnchor.constraint(equalToConstant: 18),
            searchLeading,
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),

            topSeparator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            topSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: topSeparator.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            scrollView.bottomAnchor.constraint(equalTo: bottomSeparator.topAnchor, constant: -4),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            bottomSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomSeparator.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -30),

            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hintLabel.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: -15),
            settingsButton.leadingAnchor.constraint(greaterThanOrEqualTo: hintLabel.trailingAnchor, constant: 8),
            settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            settingsButton.centerYAnchor.constraint(equalTo: hintLabel.centerYAnchor),
        ])
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}

extension HistoryViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ClipCellView.identifier, owner: self) as? ClipCellView ?? ClipCellView()
        let item = visibleItems[row]
        cell.configure(with: item, icon: icon(for: item), shortcutIndex: row < 9 ? row + 1 : nil)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        EmphasizedRowView()
    }
}

extension HistoryViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        reload()
    }
}
