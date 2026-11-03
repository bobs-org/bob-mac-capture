import Foundation

/// One fetched move-picker snapshot in Bob order, with display text and
/// weighted search fields precomputed so every keystroke filters locally.
/// Empty-query rows keep document order grouped by section; filtered rows
/// use the `@route+` ranking (ID prefix, word prefix, substring,
/// subsequence) with identified rows winning ties. Rows are keyed by
/// `"route|ref"` because ID-less rows share Bob's empty replacement.
public struct ProjectTaskMovePickerIndex: Sendable {
    private let entries: [ProjectTaskMovePickerIndexEntry]
    private let context: ProjectTaskMovePickerContext

    public init(candidates: [CaptureCompletionCandidate], context: ProjectTaskMovePickerContext) {
        self.context = context
        var seen: Set<String> = []
        var entries: [ProjectTaskMovePickerIndexEntry] = []
        for candidate in candidates {
            let key = Self.key(for: candidate)
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            entries.append(ProjectTaskMovePickerIndexEntry(candidate: candidate, bobIndex: entries.count))
        }
        self.entries = entries
    }

    static func key(for candidate: CaptureCompletionCandidate) -> String {
        "\(candidate.route ?? "")|\(candidate.taskRef ?? "")"
    }

    public var count: Int {
        entries.count
    }

    public func presentation(filter: String) -> CapturePickerPresentation {
        let query = FuzzyQuery(filter, leadingSigil: context.scopeToken)
        if query.isEmpty {
            let sections = groupedSections()
            let ids = sections.flatMap { $0.rows.map(\.id) }
            let byID = Dictionary(
                uniqueKeysWithValues: sections.flatMap(\.rows).map { ($0.id, $0) }
            )
            let countText = entries.count == 1 ? "1 task" : "\(entries.count) tasks"
            let groupedRowCount = sections.reduce(0) { $0 + $1.rows.count }
            let budget: Int =
                entries.isEmpty ? 4 : min(max(groupedRowCount + sections.count, 4), 11)
            return CapturePickerPresentation(
                mode: .grouped,
                sections: sections,
                orderedRowIDs: ids,
                rowsByID: byID,
                totalCount: entries.count,
                matchCount: entries.count,
                countText: countText,
                emptyState: entries.isEmpty
                    ? .noTasksInNote(context.noteFileName) : nil,
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
        let groupedRowCount = rows.count + 1
        let budget = min(max(groupedRowCount, 4), 11)
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

    public func actionLine(for row: CapturePickerRow) -> String? {
        if let insertion = row.insertion {
            return "Inserts \(insertion)"
        }
        if let pending = row.pendingBlockID {
            if let first = pending.suggestions.first {
                return "↩ adds ^\(first) to \(pending.route).md, then inserts \(first)"
            }
            return "↩ names this task, then inserts its ID"
        }
        if let badge = row.badgeText, !badge.isEmpty {
            return badge
        }
        return "↩ names this task, then inserts its ID"
    }

    private func groupedSections() -> [CapturePickerSection] {
        var order: [String] = []
        var rowsBySection: [String: [CapturePickerRow]] = [:]
        for entry in entries {
            let section = entry.candidate.section ?? ""
            if rowsBySection[section] == nil {
                order.append(section)
                rowsBySection[section] = []
            }
            rowsBySection[section]!.append(baseRow(for: entry, chipText: nil))
        }
        return order.map { section in
            let rows = rowsBySection[section] ?? []
            let title = section.isEmpty ? "Tasks" : section
            return CapturePickerSection(
                id: section.isEmpty ? "tasks" : "section-\(section)",
                kind: .matches,
                title: title,
                rows: rows
            )
        }
    }

    private struct RankedEntry {
        let entry: ProjectTaskMovePickerIndexEntry
        let score: Int
        let highlights: ProjectTaskMoveMatchHighlights
    }

    private func rank(tokens: [String]) -> [RankedEntry] {
        var ranked: [RankedEntry] = []
        for entry in entries {
            var total = 0
            var highlights = ProjectTaskMoveMatchHighlights()
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
            let lhsIdentified = !($0.entry.candidate.requiresBlockID)
            let rhsIdentified = !($1.entry.candidate.requiresBlockID)
            if lhsIdentified != rhsIdentified {
                return lhsIdentified && !rhsIdentified
            }
            return $0.entry.bobIndex < $1.entry.bobIndex
        }
    }

    private func filteredRow(
        for entry: ProjectTaskMovePickerIndexEntry,
        highlights: ProjectTaskMoveMatchHighlights
    ) -> CapturePickerRow {
        baseRow(
            for: entry,
            chipText: chipText(for: entry),
            textMatchRanges: highlights.textRanges,
            routeMatchRanges: highlights.routeRanges,
            blockIDMatchRanges: highlights.blockRanges
        )
    }

    private func baseRow(
        for entry: ProjectTaskMovePickerIndexEntry,
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
                route: candidate.route ?? "",
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
        let scheduledText = formattedSchedule(candidate.scheduled)
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
            isHidden: candidate.hidden,
            badgeText: badge,
            depth: 0,
            insertion: insertion,
            pendingBlockID: pending,
            scheduledText: scheduledText,
            pullsForward: false,
            detail: CapturePickerRowDetail(
                statusText: entry.status.displayName,
                route: candidate.route,
                section: candidate.section,
                summary: candidate.consequence ?? "",
                insertionPrefix: ""
            ),
            accessibilityLabel: accessibilityLabel(for: entry)
        )
    }

    private func chipText(for entry: ProjectTaskMovePickerIndexEntry) -> String? {
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

    private func formattedSchedule(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private func accessibilityLabel(for entry: ProjectTaskMovePickerIndexEntry) -> String {
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
        if let consequence = entry.candidate.consequence, !consequence.isEmpty {
            parts.append(consequence)
        }
        return parts.joined(separator: ". ") + "."
    }
}

private struct ProjectTaskMovePickerIndexEntry: Sendable {
    let candidate: CaptureCompletionCandidate
    let bobIndex: Int
    let display: TaskDisplayText
    let status: CapturePickerTaskStatus
    let pomodoro: ActiveTaskPomodoro?
    let route: String?
    let effectiveBlockID: String?
    let textField: FuzzyField
    let blockField: FuzzyField?
    let combinedField: FuzzyField?
    let combinedRouteLength: Int
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
        self.pomodoro = candidate.pomodoro
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

    func bestFieldMatch(for token: String) -> ProjectTaskMoveFieldMatch? {
        var best: ProjectTaskMoveFieldMatch?
        func consider(weight: Int, field: FuzzyField?, target: ProjectTaskMoveMatchTarget) {
            guard let field,
                  let match = FuzzyMatcher.matchPreFolded(token: token, in: field)
            else {
                return
            }
            let weighted = match.score * weight / 100
            if best == nil || weighted > best!.weightedScore {
                best = ProjectTaskMoveFieldMatch(
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
        consider(weight: 50, field: statusField, target: .status)
        consider(weight: 40, field: sectionField, target: .section)
        return best
    }
}

private enum ProjectTaskMoveMatchTarget: Sendable {
    case text
    case combined
    case blockID
    case route
    case section
    case status
}

private struct ProjectTaskMoveFieldMatch: Sendable {
    let weightedScore: Int
    let target: ProjectTaskMoveMatchTarget
    let positions: [Int]
    let combinedRouteLength: Int
}

private struct ProjectTaskMoveMatchHighlights: Sendable {
    var textPositions: [Int] = []
    var routePositions: [Int] = []
    var blockPositions: [Int] = []

    mutating func add(_ match: ProjectTaskMoveFieldMatch) {
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
        case .section, .status:
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
