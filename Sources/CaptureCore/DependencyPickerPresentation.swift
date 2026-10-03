import Foundation

/// One fetched `task_dependency` snapshot in Bob order, with display text and
/// weighted search fields precomputed so every keystroke filters locally.
/// Presents `CapturePickerPresentation` values for the source-agnostic card.
/// Rows are keyed by `"note_path|ref"` (never by `replacement`, which Bob
/// sends as `""` for ID-less and guarded rows), and the grouped view follows
/// Bob's order and `group` instead of the `^` buckets.
///
/// Grouped sections in Bob precedence: In Progress, Next, per-note Open
/// sections, then one separate Completed history section. `#hide` rows are
/// subdued and ordered last within their section. Query matches are the
/// primary ordering within the open and completed groups; deterministic
/// empty-query (Bob) order breaks ties.
public struct DependencyPickerIndex: Sendable {
    private let entries: [DependencyPickerIndexEntry]

    public init(candidates: [CaptureCompletionCandidate]) {
        var seen: Set<String> = []
        var entries: [DependencyPickerIndexEntry] = []
        for candidate in candidates {
            let key = Self.key(for: candidate)
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            entries.append(DependencyPickerIndexEntry(candidate: candidate, bobIndex: entries.count))
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
    /// `&` seed from the draft; it is stripped before matching.
    public func presentation(filter: String) -> CapturePickerPresentation {
        let groupedSections = groupedRows()
        let groupedRowCount = groupedSections.reduce(0) { $0 + $1.rows.count }
        let budget: Int
        if entries.isEmpty {
            budget = 4
        } else {
            budget = min(max(groupedRowCount + groupedSections.count, 4), 11)
        }

        let query = FuzzyQuery(filter, leadingSigil: "&")
        if query.isEmpty {
            let ids = groupedSections.flatMap { $0.rows.map { $0.id } }
            let byID = Dictionary(uniqueKeysWithValues: groupedSections.flatMap { $0.rows }.map { ($0.id, $0) })
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
        var inProgress: [CapturePickerRow] = []
        var next: [CapturePickerRow] = []
        var noteOrder: [String] = []
        var noteRows: [String: [CapturePickerRow]] = [:]
        var completed: [CapturePickerRow] = []
        for entry in entries {
            switch entry.group {
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
        inProgress = Self.hiddenLast(inProgress, entries: entries)
        next = Self.hiddenLast(next, entries: entries)
        completed = Self.hiddenLast(completed, entries: entries)
        var sections: [CapturePickerSection] = []
        if !inProgress.isEmpty {
            sections.append(CapturePickerSection(
                id: "dependency-in-progress",
                kind: .unqueuedInProgress,
                title: "In Progress",
                rows: inProgress
            ))
        }
        if !next.isEmpty {
            sections.append(CapturePickerSection(
                id: "dependency-next",
                kind: .unqueuedNext,
                title: "Next",
                rows: next
            ))
        }
        for note in noteOrder {
            sections.append(CapturePickerSection(
                id: "dependency-note-\(note)",
                kind: .note,
                title: note,
                rows: Self.hiddenLast(noteRows[note] ?? [], entries: entries)
            ))
        }
        if !completed.isEmpty {
            sections.append(CapturePickerSection(
                id: "dependency-completed",
                kind: .other,
                title: "Completed history",
                subtitle: "Non-blocking",
                rows: completed
            ))
        }
        return sections
    }

    private static func hiddenLast(
        _ rows: [CapturePickerRow],
        entries: [DependencyPickerIndexEntry]
    ) -> [CapturePickerRow] {
        let hiddenIDs = Set(entries.filter { $0.candidate.hidden }.map { key(for: $0.candidate) })
        let visible = rows.filter { !hiddenIDs.contains($0.id) }
        let hidden = rows.filter { hiddenIDs.contains($0.id) }
        return visible + hidden
    }

    // MARK: - Filtered view

    private struct RankedEntry {
        let entry: DependencyPickerIndexEntry
        let score: Int
        let highlights: DependencyMatchHighlights
    }

    private func rank(tokens: [String]) -> [RankedEntry] {
        var ranked: [RankedEntry] = []
        for entry in entries {
            var total = 0
            var highlights = DependencyMatchHighlights()
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
            return $0.entry.bobIndex < $1.entry.bobIndex
        }
    }

    // MARK: - Rows

    private func groupedRow(for entry: DependencyPickerIndexEntry) -> CapturePickerRow {
        baseRow(for: entry, depth: 0, chipText: nil)
    }

    private func groupedNoteRow(for entry: DependencyPickerIndexEntry) -> CapturePickerRow {
        baseRow(for: entry, depth: entry.candidate.depth ?? 0, chipText: nil)
    }

    private func filteredRow(
        for entry: DependencyPickerIndexEntry,
        highlights: DependencyMatchHighlights
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
        for entry: DependencyPickerIndexEntry,
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
            badge = candidate.alreadyDependency ? "Already added" : nil
        }
        // Accepting an already-present or guarded row is a harmless no-op:
        // both already carry a nil insertion above, so the accept keeps the
        // draft unchanged with the explanation. Backend idempotence is the
        // last defense for typed duplicates.
        return CapturePickerRow(
            id: Self.key(for: candidate),
            bobIndex: entry.bobIndex,
            glyph: .task(entry.status),
            displayText: entry.display.text,
            textSegments: entry.display.segments,
            textMatchRanges: textMatchRanges,
            route: candidate.locator ?? candidate.route,
            blockID: entry.effectiveBlockID,
            routeMatchRanges: routeMatchRanges,
            blockIDMatchRanges: blockIDMatchRanges,
            chipText: chipText,
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
                insertionPrefix: "&"
            ),
            accessibilityLabel: accessibilityLabel(for: entry)
        )
    }

    // MARK: - Detail lines

    /// The detail-strip action line for `row`: the insertion for identified
    /// rows, the Add block ID outcome for ID-less rows, or the guard reason
    /// for disabled rows.
    public func actionLine(for row: CapturePickerRow) -> String {
        if let insertion = row.insertion {
            return "↩ inserts \(insertion) · space adds another &"
        }
        if let pending = row.pendingBlockID {
            if let first = pending.suggestions.first {
                let locator = row.route ?? pending.route
                return "↩ adds ^\(first), then inserts &\(locator):\(first)"
            }
            return "↩ names this task, then inserts its link"
        }
        if let badge = row.badgeText, !badge.isEmpty {
            return badge
        }
        return "↩ names this task, then inserts its link"
    }

    private func chipText(for entry: DependencyPickerIndexEntry) -> String? {
        if entry.candidate.alreadyDependency {
            return "Already added"
        }
        if entry.candidate.hidden {
            return "Hidden"
        }
        switch entry.group {
        case .completed:
            return "Done"
        default:
            return nil
        }
    }

    private func summary(for entry: DependencyPickerIndexEntry) -> String {
        if let reason = entry.candidate.disabledReason, !reason.isEmpty {
            return reason
        }
        if entry.candidate.alreadyDependency {
            return "Already a prerequisite — accepting changes nothing"
        }
        switch entry.group {
        case .completed:
            return "Completed history — selecting never blocks"
        case .inProgress, .next, .open:
            return "Open · will block the dependent until finished"
        }
    }

    private func accessibilityLabel(for entry: DependencyPickerIndexEntry) -> String {
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
        parts.append(summary(for: entry))
        return parts.joined(separator: ". ") + "."
    }

    // MARK: - Owner header

    /// Picker header for the dependent: `For: <text>` when the draft names
    /// one, else the ownerless prompt. Choosing a prerequisite stays allowed
    /// before the dependent exists.
    public static func headerTitle(owner: DependencyOwner?, dependentText: String?) -> String {
        if let dependentText, !dependentText.isEmpty {
            return "For: \(dependentText)"
        }
        if let header = owner?.headerText {
            return "For: \(header)"
        }
        return "Choose a prerequisite"
    }

    /// Ownerless subtitle shown under the header when no dependent exists.
    public static func headerSubtitle(owner: DependencyOwner?, dependentText: String?) -> String? {
        if let dependentText, !dependentText.isEmpty {
            return nil
        }
        if owner?.headerText != nil {
            return nil
        }
        return "Then add task text or @note+id"
    }
}

// MARK: - Index entries

/// Bob's dependency `group` wire value, in precedence order. Missing or
/// unknown groups fall back to `open` so the row still appears.
private enum DependencyGroup: Sendable {
    case inProgress
    case next
    case open
    case completed

    init(wireValue: String?) {
        switch wireValue {
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
/// Weights mirror the `:` picker: display text 100%, `locator:block-id`
/// 90%, block ID 90%, locator/note path 80%, section 40%. For ID-less rows
/// the block-ID and combined fields use the first suggestion, so the
/// locator stays searchable.
private struct DependencyPickerIndexEntry: Sendable {
    let candidate: CaptureCompletionCandidate
    let bobIndex: Int
    let display: TaskDisplayText
    let status: CapturePickerTaskStatus
    let group: DependencyGroup
    /// The locator's block ID: Bob's ID, or the first suggestion on
    /// ID-less rows so `locator plus suggestion` renders and matches.
    let effectiveBlockID: String?
    /// Short per-note section title: the exact note path including
    /// extension, falling back to the display route for older Bob rows.
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
        self.group = DependencyGroup(wireValue: candidate.group)
        if let blockID = candidate.blockID, !blockID.isEmpty {
            self.effectiveBlockID = blockID
        } else {
            self.effectiveBlockID = candidate.blockIDSuggestions.first
        }
        if let notePath = candidate.notePath, !notePath.isEmpty {
            self.noteTitle = notePath
        } else {
            self.noteTitle = "\(candidate.route ?? "Unknown").md"
        }
        self.textField = FuzzyField(display.text)
        if let effectiveBlockID, !effectiveBlockID.isEmpty {
            self.blockField = FuzzyField(effectiveBlockID)
        } else {
            self.blockField = nil
        }
        let locatorText = candidate.locator ?? candidate.route ?? ""
        if !locatorText.isEmpty, let effectiveBlockID, !effectiveBlockID.isEmpty {
            self.combinedField = FuzzyField("\(locatorText):\(effectiveBlockID)")
            self.combinedRouteLength = locatorText.count
        } else {
            self.combinedField = nil
            self.combinedRouteLength = 0
        }
        let routeText = [candidate.locator, candidate.notePath, candidate.route]
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
    func bestFieldMatch(for token: String) -> DependencyFieldMatch? {
        var best: DependencyFieldMatch?
        func consider(weight: Int, field: FuzzyField?, target: DependencyMatchTarget) {
            guard let field,
                  let match = FuzzyMatcher.match(token: token, in: field)
            else {
                return
            }
            let weighted = match.score * weight / 100
            if best == nil || weighted > best!.weightedScore {
                best = DependencyFieldMatch(
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

private enum DependencyMatchTarget: Sendable {
    case text
    case combined
    case blockID
    case route
    case section
}

private struct DependencyFieldMatch: Sendable {
    let weightedScore: Int
    let target: DependencyMatchTarget
    let positions: [Int]
    let combinedRouteLength: Int
}

/// Coalesced highlight positions gathered from every token's best field.
/// Section matches raise the rank without highlighting.
private struct DependencyMatchHighlights: Sendable {
    var textPositions: [Int] = []
    var routePositions: [Int] = []
    var blockPositions: [Int] = []

    mutating func add(_ match: DependencyFieldMatch) {
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
