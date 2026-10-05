import Foundation

/// One fetched `task_complete` snapshot in Bob order, with display text and
/// weighted search fields precomputed so every keystroke filters locally.
/// Presents `CapturePickerPresentation` values for the source-agnostic card.
/// Rows are keyed by `"note_path|ref"` (never by `replacement`, which Bob
/// sends as `""` for ID-less and guarded rows), and the grouped view follows
/// Bob's order and `group` with per-Pomodoro Today sections first.
///
/// Grouped sections in Bob precedence: one section per today Pomodoro
/// (running with the NOW pill, completed recent-first with 🍅, queued with
/// UP NEXT), then "In today's note", In Progress, Next, and one section per
/// note. Hidden rows sort after visible ones and recurring rows sort last
/// within their section. Filtered sections are Today then All open tasks.
public struct TaskCompletePickerIndex: Sendable {
    private let entries: [TaskCompletePickerIndexEntry]
    private let pomodoroOrdinals: [Int: Int]

    public init(candidates: [CaptureCompletionCandidate]) {
        var seen: Set<String> = []
        var entries: [TaskCompletePickerIndexEntry] = []
        for candidate in candidates {
            let key = Self.key(for: candidate)
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            entries.append(TaskCompletePickerIndexEntry(candidate: candidate, bobIndex: entries.count))
        }
        self.entries = entries
        var ordinals: [Int: Int] = [:]
        for entry in entries {
            guard let line = entry.todayPomodoroLine, ordinals[line] == nil else {
                continue
            }
            ordinals[line] = ordinals.count + 1
        }
        self.pomodoroOrdinals = ordinals
    }

    /// Deduped row key: exact note path plus the stale-safe task ref.
    /// ID-less and guarded rows share Bob's empty replacement, so keying on
    /// it would collapse them. Falls back to the display locator for rows
    /// from older Bob binaries that predate `note_path`.
    static func key(for candidate: CaptureCompletionCandidate) -> String {
        let note = candidate.notePath ?? candidate.locator ?? candidate.route ?? ""
        return "\(note)|\(candidate.taskRef ?? "")"
    }

    public var count: Int {
        entries.count
    }

    /// Presents the snapshot for `filter`: grouped sections for an empty
    /// query, Today plus All sections otherwise. The filter may carry the
    /// `!` seed from the draft; it is stripped before matching.
    public func presentation(filter: String) -> CapturePickerPresentation {
        let groupedSections = groupedRows()
        let groupedRowCount = groupedSections.reduce(0) { $0 + $1.rows.count }
        let budget: Int
        if entries.isEmpty {
            budget = 4
        } else {
            budget = min(max(groupedRowCount + groupedSections.count, 4), 11)
        }

        let query = FuzzyQuery(filter, leadingSigil: "!")
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
        var todayRows: [CapturePickerRow] = []
        var allRows: [CapturePickerRow] = []
        for scored in ranked {
            let row = filteredRow(for: scored.entry, highlights: scored.highlights)
            if scored.entry.group == .today {
                todayRows.append(row)
            } else {
                allRows.append(row)
            }
        }
        var sections: [CapturePickerSection] = []
        if !todayRows.isEmpty {
            sections.append(CapturePickerSection(
                id: "task-complete-today",
                kind: .matches,
                title: "Today",
                rows: todayRows
            ))
        }
        if !allRows.isEmpty {
            sections.append(CapturePickerSection(
                id: "task-complete-all",
                kind: .matches,
                title: "All open tasks",
                rows: allRows
            ))
        }
        let allPresented = todayRows + allRows
        let ids = allPresented.map { $0.id }
        let byID = Dictionary(uniqueKeysWithValues: allPresented.map { ($0.id, $0) })
        return CapturePickerPresentation(
            mode: .filtered,
            sections: sections,
            orderedRowIDs: ids,
            rowsByID: byID,
            totalCount: entries.count,
            matchCount: allPresented.count,
            countText: "\(allPresented.count) of \(entries.count)",
            emptyState: allPresented.isEmpty ? .noMatches(query: filter, noun: "open tasks") : nil,
            visibleRowBudget: budget
        )
    }

    // MARK: - Grouped view

    private func groupedRows() -> [CapturePickerSection] {
        var pomodoroOrder: [Int] = []
        var pomodoroRows: [Int: [TaskCompletePickerIndexEntry]] = [:]
        var todayNote: [TaskCompletePickerIndexEntry] = []
        var inProgress: [TaskCompletePickerIndexEntry] = []
        var next: [TaskCompletePickerIndexEntry] = []
        var noteOrder: [String] = []
        var noteRows: [String: [TaskCompletePickerIndexEntry]] = [:]
        for entry in entries {
            switch entry.group {
            case .today:
                if let line = entry.todayPomodoroLine, entry.todayRole != .noted {
                    if pomodoroRows[line] == nil {
                        pomodoroOrder.append(line)
                        pomodoroRows[line] = []
                    }
                    pomodoroRows[line]!.append(entry)
                } else {
                    todayNote.append(entry)
                }
            case .inProgress:
                inProgress.append(entry)
            case .next:
                next.append(entry)
            case .open:
                let note = entry.noteTitle
                if noteRows[note] == nil {
                    noteOrder.append(note)
                    noteRows[note] = []
                }
                noteRows[note]!.append(entry)
            }
        }
        var sections: [CapturePickerSection] = []
        for line in pomodoroOrder {
            let ordinal = pomodoroOrdinals[line] ?? 0
            let first = (pomodoroRows[line] ?? []).first
            let pomodoro = first?.candidate.today?.pomodoro
            let name = pomodoro?.name.flatMap { $0.isEmpty ? nil : $0 }
            let status = pomodoro?.status ?? "queued"
            let title: String
            let isCurrent: Bool
            switch status {
            case "running":
                title = name ?? "Unnamed Pomodoro"
                isCurrent = true
            case "completed":
                if let name {
                    title = "🍅 \(name)"
                } else {
                    title = "🍅 Unnamed Pomodoro"
                }
                isCurrent = false
            default:
                if let name {
                    title = "UP NEXT \(name)"
                } else {
                    title = "UP NEXT Unnamed Pomodoro"
                }
                isCurrent = false
            }
            let rows = Self.orderedWithinSection(pomodoroRows[line] ?? []).map { groupedRow(for: $0) }
            sections.append(CapturePickerSection(
                id: "task-complete-today-\(line)",
                kind: .pomodoro,
                title: title,
                timeRangeText: pomodoro?.timeRange.map { ActiveTaskPickerIndex.formattedTimeRange($0) },
                ordinal: ordinal,
                isCurrent: isCurrent,
                rows: rows
            ))
        }
        if !todayNote.isEmpty {
            sections.append(CapturePickerSection(
                id: "task-complete-today-note",
                kind: .other,
                title: "In today's note",
                rows: Self.orderedWithinSection(todayNote).map { groupedRow(for: $0) }
            ))
        }
        if !inProgress.isEmpty {
            sections.append(CapturePickerSection(
                id: "task-complete-in-progress",
                kind: .unqueuedInProgress,
                title: "In Progress",
                rows: Self.orderedWithinSection(inProgress).map { groupedRow(for: $0) }
            ))
        }
        if !next.isEmpty {
            sections.append(CapturePickerSection(
                id: "task-complete-next",
                kind: .unqueuedNext,
                title: "Next",
                rows: Self.orderedWithinSection(next).map { groupedRow(for: $0) }
            ))
        }
        for note in noteOrder {
            sections.append(CapturePickerSection(
                id: "task-complete-note-\(note)",
                kind: .note,
                title: note,
                rows: Self.orderedWithinSection(noteRows[note] ?? []).map { groupedNoteRow(for: $0) }
            ))
        }
        return sections
    }

    /// Visible rows first, then hidden, then recurring last, preserving Bob
    /// order inside each tier.
    static func orderedWithinSection(_ entries: [TaskCompletePickerIndexEntry]) -> [TaskCompletePickerIndexEntry] {
        let visible = entries.filter { !$0.candidate.hidden && !$0.candidate.recurring }
        let hidden = entries.filter { $0.candidate.hidden && !$0.candidate.recurring }
        let recurring = entries.filter { $0.candidate.recurring }
        let hiddenRecurring = recurring.filter { $0.candidate.hidden }
        let visibleRecurring = recurring.filter { !$0.candidate.hidden }
        return visible + hidden + visibleRecurring + hiddenRecurring
    }

    // MARK: - Filtered view

    private struct RankedEntry {
        let entry: TaskCompletePickerIndexEntry
        let score: Int
        let highlights: TaskCompleteMatchHighlights
    }

    private func rank(tokens: [String]) -> [RankedEntry] {
        var todayRanked: [RankedEntry] = []
        var otherRanked: [RankedEntry] = []
        for entry in entries {
            var total = 0
            var highlights = TaskCompleteMatchHighlights()
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
                let ranked = RankedEntry(entry: entry, score: total, highlights: highlights)
                if entry.group == .today {
                    todayRanked.append(ranked)
                } else {
                    otherRanked.append(ranked)
                }
            }
        }
        let sort: (RankedEntry, RankedEntry) -> Bool = {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.entry.bobIndex < $1.entry.bobIndex
        }
        return todayRanked.sorted(by: sort) + otherRanked.sorted(by: sort)
    }

    // MARK: - Rows

    private func groupedRow(for entry: TaskCompletePickerIndexEntry) -> CapturePickerRow {
        baseRow(for: entry, depth: 0, chipText: nil)
    }

    private func groupedNoteRow(for entry: TaskCompletePickerIndexEntry) -> CapturePickerRow {
        baseRow(for: entry, depth: entry.candidate.depth ?? 0, chipText: nil)
    }

    private func filteredRow(
        for entry: TaskCompletePickerIndexEntry,
        highlights: TaskCompleteMatchHighlights
    ) -> CapturePickerRow {
        baseRow(
            for: entry,
            depth: 0,
            chipText: nil,
            textMatchRanges: highlights.textRanges,
            routeMatchRanges: highlights.routeRanges,
            blockIDMatchRanges: highlights.blockRanges
        )
    }

    private func baseRow(
        for entry: TaskCompletePickerIndexEntry,
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
            pending = nil
            insertion = nil
            badge = candidate.disabledReason
        } else if candidate.requiresBlockID {
            pending = CapturePickerPendingBlockID(
                route: candidate.notePath ?? candidate.locator ?? candidate.route ?? "",
                taskRef: candidate.taskRef ?? "",
                suggestions: candidate.blockIDSuggestions
            )
            insertion = nil
            badge = nil
        } else {
            pending = nil
            insertion = candidate.replacement.isEmpty ? nil : candidate.replacement
            if candidate.sessions >= 2 {
                badge = "🍅 \(candidate.sessions)"
            } else {
                badge = nil
            }
        }
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
            isSelectable: candidate.disabledReason == nil,
            insertion: insertion,
            pendingBlockID: pending,
            scheduledText: candidate.scheduled.map { Self.formattedScheduledDate($0) },
            pullsForward: false,
            detail: CapturePickerRowDetail(
                statusText: entry.status.displayName,
                route: candidate.locator ?? candidate.route,
                section: candidate.section,
                summary: summary(for: entry),
                insertionPrefix: "!"
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
            let symbol = statusSymbol(for: row) ?? " "
            return "Inserts \(insertion) — completes it [\(symbol)] → [x]"
        }
        if let pending = row.pendingBlockID {
            if let first = pending.suggestions.first {
                let locator = row.route ?? pending.route
                return "↩ adds ^\(first), then inserts !\(locator):\(first)"
            }
            return "↩ names this task, then inserts its completion"
        }
        if let badge = row.badgeText, !badge.isEmpty {
            return badge
        }
        return "↩ names this task, then inserts its completion"
    }

    private func statusSymbol(for row: CapturePickerRow) -> String? {
        switch row.glyph {
        case .task(let status):
            switch status {
            case .inProgress: return "/"
            case .next: return "*"
            case .todo: return " "
            case .blocked: return "?"
            case .done: return "x"
            case .canceled: return "-"
            case .other: return nil
            }
        default:
            return nil
        }
    }

    /// `YYYY-MM-DD` renders as `Oct 3`, with the year appended outside
    /// `currentYear`. Unparseable input is shown raw.
    static func formattedScheduledDate(
        _ raw: String,
        currentYear: Int = Calendar.current.component(.year, from: Date())
    ) -> String {
        TaskLinkPickerIndex.formattedScheduledDate(raw, currentYear: currentYear)
    }

    private func summary(for entry: TaskCompletePickerIndexEntry) -> String {
        if let reason = entry.candidate.disabledReason, !reason.isEmpty {
            return reason
        }
        if entry.candidate.requiresBlockID {
            return "Needs a block ID"
        }
        switch entry.group {
        case .today:
            switch entry.todayRole {
            case .running:
                return "Today · running"
            case .worked:
                return "Today · worked"
            case .queued:
                return "Today · queued"
            case .noted:
                return "In today's note"
            }
        case .inProgress:
            return "In Progress"
        case .next:
            return "Next"
        case .open:
            return "Open"
        }
    }

    private func accessibilityLabel(for entry: TaskCompletePickerIndexEntry) -> String {
        let name = entry.candidate.statusName.flatMap { $0.isEmpty ? nil : $0 }
        let statusText = name ?? entry.status.displayName
        var parts = [statusText, entry.display.text]
        let note = entry.candidate.notePath ?? entry.candidate.locator ?? entry.candidate.route ?? ""
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
}

// MARK: - Index entries

/// Bob's completable `group` wire value. Missing or unknown groups fall
/// back to `open` so the row still appears under its note.
enum TaskCompleteGroup: Sendable {
    case today
    case inProgress
    case next
    case open

    init(wireValue: String?) {
        switch wireValue {
        case "today":
            self = .today
        case "in_progress":
            self = .inProgress
        case "next":
            self = .next
        default:
            self = .open
        }
    }
}

/// Bob's today `role` wire value. Missing or unknown roles fall back to
/// `noted` so the row still appears under "In today's note".
enum TaskCompleteRole: Sendable {
    case running
    case worked
    case queued
    case noted

    init(wireValue: String?) {
        switch wireValue {
        case "running":
            self = .running
        case "worked":
            self = .worked
        case "queued":
            self = .queued
        default:
            self = .noted
        }
    }
}

/// One deduped candidate with its display text and weighted search fields.
/// Weights mirror the `:` picker: display text 100%, `locator:block-id`
/// 90%, block ID 90%, locator/note path 80%, Pomodoro name 70%, section
/// 40%. For ID-less rows the block-ID and combined fields use the first
/// suggestion, so the locator stays searchable.
struct TaskCompletePickerIndexEntry: Sendable {
    let candidate: CaptureCompletionCandidate
    let bobIndex: Int
    let display: TaskDisplayText
    let status: CapturePickerTaskStatus
    let group: TaskCompleteGroup
    let todayRole: TaskCompleteRole
    let todayPomodoroLine: Int?
    /// Short per-note section title: the exact note path including
    /// extension, falling back to the display locator for older Bob rows.
    let noteTitle: String
    /// The locator's block ID: Bob's ID, or the first suggestion on
    /// ID-less rows so `locator plus suggestion` renders and matches.
    let effectiveBlockID: String?
    let sessions: Int
    let textField: FuzzyField
    let blockField: FuzzyField?
    let combinedField: FuzzyField?
    let combinedRouteLength: Int
    let routeField: FuzzyField?
    let pomodoroField: FuzzyField?
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
        self.group = TaskCompleteGroup(wireValue: candidate.group)
        self.todayRole = TaskCompleteRole(wireValue: candidate.today?.role)
        self.todayPomodoroLine = candidate.today?.pomodoro?.line
        if let notePath = candidate.notePath, !notePath.isEmpty {
            self.noteTitle = notePath
        } else if let locator = candidate.locator, !locator.isEmpty {
            self.noteTitle = "\(locator).md"
        } else {
            self.noteTitle = "\(candidate.route ?? "Unknown").md"
        }
        if let blockID = candidate.blockID, !blockID.isEmpty {
            self.effectiveBlockID = blockID
        } else {
            self.effectiveBlockID = candidate.blockIDSuggestions.first
        }
        self.sessions = candidate.today?.sessions ?? 0
        self.textField = FuzzyField(display.text)
        if let effectiveBlockID, !effectiveBlockID.isEmpty {
            self.blockField = FuzzyField(effectiveBlockID)
        } else {
            self.blockField = nil
        }
        let locatorText = candidate.locator ?? candidate.notePath ?? candidate.route ?? ""
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
        if let name = candidate.today?.pomodoro?.name, !name.isEmpty {
            self.pomodoroField = FuzzyField(name)
        } else {
            self.pomodoroField = nil
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
    func bestFieldMatch(for token: String) -> TaskCompleteFieldMatch? {
        var best: TaskCompleteFieldMatch?
        func consider(weight: Int, field: FuzzyField?, target: TaskCompleteMatchTarget) {
            guard let field,
                  let match = FuzzyMatcher.match(token: token, in: field)
            else {
                return
            }
            let weighted = match.score * weight / 100
            if best == nil || weighted > best!.weightedScore {
                best = TaskCompleteFieldMatch(
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

enum TaskCompleteMatchTarget: Sendable {
    case text
    case combined
    case blockID
    case route
    case pomodoroName
    case section
}

struct TaskCompleteFieldMatch: Sendable {
    let weightedScore: Int
    let target: TaskCompleteMatchTarget
    let positions: [Int]
    let combinedRouteLength: Int
}

/// Coalesced highlight positions gathered from every token's best field.
/// Section and Pomodoro-name matches raise the rank without highlighting.
struct TaskCompleteMatchHighlights: Sendable {
    var textPositions: [Int] = []
    var routePositions: [Int] = []
    var blockPositions: [Int] = []

    mutating func add(_ match: TaskCompleteFieldMatch) {
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
