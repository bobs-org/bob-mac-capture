import Foundation

/// One fetched `task_link` snapshot in Bob order, with display text and
/// weighted search fields precomputed so every keystroke filters locally.
/// Presents `CapturePickerPresentation` values for the source-agnostic card.
/// Rows are keyed by `"route|ref"` (never by `replacement`, which Bob sends
/// as `""` for ID-less tasks), and the grouped view follows Bob's order and
/// `group` instead of the `^` buckets.
public struct TaskLinkPickerIndex: Sendable {
    private let entries: [TaskLinkPickerIndexEntry]
    /// Pomodoro line to its 1-based section ordinal (first-appearance order).
    private let pomodoroOrdinals: [Int: Int]

    public init(candidates: [CaptureCompletionCandidate]) {
        var seen: Set<String> = []
        var entries: [TaskLinkPickerIndexEntry] = []
        for candidate in candidates {
            let key = Self.key(for: candidate)
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            entries.append(TaskLinkPickerIndexEntry(candidate: candidate, bobIndex: entries.count))
        }
        self.entries = entries
        var ordinals: [Int: Int] = [:]
        for entry in entries {
            guard let line = entry.pomodoroLine, ordinals[line] == nil else {
                continue
            }
            ordinals[line] = ordinals.count + 1
        }
        self.pomodoroOrdinals = ordinals
    }

    /// Deduped row key: route plus the stale-safe task ref. ID-less rows
    /// share Bob's empty replacement, so keying on it would collapse them.
    static func key(for candidate: CaptureCompletionCandidate) -> String {
        "\(candidate.route ?? "")|\(candidate.taskRef ?? "")"
    }

    public var count: Int {
        entries.count
    }

    /// Presents the snapshot for `filter`: grouped sections for an empty
    /// query, one ranked flat section otherwise. The filter may carry the
    /// `:` seed from the draft; it is stripped before matching.
    public func presentation(filter: String) -> CapturePickerPresentation {
        let groupedSections = groupedRows()
        let groupedRowCount = groupedSections.reduce(0) { $0 + $1.rows.count }
        let budget: Int
        if entries.isEmpty {
            budget = 4
        } else {
            budget = min(max(groupedRowCount + groupedSections.count, 4), 11)
        }

        let query = FuzzyQuery(filter, leadingSigil: ":")
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
            emptyState: rows.isEmpty ? .noMatches(query: filter, noun: "open tasks") : nil,
            visibleRowBudget: budget
        )
    }

    // MARK: - Grouped view

    private func groupedRows() -> [CapturePickerSection] {
        var pomodoroOrder: [Int] = []
        var pomodoroRows: [Int: [CapturePickerRow]] = [:]
        var inProgress: [CapturePickerRow] = []
        var next: [CapturePickerRow] = []
        var now: [CapturePickerRow] = []
        var noteOrder: [String] = []
        var noteRows: [String: [CapturePickerRow]] = [:]
        var noteKinds: [String: String?] = [:]
        for entry in entries {
            switch entry.group {
            case .queued where entry.pomodoroLine != nil:
                let line = entry.pomodoroLine!
                if pomodoroRows[line] == nil {
                    pomodoroOrder.append(line)
                    pomodoroRows[line] = []
                }
                pomodoroRows[line]!.append(groupedRow(for: entry))
            case .inProgress:
                inProgress.append(groupedRow(for: entry))
            case .next:
                next.append(groupedRow(for: entry))
            case .now:
                now.append(groupedRow(for: entry))
            case .queued, .note:
                // A queued row without a Pomodoro line cannot happen per the
                // contract; bucket it with its note rather than dropping it.
                let route = entry.route ?? "Unknown"
                if noteRows[route] == nil {
                    noteOrder.append(route)
                    noteRows[route] = []
                    noteKinds[route] = entry.candidate.noteKind
                }
                noteRows[route]!.append(groupedNoteRow(for: entry))
            }
        }
        var sections: [CapturePickerSection] = []
        for line in pomodoroOrder {
            let ordinal = pomodoroOrdinals[line] ?? 0
            let pomodoro = entries.first { $0.pomodoroLine == line }?.pomodoro
            let name = pomodoro?.name.flatMap { $0.isEmpty ? nil : $0 }
            sections.append(CapturePickerSection(
                id: "pomodoro-\(line)",
                kind: .pomodoro,
                title: name ?? "Unnamed Pomodoro",
                timeRangeText: pomodoro?.timeRange.map { ActiveTaskPickerIndex.formattedTimeRange($0) },
                ordinal: ordinal,
                isCurrent: pomodoro?.isCurrent ?? false,
                rows: pomodoroRows[line] ?? []
            ))
        }
        if !inProgress.isEmpty {
            sections.append(CapturePickerSection(
                id: "unqueued-in-progress",
                kind: .unqueuedInProgress,
                title: "In Progress",
                rows: inProgress
            ))
        }
        if !next.isEmpty {
            sections.append(CapturePickerSection(
                id: "unqueued-next",
                kind: .unqueuedNext,
                title: "Next",
                rows: next
            ))
        }
        if !now.isEmpty {
            sections.append(CapturePickerSection(
                id: "now",
                kind: .now,
                title: "This Week's Bets",
                rows: now
            ))
        }
        for route in noteOrder {
            sections.append(CapturePickerSection(
                id: "note-\(route)",
                kind: .note,
                title: "\(route).md",
                subtitle: Self.noteKindSubtitle(noteKinds[route] ?? nil),
                rows: noteRows[route] ?? []
            ))
        }
        return sections
    }

    private static func noteKindSubtitle(_ noteKind: String?) -> String? {
        switch noteKind {
        case "inbox":
            return "Inbox"
        case "area":
            return "Area"
        case "project":
            return "Project"
        default:
            return nil
        }
    }

    // MARK: - Filtered view

    private struct RankedEntry {
        let entry: TaskLinkPickerIndexEntry
        let score: Int
        let highlights: TaskLinkMatchHighlights
    }

    private func rank(tokens: [String]) -> [RankedEntry] {
        var ranked: [RankedEntry] = []
        for entry in entries {
            var total = 0
            var highlights = TaskLinkMatchHighlights()
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

    private func groupedRow(for entry: TaskLinkPickerIndexEntry) -> CapturePickerRow {
        baseRow(for: entry, depth: 0, chipText: nil)
    }

    private func groupedNoteRow(for entry: TaskLinkPickerIndexEntry) -> CapturePickerRow {
        baseRow(for: entry, depth: entry.candidate.depth ?? 0, chipText: nil)
    }

    private func filteredRow(
        for entry: TaskLinkPickerIndexEntry,
        highlights: TaskLinkMatchHighlights
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
        for entry: TaskLinkPickerIndexEntry,
        depth: Int,
        chipText: String?,
        textMatchRanges: [Range<Int>] = [],
        routeMatchRanges: [Range<Int>] = [],
        blockIDMatchRanges: [Range<Int>] = []
    ) -> CapturePickerRow {
        let candidate = entry.candidate
        let pending: CapturePickerPendingBlockID?
        let insertion: String?
        if candidate.requiresBlockID {
            pending = CapturePickerPendingBlockID(
                route: candidate.route ?? "",
                taskRef: candidate.taskRef ?? "",
                suggestions: candidate.blockIDSuggestions
            )
            insertion = nil
        } else {
            pending = nil
            insertion = candidate.replacement
        }
        return CapturePickerRow(
            id: Self.key(for: candidate),
            bobIndex: entry.bobIndex,
            glyph: .task(entry.status),
            displayText: entry.display.text,
            textSegments: entry.display.segments,
            textMatchRanges: textMatchRanges,
            route: candidate.route,
            blockID: entry.effectiveBlockID,
            routeMatchRanges: routeMatchRanges,
            blockIDMatchRanges: blockIDMatchRanges,
            chipText: chipText,
            badgeText: candidate.now ? "NOW" : nil,
            depth: depth,
            insertion: insertion,
            pendingBlockID: pending,
            scheduledText: candidate.scheduled.map { Self.formattedScheduledDate($0) },
            pullsForward: candidate.pullsForward,
            detail: CapturePickerRowDetail(
                statusText: entry.status.displayName,
                route: candidate.route,
                section: candidate.section,
                summary: pomodoroSummary(for: entry),
                insertionPrefix: "@"
            ),
            accessibilityLabel: accessibilityLabel(for: entry)
        )
    }

    // MARK: - Detail lines

    /// The detail-strip action line for `row`: the insertion for identified
    /// rows, or the Add block ID outcome for ID-less rows.
    public func actionLine(for row: CapturePickerRow) -> String {
        if let insertion = row.insertion {
            return "↩ inserts \(insertion) · ⇧↩ adds = to start it"
        }
        if let pending = row.pendingBlockID {
            if let first = pending.suggestions.first {
                return "↩ adds ^\(first) to \(pending.route).md, then inserts @\(pending.route):\(first)"
            }
            return "↩ names this task, then inserts its link"
        }
        return "↩ names this task, then inserts its link"
    }

    /// The pull-forward line for `row`, or nil when linking retires no
    /// future schedule.
    public func pullForwardLine(for row: CapturePickerRow) -> String? {
        guard row.pullsForward, let scheduled = row.scheduledText else {
            return nil
        }
        return "Scheduled \(scheduled) — linking pulls it forward"
    }

    /// `YYYY-MM-DD` renders as `Oct 3`, with the year appended outside
    /// `currentYear`. Unparseable input is shown raw.
    static func formattedScheduledDate(
        _ raw: String,
        currentYear: Int = Calendar.current.component(.year, from: Date())
    ) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              parts[0].count == 4,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day)
        else {
            return raw
        }
        let rendered = "\(months[month - 1]) \(day)"
        if year == currentYear {
            return rendered
        }
        return "\(rendered), \(year)"
    }

    private func chipText(for entry: TaskLinkPickerIndexEntry) -> String? {
        guard let pomodoro = entry.pomodoro else {
            return nil
        }
        let name = pomodoro.name.flatMap { $0.isEmpty ? nil : $0 }
        if pomodoro.isCurrent {
            let label = "Now · \(name ?? "Unnamed Pomodoro")"
            if let raw = pomodoro.timeRange, !raw.isEmpty {
                return "\(label) \(ActiveTaskPickerIndex.formattedTimeRange(raw))"
            }
            return label
        }
        return name ?? "Planned"
    }

    private func pomodoroSummary(for entry: TaskLinkPickerIndexEntry) -> String {
        guard let pomodoro = entry.pomodoro else {
            return "Not in a Pomodoro"
        }
        let name = pomodoro.name.flatMap { $0.isEmpty ? nil : $0 }
        if pomodoro.isCurrent {
            let label = "Now · \(name ?? "Unnamed Pomodoro")"
            if let raw = pomodoro.timeRange, !raw.isEmpty {
                return "\(label) \(ActiveTaskPickerIndex.formattedTimeRange(raw))"
            }
            return label
        }
        guard let name else {
            return "Queued in an unnamed Pomodoro"
        }
        let ordinal = entry.pomodoroLine.flatMap { pomodoroOrdinals[$0] } ?? 0
        return "Queued in \(name) (#\(ordinal))"
    }

    private func accessibilityLabel(for entry: TaskLinkPickerIndexEntry) -> String {
        let name = entry.candidate.statusName.flatMap { $0.isEmpty ? nil : $0 }
        let statusText = name ?? entry.status.displayName
        var parts = [statusText, entry.display.text]
        if entry.candidate.now {
            parts.append("This week's bet")
        }
        if let route = entry.candidate.route, let blockID = entry.effectiveBlockID {
            if entry.candidate.requiresBlockID {
                parts.append("Note \(route), suggested block \(blockID)")
            } else {
                parts.append("Note \(route), block \(blockID)")
            }
        } else if let route = entry.candidate.route {
            parts.append("Note \(route)")
        }
        parts.append(pomodoroSummary(for: entry))
        return parts.joined(separator: ". ") + "."
    }
}

// MARK: - Index entries

/// Bob's `group` wire value, in precedence order. A missing or unknown group
/// falls back to `note` so the row still appears under its note.
private enum TaskLinkGroup: Sendable {
    case queued
    case inProgress
    case next
    case now
    case note

    init(wireValue: String?) {
        switch wireValue {
        case "queued":
            self = .queued
        case "in_progress":
            self = .inProgress
        case "next":
            self = .next
        case "now":
            self = .now
        default:
            self = .note
        }
    }
}

/// One deduped candidate with its display text and weighted search fields.
/// Weights: display text 100%, `route:block-id` 90%, block ID 90%, route
/// 80%, Pomodoro name 70%, section 40%. For ID-less rows the block-ID and
/// combined fields use the first suggestion, so the locator stays
/// searchable.
private struct TaskLinkPickerIndexEntry: Sendable {
    let candidate: CaptureCompletionCandidate
    let bobIndex: Int
    let display: TaskDisplayText
    let status: CapturePickerTaskStatus
    let group: TaskLinkGroup
    let pomodoro: ActiveTaskPomodoro?
    let pomodoroLine: Int?
    let route: String?
    /// The locator's block ID: Bob's ID, or the first suggestion on ID-less
    /// rows so `route plus suggestion` renders and matches.
    let effectiveBlockID: String?
    let textField: FuzzyField
    let blockField: FuzzyField?
    let combinedField: FuzzyField?
    let combinedRouteLength: Int
    let pomodoroField: FuzzyField?
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
        self.group = TaskLinkGroup(wireValue: candidate.group)
        self.pomodoro = candidate.pomodoro
        self.pomodoroLine = candidate.pomodoro?.line
        self.route = candidate.route
        if let blockID = candidate.blockID, !blockID.isEmpty {
            self.effectiveBlockID = blockID
        } else {
            self.effectiveBlockID = candidate.blockIDSuggestions.first
        }
        self.textField = FuzzyField(display.text)
        if let effectiveBlockID, !effectiveBlockID.isEmpty {
            self.blockField = FuzzyField(effectiveBlockID)
        } else {
            self.blockField = nil
        }
        if let route = candidate.route, !route.isEmpty,
           let effectiveBlockID, !effectiveBlockID.isEmpty
        {
            self.combinedField = FuzzyField("\(route):\(effectiveBlockID)")
            self.combinedRouteLength = route.count
        } else {
            self.combinedField = nil
            self.combinedRouteLength = 0
        }
        if let name = candidate.pomodoro?.name, !name.isEmpty {
            self.pomodoroField = FuzzyField(name)
        } else {
            self.pomodoroField = nil
        }
        if let route = candidate.route, !route.isEmpty {
            self.routeField = FuzzyField(route)
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
    func bestFieldMatch(for token: String) -> TaskLinkFieldMatch? {
        var best: TaskLinkFieldMatch?
        func consider(weight: Int, field: FuzzyField?, target: TaskLinkMatchTarget) {
            guard let field,
                  let match = FuzzyMatcher.match(token: token, in: field)
            else {
                return
            }
            let weighted = match.score * weight / 100
            if best == nil || weighted > best!.weightedScore {
                best = TaskLinkFieldMatch(
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
        consider(weight: 70, field: pomodoroField, target: .pomodoroName)
        consider(weight: 40, field: sectionField, target: .section)
        return best
    }
}

private enum TaskLinkMatchTarget: Sendable {
    case text
    case combined
    case blockID
    case route
    case pomodoroName
    case section
}

private struct TaskLinkFieldMatch: Sendable {
    let weightedScore: Int
    let target: TaskLinkMatchTarget
    let positions: [Int]
    let combinedRouteLength: Int
}

/// Coalesced highlight positions gathered from every token's best field.
/// Section and Pomodoro-name matches raise the rank without highlighting.
private struct TaskLinkMatchHighlights: Sendable {
    var textPositions: [Int] = []
    var routePositions: [Int] = []
    var blockPositions: [Int] = []

    mutating func add(_ match: TaskLinkFieldMatch) {
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
        case .pomodoroName, .section:
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
