import CaptureCore
import Foundation

/// A calendar-day ordinal parsed from `YYYY-MM-DD`: comparable and
/// timezone-free, so browse and search ordering never depends on the
/// machine's time zone.
public struct RefDay: Comparable, Codable, Equatable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(parsing text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...Self.daysIn(month: month, year: year)).contains(day)
        else {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: RefDay, rhs: RefDay) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year
        }
        if lhs.month != rhs.month {
            return lhs.month < rhs.month
        }
        return lhs.day < rhs.day
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = RefDay(parsing: text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "expected YYYY-MM-DD, got \(text)"
            )
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2:
            return isLeap(year: year) ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    private static func isLeap(year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

/// The reference kind, derived from bob's `ref_type`. The tint lives in the
/// app, keyed by kind; RefsCore only names the symbol and the scope.
public enum RefKind: Equatable, Hashable, Sendable {
    case chat
    case paper
    case article
    case doc
    case book
    case slides
    case other(raw: String?)

    public init(refType: String?) {
        switch refType {
        case "chat":
            self = .chat
        case "papers":
            self = .paper
        case "blogs":
            self = .article
        case "docs":
            self = .doc
        case "books":
            self = .book
        case "slides":
            self = .slides
        default:
            self = .other(raw: refType)
        }
    }

    public var label: String {
        switch self {
        case .chat:
            return "Chat"
        case .paper:
            return "Paper"
        case .article:
            return "Article"
        case .doc:
            return "Doc"
        case .book:
            return "Book"
        case .slides:
            return "Slides"
        case .other(let raw):
            guard let raw, !raw.isEmpty else {
                return "Reference"
            }
            return raw
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
        }
    }

    public var symbolName: String {
        switch self {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .paper:
            return "graduationcap"
        case .article:
            return "newspaper"
        case .doc:
            return "book.closed"
        case .book:
            return "books.vertical"
        case .slides:
            return "rectangle.on.rectangle"
        case .other:
            return "doc"
        }
    }

    /// The scope this kind appears under, or nil when it only appears
    /// under All.
    public var scope: RefScope? {
        switch self {
        case .chat:
            return .chats
        case .paper:
            return .papers
        case .article:
            return .articles
        case .doc:
            return .docs
        case .book, .slides, .other:
            return nil
        }
    }
}

/// The panel's scope filter: All (⌘1) plus one lane per headed kind.
public enum RefScope: Int, Equatable, CaseIterable, Sendable {
    case all = 1
    case chats = 2
    case papers = 3
    case articles = 4
    case docs = 5

    public var label: String {
        switch self {
        case .all:
            return "All"
        case .chats:
            return "Chats"
        case .papers:
            return "Papers"
        case .articles:
            return "Articles"
        case .docs:
            return "Docs"
        }
    }

    public func contains(_ kind: RefKind) -> Bool {
        switch self {
        case .all:
            return true
        case .chats:
            return kind == .chat
        case .papers:
            return kind == .paper
        case .articles:
            return kind == .article
        case .docs:
            return kind == .doc
        }
    }
}

/// The reading state. Blocked is an overlay on these lanes, not a state:
/// a blocked Next row keeps the Next lane.
public enum RefState: Equatable, Hashable, Sendable {
    case reading
    case next
    case ready
    case read
    case dropped
    case unknown

    public init(status: String?, readingState: String?) {
        switch status {
        case "wip":
            self = .reading
        case "next":
            self = .next
        case "ready":
            self = .ready
        case "read":
            self = .read
        case "abandoned":
            self = .dropped
        default:
            switch readingState {
            case "started":
                self = .reading
            case "queued":
                self = .ready
            case "finished":
                self = .read
            case "dropped":
                self = .dropped
            default:
                self = .unknown
            }
        }
    }
}

/// One library row: a decoded record plus the snapshot's git dates.
/// `id` is the note path, never the PDF path, because PDF stems repeat.
public struct RefItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let link: String
    public let rawTitle: String
    public let title: TaskDisplayText
    public let stem: String
    public let titleDisambiguator: String?
    public let markerID: RefMarkerID
    public let markerIDShareCount: Int
    public let researchRef: String?
    public let kind: RefKind
    public let state: RefState
    public let isBlocked: Bool
    public let pdfPath: String
    public let parentLabel: String?
    public let task: RefTask?
    public let author: String?
    public let published: String?
    public let added: RefDay?
    public let addedSource: String?
    /// The most precise instant known on the `added` day, or nil when
    /// only the day is known.
    public let addedAt: Date?
    public let addedIsApproximate: Bool
    public let finished: RefDay?
    public let annotationCount: Int
    public let commentCount: Int
    public let snapshotSyncedAt: String?
    public let audioPath: String?
    public let urls: [String]
    public let arxivID: String?
    public let doi: String?
    public let isAgentReport: Bool

    public init(
        id: String,
        link: String,
        rawTitle: String,
        stem: String,
        titleDisambiguator: String? = nil,
        markerID: RefMarkerID = .unsupported,
        markerIDShareCount: Int = 0,
        researchRef: String? = nil,
        kind: RefKind,
        state: RefState,
        isBlocked: Bool,
        pdfPath: String,
        parentLabel: String? = nil,
        task: RefTask? = nil,
        author: String? = nil,
        published: String? = nil,
        added: RefDay? = nil,
        addedSource: String? = nil,
        addedAt: Date? = nil,
        addedIsApproximate: Bool = false,
        finished: RefDay? = nil,
        annotationCount: Int = 0,
        commentCount: Int = 0,
        snapshotSyncedAt: String? = nil,
        audioPath: String? = nil,
        urls: [String] = [],
        arxivID: String? = nil,
        doi: String? = nil,
        isAgentReport: Bool = false
    ) {
        self.id = id
        self.link = link
        self.rawTitle = rawTitle
        self.title = TaskDisplayText(parsing: rawTitle)
        self.stem = stem
        self.titleDisambiguator = titleDisambiguator
        self.markerID = markerID
        self.markerIDShareCount = markerIDShareCount
        self.researchRef = researchRef
        self.kind = kind
        self.state = state
        self.isBlocked = isBlocked
        self.pdfPath = pdfPath
        self.parentLabel = parentLabel
        self.task = task
        self.author = author
        self.published = published
        self.added = added
        self.addedSource = addedSource
        self.addedAt = addedAt
        self.addedIsApproximate = addedIsApproximate
        self.finished = finished
        self.annotationCount = annotationCount
        self.commentCount = commentCount
        self.snapshotSyncedAt = snapshotSyncedAt
        self.audioPath = audioPath
        self.urls = urls
        self.arxivID = arxivID
        self.doi = doi
        self.isAgentReport = isAgentReport
    }
}

extension RefItem {
    static func make(
        from record: RefRecord,
        gitAddedDates: [String: String],
        gitAddedAt: [String: String] = [:],
        titleDisambiguator: String? = nil,
        markerIDShareCount: Int = 0
    ) -> RefItem? {
        guard let pdf = record.sourcePDF, !pdf.isEmpty, Self.isSafePDFPath(pdf) else {
            return nil
        }
        let added: RefDay?
        let addedSource: String?
        let addedAt: Date?
        let addedIsApproximate: Bool
        if let raw = record.added {
            added = RefDay(parsing: raw)
            addedSource = record.addedSource
            addedAt = added == nil ? nil : record.addedAt.flatMap(RefsInstant.parse)
            addedIsApproximate = record.addedSource == "git"
        } else if let gitRaw = gitAddedDates[record.path] {
            added = RefDay(parsing: gitRaw)
            addedSource = "git"
            addedAt = added == nil ? nil : gitAddedAt[record.path].flatMap(RefsInstant.parse)
            addedIsApproximate = true
        } else {
            added = nil
            addedSource = nil
            addedAt = nil
            addedIsApproximate = false
        }
        // A git-sourced `finished` date is a bulk backfill shared by hundreds
        // of rows, never a real finish date.
        let finished: RefDay?
        if record.finishedSource == "git" {
            finished = nil
        } else {
            finished = record.finished.flatMap(RefDay.init(parsing:))
        }
        return RefItem(
            id: record.path,
            link: record.link,
            rawTitle: record.title,
            stem: Self.stem(forPDFPath: pdf),
            titleDisambiguator: titleDisambiguator,
            markerID: record.reportsMarkerID
                ? (record.markerID.map(RefMarkerID.present) ?? .absent)
                : .unsupported,
            markerIDShareCount: markerIDShareCount,
            researchRef: record.researchRef,
            kind: RefKind(refType: record.refType),
            state: RefState(status: record.status, readingState: record.readingState),
            isBlocked: record.blocked,
            pdfPath: pdf,
            parentLabel: Self.parentLabel(from: record),
            task: record.task,
            author: record.author,
            published: record.published,
            added: added,
            addedSource: addedSource,
            addedAt: addedAt,
            addedIsApproximate: addedIsApproximate,
            finished: finished,
            annotationCount: record.annotationCount,
            commentCount: record.commentCount,
            snapshotSyncedAt: record.snapshotSyncedAt,
            audioPath: record.audio,
            urls: record.urls,
            arxivID: record.arxiv,
            doi: record.doi,
            isAgentReport: record.origin == "agent-report"
        )
    }

    /// Whether a stored PDF path resolves inside the vault: relative
    /// and without a `..` component. `RefsLibrary` reuses this instead
    /// of keeping its own copy.
    public static func isSafePDFPath(_ path: String) -> Bool {
        guard !path.hasPrefix("/") else {
            return false
        }
        return !path.split(separator: "/").contains("..")
    }

    /// The vault-relative file holding this reference's reading task (an
    /// area/project/inbox note, a `done/` archive, or the ref note itself
    /// for a frozen v1 tracker), or nil when bob reported no task or the
    /// path is not a safe vault-relative path.
    public var readingTaskPath: String? {
        guard let path = task?.path, !path.isEmpty, Self.isSafePDFPath(path) else {
            return nil
        }
        return path
    }

    static func stem(forPDFPath path: String) -> String {
        let last = path.split(separator: "/").last.map(String.init) ?? ""
        guard last.hasSuffix(".pdf") else {
            return last
        }
        return String(last.dropLast(4))
    }

    static func parentLabel(from record: RefRecord) -> String? {
        guard var label = record.parent else {
            return nil
        }
        label = label.replacingOccurrences(of: "[[", with: "")
        label = label.replacingOccurrences(of: "]]", with: "")
        // A v2 row's parent is already the real residence route, so it
        // keeps its full name. Only frozen v1 rows keep the legacy
        // `_ref`-stripping heuristic (`obsidian_ref` reads as `obsidian`).
        if !isV2Task(record.task, for: record.path) {
            if label.hasSuffix("_ref") {
                label = String(label.dropLast(4))
            }
        }
        return label
    }

    /// Whether a located task is a v2 reading task: its residence is a
    /// different file than the ref note itself. Frozen v1 trackers live
    /// inside their own note (`task.path == record.path`, block `ref`).
    public static func isV2Task(_ task: RefTask?, for recordPath: String) -> Bool {
        guard let task else {
            return false
        }
        return task.path != recordPath
    }

    /// The folded display title used to find collisions: case, diacritics,
    /// and width folded so identical-looking titles always collide.
    static func foldedTitle(_ title: TaskDisplayText) -> String {
        title.text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

/// Builds the sorted item list for one decoded snapshot: drops rows without
/// a usable PDF, merges git-added dates, and sets `titleDisambiguator` to
/// the stem wherever another item shares the folded display title.
public enum RefsCatalog {
    public static func items(from snapshot: RefsSnapshot) -> [RefItem] {
        var markerIDCounts: [String: Int] = [:]
        for record in snapshot.records {
            if let markerID = record.markerID {
                markerIDCounts[markerID, default: 0] += 1
            }
        }
        let prelim = snapshot.records.compactMap {
            RefItem.make(
                from: $0,
                gitAddedDates: snapshot.gitAddedDates,
                gitAddedAt: snapshot.gitAddedAt,
                markerIDShareCount: $0.markerID.map { markerIDCounts[$0, default: 0] } ?? 0
            )
        }
        var counts: [String: Int] = [:]
        for item in prelim {
            counts[RefItem.foldedTitle(item.title), default: 0] += 1
        }
        return prelim
            .map { item -> RefItem in
                guard counts[RefItem.foldedTitle(item.title), default: 0] > 1 else {
                    return item
                }
                return RefItem(
                    id: item.id,
                    link: item.link,
                    rawTitle: item.rawTitle,
                    stem: item.stem,
                    titleDisambiguator: item.stem,
                    markerID: item.markerID,
                    markerIDShareCount: item.markerIDShareCount,
                    researchRef: item.researchRef,
                    kind: item.kind,
                    state: item.state,
                    isBlocked: item.isBlocked,
                    pdfPath: item.pdfPath,
                    parentLabel: item.parentLabel,
                    task: item.task,
                    author: item.author,
                    published: item.published,
                    added: item.added,
                    addedSource: item.addedSource,
                    addedAt: item.addedAt,
                    addedIsApproximate: item.addedIsApproximate,
                    finished: item.finished,
                    annotationCount: item.annotationCount,
                    commentCount: item.commentCount,
                    snapshotSyncedAt: item.snapshotSyncedAt,
                    audioPath: item.audioPath,
                    urls: item.urls,
                    arxivID: item.arxivID,
                    doi: item.doi,
                    isAgentReport: item.isAgentReport
                )
            }
            .sorted { $0.id < $1.id }
    }
}

/// Parses the RFC 3339 instants bob reports in `added_at` and the
/// snapshot's `git_added_at`. A malformed value is nil, never an error.
enum RefsInstant {
    private static let lock = NSLock()
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return formatter.date(from: raw)
    }
}

/// One decoded snapshot plus the git-added dates the `-g` pass backfilled.
/// `gitAddedDates` maps note paths to `YYYY-MM-DD`; `gitAddedAt` maps the
/// same paths to the birth commit's RFC 3339 instant. An older cache has
/// no `git_added_at` and decodes it as empty.
public struct RefsSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var fetchedAt: Date
    public var records: [RefRecord]
    public var gitAddedDates: [String: String]
    public var gitAddedAt: [String: String]

    public init(
        schemaVersion: Int = RefsSnapshot.currentSchemaVersion,
        fetchedAt: Date,
        records: [RefRecord] = [],
        gitAddedDates: [String: String] = [:],
        gitAddedAt: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.fetchedAt = fetchedAt
        self.records = records
        self.gitAddedDates = gitAddedDates
        self.gitAddedAt = gitAddedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case fetchedAt = "fetched_at"
        case records
        case gitAddedDates = "git_added_dates"
        case gitAddedAt = "git_added_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        records = try container.decode([RefRecord].self, forKey: .records)
        gitAddedDates = try container.decode([String: String].self, forKey: .gitAddedDates)
        gitAddedAt = try container.decodeIfPresent(
            [String: String].self,
            forKey: .gitAddedAt
        ) ?? [:]
    }

    /// Note paths with no `added` date that the `-g` pass has not covered
    /// yet, plus dateless rows whose git date has no instant yet (an old
    /// cache refills once): the only rows worth a git-date refresh.
    public var pathsNeedingGitDates: [String] {
        records
            .filter {
                $0.added == nil
                    && (gitAddedDates[$0.path] == nil || gitAddedAt[$0.path] == nil)
            }
            .map(\.path)
    }

    /// This snapshot with a `-g` response merged in: for each record in
    /// `needing` that is still dateless here and that bob dated from git,
    /// the git `added` day and its `added_at` instant. Every other path,
    /// and the records themselves, are untouched.
    public func mergingGitDates(
        from records: [RefRecord],
        needing: Set<String>
    ) -> RefsSnapshot {
        let stillNeeding = Set(pathsNeedingGitDates)
        var merged = self
        for record in records {
            guard let added = record.added,
                needing.contains(record.path),
                stillNeeding.contains(record.path),
                record.addedSource == "git"
            else {
                continue
            }
            merged.gitAddedDates[record.path] = added
            if let instant = record.addedAt {
                merged.gitAddedAt[record.path] = instant
            }
        }
        return merged
    }
}
