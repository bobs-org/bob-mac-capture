import Foundation

/// Presentation status feeding the New ID badge capsule and detail strip:
/// live availability of the current field text, the used-ID count, and the
/// item body Bob parsed. Populated whenever Bob sent a `block_id` object;
/// nil for the `^` source and older Bob responses without one.
public struct CapturePickerBlockIDStatus: Equatable, Sendable {
    public let availability: CapturePickerAvailability
    public let usedCount: Int
    public let body: String
    public let route: String
    public let relativeTarget: String
    public let marker: String
    public let isProjectNote: Bool

    public init(
        availability: CapturePickerAvailability,
        usedCount: Int,
        body: String,
        route: String,
        relativeTarget: String,
        marker: String,
        isProjectNote: Bool
    ) {
        self.availability = availability
        self.usedCount = usedCount
        self.body = body
        self.route = route
        self.relativeTarget = relativeTarget
        self.marker = marker
        self.isProjectNote = isProjectNote
    }
}

/// One fetched block-ID snapshot in Bob order, with display text and
/// weighted search fields precomputed so every keystroke filters locally.
/// Presents `CapturePickerPresentation` values for the source-agnostic card.
///
/// Link intent (or no field, for older Bob) groups the note's linkable tasks
/// by the note's own headings. New and project-note intents compose an ID
/// from Bob's suggestions with live availability against every ID already
/// in the note. `insertion` is always the exact string an accept inserts
/// into Bob's replacement range; `detail.insertionPrefix` is `"@"` so the
/// preview reads `@route` + marker + ID once the card renders the
/// `blockOnly` locator (a flow-phase view concern).
public struct BlockIDPickerIndex: Sendable {
    private let field: CaptureBlockIDField?
    private let route: String
    private let entries: [BlockIDLinkEntry]
    private let rules: BlockIDRules?
    private let usedByID: [String: CaptureUsedBlockID]
    private let usedOrder: [CaptureUsedBlockID]
    private let usedIDs: Set<String>
    /// Pomodoro day-file line to its 1-based ordinal (first-appearance
    /// order), so queued summaries read "Queued in BUGS (#1)" as in `^`.
    private let pomodoroOrdinals: [Int: Int]

    public init(
        field: CaptureBlockIDField?,
        candidates: [CaptureCompletionCandidate],
        route: String
    ) {
        self.field = field
        if let fieldRoute = field?.route, !fieldRoute.isEmpty {
            self.route = fieldRoute
        } else {
            self.route = route
        }
        var seen: Set<String> = []
        var entries: [BlockIDLinkEntry] = []
        for candidate in candidates {
            if seen.contains(candidate.replacement) {
                continue
            }
            seen.insert(candidate.replacement)
            entries.append(BlockIDLinkEntry(candidate: candidate, bobIndex: entries.count))
        }
        self.entries = entries
        self.rules = field.flatMap {
            BlockIDRules(allowedCharacter: $0.allowedCharacter, description: $0.allowedDescription)
        }
        let used = field?.used ?? []
        var usedByID: [String: CaptureUsedBlockID] = [:]
        for entry in used where usedByID[entry.id] == nil {
            usedByID[entry.id] = entry
        }
        self.usedByID = usedByID
        self.usedOrder = used
        self.usedIDs = Set(used.map { $0.id })
        var ordinals: [Int: Int] = [:]
        for entry in entries {
            guard let line = entry.candidate.pomodoro?.line, ordinals[line] == nil else {
                continue
            }
            ordinals[line] = ordinals.count + 1
        }
        self.pomodoroOrdinals = ordinals
    }

    /// Link intent, or no field (older Bob): the note's linkable tasks.
    /// Anything else is the New ID composer.
    private var isNewIDMode: Bool {
        field?.intent == .new || field?.intent == .projectNote
    }

    /// Presents the snapshot for `filter`: grouped sections for an empty
    /// query, one ranked flat section otherwise (Link), or the composer rows
    /// (New ID).
    public func presentation(filter: String) -> CapturePickerPresentation {
        if isNewIDMode {
            return newIDPresentation(filter: filter)
        }
        return linkPresentation(filter: filter)
    }

    /// Badge/detail-strip status for the current field text. Nil without a
    /// `block_id` object.
    public func blockStatus(filter: String) -> CapturePickerBlockIDStatus? {
        guard let field else {
            return nil
        }
        return CapturePickerBlockIDStatus(
            availability: availability(of: filter),
            usedCount: usedOrder.count,
            body: field.body,
            route: route,
            relativeTarget: noteTarget(),
            marker: field.marker,
            isProjectNote: field.intent == .projectNote
        )
    }

    /// Live availability of one ID string: project-note IDs are unchecked
    /// (Bob validates on capture), otherwise Bob's rule, then exact
    /// case-sensitive membership in Bob's used list, exactly like Bob's
    /// duplicate check.
    public func availability(of id: String) -> CapturePickerAvailability {
        guard let field else {
            return .unchecked
        }
        if field.intent == .projectNote {
            return .unchecked
        }
        guard let rules else {
            return .unchecked
        }
        if id.isEmpty {
            return .unchecked
        }
        if !rules.isValid(id) {
            return .invalid(field.allowedDescription)
        }
        if let used = usedByID[id] {
            return .taken(line: used.line, text: used.text)
        }
        return .available
    }

    private func noteTarget() -> String {
        if let relative = field?.relativeTarget, !relative.isEmpty {
            return relative
        }
        return "\(route).md"
    }

    // MARK: - Link presentation

    private func linkPresentation(filter: String) -> CapturePickerPresentation {
        let groupedSections = linkGroupedSections()
        let groupedRowCount = groupedSections.reduce(0) { $0 + $1.rows.count }
        let budget: Int
        if entries.isEmpty {
            budget = 4
        } else {
            budget = min(max(groupedRowCount + groupedSections.count, 4), 11)
        }
        let target = noteTarget()

        let query = FuzzyQuery(filter)
        if query.isEmpty {
            let rows = groupedSections.flatMap { $0.rows }
            let ids = rows.map { $0.id }
            let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            let emptyState: CapturePickerEmptyState? = rows.isEmpty ? linkEmptyState(target: target) : nil
            return CapturePickerPresentation(
                mode: .grouped,
                sections: groupedSections,
                orderedRowIDs: ids,
                rowsByID: byID,
                totalCount: entries.count,
                matchCount: entries.count,
                countText: entries.count == 1 ? "1 task" : "\(entries.count) tasks",
                emptyState: emptyState,
                visibleRowBudget: budget,
                blockIDStatus: blockStatus(filter: filter)
            )
        }

        let ranked = rankLinkEntries(tokens: query.tokens)
        var rows = ranked.map { linkFilteredRow(for: $0.entry, highlights: $0.highlights) }
        if query.tokens.count == 1, let token = query.tokens.first {
            rows = pinExactBlockID(token: token, in: rows, ranked: ranked)
            appendLinkTrailingRow(filter: filter, to: &rows)
        }
        let section = CapturePickerSection(
            id: "matches",
            kind: .matches,
            title: "",
            rows: rows
        )
        let ids = rows.filter { $0.isSelectable }.map { $0.id }
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        return CapturePickerPresentation(
            mode: .filtered,
            sections: [section],
            orderedRowIDs: ids,
            rowsByID: byID,
            totalCount: entries.count,
            matchCount: ranked.count,
            countText: "\(ranked.count) of \(entries.count)",
            emptyState: rows.isEmpty
                ? .blockIDNoMatches(target: target, query: filter) : nil,
            visibleRowBudget: budget,
            blockIDStatus: blockStatus(filter: filter)
        )
    }

    private func linkEmptyState(target: String) -> CapturePickerEmptyState {
        if field?.noteExists == false {
            return .blockIDNoteMissing(target: target)
        }
        return .blockIDNoLinkable(target: target, route: route)
    }

    private func linkGroupedSections() -> [CapturePickerSection] {
        var order: [String] = []
        var rowsBySection: [String: [CapturePickerRow]] = [:]
        for entry in entries {
            let key = entry.candidate.section ?? "Top of note"
            if rowsBySection[key] == nil {
                order.append(key)
                rowsBySection[key] = []
            }
            rowsBySection[key]!.append(linkGroupedRow(for: entry))
        }
        return order.enumerated().map { index, key in
            let rows = rowsBySection[key] ?? []
            return CapturePickerSection(
                id: "note-heading-\(index)",
                kind: .noteHeading,
                title: key,
                countText: rows.count == 1 ? "1 task" : "\(rows.count) tasks",
                rows: rows
            )
        }
    }

    // MARK: - Link filtering

    private struct RankedLinkEntry {
        let entry: BlockIDLinkEntry
        let score: Int
        let highlights: BlockIDMatchHighlights
    }

    private func rankLinkEntries(tokens: [String]) -> [RankedLinkEntry] {
        var ranked: [RankedLinkEntry] = []
        for entry in entries {
            var total = 0
            var highlights = BlockIDMatchHighlights()
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
                ranked.append(RankedLinkEntry(entry: entry, score: total, highlights: highlights))
            }
        }
        return ranked.sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.entry.bobIndex < $1.entry.bobIndex
        }
    }

    /// Pins an exact block-ID match first, preserving rank order otherwise.
    private func pinExactBlockID(
        token: String,
        in rows: [CapturePickerRow],
        ranked: [RankedLinkEntry]
    ) -> [CapturePickerRow] {
        let folded = FuzzyMatcher.folded(token)
        let exactIDs = Set(
            ranked.map { $0.entry }
                .filter { $0.blockID.map(FuzzyMatcher.folded).map({ $0 == folded }) ?? false }
                .map { $0.candidate.replacement }
        )
        guard !exactIDs.isEmpty else {
            return rows
        }
        return rows.sorted {
            let leftExact = exactIDs.contains($0.id)
            let rightExact = exactIDs.contains($1.id)
            if leftExact != rightExact {
                return leftExact
            }
            return false
        }
    }

    /// The trailing New ID row (or used-status row) for a one-token filter
    /// that satisfies Bob's rule and is not an exact candidate. Only when a
    /// field and rules exist.
    private func appendLinkTrailingRow(filter: String, to rows: inout [CapturePickerRow]) {
        guard field != nil, let rules else {
            return
        }
        let raw = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rules.isValid(raw) else {
            return
        }
        let folded = FuzzyMatcher.folded(raw)
        let isExactCandidate = entries.contains {
            $0.blockID.map(FuzzyMatcher.folded).map({ $0 == folded }) ?? false
        }
        guard !isExactCandidate else {
            return
        }
        if let used = usedByID[raw] {
            rows.append(linkUsedStatusRow(id: raw, used: used))
        } else {
            rows.append(linkNewIDRow(id: raw))
        }
    }

    // MARK: - New ID presentation

    private func newIDPresentation(filter: String) -> CapturePickerPresentation {
        guard let field else {
            return linkPresentation(filter: filter)
        }
        let target = noteTarget()
        var sections: [CapturePickerSection] = []
        var orderedIDs: [String] = []
        var byID: [String: CapturePickerRow] = [:]
        func appendSelectable(_ row: CapturePickerRow) {
            orderedIDs.append(row.id)
            byID[row.id] = row
        }
        func appendRow(_ row: CapturePickerRow) {
            byID[row.id] = row
        }

        var mainRows: [CapturePickerRow] = []
        if !filter.isEmpty {
            if field.intent == .projectNote {
                mainRows.append(newIDRow(id: filter, availability: .unchecked))
            } else if let rules {
                if !rules.isValid(filter) {
                    mainRows.append(invalidStatusRow(id: filter, description: field.allowedDescription))
                } else if let used = usedByID[filter] {
                    mainRows.append(takenStatusRow(id: filter, used: used))
                    if let variant = rules.nextFreeVariant(of: filter, used: usedIDs) {
                        mainRows.append(alternativeRow(id: variant))
                    }
                } else {
                    mainRows.append(newIDRow(id: filter, availability: .available))
                }
            }
        }
        if !mainRows.isEmpty {
            sections.append(CapturePickerSection(
                id: "new-id",
                kind: .matches,
                title: "",
                rows: mainRows
            ))
            for row in mainRows where row.isSelectable {
                appendSelectable(row)
            }
            for row in mainRows where !row.isSelectable {
                appendRow(row)
            }
        }

        let suggestions = visibleSuggestions(filter: filter)
        if !suggestions.isEmpty {
            let rows = suggestions.enumerated().map { index, suggestion in
                suggestionRow(
                    suggestion: suggestion,
                    bobIndex: entries.count + mainRows.count + index
                )
            }
            sections.append(CapturePickerSection(
                id: "suggestions",
                kind: .suggestions,
                title: "Suggested from your text",
                rows: rows
            ))
            for row in rows {
                appendSelectable(row)
            }
        }

        if !filter.isEmpty, field.intent != .projectNote {
            let matches = infoMatches(filter: filter)
            if !matches.isEmpty {
                let rows = matches.map { infoRow(used: $0.used, positions: $0.positions) }
                sections.append(CapturePickerSection(
                    id: "used-ids",
                    kind: .usedIDs,
                    title: "In use in \(target)",
                    countText: matches.count == 1 ? "1 similar" : "\(matches.count) similar",
                    rows: rows
                ))
                for row in rows {
                    appendRow(row)
                }
            }
        }

        let emptyState: CapturePickerEmptyState? = {
            guard orderedIDs.isEmpty else {
                return nil
            }
            if filter.isEmpty {
                return .blockIDNewIDEmpty(
                    allowedDescription: field.allowedDescription,
                    usedCount: usedOrder.count,
                    target: target,
                    needsBody: field.body.isEmpty
                )
            }
            return .blockIDNewIDNoOptions(query: filter)
        }()
        return CapturePickerPresentation(
            mode: filter.isEmpty ? .grouped : .filtered,
            sections: sections,
            orderedRowIDs: orderedIDs,
            rowsByID: byID,
            totalCount: usedOrder.count,
            matchCount: orderedIDs.count,
            countText: orderedIDs.count == 1 ? "1 option" : "\(orderedIDs.count) options",
            emptyState: emptyState,
            visibleRowBudget: 6,
            blockIDStatus: blockStatus(filter: filter)
        )
    }

    private func visibleSuggestions(filter: String) -> [String] {
        guard let field else {
            return []
        }
        var seen: Set<String> = []
        let unique = field.suggestions.filter { seen.insert($0).inserted }
        if filter.isEmpty {
            return unique
        }
        let foldedFilter = FuzzyMatcher.folded(filter)
        return unique.filter { suggestion in
            guard suggestion != filter else {
                return false
            }
            if FuzzyMatcher.folded(suggestion).hasPrefix(foldedFilter) {
                return true
            }
            return FuzzyMatcher.match(token: filter, in: FuzzyField(suggestion)) != nil
        }
    }

    private struct InfoMatch {
        let used: CaptureUsedBlockID
        let score: Int
        let documentOrder: Int
        let positions: [Int]
    }

    /// Used IDs that fuzzy-match the field on the ID only, excluding the
    /// exact conflict already shown: top 5 by score, then document order.
    private func infoMatches(filter: String) -> [InfoMatch] {
        let tokens = FuzzyQuery(filter).tokens
        guard !tokens.isEmpty else {
            return []
        }
        var matches: [InfoMatch] = []
        for (documentOrder, used) in usedOrder.enumerated() {
            guard used.id != filter else {
                continue
            }
            let idField = FuzzyField(used.id)
            var total = 0
            var positions: [Int] = []
            var matchesAll = true
            for token in tokens {
                guard let match = FuzzyMatcher.match(token: token, in: idField) else {
                    matchesAll = false
                    break
                }
                total += match.score
                positions += match.positions
            }
            if matchesAll {
                matches.append(InfoMatch(
                    used: used,
                    score: total,
                    documentOrder: documentOrder,
                    positions: positions
                ))
            }
        }
        matches.sort {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.documentOrder < $1.documentOrder
        }
        return Array(matches.prefix(5))
    }

    // MARK: - Link rows

    private func linkGroupedRow(for entry: BlockIDLinkEntry) -> CapturePickerRow {
        linkRow(for: entry, textRanges: [], blockRanges: [])
    }

    private func linkFilteredRow(
        for entry: BlockIDLinkEntry,
        highlights: BlockIDMatchHighlights
    ) -> CapturePickerRow {
        linkRow(
            for: entry,
            textRanges: highlights.textRanges,
            blockRanges: highlights.blockRanges
        )
    }

    private func linkRow(
        for entry: BlockIDLinkEntry,
        textRanges: [Range<Int>],
        blockRanges: [Range<Int>]
    ) -> CapturePickerRow {
        let candidate = entry.candidate
        let statusLabel = nonEmpty(candidate.statusName) ?? entry.status.displayName
        let rowRoute = nonEmpty(candidate.route) ?? route
        let summary = pomodoroSummary(for: candidate.pomodoro)
        return CapturePickerRow(
            id: candidate.replacement,
            bobIndex: entry.bobIndex,
            glyph: .task(entry.status),
            displayText: entry.display.text,
            textSegments: entry.display.segments,
            textMatchRanges: textRanges,
            route: rowRoute,
            blockID: candidate.blockID,
            blockIDMatchRanges: blockRanges,
            locatorStyle: .blockOnly,
            chipText: chipText(for: candidate.pomodoro),
            depth: candidate.depth ?? 0,
            insertion: candidate.replacement,
            detail: CapturePickerRowDetail(
                statusText: statusLabel,
                route: rowRoute,
                section: candidate.section,
                summary: summary,
                childCount: candidate.childCount ?? 0,
                insertionPrefix: "@"
            ),
            accessibilityLabel: "\(statusLabel). \(truncated(entry.display.text)). Block \(candidate.blockID ?? candidate.replacement). \(summary)."
        )
    }

    private func linkNewIDRow(id: String) -> CapturePickerRow {
        CapturePickerRow(
            id: "blockid-new:\(id)",
            bobIndex: entries.count,
            glyph: .newID(.available),
            displayText: "^\(id)",
            route: route,
            blockID: id,
            locatorStyle: .blockOnly,
            badgeText: "Available · add task text",
            insertion: id,
            detail: CapturePickerRowDetail(
                statusText: "New ID ^\(id)",
                route: route,
                section: nil,
                summary: "Available in \(noteTarget()) — add task text after the marker to create a new Next task",
                insertionPrefix: "@"
            ),
            accessibilityLabel: "New ID \(id), available. Add task text after the marker to create a new Next task."
        )
    }

    private func linkUsedStatusRow(id: String, used: CaptureUsedBlockID) -> CapturePickerRow {
        let message: String
        if used.isTask {
            let name = nonEmpty(used.statusName) ?? "task"
            message = "Used by \(indefiniteArticle(for: name)) \(name) task · line \(used.line)"
        } else {
            message = "Used on line \(used.line) · not a task"
        }
        return CapturePickerRow(
            id: "blockid-used:\(id)",
            bobIndex: entries.count + 1,
            glyph: .newID(.taken(line: used.line, text: used.text)),
            displayText: message,
            route: route,
            blockID: id,
            locatorStyle: .blockOnly,
            badgeText: "Used",
            isSelectable: false,
            insertion: nil,
            detail: CapturePickerRowDetail(
                statusText: message,
                route: route,
                section: nil,
                summary: truncated(used.text),
                insertionPrefix: "@"
            ),
            accessibilityLabel: "\(message). \(truncated(used.text))."
        )
    }

    // MARK: - New ID rows

    private func newIDRow(id: String, availability: CapturePickerAvailability) -> CapturePickerRow {
        CapturePickerRow(
            id: "new:\(id)",
            bobIndex: entries.count,
            glyph: .newID(availability),
            displayText: "^\(id)",
            route: route,
            blockID: id,
            locatorStyle: .blockOnly,
            badgeText: badgeWord(for: availability),
            insertion: id,
            detail: newIDDetail(id: id, availability: availability),
            accessibilityLabel: "New ID \(id), \(accessibilityWord(for: availability))."
        )
    }

    private func alternativeRow(id: String) -> CapturePickerRow {
        CapturePickerRow(
            id: "alternative:\(id)",
            bobIndex: entries.count + 1,
            glyph: .alternativeID,
            displayText: "^\(id)",
            route: route,
            blockID: id,
            locatorStyle: .blockOnly,
            badgeText: "Next free",
            insertion: id,
            detail: newIDDetail(id: id, availability: .available),
            accessibilityLabel: "New ID \(id), available."
        )
    }

    private func takenStatusRow(id: String, used: CaptureUsedBlockID) -> CapturePickerRow {
        let message = "^\(id) is already used — \(truncated(used.text)) · line \(used.line)"
        return CapturePickerRow(
            id: "status:\(id)",
            bobIndex: entries.count + 2,
            glyph: .newID(.taken(line: used.line, text: used.text)),
            displayText: message,
            route: route,
            blockID: id,
            locatorStyle: .blockOnly,
            isSelectable: false,
            insertion: nil,
            detail: CapturePickerRowDetail(
                statusText: message,
                route: route,
                section: nil,
                summary: availabilitySummary(for: .taken(line: used.line, text: used.text), id: id),
                insertionPrefix: "@"
            ),
            accessibilityLabel: "\(id) is already used on line \(used.line) by \(truncated(used.text))."
        )
    }

    private func invalidStatusRow(id: String, description: String) -> CapturePickerRow {
        let message = "“\(id)” isn't a valid block ID"
        return CapturePickerRow(
            id: "status:\(id)",
            bobIndex: entries.count + 2,
            glyph: .newID(.invalid(description)),
            displayText: message,
            route: route,
            blockID: id,
            locatorStyle: .blockOnly,
            badgeText: description,
            isSelectable: false,
            insertion: nil,
            detail: CapturePickerRowDetail(
                statusText: message,
                route: route,
                section: nil,
                summary: description,
                insertionPrefix: "@"
            ),
            accessibilityLabel: "\(id) is invalid: \(description)."
        )
    }

    private func suggestionRow(suggestion: String, bobIndex: Int) -> CapturePickerRow {
        let availability = availability(of: suggestion)
        return CapturePickerRow(
            id: "suggestion:\(suggestion)",
            bobIndex: bobIndex,
            glyph: .suggestion,
            displayText: "^\(suggestion)",
            route: route,
            blockID: suggestion,
            locatorStyle: .blockOnly,
            badgeText: rules == nil ? nil : badgeWord(for: availability),
            insertion: suggestion,
            detail: newIDDetail(id: suggestion, availability: availability),
            accessibilityLabel: "Suggestion \(suggestion), \(accessibilityWord(for: availability))."
        )
    }

    private func infoRow(used: CaptureUsedBlockID, positions: [Int]) -> CapturePickerRow {
        let display = TaskDisplayText(parsing: used.text)
        let glyph: CapturePickerGlyph = used.isTask
            ? .task(CapturePickerTaskStatus(symbol: used.statusSymbol, name: used.statusName))
            : .anchor
        return CapturePickerRow(
            id: "info:\(used.id)",
            bobIndex: entries.count + 3,
            glyph: glyph,
            displayText: display.text,
            textSegments: display.segments,
            route: route,
            blockID: used.id,
            blockIDMatchRanges: ActiveTaskMatchHighlights.coalesced(positions),
            locatorStyle: .blockOnly,
            isSelectable: false,
            insertion: nil,
            detail: CapturePickerRowDetail(
                statusText: nonEmpty(used.statusName) ?? (used.isTask ? "Task" : "Not a task"),
                route: route,
                section: nil,
                summary: "Line \(used.line) · \(noteTarget())",
                insertionPrefix: "@"
            ),
            accessibilityLabel: "\(truncated(used.text)). Block \(used.id). Line \(used.line)."
        )
    }

    private func newIDDetail(id: String, availability: CapturePickerAvailability) -> CapturePickerRowDetail {
        let title: String
        let outcome: String
        if let field {
            title = field.body.isEmpty ? "New task" : "“\(field.body)”"
            if field.intent == .projectNote {
                outcome = "Names the new project note"
            } else if field.marker == ":" {
                outcome = "New Next task in ▣ \(noteTarget()), linked into today's Pomodoro"
            } else {
                outcome = "New task in ▣ \(noteTarget())"
            }
        } else {
            title = "New task"
            outcome = "New task in ▣ \(noteTarget())"
        }
        return CapturePickerRowDetail(
            statusText: title,
            route: route,
            section: nil,
            summary: "\(outcome) · \(availabilitySummary(for: availability, id: id))",
            insertionPrefix: "@"
        )
    }

    // MARK: - Shared presentation helpers

    private func pomodoroSummary(for pomodoro: ActiveTaskPomodoro?) -> String {
        guard let pomodoro else {
            return "Not in a Pomodoro"
        }
        let name = nonEmpty(pomodoro.name)
        if pomodoro.isCurrent {
            let label = "Now · \(name ?? "Unnamed Pomodoro")"
            if let raw = nonEmpty(pomodoro.timeRange) {
                return "\(label) \(ActiveTaskPickerIndex.formattedTimeRange(raw))"
            }
            return label
        }
        guard let name else {
            return "Queued in an unnamed Pomodoro"
        }
        if let ordinal = pomodoroOrdinals[pomodoro.line] {
            return "Queued in \(name) (#\(ordinal))"
        }
        return "Queued in \(name)"
    }

    private func chipText(for pomodoro: ActiveTaskPomodoro?) -> String? {
        guard let pomodoro else {
            return nil
        }
        let name = nonEmpty(pomodoro.name)
        if pomodoro.isCurrent {
            let label = "Now · \(name ?? "Unnamed Pomodoro")"
            if let raw = nonEmpty(pomodoro.timeRange) {
                return "\(label) \(ActiveTaskPickerIndex.formattedTimeRange(raw))"
            }
            return label
        }
        return name ?? "Planned"
    }

    private func badgeWord(for availability: CapturePickerAvailability) -> String {
        switch availability {
        case .available:
            return "Available"
        case .unchecked:
            return "Checked on capture"
        case .taken(let line, _):
            if let line {
                return "Used · line \(line)"
            }
            return "Used"
        case .invalid(let description):
            return description
        }
    }

    private func accessibilityWord(for availability: CapturePickerAvailability) -> String {
        switch availability {
        case .available:
            return "available"
        case .unchecked:
            return "checked on capture"
        case .taken:
            return "already used"
        case .invalid:
            return "invalid"
        }
    }

    private func availabilitySummary(for availability: CapturePickerAvailability, id: String) -> String {
        switch availability {
        case .available:
            return "^\(id) is available"
        case .unchecked:
            return "Checked on capture"
        case .taken(let line, _):
            if let line {
                return "^\(id) is already used on line \(line)"
            }
            return "^\(id) is already used"
        case .invalid(let description):
            return description
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private func truncated(_ text: String, limit: Int = 60) -> String {
        guard text.count > limit else {
            return text
        }
        return String(text.prefix(limit)) + "…"
    }

    private func indefiniteArticle(for word: String) -> String {
        guard let first = word.lowercased().first else {
            return "a"
        }
        return "aeiou".contains(first) ? "an" : "a"
    }
}

// MARK: - Link index entries

/// One deduped link candidate with its display text and weighted search
/// fields. Weights: display text 100%, block ID 95%, Pomodoro name 50%,
/// section 40%, status name 30%.
private struct BlockIDLinkEntry: Sendable {
    let candidate: CaptureCompletionCandidate
    let bobIndex: Int
    let display: TaskDisplayText
    let status: CapturePickerTaskStatus
    let blockID: String?
    let textField: FuzzyField
    let blockField: FuzzyField?
    let pomodoroField: FuzzyField?
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
        if let blockID = candidate.blockID, !blockID.isEmpty {
            self.blockID = blockID
        } else {
            self.blockID = nil
        }
        self.textField = FuzzyField(display.text)
        if let blockID = self.blockID {
            self.blockField = FuzzyField(blockID)
        } else {
            self.blockField = nil
        }
        if let name = candidate.pomodoro?.name, !name.isEmpty {
            self.pomodoroField = FuzzyField(name)
        } else {
            self.pomodoroField = nil
        }
        if let section = candidate.section, !section.isEmpty {
            self.sectionField = FuzzyField(section)
        } else {
            self.sectionField = nil
        }
        let statusName = (candidate.statusName.flatMap { $0.isEmpty ? nil : $0 })
            ?? status.displayName
        self.statusField = FuzzyField(statusName)
    }

    /// The token's best weighted field match (`score * weight / 100`), or nil
    /// when the token matches no field. Preference order breaks weighted ties
    /// toward highlightable fields (display text first).
    func bestFieldMatch(for token: String) -> BlockIDFieldMatch? {
        var best: BlockIDFieldMatch?
        func consider(weight: Int, field: FuzzyField?, target: BlockIDMatchTarget) {
            guard let field,
                  let match = FuzzyMatcher.match(token: token, in: field)
            else {
                return
            }
            let weighted = match.score * weight / 100
            if best == nil || weighted > best!.weightedScore {
                best = BlockIDFieldMatch(
                    weightedScore: weighted,
                    target: target,
                    positions: match.positions
                )
            }
        }
        consider(weight: 100, field: textField, target: .text)
        consider(weight: 95, field: blockField, target: .blockID)
        consider(weight: 50, field: pomodoroField, target: .pomodoroName)
        consider(weight: 40, field: sectionField, target: .section)
        consider(weight: 30, field: statusField, target: .statusName)
        return best
    }
}

private enum BlockIDMatchTarget: Sendable {
    case text
    case blockID
    case pomodoroName
    case section
    case statusName
}

private struct BlockIDFieldMatch: Sendable {
    let weightedScore: Int
    let target: BlockIDMatchTarget
    let positions: [Int]
}

/// Coalesced highlight positions gathered from every token's best field.
/// Section, Pomodoro-name, and status-name matches raise the rank without
/// highlighting.
private struct BlockIDMatchHighlights: Sendable {
    var textPositions: [Int] = []
    var blockPositions: [Int] = []

    mutating func add(_ match: BlockIDFieldMatch) {
        switch match.target {
        case .text:
            textPositions += match.positions
        case .blockID:
            blockPositions += match.positions
        case .pomodoroName, .section, .statusName:
            break
        }
    }

    var textRanges: [Range<Int>] {
        ActiveTaskMatchHighlights.coalesced(textPositions)
    }

    var blockRanges: [Range<Int>] {
        ActiveTaskMatchHighlights.coalesced(blockPositions)
    }
}

extension CapturePickerEmptyState {
    public static func blockIDNoLinkable(target: String, route: String) -> Self {
        Self(
            title: "No linkable tasks in \(target)",
            message: "A task needs a ^block-id to be linked. Type a new ID, or use @\(route)+ to add an ID to a task."
        )
    }

    public static func blockIDNoteMissing(target: String) -> Self {
        Self(
            title: "\(target) doesn't exist yet",
            message: "Type a new ID — Bob creates the note when you capture."
        )
    }

    public static func blockIDNoMatches(target: String, query: String) -> Self {
        Self(
            title: "No matches",
            message: "No \(target) tasks match “\(query)” — Esc clears the filter."
        )
    }

    public static func blockIDNewIDEmpty(
        allowedDescription: String,
        usedCount: Int,
        target: String,
        needsBody: Bool
    ) -> Self {
        let countText = usedCount == 1
            ? "1 ID already used"
            : "\(usedCount) IDs already used"
        var message = "\(allowedDescription) · \(countText) in \(target)."
        if needsBody {
            message += " Add the task text after the marker."
        }
        return Self(title: "Type a new block ID", message: message)
    }

    public static func blockIDNewIDNoOptions(query: String) -> Self {
        Self(
            title: "No options",
            message: "Nothing selectable for “\(query)” — Esc clears the filter."
        )
    }
}
