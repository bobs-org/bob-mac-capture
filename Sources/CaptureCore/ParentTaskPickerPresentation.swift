import Foundation

/// Whether a parent-task picker session searches one note or every capture
/// note. Wire values match Bob's `picker.scope`.
public enum ParentTaskPickerScope: String, Equatable, Sendable {
    case note
    case vault
}

/// Server-authored parent-task picker context: scoped `@route+` vs vault-wide
/// `+`, the capsule token, highlight and Backspace ranges, and optional
/// lone-plus operator-continuation keys. Swift never classifies capture
/// syntax from these keys; it only routes them.
public struct ParentTaskPickerContext: Equatable, Sendable {
    public let scope: ParentTaskPickerScope
    public let scopeToken: String
    public let noteTarget: String?
    public let markerRange: CaptureRange
    public let triggerRemovalRange: CaptureRange
    public let actionContinuationKeys: [String]

    public init(
        scope: ParentTaskPickerScope,
        scopeToken: String,
        noteTarget: String? = nil,
        markerRange: CaptureRange,
        triggerRemovalRange: CaptureRange,
        actionContinuationKeys: [String] = []
    ) {
        self.scope = scope
        self.scopeToken = scopeToken
        self.noteTarget = noteTarget
        self.markerRange = markerRange
        self.triggerRemovalRange = triggerRemovalRange
        self.actionContinuationKeys = actionContinuationKeys
    }

    public var isVault: Bool {
        scope == .vault
    }

    /// Dual-use lone `+` only: Bob listed keys that continue a Pomodoro
    /// operator instead of filtering.
    public var isLonePlusOperator: Bool {
        !actionContinuationKeys.isEmpty
    }

    /// Note filename for the scope capsule and empty state (`cash.md`).
    public var noteFileName: String {
        if let noteTarget, !noteTarget.isEmpty {
            return noteTarget
        }
        return "this note"
    }

    public static func vault(
        markerRange: CaptureRange,
        actionContinuationKeys: [String] = []
    ) -> ParentTaskPickerContext {
        ParentTaskPickerContext(
            scope: .vault,
            scopeToken: "+",
            noteTarget: nil,
            markerRange: markerRange,
            triggerRemovalRange: markerRange,
            actionContinuationKeys: actionContinuationKeys
        )
    }

    public static func note(
        route: String,
        noteTarget: String,
        markerRange: CaptureRange,
        triggerRemovalRange: CaptureRange
    ) -> ParentTaskPickerContext {
        ParentTaskPickerContext(
            scope: .note,
            scopeToken: "@\(route)+",
            noteTarget: noteTarget,
            markerRange: markerRange,
            triggerRemovalRange: triggerRemovalRange
        )
    }
}

/// One fetched parent-task snapshot in Bob order, with display text and
/// weighted search fields precomputed so every keystroke filters locally.
/// Vault empty-query rows keep the colon groups; scoped empty-query rows
/// keep document order. Rows are keyed by `"route|ref"` because ID-less
/// rows share Bob's empty replacement.
public struct ParentTaskPickerIndex: Sendable {
    private let entries: [ParentTaskPickerIndexEntry]
    private let pomodoroOrdinals: [Int: Int]
    private let context: ParentTaskPickerContext

    public init(candidates: [CaptureCompletionCandidate], context: ParentTaskPickerContext) {
        self.context = context
        var seen: Set<String> = []
        var entries: [ParentTaskPickerIndexEntry] = []
        for candidate in candidates {
            let key = Self.key(for: candidate)
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            entries.append(ParentTaskPickerIndexEntry(candidate: candidate, bobIndex: entries.count))
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

    static func key(for candidate: CaptureCompletionCandidate) -> String {
        "\(candidate.route ?? "")|\(candidate.taskRef ?? "")"
    }

    public var count: Int {
        entries.count
    }

    public func presentation(filter: String) -> CapturePickerPresentation {
        let groupedSections = context.isVault ? groupedRows() : documentOrderRows()
        let groupedRowCount = groupedSections.reduce(0) { $0 + $1.rows.count }
        let budget: Int
        if entries.isEmpty {
            budget = 4
        } else {
            budget = min(max(groupedRowCount + groupedSections.count, 4), 11)
        }

        let query = FuzzyQuery(filter, leadingSigil: "+")
        if query.isEmpty {
            let ids = groupedSections.flatMap { $0.rows.map(\.id) }
            let byID = Dictionary(
                uniqueKeysWithValues: groupedSections.flatMap(\.rows).map { ($0.id, $0) }
            )
            let countText = entries.count == 1 ? "1 task" : "\(entries.count) tasks"
            return CapturePickerPresentation(
                mode: .grouped,
                sections: groupedSections,
                orderedRowIDs: ids,
                rowsByID: byID,
                totalCount: entries.count,
                matchCount: entries.count,
                countText: countText,
                emptyState: entries.isEmpty ? emptyCatalogState : nil,
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
        let ids = rows.map(\.id)
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

    public func actionLine(for row: CapturePickerRow) -> String {
        if let insertion = row.insertion {
            return "Inserts \(insertion)"
        }
        if let pending = row.pendingBlockID {
            if let first = pending.suggestions.first {
                return "↩ adds ^\(first) to \(pending.route).md, then inserts @\(pending.route)+\(first)"
            }
            return "↩ names this task, then inserts @route+id"
        }
        return "↩ names this task, then inserts @route+id"
    }

    private var emptyCatalogState: CapturePickerEmptyState {
        if context.isVault {
            return .noCaptureNoteTasks
        }
        return .noTasksInNote(context.noteFileName)
    }

    private func documentOrderRows() -> [CapturePickerSection] {
        let rows = entries.map { groupedNoteRow(for: $0) }
        return [
            CapturePickerSection(
                id: "document",
                kind: .matches,
                title: "",
                rows: rows
            ),
        ]
    }

    private func groupedRows() -> [CapturePickerSection] {
        var pomodoroOrder: [Int] = []
        var pomodoroRows: [Int: [CapturePickerRow]] = [:]
        var inProgress: [CapturePickerRow] = []
        var next: [CapturePickerRow] = []
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
            case .queued, .note:
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

    private struct RankedEntry {
        let entry: ParentTaskPickerIndexEntry
        let score: Int
        let highlights: ParentTaskMatchHighlights
    }

    private func rank(tokens: [String]) -> [RankedEntry] {
        var ranked: [RankedEntry] = []
        for entry in entries {
            var total = 0
            var highlights = ParentTaskMatchHighlights()
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

    private func groupedRow(for entry: ParentTaskPickerIndexEntry) -> CapturePickerRow {
        baseRow(for: entry, depth: 0, chipText: nil)
    }

    private func groupedNoteRow(for entry: ParentTaskPickerIndexEntry) -> CapturePickerRow {
        baseRow(for: entry, depth: entry.candidate.depth ?? 0, chipText: nil)
    }

    private func filteredRow(
        for entry: ParentTaskPickerIndexEntry,
        highlights: ParentTaskMatchHighlights
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
        for entry: ParentTaskPickerIndexEntry,
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
            badgeText: nil,
            depth: depth,
            insertion: insertion,
            pendingBlockID: pending,
            scheduledText: nil,
            pullsForward: false,
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

    private func chipText(for entry: ParentTaskPickerIndexEntry) -> String? {
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

    private func pomodoroSummary(for entry: ParentTaskPickerIndexEntry) -> String {
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

    private func accessibilityLabel(for entry: ParentTaskPickerIndexEntry) -> String {
        let name = entry.candidate.statusName.flatMap { $0.isEmpty ? nil : $0 }
        let statusText = name ?? entry.status.displayName
        var parts = [statusText, entry.display.text]
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

private enum ParentTaskGroup: Sendable {
    case queued
    case inProgress
    case next
    case note

    init(wireValue: String?) {
        switch wireValue {
        case "queued":
            self = .queued
        case "in_progress":
            self = .inProgress
        case "next":
            self = .next
        default:
            self = .note
        }
    }
}

private struct ParentTaskPickerIndexEntry: Sendable {
    let candidate: CaptureCompletionCandidate
    let bobIndex: Int
    let display: TaskDisplayText
    let status: CapturePickerTaskStatus
    let group: ParentTaskGroup
    let pomodoro: ActiveTaskPomodoro?
    let pomodoroLine: Int?
    let route: String?
    let effectiveBlockID: String?
    let textField: FuzzyField
    let blockField: FuzzyField?
    let combinedField: FuzzyField?
    let combinedRouteLength: Int
    let pomodoroField: FuzzyField?
    let routeField: FuzzyField?
    let sectionField: FuzzyField?
    let statusField: FuzzyField?

    init(candidate: CaptureCompletionCandidate, bobIndex: Int) {
        self.candidate = candidate
        self.bobIndex = bobIndex
        let display = TaskDisplayText(parsing: candidate.text ?? candidate.replacement)
        self.display = display
        self.status = CapturePickerTaskStatus(
            symbol: candidate.statusSymbol,
            name: candidate.statusName
        )
        self.group = ParentTaskGroup(wireValue: candidate.group)
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
            self.combinedField = FuzzyField("\(route)+\(effectiveBlockID)")
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
        if let statusName = candidate.statusName, !statusName.isEmpty {
            self.statusField = FuzzyField(statusName)
        } else {
            self.statusField = nil
        }
    }

    func bestFieldMatch(for token: String) -> ParentTaskFieldMatch? {
        var best: ParentTaskFieldMatch?
        func consider(weight: Int, field: FuzzyField?, target: ParentTaskMatchTarget) {
            guard let field,
                  let match = FuzzyMatcher.match(token: token, in: field)
            else {
                return
            }
            let weighted = match.score * weight / 100
            if best == nil || weighted > best!.weightedScore {
                best = ParentTaskFieldMatch(
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
        consider(weight: 50, field: statusField, target: .status)
        consider(weight: 40, field: sectionField, target: .section)
        return best
    }
}

private enum ParentTaskMatchTarget: Sendable {
    case text
    case combined
    case blockID
    case route
    case pomodoroName
    case section
    case status
}

private struct ParentTaskFieldMatch: Sendable {
    let weightedScore: Int
    let target: ParentTaskMatchTarget
    let positions: [Int]
    let combinedRouteLength: Int
}

private struct ParentTaskMatchHighlights: Sendable {
    var textPositions: [Int] = []
    var routePositions: [Int] = []
    var blockPositions: [Int] = []

    mutating func add(_ match: ParentTaskFieldMatch) {
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
        case .pomodoroName, .section, .status:
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
