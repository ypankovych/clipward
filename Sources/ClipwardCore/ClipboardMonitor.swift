import AppKit

/// Watches the general pasteboard and reports every new copy that the capture policy allows.
///
/// macOS has no clipboard-change notification, so this polls `changeCount`
/// (a cheap integer read) a few times per second.
public final class ClipboardMonitor {
    public typealias CaptureHandler = (ClipPayload, ClipSource) -> Void

    private let pasteboard: NSPasteboard
    private let settings: AppSettings
    private let interval: TimeInterval
    private let onCapture: CaptureHandler
    private var timer: Timer?
    private var lastChangeCount: Int

    public init(pasteboard: NSPasteboard = .general, settings: AppSettings, interval: TimeInterval = 0.4, onCapture: @escaping CaptureHandler) {
        self.pasteboard = pasteboard
        self.settings = settings
        self.interval = interval
        self.onCapture = onCapture
        lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common) // keep polling while menus are open
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call right after the app itself writes to the pasteboard, so that write isn't recorded as a new copy.
    public func ignoreCurrentContents() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard !settings.isCapturePaused, let items = pasteboard.pasteboardItems, !items.isEmpty else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication.flatMap { $0 == NSRunningApplication.current ? nil : $0 }
        let source = ClipSource(name: frontmost?.localizedName, bundleID: frontmost?.bundleIdentifier)
        let policy = CapturePolicy(ignoreConfidential: settings.ignoreConfidentialContent,
                                   ignoredBundleIDs: Set(settings.ignoredBundleIDs))
        let types = Set(items.flatMap { $0.types.map(\.rawValue) })
        guard policy.allowsCapture(types: types, sourceBundleID: source.bundleID),
              let payload = readPayload(items) else { return }
        onCapture(payload, source)
    }

    private func readPayload(_ items: [NSPasteboardItem]) -> ClipPayload? {
        var totalBytes = 0
        var captured: [[ClipRepresentation]] = []
        for item in items {
            var representations: [ClipRepresentation] = []
            for type in item.types {
                guard let data = item.data(forType: type) else { continue }
                totalBytes += data.count
                if totalBytes > CapturePolicy.maxPayloadBytes {
                    NSLog("Clipward: skipped a copy larger than \(CapturePolicy.maxPayloadBytes / 1_048_576) MB")
                    return nil
                }
                representations.append(ClipRepresentation(type: type.rawValue, data: data))
            }
            if !representations.isEmpty { captured.append(representations) }
        }
        return captured.isEmpty ? nil : ClipPayload(items: captured)
    }
}
