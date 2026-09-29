import Foundation

/// One fetched `active_task` snapshot in Bob order, with display text and
/// weighted search fields precomputed so every keystroke filters locally.
/// Presents `CapturePickerPresentation` values for the source-agnostic card.
public struct ActiveTaskPickerIndex: Sendable {
    private let entries: [ActiveTaskPickerIndexEntry]
    /// Pomodoro line to its 1-based section ordinal (first-appearance order).
    private let pomodoroOrdinals: [Int: Int]

    public init(candidates: [CaptureCompletionCandidate]) {
        var seen: Set<String> = []
        var entries: [ActiveTaskPickerIndexEntry] = []
        for candidate in candidates {
            if seen.contains(candidate.replacement) {
                continue
            }
            seen.insert(candidate.replacement)
            entries.append(ActiveTaskPickerIndexEntry(candidate: candidate, bobIndex: entries.count))
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

    public var count: Int {
        entries.count
    }

    /// Presents the snapshot for `filter`: grouped sections for an empty
    /// query, one ranked flat section otherwise.
    public func presentation(filter: String) -> CapturePickerPresentation {
        let groupedSections = groupedRows()
        let groupedRowCount = groupedSections.reduce(0) { $0 + $1.rows.count }
        let budget: Int
        if entries.isEmpty {
            budget = 4
        } else {
            budget = min(max(groupedRowCount + groupedSections.count, 4), 11)
        }

        let query = FuzzyQuery(filter)
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
                emptyState: entries.isEmpty ? .noActiveTasks : nil,
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
            emptyState: rows.isEmpty ? .noMatches(query: filter) : nil,
            visibleRowBudget: budget
        )
    }

    // MARK: - Grouped view

    private func groupedRows() -> [CapturePickerSection] {
        var pomodoroOrder: [Int] = []
        var pomodoroRows: [Int: [CapturePickerRow]] = [:]
        var inProgress: [CapturePickerRow] = []
        var next: [CapturePickerRow] = []
        var other: [CapturePickerRow] = []
        for entry in entries {
            let row = baseRow(for: entry)
            if entry.pomodoroLine != nil {
                let line = entry.pomodoroLine!
                if pomodoroRows[line] == nil {
                    pomodoroOrder.append(line)
                    pomodoroRows[line] = []
                }
                pomodoroRows[line]!.append(row)
            } else {
                switch entry.status {
                case .inProgress:
                    inProgress.append(row)
                case .next:
                    next.append(row)
                case .todo, .blocked, .done, .canceled, .other:
                    other.append(row)
                }
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
                timeRangeText: pomodoro?.timeRange.map { Self.formattedTimeRange($0) },
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
        if !other.isEmpty {
            sections.append(CapturePickerSection(
                id: "other",
                kind: .other,
                title: "Other",
                rows: other
            ))
        }
        return sections
    }

    // MARK: - Filtered view

    private struct RankedEntry {
        let entry: ActiveTaskPickerIndexEntry
        let score: Int
        let highlights: ActiveTaskMatchHighlights
    }

    private func rank(tokens: [String]) -> [RankedEntry] {
        var ranked: [RankedEntry] = []
        for entry in entries {
            var total = 0
            var highlights = ActiveTaskMatchHighlights()
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

    private func baseRow(for entry: ActiveTaskPickerIndexEntry) -> CapturePickerRow {
        CapturePickerRow(
            id: entry.candidate.replacement,
            bobIndex: entry.bobIndex,
            glyph: .task(entry.status),
            displayText: entry.display.text,
            textSegments: entry.display.segments,
            route: entry.candidate.route,
            blockID: entry.candidate.blockID,
            insertion: "^\(entry.candidate.replacement)",
            detail: CapturePickerRowDetail(
                statusText: entry.status.displayName,
                route: entry.candidate.route,
                section: entry.candidate.section,
                summary: pomodoroSummary(for: entry),
                insertionPrefix: "^"
            ),
            accessibilityLabel: accessibilityLabel(for: entry)
        )
    }

    private func filteredRow(
        for entry: ActiveTaskPickerIndexEntry,
        highlights: ActiveTaskMatchHighlights
    ) -> CapturePickerRow {
        CapturePickerRow(
            id: entry.candidate.replacement,
            bobIndex: entry.bobIndex,
            glyph: .task(entry.status),
            displayText: entry.display.text,
            textSegments: entry.display.segments,
            textMatchRanges: highlights.textRanges,
            route: entry.candidate.route,
            blockID: entry.candidate.blockID,
            routeMatchRanges: highlights.routeRanges,
            blockIDMatchRanges: highlights.blockRanges,
            chipText: chipText(for: entry),
            insertion: "^\(entry.candidate.replacement)",
            detail: CapturePickerRowDetail(
                statusText: entry.status.displayName,
                route: entry.candidate.route,
                section: entry.candidate.section,
                summary: pomodoroSummary(for: entry),
                insertionPrefix: "^"
            ),
            accessibilityLabel: accessibilityLabel(for: entry)
        )
    }

    private func chipText(for entry: ActiveTaskPickerIndexEntry) -> String? {
        guard let pomodoro = entry.pomodoro else {
            return nil
        }
        let name = pomodoro.name.flatMap { $0.isEmpty ? nil : $0 }
        if pomodoro.isCurrent {
            let label = "Now · \(name ?? "Unnamed Pomodoro")"
            if let raw = pomodoro.timeRange, !raw.isEmpty {
                return "\(label) \(Self.formattedTimeRange(raw))"
            }
            return label
        }
        return name ?? "Planned"
    }

    private func pomodoroSummary(for entry: ActiveTaskPickerIndexEntry) -> String {
        guard let pomodoro = entry.pomodoro else {
            return "Not in a Pomodoro"
        }
        let name = pomodoro.name.flatMap { $0.isEmpty ? nil : $0 }
        if pomodoro.isCurrent {
            let label = "Now · \(name ?? "Unnamed Pomodoro")"
            if let raw = pomodoro.timeRange, !raw.isEmpty {
                return "\(label) \(Self.formattedTimeRange(raw))"
            }
            return label
        }
        guard let name else {
            return "Queued in an unnamed Pomodoro"
        }
        let ordinal = entry.pomodoroLine.flatMap { pomodoroOrdinals[$0] } ?? 0
        return "Queued in \(name) (#\(ordinal))"
    }

    private func accessibilityLabel(for entry: ActiveTaskPickerIndexEntry) -> String {
        let name = entry.candidate.statusName.flatMap { $0.isEmpty ? nil : $0 }
        let statusText = name ?? entry.status.displayName
        var parts = [statusText, entry.display.text]
        if let route = entry.candidate.route, let blockID = entry.candidate.blockID {
            parts.append("Note \(route), block \(blockID)")
        } else if let route = entry.candidate.route {
            parts.append("Note \(route)")
        } else if let blockID = entry.candidate.blockID {
            parts.append("Block \(blockID)")
        }
        if let pomodoro = entry.pomodoro {
            let name = pomodoro.name.flatMap { $0.isEmpty ? nil : $0 }
            if pomodoro.isCurrent {
                parts.append(pomodoroSummary(for: entry))
            } else if let name {
                let ordinal = entry.pomodoroLine.flatMap { pomodoroOrdinals[$0] } ?? 0
                parts.append("Queued in \(name), Pomodoro \(ordinal)")
            } else {
                parts.append("Queued in an unnamed Pomodoro")
            }
        } else {
            parts.append("Not in a Pomodoro")
        }
        return parts.joined(separator: ". ") + "."
    }

    /// `0900-0930` becomes `09:00–09:30`; anything not in `HHMM-HHMM` form is
    /// shown raw.
    static func formattedTimeRange(_ raw: String) -> String {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 4,
              parts[1].count == 4,
              parts[0].allSatisfy({ $0.isNumber }),
              parts[1].allSatisfy({ $0.isNumber })
        else {
            return raw
        }
        func split(_ part: Substring) -> (Int, Int)? {
            let hour = Int(String(part.prefix(2))) ?? 99
            let minute = Int(String(part.suffix(2))) ?? 99
            guard (0...23).contains(hour), (0...59).contains(minute) else {
                return nil
            }
            return (hour, minute)
        }
        guard let start = split(parts[0]), let end = split(parts[1]) else {
            return raw
        }
        func two(_ value: Int) -> String {
            value < 10 ? "0\(value)" : "\(value)"
        }
        return "\(two(start.0)):\(two(start.1))–\(two(end.0)):\(two(end.1))"
    }
}

// MARK: - Index entries

/// One deduped candidate with its display text and weighted search fields.
/// Weights: display text 100%, block ID 90%, `route:block-id` 90%, Pomodoro
/// name 70%, route 60%, section 40%.
private struct ActiveTaskPickerIndexEntry: Sendable {
    let candidate: CaptureCompletionCandidate
    let bobIndex: Int
    let display: TaskDisplayText
    let status: CapturePickerTaskStatus
    let pomodoro: ActiveTaskPomodoro?
    let pomodoroLine: Int?
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
        self.pomodoro = candidate.pomodoro
        self.pomodoroLine = candidate.pomodoro?.line
        self.textField = FuzzyField(display.text)
        if let blockID = candidate.blockID, !blockID.isEmpty {
            self.blockField = FuzzyField(blockID)
        } else {
            self.blockField = nil
        }
        if let route = candidate.route, !route.isEmpty,
           let blockID = candidate.blockID, !blockID.isEmpty
        {
            self.combinedField = FuzzyField("\(route):\(blockID)")
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
    func bestFieldMatch(for token: String) -> ActiveTaskFieldMatch? {
        var best: ActiveTaskFieldMatch?
        func consider(weight: Int, field: FuzzyField?, target: ActiveTaskMatchTarget) {
            guard let field,
                  let match = FuzzyMatcher.match(token: token, in: field)
            else {
                return
            }
            let weighted = match.score * weight / 100
            if best == nil || weighted > best!.weightedScore {
                best = ActiveTaskFieldMatch(
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
        consider(weight: 70, field: pomodoroField, target: .pomodoroName)
        consider(weight: 60, field: routeField, target: .route)
        consider(weight: 40, field: sectionField, target: .section)
        return best
    }
}

private enum ActiveTaskMatchTarget: Sendable {
    case text
    case combined
    case blockID
    case route
    case pomodoroName
    case section
}

private struct ActiveTaskFieldMatch: Sendable {
    let weightedScore: Int
    let target: ActiveTaskMatchTarget
    let positions: [Int]
    let combinedRouteLength: Int
}

/// Coalesced highlight positions gathered from every token's best field.
/// Section and Pomodoro-name matches raise the rank without highlighting.
struct ActiveTaskMatchHighlights: Sendable {
    var textPositions: [Int] = []
    var routePositions: [Int] = []
    var blockPositions: [Int] = []

    fileprivate mutating func add(_ match: ActiveTaskFieldMatch) {
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
