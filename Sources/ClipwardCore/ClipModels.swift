import Foundation

/// One pasteboard type and its raw bytes, e.g. `public.utf8-plain-text` and its UTF-8 data.
public struct ClipRepresentation: Codable, Equatable {
    public let type: String
    public let data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

/// The full, restorable contents of one clipboard capture.
///
/// `items` mirrors the pasteboard's items (copying three files yields three items);
/// each item keeps every representation the source app offered, so pasting it back
/// is indistinguishable from the original copy.
public struct ClipPayload: Codable, Equatable {
    public let items: [[ClipRepresentation]]

    public init(items: [[ClipRepresentation]]) {
        self.items = items
    }

    /// Total size of all representations, in bytes.
    public var byteCount: Int {
        items.reduce(0) { total, item in total + item.reduce(0) { $0 + $1.data.count } }
    }

    /// Every type present in any item.
    public var types: Set<String> {
        Set(items.flatMap { $0.map(\.type) })
    }

    /// The first item's data for `type`, if any item provides it.
    public func data(forType type: String) -> Data? {
        allData(forType: type).first
    }

    /// The data for `type` from every item that provides it, in item order.
    public func allData(forType type: String) -> [Data] {
        items.compactMap { item in item.first { $0.type == type }?.data }
    }
}

/// What a capture mostly is, used for its icon and title.
public enum ClipKind: String, Codable {
    case text, richText, link, image, file, color, other
}

/// The app a capture was copied from.
public struct ClipSource: Equatable {
    public let name: String?
    public let bundleID: String?

    public init(name: String?, bundleID: String?) {
        self.name = name
        self.bundleID = bundleID
    }
}

/// Lightweight description of a capture, kept in memory for listing and searching.
/// The (possibly large) payload stays in the repository until it is pasted.
public struct ClipMetadata: Codable, Equatable {
    public let id: UUID
    public var lastCopiedAt: Date
    public let sourceAppName: String?
    public let sourceBundleID: String?
    public let kind: ClipKind
    /// Single-line text shown in the list.
    public let title: String
    /// Lower-cased text matched against search queries.
    public let searchText: String
    /// Identifies captures with the same primary content, used to de-duplicate.
    public let fingerprint: String
    public let byteCount: Int
    /// Small PNG preview for images and colors.
    public let thumbnail: Data?
    public let filePaths: [String]

    public init(
        id: UUID = UUID(),
        lastCopiedAt: Date,
        source: ClipSource,
        kind: ClipKind,
        title: String,
        searchText: String,
        fingerprint: String,
        byteCount: Int,
        thumbnail: Data? = nil,
        filePaths: [String] = []
    ) {
        self.id = id
        self.lastCopiedAt = lastCopiedAt
        self.sourceAppName = source.name
        self.sourceBundleID = source.bundleID
        self.kind = kind
        self.title = title
        self.searchText = searchText
        self.fingerprint = fingerprint
        self.byteCount = byteCount
        self.thumbnail = thumbnail
        self.filePaths = filePaths
    }
}

/// Uniform type identifiers the app understands.
public enum PasteboardTypes {
    public static let plainText = "public.utf8-plain-text"
    public static let rtf = "public.rtf"
    public static let rtfd = "com.apple.flat-rtfd"
    public static let html = "public.html"
    public static let fileURL = "public.file-url"
    public static let url = "public.url"
    public static let png = "public.png"
    public static let tiff = "public.tiff"
    public static let jpeg = "public.jpeg"
    public static let heic = "public.heic"
    public static let gif = "com.compuserve.gif"
    public static let color = "com.apple.cocoa.pasteboard.color"

    /// Image types in decoding preference order.
    public static let images = [png, tiff, jpeg, heic, gif]
    public static let richText: Set<String> = [rtf, rtfd, html]
}
