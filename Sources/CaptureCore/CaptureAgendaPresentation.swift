import Foundation

/// Stable identity for a foldable agenda unit: one task (by ledger
/// line), one Pomodoro group (by entry line), or the Later name strip.
public enum CaptureAgendaUnitID: Hashable, Equatable, Sendable {
    case task(ledgerLine: Int)
    case group(entryLine: Int)
    case strip
    /// The Calendar band as a whole: expanding pins it at full.
    case calendar
    /// The band's ended rows: expanding reveals them in the full fold.
    case calendarEarlier
}

/// The kind of one rendered agenda row. Part of the row key, so a kind
/// change always re-measures.
public enum CaptureAgendaRowKind: Hashable, Equatable, Sendable {
    case title
    case planBudget
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
    case calendarHeader
    case calendarRail
    case calendarAllDay
    case calendarRow
    case calendarGap
    case calendarConflict
    case calendarMore
    case calendarClear
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
    public let notesChip: String?
    public let nameIsDerived: Bool
    public let homeChip: String?
    public let homeHue: PomodoroHomeHue?
    public let homeIsForecast: Bool
    /// The title's decorative off-clock summary chip. Its spoken form is
    /// folded into the title row's accessibility label.
    public let titleOffClockText: String?
    /// Theme hues for a group header or one-row name, in component
    /// order. Part of the measure key so a hue change re-measures.
    public let themeHues: [PomodoroHomeHue?]
    /// Calendar event facts for a `.calendarRow`: time text, join
    /// URL, and countdown all affect measurement.
    public let calendar: CaptureAgendaCalendarRowData?
    public let calendarRail: CaptureAgendaRailData?
    public let sessionOffClock: Bool

    public init(
        kind: CaptureAgendaRowKind,
        text: String,
        depth: Int,
        lineLimit: Int,
        hasAccessory: Bool,
        notesChip: String? = nil,
        nameIsDerived: Bool = false,
        homeChip: String? = nil,
        homeHue: PomodoroHomeHue? = nil,
        homeIsForecast: Bool = false,
        titleOffClockText: String? = nil,
        themeHues: [PomodoroHomeHue?] = [],
        calendar: CaptureAgendaCalendarRowData? = nil,
        calendarRail: CaptureAgendaRailData? = nil,
        sessionOffClock: Bool = false
    ) {
        self.kind = kind
        self.text = text
        self.depth = depth
        self.lineLimit = lineLimit
        self.hasAccessory = hasAccessory
        self.notesChip = notesChip
        self.nameIsDerived = nameIsDerived
        self.homeChip = homeChip
        self.homeHue = homeHue
        self.homeIsForecast = homeIsForecast
        self.titleOffClockText = titleOffClockText
        self.themeHues = themeHues
        self.calendar = calendar
        self.calendarRail = calendarRail
        self.sessionOffClock = sessionOffClock
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
    /// Typed data for the shared saved-budget capsules. Its visible
    /// labels are also included in `key.text` for height-cache identity.
    public let planBudget: CapturePlanBudgetPresentation?
    /// A session-notes chip rendered as its own capsule button next
    /// to the header's normal trailing accessory, never inside it.
    public let notesChip: String?
    /// True when `text` is a derived home label, so the view paints it
    /// in a secondary style.
    public let nameIsDerived: Bool
    /// Named-entry home chip (bob already suppressed it when the name
    /// says the same thing). Drawn as a muted accessory with a hue dot.
    public let homeChip: String?
    public let homeHue: PomodoroHomeHue?
    /// True when the chip's homes state is forecast: the view draws a
    /// hollow ring (R7) instead of a filled dot.
    public let homeIsForecast: Bool
    /// The title's decorative off-clock summary chip. Its spoken form is
    /// folded into the title row's accessibility label.
    public let titleOffClockText: String?
    /// Bob-owned theme refs for a group header or one-row name, in
    /// component order. Empty for every other row and on an older Bob.
    public let themeRefs: [CapturePomodoroThemeRef]
    /// Calendar event facts for a `.calendarRow`. Nil for every other
    /// kind: the view renders the row from these, never from JSON.
    public let calendar: CaptureAgendaCalendarRowData?
    /// Normalized positions for the decorative day rail.
    public let calendarRail: CaptureAgendaRailData?
    /// True only for an entry Bob explicitly reports as off-clock
    /// session; older Bob leaves the Now header unchanged.
    public let sessionOffClock: Bool

    public init(
        kind: CaptureAgendaRowKind,
        text: String,
        depth: Int,
        lineLimit: Int,
        numberBadge: Int? = nil,
        accessoryText: String? = nil,
        statusGlyph: String? = nil,
        accessibilityLabel: String? = nil,
        accessoryAccessibilityLabel: String? = nil,
        notesChip: String? = nil,
        planBudget: CapturePlanBudgetPresentation? = nil,
        nameIsDerived: Bool = false,
        homeChip: String? = nil,
        homeHue: PomodoroHomeHue? = nil,
        homeIsForecast: Bool = false,
        titleOffClockText: String? = nil,
        themeRefs: [CapturePomodoroThemeRef] = [],
        calendar: CaptureAgendaCalendarRowData? = nil,
        calendarRail: CaptureAgendaRailData? = nil,
        sessionOffClock: Bool = false
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
        self.notesChip = notesChip
        self.planBudget = planBudget
        self.nameIsDerived = nameIsDerived
        self.homeChip = homeChip
        self.homeHue = homeHue
        self.homeIsForecast = homeIsForecast
        self.titleOffClockText = titleOffClockText
        self.themeRefs = themeRefs
        self.calendar = calendar
        self.calendarRail = calendarRail
        self.sessionOffClock = sessionOffClock
        key = CaptureAgendaRowKey(
            kind: kind,
            text: text,
            depth: depth,
            lineLimit: lineLimit,
            hasAccessory: numberBadge != nil || accessoryText != nil
                || titleOffClockText != nil || sessionOffClock,
            notesChip: notesChip,
            nameIsDerived: nameIsDerived,
            homeChip: homeChip,
            homeHue: homeHue,
            homeIsForecast: homeIsForecast,
            titleOffClockText: titleOffClockText,
            themeHues: themeRefs.map(\.hue),
            calendar: calendar,
            calendarRail: calendarRail,
            sessionOffClock: sessionOffClock
        )
    }

    /// Per-component swatches for the row's theme refs, in order.
    public var themeSwatches: [CaptureThemeSwatch] {
        themeRefs.map { CaptureThemeSwatch($0) }
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
    /// Bob's saved daily theme and Task Link meters. Present only for a
    /// same-day snapshot that includes `plan_budget`.
    public let planBudgetRow: CaptureAgendaRow?
    public let warningRow: CaptureAgendaRow?
    public let groups: [CaptureAgendaGroup]
    /// The Calendar band: today's events from bob's additive `events`
    /// block, placed after the Now groups (or after the title rows
    /// when nothing runs). Nil when bob omits `events` (older bob) or
    /// when the block carries no rows and no all-day lines.
    public let calendar: CaptureAgendaCalendar?
    /// True while the band shows a running or upcoming event: the view
    /// mounts its minute-granularity countdown then, even with no
    /// running Pomodoro.
    public var calendarNeedsTick: Bool {
        calendar?.hasTickingEvent == true
    }
    public let stateRow: CaptureAgendaRow?
    /// The title row's stale suffix, shared by the presentation and the
    /// view's stale-icon split. Never a ledger fact, only wording.
    public static let staleSuffix = "Couldn't refresh"
    /// The strip with every Later name: the unmeasured fallback for
    /// budgeting the strip; the rendered strip lists the current
    /// members.
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
            $0.role == .current
                && (!($0.startsAt ?? "").isEmpty || !($0.endsAt ?? "").isEmpty)
        }
        titleRow = Self.makeTitleRow(
            rawDate: snapshot.date,
            nothingRunning: nothingRunning,
            summaryText: summaryText,
            offClockMinutes: snapshot.completedSummary.offClock.minutes,
            locale: locale,
            stale: isStale
        )
        let ordered = Self.orderEntries(entries)
        warningRow = openCount >= 2 ? Self.makeMultiOpenWarningRow() : nil
        let laterEntries = ordered.filter { $0.role == .later }
        let laterNames = laterEntries.map(Self.displayName)
        let laterSpoken = laterEntries.map(Self.spokenName)
        stripFullRow = Self.makeStripRow(names: laterNames, spokenNames: laterSpoken)
        guard snapshot.date == today else {
            state = .loading
            planBudgetRow = nil
            groups = []
            calendar = nil
            stateRow = Self.makeStateRow(text: "Loading today…")
            return
        }
        planBudgetRow = snapshot.planBudget.map(Self.makePlanBudgetRow)
        calendar = Self.makeCalendar(
            events: snapshot.events,
            entries: snapshot.pomodoros,
            date: today,
            now: now,
            locale: locale
        )
        guard !ordered.isEmpty else {
            groups = []
            if Self.hasMissingDailyNoteWarning(snapshot.warnings) {
                state = .noDailyNote
                stateRow = Self.makeStateRow(text: "No daily note for today yet")
            } else {
                state = .noOpen
                stateRow = Self.makeStateRow(text: "No Pomodoros planned · =#NAME starts one")
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

    static func displayName(_ entry: CaptureAgendaPomodoro) -> String {
        PomodoroHomesPresentation.displayName(authored: entry.name, homes: entry.homes)
    }

    static func nameIsDerived(_ entry: CaptureAgendaPomodoro) -> Bool {
        PomodoroHomesPresentation.nameIsDerived(authored: entry.name, homes: entry.homes)
    }

    static func namedHomeChip(_ entry: CaptureAgendaPomodoro) -> String? {
        PomodoroHomesPresentation.namedChip(authored: entry.name, homes: entry.homes)
    }

    static func spokenName(_ entry: CaptureAgendaPomodoro) -> String {
        PomodoroHomesPresentation.accessibilityName(authored: entry.name, homes: entry.homes)
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
            planBudgetRow: nil,
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
        planBudgetRow: CaptureAgendaRow?,
        warningRow: CaptureAgendaRow?,
        groups: [CaptureAgendaGroup],
        calendar: CaptureAgendaCalendar? = nil,
        stateRow: CaptureAgendaRow?,
        stripFullRow: CaptureAgendaRow
    ) {
        self.state = state
        self.titleRow = titleRow
        self.summaryText = summaryText
        self.isStale = isStale
        self.hasLiveCountdown = hasLiveCountdown
        self.planBudgetRow = planBudgetRow
        self.warningRow = warningRow
        self.groups = groups
        self.calendar = calendar
        self.stateRow = stateRow
        self.stripFullRow = stripFullRow
    }

    static func makeTitleRow(
        rawDate: String?,
        nothingRunning: Bool,
        summaryText: String?,
        offClockMinutes: Int = 0,
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
        let offClockDuration = offClockMinutes > 0
            ? CaptureAgendaClock.offClockDurationText(minutes: offClockMinutes)
            : nil
        let offClockChipText = offClockDuration.map { "◌ \($0) off-clock" }
        let spokenAccessory = [
            summaryText,
            offClockDuration.map { "\($0) off-clock" },
            stale ? staleSuffix : nil,
        ].compactMap { $0 }.joined(separator: ", ")
        return CaptureAgendaRow(
            kind: .title,
            text: text,
            depth: 0,
            lineLimit: 1,
            accessoryText: accessory,
            accessibilityLabel: spokenAccessory.isEmpty ? text : "\(text). \(spokenAccessory)",
            titleOffClockText: offClockChipText
        )
    }

    static func makeMultiOpenWarningRow() -> CaptureAgendaRow {
        let text = "Multiple open timed sessions — close one so `x` knows which is running"
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

    static func makePlanBudgetRow(_ budget: CapturePlanBudget) -> CaptureAgendaRow {
        let presentation = CapturePlanBudgetPresentation(
            budget: budget,
            destination: nil,
            includeProposalDetails: false
        )
        let text = presentation.linksCapsuleText
        return CaptureAgendaRow(
            kind: .planBudget,
            text: text,
            depth: 0,
            lineLimit: 1,
            accessibilityLabel: "Plan budget: \(text)",
            planBudget: presentation
        )
    }

    private static func hasMissingDailyNoteWarning(_ warnings: [String]) -> Bool {
        warnings.contains {
            $0.hasPrefix("Bob daily note does not exist:")
                || $0.hasPrefix("Bob daily note has no Pomodoros section:")
        }
    }

    /// The Later name strip for the given member names. Names past the
    /// character budget fold into a `+N` overflow token. The spoken text
    /// uses each entry's spoken name, so derived labels read "for <label>".
    static func makeStripRow(names: [String], spokenNames: [String]? = nil) -> CaptureAgendaRow {
        let text = Self.stripText(names: names)
        return CaptureAgendaRow(
            kind: .strip,
            text: text,
            depth: 0,
            lineLimit: CaptureAgendaLayoutMetrics.stripLineLimit,
            accessibilityLabel: Self.stripAccessibilityText(names: spokenNames ?? names)
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
        let name = displayName(entry)
        let derived = nameIsDerived(entry)
        let homeChip = namedHomeChip(entry)
        let homeHue = homeChip == nil ? nil : entry.homes?.hue
        let homeIsForecast = homeChip != nil && entry.homes?.state == .forecast
        let header = makeHeaderRow(
            entry: entry,
            name: name,
            spoken: spokenName(entry),
            derived: derived,
            homeChip: homeChip,
            homeHue: homeHue,
            homeIsForecast: homeIsForecast,
            themeRefs: entry.themes,
            now: now
        )
        let sessionNotes = entry.notes.map { note in
            CaptureAgendaRow(
                kind: .sessionNote,
                text: note.text,
                depth: note.depth,
                lineLimit: CaptureAgendaLayoutMetrics.childLineLimit,
                statusGlyph: note.statusSymbol,
                accessibilityLabel: spokenKeepText(note.text)
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
        let oneRow = makeOneRowRow(
            name: name,
            tasks: tasks,
            derived: derived,
            homeChip: homeChip,
            homeHue: homeHue,
            homeIsForecast: homeIsForecast,
            themeRefs: entry.themes,
            spoken: spokenName(entry)
        )
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
                name: spokenName(entry),
                taskCount: tasks.count
            )
        )
    }

    static func makeHeaderRow(
        entry: CaptureAgendaPomodoro,
        name: String,
        spoken: String,
        derived: Bool,
        homeChip: String?,
        homeHue: PomodoroHomeHue?,
        homeIsForecast: Bool = false,
        themeRefs: [CapturePomodoroThemeRef] = [],
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
                if let start = entry.startsAt,
                    let startDate = CaptureAgendaClock.date(fromNaiveLocal: start),
                    startDate > $0,
                    let until = CaptureAgendaClock.countdownUntilText(
                        startsAt: entry.startsAt,
                        now: $0
                    )
                {
                    return "starts \(until)"
                }
                return CaptureAgendaClock.remainingText(endsAt: entry.endsAt, now: $0)
            }
            accessory = [range, countdown].compactMap { $0 }.joined(separator: " · ")
            label =
                entry.offClock == true
                ? "Header, \(spoken), off-clock session"
                : "Header, \(spoken)"
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
            label = "Header, \(spoken)"
        case .next:
            accessory = "= starts it"
            label = "Header, \(spoken)"
        case .later:
            if entry.selectable, let slug = entry.slug, !slug.isEmpty {
                accessory = "=#\(slug)"
            } else {
                accessory = nil
            }
            label = "Header, \(spoken)"
        case .completed, .other:
            accessory = nil
            label = "Header, \(spoken)"
        }
        let trimmed = accessory.flatMap { $0.isEmpty ? nil : $0 }
        let themeWords = themeRefs.isEmpty ? [] : PomodoroThemeSwatches.spokenThemeColors(
            forName: name,
            refs: themeRefs
        )
        let spokenLabel = themeWords.isEmpty
            ? label
            : "\(label), types \(themeWords.joined(separator: "; "))"
        return CaptureAgendaRow(
            kind: .groupHeader,
            text: name,
            depth: 0,
            lineLimit: 2,
            accessoryText: trimmed,
            accessibilityLabel: spokenLabel,
            nameIsDerived: derived,
            homeChip: homeChip,
            homeHue: homeHue,
            homeIsForecast: homeIsForecast,
            themeRefs: themeRefs,
            sessionOffClock: entry.role == .current && entry.offClock == true
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
        tasks: [CaptureAgendaTask],
        derived: Bool,
        homeChip: String?,
        homeHue: PomodoroHomeHue?,
        homeIsForecast: Bool = false,
        themeRefs: [CapturePomodoroThemeRef] = [],
        spoken: String
    ) -> CaptureAgendaRow {
        let titles = tasks.map { spokenKeepText($0.title) }.joined(separator: " · ")
        let joined = titles.isEmpty ? name : "\(name) · \(titles)"
        let text = truncate(joined, to: CaptureAgendaLayoutMetrics.maxOneRowLength)
        let chip = tasks.count == 1 ? "1 task" : "\(tasks.count) tasks"
        return CaptureAgendaRow(
            kind: .groupOneRow,
            text: text,
            depth: 0,
            lineLimit: CaptureAgendaLayoutMetrics.oneLineLimit,
            accessoryText: chip,
            accessibilityLabel: "\(spoken), \(chip)",
            nameIsDerived: derived,
            homeChip: homeChip,
            homeHue: homeHue,
            homeIsForecast: homeIsForecast,
            themeRefs: themeRefs
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
        let spokenTitle = spokenKeepText(title)
        let status = item.statusName ?? "Unknown"
        let baseLabel: String
        if let index = item.index {
            baseLabel = "Task \(index), \(status), \(spokenTitle)"
        } else {
            baseLabel = "Task, \(status), \(spokenTitle)"
        }
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
                lineLimit: 1,
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
        // MEET items linked to an Event Task wear the event's time
        // chip instead of the bold span.
        let timeChip = eventTimeChip(item: item, entry: entry)
        let title = timeChip == nil ? title : stripLeadingBoldSpan(title)
        let headline = CaptureAgendaRow(
            kind: .taskHeadline,
            text: title,
            depth: 0,
            lineLimit: CaptureAgendaLayoutMetrics.headlineLineLimit,
            numberBadge: item.index,
            accessoryText: joinAccessories([timeChip, caption]),
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
                accessibilityLabel: spokenKeepText(note.text)
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
            accessoryText: joinAccessories([timeChip, chipText, caption]),
            statusGlyph: item.statusSymbol,
            accessibilityLabel: baseLabel,
            accessoryAccessibilityLabel: chipLabel
        )
        let plainChildren = childRows.filter { $0.kind != .logHeader && $0.kind != .logEntry }
        let noLogs = [noLogsHeadline] + ledgerRows + plainChildren
            + (truncationRow.map { [$0] } ?? [])
        let hiddenCount = item.ledgerNotes.count + item.lines.count + item.linesTruncated
        let hiddenChip: String? = hiddenCount > 0 ? "+\(hiddenCount) lines" : nil
        let hiddenLabel: String? = hiddenCount > 0 ? "Show \(hiddenCount) hidden lines" : nil
        let oneLine = CaptureAgendaRow(
            kind: .taskHeadline,
            text: title,
            depth: 0,
            lineLimit: CaptureAgendaLayoutMetrics.oneLineLimit,
            numberBadge: item.index,
            accessoryText: joinAccessories([timeChip, hiddenChip, caption]),
            statusGlyph: item.statusSymbol,
            accessibilityLabel: baseLabel,
            accessoryAccessibilityLabel: hiddenLabel
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
            case (.logMarker, .rotten):
                return CaptureAgendaRow(
                    kind: .logHeader,
                    text: "🥀 Rotten log",
                    depth: line.depth,
                    lineLimit: 1,
                    accessibilityLabel: "Rotten log"
                )
            case (.logMarker, _):
                return CaptureAgendaRow(
                    kind: .logHeader,
                    text: line.text,
                    depth: line.depth,
                    lineLimit: 1,
                    accessibilityLabel: spokenKeepText(line.text)
                )
            case (_, .work), (_, .schedule), (_, .rotten):
                return CaptureAgendaRow(
                    kind: .logEntry,
                    text: line.text,
                    depth: line.depth,
                    lineLimit: CaptureAgendaLayoutMetrics.childLineLimit,
                    statusGlyph: line.statusSymbol,
                    accessibilityLabel: spokenKeepText(line.text)
                )
            case (_, _):
                return CaptureAgendaRow(
                    kind: .childLine,
                    text: line.text,
                    depth: line.depth,
                    lineLimit: CaptureAgendaLayoutMetrics.childLineLimit,
                    statusGlyph: line.statusSymbol,
                    accessibilityLabel: spokenKeepText(line.text)
                )
            }
        }
    }

    /// Per-kind direct-entry counts (`"⚒ 3"`, `"🗓 2"`, `"🥀 1"`): lines
    /// tagged with a log whose depth is exactly one past their marker's.
    static func logChips(lines: [CaptureAgendaLine]) -> [String] {
        var work = 0
        var schedule = 0
        var rotten = 0
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
            case .rotten:
                rotten += 1
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
        if rotten > 0 {
            chips.append("🥀 \(rotten)")
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
        if chip.hasPrefix("🥀") {
            return "Show rotten log, \(chip.dropFirst(2)) entries"
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

    /// Narrow Keep-link projection for spoken labels and one-row
    /// summaries. Ordinary row source text stays raw so the inline
    /// renderer still sees a complete `[💡](url)` span.
    static func spokenKeepText(_ source: String) -> String {
        CaptureAgendaInlineText.projectingKeepSourceLinks(source)
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

// MARK: - Calendar band

/// Per-event facts for one `.calendarRow`. The view renders the row
/// from these, never from snapshot JSON.
public struct CaptureAgendaCalendarRowData: Hashable, Equatable, Sendable {
    /// `"13:00–13:30"` for the monospaced time column.
    public let timeText: String
    public let hue: PomodoroHomeHue?
    /// True for off-clock events: the dot is hollow and dashed and a
    /// dashed "off-clock" capsule follows the title.
    public let offClock: Bool
    /// True for Maybe/free rows: the title renders italic and dimmed.
    public let dimmed: Bool
    /// The join target behind the row's join button. Nil when the
    /// event carries no join URL.
    public let joinURL: String?
    /// `"in 38m"` / `"23m left"` for running and upcoming rows. Ended
    /// rows carry the status glyph on the row instead.
    public let countdownText: String?
    /// The `=meet`-style fit draft, shown as a chip on the focus row.
    public let startHint: String?
    /// The buffer label (`"−30m +15m"`), shown as a quiet caption
    /// capsule after the title. Nil when the event has no buffer.
    public let bufferLabel: String?
    /// True while the event's buffer is in progress: the capsule tints
    /// with the event hue instead of the secondary color.
    public let bufferActive: Bool

    public init(
        timeText: String = "",
        hue: PomodoroHomeHue? = nil,
        offClock: Bool = false,
        dimmed: Bool = false,
        joinURL: String? = nil,
        countdownText: String? = nil,
        startHint: String? = nil,
        bufferLabel: String? = nil,
        bufferActive: Bool = false
    ) {
        self.timeText = timeText
        self.hue = hue
        self.offClock = offClock
        self.dimmed = dimmed
        self.joinURL = joinURL
        self.countdownText = countdownText
        self.startHint = startHint
        self.bufferLabel = bufferLabel
        self.bufferActive = bufferActive
    }
}

/// A hatched buffer wing fused to a rail capsule: the lead-in or
/// lead-out reserve around the meeting. Thinner than the capsule and
/// painted in the event's home hue. `active` while the buffer is in
/// progress (the lead-in or lead-out contains now).
public struct CaptureAgendaRailWing: Hashable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let active: Bool

    public init(start: Double, end: Double, active: Bool = false) {
        self.start = start
        self.end = end
        self.active = active
    }
}

/// A visible event capsule on the normalized day rail. The capsule
/// always spans the meeting; `leadingWing`/`trailingWing` extend it
/// through the buffered span when the event reserves one.
public struct CaptureAgendaRailEvent: Hashable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let hue: PomodoroHomeHue?
    public let offClock: Bool
    public let maybe: Bool
    public let leadingWing: CaptureAgendaRailWing?
    public let trailingWing: CaptureAgendaRailWing?

    public init(
        start: Double,
        end: Double,
        hue: PomodoroHomeHue? = nil,
        offClock: Bool = false,
        maybe: Bool = false,
        leadingWing: CaptureAgendaRailWing? = nil,
        trailingWing: CaptureAgendaRailWing? = nil
    ) {
        self.start = start
        self.end = end
        self.hue = hue
        self.offClock = offClock
        self.maybe = maybe
        self.leadingWing = leadingWing
        self.trailingWing = trailingWing
    }
}

/// One hour tick on the rail.
public struct CaptureAgendaRailTick: Hashable, Equatable, Sendable {
    public let position: Double
    public let label: String

    public init(position: Double, label: String) {
        self.position = position
        self.label = label
    }
}

/// The first open gap after Now or the running session.
public struct CaptureAgendaRailGap: Hashable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let minutes: Int

    public init(start: Double, end: Double, minutes: Int) {
        self.start = start
        self.end = end
        self.minutes = minutes
    }
}

/// Time-domain geometry for the decorative rail. Bob supplies the
/// event and session timestamps; this model only normalizes them for drawing.
public struct CaptureAgendaRailData: Hashable, Equatable, Sendable {
    public let now: Double
    public let ticks: [CaptureAgendaRailTick]
    public let events: [CaptureAgendaRailEvent]
    public let runningSession: CaptureAgendaRailEvent?
    public let firstGap: CaptureAgendaRailGap?

    public init(
        now: Double,
        ticks: [CaptureAgendaRailTick],
        events: [CaptureAgendaRailEvent],
        runningSession: CaptureAgendaRailEvent?,
        firstGap: CaptureAgendaRailGap?
    ) {
        self.now = now
        self.ticks = ticks
        self.events = events
        self.runningSession = runningSession
        self.firstGap = firstGap
    }
}

/// Fold level of the Calendar band. `full` shows every remaining row;
/// `compact` shows the focus row behind a `+N` chip; `oneRow` merges
/// the header and the next event into one line.
public enum CaptureAgendaCalendarState: Equatable, Sendable {
    case full
    case compact
    case oneRow
}

/// The Calendar band: today's events between the Now groups and the
/// Next/Later groups (or right after the title rows when nothing
/// runs). Every row is precomputed here, so the fit planner only
/// picks row lists and the view renders verbatim.
public struct CaptureAgendaCalendar: Equatable, Sendable {
    public let headerRow: CaptureAgendaRow
    public let allDayRow: CaptureAgendaRow?
    /// Reserved slot for the day rail (painted by a later phase): an
    /// empty decorative row in the `full` and `compact` folds.
    public let railRow: CaptureAgendaRow
    public let gapRow: CaptureAgendaRow?
    public let conflictRow: CaptureAgendaRow?
    /// Running and upcoming rows in note order.
    public let upcomingRows: [CaptureAgendaRow]
    /// Ended rows, shown only while `.calendarEarlier` is expanded.
    public let endedRows: [CaptureAgendaRow]
    /// The focus event's row: `compact` shows this one row.
    public let focusRow: CaptureAgendaRow?
    /// The focus event's join target for Command-J. Nil when the
    /// focus row carries no join URL.
    public let focusJoinURL: String?
    /// Ended rows hidden behind the earlier chip.
    public let earlierCount: Int
    /// `"+M earlier"` (full fold): reveals the ended rows.
    public let expandEarlierRow: CaptureAgendaRow?
    /// `"+N"` (compact fold): pins the whole band at full.
    public let expandAllRow: CaptureAgendaRow?
    /// Merged header-plus-next line for the `oneRow` fold.
    public let oneRowRow: CaptureAgendaRow
    /// `"Calendar clear for the rest of the day"` when every event
    /// has ended. The band is then exactly header plus this row.
    public let clearRow: CaptureAgendaRow?
    /// The next event boundary, for the store's refresh scheduling.
    public let refreshAt: String?
    /// True while a running or upcoming event remains: the view ticks
    /// every minute for the countdowns.
    public let hasTickingEvent: Bool
    public let accessibilityLabel: String

    public init(
        headerRow: CaptureAgendaRow,
        allDayRow: CaptureAgendaRow? = nil,
        railRow: CaptureAgendaRow,
        gapRow: CaptureAgendaRow? = nil,
        conflictRow: CaptureAgendaRow? = nil,
        upcomingRows: [CaptureAgendaRow] = [],
        endedRows: [CaptureAgendaRow] = [],
        focusRow: CaptureAgendaRow? = nil,
        focusJoinURL: String? = nil,
        earlierCount: Int = 0,
        expandEarlierRow: CaptureAgendaRow? = nil,
        expandAllRow: CaptureAgendaRow? = nil,
        oneRowRow: CaptureAgendaRow,
        clearRow: CaptureAgendaRow? = nil,
        refreshAt: String? = nil,
        hasTickingEvent: Bool = false,
        accessibilityLabel: String = "Calendar"
    ) {
        self.headerRow = headerRow
        self.allDayRow = allDayRow
        self.railRow = railRow
        self.gapRow = gapRow
        self.conflictRow = conflictRow
        self.upcomingRows = upcomingRows
        self.endedRows = endedRows
        self.focusRow = focusRow
        self.focusJoinURL = focusJoinURL
        self.earlierCount = earlierCount
        self.expandEarlierRow = expandEarlierRow
        self.expandAllRow = expandAllRow
        self.oneRowRow = oneRowRow
        self.clearRow = clearRow
        self.refreshAt = refreshAt
        self.hasTickingEvent = hasTickingEvent
        self.accessibilityLabel = accessibilityLabel
    }

    /// Every precomputed row, for the measurer: the planner picks
    /// subsets per fold, and the fixpoint pass measures new variants.
    public var allRows: [CaptureAgendaRow] {
        var rows = [headerRow]
        if let allDayRow {
            rows.append(allDayRow)
        }
        rows.append(railRow)
        if let gapRow {
            rows.append(gapRow)
        }
        if let conflictRow {
            rows.append(conflictRow)
        }
        rows += endedRows
        rows += upcomingRows
        if let expandEarlierRow {
            rows.append(expandEarlierRow)
        }
        if let expandAllRow {
            rows.append(expandAllRow)
        }
        rows.append(oneRowRow)
        if let clearRow {
            rows.append(clearRow)
        }
        return rows
    }

    /// Rows for the `full` fold: header, all-day line, rail slot, gap,
    /// conflict, upcoming rows (ended only while the earlier chip is
    /// expanded), and the earlier chip while ended rows stay hidden.
    public func fullRows(showEnded: Bool) -> [CaptureAgendaRow] {
        if let clearRow {
            var rows = [headerRow]
            if let allDayRow {
                rows.append(allDayRow)
            }
            rows.append(clearRow)
            return rows
        }
        var rows = [headerRow]
        if let allDayRow {
            rows.append(allDayRow)
        }
        rows.append(railRow)
        if let gapRow {
            rows.append(gapRow)
        }
        if let conflictRow {
            rows.append(conflictRow)
        }
        if showEnded {
            rows += endedRows
        }
        rows += upcomingRows
        if !showEnded, let expandEarlierRow {
            rows.append(expandEarlierRow)
        }
        return rows
    }

    /// Rows for the `compact` fold: header, rail slot, conflict, the
    /// focus row, and the `+N` chip while rows stay hidden.
    public func compactRows() -> [CaptureAgendaRow] {
        if let clearRow {
            return [headerRow, clearRow]
        }
        var rows = [headerRow, railRow]
        if let conflictRow {
            rows.append(conflictRow)
        }
        if let focusRow {
            rows.append(focusRow)
        }
        if let expandAllRow {
            rows.append(expandAllRow)
        }
        return rows
    }
}

// MARK: - Calendar band builders

extension CaptureAgendaPresentation {
    /// Builds the Calendar band from bob's additive `events` block.
    /// Nil when bob omits `events` (older bob) or when the block
    /// carries no rows and no all-day lines: the band stays hidden.
    static func makeCalendar(
        events: CaptureAgendaEvents?,
        entries: [CaptureAgendaPomodoro],
        date: String,
        now: Date?,
        locale: Locale
    ) -> CaptureAgendaCalendar? {
        guard let events else {
            return nil
        }
        guard !events.rows.isEmpty || !events.allDay.isEmpty else {
            return nil
        }
        let upcoming = events.rows.filter { $0.phase != .ended }
        let ended = events.rows.filter { $0.phase == .ended }
        let stamp = Self.calendarStampText(syncedAt: events.syncedAt, date: date, locale: locale)
        let header = Self.makeCalendarHeader(
            events: events,
            upcoming: upcoming,
            stamp: stamp,
            now: now
        )
        let railData = Self.makeCalendarRail(
            events: events,
            entries: entries,
            now: now
        )
        let railRow = CaptureAgendaRow(
            kind: .calendarRail,
            text: "",
            depth: 0,
            lineLimit: 1,
            accessibilityLabel: "Day timeline",
            calendarRail: railData
        )
        if upcoming.isEmpty {
            let clearText: String
            if let stamp {
                clearText = "Calendar clear for the rest of the day · \(stamp)"
            } else {
                clearText = "Calendar clear for the rest of the day"
            }
            let clearRow = CaptureAgendaRow(
                kind: .calendarClear,
                text: clearText,
                depth: 0,
                lineLimit: 1,
                accessibilityLabel: clearText
            )
            return CaptureAgendaCalendar(
                headerRow: header,
                allDayRow: Self.makeCalendarAllDayRow(events.allDay),
                railRow: railRow,
                oneRowRow: header,
                clearRow: clearRow,
                refreshAt: events.refreshAt,
                hasTickingEvent: false,
                accessibilityLabel: header.accessibilityLabel ?? "Calendar"
            )
        }
        let focusEvent = Self.calendarFocusEvent(events: events, upcoming: upcoming)
        let focusIndex = focusEvent.flatMap { focus in
            upcoming.firstIndex(where: { $0.line == focus.line })
        } ?? 0
        let upcomingRows = upcoming.indices.map { position in
            let row = upcoming[position]
            return Self.makeCalendarEventRow(
                row,
                countdown: Self.calendarCountdown(for: row, now: now),
                startHint: position == focusIndex ? events.startHint : nil,
                now: now
            )
        }
        let endedRows = ended.map {
            Self.makeCalendarEventRow($0, countdown: nil, startHint: nil, now: now)
        }
        let focusRow = upcomingRows.indices.contains(focusIndex)
            ? upcomingRows[focusIndex] : upcomingRows.first
        let earlierCount = ended.count
        let expandEarlierRow: CaptureAgendaRow? = earlierCount > 0
            ? Self.makeCalendarChipRow(
                text: "+\(earlierCount) earlier",
                label: "Show \(earlierCount) earlier events"
            ) : nil
        let hiddenCompact = max(0, upcomingRows.count - 1) + earlierCount
        let expandAllRow: CaptureAgendaRow? = hiddenCompact > 0
            ? Self.makeCalendarChipRow(
                text: "+\(hiddenCompact)",
                label: "Show \(hiddenCompact) more events"
            ) : nil
        let oneRowRow = Self.makeCalendarOneRow(
            header: header,
            upcoming: upcoming,
            focusIndex: focusIndex,
            earlierCount: earlierCount
        )
        return CaptureAgendaCalendar(
            headerRow: header,
            allDayRow: Self.makeCalendarAllDayRow(events.allDay),
            railRow: railRow,
            gapRow: events.gap.map(Self.makeCalendarGapRow),
            conflictRow: events.conflict.flatMap {
                Self.makeCalendarConflictRow($0, events: events, entries: entries)
            },
            upcomingRows: upcomingRows,
            endedRows: endedRows,
            focusRow: focusRow,
            focusJoinURL: focusEvent?.joinURL,
            earlierCount: earlierCount,
            expandEarlierRow: expandEarlierRow,
            expandAllRow: expandAllRow,
            oneRowRow: oneRowRow,
            refreshAt: events.refreshAt,
            hasTickingEvent: true,
            accessibilityLabel: header.accessibilityLabel ?? "Calendar"
        )
    }

    /// An event's meeting span plus the span it occupies with its
    /// buffer: `(meetingStart, meetingEnd, occupiedStart, occupiedEnd)`.
    /// Nil when the meeting times do not parse. Buffered bounds come
    /// from bob's `buffer.starts_at`/`ends_at` and clamp to at least the
    /// meeting, so a buffer never shrinks the capsule.
    static func occupiedEventRange(
        row: CaptureAgendaEventRow,
        calendar: Calendar = .current
    ) -> (meetingStart: Date, meetingEnd: Date, occupiedStart: Date, occupiedEnd: Date)? {
        guard let startsAt = row.startsAt,
            let endsAt = row.endsAt,
            let meetingStart = CaptureAgendaClock.date(
                fromNaiveLocal: startsAt,
                calendar: calendar
            ),
            let rawEnd = CaptureAgendaClock.date(fromNaiveLocal: endsAt, calendar: calendar)
        else {
            return nil
        }
        let meetingEnd =
            rawEnd <= meetingStart
            ? calendar.date(byAdding: .day, value: 1, to: rawEnd) ?? rawEnd
            : rawEnd
        var occupiedStart = meetingStart
        if let raw = row.buffer?.startsAt,
            let parsed = CaptureAgendaClock.date(fromNaiveLocal: raw, calendar: calendar)
        {
            occupiedStart = min(parsed, meetingStart)
        }
        var occupiedEnd = meetingEnd
        if let raw = row.buffer?.endsAt,
            let parsed = CaptureAgendaClock.date(fromNaiveLocal: raw, calendar: calendar)
        {
            occupiedEnd = max(parsed, meetingEnd)
        }
        return (meetingStart, meetingEnd, occupiedStart, occupiedEnd)
    }

    /// True while the row's buffer is in progress: now sits in the
    /// lead-in (`occupiedStart <= now < meetingStart`) or the lead-out
    /// (`meetingEnd < now <= occupiedEnd`).
    static func bufferInProgress(
        row: CaptureAgendaEventRow,
        now: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let now, let buffer = row.buffer, !buffer.isEmpty else {
            return false
        }
        guard let range = occupiedEventRange(row: row, calendar: calendar) else {
            return false
        }
        if range.occupiedStart <= now, now < range.meetingStart {
            return true
        }
        if range.meetingEnd < now, now <= range.occupiedEnd {
            return true
        }
        return false
    }

    /// `"holds 11:30 to 13:15"` from the buffer's buffered span. Nil
    /// when the event has no buffer or its buffered clocks are missing.
    static func bufferHoldText(_ buffer: CaptureEventBuffer?) -> String? {
        guard let buffer, !buffer.isEmpty else {
            return nil
        }
        guard let start = CaptureAgendaClock.clockTime(buffer.startsAt),
            let end = CaptureAgendaClock.clockTime(buffer.endsAt)
        else {
            return nil
        }
        return "holds \(start) to \(end)"
    }

    static func makeCalendarRail(
        events: CaptureAgendaEvents,
        entries: [CaptureAgendaPomodoro],
        now: Date?,
        calendar: Calendar = .current
    ) -> CaptureAgendaRailData? {
        guard let now else {
            return nil
        }
        let hour = calendar.component(.hour, from: now)
        var startComponents = calendar.dateComponents([.year, .month, .day], from: now)
        startComponents.hour = hour
        startComponents.minute = 0
        startComponents.second = 0
        guard let domainStart = calendar.date(from: startComponents) else {
            return nil
        }

        func parsedRange(_ startsAt: String?, _ endsAt: String?) -> (Date, Date)? {
            guard let startsAt,
                let endsAt,
                let start = CaptureAgendaClock.date(
                    fromNaiveLocal: startsAt,
                    calendar: calendar
                ),
                let rawEnd = CaptureAgendaClock.date(
                    fromNaiveLocal: endsAt,
                    calendar: calendar
                )
            else {
                return nil
            }
            let end =
                rawEnd <= start
                ? calendar.date(byAdding: .day, value: 1, to: rawEnd) ?? rawEnd
                : rawEnd
            return (start, end)
        }

        let remainingRows = events.rows.filter { $0.phase != .ended }
        let eventRanges = remainingRows.compactMap {
            row -> (CaptureAgendaEventRow, Date, Date, Date, Date)? in
            guard let range = Self.occupiedEventRange(row: row, calendar: calendar) else {
                return nil
            }
            return (
                row, range.meetingStart, range.meetingEnd, range.occupiedStart, range.occupiedEnd
            )
        }.sorted { $0.3 < $1.3 }
        let current = entries.first(where: { $0.role == .current })
        let sessionRange = current.flatMap { parsedRange($0.startsAt, $0.endsAt) }
        var domainEnd = domainStart.addingTimeInterval(180 * 60)
        for (_, _, _, _, occupiedEnd) in eventRanges {
            domainEnd = max(domainEnd, occupiedEnd)
        }
        if let sessionRange {
            domainEnd = max(domainEnd, sessionRange.1)
        }
        let span = max(1, domainEnd.timeIntervalSince(domainStart))
        func position(_ date: Date) -> Double {
            min(1, max(0, date.timeIntervalSince(domainStart) / span))
        }

        let railEvents = eventRanges.map {
            row, meetingStart, meetingEnd, occupiedStart, occupiedEnd in
            let qualifier = (row.qualifier ?? "").lowercased()
            let leadingWing: CaptureAgendaRailWing? =
                occupiedStart < meetingStart
                ? CaptureAgendaRailWing(
                    start: position(occupiedStart),
                    end: position(meetingStart),
                    active: occupiedStart <= now && now < meetingStart
                ) : nil
            let trailingWing: CaptureAgendaRailWing? =
                meetingEnd < occupiedEnd
                ? CaptureAgendaRailWing(
                    start: position(meetingEnd),
                    end: position(occupiedEnd),
                    active: meetingEnd < now && now <= occupiedEnd
                ) : nil
            return CaptureAgendaRailEvent(
                start: position(meetingStart),
                end: position(meetingEnd),
                hue: row.home?.hue,
                offClock: row.offClock,
                maybe: qualifier == "maybe" || qualifier == "free",
                leadingWing: leadingWing,
                trailingWing: trailingWing
            )
        }
        let runningSession = sessionRange.map { start, end in
            CaptureAgendaRailEvent(
                start: position(start),
                end: position(end),
                hue: nil
            )
        }
        var ticks: [CaptureAgendaRailTick] = []
        var tickDate = domainStart
        while tickDate <= domainEnd {
            ticks.append(
                CaptureAgendaRailTick(
                    position: position(tickDate),
                    label: String(format: "%02d", calendar.component(.hour, from: tickDate))
                )
            )
            guard let next = calendar.date(byAdding: .hour, value: 1, to: tickDate) else {
                break
            }
            tickDate = next
        }

        var cursor = max(now, sessionRange?.1 ?? now)
        var firstGap: CaptureAgendaRailGap?
        for (_, _, _, occupiedStart, occupiedEnd) in eventRanges {
            if occupiedEnd <= cursor {
                continue
            }
            if occupiedStart > cursor {
                let minutes = Int(occupiedStart.timeIntervalSince(cursor) / 60)
                if minutes > 0 {
                    firstGap = CaptureAgendaRailGap(
                        start: position(cursor),
                        end: position(occupiedStart),
                        minutes: minutes
                    )
                }
                break
            }
            cursor = max(cursor, occupiedEnd)
        }
        return CaptureAgendaRailData(
            now: position(now),
            ticks: ticks,
            events: railEvents,
            runningSession: runningSession,
            firstGap: firstGap
        )
    }

    /// The focus event: bob's `focus` index when it lands on a row, else
    /// the first remaining row.
    static func calendarFocusEvent(
        events: CaptureAgendaEvents,
        upcoming: [CaptureAgendaEventRow]
    ) -> CaptureAgendaEventRow? {
        if let focus = events.focus,
            events.rows.indices.contains(focus)
        {
            let row = events.rows[focus]
            if row.phase != .ended {
                return row
            }
        }
        return upcoming.first
    }

    /// `"↻ 08:02"`, with the weekday (`"↻ Fri 08:02"`) when the sync
    /// stamp is from another day. Nil when bob reports no stamp.
    static func calendarStampText(syncedAt: String?, date: String, locale: Locale) -> String? {
        guard let syncedAt, let clock = CaptureAgendaClock.clockTime(syncedAt) else {
            return nil
        }
        let stamp = "↻ \(clock)"
        let day = String(syncedAt.prefix(10))
        guard day != date else {
            return stamp
        }
        let parts = day.split(separator: "-")
        guard parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let dayOfMonth = Int(parts[2])
        else {
            return stamp
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let components = DateComponents(year: year, month: month, day: dayOfMonth)
        guard let resolved = calendar.date(from: components) else {
            return stamp
        }
        let weekday = calendar.component(.weekday, from: resolved)
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.indices.contains(weekday - 1) else {
            return stamp
        }
        return "↻ \(symbols[weekday - 1]) \(clock)"
    }

    static func makeCalendarHeader(
        events: CaptureAgendaEvents,
        upcoming: [CaptureAgendaEventRow],
        stamp: String?,
        now: Date?
    ) -> CaptureAgendaRow {
        // No remaining rows (with or without ended ones): the quiet
        // header behind the clear row.
        guard let focus = calendarFocusEvent(events: events, upcoming: upcoming) else {
            let accessory = stamp
            let label = accessory == nil ? "Calendar" : "Calendar, \(accessory ?? "")"
            return CaptureAgendaRow(
                kind: .calendarHeader,
                text: "Calendar",
                depth: 0,
                lineLimit: 1,
                accessoryText: accessory,
                accessibilityLabel: label
            )
        }
        let startClock = CaptureAgendaClock.clockTime(focus.startsAt) ?? ""
        let endClock = CaptureAgendaClock.clockTime(focus.endsAt) ?? ""
        let text: String
        let countdown: String?
        if focus.phase == .running {
            countdown = now.flatMap {
                CaptureAgendaClock.remainingText(endsAt: focus.endsAt, now: $0)
            }
            if let countdown, !endClock.isEmpty {
                text = "\(focus.title) until \(endClock) · \(countdown)"
            } else if !endClock.isEmpty {
                text = "\(focus.title) until \(endClock)"
            } else {
                text = focus.title
            }
        } else {
            countdown = now.flatMap {
                CaptureAgendaClock.countdownUntilText(startsAt: focus.startsAt, now: $0)
            }
            if let countdown, !startClock.isEmpty {
                text = "\(focus.title) at \(startClock) · \(countdown)"
            } else if !startClock.isEmpty {
                text = "\(focus.title) at \(startClock)"
            } else {
                text = focus.title
            }
        }
        let remainingMinutes = upcoming.compactMap(\.durationMinutes).reduce(0, +)
        var accessoryParts = ["\(upcoming.count) left"]
        if remainingMinutes > 0 {
            accessoryParts.append(CaptureAgendaClock.durationText(minutes: remainingMinutes))
        }
        if let stamp {
            accessoryParts.append(stamp)
        }
        let accessory = accessoryParts.joined(separator: " · ")
        return CaptureAgendaRow(
            kind: .calendarHeader,
            text: text,
            depth: 0,
            lineLimit: 1,
            accessoryText: accessory,
            accessibilityLabel: "\(text), \(accessory)"
        )
    }

    /// Trailing countdown for a running or upcoming row. Ended rows
    /// carry their status glyph on the row instead.
    static func calendarCountdown(for row: CaptureAgendaEventRow, now: Date?) -> String? {
        guard let now else {
            return nil
        }
        if row.phase == .running {
            return CaptureAgendaClock.remainingText(endsAt: row.endsAt, now: now)
        }
        return CaptureAgendaClock.countdownUntilText(startsAt: row.startsAt, now: now)
    }

    static func makeCalendarEventRow(
        _ row: CaptureAgendaEventRow,
        countdown: String?,
        startHint: String?,
        now: Date? = nil,
        calendar: Calendar = .current
    ) -> CaptureAgendaRow {
        let timeText =
            CaptureAgendaClock.timeRangeText(startsAt: row.startsAt, endsAt: row.endsAt)
            ?? row.timeRange ?? ""
        let qualifier = (row.qualifier ?? "").lowercased()
        let dimmed = qualifier == "maybe" || qualifier == "free"
        let bufferLabel = row.buffer?.label()
        let bufferActive = Self.bufferInProgress(row: row, now: now, calendar: calendar)
        let data = CaptureAgendaCalendarRowData(
            timeText: timeText,
            hue: row.home?.hue,
            offClock: row.offClock,
            dimmed: dimmed,
            joinURL: row.joinURL,
            countdownText: countdown,
            startHint: startHint,
            bufferLabel: bufferLabel,
            bufferActive: bufferActive
        )
        let spokenRange =
            CaptureAgendaClock.accessibilityRangeText(
                startsAt: row.startsAt,
                endsAt: row.endsAt
            ) ?? timeText
        var labelParts = ["\(row.title), \(spokenRange)"]
        if row.offClock {
            labelParts.append("off-clock")
        }
        if let buffer = row.buffer, let spoken = buffer.spoken() {
            var bufferPart = spoken
            if let holds = Self.bufferHoldText(buffer) {
                bufferPart += ", \(holds)"
            }
            labelParts.append(bufferPart)
        }
        if let countdown {
            labelParts.append(countdown)
        } else if let glyph = row.statusSymbol, !glyph.isEmpty {
            labelParts.append("status \(glyph)")
        }
        if let startHint {
            labelParts.append("hint \(startHint)")
        }
        return CaptureAgendaRow(
            kind: .calendarRow,
            text: row.title,
            depth: 0,
            lineLimit: 1,
            accessoryText: countdown,
            statusGlyph: row.phase == .ended ? row.statusSymbol : nil,
            accessibilityLabel: labelParts.joined(separator: ", "),
            calendar: data
        )
    }

    static func makeCalendarAllDayRow(_ allDay: [CaptureAgendaAllDayContext]) -> CaptureAgendaRow? {
        guard !allDay.isEmpty else {
            return nil
        }
        let text = allDay.map { entry in
            if let qualifier = entry.qualifier, !qualifier.isEmpty {
                return "\(entry.title) (\(qualifier))"
            }
            return entry.title
        }.joined(separator: " · ")
        return CaptureAgendaRow(
            kind: .calendarAllDay,
            text: text,
            depth: 0,
            lineLimit: 2,
            accessibilityLabel: "All day: \(text)"
        )
    }

    /// `"38m free · =7 fits"`: quiet free time before the focus event.
    static func makeCalendarGapRow(_ gap: CaptureAgendaEventGap) -> CaptureAgendaRow {
        let text: String
        if let fits = gap.fits, !fits.isEmpty {
            text = "\(gap.minutes)m free · \(fits) fits"
        } else {
            text = "\(gap.minutes)m free"
        }
        return CaptureAgendaRow(
            kind: .calendarGap,
            text: text,
            depth: 0,
            lineLimit: 1,
            accessibilityLabel: text
        )
    }

    /// `"BOB runs 10m into Standup"`, or `"BOB runs 5m into Lunch's
    /// −30m buffer"` when the overlap sits wholly inside one buffered
    /// side: the running Pomodoro collides with the focus event.
    static func makeCalendarConflictRow(
        _ conflict: CaptureAgendaEventConflict,
        events: CaptureAgendaEvents,
        entries: [CaptureAgendaPomodoro]
    ) -> CaptureAgendaRow? {
        guard events.rows.indices.contains(conflict.event) else {
            return nil
        }
        let row = events.rows[conflict.event]
        let name = entries.first(where: { $0.line == conflict.pomodoroLine })
            .map(displayName) ?? "The running session"
        let text: String
        if let part = conflict.bufferPart,
            let side = row.buffer?.partLabel(part)
        {
            text = "\(name) runs \(conflict.overlapMinutes)m into \(row.title)'s \(side) buffer"
        } else {
            text = "\(name) runs \(conflict.overlapMinutes)m into \(row.title)"
        }
        return CaptureAgendaRow(
            kind: .calendarConflict,
            text: text,
            depth: 0,
            lineLimit: 2,
            accessibilityLabel: text
        )
    }

    static func makeCalendarChipRow(text: String, label: String) -> CaptureAgendaRow {
        CaptureAgendaRow(
            kind: .calendarMore,
            text: text,
            depth: 0,
            lineLimit: 1,
            accessoryText: nil,
            accessibilityLabel: label
        )
    }

    /// Merged header-plus-next line: `"Standup at 13:00 · in 38m ·
    /// then 1:1 13:30 · +2"`.
    static func makeCalendarOneRow(
        header: CaptureAgendaRow,
        upcoming: [CaptureAgendaEventRow],
        focusIndex: Int,
        earlierCount: Int
    ) -> CaptureAgendaRow {
        var text = header.text
        let after = Array(upcoming.dropFirst(focusIndex + 1))
        if let next = after.first {
            let clock = CaptureAgendaClock.clockTime(next.startsAt) ?? ""
            let thenText = clock.isEmpty ? "then \(next.title)" : "then \(next.title) \(clock)"
            text += " · \(thenText)"
            let hidden = max(0, after.count - 1) + earlierCount
            if hidden > 0 {
                text += " · +\(hidden)"
            }
        } else if earlierCount > 0 {
            text += " · +\(earlierCount)"
        }
        return CaptureAgendaRow(
            kind: .calendarHeader,
            text: truncate(text, to: maxStripLength),
            depth: 0,
            lineLimit: CaptureAgendaLayoutMetrics.oneLineLimit,
            accessibilityLabel: text
        )
    }

    // MARK: - MEET event time chips

    /// MEET group items linked to an Event Task show a time chip
    /// instead of the bold span: `"13:00–13:30"`, from the event's
    /// clock times, with the buffer label appended (`"13:00–13:30
    /// −30m +15m"`). Nil for every other item.
    static func eventTimeChip(item: CaptureAgendaItem, entry: CaptureAgendaPomodoro) -> String? {
        guard let event = item.event else {
            return nil
        }
        guard entry.name?.lowercased() == "meet" else {
            return nil
        }
        guard
            let range = CaptureAgendaClock.timeRangeText(
                startsAt: event.startsAt,
                endsAt: event.endsAt
            ) ?? event.timeRange
        else {
            return nil
        }
        if let label = event.buffer?.label() {
            return "\(range) \(label)"
        }
        return range
    }

    /// Drops a leading `"**0930-1000** "` span: the time chip carries
    /// the range instead.
    static func stripLeadingBoldSpan(_ text: String) -> String {
        guard text.hasPrefix("**") else {
            return text
        }
        let rest = text.dropFirst(2)
        guard let close = rest.range(of: "**") else {
            return text
        }
        return rest[close.upperBound...].trimmingCharacters(in: .whitespaces)
    }
}
