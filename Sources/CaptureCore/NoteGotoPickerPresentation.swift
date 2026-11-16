import Foundation

/// Local grouped and fuzzy presentation of Bob's read-only `note_goto`
/// snapshot. Bob supplies the catalog, row names, search keys, ranks, and
/// grouping; this index only sorts and presents those values.
public struct NoteGotoPickerIndex {
    private let entries: [NoteGotoPickerEntry]
    private let noteGoto: CaptureCompletionNoteGoto
    private let recentNotePaths: [String]

    public init(
        candidates: [CaptureCompletionCandidate],
        noteGoto: CaptureCompletionNoteGoto,
        recentNotePaths: [String] = []
    ) {
        self.noteGoto = noteGoto
        self.recentNotePaths = recentNotePaths
        var seen: Set<String> = []
        var entries: [NoteGotoPickerEntry] = []
        for candidate in candidates {
            guard let notePath = candidate.notePath, !notePath.isEmpty,
                seen.insert(notePath).inserted
            else {
                continue
            }
            entries.append(NoteGotoPickerEntry(candidate: candidate, bobIndex: entries.count))
        }
        self.entries = entries
    }

    public var count: Int {
        entries.count
    }

    /// Presents Bob's canonical map when the filter is empty and every
    /// matching result when it is non-empty. Filtered results are never capped.
    public func presentation(filter: String) -> CapturePickerPresentation {
        let query = FuzzyQuery(filter, leadingSigil: "//")
        if query.isEmpty {
            return groupedPresentation()
        }

        let ranked = rank(tokens: query.tokens)
        let rows = ranked.map { row(for: $0, depth: 0) }
        let section = CapturePickerSection(
            id: "note-goto-matches",
            kind: .matches,
            title: "",
            rows: rows
        )
        let rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let emptyState =
            rows.isEmpty
            ? CapturePickerEmptyState.noMatches(query: filter, noun: "notes to open")
            : nil
        return CapturePickerPresentation(
            mode: .filtered,
            sections: [section],
            orderedRowIDs: rows.filter(\.isSelectable).map(\.id),
            rowsByID: rowsByID,
            totalCount: entries.count,
            matchCount: rows.count,
            countText: "\(Self.groupedCount(rows.count)) of \(Self.groupedCount(entries.count))",
            emptyState: emptyState,
            visibleRowBudget: Self.visibleRowBudget(rowCount: rows.count, sectionCount: 1)
        )
    }

    /// One-line action copy shown beneath the selected row in the detail strip.
    public func actionLine(for row: CapturePickerRow) -> String {
        guard let destination = row.noteGotoDestination else {
            return "Note location unavailable"
        }
        let basename = URL(fileURLWithPath: destination.notePath).lastPathComponent
        return "↩ Opens \(basename) in Obsidian — nothing is written"
    }

    /// Long-stable SF Symbols for the Bob-authored note kind keys.
    public static func symbolName(for kind: String) -> String {
        switch kind {
        case "inbox": "tray"
        case "area": "square.stack.3d.up"
        case "project": "hammer"
        case "notebook": "book.closed"
        case "album": "rectangle.stack"
        case "record": "doc.richtext"
        case "ref": "book"
        case "daily", "period": "calendar"
        case "bank": "banknote"
        case "mail": "envelope"
        case "view": "square.grid.2x2"
        case "note": "doc.text"
        default: "doc.text"
        }
    }

    public static func kindLabel(for kind: String) -> String {
        switch kind {
        case "inbox": "Inbox"
        case "area": "Area"
        case "project": "Project"
        case "notebook": "Notebook"
        case "album": "Album"
        case "record": "Record"
        case "ref": "Reference"
        case "daily": "Daily note"
        case "period": "Period note"
        case "bank": "Bank note"
        case "mail": "Mail note"
        case "view": "View"
        case "note": "Note"
        default: "Note"
        }
    }

    private func groupedPresentation() -> CapturePickerPresentation {
        var groupOrder: [String] = []
        var grouped: [String: [CapturePickerRow]] = [:]
        var visibleCount = 0
        var entryByPath: [String: NoteGotoPickerEntry] = [:]
        var todayPaths: Set<String> = []
        for entry in entries {
            entryByPath[entry.notePath] = entry
            guard let group = entry.candidate.group, Self.groupTitle(for: group) != nil else {
                continue
            }
            if grouped[group] == nil {
                groupOrder.append(group)
                grouped[group] = []
            }
            grouped[group, default: []].append(row(for: entry, depth: entry.candidate.depth ?? 0))
            visibleCount += 1
            if group == "today" {
                todayPaths.insert(entry.notePath)
            }
        }

        let sections = groupOrder.map { group in
            let rows = grouped[group] ?? []
            return CapturePickerSection(
                id: "note-goto-group-\(group)",
                kind: .noteGotoGroup,
                title: Self.groupTitle(for: group) ?? group,
                countText: "\(Self.groupedCount(rows.count)) \(rows.count == 1 ? "note" : "notes")",
                rows: rows
            )
        }
        var allSections = sections
        let recentRows = recentSectionRows(
            entryByPath: entryByPath,
            todayPaths: todayPaths
        )
        if !recentRows.isEmpty {
            let recentSection = CapturePickerSection(
                id: "note-goto-group-recent",
                kind: .noteGotoGroup,
                title: "Recent",
                countText:
                    "\(Self.groupedCount(recentRows.count)) \(recentRows.count == 1 ? "note" : "notes")",
                rows: recentRows
            )
            let todayIndex = allSections.firstIndex {
                $0.id == "note-goto-group-today"
            }
            if let todayIndex {
                allSections.insert(recentSection, at: todayIndex + 1)
            } else {
                allSections.insert(recentSection, at: 0)
            }
        }
        let ungroupedCount = entries.count - visibleCount
        if ungroupedCount > 0 {
            let hint = hintRow(count: ungroupedCount, bobIndex: entries.count)
            allSections.append(
                CapturePickerSection(
                    id: "note-goto-search-hint",
                    kind: .noteGotoHint,
                    title: "",
                    rows: [hint]
                )
            )
        }

        let rows = allSections.flatMap(\.rows)
        let rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let emptyState = entries.isEmpty ? CapturePickerEmptyState.noNotesToOpen : nil
        return CapturePickerPresentation(
            mode: .grouped,
            sections: allSections,
            orderedRowIDs: rows.filter(\.isSelectable).map(\.id),
            rowsByID: rowsByID,
            totalCount: entries.count,
            matchCount: visibleCount,
            countText:
                "\(Self.groupedCount(entries.count)) \(entries.count == 1 ? "note" : "notes")",
            emptyState: emptyState,
            visibleRowBudget: Self.visibleRowBudget(
                rowCount: visibleCount + recentRows.count + (ungroupedCount > 0 ? 1 : 0),
                sectionCount: sections.count + (recentRows.isEmpty ? 0 : 1)
            )
        )
    }

    private func recentSectionRows(
        entryByPath: [String: NoteGotoPickerEntry],
        todayPaths: Set<String>
    ) -> [CapturePickerRow] {
        var seen: Set<String> = []
        var rows: [CapturePickerRow] = []
        for path in recentNotePaths {
            guard rows.count < 8 else {
                break
            }
            guard !path.isEmpty, seen.insert(path).inserted else {
                continue
            }
            guard !todayPaths.contains(path) else {
                continue
            }
            guard let entry = entryByPath[path] else {
                continue
            }
            let base = row(for: entry, depth: entry.candidate.depth ?? 0)
            rows.append(recentRow(from: base, notePath: path))
        }
        return rows
    }

    private func recentRow(from base: CapturePickerRow, notePath: String) -> CapturePickerRow {
        CapturePickerRow(
            id: "recent:\(notePath)",
            bobIndex: base.bobIndex,
            glyph: base.glyph,
            displayText: base.displayText,
            textSegments: base.textSegments,
            textMatchRanges: base.textMatchRanges,
            route: base.route,
            blockID: base.blockID,
            routeMatchRanges: base.routeMatchRanges,
            blockIDMatchRanges: base.blockIDMatchRanges,
            locatorStyle: base.locatorStyle,
            chipText: base.chipText,
            isHidden: base.isHidden,
            badgeText: base.badgeText,
            depth: base.depth,
            isSelectable: base.isSelectable,
            insertion: base.insertion,
            pendingBlockID: base.pendingBlockID,
            scheduledText: base.scheduledText,
            pullsForward: base.pullsForward,
            taskGotoDestination: base.taskGotoDestination,
            noteGotoDestination: base.noteGotoDestination,
            noteGotoSecondaryText: base.noteGotoSecondaryText,
            detail: base.detail,
            accessibilityLabel: base.accessibilityLabel
        )
    }

    private func row(for ranked: NoteGotoRankedEntry, depth: Int) -> CapturePickerRow {
        row(
            for: ranked.entry,
            depth: depth,
            titleMatchRanges: ranked.titleMatchRanges,
            pathMatchRanges: ranked.pathMatchRanges,
            alias: ranked.alias
        )
    }

    private func row(for entry: NoteGotoPickerEntry, depth: Int) -> CapturePickerRow {
        row(for: entry, depth: depth, titleMatchRanges: [], pathMatchRanges: [], alias: nil)
    }

    private func row(
        for entry: NoteGotoPickerEntry,
        depth: Int,
        titleMatchRanges: [Range<Int>],
        pathMatchRanges: [Range<Int>],
        alias: String?
    ) -> CapturePickerRow {
        let candidate = entry.candidate
        let kind = candidate.kind ?? "note"
        let title = entry.title
        let destination = CaptureNoteGotoDestination(
            vaultRoot: noteGoto.vaultRoot,
            notePath: entry.notePath
        )
        let hue: PomodoroHomeHue?
        if let candidateHue = candidate.hue, case .other = candidateHue {
            hue = nil
        } else {
            hue = candidate.hue
        }
        let kindLabel = Self.kindLabel(for: kind)
        let detail = candidate.detail.flatMap { $0.isEmpty ? nil : $0 }
        let accessibilityParts = [kindLabel, title, detail, entry.notePath].compactMap { $0 }
        return CapturePickerRow(
            id: entry.notePath,
            bobIndex: entry.bobIndex,
            glyph: .noteGoto(symbol: Self.symbolName(for: kind), hue: hue),
            displayText: title,
            textMatchRanges: titleMatchRanges,
            route: entry.notePath,
            routeMatchRanges: pathMatchRanges,
            chipText: candidate.status,
            badgeText: alias.map { "aka \($0)" },
            depth: min(max(depth, 0), 2),
            isSelectable: destination != nil,
            insertion: nil,
            noteGotoDestination: destination,
            noteGotoSecondaryText: detail,
            detail: CapturePickerRowDetail(
                statusText: "",
                summary: "",
                insertionPrefix: ""
            ),
            accessibilityLabel: accessibilityParts.joined(separator: ", ")
        )
    }

    private func hintRow(count: Int, bobIndex: Int) -> CapturePickerRow {
        let text = "Type to search \(Self.groupedCount(count)) more notes"
        return CapturePickerRow(
            id: "note-goto-search-hint",
            bobIndex: bobIndex,
            glyph: .noteGotoHint,
            displayText: text,
            isSelectable: false,
            insertion: nil,
            detail: CapturePickerRowDetail(statusText: "", summary: "", insertionPrefix: ""),
            accessibilityLabel: text
        )
    }

    private func rank(tokens: [String]) -> [NoteGotoRankedEntry] {
        var ranked: [NoteGotoRankedEntry] = []
        for entry in entries {
            var score = 0
            var hasPrimaryMatch = false
            var titlePositions: [Int] = []
            var pathPositions: [Int] = []
            var aliasScores: [Int: Int] = [:]
            var matchedAllTokens = true

            for token in tokens {
                var bestPrimary: (index: Int, match: FuzzyFieldMatch)?
                for (index, field) in entry.matchFields.enumerated() {
                    guard let match = FuzzyMatcher.matchPreFolded(token: token, in: field) else {
                        continue
                    }
                    if bestPrimary == nil || match.score > bestPrimary!.match.score {
                        bestPrimary = (index, match)
                    }
                }
                let pathMatch = entry.pathField.flatMap {
                    FuzzyMatcher.matchPreFolded(token: token, in: $0)
                }
                guard bestPrimary != nil || pathMatch != nil else {
                    matchedAllTokens = false
                    break
                }
                if let bestPrimary {
                    hasPrimaryMatch = true
                    score += bestPrimary.match.score
                    if bestPrimary.index == 0 {
                        titlePositions += bestPrimary.match.positions
                    } else if entry.matchKeys[bestPrimary.index] != entry.fileStem {
                        aliasScores[bestPrimary.index, default: 0] += bestPrimary.match.score
                    }
                } else if let pathMatch {
                    score += pathMatch.score
                }
                if let pathMatch {
                    pathPositions += pathMatch.positions
                }
            }
            guard matchedAllTokens else {
                continue
            }

            let aliasIndex = aliasScores.keys.sorted {
                let left = aliasScores[$0] ?? 0
                let right = aliasScores[$1] ?? 0
                return left == right ? $0 < $1 : left > right
            }.first
            ranked.append(
                NoteGotoRankedEntry(
                    entry: entry,
                    score: score,
                    hasPrimaryMatch: hasPrimaryMatch,
                    titleMatchRanges: NoteGotoPickerIndex.coalesced(titlePositions),
                    pathMatchRanges: NoteGotoPickerIndex.coalesced(pathPositions),
                    alias: aliasIndex.map { entry.matchKeys[$0] }
                )
            )
        }
        return ranked.sorted {
            if $0.hasPrimaryMatch != $1.hasPrimaryMatch {
                return $0.hasPrimaryMatch
            }
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            if $0.entry.rank != $1.entry.rank {
                return $0.entry.rank < $1.entry.rank
            }
            return $0.entry.bobIndex < $1.entry.bobIndex
        }
    }

    private static func groupTitle(for group: String) -> String? {
        switch group {
        case "today": "Today"
        case "inbox": "Inbox"
        case "areas": "Areas"
        case "projects": "Projects"
        case "notebooks": "Notebooks"
        case "albums": "Albums"
        default: nil
        }
    }

    private static func visibleRowBudget(rowCount: Int, sectionCount: Int) -> Int {
        guard rowCount > 0 else {
            return 4
        }
        return min(max(rowCount + sectionCount, 4), 11)
    }

    private static func groupedCount(_ value: Int) -> String {
        let digits = String(value)
        var result = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0 && offset.isMultiple(of: 3) {
                result.append(",")
            }
            result.append(character)
        }
        return String(result.reversed())
    }

    private static func coalesced(_ positions: [Int]) -> [Range<Int>] {
        let sorted = Array(Set(positions)).sorted()
        var ranges: [Range<Int>] = []
        var index = 0
        while index < sorted.count {
            var end = index
            while end + 1 < sorted.count, sorted[end + 1] == sorted[end] + 1 {
                end += 1
            }
            ranges.append(sorted[index]..<sorted[end] + 1)
            index = end + 1
        }
        return ranges
    }
}

private struct NoteGotoPickerEntry {
    let candidate: CaptureCompletionCandidate
    let bobIndex: Int
    let notePath: String
    let title: String
    let fileStem: String
    let matchKeys: [String]
    let matchFields: [FuzzyField]
    let pathField: FuzzyField?
    let rank: Int

    init(candidate: CaptureCompletionCandidate, bobIndex: Int) {
        self.candidate = candidate
        self.bobIndex = bobIndex
        let path = candidate.notePath ?? ""
        self.notePath = path
        self.fileStem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        self.title = candidate.title.flatMap { $0.isEmpty ? nil : $0 } ?? fileStem
        let keys = candidate.matchKeys?.filter { !$0.isEmpty } ?? []
        self.matchKeys = keys.isEmpty ? [title] : keys
        self.matchFields = self.matchKeys.map(FuzzyField.init)
        let fileExtension = URL(fileURLWithPath: path).pathExtension
        let pathWithoutExtension =
            fileExtension.isEmpty
            ? path
            : String(path.dropLast(fileExtension.count + 1))
        self.pathField = pathWithoutExtension.isEmpty ? nil : FuzzyField(pathWithoutExtension)
        self.rank = candidate.rank ?? 8
    }
}

private struct NoteGotoRankedEntry {
    let entry: NoteGotoPickerEntry
    let score: Int
    let hasPrimaryMatch: Bool
    let titleMatchRanges: [Range<Int>]
    let pathMatchRanges: [Range<Int>]
    let alias: String?
}
