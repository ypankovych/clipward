import AppKit
import ClipwardCore

/// App imagery. Uses SF Symbols on macOS 11+, and Finder type icons or simple drawings before that.
enum Icons {
    /// An SF Symbol on macOS 11+, `nil` on older systems.
    static func symbol(_ name: String, description: String) -> NSImage? {
        if #available(macOS 11, *) {
            return NSImage(systemSymbolName: name, accessibilityDescription: description)
        }
        return nil
    }

    /// Generic icon for a kind of clipboard content.
    static func kind(_ kind: ClipKind) -> NSImage {
        let (symbolName, typeIdentifier): (String, String)
        switch kind {
        case .text: (symbolName, typeIdentifier) = ("text.alignleft", "public.plain-text")
        case .richText: (symbolName, typeIdentifier) = ("doc.richtext", "public.rtf")
        case .link: (symbolName, typeIdentifier) = ("link", "public.url")
        case .image: (symbolName, typeIdentifier) = ("photo", "public.image")
        case .file: (symbolName, typeIdentifier) = ("doc", "public.data")
        case .color: (symbolName, typeIdentifier) = ("paintpalette", "public.item")
        case .other: (symbolName, typeIdentifier) = ("square.on.square", "public.data")
        }
        return symbol(symbolName, description: kind.rawValue) ?? NSWorkspace.shared.icon(forFileType: typeIdentifier)
    }

    static let statusBar: NSImage = {
        let image = symbol("doc.on.clipboard", description: "Clipward") ?? drawnClipboard()
        image.isTemplate = true
        return image
    }()

    static var settings: NSImage {
        symbol("gearshape", description: "Settings") ?? NSImage(named: NSImage.actionTemplateName)!
    }

    static var search: NSImage? {
        symbol("magnifyingglass", description: "Search")
    }

    /// Menu bar glyph for systems without SF Symbols.
    private static func drawnClipboard() -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let board = NSBezierPath(roundedRect: NSRect(x: 3.5, y: 1.5, width: 11, height: 14), xRadius: 2, yRadius: 2)
            board.lineWidth = 1.4
            board.stroke()
            NSBezierPath(roundedRect: NSRect(x: 6, y: 13.5, width: 6, height: 3), xRadius: 1, yRadius: 1).fill()
            for y in [9.5, 6.5] {
                NSBezierPath.strokeLine(from: NSPoint(x: 6.5, y: y), to: NSPoint(x: 11.5, y: y))
            }
            return true
        }
    }
}
