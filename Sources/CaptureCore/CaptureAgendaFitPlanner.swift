import Foundation

/// Fold level of one task: full detail, logs folded into chips, or a
/// single line with a `+N lines` chip.
public enum CaptureAgendaTaskState: Equatable, Sendable {
    case full
    case noLogs
    case oneLine
}

/// Fold level of one Pomodoro group. Now, Open, and Next groups fold
/// `full → noLogs → oneLineTasks`; Later groups continue
/// `→ oneRow → inStrip`.
public enum CaptureAgendaGroupState: Equatable, Sendable {
    case full
    case noLogs
    case oneLineTasks
    case oneRow
    case inStrip
}

/// The planner's output: everything the agenda view renders, in order,
/// with no folding logic left for the view.
public struct CaptureAgendaPlan: Equatable, Sendable {
    /// Render rows in order: title, saved budget, warning, Now group
    /// rows, the Calendar band, Next/Later group rows, strip.
    public let rows: [CaptureAgendaRow]
    public let groupStates: [CaptureAgendaUnitID: CaptureAgendaGroupState]
    public let taskStates: [CaptureAgendaUnitID: CaptureAgendaTaskState]
    /// The Calendar band's fold. Nil when the snapshot carries no
    /// events: the band stays hidden and never folds.
    public let calendarState: CaptureAgendaCalendarState?
    public let stripGroupIDs: [CaptureAgendaUnitID]
    public let totalHeight: Double
    public let overflows: Bool
    /// Content rows hidden relative to the all-full rendering; drives
    /// the `N more` cue when `overflows` is set.
    public let hiddenCount: Int
    public let budget: Double

    public init(
        rows: [CaptureAgendaRow],
        groupStates: [CaptureAgendaUnitID: CaptureAgendaGroupState],
        taskStates: [CaptureAgendaUnitID: CaptureAgendaTaskState],
        calendarState: CaptureAgendaCalendarState? = nil,
        stripGroupIDs: [CaptureAgendaUnitID],
        totalHeight: Double,
        overflows: Bool,
        hiddenCount: Int,
        budget: Double
    ) {
        self.rows = rows
        self.groupStates = groupStates
        self.taskStates = taskStates
        self.calendarState = calendarState
        self.stripGroupIDs = stripGroupIDs
        self.totalHeight = totalHeight
        self.overflows = overflows
        self.hiddenCount = hiddenCount
        self.budget = budget
    }
}

/// Pure focus-gradient fit planner: detail fades with distance in time.
/// The ladder stops at the first step whose total height fits the
/// budget. Each step folds one group, farthest group first; groups with
/// nothing to fold are skipped.
///
/// 1. Everything `full`.
/// 2. `noLogs`: Later groups (last to first), then Next, then Now/Open.
/// 3. `oneLineTasks`: Later groups (last to first).
/// 4. `oneRow`: Later groups (last to first).
/// 5. `inStrip`: Later groups (last to first), budgeted at the
///    rendered strip's measured height, with the full-strip upper
///    bound as the unmeasured fallback.
/// 6. `oneLineTasks`: Next, then Now/Open (last to first).
/// 7. Overflow: the most-folded plan is marked `overflows` and the view
///    scrolls with a bottom fade and an `N more` cue.
///
/// The Calendar band folds alongside the groups: `full → compact`
/// after Later groups reach `oneRow` and before they go into the
/// strip, then `compact → oneRow` after Next goes `oneLineTasks` and
/// before Now does. It never folds away while rows remain.
///
/// Same inputs always produce the same plan; planning is O(rows)
/// arithmetic per step.
public enum CaptureAgendaFitPlanner {
    public static func plan(
        presentation: CaptureAgendaPresentation,
        heights: [CaptureAgendaRowKey: Double],
        budget: Double,
        expanded: Set<CaptureAgendaUnitID> = []
    ) -> CaptureAgendaPlan {
        let groups = presentation.groups
        var states: [CaptureAgendaUnitID: CaptureAgendaGroupState] = [:]
        for group in groups {
            states[group.id] = .full
        }
        var calendarState: CaptureAgendaCalendarState? =
            presentation.calendar == nil ? nil : .full
        let fullContentRows = contentRowCount(
            presentation: presentation,
            states: states,
            calendarState: calendarState,
            expanded: expanded
        )
        var current = render(
            presentation: presentation,
            states: states,
            calendarState: calendarState,
            heights: heights,
            expanded: expanded
        )
        if current.totalHeight <= budget {
            return finish(
                render: current,
                states: states,
                calendarState: calendarState,
                budget: budget,
                fullContentRows: fullContentRows,
                overflows: false
            )
        }
        for step in ladder(groups: groups, hasCalendar: presentation.calendar != nil) {
            switch step {
            case .group(let groupIndex, let target):
                guard let next = applyGroup(
                    groupIndex: groupIndex,
                    target: target,
                    groups: groups,
                    states: states,
                    expanded: expanded
                ) else {
                    continue
                }
                states = next
            case .calendar(let target):
                guard let next = applyCalendar(
                    target: target,
                    calendar: presentation.calendar,
                    calendarState: calendarState,
                    expanded: expanded
                ) else {
                    continue
                }
                calendarState = next
            }
            current = render(
                presentation: presentation,
                states: states,
                calendarState: calendarState,
                heights: heights,
                expanded: expanded
            )
            if current.totalHeight <= budget {
                return finish(
                    render: current,
                    states: states,
                    calendarState: calendarState,
                    budget: budget,
                    fullContentRows: fullContentRows,
                    overflows: false
                )
            }
        }
        return finish(
            render: current,
            states: states,
            calendarState: calendarState,
            budget: budget,
            fullContentRows: fullContentRows,
            overflows: current.totalHeight > budget
        )
    }

    // MARK: - Ladder

    enum Step: Equatable {
        case group(groupIndex: Int, target: CaptureAgendaGroupState)
        case calendar(CaptureAgendaCalendarState)
    }

    /// The fold sequence after the all-full candidate. The Calendar
    /// band folds `full → compact` after Later groups reach `oneRow`
    /// and before they go into the strip, then `compact → oneRow`
    /// after Next groups go `oneLineTasks` and before Now does. The
    /// band never folds away while rows remain: there is no strip
    /// state for it.
    static func ladder(groups: [CaptureAgendaGroup], hasCalendar: Bool) -> [Step] {
        var steps: [Step] = []
        let later = groups.indices.filter { groups[$0].role == .later }
        let next = groups.indices.filter { groups[$0].role == .next }
        let nowOpen = groups.indices.filter {
            groups[$0].role == .current || groups[$0].role == .open
        }
        for index in groups.indices.reversed() {
            steps.append(.group(groupIndex: index, target: .noLogs))
        }
        for index in later.reversed() {
            steps.append(.group(groupIndex: index, target: .oneLineTasks))
        }
        for index in later.reversed() {
            steps.append(.group(groupIndex: index, target: .oneRow))
        }
        if hasCalendar {
            steps.append(.calendar(.compact))
        }
        for index in later.reversed() {
            steps.append(.group(groupIndex: index, target: .inStrip))
        }
        for index in next {
            steps.append(.group(groupIndex: index, target: .oneLineTasks))
        }
        if hasCalendar {
            steps.append(.calendar(.oneRow))
        }
        for index in nowOpen.reversed() {
            steps.append(.group(groupIndex: index, target: .oneLineTasks))
        }
        return steps
    }

    /// Applies one group ladder step, or nil when the step is skipped:
    /// the group is pinned by expansion, a pinned task blocks the
    /// collapse, a taskless group would lose its `No linked tasks`
    /// line, or the rows would not change.
    static func applyGroup(
        groupIndex: Int,
        target: CaptureAgendaGroupState,
        groups: [CaptureAgendaGroup],
        states: [CaptureAgendaUnitID: CaptureAgendaGroupState],
        expanded: Set<CaptureAgendaUnitID>
    ) -> [CaptureAgendaUnitID: CaptureAgendaGroupState]? {
        let group = groups[groupIndex]
        guard states[group.id] != target else {
            return nil
        }
        guard !expanded.contains(group.id) else {
            return nil
        }
        let hasPinnedTask = group.tasks.contains { expanded.contains($0.id) }
        switch target {
        case .oneRow, .inStrip:
            guard !group.tasks.isEmpty, !hasPinnedTask else {
                return nil
            }
        case .noLogs, .oneLineTasks, .full:
            break
        }
        if target == .inStrip, expanded.contains(.strip) {
            return nil
        }
        var next = states
        next[group.id] = target
        let before = groupRows(group: group, state: states[group.id] ?? .full, expanded: expanded)
        let after = groupRows(group: group, state: target, expanded: expanded)
        guard before.rows != after.rows else {
            return nil
        }
        return next
    }

    /// Applies one Calendar band ladder step, or nil when the step is
    /// skipped: there is no band, `.calendar` pins it at full, or the
    /// rows would not change.
    static func applyCalendar(
        target: CaptureAgendaCalendarState,
        calendar: CaptureAgendaCalendar?,
        calendarState: CaptureAgendaCalendarState?,
        expanded: Set<CaptureAgendaUnitID>
    ) -> CaptureAgendaCalendarState? {
        guard let calendar else {
            return nil
        }
        guard calendarState != target else {
            return nil
        }
        guard !expanded.contains(.calendar) else {
            return nil
        }
        let before = calendarRows(
            calendar: calendar,
            state: calendarState ?? .full,
            expanded: expanded
        )
        let after = calendarRows(calendar: calendar, state: target, expanded: expanded)
        guard before != after else {
            return nil
        }
        return target
    }

    /// Visible rows for the band at one fold level. Ended rows join
    /// the `full` fold only while `.calendarEarlier` is expanded.
    static func calendarRows(
        calendar: CaptureAgendaCalendar,
        state: CaptureAgendaCalendarState,
        expanded: Set<CaptureAgendaUnitID>
    ) -> [CaptureAgendaRow] {
        switch state {
        case .full:
            return calendar.fullRows(showEnded: expanded.contains(.calendarEarlier))
        case .compact:
            return calendar.compactRows()
        case .oneRow:
            return [calendar.oneRowRow]
        }
    }

    // MARK: - Rendering

    struct GroupRender: Equatable {
        let rows: [CaptureAgendaRow]
        let taskStates: [CaptureAgendaUnitID: CaptureAgendaTaskState]
    }

    struct FullRender: Equatable {
        let rows: [CaptureAgendaRow]
        let groupStates: [CaptureAgendaUnitID: CaptureAgendaGroupState]
        let taskStates: [CaptureAgendaUnitID: CaptureAgendaTaskState]
        let calendarState: CaptureAgendaCalendarState?
        let stripGroupIDs: [CaptureAgendaUnitID]
        let totalHeight: Double
    }

    /// Visible rows for one group at one fold level. Expanded tasks stay
    /// at full inside the list states; collapse states still hide them.
    static func groupRows(
        group: CaptureAgendaGroup,
        state: CaptureAgendaGroupState,
        expanded: Set<CaptureAgendaUnitID>
    ) -> GroupRender {
        switch state {
        case .full:
            return GroupRender(
                rows: listRows(group: group, foldTasks: false, expanded: expanded),
                taskStates: taskStates(group: group, level: .full)
            )
        case .noLogs:
            return GroupRender(
                rows: listRows(group: group, foldTasks: true, expanded: expanded),
                taskStates: taskStates(group: group, level: .noLogs, expanded: expanded)
            )
        case .oneLineTasks:
            var rows = [headerWithNotesChip(group: group)]
            for task in group.tasks {
                if expanded.contains(task.id) {
                    rows += task.fullRows
                } else {
                    rows.append(task.oneLineRow)
                }
            }
            rows += tailRows(group: group)
            return GroupRender(rows: rows, taskStates: taskStates(
                group: group,
                level: .oneLine,
                expanded: expanded
            ))
        case .oneRow:
            return GroupRender(
                rows: [group.oneRowRow],
                taskStates: taskStates(group: group, level: .oneLine)
            )
        case .inStrip:
            return GroupRender(
                rows: [],
                taskStates: taskStates(group: group, level: .oneLine)
            )
        }
    }

    /// Header plus session notes (full) or the header with a notes chip
    /// (folded), then every task's rows, then the retired/empty tail.
    static func listRows(
        group: CaptureAgendaGroup,
        foldTasks: Bool,
        expanded: Set<CaptureAgendaUnitID>
    ) -> [CaptureAgendaRow] {
        var rows = [group.headerRow]
        rows += group.sessionNoteRows
        for task in group.tasks {
            if foldTasks, !expanded.contains(task.id) {
                rows += task.noLogsRows
            } else {
                rows += task.fullRows
            }
        }
        rows += tailRows(group: group)
        return rows
    }

    static func tailRows(group: CaptureAgendaGroup) -> [CaptureAgendaRow] {
        var rows: [CaptureAgendaRow] = []
        if let retired = group.retiredRow {
            rows.append(retired)
        }
        if let empty = group.emptyRow {
            rows.append(empty)
        }
        return rows
    }

    static func headerWithNotesChip(group: CaptureAgendaGroup) -> CaptureAgendaRow {
        guard let chip = group.sessionNotesChip else {
            return group.headerRow
        }
        let base = group.headerRow
        return CaptureAgendaRow(
            kind: base.kind,
            text: base.text,
            depth: base.depth,
            lineLimit: base.lineLimit,
            numberBadge: base.numberBadge,
            accessoryText: base.accessoryText,
            statusGlyph: base.statusGlyph,
            accessibilityLabel: base.accessibilityLabel,
            accessoryAccessibilityLabel: base.accessoryAccessibilityLabel,
            notesChip: chip,
            planBudget: base.planBudget,
            nameIsDerived: base.nameIsDerived,
            homeChip: base.homeChip,
            homeHue: base.homeHue,
            homeIsForecast: base.homeIsForecast
        )
    }

    static func taskStates(
        group: CaptureAgendaGroup,
        level: CaptureAgendaTaskState,
        expanded: Set<CaptureAgendaUnitID> = []
    ) -> [CaptureAgendaUnitID: CaptureAgendaTaskState] {
        var result: [CaptureAgendaUnitID: CaptureAgendaTaskState] = [:]
        for task in group.tasks {
            if expanded.contains(task.id), level != .full {
                result[task.id] = .full
            } else {
                result[task.id] = level
            }
        }
        return result
    }

    static func render(
        presentation: CaptureAgendaPresentation,
        states: [CaptureAgendaUnitID: CaptureAgendaGroupState],
        calendarState: CaptureAgendaCalendarState?,
        heights: [CaptureAgendaRowKey: Double],
        expanded: Set<CaptureAgendaUnitID>
    ) -> FullRender {
        func height(_ row: CaptureAgendaRow) -> Double {
            heights[row.key] ?? CaptureAgendaLayoutMetrics.defaultRowHeight
        }
        var rows = [presentation.titleRow]
        if let planBudget = presentation.planBudgetRow {
            rows.append(planBudget)
        }
        if let warning = presentation.warningRow {
            rows.append(warning)
        }
        if let stateRow = presentation.stateRow {
            rows.append(stateRow)
        }
        var groupStates: [CaptureAgendaUnitID: CaptureAgendaGroupState] = [:]
        var taskStates: [CaptureAgendaUnitID: CaptureAgendaTaskState] = [:]
        var stripIDs: [CaptureAgendaUnitID] = []
        var total = height(presentation.titleRow)
        if let planBudget = presentation.planBudgetRow {
            total += height(planBudget)
        }
        if let warning = presentation.warningRow {
            total += height(warning)
        }
        if let stateRow = presentation.stateRow {
            total += height(stateRow)
        }
        var visibleBlocks = 0
        var stripNames: [String] = []
        func appendBlock(_ newRows: [CaptureAgendaRow], insets: Double) {
            rows += newRows
            visibleBlocks += 1
            var block = insets
            for row in newRows {
                block += height(row)
            }
            total += block
        }
        // The band sits after the Now groups (current, open) and
        // before the Next/Later ones; with nothing running it follows
        // the title rows directly.
        let split = presentation.groups.firstIndex {
            $0.role != .current && $0.role != .open
        } ?? presentation.groups.count
        for offset in 0 ... presentation.groups.count {
            if offset == split, let calendar = presentation.calendar {
                let rendered = calendarRows(
                    calendar: calendar,
                    state: calendarState ?? .full,
                    expanded: expanded
                )
                if !rendered.isEmpty {
                    appendBlock(
                        rendered,
                        insets: CaptureAgendaLayoutMetrics.calendarVerticalInsets
                    )
                }
            }
            guard offset < presentation.groups.count else {
                break
            }
            let group = presentation.groups[offset]
            let state = states[group.id] ?? .full
            groupStates[group.id] = state
            // An expanded strip shows its members as one-row groups
            // instead of folding them into the strip.
            let effective = state == .inStrip && expanded.contains(.strip) ? .oneRow : state
            let rendered = groupRows(group: group, state: effective, expanded: expanded)
            for (id, level) in rendered.taskStates {
                taskStates[id] = level
            }
            if effective == .inStrip {
                stripIDs.append(group.id)
                stripNames.append(group.stripName)
                continue
            }
            // Measured row heights already carry their bottom gaps
            // (inter-row gaps live inside the row views), so the block
            // is exactly the role insets plus the row heights. This
            // matches the plan's height model and what the group view
            // lays out; see CaptureAgendaHeightConsistencyTests.
            appendBlock(
                rendered.rows,
                insets: CaptureAgendaLayoutMetrics.groupVerticalInsets(role: group.role)
            )
        }
        if visibleBlocks > 1 {
            let gaps = Double(visibleBlocks - 1)
            total += gaps * CaptureAgendaLayoutMetrics.groupSpacing
        }
        if !stripIDs.isEmpty {
            let stripRow = CaptureAgendaPresentation.makeStripRow(names: stripNames)
            rows.append(stripRow)
            // Budget the strip the view renders (a folded subset of the
            // Later names), falling back to the full-strip upper bound
            // while its variant is still unmeasured mid-fixpoint.
            total += heights[stripRow.key]
                ?? heights[presentation.stripFullRow.key]
                ?? CaptureAgendaLayoutMetrics.defaultRowHeight
        }
        return FullRender(
            rows: rows,
            groupStates: groupStates,
            taskStates: taskStates,
            calendarState: calendarState,
            stripGroupIDs: stripIDs,
            totalHeight: total
        )
    }

    static func contentRowCount(
        presentation: CaptureAgendaPresentation,
        states: [CaptureAgendaUnitID: CaptureAgendaGroupState],
        calendarState: CaptureAgendaCalendarState?,
        expanded: Set<CaptureAgendaUnitID>
    ) -> Int {
        var count = 0
        for group in presentation.groups {
            let state = states[group.id] ?? .full
            count += groupRows(group: group, state: state, expanded: expanded).rows.count
        }
        if let calendar = presentation.calendar {
            count += calendarRows(
                calendar: calendar,
                state: calendarState ?? .full,
                expanded: expanded
            ).count
        }
        return count
    }

    static func finish(
        render: FullRender,
        states: [CaptureAgendaUnitID: CaptureAgendaGroupState],
        calendarState: CaptureAgendaCalendarState?,
        budget: Double,
        fullContentRows: Int,
        overflows: Bool
    ) -> CaptureAgendaPlan {
        var shown = 0
        for row in render.rows {
            switch row.kind {
            case .title, .planBudget, .multiOpenWarning, .stateLine, .strip:
                break
            case .groupHeader, .sessionNote, .taskHeadline, .ledgerNote, .childLine, .logHeader,
                 .logEntry, .warning, .duplicate, .struck, .retired, .emptyGroup, .truncation,
                 .groupOneRow, .calendarHeader, .calendarRail, .calendarAllDay, .calendarRow,
                 .calendarGap, .calendarConflict, .calendarMore, .calendarClear:
                shown += 1
            }
        }
        return CaptureAgendaPlan(
            rows: render.rows,
            groupStates: states,
            taskStates: render.taskStates,
            calendarState: calendarState,
            stripGroupIDs: render.stripGroupIDs,
            totalHeight: render.totalHeight,
            overflows: overflows,
            hiddenCount: max(0, fullContentRows - shown),
            budget: budget
        )
    }
}
