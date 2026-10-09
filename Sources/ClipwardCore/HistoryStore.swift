import Foundation

/// The clipboard history: an ordered list (newest first) backed by a `HistoryRepository`.
///
/// Must be used from the main thread. Disk work runs on a private serial queue so the
/// UI never waits on encryption or file I/O, except when fetching a payload to paste.
public final class HistoryStore {
    public static let didChangeNotification = Notification.Name("Clipward.HistoryStoreDidChange")

    public private(set) var items: [ClipMetadata]

    /// Maximum number of items kept; older ones are deleted.
    public var maxItems: Int {
        didSet { if maxItems != oldValue { enforceLimits() } }
    }

    /// Items not copied for longer than this are deleted. `nil` keeps them forever.
    public var retention: TimeInterval? {
        didSet { if retention != oldValue { enforceLimits() } }
    }

    private var repository: HistoryRepository
    private let ioQueue = DispatchQueue(label: "Clipward.HistoryStore.io", qos: .utility)
    private let notificationCenter: NotificationCenter
    private let now: () -> Date

    public init(repository: HistoryRepository,
                maxItems: Int,
                retention: TimeInterval?,
                notificationCenter: NotificationCenter = .default,
                now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.maxItems = maxItems
        self.retention = retention
        self.notificationCenter = notificationCenter
        self.now = now
        items = repository.loadAllMetadata().sorted { $0.lastCopiedAt > $1.lastCopiedAt }
        enforceLimits()
    }

    /// Adds a capture at the top. An older capture with the same content is replaced.
    public func add(_ metadata: ClipMetadata, payload: ClipPayload) {
        let duplicates = items.filter { $0.fingerprint == metadata.fingerprint }.map(\.id)
        items.removeAll { $0.fingerprint == metadata.fingerprint }
        items.insert(metadata, at: 0)
        let repository = self.repository
        ioQueue.async {
            duplicates.forEach(repository.delete)
            do { try repository.save(metadata, payload: payload) } catch { NSLog("Clipward: failed to save item: \(error)") }
        }
        enforceLimits()
    }

    /// Moves an item to the top, e.g. after it was pasted from the history.
    public func markUsed(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var metadata = items.remove(at: index)
        metadata.lastCopiedAt = now()
        items.insert(metadata, at: 0)
        let repository = self.repository
        ioQueue.async { try? repository.update(metadata) }
        notifyChange()
    }

    /// Loads the full contents of an item. Waits for pending writes.
    public func payload(for id: UUID) -> ClipPayload? {
        let repository = self.repository
        return ioQueue.sync { repository.payload(for: id) }
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
        let repository = self.repository
        ioQueue.async { repository.delete(id: id) }
        notifyChange()
    }

    public func removeAll() {
        items.removeAll()
        let repository = self.repository
        ioQueue.async { repository.deleteAll() }
        notifyChange()
    }

    /// Items whose text matches every word of `query` (case-insensitive). Empty query returns all.
    public func items(matching query: String) -> [ClipMetadata] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { item in words.allSatisfy { item.searchText.contains($0) } }
    }

    /// Moves all history into `newRepository` and wipes the old one,
    /// e.g. when the user turns disk persistence on or off.
    public func replaceRepository(with newRepository: HistoryRepository) {
        let oldRepository = repository
        repository = newRepository
        let snapshot = items
        ioQueue.async {
            for metadata in snapshot {
                guard let payload = oldRepository.payload(for: metadata.id) else { continue }
                try? newRepository.save(metadata, payload: payload)
            }
            oldRepository.deleteAll()
        }
    }

    /// Deletes items beyond `maxItems` or older than `retention`.
    public func enforceLimits() {
        let cutoff = retention.map { now().addingTimeInterval(-$0) }
        var expired: [UUID] = []
        var kept: [ClipMetadata] = []
        for item in items {
            if kept.count >= maxItems || (cutoff.map { item.lastCopiedAt < $0 } ?? false) {
                expired.append(item.id)
            } else {
                kept.append(item)
            }
        }
        items = kept
        if !expired.isEmpty {
            let repository = self.repository
            ioQueue.async { expired.forEach(repository.delete) }
        }
        notifyChange()
    }

    /// Blocks until queued disk writes finish (used before quitting and in tests).
    public func flush() {
        ioQueue.sync {}
    }

    private func notifyChange() {
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }
}
