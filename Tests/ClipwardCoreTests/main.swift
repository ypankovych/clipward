// Core logic tests. XCTest isn't available with only the Command Line Tools, so this is a
// tiny self-contained runner: `Scripts/test.sh` compiles and runs it.
import AppKit
import ClipwardCore

var failures = 0
var checks = 0

func check(_ condition: @autoclosure () throws -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if (try? condition()) != true {
        failures += 1
        print("  ✗ \(message) (line \(line))")
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    print("• \(name)")
    do { try body() } catch {
        failures += 1
        print("  ✗ threw \(error)")
    }
}

func text(_ string: String, extra: [ClipRepresentation] = []) -> ClipPayload {
    ClipPayload(items: [[ClipRepresentation(type: PasteboardTypes.plainText, data: Data(string.utf8))] + extra])
}

func pngImage(width: Int, height: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("clipward-tests-\(UUID().uuidString)")
}

let source = ClipSource(name: "Tests", bundleID: "com.example.tests")
let analyzer = ClipAnalyzer()

// MARK: - Cipher

test("cipher round-trips data of any length") {
    let cipher = try AuthenticatedCipher(key: AuthenticatedCipher.randomBytes(count: AuthenticatedCipher.keyLength))
    for length in [0, 1, 15, 16, 17, 1000, 100_000] {
        let plain = try AuthenticatedCipher.randomBytes(count: length)
        let sealed = try cipher.seal(plain)
        check(try cipher.open(sealed) == plain, "round trip for \(length) bytes")
        check(sealed != plain || length == 0, "ciphertext differs from plaintext")
    }
}

test("cipher uses a fresh IV per message") {
    let cipher = try AuthenticatedCipher(key: AuthenticatedCipher.randomBytes(count: AuthenticatedCipher.keyLength))
    let plain = Data("same message".utf8)
    check(try cipher.seal(plain) != cipher.seal(plain), "two seals of the same data differ")
}

test("cipher rejects tampering and wrong keys") {
    let key = try AuthenticatedCipher.randomBytes(count: AuthenticatedCipher.keyLength)
    let cipher = try AuthenticatedCipher(key: key)
    var sealed = try cipher.seal(Data("secret".utf8))
    sealed[20] ^= 0x01
    check((try? cipher.open(sealed)) == nil, "flipped bit is detected")

    let other = try AuthenticatedCipher(key: AuthenticatedCipher.randomBytes(count: AuthenticatedCipher.keyLength))
    check((try? other.open(try cipher.seal(Data("secret".utf8)))) == nil, "other key cannot open")
    check((try? cipher.open(Data([1, 2, 3]))) == nil, "truncated input is rejected")
    check((try? AuthenticatedCipher(key: Data(count: 10))) == nil, "short key is rejected")
}

// MARK: - Analyzer

test("plain text is classified and condensed") {
    let metadata = analyzer.metadata(for: text("  Hello\n\n   world  "), source: source)
    check(metadata.kind == .text, "kind is text")
    check(metadata.title == "Hello world", "whitespace collapsed, got '\(metadata.title)'")
    check(metadata.searchText.contains("hello"), "search text is lower-cased")
    check(metadata.sourceAppName == "Tests", "source recorded")
}

test("links, rich text and files") {
    check(analyzer.metadata(for: text("https://example.com/path?q=1"), source: source).kind == .link, "https URL is a link")
    check(analyzer.metadata(for: text("see https://example.com"), source: source).kind == .text, "sentence with URL is text")
    let rich = text("Bold", extra: [ClipRepresentation(type: PasteboardTypes.rtf, data: Data("{\\rtf1 Bold}".utf8))])
    check(analyzer.metadata(for: rich, source: source).kind == .richText, "rtf + text is rich text")

    let files = ClipPayload(items: ["/tmp/a.txt", "/tmp/b.pdf"].map {
        [ClipRepresentation(type: PasteboardTypes.fileURL, data: Data(URL(fileURLWithPath: $0).absoluteString.utf8)),
         ClipRepresentation(type: PasteboardTypes.plainText, data: Data($0.utf8))]
    })
    let metadata = analyzer.metadata(for: files, source: source)
    check(metadata.kind == .file, "file URLs win over text")
    check(metadata.filePaths == ["/tmp/a.txt", "/tmp/b.pdf"], "paths extracted, got \(metadata.filePaths)")
    check(metadata.title.hasPrefix("2 files"), "multi-file title, got '\(metadata.title)'")
}

test("images get dimensions and a thumbnail") {
    let payload = ClipPayload(items: [[ClipRepresentation(type: PasteboardTypes.png, data: pngImage(width: 640, height: 480))]])
    let metadata = analyzer.metadata(for: payload, source: source)
    check(metadata.kind == .image, "kind is image")
    check(metadata.title.contains("640 × 480"), "title has size, got '\(metadata.title)'")
    let thumbnail = metadata.thumbnail.flatMap(NSBitmapImageRep.init(data:))
    check(thumbnail != nil && max(thumbnail!.pixelsWide, thumbnail!.pixelsHigh) <= analyzer.thumbnailPixelSize, "thumbnail is small")
}

test("colors get a hex title and swatch") {
    let data = try NSKeyedArchiver.archivedData(withRootObject: NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1), requiringSecureCoding: false)
    let metadata = analyzer.metadata(for: ClipPayload(items: [[ClipRepresentation(type: PasteboardTypes.color, data: data)]]), source: source)
    check(metadata.kind == .color, "kind is color")
    check(metadata.title == "#FF8000", "hex title, got '\(metadata.title)'")
    check(metadata.thumbnail != nil, "swatch generated")
}

test("fingerprint ignores incidental extra types") {
    let a = analyzer.metadata(for: text("same"), source: source)
    let b = analyzer.metadata(for: text("same", extra: [ClipRepresentation(type: "com.example.meta", data: Data([9]))]), source: source)
    let c = analyzer.metadata(for: text("different"), source: source)
    check(a.fingerprint == b.fingerprint, "same text, same fingerprint")
    check(a.fingerprint != c.fingerprint, "different text, different fingerprint")
}

// MARK: - Capture policy

test("capture policy honours concealed types and ignored apps") {
    let policy = CapturePolicy(ignoreConfidential: true, ignoredBundleIDs: ["com.apple.keychainaccess"])
    check(policy.allowsCapture(types: [PasteboardTypes.plainText], sourceBundleID: "com.apple.Safari"), "normal copy allowed")
    check(!policy.allowsCapture(types: [PasteboardTypes.plainText, "org.nspasteboard.ConcealedType"], sourceBundleID: nil), "concealed blocked")
    check(!policy.allowsCapture(types: [PasteboardTypes.plainText], sourceBundleID: "com.apple.keychainaccess"), "ignored app blocked")
    check(!policy.allowsCapture(types: [], sourceBundleID: nil), "empty pasteboard ignored")
    let permissive = CapturePolicy(ignoreConfidential: false, ignoredBundleIDs: [])
    check(permissive.allowsCapture(types: ["org.nspasteboard.ConcealedType"], sourceBundleID: nil), "opt-out respected")
}

// MARK: - History store

func makeItem(_ string: String, at date: Date = Date()) -> (ClipMetadata, ClipPayload) {
    let payload = text(string)
    return (analyzer.metadata(for: payload, source: source, date: date), payload)
}

test("store keeps newest first and de-duplicates") {
    let store = HistoryStore(repository: InMemoryHistoryRepository(), maxItems: 10, retention: nil, notificationCenter: NotificationCenter())
    for word in ["one", "two", "three", "two"] {
        let (metadata, payload) = makeItem(word)
        store.add(metadata, payload: payload)
    }
    check(store.items.map(\.title) == ["two", "three", "one"], "order after dedupe, got \(store.items.map(\.title))")
    check(store.payload(for: store.items[0].id) == text("two"), "payload retrievable")
}

test("store enforces size and age limits") {
    var now = Date()
    let store = HistoryStore(repository: InMemoryHistoryRepository(), maxItems: 3, retention: 3_600,
                             notificationCenter: NotificationCenter(), now: { now })
    for index in 0..<5 {
        let (metadata, payload) = makeItem("item \(index)", at: now)
        store.add(metadata, payload: payload)
    }
    check(store.items.count == 3, "trimmed to maxItems")
    check(store.items.first?.title == "item 4", "newest kept")
    now = now.addingTimeInterval(7_200)
    store.enforceLimits()
    check(store.items.isEmpty, "expired after retention")
}

test("store search, markUsed and remove") {
    let store = HistoryStore(repository: InMemoryHistoryRepository(), maxItems: 10, retention: nil, notificationCenter: NotificationCenter())
    for word in ["alpha beta", "gamma", "Beta gamma"] {
        let (metadata, payload) = makeItem(word)
        store.add(metadata, payload: payload)
    }
    check(store.items(matching: "beta").count == 2, "case-insensitive search")
    check(store.items(matching: "gamma BETA").map(\.title) == ["Beta gamma"], "all words must match")
    let last = store.items.last!.id
    store.markUsed(id: last)
    check(store.items.first?.id == last, "markUsed moves to top")
    store.remove(id: last)
    check(store.items.count == 2 && !store.items.contains { $0.id == last }, "remove deletes")
}

// MARK: - Encrypted repository

test("encrypted repository persists, protects and discards foreign files") {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = try AuthenticatedCipher.randomBytes(count: AuthenticatedCipher.keyLength)
    let repository = try EncryptedFileHistoryRepository(directory: directory, cipher: AuthenticatedCipher(key: key))
    let (metadata, payload) = makeItem("top secret password-ish text")
    try repository.save(metadata, payload: payload)

    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    check(files.count == 2, "meta + data files written")
    for file in files {
        let contents = try Data(contentsOf: directory.appendingPathComponent(file))
        check(contents.range(of: Data("top secret".utf8)) == nil, "\(file) is not plaintext")
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(file).path)[.posixPermissions] as? Int
        check(permissions == 0o600, "\(file) is owner-only")
    }
    let directoryPermissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
    check(directoryPermissions == 0o700, "directory is owner-only")

    let reopened = try EncryptedFileHistoryRepository(directory: directory, cipher: AuthenticatedCipher(key: key))
    check(reopened.loadAllMetadata() == [metadata], "metadata reloads")
    check(reopened.payload(for: metadata.id) == payload, "payload reloads")

    let wrongKey = try EncryptedFileHistoryRepository(directory: directory, cipher: AuthenticatedCipher(key: AuthenticatedCipher.randomBytes(count: 64)))
    check(wrongKey.loadAllMetadata().isEmpty, "unreadable with another key")
    check(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty, "undecryptable files removed")
}

test("switching repositories migrates history and wipes the old one") {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let disk = try EncryptedFileHistoryRepository(directory: directory, cipher: AuthenticatedCipher(key: AuthenticatedCipher.randomBytes(count: 64)))
    let store = HistoryStore(repository: disk, maxItems: 10, retention: nil, notificationCenter: NotificationCenter())
    let (metadata, payload) = makeItem("migrate me")
    store.add(metadata, payload: payload)
    store.replaceRepository(with: InMemoryHistoryRepository())
    store.flush()
    check(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty, "disk wiped after switching to memory")
    check(store.payload(for: metadata.id) == payload, "payload still available from memory")
}

// MARK: - Relative time

test("relative time strings") {
    let now = Date()
    check(RelativeTime.string(for: now, now: now) == "now", "now")
    check(RelativeTime.string(for: now.addingTimeInterval(-300), now: now) == "5m ago", "minutes")
    check(RelativeTime.string(for: now.addingTimeInterval(-7_200), now: now) == "2h ago", "hours")
    check(RelativeTime.string(for: now.addingTimeInterval(-172_800), now: now) == "2d ago", "days")
}

// MARK: - Clipboard monitor and paste service (on a private pasteboard, never the user's)

func runLoop(for seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

func isolatedSettings() -> AppSettings {
    let suite = "clipward-tests-\(UUID().uuidString)"
    return AppSettings(defaults: UserDefaults(suiteName: suite)!, notificationCenter: NotificationCenter())
}

func put(_ string: String, on pasteboard: NSPasteboard, extraType: String? = nil) {
    let item = NSPasteboardItem()
    item.setString(string, forType: .string)
    if let extraType = extraType { item.setData(Data(), forType: NSPasteboard.PasteboardType(extraType)) }
    pasteboard.clearContents()
    pasteboard.writeObjects([item])
}

test("monitor records copies, skips concealed ones and its own writes") {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("clipward-tests-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    var captured: [String] = []
    let monitor = ClipboardMonitor(pasteboard: pasteboard, settings: isolatedSettings(), interval: 0.05) { payload, _ in
        captured.append(String(data: payload.data(forType: PasteboardTypes.plainText) ?? Data(), encoding: .utf8) ?? "")
    }
    monitor.start()
    put("visible", on: pasteboard)
    runLoop(for: 0.2)
    put("password", on: pasteboard, extraType: "org.nspasteboard.ConcealedType")
    runLoop(for: 0.2)
    put("own write", on: pasteboard)
    monitor.ignoreCurrentContents()
    runLoop(for: 0.2)
    monitor.stop()
    check(captured == ["visible"], "only the normal copy is recorded, got \(captured)")
}

test("paste service clears the clipboard after the timeout, unless something newer was copied") {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("clipward-tests-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    let settings = isolatedSettings()
    settings.clearClipboardAfter = 0.3
    let monitor = ClipboardMonitor(pasteboard: pasteboard, settings: settings) { _, _ in }
    let service = PasteService(pasteboard: pasteboard, settings: settings, monitor: monitor)

    service.copy(text("from history"))
    check(pasteboard.string(forType: .string) == "from history", "item written to clipboard")
    runLoop(for: 0.6)
    check(pasteboard.pasteboardItems?.isEmpty ?? true, "cleared after timeout")

    service.copy(text("from history"))
    put("user copied something newer", on: pasteboard)
    runLoop(for: 0.6)
    check(pasteboard.string(forType: .string) == "user copied something newer", "newer copy is left alone")

    let rich = text("Bold", extra: [ClipRepresentation(type: PasteboardTypes.rtf, data: Data("{\\rtf1 Bold}".utf8))])
    settings.clearClipboardAfter = 0
    service.copy(rich, plainTextOnly: true)
    check(pasteboard.data(forType: NSPasteboard.PasteboardType(PasteboardTypes.rtf)) == nil, "plain-text paste drops formatting, types: \(pasteboard.types ?? [])")
    runLoop(for: 0.4)
    check(pasteboard.string(forType: .string) == "Bold", "never-clear setting keeps the item")
}

// MARK: - Shortcuts

test("hot key shortcuts: validation, display and persistence") {
    check(HotKeyShortcut.defaultShortcut.displayString == "⌥⌘C", "default shows ⌥⌘C, got \(HotKeyShortcut.defaultShortcut.displayString)")
    check(HotKeyShortcut.defaultShortcut.menuKeyEquivalent == "c", "menu key equivalent")
    check(HotKeyShortcut(keyCode: 8, modifierFlags: []) == nil, "bare letter rejected")
    check(HotKeyShortcut(keyCode: 8, modifierFlags: .shift) == nil, "shift-only rejected")
    check(HotKeyShortcut(keyCode: 96, modifierFlags: [])?.displayString == "F5", "function key alone allowed")
    let recorded = HotKeyShortcut(keyCode: 9, modifierFlags: [.control, .shift, .command, .capsLock])
    check(recorded?.displayString == "⌃⇧⌘V", "modifier order and caps lock ignored, got \(recorded?.displayString ?? "nil")")
    check(HotKeyShortcut(keyCode: 49, modifierFlags: .option)?.displayString == "⌥Space", "space")

    let settings = isolatedSettings()
    check(settings.hotKey == .defaultShortcut, "default stored shortcut")
    settings.hotKey = recorded!
    check(settings.hotKey == recorded!, "shortcut persists")
}

print(failures == 0 ? "\nAll \(checks) checks passed." : "\n\(failures) of \(checks) checks failed.")
exit(failures == 0 ? 0 : 1)
