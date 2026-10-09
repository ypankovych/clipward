import AppKit
import ImageIO

/// Derives display metadata (kind, title, thumbnail, fingerprint) from raw clipboard contents.
/// Safe to call off the main thread.
public struct ClipAnalyzer {
    public var thumbnailPixelSize = 96
    public var maxTitleLength = 300
    public var maxSearchTextLength = 20_000

    public init() {}

    public func metadata(for payload: ClipPayload, source: ClipSource, date: Date = Date()) -> ClipMetadata {
        let text = plainText(in: payload)
        let files = fileURLs(in: payload)
        let kind = classify(payload, text: text, files: files)

        let title: String
        var thumbnail: Data?
        var primaryContent: [Data]
        switch kind {
        case .file:
            title = fileTitle(files)
            primaryContent = files.map { Data($0.path.utf8) }
        case .image:
            let image = imageSummary(payload)
            title = image.title
            thumbnail = image.thumbnail
            primaryContent = [image.data]
        case .color:
            let color = colorSummary(payload)
            title = color.title
            thumbnail = color.swatch
            primaryContent = [Data(title.utf8)]
        case .text, .richText, .link:
            let body = text ?? ""
            title = body.isEmpty ? "Rich text" : condensed(body)
            primaryContent = [Data(body.utf8)]
        case .other:
            title = payload.types.sorted().first ?? "Unknown data"
            primaryContent = payload.items.flatMap { $0.flatMap { [Data($0.type.utf8), $0.data] } }
        }

        let searchable = ([title, text ?? ""] + files.map(\.path)).joined(separator: "\n")
        return ClipMetadata(
            lastCopiedAt: date,
            source: source,
            kind: kind,
            title: title,
            searchText: String(searchable.lowercased().prefix(maxSearchTextLength)),
            fingerprint: Digest.sha256Hex([Data(kind.rawValue.utf8)] + primaryContent),
            byteCount: payload.byteCount,
            thumbnail: thumbnail,
            filePaths: files.map(\.path)
        )
    }

    // MARK: - Classification

    private func classify(_ payload: ClipPayload, text: String?, files: [URL]) -> ClipKind {
        let types = payload.types
        if !files.isEmpty { return .file }
        if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if isLink(text) { return .link }
            return types.isDisjoint(with: PasteboardTypes.richText) ? .text : .richText
        }
        if PasteboardTypes.images.contains(where: types.contains) { return .image }
        if types.contains(PasteboardTypes.color) { return .color }
        if !types.isDisjoint(with: PasteboardTypes.richText) { return .richText }
        return .other
    }

    private func plainText(in payload: ClipPayload) -> String? {
        if let data = payload.data(forType: PasteboardTypes.plainText) ?? payload.data(forType: PasteboardTypes.url) {
            return String(data: data, encoding: .utf8)
        }
        if let rtf = payload.data(forType: PasteboardTypes.rtf) {
            return NSAttributedString(rtf: rtf, documentAttributes: nil)?.string
        }
        return nil
    }

    private func fileURLs(in payload: ClipPayload) -> [URL] {
        payload.allData(forType: PasteboardTypes.fileURL).compactMap { data in
            guard let string = String(data: data, encoding: .utf8), let url = URL(string: string), url.isFileURL else { return nil }
            return url.standardizedFileURL
        }
    }

    private func isLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }),
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https", "ftp": return url.host != nil
        case "mailto", "tel": return true
        default: return false
        }
    }

    // MARK: - Titles and previews

    private func condensed(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return String(collapsed.prefix(maxTitleLength))
    }

    private func fileTitle(_ files: [URL]) -> String {
        let names = files.map(\.lastPathComponent)
        if names.count == 1 { return names[0] }
        return "\(names.count) files: " + names.prefix(5).joined(separator: ", ")
    }

    private func imageSummary(_ payload: ClipPayload) -> (title: String, thumbnail: Data?, data: Data) {
        let data = PasteboardTypes.images.lazy.compactMap { payload.data(forType: $0) }.first ?? Data()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return ("Image", nil, data) }

        var title = "Image"
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            title = "Image  \(width) × \(height)"
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixelSize,
        ]
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).flatMap(pngData)
        return (title, thumbnail, data)
    }

    private func colorSummary(_ payload: ClipPayload) -> (title: String, swatch: Data?) {
        guard let data = payload.data(forType: PasteboardTypes.color),
              let color = (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)) ?? nil,
              let rgb = color.usingColorSpace(.sRGB) else { return ("Color", nil) }
        let hex = String(format: "#%02X%02X%02X",
                         Int(round(rgb.redComponent * 255)), Int(round(rgb.greenComponent * 255)), Int(round(rgb.blueComponent * 255)))
        return (hex, swatch(rgb.cgColor))
    }

    private func swatch(_ color: CGColor) -> Data? {
        let size = thumbnailPixelSize
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 4, dy: 4)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 16, cornerHeight: 16, transform: nil))
        context.setFillColor(color)
        context.fillPath()
        return context.makeImage().flatMap(pngData)
    }

    private func pngData(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
