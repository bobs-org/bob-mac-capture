import CaptureCore
import Foundation

/// Named tuning constants for browse sections (§3) and search ranking (§4).
/// Golden tests pin behavior built on these values; see "Sorting" in the
/// README's Bob Refs section before changing any of them.
public enum RefsRankingConstants {
    /// A ready/next unopened row counts as just added within this many days.
    public static let justAddedWindowDays = 3
    /// The Just added section never shows more than this many rows.
    public static let justAddedCap = 5
    /// A read/dropped/unknown row counts as recently opened within this many days.
    public static let recentlyOpenedWindowDays = 14
    /// The Recently opened section never shows more than this many rows.
    public static let recentlyOpenedCap = 5
    /// Minimum fuzzy quality `q` for a token of 3+ characters to match.
    public static let fuzzyFloor = 0.55
    /// Score bonus when the first token's match starts at offset 0.
    public static let prefixBonus = 0.15
    /// Score bonus when every token equals a whole word.
    public static let wholeWordBonus = 0.10
    /// Lane prior for Today rows: wins over the state lane.
    public static let todayLanePrior = 0.20
    /// Lane prior for the reading state.
    public static let readingLanePrior = 0.15
    /// Lane prior for the next state.
    public static let nextLanePrior = 0.12
    /// Lane prior for the ready state.
    public static let readyLanePrior = 0.08
    /// A blocked row uses its lane's prior minus this penalty.
    public static let blockedLanePenalty = 0.02
    /// Lane prior for the dropped state. The spec's −0.10 let a dropped
    /// title-prefix match (prefix bonus +0.15) outscore a Ready non-prefix
    /// word match, failing golden expectation 3 ("sinks the dropped
    /// row"); −0.20 sinks it while keeping every other expectation's
    /// order. See "Sorting" in the README.
    public static let droppedLanePrior = -0.20
    /// Weight of the normalized frecency term.
    public static let frecencyWeight = 0.25
    /// Weight of the added-date recency term.
    public static let recencyWeight = 0.10
    /// Half-life, in days, of the per-open frecency decay.
    public static let frecencyHalfLifeDays = 14.0
    /// Half-life, in days, of the added-date recency decay.
    public static let recencyHalfLifeDays = 30.0
}

/// The signals a ranking runs against: everything `bob` and the app know
/// about the library beyond the items themselves.
public struct RefsSignals: Sendable {
    public var today: RefsToday
    public var opens: RefsOpenStats
    /// Spotlight last-used dates by note path (item id).
    public var externalLastUsed: [String: Date]
    /// PDF page counts by note path (item id).
    public var pageCounts: [String: Int]
    /// Note paths whose PDF is missing.
    public var missingPDFs: Set<String>
    /// Cached inspector outline headings by note path.
    public var outlineHeadings: [String: [String]]
    public var now: Date
    public var calendar: Calendar

    public init(
        today: RefsToday = RefsToday(),
        opens: RefsOpenStats = RefsOpenStats(events: [], now: Date()),
        externalLastUsed: [String: Date] = [:],
        pageCounts: [String: Int] = [:],
        missingPDFs: Set<String> = [],
        outlineHeadings: [String: [String]] = [:],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.today = today
        self.opens = opens
        self.externalLastUsed = externalLastUsed
        self.pageCounts = pageCounts
        self.missingPDFs = missingPDFs
        self.outlineHeadings = outlineHeadings
        self.now = now
        self.calendar = calendar
    }
}

/// One browse section, in panel order.
public enum RefsSectionKind: Equatable, CaseIterable, Sendable {
    case today
    case justAdded
    case reading
    case next
    case ready
    case recentlyOpened
    case library

    /// The pinned uppercase header title. Never "NEW": the review walk
    /// owns that chip, so the section is "Just added".
    public var title: String {
        switch self {
        case .today:
            return "Today"
        case .justAdded:
            return "Just added"
        case .reading:
            return "Reading"
        case .next:
            return "Next"
        case .ready:
            return "Ready"
        case .recentlyOpened:
            return "Recently opened"
        case .library:
            return "Library"
        }
    }
}

/// Search relevance tiers. A row's tier is its worst token's best tier,
/// and rows never cross tiers no matter their within-tier score.
public enum RefsMatchTier: Int, Comparable, Sendable {
    case exact = 0
    case word = 1
    case fuzzy = 2
    case secondary = 3

    public static func < (lhs: RefsMatchTier, rhs: RefsMatchTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Which secondary field a T3 token matched.
public enum RefsSecondaryField: String, Equatable, Sendable {
    case author
    case area
    case kind
    case heading
}

/// One secondary-field hit: the field, the text that matched, and the
/// character ranges inside that text.
public struct RefsSecondaryMatch: Equatable, Sendable {
    public let field: RefsSecondaryField
    public let text: String
    public let ranges: [Range<Int>]

    public init(field: RefsSecondaryField, text: String, ranges: [Range<Int>]) {
        self.field = field
        self.text = text
        self.ranges = ranges
    }
}

/// The `m + P + W + L + F + R` score behind one ranked row.
public struct RefsScoreBreakdown: Equatable, Sendable {
    /// Mean token quality.
    public let m: Double
    /// Prefix bonus: the first token starts at offset 0 of title or stem.
    public let p: Double
    /// Whole-word bonus: every token equals a whole word.
    public let w: Double
    /// Lane prior.
    public let l: Double
    /// Normalized frecency.
    public let f: Double
    /// Added-date recency.
    public let r: Double

    public init(m: Double, p: Double, w: Double, l: Double, f: Double, r: Double) {
        self.m = m
        self.p = p
        self.w = w
        self.l = l
        self.f = f
        self.r = r
    }

    public var total: Double {
        m + p + w + l + f + r
    }
}

/// One ranked row's match: its tier, score, and highlight ranges.
public struct RefsMatch: Equatable, Sendable {
    public let tier: RefsMatchTier
    public let score: Double
    public let breakdown: RefsScoreBreakdown
    /// Coalesced winning title alignments.
    public let titleRanges: [Range<Int>]
    /// Coalesced stem alignments, for tokens that matched only the stem.
    public let stemRanges: [Range<Int>]
    /// The secondary hit, for T3 rows.
    public let secondary: RefsSecondaryMatch?

    public init(
        tier: RefsMatchTier,
        score: Double,
        breakdown: RefsScoreBreakdown,
        titleRanges: [Range<Int>] = [],
        stemRanges: [Range<Int>] = [],
        secondary: RefsSecondaryMatch? = nil
    ) {
        self.tier = tier
        self.score = score
        self.breakdown = breakdown
        self.titleRanges = titleRanges
        self.stemRanges = stemRanges
        self.secondary = secondary
    }
}

/// One listing slice: a browse section, or the whole ranked list when
/// `kind` is nil (search mode).
public struct RefsSection: Equatable, Sendable {
    public let kind: RefsSectionKind?
    public let ids: [String]

    public init(kind: RefsSectionKind?, ids: [String]) {
        self.kind = kind
        self.ids = ids
    }
}

/// A frozen ranking: sections in panel order, the flattened row order,
/// and every search match. Selection is an id into `orderedIDs`, so a
/// content refresh can keep it stable while rows move underneath.
public struct RefsListing: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case browse
        case search(String)
    }

    public let mode: Mode
    public let scope: RefScope
    public let sections: [RefsSection]
    public let orderedIDs: [String]
    public let matches: [String: RefsMatch]
    /// Rows passing the scope filter.
    public let totalCount: Int
    /// Rows in the reading, next, or ready state (blocked included).
    public let openCount: Int
    /// Frozen ids that vanished from the latest snapshot. They keep
    /// their index in `orderedIDs` and their sections, rendered dimmed.
    /// INTERFACE CHANGE for refs-model-fixes: read this set (and
    /// `unavailableItems` for the last known titles) instead of tracking
    /// vanished ids in the panel model.
    public let unavailableIDs: Set<String>
    /// Last known content for `unavailableIDs`, so an unavailable row
    /// can still draw its title. Keyed by id; empty when the caller did
    /// not pass last-known items.
    public let unavailableItems: [String: RefItem]

    public init(
        mode: Mode,
        scope: RefScope,
        sections: [RefsSection],
        orderedIDs: [String],
        matches: [String: RefsMatch],
        totalCount: Int,
        openCount: Int,
        unavailableIDs: Set<String> = [],
        unavailableItems: [String: RefItem] = [:]
    ) {
        self.mode = mode
        self.scope = scope
        self.sections = sections
        self.orderedIDs = orderedIDs
        self.matches = matches
        self.totalCount = totalCount
        self.openCount = openCount
        self.unavailableIDs = unavailableIDs
        self.unavailableItems = unavailableItems
    }

    /// A content-only refresh of a frozen listing: late data changes row
    /// content in place but never reorders. Vanished ids keep their index
    /// and sections, marked unavailable with their last known content.
    /// A gone id is shown as unavailable — dimmed, never opening whatever
    /// row slid into its index. A fresh listing (query or scope edit, ⌘R,
    /// next open) drops them.
    public func refreshingContent(
        availableIDs: Set<String>,
        lastKnownItems: [String: RefItem] = [:]
    ) -> (listing: RefsListing, unavailable: Set<String>) {
        let unavailable = Set(orderedIDs).subtracting(availableIDs)
            .union(unavailableIDs.subtracting(availableIDs))
        var mergedUnavailableItems = unavailableItems
        for (id, item) in lastKnownItems where unavailable.contains(id) {
            mergedUnavailableItems[id] = item
        }
        return (
            RefsListing(
                mode: mode,
                scope: scope,
                sections: sections,
                orderedIDs: orderedIDs,
                matches: matches,
                totalCount: totalCount,
                openCount: openCount,
                unavailableIDs: unavailable,
                unavailableItems: mergedUnavailableItems
            ),
            unavailable
        )
    }
}

/// Merges sorted positions into ranges of consecutive offsets, copied
/// from capture's `ActiveTaskMatchHighlights.coalesced` (internal there).
public enum RefsHighlights {
    public static func coalesced(_ positions: [Int]) -> [Range<Int>] {
        let sorted = Array(Set(positions)).sorted()
        var ranges: [Range<Int>] = []
        var start = 0
        while start < sorted.count {
            var end = start
            while end + 1 < sorted.count, sorted[end + 1] == sorted[end] + 1 {
                end += 1
            }
            ranges.append(sorted[start]..<sorted[end] + 1)
            start = end + 1
        }
        return ranges
    }
}

// MARK: - Shared text and date helpers

/// One folded word with its character range in the folded text.
struct RefsFoldedWord {
    let text: String
    let range: Range<Int>
}

enum RefsText {
    /// Per-character folding identical to `FuzzyMatcher`: case,
    /// diacritics, and width are ignored, and indices stay 1:1 with the
    /// original text so highlight offsets map directly onto it.
    static func foldedCharacter(_ c: Character) -> Character {
        let folded = String(c).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
        if folded.count == 1, let single = folded.first {
            return single
        }
        return c.lowercased().first ?? c
    }

    static func folded(_ text: String) -> String {
        if text.unicodeScalars.allSatisfy({ $0.isASCII }) {
            return text.lowercased()
        }
        let whole = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
        if whole.count == text.count {
            return whole
        }
        return String(text.map(foldedCharacter))
    }

    /// The spec's query normalization: split on whitespace, split each
    /// token on `_ - / . :`, strip leading and trailing non-alphanumerics
    /// (so `` `%auto` `` becomes `auto`), and drop empty pieces. No
    /// pieces means browse order.
    static func queryTokens(_ query: String) -> [String] {
        var pieces: [String] = []
        for raw in query.split(whereSeparator: { $0.isWhitespace }) {
            for part in String(raw).split(whereSeparator: { "_-/.:".contains($0) }) {
                var token = folded(String(part))
                while let first = token.first, !first.isLetter, !first.isNumber {
                    token.removeFirst()
                }
                while let last = token.last, !last.isLetter, !last.isNumber {
                    token.removeLast()
                }
                if !token.isEmpty {
                    pieces.append(token)
                }
            }
        }
        return pieces
    }

    /// Maximal letter-or-digit runs of folded text, with ranges.
    static func words(inFolded folded: String) -> [RefsFoldedWord] {
        let chars = Array(folded)
        var out: [RefsFoldedWord] = []
        var index = 0
        while index < chars.count {
            guard chars[index].isLetter || chars[index].isNumber else {
                index += 1
                continue
            }
            var end = index
            while end < chars.count, chars[end].isLetter || chars[end].isNumber {
                end += 1
            }
            out.append(RefsFoldedWord(
                text: String(chars[index..<end]),
                range: index..<end
            ))
            index = end
        }
        return out
    }

    /// Kind words for secondary matching.
    static func kindWords(_ kind: RefKind) -> [String] {
        switch kind {
        case .chat:
            return ["chat", "agent", "report"]
        case .paper:
            return ["paper"]
        case .article:
            return ["article", "blog"]
        case .doc:
            return ["doc", "docs"]
        case .book, .slides, .other:
            return []
        }
    }
}

enum RefsDates {
    /// Timezone-free day ordinal for a `RefDay` (days from civil).
    static func ordinal(year: Int, month: Int, day: Int) -> Int {
        var y = year
        y -= month <= 2 ? 1 : 0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe
    }

    static func ordinal(_ day: RefDay) -> Int {
        ordinal(year: day.year, month: day.month, day: day.day)
    }

    /// A `RefDay` on the Unix-day scale, so it compares directly with
    /// instant ordinals. Differences are identical on either scale, but
    /// `max()` across days and instants needs one shared scale.
    static func unixOrdinal(_ day: RefDay) -> Int {
        ordinal(day) - ordinal(year: 1970, month: 1, day: 1)
    }

    /// Timezone-free day ordinal for an instant (UTC days).
    static func ordinal(_ date: Date) -> Int {
        Int(floor(date.timeIntervalSince1970 / 86_400))
    }

    /// Local day ordinal for an instant in `calendar`: the civil
    /// year/month/day in that calendar's time zone, on the Unix-day
    /// scale so it compares directly with `unixOrdinal(RefDay)`.
    static func ordinal(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents(
            [.year, .month, .day], from: date
        )
        guard let year = parts.year, let month = parts.month,
            let day = parts.day
        else {
            return ordinal(date)
        }
        return ordinal(year: year, month: month, day: day)
            - ordinal(year: 1970, month: 1, day: 1)
    }
}

// MARK: - Ranker

/// Browse sections and tiered search over one item set. The scope filter
/// applies first; identical inputs always produce identical order (the
/// final tie-break everywhere is id ascending).
public enum RefsRanker {
    /// Ranks items for a query and scope. An empty or whitespace-only
    /// query yields browse sections; anything else yields one ranked list.
    public static func listing(
        _ items: [RefItem],
        query: String,
        scope: RefScope,
        signals: RefsSignals
    ) -> RefsListing {
        let scoped = items.filter { scope.contains($0.kind) }
        let openStates: Set<RefState> = [.reading, .next, .ready]
        let openCount = scoped.filter { openStates.contains($0.state) }.count
        let tokens = RefsText.queryTokens(query)
        if tokens.isEmpty {
            let sections = browseSections(scoped, signals: signals)
            return RefsListing(
                mode: .browse,
                scope: scope,
                sections: sections,
                orderedIDs: sections.flatMap(\.ids),
                matches: [:],
                totalCount: scoped.count,
                openCount: openCount
            )
        }
        let ranked = searchRows(scoped, tokens: tokens, rawQuery: query, signals: signals)
        let ids = ranked.map(\.id)
        let matches = Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0.match) })
        return RefsListing(
            mode: .search(query),
            scope: scope,
            sections: ids.isEmpty ? [] : [RefsSection(kind: nil, ids: ids)],
            orderedIDs: ids,
            matches: matches,
            totalCount: scoped.count,
            openCount: openCount
        )
    }

    /// True when the item is unopened: ready or next (blocked included),
    /// no open-log event, no Spotlight last-used date, and no annotations.
    public static func isUnopened(_ item: RefItem, signals: RefsSignals) -> Bool {
        (item.state == .ready || item.state == .next)
            && signals.opens.count(item.id) == 0
            && signals.externalLastUsed[item.id] == nil
            && item.annotationCount == 0
    }

    /// "Last opened": the newest of the picker open log and Spotlight.
    public static func lastOpened(_ item: RefItem, signals: RefsSignals) -> Date? {
        let logged = signals.opens.lastOpened(item.id)
        let external = signals.externalLastUsed[item.id]
        switch (logged, external) {
        case let (a?, b?):
            return max(a, b)
        case let (a?, nil):
            return a
        case let (nil, b?):
            return b
        case (nil, nil):
            return nil
        }
    }

    /// The lane prior `L`: Today wins over the state lane; a blocked row
    /// uses its lane's prior minus the blocked penalty.
    public static func lanePrior(_ item: RefItem, signals: RefsSignals) -> Double {
        if signals.today.entries[item.id] != nil {
            return RefsRankingConstants.todayLanePrior
        }
        let base: Double
        switch item.state {
        case .reading:
            base = RefsRankingConstants.readingLanePrior
        case .next:
            base = RefsRankingConstants.nextLanePrior
        case .ready:
            base = RefsRankingConstants.readyLanePrior
        case .read, .unknown:
            base = 0
        case .dropped:
            base = RefsRankingConstants.droppedLanePrior
        }
        if item.isBlocked {
            return base - RefsRankingConstants.blockedLanePenalty
        }
        return base
    }

    // MARK: Browse

    static func browseSections(_ scoped: [RefItem], signals: RefsSignals) -> [RefsSection] {
        let todayOrdinal = RefsDates.ordinal(
            signals.now, calendar: signals.calendar
        )
        var placed: Set<String> = []
        var sections: [RefsSection] = []

        func take(_ kind: RefsSectionKind, ids: [String]) {
            guard !ids.isEmpty else {
                return
            }
            placed.formUnion(ids)
            sections.append(RefsSection(kind: kind, ids: ids))
        }

        // Today, in ledger order.
        let todayIDs = scoped
            .filter { signals.today.entries[$0.id] != nil }
            .sorted {
                let a = signals.today.entries[$0.id]?.order ?? Int.max
                let b = signals.today.entries[$1.id]?.order ?? Int.max
                if a != b {
                    return a < b
                }
                return $0.id < $1.id
            }
            .map(\.id)
        take(.today, ids: todayIDs)

        // Just added: ready/next, unopened, added within the window.
        let justAddedCandidates = scoped
            .filter { !placed.contains($0.id) }
            .filter {
                ($0.state == .ready || $0.state == .next)
                    && isUnopened($0, signals: signals)
                    && $0.added.map {
                        todayOrdinal - RefsDates.unixOrdinal($0)
                            <= RefsRankingConstants.justAddedWindowDays
                    } ?? false
            }
            .sorted {
                compareAddedDesc($0, $1) ?? ($0.id < $1.id)
            }
        let justAddedIDs = justAddedCandidates.prefix(RefsRankingConstants.justAddedCap).map(\.id)
        take(.justAdded, ids: justAddedIDs)

        // Reading.
        take(.reading, ids: browseLane(
            scoped, placed: placed, signals: signals,
            states: [.reading], blockedLast: false, todayOrdinal: todayOrdinal
        ).map(\.id))

        // Next, blocked rows last.
        let nextIDs = browseLane(
            scoped, placed: placed, signals: signals,
            states: [.next], blockedLast: true, todayOrdinal: todayOrdinal
        ).map(\.id)
        placed.formUnion(nextIDs)
        if !nextIDs.isEmpty {
            sections.append(RefsSection(kind: .next, ids: nextIDs))
        }

        // Ready (§3): added desc, blocked rows last, id tie-break.
        let readyIDs = readyLane(
            scoped, placed: placed, states: [.ready]
        ).map(\.id)
        placed.formUnion(readyIDs)
        if !readyIDs.isEmpty {
            sections.append(RefsSection(kind: .ready, ids: readyIDs))
        }

        // Recently opened: read/dropped/unknown, opened within the window.
        let recentCandidates = scoped
            .filter { !placed.contains($0.id) }
            .filter {
                ($0.state == .read || $0.state == .dropped || $0.state == .unknown)
                    && lastOpened($0, signals: signals).map {
                        todayOrdinal
                            - RefsDates.ordinal(
                                $0, calendar: signals.calendar
                            )
                            <= RefsRankingConstants.recentlyOpenedWindowDays
                    } ?? false
            }
            .sorted {
                compareOpenedDesc($0, $1, signals: signals) ?? ($0.id < $1.id)
            }
        let recentIDs = recentCandidates.prefix(RefsRankingConstants.recentlyOpenedCap).map(\.id)
        take(.recentlyOpened, ids: recentIDs)

        // Library: everything else, by last activity.
        let libraryIDs = scoped
            .filter { !placed.contains($0.id) }
            .sorted {
                compareActivityDesc($0, $1, signals: signals) ?? ($0.id < $1.id)
            }
            .map(\.id)
        take(.library, ids: libraryIDs)

        return sections
    }

    /// One state lane in browse mode: last opened desc (nil last),
    /// then added desc, then id. Blocked rows sort last when asked.
    /// `todayOrdinal` is unused and kept only for call-site stability.
    static func browseLane(
        _ scoped: [RefItem],
        placed: Set<String>,
        signals: RefsSignals,
        states: Set<RefState>,
        blockedLast: Bool,
        todayOrdinal: Int = 0
    ) -> [RefItem] {
        scoped
            .filter { !placed.contains($0.id) && states.contains($0.state) }
            .sorted {
                if blockedLast, $0.isBlocked != $1.isBlocked {
                    return !$0.isBlocked
                }
                if let compared = compareOpenedDesc($0, $1, signals: signals) {
                    return compared
                }
                return compareAddedDesc($0, $1) ?? ($0.id < $1.id)
            }
    }

    /// The Ready lane (§3): added desc, blocked rows last, id tie-break.
    /// Next and Reading keep last-opened-then-added; Ready does not.
    static func readyLane(
        _ scoped: [RefItem],
        placed: Set<String>,
        states: Set<RefState>
    ) -> [RefItem] {
        scoped
            .filter { !placed.contains($0.id) && states.contains($0.state) }
            .sorted {
                if $0.isBlocked != $1.isBlocked {
                    return !$0.isBlocked
                }
                return compareAddedDesc($0, $1) ?? ($0.id < $1.id)
            }
    }

    /// Newer last-opened first, nil last. Nil when equal.
    static func compareOpenedDesc(_ a: RefItem, _ b: RefItem, signals: RefsSignals) -> Bool? {
        switch (lastOpened(a, signals: signals), lastOpened(b, signals: signals)) {
        case let (x?, y?):
            if x != y {
                return x > y
            }
            return nil
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return nil
        }
    }

    /// Newer added first, nil last. Nil when equal.
    static func compareAddedDesc(_ a: RefItem, _ b: RefItem) -> Bool? {
        switch (a.added, b.added) {
        case let (x?, y?):
            if x != y {
                return x > y
            }
            return nil
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return nil
        }
    }

    /// Last activity: `max(added, last-opened day, finished)` on the
    /// Unix-day scale, nil last. Opened days use `signals.calendar`.
    static func activityOrdinal(_ item: RefItem, signals: RefsSignals) -> Int? {
        var best: Int?
        if let added = item.added {
            best = RefsDates.unixOrdinal(added)
        }
        if let finished = item.finished {
            best = max(best ?? Int.min, RefsDates.unixOrdinal(finished))
        }
        if let opened = lastOpened(item, signals: signals) {
            best = max(
                best ?? Int.min,
                RefsDates.ordinal(opened, calendar: signals.calendar)
            )
        }
        return best
    }

    static func compareActivityDesc(_ a: RefItem, _ b: RefItem, signals: RefsSignals) -> Bool? {
        switch (activityOrdinal(a, signals: signals), activityOrdinal(b, signals: signals)) {
        case let (x?, y?):
            if x != y {
                return x > y
            }
            return nil
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return nil
        }
    }

    // MARK: Search

    struct RankedRow {
        let id: String
        let match: RefsMatch
        let titleCount: Int
        let added: RefDay?
    }

    /// One ranked list: every token must match somewhere (AND); a row's
    /// tier is its worst token's best tier; rows never cross tiers.
    /// Ties break on shorter display title, newer added, then id.
    static func searchRows(
        _ scoped: [RefItem],
        tokens: [String],
        rawQuery: String,
        signals: RefsSignals
    ) -> [RankedRow] {
        // Prepared items come from a per-snapshot cache, so repeated
        // listings over the same snapshot never rebuild mid-keystroke.
        let prepared = RefsPreparedCache.prepared(
            for: scoped, signals: signals
        )
        let selfScores = Dictionary(
            uniqueKeysWithValues: tokens.map { ($0, selfScore($0)) }
        )
        let foldedTokens = Dictionary(
            uniqueKeysWithValues: tokens.map { ($0, Array(RefsText.folded($0))) }
        )
        let normalizedQuery = normalizedWholeQuery(rawQuery)
        var rows: [RankedRow] = []
        for candidate in prepared {
            if let row = rankItem(
                candidate, tokens: tokens, rawQuery: rawQuery,
                normalizedQuery: normalizedQuery,
                selfScores: selfScores, foldedTokens: foldedTokens,
                signals: signals
            ) {
                rows.append(row)
            }
        }
        return rows.sorted {
            if $0.match.tier != $1.match.tier {
                return $0.match.tier < $1.match.tier
            }
            if $0.match.score != $1.match.score {
                return $0.match.score > $1.match.score
            }
            if $0.titleCount != $1.titleCount {
                return $0.titleCount < $1.titleCount
            }
            switch ($0.added, $1.added) {
            case let (x?, y?):
                if x != y {
                    return x > y
                }
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                break
            }
            return $0.id < $1.id
        }
    }

    /// `FuzzyMatcher` score of a token against itself: the quality
    /// denominator `q(token) = min(1, best ÷ self)`.
    static func selfScore(_ token: String) -> Double {
        Double(FuzzyMatcher.match(token: token, in: FuzzyField(token))?.score ?? 1)
    }

    static func rankItem(
        _ prepared: RefsPreparedItem,
        tokens: [String],
        rawQuery: String,
        normalizedQuery: String,
        selfScores: [String: Double],
        foldedTokens: [String: [Character]],
        signals: RefsSignals
    ) -> RankedRow? {
        let item = prepared.item
        // T0 identity: a pasted arXiv id, DOI, or URL selects its row.
        // Rows without identity fields can never match; skipping them
        // avoids per-row copies and the arXiv pattern check.
        if item.arxivID != nil || item.doi != nil || !item.urls.isEmpty,
            matchIdentity(rawQuery, item: item)
        {
            let breakdown = scoreBreakdown(
                item: item, qualities: [],
                firstStartsAtZero: false, wholeWord: false,
                signals: signals, exactMean: true
            )
            let match = RefsMatch(
                tier: .exact, score: breakdown.total, breakdown: breakdown
            )
            return RankedRow(
                id: item.id, match: match,
                titleCount: item.title.text.count, added: item.added
            )
        }
        // T0 equality: the normalized whole query equals the folded
        // title or stem.
        if isExactTitleQuery(normalizedQuery, prepared: prepared) {
            var wholeWord = true
            for token in tokens {
                guard prepared.isWholeWord(token) else {
                    wholeWord = false
                    break
                }
            }
            let breakdown = scoreBreakdown(
                item: item, qualities: [],
                firstStartsAtZero: true, wholeWord: wholeWord,
                signals: signals, exactMean: true
            )
            var titleRanges: [Range<Int>] = []
            var stemRanges: [Range<Int>] = []
            if prepared.foldedTitle == normalizedQuery {
                titleRanges = [0..<item.title.text.count]
            } else {
                stemRanges = [0..<item.stem.count]
            }
            let match = RefsMatch(
                tier: .exact, score: breakdown.total, breakdown: breakdown,
                titleRanges: titleRanges, stemRanges: stemRanges
            )
            return RankedRow(
                id: item.id, match: match,
                titleCount: item.title.text.count, added: item.added
            )
        }

        var tier = RefsMatchTier.exact
        var qualities: [Double] = []
        var titlePositions: [Int] = []
        var stemPositions: [Int] = []
        var firstStartsAtZero = false
        var wholeWord = true
        var secondary: RefsSecondaryMatch?
        for (index, token) in tokens.enumerated() {
            guard let hit = prepared.bestHit(
                token, tokenFolded: foldedTokens[token] ?? Array(token),
                selfScore: selfScores[token] ?? 1, signals: signals
            ) else {
                return nil
            }
            tier = max(tier, hit.tier)
            qualities.append(hit.quality)
            if index == 0 {
                firstStartsAtZero = hit.startsAtZero && hit.tier != .secondary
            }
            if hit.tier == .secondary || !hit.isWholeWord {
                wholeWord = false
            }
            switch hit.place {
            case let .title(positions):
                titlePositions.append(contentsOf: positions)
            case let .stem(positions):
                stemPositions.append(contentsOf: positions)
            case let .secondary(match):
                if secondary == nil {
                    secondary = match
                }
            }
        }
        let breakdown = scoreBreakdown(
            item: item, qualities: qualities,
            firstStartsAtZero: firstStartsAtZero, wholeWord: wholeWord,
            signals: signals, exactMean: false
        )
        let match = RefsMatch(
            tier: tier, score: breakdown.total, breakdown: breakdown,
            titleRanges: titlePositions.isEmpty ? [] : RefsHighlights.coalesced(titlePositions),
            stemRanges: stemPositions.isEmpty ? [] : RefsHighlights.coalesced(stemPositions),
            secondary: tier == .secondary ? secondary : nil
        )
        return RankedRow(
            id: item.id, match: match,
            titleCount: item.title.text.count, added: item.added
        )
    }

    static func scoreBreakdown(
        item: RefItem,
        qualities: [Double],
        firstStartsAtZero: Bool,
        wholeWord: Bool,
        signals: RefsSignals,
        exactMean: Bool
    ) -> RefsScoreBreakdown {
        let m = exactMean ? 1 : qualities.reduce(0, +) / Double(max(qualities.count, 1))
        let p = firstStartsAtZero ? RefsRankingConstants.prefixBonus : 0
        let w = wholeWord ? RefsRankingConstants.wholeWordBonus : 0
        let l = lanePrior(item, signals: signals)
        let f: Double = {
            let fMax = signals.opens.maxFrecency
            guard fMax > 0 else {
                return 0
            }
            return RefsRankingConstants.frecencyWeight
                * log1p(signals.opens.frecency(item.id)) / log1p(fMax)
        }()
        let r: Double = {
            guard let added = item.added else {
                return 0
            }
            let daysSince = max(
                0,
                RefsDates.ordinal(signals.now, calendar: signals.calendar)
                    - RefsDates.unixOrdinal(added)
            )
            return RefsRankingConstants.recencyWeight
                * pow(0.5, Double(daysSince) / RefsRankingConstants.recencyHalfLifeDays)
        }()
        return RefsScoreBreakdown(m: m, p: p, w: w, l: l, f: f, r: r)
    }

    // MARK: T0 helpers

    /// Collapsed, folded whole-query form for exact comparison.
    static func normalizedWholeQuery(_ query: String) -> String {
        RefsText.folded(query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))
    }

    static func isExactTitleQuery(_ normalized: String, prepared: RefsPreparedItem) -> Bool {
        !normalized.isEmpty
            && (prepared.foldedTitle == normalized || prepared.foldedStem == normalized)
    }

    /// An arXiv id (case-insensitive, `arxiv:` prefix and `vN` suffix
    /// ignored), a DOI (case-insensitive), or a URL (scheme, `www.`, and
    /// trailing `/` ignored).
    static func matchIdentity(_ query: String, item: RefItem) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        if let arxiv = item.arxivID {
            let wanted = normalizeArxiv(trimmed)
            if !wanted.isEmpty, wanted == normalizeArxiv(arxiv) {
                return true
            }
        }
        if let doi = item.doi,
            trimmed.lowercased() == doi.lowercased()
        {
            return true
        }
        let normalizedQuery = normalizeURL(trimmed)
        if !normalizedQuery.isEmpty {
            for url in item.urls {
                if normalizeURL(url) == normalizedQuery {
                    return true
                }
            }
        }
        return false
    }

    static func normalizeArxiv(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("arxiv:") {
            value = String(value.dropFirst("arxiv:".count))
        }
        if let slash = value.range(of: "v\\d+$", options: .regularExpression) {
            value.removeSubrange(slash)
        }
        return value
    }

    static func normalizeURL(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = value.range(of: "://") {
            value = String(value[scheme.upperBound...])
        }
        if value.hasPrefix("www.") {
            value = String(value.dropFirst("www.".count))
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}

// MARK: - Prepared items

/// Where one token matched.
enum RefsHitPlace {
    case title([Int])
    case stem([Int])
    case secondary(RefsSecondaryMatch)
}

/// One token's best hit in a row.
struct RefsTokenHit {
    let tier: RefsMatchTier
    let quality: Double
    let place: RefsHitPlace
    let startsAtZero: Bool
    let isWholeWord: Bool
}

/// One searchable field: folded characters, original characters, and
/// boundary bonuses, all index-aligned and truncated exactly like
/// `FuzzyField`, plus the word list. A `FuzzyField` is built lazily
/// only for fuzzy-tier winners that need highlight positions.
struct RefsSearchField {
    let folded: [Character]
    let bonuses: [Int]
    let words: [RefsFoldedWord]
    let raw: String

    init(_ text: String) {
        let truncated = String(text.prefix(FuzzyMatcher.maxFieldLength))
        let bytes = Array(truncated.utf8)
        if bytes.allSatisfy({ $0 < 0x80 }) {
            self.init(ascii: truncated, bytes: bytes)
        } else {
            self.init(general: truncated)
        }
    }

    /// Byte-based build for ASCII text: byte offsets equal character
    /// offsets, and every byte test below matches its `Character`
    /// property exactly on ASCII bytes, so the result is identical to
    /// the general path with none of the Unicode property lookups.
    private init(ascii text: String, bytes: [UInt8]) {
        self.raw = text
        var folded: [Character] = []
        folded.reserveCapacity(bytes.count)
        var bonuses: [Int] = []
        bonuses.reserveCapacity(bytes.count)
        var words: [RefsFoldedWord] = []
        var wordStart: Int?
        var wordBytes: [UInt8] = []
        func lower(_ byte: UInt8) -> UInt8 {
            (byte >= 65 && byte <= 90) ? byte + 32 : byte
        }
        for index in bytes.indices {
            let byte = bytes[index]
            folded.append(Character(UnicodeScalar(lower(byte))))
            let bonus: Int
            if index == 0 {
                bonus = FuzzyMatcher.startBoundaryBonus
            } else {
                let prev = bytes[index - 1]
                let prevLetter = (prev >= 65 && prev <= 90) || (prev >= 97 && prev <= 122)
                let prevDigit = prev >= 48 && prev <= 57
                let byteLetter = (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
                let byteDigit = byte >= 48 && byte <= 57
                if !(prevLetter || prevDigit) {
                    bonus = FuzzyMatcher.separatorBoundaryBonus
                } else if prev >= 97 && prev <= 122 && byte >= 65 && byte <= 90 {
                    bonus = FuzzyMatcher.transitionBoundaryBonus
                } else if (prevLetter && byteDigit) || (prevDigit && byteLetter) {
                    bonus = FuzzyMatcher.transitionBoundaryBonus
                } else {
                    bonus = 0
                }
            }
            bonuses.append(bonus)
            let isUpper = byte >= 65 && byte <= 90
            let isLower = byte >= 97 && byte <= 122
            let isDigit = byte >= 48 && byte <= 57
            if isUpper || isLower || isDigit {
                if wordStart == nil {
                    wordStart = index
                    wordBytes = []
                }
                wordBytes.append(lower(byte))
            } else if let start = wordStart {
                let word = String(bytes: wordBytes, encoding: .utf8) ?? ""
                words.append(RefsFoldedWord(text: word, range: start..<index))
                wordStart = nil
            }
        }
        if let start = wordStart {
            let word = String(bytes: wordBytes, encoding: .utf8) ?? ""
            words.append(RefsFoldedWord(text: word, range: start..<bytes.count))
        }
        self.folded = folded
        self.bonuses = bonuses
        self.words = words
    }

    private init(general text: String) {
        let chars = Array(text)
        self.raw = text
        self.folded = chars.map(RefsText.foldedCharacter)
        self.bonuses = chars.indices.map {
            RefsFuzzyScore.boundaryBonus(at: $0, in: chars)
        }
        self.words = RefsText.words(inFolded: String(self.folded))
    }
}

/// Score-only fuzzy matching: `FuzzyMatcher`'s recurrence with only the
/// maximum tracked. Tie-breaks in the full matcher choose among equal
/// scores, so the maximum here always equals
/// `FuzzyMatcher.match(token:in:).score` — without the backtracking
/// matrix, which dominates ranking cost in unoptimized builds.
enum RefsFuzzyScore {
    /// The boundary rule, mirroring `FuzzyMatcher` over the original
    /// (unfolded) characters.
    static func boundaryBonus(at index: Int, in chars: [Character]) -> Int {
        if index == 0 {
            return FuzzyMatcher.startBoundaryBonus
        }
        let previous = chars[index - 1]
        let current = chars[index]
        if previous.isWhitespace || !(previous.isLetter || previous.isNumber) {
            return FuzzyMatcher.separatorBoundaryBonus
        }
        if previous.isLowercase && current.isUppercase {
            return FuzzyMatcher.transitionBoundaryBonus
        }
        if (previous.isLetter && current.isNumber) || (previous.isNumber && current.isLetter) {
            return FuzzyMatcher.transitionBoundaryBonus
        }
        return 0
    }

    static func bestScore(token: [Character], field: RefsSearchField) -> Int? {
        token.withUnsafeBufferPointer { t in
            field.folded.withUnsafeBufferPointer { f in
                field.bonuses.withUnsafeBufferPointer { b in
                    scoreImpl(token: t, folded: f, bonuses: b)
                }
            }
        }
    }

    /// The hot loop over one token and field. Pointer arithmetic is
    /// unchecked, so every index below is bounded by construction:
    /// `i` ranges over the token, `j` over the field, and `j - 2` only
    /// runs when `j >= 2`. The recurrence is verbatim `FuzzyMatcher`'s,
    /// so the maximum equals its alignment score.
    private static func scoreImpl(
        token: UnsafeBufferPointer<Character>,
        folded: UnsafeBufferPointer<Character>,
        bonuses: UnsafeBufferPointer<Int>
    ) -> Int? {
        let need = token.count
        let avail = folded.count
        guard need > 0, need <= avail else {
            return need == 0 ? 0 : nil
        }
        guard let tb = token.baseAddress, let fb = folded.baseAddress,
            let bb = bonuses.baseAddress
        else {
            return nil
        }
        // Int.min stands in for nil; every real score stays within a
        // few thousand of zero, so no addition below can overflow.
        let impossible = Int.min
        let matchPoints = FuzzyMatcher.matchPoints
        let consecutiveBonus = FuzzyMatcher.consecutiveBonus
        var prev = [Int](repeating: impossible, count: avail)
        var curr = [Int](repeating: impossible, count: avail)
        return prev.withUnsafeMutableBufferPointer { pBuf in
            curr.withUnsafeMutableBufferPointer { cBuf in
                guard var read = pBuf.baseAddress, var write = cBuf.baseAddress else {
                    return nil
                }
                for i in 0..<need {
                    let wanted = tb[i]
                    var run = impossible
                    if i == 0 {
                        for j in 0..<avail where fb[j] == wanted {
                            write[j] = matchPoints + 2 * bb[j]
                        }
                    } else {
                        for j in 0..<avail {
                            if j >= 2 {
                                let source = read[j - 2]
                                if source != impossible {
                                    let value = source + (j - 2)
                                    if run == impossible || value > run {
                                        run = value
                                    }
                                }
                            }
                            guard fb[j] == wanted else {
                                continue
                            }
                            let base = matchPoints + bb[j]
                            var best = impossible
                            if j > 0 {
                                let adjacent = read[j - 1]
                                if adjacent != impossible {
                                    best = adjacent + base + consecutiveBonus
                                }
                            }
                            if run != impossible {
                                let gapped = run - j - 1 + base
                                if best == impossible || gapped > best {
                                    best = gapped
                                }
                            }
                            write[j] = best
                        }
                    }
                    let swapTmp = read
                    read = write
                    write = swapTmp
                    for j in 0..<avail {
                        write[j] = impossible
                    }
                }
                var best: Int?
                for j in 0..<avail {
                    let value = read[j]
                    if value != impossible, best == nil || value > best! {
                        best = value
                    }
                }
                return best
            }
        }
    }
}

/// Small single-entry cache for prepared items, keyed by snapshot
/// identity plus the inputs that change the prepared fields. The
/// prepared text depends on each item's id, title, and stem; the key
/// also folds in the inspector's outline headings, which change what
/// secondary matches a listing can produce. Rebuilds only when the
/// snapshot or those inputs change.
enum RefsPreparedCache {
    private static let lock = NSLock()
    private static var lastKey: String?
    private static var lastPrepared: [RefsPreparedItem] = []
    /// Test hook: how many times the cache rebuilt. Tests reset it.
    static var buildCount = 0

    static func prepared(
        for items: [RefItem], signals: RefsSignals
    ) -> [RefsPreparedItem] {
        let key = cacheKey(items: items, signals: signals)
        lock.lock()
        if let lastKey, lastKey == key {
            let cached = lastPrepared
            lock.unlock()
            return cached
        }
        lock.unlock()
        let built = items.map { RefsPreparedItem(item: $0) }
        lock.lock()
        lastKey = key
        lastPrepared = built
        buildCount += 1
        lock.unlock()
        return built
    }

    static func resetForTests() {
        lock.lock()
        lastKey = nil
        lastPrepared = []
        buildCount = 0
        lock.unlock()
    }

    static func cacheKey(
        items: [RefItem], signals: RefsSignals
    ) -> String {
        var parts: [String] = []
        parts.reserveCapacity(items.count * 3 + signals.outlineHeadings.count)
        for item in items {
            parts.append(item.id)
            parts.append(item.rawTitle)
            parts.append(item.stem)
        }
        for id in signals.outlineHeadings.keys.sorted() {
            parts.append(id)
            parts.append((signals.outlineHeadings[id] ?? []).joined(
                separator: "\n"
            ))
        }
        return parts.joined(separator: "\u{1F}")
    }
}

/// One item's searchable text, precomputed once per item set: folded
/// titles and stems with their words and alignment tables. Cached per
/// snapshot by `RefsPreparedCache` so ranking never rebuilds
/// mid-keystroke state.
struct RefsPreparedItem {
    let item: RefItem
    let foldedTitle: String
    let foldedStem: String
    let titleField: RefsSearchField
    let stemField: RefsSearchField

    init(item: RefItem) {
        self.item = item
        self.foldedTitle = RefsText.folded(item.title.text)
        self.foldedStem = RefsText.folded(item.stem)
        self.titleField = RefsSearchField(item.title.text)
        self.stemField = RefsSearchField(item.stem)
    }

    /// True when the token equals a whole title or stem word.
    func isWholeWord(_ token: String) -> Bool {
        for word in titleField.words where word.text == token {
            return true
        }
        for word in stemField.words where word.text == token {
            return true
        }
        return false
    }

    /// The token's best hit: a title or stem hit beats any secondary
    /// hit, and a word hit beats a fuzzy one.
    func bestHit(
        _ token: String,
        tokenFolded: [Character],
        selfScore: Double,
        signals: RefsSignals
    ) -> RefsTokenHit? {
        if let hit = matchField(
            token, tokenFolded: tokenFolded, selfScore: selfScore,
            field: titleField, place: RefsHitPlace.title
        ) {
            // A stem hit can only tie a title word hit, and ties keep
            // the title, so the stem check runs only below word tier.
            if hit.tier > .word,
                let stemHit = matchField(
                    token, tokenFolded: tokenFolded, selfScore: selfScore,
                    field: stemField, place: RefsHitPlace.stem
                ),
                stemHit.tier < hit.tier
            {
                return stemHit
            }
            return hit
        }
        if let hit = matchField(
            token, tokenFolded: tokenFolded, selfScore: selfScore,
            field: stemField, place: RefsHitPlace.stem
        ) {
            return hit
        }
        return matchSecondary(
            token, tokenFolded: tokenFolded, selfScore: selfScore,
            signals: signals
        )
    }

    /// Word or fuzzy match of one token against one prepared field. A
    /// one-character token matches as a word prefix only; a
    /// two-character token that prefixes a word is a word (T1) hit,
    /// otherwise it needs a contiguous substring (T2); three or more
    /// use the fuzzy subsequence at `q >= fuzzyFloor`. Quality rides
    /// the score-only alignment; the full alignment runs only for
    /// fuzzy winners that need highlight positions.
    func matchField(
        _ token: String,
        tokenFolded: [Character],
        selfScore: Double,
        field: RefsSearchField,
        place: ([Int]) -> RefsHitPlace
    ) -> RefsTokenHit? {
        var wordStart: Int?
        var wordWhole = false
        for word in field.words where word.text.hasPrefix(token) {
            wordStart = word.range.lowerBound
            wordWhole = word.text == token
            break
        }
        let fuzzyQuality: Double? = {
            guard let score = RefsFuzzyScore.bestScore(token: tokenFolded, field: field) else {
                return nil
            }
            return min(1, Double(score) / max(selfScore, 1))
        }()
        if token.count == 1 {
            guard let start = wordStart else {
                return nil
            }
            return RefsTokenHit(
                tier: .word, quality: fuzzyQuality ?? 1,
                place: place([start]),
                startsAtZero: start == 0, isWholeWord: wordWhole
            )
        }
        if token.count == 2 {
            if let start = wordStart {
                return RefsTokenHit(
                    tier: .word, quality: fuzzyQuality ?? 1,
                    place: place(wordPositions(token, start: start)),
                    startsAtZero: start == 0, isWholeWord: wordWhole
                )
            }
            guard let start = substringStart(tokenFolded, in: field.folded) else {
                return nil
            }
            return RefsTokenHit(
                tier: .fuzzy, quality: fuzzyQuality ?? 1,
                place: place([start, start + 1]),
                startsAtZero: start == 0, isWholeWord: wordWhole
            )
        }
        if wordStart != nil {
            let positions = wordPositions(token, start: wordStart ?? 0)
            return RefsTokenHit(
                tier: .word, quality: fuzzyQuality ?? 1,
                place: place(positions),
                startsAtZero: wordStart == 0, isWholeWord: wordWhole
            )
        }
        guard let fuzzyQuality = fuzzyQuality,
            fuzzyQuality >= RefsRankingConstants.fuzzyFloor
        else {
            return nil
        }
        guard let fuzzy = FuzzyMatcher.match(token: token, in: FuzzyField(field.raw)) else {
            return nil
        }
        return RefsTokenHit(
            tier: .fuzzy, quality: fuzzyQuality,
            place: place(fuzzy.positions),
            startsAtZero: fuzzy.positions.first == 0, isWholeWord: false
        )
    }

    func wordPositions(_ token: String, start: Int) -> [Int] {
        (start..<(start + token.count)).map { $0 }
    }

    func substringStart(_ token: [Character], in folded: [Character]) -> Int? {
        guard token.count <= folded.count else {
            return nil
        }
        for start in 0...(folded.count - token.count) {
            var matches = true
            for offset in token.indices {
                if folded[start + offset] != token[offset] {
                    matches = false
                    break
                }
            }
            if matches {
                return start
            }
        }
        return nil
    }

    /// Word or fuzzy match against author, area, kind words, and cached
    /// outline headings. One-character tokens match as word prefixes.
    func matchSecondary(
        _ token: String,
        tokenFolded: [Character],
        selfScore: Double,
        signals: RefsSignals
    ) -> RefsTokenHit? {
        var candidates: [(RefsSecondaryField, String)] = []
        if let author = item.author, !author.isEmpty {
            candidates.append((.author, author))
        }
        if let area = item.parentLabel, !area.isEmpty {
            candidates.append((.area, area))
        }
        for word in RefsText.kindWords(item.kind) {
            candidates.append((.kind, word))
        }
        for heading in signals.outlineHeadings[item.id] ?? [] {
            candidates.append((.heading, heading))
        }
        var best: RefsTokenHit?
        for (field, text) in candidates {
            let prepared = RefsSearchField(text)
            guard let hit = matchField(
                token, tokenFolded: tokenFolded, selfScore: selfScore,
                field: prepared,
                place: { RefsHitPlace.secondary(RefsSecondaryMatch(
                    field: field, text: field == .kind ? item.kind.label : text,
                    ranges: RefsHighlights.coalesced($0)
                )) }
            ) else {
                continue
            }
            let placed: RefsTokenHit = {
                // Ranges for kind hits point at the kind word; the
                // caption shows the kind label instead.
                if field == .kind, case let .secondary(match) = hit.place {
                    let relabeled = RefsSecondaryMatch(
                        field: match.field, text: item.kind.label,
                        ranges: match.ranges
                    )
                    return RefsTokenHit(
                        tier: .secondary, quality: hit.quality,
                        place: .secondary(relabeled),
                        startsAtZero: hit.startsAtZero,
                        isWholeWord: hit.isWholeWord
                    )
                }
                return RefsTokenHit(
                    tier: .secondary, quality: hit.quality,
                    place: hit.place,
                    startsAtZero: hit.startsAtZero,
                    isWholeWord: hit.isWholeWord
                )
            }()
            if let current = best {
                if placed.quality > current.quality {
                    best = placed
                }
            } else {
                best = placed
            }
        }
        return best
    }
}
