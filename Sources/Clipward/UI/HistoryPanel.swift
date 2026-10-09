import AppKit

/// Borderless floating panel that takes keyboard focus without activating the app,
/// so the app the user was in stays frontmost and can receive the paste.
final class HistoryPanel: NSPanel {
    /// Gets every key-down first; return `true` to consume it.
    var keyDownHandler: ((NSEvent) -> Bool)?

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !isComposingText, keyDownHandler?(event) == true { return }
        super.sendEvent(event)
    }

    /// True while an input method (e.g. Japanese) is composing; Return and arrows belong to it then.
    private var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }
}

/// Rounded, translucent background matching system popovers. Uses a mask image
/// rather than layer corner radius so the blur is clipped correctly on every macOS version.
final class RoundedVisualEffectView: NSVisualEffectView {
    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        maskImage = Self.mask(cornerRadius: cornerRadius)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func mask(cornerRadius radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
