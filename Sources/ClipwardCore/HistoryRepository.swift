import Foundation

/// Storage for clipboard history. Metadata is loaded up front; payloads are fetched on demand.
///
/// Implementations are not thread-safe; `HistoryStore` calls them from one serial queue.
public protocol HistoryRepository: AnyObject {
    func loadAllMetadata() -> [ClipMetadata]
    func save(_ metadata: ClipMetadata, payload: ClipPayload) throws
    func update(_ metadata: ClipMetadata) throws
    func payload(for id: UUID) -> ClipPayload?
    func delete(id: UUID)
    func deleteAll()
}

/// Keeps history in memory only; nothing survives a restart.
public final class InMemoryHistoryRepository: HistoryRepository {
    private var metadata: [UUID: ClipMetadata] = [:]
    private var payloads: [UUID: ClipPayload] = [:]

    public init() {}

    public func loadAllMetadata() -> [ClipMetadata] { Array(metadata.values) }

    public func save(_ metadata: ClipMetadata, payload: ClipPayload) throws {
        self.metadata[metadata.id] = metadata
        payloads[metadata.id] = payload
    }

    public func update(_ metadata: ClipMetadata) throws {
        self.metadata[metadata.id] = metadata
    }

    public func payload(for id: UUID) -> ClipPayload? { payloads[id] }

    public func delete(id: UUID) {
        metadata[id] = nil
        payloads[id] = nil
    }

    public func deleteAll() {
        metadata.removeAll()
        payloads.removeAll()
    }
}

/// Persists each capture as two encrypted files, `<id>.meta` and `<id>.data`,
/// in a directory only the current user can read. Files that fail to decrypt
/// (tampered, or written with a different key) are discarded.
public final class EncryptedFileHistoryRepository: HistoryRepository {
    private static let metadataExtension = "meta"
    private static let payloadExtension = "data"

    private let directory: URL
    private let cipher: AuthenticatedCipher
    private let fileManager: FileManager
    private let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()
    private let decoder = PropertyListDecoder()

    public init(directory: URL, cipher: AuthenticatedCipher, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.cipher = cipher
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(excluded)
    }

    public func loadAllMetadata() -> [ClipMetadata] {
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var loaded: [ClipMetadata] = []
        var validIDs = Set<String>()
        for file in files where file.pathExtension == Self.metadataExtension {
            if let metadata: ClipMetadata = read(file) {
                loaded.append(metadata)
                validIDs.insert(metadata.id.uuidString)
            } else {
                try? fileManager.removeItem(at: file)
            }
        }
        // Payloads whose metadata is missing or unreadable are unreachable; drop them.
        for file in files where file.pathExtension == Self.payloadExtension
            && !validIDs.contains(file.deletingPathExtension().lastPathComponent) {
            try? fileManager.removeItem(at: file)
        }
        return loaded
    }

    public func save(_ metadata: ClipMetadata, payload: ClipPayload) throws {
        // Payload first, so an existing metadata file always has its payload.
        try write(payload, to: url(for: metadata.id, extension: Self.payloadExtension))
        try write(metadata, to: url(for: metadata.id, extension: Self.metadataExtension))
    }

    public func update(_ metadata: ClipMetadata) throws {
        try write(metadata, to: url(for: metadata.id, extension: Self.metadataExtension))
    }

    public func payload(for id: UUID) -> ClipPayload? {
        read(url(for: id, extension: Self.payloadExtension))
    }

    public func delete(id: UUID) {
        try? fileManager.removeItem(at: url(for: id, extension: Self.metadataExtension))
        try? fileManager.removeItem(at: url(for: id, extension: Self.payloadExtension))
    }

    public func deleteAll() {
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? fileManager.removeItem(at: $0) }
    }

    private func url(for id: UUID, extension ext: String) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(ext)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let sealed = try cipher.seal(try encoder.encode(value))
        try sealed.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func read<T: Decodable>(_ url: URL) -> T? {
        guard let sealed = try? Data(contentsOf: url),
              let plain = try? cipher.open(sealed) else { return nil }
        return try? decoder.decode(T.self, from: plain)
    }
}
