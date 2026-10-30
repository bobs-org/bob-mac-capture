import Foundation

/// Server-authored Task Wikilink (`((`) picker context: Bob's `query` plus
/// the verbatim `marker_range` and `trigger_removal_range` from the
/// `wikilink_task` picker descriptor. Swift never synthesizes grammar or
/// ranges; a missing or invalid descriptor means an older Bob and the token
/// stays plain.
public struct WikilinkTaskPickerContext: Equatable, Sendable {
    public let markerRange: CaptureRange
    public let triggerRemovalRange: CaptureRange
    public let query: String

    public init(
        markerRange: CaptureRange,
        triggerRemovalRange: CaptureRange,
        query: String
    ) {
        self.markerRange = markerRange
        self.triggerRemovalRange = triggerRemovalRange
        self.query = query
    }
}

/// One fetched `wikilink_task` snapshot in Bob order, with display text and
/// weighted search fields precomputed so every keystroke filters locally.
/// Presents `CapturePickerPresentation` values for the source-agnostic card.
/// Rows are keyed by `"note_path|ref"` (never by `replacement`, which Bob
/// sends as `""` for ID-less and guarded rows), and the grouped view follows
/// Bob's order and `group`.
///
/// Grouped sections in Bob precedence: This note, In Progress, Next, one
/// section per note for other open tasks, then Completed history. `#hide`
/// rows are subdued and ordered last within their section. A non-empty
/// filter becomes one ranked flat list (spaces are AND terms) with open
/// matches ahead of completed ones at equal score.
public struct WikilinkTaskPickerIndex: Sendable {
    private let entries: [WikilinkTaskPickerIndexEntry]

    public init(candidates: [CaptureCompletionCandidate]) {
        var seen: Set<String> = []
        var entries: [WikilinkTaskPickerIndexEntry] = []
        for candidate in candidates {
            let key = Self.key(for: candidate)
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            entries.append(
                WikilinkTaskPickerIndexEntry(candidate: candidate, bobIndex: entries.count))
        }
        self.entries = entries
    }

    /// Deduped row key: exact note path plus the stale-safe task ref.
    /// ID-less and guarded rows share Bob's empty replacement, so keying on
    /// it would collapse them. Falls back to the display route for rows
    /// from older Bob binaries that predate `note_path`.
    static func key(for candidate: CaptureCompletionCandidate) -> String {
        let note = candidate.notePath ?? candidate.route ?? ""
        return "\(note)|\(candidate.taskRef ?? "")"
    }

    public var count: Int {
        entries.count
    }

    /// Presents the snapshot for `filter`: grouped sections for an empty
    /// query, one ranked flat section otherwise. The filter may carry the
    /// `((` seed from the draft; it is stripped before matching.
    public func presentation(filter: String) -> CapturePickerPresentation {
        let groupedSections = groupedRows()
        let groupedRowCount = groupedSections.reduce(0) { $0 + $1.rows.count }
        let budget: Int
        if entries.isEmpty {
            budget = 4
        } else {
            budget = min(max(groupedRowCount + groupedSections.count, 4), 11)
        }

        let query = FuzzyQuery(filter, leadingSigil: "((")
        if query.isEmpty {
            let ids = groupedSections.flatMap { $0.rows.map { $0.id } }
            let byID = Dictionary(
                uniqueKeysWithValues: groupedSections.flatMap { $0.rows }.map { ($0.id, $0) })
            let countText = entries.count == 1 ? "1 task" : "\(entries.count) tasks"
            return CapturePickerPresentation(
                mode: .grouped,
                sections: groupedSections,
                orderedRowIDs: ids,
                rowsByID: byID,
                totalCount: entries.count,
                matchCount: entries.count,
                countText: countText,
                emptyState: entries.isEmpty ? .noOpenTasks : nil,
                visibleRowBudget: budget
            )
        }

        let ranked = rank(tokens: query.tokens)
        let rows = ranked.map { scored in
            self.filteredRow(for: scored.entry, highlights: scored.highlights)
        }
        let section = CapturePickerSection(
            id: "matches",
            kind: .matches,
            title: "",
            rows: rows
        )
        let ids = rows.map { $0.id }
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        return CapturePickerPresentation(
            mode: .filtered,
            sections: [section],
            orderedRowIDs: ids,
            rowsByID: byID,
            totalCount: entries.count,
            matchCount: rows.count,
            countText: "\(rows.count) of \(entries.count)",
            emptyState: rows.isEmpty ? .noMatches(query: filter, noun: "tasks") : nil,
            visibleRowBudget: budget
        )
    }

    // MARK: - Grouped view

    private func groupedRows() -> [CapturePickerSection] {
        var thisNote: [CapturePickerRow] = []
        var inProgress: [CapturePickerRow] = []
        var next: [CapturePickerRow] = []
        var noteOrder: [String] = []
        var noteRows: [String: [CapturePickerRow]] = [:]
        var completed: [CapturePickerRow] = []
        for entry in entries {
            switch entry.group {
            case .thisNote:
                thisNote.append(groupedNoteRow(for: entry))
            case .inProgress:
                inProgress.append(groupedRow(for: entry))
            case .next:
                next.append(groupedRow(for: entry))
            case .completed:
                completed.append(groupedRow(for: entry))
            case .open:
                let note = entry.noteTitle
                if noteRows[note] == nil {
                    noteOrder.append(note)
                    noteRows[note] = []
                }
                noteRows[note]!.append(groupedNoteRow(for: entry))
            }
        }
        // Hidden rows render subdued and sort last within their section.
        thisNote = Self.hiddenLast(thisNote, entries: entries)
        inProgress = Self.hiddenLast(inProgress, entries: entries)
        next = Self.hiddenLast(next, entries: entries)
        completed = Self.hiddenLast(completed, entries: entries)
        var sections: [CapturePickerSection] = []
        if !thisNote.isEmpty {
            sections.append(
                CapturePickerSection(
                    id: "wikilink-this-note",
                    kind: .thisNote,
                    title: "This note",
                    rows: thisNote
                ))
        }
        if !inProgress.isEmpty {
            sections.append(
                CapturePickerSection(
                    id: "wikilink-in-progress",
                    kind: .unqueuedInProgress,
                    title: "In Progress",
                    rows: inProgress
                ))
        }
        if !next.isEmpty {
            sections.append(
                CapturePickerSection(
                    id: "wikilink-next",
                    kind: .unqueuedNext,
                    title: "Next",
                    rows: next
                ))
        }
        for note in noteOrder {
            sections.append(
                CapturePickerSection(
                    id: "wikilink-note-\(note)",
                    kind: .note,
                    title: note,
                    rows: Self.hiddenLast(noteRows[note] ?? [], entries: entries)
                ))
        }
        if !completed.isEmpty {
            sections.append(
                CapturePickerSection(
                    id: "wikilink-completed",
                    kind: .other,
                    title: "Completed history",
                    rows: completed
                ))
        }
        return sections
    }

    private static func hiddenLast(
        _ rows: [CapturePickerRow],
        entries: [WikilinkTaskPickerIndexEntry]
    ) -> [CapturePickerRow] {
        let hiddenIDs = Set(entries.filter { $0.candidate.hidden }.map { key(for: $0.candidate) })
        let visible = rows.filter { !hiddenIDs.contains($0.id) }
        let hidden = rows.filter { hiddenIDs.contains($0.id) }
        return visible + hidden
    }

    // MARK: - Filtered view

    private struct RankedEntry {
        let entry: WikilinkTaskPickerIndexEntry
        let score: Int
        let highlights: WikilinkMatchHighlights
    }

    private func rank(tokens: [String]) -> [RankedEntry] {
        var ranked: [RankedEntry] = []
        for entry in entries {
            var total = 0
            var highlights = WikilinkMatchHighlights()
            var matchesAll = true
            for token in tokens {
                guard let fieldMatch = entry.bestFieldMatch(for: token) else {
                    matchesAll = false
                    break
                }
                total += fieldMatch.weightedScore
                highlights.add(fieldMatch)
            }
            if matchesAll {
                ranked.append(RankedEntry(entry: entry, score: total, highlights: highlights))
            }
        }
        return ranked.sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            // Open matches ahead of completed ones at equal score; Bob
            // order (open before completed) breaks remaining ties.
            let lhsCompleted = $0.entry.group == .completed
            let rhsCompleted = $1.entry.group == .completed
            if lhsCompleted != rhsCompleted {
                return !lhsCompleted && rhsCompleted
            }
            return $0.entry.bobIndex < $1.entry.bobIndex
        }
    }

    // MARK: - Rows

    private func groupedRow(for entry: WikilinkTaskPickerIndexEntry) -> CapturePickerRow {
        baseRow(for: entry, depth: 0, chipText: chipText(for: entry))
    }

    private func groupedNoteRow(for entry: WikilinkTaskPickerIndexEntry) -> CapturePickerRow {
        baseRow(for: entry, depth: entry.candidate.depth ?? 0, chipText: chipText(for: entry))
    }

    private func filteredRow(
        for entry: WikilinkTaskPickerIndexEntry,
        highlights: WikilinkMatchHighlights
    ) -> CapturePickerRow {
        baseRow(
            for: entry,
            depth: 0,
            chipText: chipText(for: entry),
            textMatchRanges: highlights.textRanges,
            routeMatchRanges: highlights.routeRanges,
            blockIDMatchRanges: highlights.blockRanges
        )
    }

    private func baseRow(
        for entry: WikilinkTaskPickerIndexEntry,
        depth: Int,
        chipText: String?,
        textMatchRanges: [Range<Int>] = [],
        routeMatchRanges: [Range<Int>] = [],
        blockIDMatchRanges: [Range<Int>] = []
    ) -> CapturePickerRow {
        let candidate = entry.candidate
        let pending: CapturePickerPendingBlockID?
        let insertion: String?
        let badge: String?
        if candidate.disabledReason != nil {
            // Guarded rows never supply an insertable replacement and never
            // open the Add block ID flow: accepting one changes nothing and
            // the detail strip carries the backend's explanation.
            pending = nil
            insertion = nil
            badge = candidate.disabledReason
        } else if candidate.requiresBlockID {
            // ID-less rows never supply an insertable empty replacement:
            // they resolve through the explicit Add block ID flow, keyed by
            // the exact note path so quoting and case survive.
            pending = CapturePickerPendingBlockID(
                route: candidate.notePath ?? candidate.route ?? "",
                taskRef: candidate.taskRef ?? "",
                suggestions: candidate.blockIDSuggestions
            )
            insertion = nil
            badge = nil
        } else {
            pending = nil
            insertion = candidate.replacement.isEmpty ? nil : candidate.replacement
            badge = nil
        }
        return CapturePickerRow(
            id: Self.key(for: candidate),
            bobIndex: entry.bobIndex,
            glyph: .task(entry.status),
            displayText: entry.display.text,
            textSegments: entry.display.segments,
            textMatchRanges: textMatchRanges,
            route: candidate.linkTarget ?? candidate.locator ?? candidate.route,
            blockID: entry.effectiveBlockID,
            routeMatchRanges: routeMatchRanges,
            blockIDMatchRanges: blockIDMatchRanges,
            chipText: chipText,
            isHidden: candidate.hidden,
            badgeText: badge,
            depth: depth,
            insertion: insertion,
            pendingBlockID: pending,
            scheduledText: nil,
            pullsForward: false,
            detail: CapturePickerRowDetail(
                statusText: entry.status.displayName,
                route: candidate.locator ?? candidate.route,
                section: candidate.section,
                summary: summary(for: entry),
                insertionPrefix: "(("
            ),
            accessibilityLabel: accessibilityLabel(for: entry)
        )
    }

    // MARK: - Detail lines

    /// The detail-strip action line for `row`: the insertion for identified
    /// rows, the Add block ID outcome for ID-less rows, or the guard reason
    /// for disabled rows.
    public func actionLine(for row: CapturePickerRow) -> String {
        Self.actionLine(for: row)
    }

    /// Type-level action line so SwiftUI can render it without owning an index.
    public static func actionLine(for row: CapturePickerRow) -> String {
        if let insertion = row.insertion {
            return "↩ inserts \(insertion)"
        }
        if let pending = row.pendingBlockID {
            if let first = pending.suggestions.first {
                return "↩ names it ^\(first) in \(pending.route), then links it"
            }
            return "↩ names this task, then links it"
        }
        if let badge = row.badgeText, !badge.isEmpty {
            return badge
        }
        return "↩ names this task, then links it"
    }

    private func chipText(for entry: WikilinkTaskPickerIndexEntry) -> String? {
        if entry.candidate.hidden {
            return "Hidden"
        }
        switch entry.group {
        case .completed:
            switch entry.status {
            case .done:
                return "Done"
            case .canceled:
                return "Cancelled"
            default:
                return "Done"
            }
        default:
            return nil
        }
    }

    private func summary(for entry: WikilinkTaskPickerIndexEntry) -> String {
        if let reason = entry.candidate.disabledReason, !reason.isEmpty {
            return reason
        }
        if entry.candidate.requiresBlockID {
            return "Needs a block ID"
        }
        switch entry.group {
        case .thisNote:
            return "In this note"
        case .inProgress:
            return "In Progress"
        case .next:
            return "Next"
        case .open:
            return "Open"
        case .completed:
            return "Completed history"
        }
    }

    private func accessibilityLabel(for entry: WikilinkTaskPickerIndexEntry) -> String {
        let name = entry.candidate.statusName.flatMap { $0.isEmpty ? nil : $0 }
        let statusText = name ?? entry.status.displayName
        var parts = [statusText, entry.display.text]
        let note = entry.candidate.notePath ?? entry.candidate.route ?? ""
        if !note.isEmpty {
            if let blockID = entry.effectiveBlockID, !blockID.isEmpty {
                if entry.candidate.requiresBlockID {
                    parts.append("Note \(note), suggested block \(blockID)")
                } else {
                    parts.append("Note \(note), block \(blockID)")
                }
            } else {
                parts.append("Note \(note)")
            }
        }
        if let link = entry.candidate.linkTarget, !link.isEmpty,
            let blockID = entry.effectiveBlockID, !blockID.isEmpty,
            !entry.candidate.requiresBlockID
        {
            parts.append("Inserts [[\(link)#^\(blockID)]]")
        }
        parts.append(summary(for: entry))
        return parts.joined(separator: ". ") + "."
    }
}

// MARK: - Index entries

/// Bob's wikilink_task `group` wire value, in precedence order. Missing or
/// unknown groups fall back to `open` so the row still appears.
enum WikilinkTaskGroup: Sendable {
    case thisNote
    case inProgress
    case next
    case open
    case completed

    init(wireValue: String?) {
        switch wireValue {
        case "in_this_note":
            self = .thisNote
        case "in_progress":
            self = .inProgress
        case "next":
            self = .next
        case "completed":
            self = .completed
        default:
            self = .open
        }
    }
}

/// One deduped candidate with its display text and weighted search fields.
/// Weights mirror the `:` picker: display text 100%, `link_target:block-id`
/// 90%, block ID 90%, link target/note path 80%, section 40%. For ID-less rows
/// the block-ID and combined fields use the first suggestion, so the
/// locator stays searchable.
struct WikilinkTaskPickerIndexEntry: Sendable {
    let candidate: CaptureCompletionCandidate
    let bobIndex: Int
    let display: TaskDisplayText
    let status: CapturePickerTaskStatus
    let group: WikilinkTaskGroup
    /// The locator's block ID: Bob's ID, or the first suggestion on
    /// ID-less rows so `link_target plus suggestion` renders and matches.
    let effectiveBlockID: String?
    /// Short per-note section title: the exact note path including
    /// extension, falling back to the display locator for older Bob rows.
    let noteTitle: String
    let textField: FuzzyField
    let blockField: FuzzyField?
    let combinedField: FuzzyField?
    let combinedRouteLength: Int
    let routeField: FuzzyField?
    let sectionField: FuzzyField?

    init(candidate: CaptureCompletionCandidate, bobIndex: Int) {
        self.candidate = candidate
        self.bobIndex = bobIndex
        let display = TaskDisplayText(parsing: candidate.text ?? candidate.replacement)
        self.display = display
        self.status = CapturePickerTaskStatus(
            symbol: candidate.statusSymbol,
            name: candidate.statusName
        )
        self.group = WikilinkTaskGroup(wireValue: candidate.group)
        if let blockID = candidate.blockID, !blockID.isEmpty {
            self.effectiveBlockID = blockID
        } else {
            self.effectiveBlockID = candidate.blockIDSuggestions.first
        }
        if let notePath = candidate.notePath, !notePath.isEmpty {
            self.noteTitle = notePath
        } else {
            self.noteTitle =
                "\(candidate.locator ?? candidate.linkTarget ?? candidate.route ?? "Unknown").md"
        }
        self.textField = FuzzyField(display.text)
        if let effectiveBlockID, !effectiveBlockID.isEmpty {
            self.blockField = FuzzyField(effectiveBlockID)
        } else {
            self.blockField = nil
        }
        let locatorText = candidate.linkTarget ?? candidate.locator ?? candidate.route ?? ""
        if !locatorText.isEmpty, let effectiveBlockID, !effectiveBlockID.isEmpty {
            self.combinedField = FuzzyField("\(locatorText):\(effectiveBlockID)")
            self.combinedRouteLength = locatorText.count
        } else {
            self.combinedField = nil
            self.combinedRouteLength = 0
        }
        let routeText = [
            candidate.linkTarget, candidate.locator, candidate.notePath, candidate.route,
        ]
        .compactMap { $0 }
        .first(where: { !$0.isEmpty })
        if let routeText {
            self.routeField = FuzzyField(routeText)
        } else {
            self.routeField = nil
        }
        if let section = candidate.section, !section.isEmpty {
            self.sectionField = FuzzyField(section)
        } else {
            self.sectionField = nil
        }
    }

    /// The token's best weighted field match (`score * weight / 100`), or nil
    /// when the token matches no field. Preference order breaks weighted ties
    /// toward highlightable fields (display text first).
    func bestFieldMatch(for token: String) -> WikilinkFieldMatch? {
        var best: WikilinkFieldMatch?
        func consider(weight: Int, field: FuzzyField?, target: WikilinkMatchTarget) {
            guard let field,
                let match = FuzzyMatcher.matchPreFolded(token: token, in: field)
            else {
                return
            }
            let weighted = match.score * weight / 100
            if best == nil || weighted > best!.weightedScore {
                best = WikilinkFieldMatch(
                    weightedScore: weighted,
                    target: target,
                    positions: match.positions,
                    combinedRouteLength: combinedRouteLength
                )
            }
        }
        consider(weight: 100, field: textField, target: .text)
        consider(weight: 90, field: combinedField, target: .combined)
        consider(weight: 90, field: blockField, target: .blockID)
        consider(weight: 80, field: routeField, target: .route)
        consider(weight: 40, field: sectionField, target: .section)
        return best
    }
}

enum WikilinkMatchTarget: Sendable {
    case text
    case combined
    case blockID
    case route
    case section
}

struct WikilinkFieldMatch: Sendable {
    let weightedScore: Int
    let target: WikilinkMatchTarget
    let positions: [Int]
    let combinedRouteLength: Int
}

/// Coalesced highlight positions gathered from every token's best field.
/// Section matches raise the rank without highlighting.
struct WikilinkMatchHighlights: Sendable {
    var textPositions: [Int] = []
    var routePositions: [Int] = []
    var blockPositions: [Int] = []

    mutating func add(_ match: WikilinkFieldMatch) {
        switch match.target {
        case .text:
            textPositions += match.positions
        case .combined:
            for position in match.positions {
                if position < match.combinedRouteLength {
                    routePositions.append(position)
                } else if position > match.combinedRouteLength {
                    blockPositions.append(position - match.combinedRouteLength - 1)
                }
            }
        case .blockID:
            blockPositions += match.positions
        case .route:
            routePositions += match.positions
        case .section:
            break
        }
    }

    var textRanges: [Range<Int>] {
        Self.coalesced(textPositions)
    }

    var routeRanges: [Range<Int>] {
        Self.coalesced(routePositions)
    }

    var blockRanges: [Range<Int>] {
        Self.coalesced(blockPositions)
    }

    /// Merges sorted unique positions into ranges of consecutive offsets.
    static func coalesced(_ positions: [Int]) -> [Range<Int>] {
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
