import Foundation

/// Stable identity for a foldable agenda unit: one task (by ledger
/// line), one Pomodoro group (by entry line), or the Later name strip.
public enum CaptureAgendaUnitID: Hashable, Equatable, Sendable {
    case task(ledgerLine: Int)
    case group(entryLine: Int)
    case strip
}

/// The kind of one rendered agenda row. Part of the row key, so a kind
/// change always re-measures.
public enum CaptureAgendaRowKind: Hashable, Equatable, Sendable {
    case title
    case multiOpenWarning
    case stateLine
    case groupHeader
    case sessionNote
    case taskHeadline
    case ledgerNote
    case childLine
    case logHeader
    case logEntry
    case warning
    case duplicate
    case struck
    case retired
    case emptyGroup
    case truncation
    case groupOneRow
    case strip
}

/// Cache key for a measured row: kind, display text, depth, line limit,
/// and accessory presence. Unchanged rows across snapshots are never
/// re-measured.
public struct CaptureAgendaRowKey: Hashable, Equatable, Sendable {
    public let kind: CaptureAgendaRowKind
    public let text: String
    public let depth: Int
    public let lineLimit: Int
    public let hasAccessory: Bool

    public init(
        kind: CaptureAgendaRowKind,
        text: String,
        depth: Int,
        lineLimit: Int,
        hasAccessory: Bool
    ) {
        self.kind = kind
        self.text = text
        self.depth = depth
        self.lineLimit = lineLimit
        self.hasAccessory = hasAccessory
    }
}

/// One display-ready agenda row. The view renders these verbatim: all
/// wording, chips, and accessibility labels are decided here, so views
/// never branch on snapshot JSON.
public struct CaptureAgendaRow: Equatable, Sendable {
    public let key: CaptureAgendaRowKey
    public let kind: CaptureAgendaRowKind
    public let text: String
    public let depth: Int
    public let lineLimit: Int
    public let numberBadge: Int?
    public let accessoryText: String?
    public let statusGlyph: String?
    public let accessibilityLabel: String?
    public let accessoryAccessibilityLabel: String?

    public init(
        kind: CaptureAgendaRowKind,
        text: String,
        depth: Int,
        lineLimit: Int,
        numberBadge: Int? = nil,
        accessoryText: String? = nil,
        statusGlyph: String? = nil,
        accessibilityLabel: String? = nil,
        accessoryAccessibilityLabel: String? = nil
    ) {
        self.kind = kind
        self.text = text
        self.depth = depth
        self.lineLimit = lineLimit
        self.numberBadge = numberBadge
        self.accessoryText = accessoryText
        self.statusGlyph = statusGlyph
        self.accessibilityLabel = accessibilityLabel
        self.accessoryAccessibilityLabel = accessoryAccessibilityLabel
        key = CaptureAgendaRowKey(
            kind: kind,
            text: text,
            depth: depth,
            lineLimit: lineLimit,
            hasAccessory: numberBadge != nil || accessoryText != nil
        )
    }
}

/// One agenda task with its rows precomputed at every fold level, so
/// the fit planner picks row lists without branching on item JSON.
public struct CaptureAgendaTask: Equatable, Sendable {
    public let id: CaptureAgendaUnitID
    public let title: String
    public let fullRows: [CaptureAgendaRow]
    public let noLogsRows: [CaptureAgendaRow]
    public let oneLineRow: CaptureAgendaRow

    public init(
        id: CaptureAgendaUnitID,
        title: String,
        fullRows: [CaptureAgendaRow],
        noLogsRows: [CaptureAgendaRow],
        oneLineRow: CaptureAgendaRow
    ) {
        self.id = id
        self.title = title
        self.fullRows = fullRows
        self.noLogsRows = noLogsRows
        self.oneLineRow = oneLineRow
    }
}

/// One Pomodoro's agenda group: header, session notes, tasks, and the
/// retired-links line, with the folded variants precomputed.
public struct CaptureAgendaGroup: Equatable, Sendable {
    public let id: CaptureAgendaUnitID
    public let role: CaptureAgendaRole
    public let entryLine: Int
    public let name: String
    public let headerRow: CaptureAgendaRow
    public let sessionNoteRows: [CaptureAgendaRow]
    public let sessionNotesChip: String?
    public let tasks: [CaptureAgendaTask]
    public let retiredRow: CaptureAgendaRow?
    public let emptyRow: CaptureAgendaRow?
    public let oneRowRow: CaptureAgendaRow
    public let stripName: String
    public let accessibilityLabel: String

    public init(
        id: CaptureAgendaUnitID,
        role: CaptureAgendaRole,
        entryLine: Int,
        name: String,
        headerRow: CaptureAgendaRow,
        sessionNoteRows: [CaptureAgendaRow],
        sessionNotesChip: String?,
        tasks: [CaptureAgendaTask],
        retiredRow: CaptureAgendaRow?,
        emptyRow: CaptureAgendaRow?,
        oneRowRow: CaptureAgendaRow,
        stripName: String,
        accessibilityLabel: String
    ) {
        self.id = id
        self.role = role
        self.entryLine = entryLine
        self.name = name
        self.headerRow = headerRow
        self.sessionNoteRows = sessionNoteRows
        self.sessionNotesChip = sessionNotesChip
        self.tasks = tasks
        self.retiredRow = retiredRow
        self.emptyRow = emptyRow
        self.oneRowRow = oneRowRow
        self.stripName = stripName
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Pure presentation model for the idle agenda: today's Pomodoros with
/// their linked tasks, built once from the snapshot so views never
/// branch on ledger JSON. bob owns every fact here; this only decides
/// wording, grouping, row order, and duplicate folding.
public struct CaptureAgendaPresentation: Equatable, Sendable {
    /// Which content the agenda shows. Anything but `.agenda` renders
    /// the title row plus one quiet `stateRow` line.
    public enum State: Equatable, Sendable {
        case agenda
        case loading
        case noDailyNote
        case noOpen
    }

    public let state: State
    public let titleRow: CaptureAgendaRow
    public let summaryText: String?
    /// True when the last refresh failed but the previous snapshot is
    /// still today: the agenda paints with a "Couldn't refresh" marker
    /// on the title row's right. Encoded into the title accessory text
    /// so the measurer and the renderer agree by construction.
    public let isStale: Bool
    /// True while a current entry carries an end time: the view mounts
    /// its minute-granularity countdown only then.
    public let hasLiveCountdown: Bool
    public let warningRow: CaptureAgendaRow?
    public let groups: [CaptureAgendaGroup]
    public let stateRow: CaptureAgendaRow?
    /// The title row's stale suffix, shared by the presentation and the
    /// view's stale-icon split. Never a ledger fact, only wording.
    public static let staleSuffix = "Couldn't refresh"
    /// The strip with every Later name, used only to budget the strip's
    /// upper bound; the rendered strip lists the current members.
    public let stripFullRow: CaptureAgendaRow

    public init(
        snapshot: CaptureAgendaSnapshot,
        today: String,
        now: Date? = nil,
        locale: Locale = Locale.current,
        isStale: Bool = false
    ) {
        self.isStale = isStale
        summaryText = CaptureAgendaClock.summaryText(
            count: snapshot.completedSummary.count,
            minutes: snapshot.completedSummary.minutes
        )
        let entries = snapshot.pomodoros.filter { Self.isOpenRole($0.role) }
        let currentCount = entries.filter { $0.role == .current }.count
        let openCount = entries.filter { $0.role == .open }.count
        let nothingRunning = currentCount == 0 && openCount == 0
        hasLiveCountdown = entries.contains {
            $0.role == .current && !($0.endsAt ?? "").isEmpty
        }
        titleRow = Self.makeTitleRow(
            rawDate: snapshot.date,
            nothingRunning: nothingRunning,
            summaryText: summaryText,
            locale: locale,
            stale: isStale
        )
        let ordered = Self.orderEntries(entries)
        warningRow = openCount >= 2 ? Self.makeMultiOpenWarningRow() : nil
        let laterNames = ordered.filter { $0.role == .later }.map { Self.displayName($0.name) }
        stripFullRow = Self.makeStripRow(names: laterNames)
        guard snapshot.date == today else {
            state = .loading
            groups = []
            stateRow = Self.makeStateRow(text: "Loading today…")
            return
        }
        guard !ordered.isEmpty else {
            groups = []
            if snapshot.warnings.isEmpty {
                state = .noOpen
                stateRow = Self.makeStateRow(text: "No Pomodoros planned · =#NAME starts one")
            } else {
                state = .noDailyNote
                stateRow = Self.makeStateRow(text: "No daily note for today yet")
            }
            return
        }
        state = .agenda
        stateRow = nil
        groups = Self.makeGroups(entries: ordered, now: now)
    }

    // MARK: - Entry ordering

    static func isOpenRole(_ role: CaptureAgendaRole) -> Bool {
        switch role {
        case .current, .open, .next, .later:
            return true
        case .completed, .other:
            return false
        }
    }

    /// Ledger order within each role: current entries, then open ones,
    /// then next, then later.
    static func orderEntries(_ entries: [CaptureAgendaPomodoro]) -> [CaptureAgendaPomodoro] {
        let current = entries.filter { $0.role == .current }
        let open = entries.filter { $0.role == .open }
        let next = entries.filter { $0.role == .next }
        let later = entries.filter { $0.role == .later }
        return current + open + next + later
    }

    static func displayName(_ name: String?) -> String {
        guard let name, !name.isEmpty else {
            return "Untitled Pomodoro"
        }
        return name
    }

    // MARK: - Title, warning, and state rows

    /// A loading presentation for the no-snapshot-yet state: the title
    /// row plus one quiet "Loading today…" line. The model paints this
    /// while the setting is on and the store has nothing current yet.
    public static func loading(
        today: String,
        locale: Locale = Locale.current
    ) -> CaptureAgendaPresentation {
        let titleRow = makeTitleRow(
            rawDate: today,
            nothingRunning: false,
            summaryText: nil,
            locale: locale
        )
        return CaptureAgendaPresentation(
            state: .loading,
            titleRow: titleRow,
            summaryText: nil,
            isStale: false,
            hasLiveCountdown: false,
            warningRow: nil,
            groups: [],
            stateRow: makeStateRow(text: "Loading today…"),
            stripFullRow: makeStripRow(names: [])
        )
    }

    private init(
        state: State,
        titleRow: CaptureAgendaRow,
        summaryText: String?,
        isStale: Bool,
        hasLiveCountdown: Bool,
        warningRow: CaptureAgendaRow?,
        groups: [CaptureAgendaGroup],
        stateRow: CaptureAgendaRow?,
        stripFullRow: CaptureAgendaRow
    ) {
        self.state = state
        self.titleRow = titleRow
        self.summaryText = summaryText
        self.isStale = isStale
        self.hasLiveCountdown = hasLiveCountdown
        self.warningRow = warningRow
        self.groups = groups
        self.stateRow = stateRow
        self.stripFullRow = stripFullRow
    }

    static func makeTitleRow(
        rawDate: String?,
        nothingRunning: Bool,
        summaryText: String?,
        locale: Locale,
        stale: Bool = false
    ) -> CaptureAgendaRow {
        let dateText = CaptureAgendaClock.titleDateText(rawDate: rawDate, locale: locale)
        var text = "Today"
        if !dateText.isEmpty {
            text += " · \(dateText)"
        }
        if nothingRunning {
            text += " · Nothing running"
        }
        var accessory = summaryText
        if stale {
            if let existing = accessory, !existing.isEmpty {
                accessory = "\(existing) · \(staleSuffix)"
            } else {
                accessory = staleSuffix
            }
        }
        return CaptureAgendaRow(
            kind: .title,
            text: text,
            depth: 0,
            lineLimit: 1,
            accessoryText: accessory,
            accessibilityLabel: accessory == nil ? text : "\(text). \(accessory ?? "")"
        )
    }

    static func makeMultiOpenWarningRow() -> CaptureAgendaRow {
        let text = "Multiple open timed sessions — close one so `=x` knows which is running"
        return CaptureAgendaRow(
            kind: .multiOpenWarning,
            text: text,
            depth: 0,
            lineLimit: 2,
            accessibilityLabel: text
        )
    }

    static func makeStateRow(text: String) -> CaptureAgendaRow {
        CaptureAgendaRow(
            kind: .stateLine,
            text: text,
            depth: 0,
            lineLimit: 1,
            accessibilityLabel: text
        )
    }

    /// The Later name strip for the given member names. Names past the
    /// character budget fold into a `+N` overflow token.
    static func makeStripRow(names: [String]) -> CaptureAgendaRow {
        let text = Self.stripText(names: names)
        return CaptureAgendaRow(
            kind: .strip,
            text: text,
            depth: 0,
            lineLimit: CaptureAgendaLayoutMetrics.stripLineLimit,
            accessibilityLabel: Self.stripAccessibilityText(names: names)
        )
    }

    static func stripText(names: [String]) -> String {
        guard !names.isEmpty else {
            return "Later"
        }
        var shown = names
        while !shown.isEmpty {
            let hidden = names.count - shown.count
            guard stripJoined(shown, hidden: hidden).count > maxStripLength else {
                break
            }
            shown.removeLast()
        }
        guard !shown.isEmpty else {
            return "Later · +\(names.count)"
        }
        return stripJoined(shown, hidden: names.count - shown.count)
    }

    private static func stripJoined(_ shown: [String], hidden: Int) -> String {
        var text = "Later · " + shown.joined(separator: " · ")
        if hidden > 0 {
            text += " · +\(hidden)"
        }
        return text
    }

    static func stripAccessibilityText(names: [String]) -> String {
        guard !names.isEmpty else {
            return "Later Pomodoros"
        }
        return "Later: " + names.joined(separator: ", ")
    }

    // MARK: - Groups

    static func makeGroups(entries: [CaptureAgendaPomodoro], now: Date?) -> [CaptureAgendaGroup] {
        var seen: Set<String> = []
        var firstNames: [String: String] = [:]
        return entries.map { entry in
            makeGroup(entry: entry, now: now, seen: &seen, firstNames: &firstNames)
        }
    }

    static func makeGroup(
        entry: CaptureAgendaPomodoro,
        now: Date?,
        seen: inout Set<String>,
        firstNames: inout [String: String]
    ) -> CaptureAgendaGroup {
        let name = displayName(entry.name)
        let header = makeHeaderRow(entry: entry, name: name, now: now)
        let sessionNotes = entry.notes.map { note in
            CaptureAgendaRow(
                kind: .sessionNote,
                text: note.text,
                depth: note.depth,
                lineLimit: CaptureAgendaLayoutMetrics.childLineLimit,
                statusGlyph: note.statusSymbol,
                accessibilityLabel: note.text
            )
        }
        let chip: String? = entry.notes.isEmpty ? nil : "\(entry.notes.count) notes"
        var tasks: [CaptureAgendaTask] = []
        tasks.reserveCapacity(entry.items.count)
        for (position, item) in entry.items.enumerated() {
            let number = position + 1
            tasks.append(makeTask(
                item: item,
                number: number,
                entry: entry,
                groupName: name,
                seen: &seen,
                firstNames: &firstNames
            ))
        }
        let retired: CaptureAgendaRow? = entry.retiredLinkCount > 0
            ? makeRetiredRow(count: entry.retiredLinkCount, role: entry.role)
            : nil
        let empty: CaptureAgendaRow? = tasks.isEmpty
            ? CaptureAgendaRow(
                kind: .emptyGroup,
                text: "No linked tasks",
                depth: 1,
                lineLimit: 1,
                accessibilityLabel: "No linked tasks"
            )
            : nil
        let oneRow = makeOneRowRow(name: name, tasks: tasks)
        return CaptureAgendaGroup(
            id: .group(entryLine: entry.line),
            role: entry.role,
            entryLine: entry.line,
            name: name,
            headerRow: header,
            sessionNoteRows: sessionNotes,
            sessionNotesChip: chip,
            tasks: tasks,
            retiredRow: retired,
            emptyRow: empty,
            oneRowRow: oneRow,
            stripName: name,
            accessibilityLabel: groupAccessibilityLabel(
                entry: entry,
                name: name,
                taskCount: tasks.count
            )
        )
    }

    static func makeHeaderRow(
        entry: CaptureAgendaPomodoro,
        name: String,
        now: Date?
    ) -> CaptureAgendaRow {
        let accessory: String?
        let label: String
        switch entry.role {
        case .current:
            let range = CaptureAgendaClock.timeRangeText(
                startsAt: entry.startsAt,
                endsAt: entry.endsAt
            )
            let countdown = now.flatMap {
                CaptureAgendaClock.remainingText(endsAt: entry.endsAt, now: $0)
            }
            accessory = [range, countdown].compactMap { $0 }.joined(separator: " · ")
            label = "Header, \(name)"
        case .open:
            let range = CaptureAgendaClock.timeRangeText(
                startsAt: entry.startsAt,
                endsAt: entry.endsAt
            )
            if let range {
                accessory = "Open · \(range)"
            } else {
                accessory = "Open"
            }
            label = "Header, \(name)"
        case .next:
            accessory = "= starts it"
            label = "Header, \(name)"
        case .later:
            if entry.selectable, let slug = entry.slug, !slug.isEmpty {
                accessory = "=#\(slug)"
            } else {
                accessory = nil
            }
            label = "Header, \(name)"
        case .completed, .other:
            accessory = nil
            label = "Header, \(name)"
        }
        let trimmed = accessory.flatMap { $0.isEmpty ? nil : $0 }
        return CaptureAgendaRow(
            kind: .groupHeader,
            text: name,
            depth: 0,
            lineLimit: 2,
            accessoryText: trimmed,
            accessibilityLabel: label
        )
    }

    static func groupAccessibilityLabel(
        entry: CaptureAgendaPomodoro,
        name: String,
        taskCount: Int
    ) -> String {
        let roleWord: String
        switch entry.role {
        case .current:
            roleWord = "Running"
        case .open:
            roleWord = "Open"
        case .next:
            roleWord = "Next"
        case .later, .completed, .other:
            roleWord = "Later"
        }
        let range = CaptureAgendaClock.accessibilityRangeText(
            startsAt: entry.startsAt,
            endsAt: entry.endsAt
        )
        let tasks = taskCount == 1 ? "1 task" : "\(taskCount) tasks"
        if let range {
            return "\(roleWord) Pomodoro \(name), \(range), \(tasks)"
        }
        return "\(roleWord) Pomodoro \(name), \(tasks)"
    }

    static func makeRetiredRow(count: Int, role: CaptureAgendaRole) -> CaptureAgendaRow {
        let text: String
        switch role {
        case .current, .open:
            text = "✓ \(count) done this session"
        case .next, .later, .completed, .other:
            text = "✓ \(count) done"
        }
        return CaptureAgendaRow(
            kind: .retired,
            text: text,
            depth: 1,
            lineLimit: 1,
            accessibilityLabel: text
        )
    }

    static func makeOneRowRow(
        name: String,
        tasks: [CaptureAgendaTask]
    ) -> CaptureAgendaRow {
        let titles = tasks.map(\.title).joined(separator: " · ")
        let joined = titles.isEmpty ? name : "\(name) · \(titles)"
        let text = truncate(joined, to: CaptureAgendaLayoutMetrics.maxOneRowLength)
        let chip = tasks.count == 1 ? "1 task" : "\(tasks.count) tasks"
        return CaptureAgendaRow(
            kind: .groupOneRow,
            text: text,
            depth: 0,
            lineLimit: CaptureAgendaLayoutMetrics.oneLineLimit,
            accessoryText: chip,
            accessibilityLabel: "\(name), \(chip)"
        )
    }

    // MARK: - Tasks

    static func makeTask(
        item: CaptureAgendaItem,
        number: Int,
        entry: CaptureAgendaPomodoro,
        groupName: String,
        seen: inout Set<String>,
        firstNames: inout [String: String]
    ) -> CaptureAgendaTask {
        let id = CaptureAgendaUnitID.task(ledgerLine: item.ledgerLine)
        let title = item.text ?? item.blockLink
        let status = item.statusName ?? "Unknown"
        let labelNumber = item.index.map(String.init) ?? "\(number)"
        let baseLabel = "Task \(labelNumber), \(status), \(title)"
        if item.resolution == .resolved, isDoneStatus(item.statusType) {
            let row = CaptureAgendaRow(
                kind: .struck,
                text: title,
                depth: 0,
                lineLimit: CaptureAgendaLayoutMetrics.oneLineLimit,
                numberBadge: item.index,
                statusGlyph: item.statusSymbol,
                accessibilityLabel: "\(baseLabel), completed"
            )
            return CaptureAgendaTask(
                id: id,
                title: title,
                fullRows: [row],
                noLogsRows: [row],
                oneLineRow: row
            )
        }
        if item.resolution != .resolved {
            let warning = item.warning.map { truncate($0, to: maxWarningLength) }
            let text = warning == nil ? item.blockLink : "\(item.blockLink) — \(warning ?? "")"
            let row = CaptureAgendaRow(
                kind: .warning,
                text: text,
                depth: 0,
                lineLimit: 2,
                accessibilityLabel: warning == nil
                    ? "Warning, \(item.blockLink)"
                    : "Warning, \(warning ?? "")"
            )
            return CaptureAgendaTask(
                id: id,
                title: title,
                fullRows: [row],
                noLogsRows: [row],
                oneLineRow: row
            )
        }
        if !item.blockID.isEmpty {
            let target = item.relativeTarget ?? ""
            let key = "\(target)\n\(item.blockID)"
            if seen.contains(key) {
                let first = firstNames[key] ?? groupName
                let row = CaptureAgendaRow(
                    kind: .duplicate,
                    text: "\(title) ↑ in \(first)",
                    depth: 0,
                    lineLimit: CaptureAgendaLayoutMetrics.oneLineLimit,
                    numberBadge: item.index,
                    statusGlyph: item.statusSymbol,
                    accessibilityLabel: "\(baseLabel), already shown"
                )
                return CaptureAgendaTask(
                    id: id,
                    title: title,
                    fullRows: [row],
                    noLogsRows: [row],
                    oneLineRow: row
                )
            }
            seen.insert(key)
            if firstNames[key] == nil {
                firstNames[key] = groupName
            }
        }
        return makeFullTask(
            id: id,
            item: item,
            title: title,
            entry: entry,
            baseLabel: baseLabel
        )
    }

    static func makeFullTask(
        id: CaptureAgendaUnitID,
        item: CaptureAgendaItem,
        title: String,
        entry: CaptureAgendaPomodoro,
        baseLabel: String
    ) -> CaptureAgendaTask {
        let caption = markerCaption(marker: item.marker, role: entry.role)
        let headline = CaptureAgendaRow(
            kind: .taskHeadline,
            text: title,
            depth: 0,
            lineLimit: CaptureAgendaLayoutMetrics.headlineLineLimit,
            numberBadge: item.index,
            accessoryText: caption,
            statusGlyph: item.statusSymbol,
            accessibilityLabel: baseLabel
        )
        let ledgerRows = item.ledgerNotes.map { note in
            CaptureAgendaRow(
                kind: .ledgerNote,
                text: note.text,
                depth: max(1, note.depth),
                lineLimit: CaptureAgendaLayoutMetrics.childLineLimit,
                statusGlyph: note.statusSymbol,
                accessibilityLabel: note.text
            )
        }
        let childRows = childRowsForLines(item.lines)
        let truncationRow = item.linesTruncated > 0
            ? CaptureAgendaRow(
                kind: .truncation,
                text: "+\(item.linesTruncated) more lines",
                depth: 1,
                lineLimit: 1,
                accessibilityLabel: "Show \(item.linesTruncated) hidden lines"
            )
            : nil
        let full = [headline] + ledgerRows + childRows + (truncationRow.map { [$0] } ?? [])
        let chips = logChips(lines: item.lines)
        let chipText = chips.isEmpty ? nil : chips.joined(separator: " · ")
        let chipLabel = chips.isEmpty ? nil : chips.map(accessibilityChip).joined(separator: ", ")
        let noLogsHeadline = CaptureAgendaRow(
            kind: .taskHeadline,
            text: title,
            depth: 0,
            lineLimit: CaptureAgendaLayoutMetrics.headlineLineLimit,
            numberBadge: item.index,
            accessoryText: joinAccessories([chipText, caption]),
            statusGlyph: item.statusSymbol,
            accessibilityLabel: baseLabel,
            accessoryAccessibilityLabel: chipLabel
        )
        let plainChildren = childRows.filter { $0.kind != .logHeader && $0.kind != .logEntry }
        let noLogs = [noLogsHeadline] + ledgerRows + plainChildren
            + (truncationRow.map { [$0] } ?? [])
        let hiddenCount = item.ledgerNotes.count + item.lines.count + item.linesTruncated
        let oneLine = CaptureAgendaRow(
            kind: .taskHeadline,
            text: title,
            depth: 0,
            lineLimit: CaptureAgendaLayoutMetrics.oneLineLimit,
            numberBadge: item.index,
            accessoryText: joinAccessories(["+\(hiddenCount) lines", caption]),
            statusGlyph: item.statusSymbol,
            accessibilityLabel: baseLabel,
            accessoryAccessibilityLabel: "Show \(hiddenCount) hidden lines"
        )
        return CaptureAgendaTask(
            id: id,
            title: title,
            fullRows: full,
            noLogsRows: noLogs,
            oneLineRow: oneLine
        )
    }

    /// Log-marker lines become canonical headers; every other line keeps
    /// its depth and kind.
    static func childRowsForLines(_ lines: [CaptureAgendaLine]) -> [CaptureAgendaRow] {
        lines.map { line in
            switch (line.kind, line.log) {
            case (.logMarker, .work):
                return CaptureAgendaRow(
                    kind: .logHeader,
                    text: "⚒ Work log",
                    depth: line.depth,
                    lineLimit: 1,
                    accessibilityLabel: "Work log"
                )
            case (.logMarker, .schedule):
                return CaptureAgendaRow(
                    kind: .logHeader,
                    text: "🗓 Schedule log",
                    depth: line.depth,
                    lineLimit: 1,
                    accessibilityLabel: "Schedule log"
                )
            case (.logMarker, _):
                return CaptureAgendaRow(
                    kind: .logHeader,
                    text: line.text,
                    depth: line.depth,
                    lineLimit: 1,
                    accessibilityLabel: line.text
                )
            case (_, .work), (_, .schedule):
                return CaptureAgendaRow(
                    kind: .logEntry,
                    text: line.text,
                    depth: line.depth,
                    lineLimit: CaptureAgendaLayoutMetrics.childLineLimit,
                    statusGlyph: line.statusSymbol,
                    accessibilityLabel: line.text
                )
            case (_, _):
                return CaptureAgendaRow(
                    kind: .childLine,
                    text: line.text,
                    depth: line.depth,
                    lineLimit: CaptureAgendaLayoutMetrics.childLineLimit,
                    statusGlyph: line.statusSymbol,
                    accessibilityLabel: line.text
                )
            }
        }
    }

    /// Per-kind direct-entry counts (`"⚒ 3"`, `"🗓 2"`): lines tagged
    /// with a log whose depth is exactly one past their marker's.
    static func logChips(lines: [CaptureAgendaLine]) -> [String] {
        var work = 0
        var schedule = 0
        var markerDepth: Int? = nil
        var markerLog: CaptureAgendaLog? = nil
        for line in lines {
            if line.kind == .logMarker {
                markerDepth = line.depth
                markerLog = line.log
                continue
            }
            guard let depth = markerDepth, let log = markerLog else {
                continue
            }
            guard line.log == log, line.depth == depth + 1 else {
                continue
            }
            switch log {
            case .work:
                work += 1
            case .schedule:
                schedule += 1
            case .other:
                break
            }
        }
        var chips: [String] = []
        if work > 0 {
            chips.append("⚒ \(work)")
        }
        if schedule > 0 {
            chips.append("🗓 \(schedule)")
        }
        return chips
    }

    static func accessibilityChip(_ chip: String) -> String {
        if chip.hasPrefix("⚒") {
            return "Show work log, \(chip.dropFirst(2)) entries"
        }
        if chip.hasPrefix("🗓") {
            return "Show schedule log, \(chip.dropFirst(2)) entries"
        }
        return chip
    }

    /// Trailing captions appear on the current entry only.
    static func markerCaption(marker: CaptureAgendaMarker, role: CaptureAgendaRole) -> String? {
        guard role == .current else {
            return nil
        }
        switch marker {
        case .deferred:
            return "deferred"
        case .embedded:
            return "completes on close"
        case .plain, .other:
            return nil
        }
    }

    static func isDoneStatus(_ statusType: String?) -> Bool {
        statusType == "DONE" || statusType == "CANCELLED"
    }

    static func joinAccessories(_ parts: [String?]) -> String? {
        let kept = parts.compactMap { $0 }.filter { !$0.isEmpty }
        guard !kept.isEmpty else {
            return nil
        }
        return kept.joined(separator: " · ")
    }

    static func truncate(_ text: String, to length: Int) -> String {
        guard text.count > length else {
            return text
        }
        return String(text.prefix(length - 1)) + "…"
    }

    private static var maxWarningLength: Int {
        CaptureAgendaLayoutMetrics.maxWarningLength
    }

    private static var maxStripLength: Int {
        CaptureAgendaLayoutMetrics.maxStripCharacters
    }

    // MARK: - Duplicate tracking

    /// Repeats are tracked per build: `makeGroups` threads one `seen`
    /// set plus one `"target\\nblock"`-to-group-name map through every
    /// group, so the first full rendering wins and later repeats render
    /// `↑ in <first group>`. Nothing here is shared across builds.
    static func duplicateKey(target: String?, blockID: String) -> String {
        "\(target ?? "")\n\(blockID)"
    }
}
