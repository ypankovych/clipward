import AppKit
import ClipwardCore

/// One history row: icon or thumbnail, title, "app · time" subtitle and a ⌘-number hint.
final class ClipCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ClipCell")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private var iconIsTemplate = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        buildLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// - Parameters:
    ///   - icon: thumbnail, file icon or kind symbol.
    ///   - shortcutIndex: 1–9 to show "⌘n", `nil` for none.
    func configure(with item: ClipMetadata, icon: NSImage, shortcutIndex: Int?) {
        iconView.image = icon
        iconIsTemplate = icon.isTemplate
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = Self.subtitle(for: item)
        shortcutLabel.stringValue = shortcutIndex.map { "⌘\($0)" } ?? ""
        toolTip = item.title.count > 60 ? String(item.title.prefix(500)) : nil
        updateColors()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    private static func subtitle(for item: ClipMetadata) -> String {
        var parts = [item.sourceAppName, RelativeTime.string(for: item.lastCopiedAt)].compactMap { $0 }
        if [.image, .other].contains(item.kind) {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private var isHighlighted: Bool {
        if #available(macOS 10.14, *) { return backgroundStyle == .emphasized }
        return backgroundStyle == .dark
    }

    private func updateColors() {
        let highlighted = isHighlighted
        titleLabel.textColor = highlighted ? .alternateSelectedControlTextColor : .labelColor
        subtitleLabel.textColor = highlighted ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.75) : .secondaryLabelColor
        shortcutLabel.textColor = highlighted ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.75) : .tertiaryLabelColor
        if #available(macOS 10.14, *), iconIsTemplate {
            iconView.contentTintColor = highlighted ? .alternateSelectedControlTextColor : .secondaryLabelColor
        }
    }

    private func buildLayout() {
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 4
        iconView.layer?.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        shortcutLabel.font = .systemFont(ofSize: 11, weight: .medium)
        shortcutLabel.alignment = .right
        shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        for view in [iconView, textStack, shortcutLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 8),
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

/// Row view that always draws the selection in the accent color: focus stays in the
/// search field, which would otherwise make the table show the grey "inactive" selection.
final class EmphasizedRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {} // ignore the table's focus-based value
    }
}
