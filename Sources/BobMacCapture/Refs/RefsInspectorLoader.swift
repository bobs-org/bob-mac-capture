import AppKit
import Combine
import CryptoKit
import Foundation
import PDFKit
import RefsCore

/// PDF file facts for one reference: the page count, the cleaned
/// top-level outline headings, the lead text (up to 3 pages, capped at
/// 12k characters) summaries extract from, and the word estimate
/// reading time derives from. The thumbnail travels as PNG data so the
/// value stays `Sendable`; the loader converts it to an `NSImage` on
/// the main actor.
public struct RefsPDFIntrinsics: Equatable, Sendable {
    public var pageCount: Int?
    public var outlineHeadings: [String]
    public var leadText: String
    public var wordEstimate: Int
    public var thumbnailPNG: Data?
    public var isEncrypted: Bool
    public var failed: Bool

    public init(
        pageCount: Int? = nil,
        outlineHeadings: [String] = [],
        leadText: String = "",
        wordEstimate: Int = 0,
        thumbnailPNG: Data? = nil,
        isEncrypted: Bool = false,
        failed: Bool = false
    ) {
        self.pageCount = pageCount
        self.outlineHeadings = outlineHeadings
        self.leadText = leadText
        self.wordEstimate = wordEstimate
        self.thumbnailPNG = thumbnailPNG
        self.isEncrypted = isEncrypted
        self.failed = failed
    }

    /// The inspector's preview line when nothing rendered: nil while a
    /// thumbnail or outline is showing.
    public var previewMessage: String? {
        if isEncrypted {
            return "Preview unavailable: encrypted"
        }
        if failed {
            return "Preview unavailable"
        }
        return nil
    }
}

/// Loads PDF intrinsics behind a protocol so tests inject a stub.
public protocol RefsPDFIntrinsicsProviding: Sendable {
    func intrinsics(for pdfURL: URL, id: String) async -> RefsPDFIntrinsics
}

/// The two sides of an intrinsics load race: the first `finish`
/// wins and resumes the continuation exactly once, so a timeout
/// never waits for the abandoned read.
private final class TimeoutRace: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<RefsPDFIntrinsics, Never>

    init(_ continuation: CheckedContinuation<RefsPDFIntrinsics, Never>) {
        self.continuation = continuation
    }

    func finish(with value: RefsPDFIntrinsics) {
        lock.withLock {
            guard !done else {
                return
            }
            done = true
            continuation.resume(returning: value)
        }
    }
}

/// Reads PDF intrinsics with PDFKit: the page count, the outline (top
/// level, descending once when the root has a single child with
/// children), a page-1 thumbnail at 2x for 112 x 145 pt using the
/// crop box, lead text from up to 3 pages, and a word estimate from up
/// to 5 pages scaled by the page count. Results cache by
/// (path, fileSize, mtime) in memory (LRU of 64) and on disk
/// (`intrinsics.json` capped at 1000 entries plus a
/// `thumbs/<sha256>.png` per thumbnail), all mode 0600 in 0700
/// directories like the other Refs stores. A locked document reports
/// encrypted; a load over 3 s reports failed without waiting for the
/// abandoned read, which finishes off the actor. Failures never
/// cache, so a later selection retries.
public actor RefsPDFIntrinsicsLoader: RefsPDFIntrinsicsProviding {
    /// Lead-text cap in characters.
    public static let leadTextCap = 12_000
    /// Load timeout in nanoseconds.
    public static let loadTimeoutNanoseconds: UInt64 = 3_000_000_000
    /// Memory LRU capacity.
    public static let memoryCapacity = 64
    /// Disk entry capacity.
    public static let diskCapacity = 1_000
    /// Thumbnail size: 112 x 145 pt at 2x.
    public static let thumbnailSize = CGSize(width: 224, height: 290)

    private struct Key: Hashable, Sendable {
        var path: String
        var fileSize: UInt64
        var mtime: TimeInterval
    }

    private struct DiskEntry: Codable, Sendable {
        var pageCount: Int?
        var outlineHeadings: [String]
        var leadText: String
        var wordEstimate: Int
        var thumbSHA: String?
        var savedAt: Date
    }

    private let cacheDirectory: URL
    private let reader: @Sendable (URL) async -> RefsPDFIntrinsics
    private var memory: [Key: RefsPDFIntrinsics] = [:]
    private var memoryOrder: [Key] = []

    public init(
        cacheDirectory: URL? = nil,
        reader: (@Sendable (URL) async -> RefsPDFIntrinsics)? = nil
    ) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let base = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first
            self.cacheDirectory = (base ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("org.bobs.bob-mac-capture/refs")
        }
        self.reader = reader ?? Self.readIntrinsics
    }

    public func intrinsics(for pdfURL: URL, id: String) async -> RefsPDFIntrinsics {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: pdfURL.path
        )
        let key = Key(
            path: id,
            fileSize: (attributes?[.size] as? NSNumber)?.uint64Value ?? 0,
            mtime: (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        )
        if let cached = memory[key] {
            return cached
        }
        if let cached = readDisk(key: key) {
            remember(key: key, value: cached)
            return cached
        }
        let loaded = await loadWithTimeout(url: pdfURL)
        // A failure never caches: the timeout abandons its read, and a
        // later selection retries instead of pinning the miss.
        if !loaded.failed {
            remember(key: key, value: loaded)
            writeDisk(key: key, value: loaded)
        }
        return loaded
    }

    private func remember(key: Key, value: RefsPDFIntrinsics) {
        memory[key] = value
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
        while memoryOrder.count > Self.memoryCapacity {
            memory.removeValue(forKey: memoryOrder.removeFirst())
        }
    }

    /// Races the PDFKit read against the 3 s timeout. Both sides run
    /// in detached tasks and the first to finish resumes the
    /// continuation, so a timeout returns "Preview unavailable" after
    /// 3 s without waiting for the read, without queueing later loads
    /// behind it, and while the abandoned read finishes on its own. A
    /// task group cannot do this: leaving its scope waits for every
    /// child, including one still awaiting the abandoned read.
    private func loadWithTimeout(url: URL) async -> RefsPDFIntrinsics {
        await withCheckedContinuation { continuation in
            let race = TimeoutRace(continuation)
            let reader = self.reader
            Task.detached(priority: .utility) {
                await race.finish(with: reader(url))
            }
            Task.detached(priority: .utility) {
                try? await Task.sleep(nanoseconds: Self.loadTimeoutNanoseconds)
                race.finish(with: RefsPDFIntrinsics(failed: true))
            }
        }
    }

    private nonisolated static func readIntrinsics(url: URL) async -> RefsPDFIntrinsics {
        guard let document = PDFDocument(url: url) else {
            return RefsPDFIntrinsics(failed: true)
        }
        if document.isLocked {
            return RefsPDFIntrinsics(isEncrypted: true)
        }
        let pageCount = document.pageCount
        let outline = Self.headings(of: document)
        let leadText = Self.leadText(of: document)
        let words = Self.wordEstimate(of: document)
        let thumbnail = Self.thumbnailPNG(of: document)
        return RefsPDFIntrinsics(
            pageCount: pageCount,
            outlineHeadings: outline,
            leadText: leadText,
            wordEstimate: words,
            thumbnailPNG: thumbnail
        )
    }

    nonisolated static func headings(of document: PDFDocument) -> [String] {
        guard let root = document.outlineRoot else {
            return []
        }
        var top = (0..<root.numberOfChildren).compactMap { root.child(at: $0)?.label }
        if top.count == 1,
           let only = root.child(at: 0),
           only.numberOfChildren > 0
        {
            top = (0..<only.numberOfChildren).compactMap { only.child(at: $0)?.label }
        }
        return RefsOutline.clean(top)
    }

    nonisolated static func leadText(of document: PDFDocument) -> String {
        let pages = min(3, document.pageCount)
        var text = ""
        for index in 0..<pages {
            guard let page = document.page(at: index),
                  let string = page.string,
                  !string.isEmpty
            else {
                continue
            }
            text += string + "\n"
            if text.count >= leadTextCap {
                break
            }
        }
        return String(text.prefix(leadTextCap))
    }

    nonisolated static func wordEstimate(of document: PDFDocument) -> Int {
        let sampled = min(5, document.pageCount)
        guard sampled > 0 else {
            return 0
        }
        var words = 0
        for index in 0..<sampled {
            guard let string = document.page(at: index)?.string else {
                continue
            }
            words += string.split(whereSeparator: \.isWhitespace).count
        }
        return words * document.pageCount / sampled
    }

    nonisolated static func thumbnailPNG(of document: PDFDocument) -> Data? {
        guard let page = document.page(at: 0) else {
            return nil
        }
        let image = page.thumbnail(of: thumbnailSize, for: .cropBox)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Disk cache

    private func diskFile() -> URL {
        cacheDirectory.appendingPathComponent("intrinsics.json")
    }

    private func thumbFile(sha: String) -> URL {
        cacheDirectory.appendingPathComponent("thumbs/\(sha).png")
    }

    private func thumbSHA(key: Key) -> String {
        let raw = "\(key.path)|\(key.fileSize)|\(key.mtime)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func readDisk(key: Key) -> RefsPDFIntrinsics? {
        guard let data = try? Data(contentsOf: diskFile()),
              let entries = try? JSONDecoder().decode(
                [String: DiskEntry].self,
                from: data
              ),
              let entry = entries[diskKey(key)]
        else {
            return nil
        }
        var thumbnail: Data?
        if let sha = entry.thumbSHA {
            thumbnail = try? Data(contentsOf: thumbFile(sha: sha))
        }
        return RefsPDFIntrinsics(
            pageCount: entry.pageCount,
            outlineHeadings: entry.outlineHeadings,
            leadText: entry.leadText,
            wordEstimate: entry.wordEstimate,
            thumbnailPNG: thumbnail,
            isEncrypted: false,
            failed: false
        )
    }

    /// The cache directory and its `thumbs` child, both mode 0700
    /// like the other Refs stores. Best effort.
    private func ensureCacheDirectories() {
        for directory in [cacheDirectory, cacheDirectory.appendingPathComponent("thumbs")] {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        }
    }

    /// Locks a cache file to mode 0600. Best effort.
    private func protect(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func writeDisk(key: Key, value: RefsPDFIntrinsics) {
        guard !value.failed, !value.isEncrypted else {
            return
        }
        ensureCacheDirectories()
        var entries = (try? Data(contentsOf: diskFile())).flatMap {
            try? JSONDecoder().decode([String: DiskEntry].self, from: $0)
        } ?? [:]
        var savedThumbSHA: String?
        if let png = value.thumbnailPNG {
            let sha = thumbSHA(key: key)
            let url = thumbFile(sha: sha)
            try? png.write(to: url, options: .atomic)
            protect(url)
            savedThumbSHA = sha
        }
        entries[diskKey(key)] = DiskEntry(
            pageCount: value.pageCount,
            outlineHeadings: value.outlineHeadings,
            leadText: value.leadText,
            wordEstimate: value.wordEstimate,
            thumbSHA: savedThumbSHA,
            savedAt: Date()
        )
        while entries.count > Self.diskCapacity {
            let oldest = entries.min { $0.value.savedAt < $1.value.savedAt }?.key
            guard let oldest,
                  let removed = entries.removeValue(forKey: oldest)
            else {
                break
            }
            // An evicted entry takes its thumbnail with it, so the
            // thumbs directory cannot grow without bound.
            if let sha = removed.thumbSHA {
                try? FileManager.default.removeItem(at: thumbFile(sha: sha))
            }
        }
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: diskFile(), options: .atomic)
            protect(diskFile())
        }
    }

    private func diskKey(_ key: Key) -> String {
        "\(key.path)|\(key.fileSize)|\(key.mtime)"
    }
}

/// The inspector's hydrated content for one row: everything the basic
/// column cannot fill from the list item. All lazy, cancellable, and
/// cached by the loader below.
public struct RefsInspectorContent: Equatable, Sendable {
    public var summary: RefsSummary?
    public var outline: [String]
    public var notes: [RefsShowAnnotation]
    public var remainingNoteCount: Int
    public var openTaskCount: Int
    public var readingTime: RefsReadingTime?
    public var pageCount: Int?
    public var showFailed: Bool
    public var previewMessage: String?

    public init(
        summary: RefsSummary? = nil,
        outline: [String] = [],
        notes: [RefsShowAnnotation] = [],
        remainingNoteCount: Int = 0,
        openTaskCount: Int = 0,
        readingTime: RefsReadingTime? = nil,
        pageCount: Int? = nil,
        showFailed: Bool = false,
        previewMessage: String? = nil
    ) {
        self.summary = summary
        self.outline = outline
        self.notes = notes
        self.remainingNoteCount = remainingNoteCount
        self.openTaskCount = openTaskCount
        self.readingTime = readingTime
        self.pageCount = pageCount
        self.showFailed = showFailed
        self.previewMessage = previewMessage
    }
}

/// Hydrates the inspector for the selected row: it waits for the
/// selection to settle for 120 ms, cancels the previous load, then
/// loads intrinsics and `ref show` concurrently. `ref show` results
/// keep an LRU of 32 keyed by (id, snapshot fetch time). It publishes
/// content updates only, so the inspector fills in without re-ranking,
/// and feeds page counts and outline headings back into the library
/// signals, so rows gain `N pp` and T3 can match headings.
@MainActor
public final class RefsInspectorLoader: ObservableObject {
    /// Selection settle delay in nanoseconds.
    public static let settleDelayNanoseconds: UInt64 = 120_000_000
    /// `ref show` result LRU capacity.
    public static let showCacheCapacity = 32

    @Published public private(set) var content: [String: RefsInspectorContent] = [:]
    @Published public private(set) var thumbnails: [String: NSImage] = [:]

    private let library: RefsLibrary
    private let intrinsics: RefsPDFIntrinsicsProviding
    private var current: Task<Void, Never>?
    private var showCache: [(key: String, row: RefsShowRow)] = []
    /// Insertion order of the published content, so it stays bounded
    /// by the same LRU capacity as the show cache.
    private var contentOrder: [String] = []

    public init(
        library: RefsLibrary,
        intrinsics: RefsPDFIntrinsicsProviding = RefsPDFIntrinsicsLoader()
    ) {
        self.library = library
        self.intrinsics = intrinsics
    }

    /// The hydrated content for an id, or nil while it loads.
    public func content(for id: String) -> RefsInspectorContent? {
        content[id]
    }

    /// The thumbnail for an id, or nil while it loads.
    public func thumbnail(for id: String) -> NSImage? {
        thumbnails[id]
    }

    /// Requests hydration for an item, debouncing rapid selection
    /// movement: the previous load cancels.
    public func request(_ item: RefItem) {
        current?.cancel()
        current = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.settleDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            await self?.load(item)
        }
    }

    /// Cancels any in-flight load without publishing.
    public func cancel() {
        current?.cancel()
        current = nil
    }

    /// Clears published content (design previews reset through this).
    public func reset() {
        cancel()
        content = [:]
        thumbnails = [:]
    }

    /// Installs canned content for design tests and previews, skipping
    /// every process.
    public func installContentForPreviews(
        _ content: [String: RefsInspectorContent],
        thumbnails: [String: NSImage] = [:]
    ) {
        cancel()
        self.content = content
        self.thumbnails = thumbnails
    }

    private func load(_ item: RefItem) async {
        async let intrinsicsValue = loadIntrinsics(for: item)
        async let showValue = cachedShowRow(for: item)
        let (intrinsicsResult, showRow) = await (intrinsicsValue, showValue)
        guard !Task.isCancelled else {
            return
        }
        var built = RefsInspectorContent()
        if let intrinsicsValue = intrinsicsResult {
            built.pageCount = intrinsicsValue.pageCount
            built.outline = intrinsicsValue.outlineHeadings
            built.previewMessage = intrinsicsValue.previewMessage
            if intrinsicsValue.wordEstimate > 0, !intrinsicsValue.failed {
                built.readingTime = RefsReadingTime.estimate(
                    words: intrinsicsValue.wordEstimate
                )
            }
            // The summary excerpt is kind-gated (§10): chats get the
            // Bottom-line excerpt, papers the Abstract excerpt, and
            // every other kind no excerpt at all.
            if item.kind == .chat {
                built.summary = RefsSummaryExtractor.bottomLine(
                    fromLeadText: intrinsicsValue.leadText
                )
            } else if item.kind == .paper {
                built.summary = RefsSummaryExtractor.abstract(
                    fromLeadText: intrinsicsValue.leadText
                )
            }
            if let png = intrinsicsValue.thumbnailPNG,
               let image = NSImage(data: png)
            {
                thumbnails[item.id] = image
            }
        }
        if let row = showRow {
            built.notes = row.commentedHighlights
            built.remainingNoteCount = row.remainingCommentCount
            built.openTaskCount = row.openTasks.count
            built.showFailed = false
        } else {
            built.showFailed = true
        }
        rememberContent(id: item.id, value: built)
        var pageCounts: [String: Int] = [:]
        if let pages = built.pageCount {
            pageCounts[item.id] = pages
        }
        let headings = built.outline.isEmpty ? [:] : [item.id: built.outline]
        if !pageCounts.isEmpty || !headings.isEmpty {
            library.applyInspectorSignals(
                pageCounts: pageCounts,
                outlineHeadings: headings
            )
        }
    }

    private func loadIntrinsics(for item: RefItem) async -> RefsPDFIntrinsics? {
        guard let pdfURL = library.pdfURL(for: item) else {
            return nil
        }
        return await intrinsics.intrinsics(for: pdfURL, id: item.id)
    }

    /// Stores one row's hydrated content, evicting the oldest rows
    /// past the show-cache capacity from both the content and the
    /// thumbnail dictionaries.
    private func rememberContent(id: String, value: RefsInspectorContent) {
        content[id] = value
        contentOrder.removeAll { $0 == id }
        contentOrder.append(id)
        while contentOrder.count > Self.showCacheCapacity {
            let evicted = contentOrder.removeFirst()
            content.removeValue(forKey: evicted)
            thumbnails.removeValue(forKey: evicted)
        }
    }

    private func cachedShowRow(for item: RefItem) async -> RefsShowRow? {
        let key = "\(item.id)|\(library.snapshotFetchedAt?.timeIntervalSince1970 ?? 0)"
        if let cached = showCache.first(where: { $0.key == key }) {
            return cached.row
        }
        do {
            let response = try await library.showDetail(path: item.id)
            guard let row = response.refs.first(where: { $0.path == item.id })
                ?? response.refs.first
            else {
                return nil
            }
            showCache.append((key: key, row: row))
            while showCache.count > Self.showCacheCapacity {
                showCache.removeFirst()
            }
            return row
        } catch {
            return nil
        }
    }
}
