import Foundation
import XCTest

@testable import CaptureCore

final class CompletionRowContentTests: XCTestCase {
    func testRouteContextPrefersRouteAsPrimaryAndSurfacesLabelKindStatusAsSecondaryBadges() {
        let candidate = CaptureCompletionCandidate(
            replacement: "today",
            route: "today",
            label: "today.md",
            kind: "inbox",
            status: "active"
        )

        let content = completionRowContent(for: candidate, context: "route", query: "tod")

        XCTAssertEqual(content.category, .route)
        XCTAssertEqual(content.contextLabel, "Destination")
        XCTAssertEqual(content.primaryText, "today")
        XCTAssertEqual(content.secondaryText, "today.md")
        XCTAssertEqual(content.badges, ["inbox", "active"])
        XCTAssertEqual(content.primaryMatchRange, 0..<3)
        XCTAssertEqual(content.accessibilityLabel, "Destination, today, today.md, inbox, active")
    }

    func testRouteContextOmitsSecondaryWhenLabelMatchesPrimary() {
        let candidate = CaptureCompletionCandidate(
            replacement: "today",
            route: "today",
            label: "today",
            kind: "inbox"
        )

        let content = completionRowContent(for: candidate, context: "route", query: "")

        XCTAssertNil(content.secondaryText)
        XCTAssertNil(content.primaryMatchRange)
    }

    func testSectionContextShowsTitleAndHeadingLevelBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "Design",
            title: "Design",
            level: 2
        )

        let content = completionRowContent(for: candidate, context: "section", query: "des")

        XCTAssertEqual(content.category, .section)
        XCTAssertEqual(content.contextLabel, "Section")
        XCTAssertEqual(content.primaryText, "Design")
        XCTAssertEqual(content.badges, ["H2"])
        XCTAssertEqual(content.primaryMatchRange, 0..<3)
    }

    func testTaskSectionContextShowsTitleParentTaskAndItemCountBadges() {
        let candidate = CaptureCompletionCandidate(
            replacement: "requirements",
            title: "REQUIREMENTS",
            blockID: "bar",
            text: "Parent task",
            childCount: 2
        )

        let content = completionRowContent(for: candidate, context: "task_section", query: "req")

        XCTAssertEqual(content.category, .section)
        XCTAssertEqual(content.symbolName, "list.bullet.rectangle")
        XCTAssertEqual(content.contextLabel, "Task Section")
        XCTAssertEqual(content.primaryText, "REQUIREMENTS")
        XCTAssertEqual(content.secondaryText, "Parent task")
        XCTAssertEqual(content.badges, ["^bar", "2 items"])
        XCTAssertEqual(content.primaryMatchRange, 0..<3)
        XCTAssertEqual(content.accessibilityHint, "Nests the capture under this task section.")
        XCTAssertEqual(
            content.accessibilityLabel,
            "Task Section, REQUIREMENTS, Parent task, ^bar, 2 items"
        )
    }

    func testTaskSectionContextEmptySectionUsesEmptyBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "requirements",
            title: "REQUIREMENTS",
            blockID: "bar",
            text: "Parent task",
            childCount: 0
        )

        let content = completionRowContent(for: candidate, context: "task_section", query: "")

        XCTAssertEqual(content.badges, ["^bar", "Empty"])
        XCTAssertNil(content.primaryMatchRange)
    }

    func testTaskSectionContextShowsMultiWordTitle() {
        let candidate = CaptureCompletionCandidate(
            replacement: "future-work",
            title: "FUTURE WORK",
            blockID: "bar",
            text: "Parent task",
            childCount: 1
        )

        let content = completionRowContent(for: candidate, context: "task_section", query: "future")

        XCTAssertEqual(content.primaryText, "FUTURE WORK")
        XCTAssertEqual(content.primaryMatchRange, 0..<6)
        XCTAssertEqual(content.badges, ["^bar", "1 items"])
    }

    func testTaskContextShowsTextSectionStatusAndBlockBadges() {
        let candidate = CaptureCompletionCandidate(
            replacement: "goog-exit",
            blockID: "goog-exit",
            statusSymbol: "x",
            statusName: "Done",
            text: "Ship the release",
            section: "Work"
        )

        let content = completionRowContent(for: candidate, context: "task", query: "")

        XCTAssertEqual(content.category, .blockID)
        XCTAssertEqual(content.symbolName, "link")
        XCTAssertEqual(content.contextLabel, "Parent Task")
        XCTAssertEqual(content.primaryText, "Ship the release")
        XCTAssertEqual(content.secondaryText, "Work")
        XCTAssertEqual(content.badges, ["[x] Done", "^goog-exit"])
    }

    func testTaskContextMissingBlockIDUsesAddIDPresentation() {
        let candidate = CaptureCompletionCandidate(
            replacement: "",
            route: "cash",
            taskRef: "8:missing",
            blockID: nil,
            requiresBlockID: true,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: "Plan the handoff",
            section: "Tasks"
        )

        let content = completionRowContent(for: candidate, context: "task", query: "hand")

        XCTAssertEqual(content.category, .priority)
        XCTAssertEqual(content.symbolName, "link.badge.plus")
        XCTAssertEqual(content.contextLabel, "Parent Task")
        XCTAssertEqual(content.primaryText, "Plan the handoff")
        XCTAssertEqual(content.badges, ["[ ] Todo", "Add ID"])
        XCTAssertEqual(content.primaryMatchRange, 9..<13)
        XCTAssertEqual(content.accessibilityHint, "Adds a block ID, then selects this task.")
    }

    func testTaskParentContextShowsParentTaskLabel() {
        let candidate = CaptureCompletionCandidate(
            replacement: "@sase+deep-fix",
            route: "sase",
            blockID: "deep-fix",
            statusSymbol: "*",
            statusName: "Next",
            text: "Fix deep bug",
            section: "Bugs"
        )

        let content = completionRowContent(for: candidate, context: "task_parent", query: "deep")

        XCTAssertEqual(content.category, .blockID)
        XCTAssertEqual(content.contextLabel, "Parent Task")
        XCTAssertEqual(content.primaryText, "Fix deep bug")
        XCTAssertEqual(content.secondaryText, "Bugs")
        XCTAssertEqual(content.badges, ["[*] Next", "^deep-fix"])
        XCTAssertEqual(content.primaryMatchRange, 4..<8)
    }

    func testRefTaskKindDrawsTheBookSymbolInEveryTaskPicker() {
        let contexts = [
            "active_task", "task_link", "task", "task_parent",
            "task_dependency", "task_complete",
        ]
        for context in contexts {
            let candidate = CaptureCompletionCandidate(
                replacement: "sase:ref-first-essay",
                route: "sase",
                blockID: "ref-first-essay",
                statusSymbol: "*",
                statusName: "Next",
                text: "First Essay",
                taskKind: "ref"
            )

            let content = completionRowContent(for: candidate, context: context, query: "")

            XCTAssertEqual(content.symbolName, "book", "context \(context)")
            XCTAssertEqual(content.primaryText, "First Essay", "context \(context)")
        }
    }

    func testRefTaskKindLeavesNonTaskPickersAlone() {
        let candidate = CaptureCompletionCandidate(
            replacement: "sase",
            route: "sase",
            label: "sase.md",
            kind: "project",
            taskKind: "ref"
        )

        let content = completionRowContent(for: candidate, context: "route", query: "")

        XCTAssertEqual(content.symbolName, "signpost.right")
    }

    func testOrdinaryTasksKeepTheirPickerSymbols() {
        let candidate = CaptureCompletionCandidate(
            replacement: "sase:deep-fix",
            route: "sase",
            blockID: "deep-fix",
            statusSymbol: "*",
            statusName: "Next",
            text: "Fix deep bug"
        )

        XCTAssertEqual(
            completionRowContent(for: candidate, context: "task", query: "").symbolName,
            "link"
        )
        XCTAssertEqual(
            completionRowContent(for: candidate, context: "active_task", query: "").symbolName,
            "bookmark"
        )
    }

    func testTaskKindDecodesAdditivelyFromBobJSON() throws {
        let candidate = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data("""
            {"replacement":"sase:ref-x","route":"sase","block_id":"ref-x",
             "status_symbol":"*","status_name":"Next","text":"X",
             "task_kind":"ref"}
            """.utf8)
        )

        XCTAssertEqual(candidate.taskKind, "ref")
    }

    func testTaskKindDefaultsToNilForOlderBob() throws {
        let candidate = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data("""
            {"replacement":"sase:deep-fix","text":"Fix deep bug"}
            """.utf8)
        )

        XCTAssertNil(candidate.taskKind)
    }

    func testPomodoroNameSelectableRowShowsNameTimeAndCurrentDuplicateBadges() {
        let candidate = CaptureCompletionCandidate(
            replacement: "memory",
            taskRef: "31:1a2b3c4d",
            statusSymbol: " ",
            childCount: 5,
            name: "MEMORY",
            requiresName: false,
            line: 31,
            state: "open",
            timeRange: "1205-1230",
            placeholder: false,
            isCurrent: true,
            matchCount: 2
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_name", query: "mem")

        XCTAssertEqual(content.category, .section)
        XCTAssertEqual(content.symbolName, "timer")
        XCTAssertEqual(content.contextLabel, "Pomodoro")
        XCTAssertEqual(content.primaryText, "MEMORY")
        XCTAssertEqual(content.secondaryText, "1205-1230")
        XCTAssertEqual(content.badges, ["Current", "2 matches", "5 links"])
        XCTAssertEqual(content.primaryMatchRange, 0..<3)
        XCTAssertEqual(content.accessibilityHint, "Inserts this Pomodoro name.")
    }

    func testPomodoroNameNameableRowUsesPriorityCategoryAndNameItBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "",
            taskRef: "38:9f8e7d6c",
            statusSymbol: " ",
            childCount: 0,
            name: nil,
            requiresName: true,
            line: 38,
            state: "open",
            timeRange: nil,
            placeholder: true,
            isCurrent: false,
            matchCount: 1
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_name", query: "")

        XCTAssertEqual(content.category, .priority)
        XCTAssertEqual(content.symbolName, "square.and.pencil")
        XCTAssertEqual(content.contextLabel, "Pomodoro")
        XCTAssertEqual(content.primaryText, "Unnamed Pomodoro")
        XCTAssertEqual(content.secondaryText, "Planned")
        XCTAssertEqual(content.badges, ["Empty", "Name it"])
        XCTAssertEqual(content.accessibilityHint, "Names this Pomodoro, then selects it.")
    }

    func testPomodoroNameUnnamedTimedRowUsesTimeRangeAsPrimary() {
        let candidate = CaptureCompletionCandidate(
            replacement: "",
            taskRef: "12:aaaabbbb",
            childCount: 3,
            name: nil,
            requiresName: true,
            timeRange: "0900-0930",
            placeholder: false,
            matchCount: 1
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_name", query: "")

        XCTAssertEqual(content.primaryText, "0900-0930")
        XCTAssertNil(content.secondaryText)
        XCTAssertEqual(content.badges, ["3 links", "Name it"])
    }

    func testPomodoroNameCreationRowUsesTimerPlusAndCreateAffordance() {
        let candidate = CaptureCompletionCandidate(
            replacement: "future",
            childCount: 0,
            name: "FUTURE",
            requiresName: false,
            placeholder: true,
            createsPomodoro: true
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_name", query: "fut")

        XCTAssertEqual(content.category, .priority)
        XCTAssertEqual(content.symbolName, "timer.badge.plus")
        XCTAssertEqual(content.contextLabel, "Pomodoro")
        XCTAssertEqual(content.primaryText, "FUTURE")
        XCTAssertEqual(content.secondaryText, "New future Pomodoro")
        XCTAssertEqual(content.badges, ["Create"])
        XCTAssertEqual(content.primaryMatchRange, 0..<3)
        XCTAssertEqual(content.accessibilityLabel, "Pomodoro, FUTURE, New future Pomodoro, Create")
        XCTAssertEqual(
            content.accessibilityHint,
            "Creates this named future Pomodoro when the draft is captured."
        )
    }

    func testPomodoroNameNamedRowIgnoresAbsentCreatesPomodoro() {
        let candidate = CaptureCompletionCandidate(
            replacement: "memory",
            taskRef: "31:1a2b3c4d",
            childCount: 5,
            name: "MEMORY",
            requiresName: false,
            timeRange: "1205-1230",
            isCurrent: true,
            matchCount: 2,
            createsPomodoro: false
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_name", query: "mem")

        XCTAssertEqual(content.symbolName, "timer")
        XCTAssertEqual(content.primaryText, "MEMORY")
        XCTAssertEqual(content.secondaryText, "1205-1230")
        XCTAssertEqual(content.badges, ["Current", "2 matches", "5 links"])
        XCTAssertEqual(content.accessibilityHint, "Inserts this Pomodoro name.")
    }

    func testPomodoroStartNameNextUpRowLeadsWithNextAndSingularLink() {
        let candidate = CaptureCompletionCandidate(
            replacement: "bugs",
            taskRef: "7:49ff9cb6",
            statusSymbol: " ",
            childCount: 1,
            name: "BUGS",
            requiresName: false,
            line: 7,
            state: "open",
            timeRange: nil,
            placeholder: true,
            isCurrent: false,
            matchCount: 1,
            createsPomodoro: false,
            nextUp: true
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_start_name", query: "bu")

        XCTAssertEqual(content.category, .pomodoroStart)
        XCTAssertEqual(content.symbolName, "play.circle")
        XCTAssertEqual(content.contextLabel, "Start")
        XCTAssertEqual(content.primaryText, "BUGS")
        XCTAssertEqual(content.secondaryText, "Next up")
        XCTAssertEqual(content.badges, ["Next", "1 link"])
        XCTAssertEqual(content.primaryMatchRange, 0..<2)
        XCTAssertEqual(content.accessibilityHint, "Starts this Pomodoro now.")
    }

    func testPomodoroStartNamePlannedRowUsesPluralLinks() {
        let candidate = CaptureCompletionCandidate(
            replacement: "deep-work",
            taskRef: "9:a1781cce",
            statusSymbol: " ",
            childCount: 2,
            name: "DEEP WORK",
            requiresName: false,
            line: 9,
            state: "open",
            timeRange: nil,
            placeholder: true,
            isCurrent: false,
            matchCount: 1
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_start_name", query: "")

        XCTAssertEqual(content.category, .pomodoroStart)
        XCTAssertEqual(content.symbolName, "play.circle")
        XCTAssertEqual(content.contextLabel, "Start")
        XCTAssertEqual(content.primaryText, "DEEP WORK")
        XCTAssertEqual(content.secondaryText, "Planned")
        XCTAssertEqual(content.badges, ["2 links"])
        XCTAssertNil(content.primaryMatchRange)
        XCTAssertEqual(content.accessibilityHint, "Starts this Pomodoro now.")
    }

    func testPomodoroStartNameNewRowCreatesAndStarts() {
        let candidate = CaptureCompletionCandidate(
            replacement: "rev",
            childCount: 0,
            name: "REV",
            requiresName: false,
            state: "open",
            timeRange: nil,
            placeholder: true,
            isCurrent: false,
            matchCount: 1,
            createsPomodoro: true
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_start_name", query: "rev")

        XCTAssertEqual(content.category, .priority)
        XCTAssertEqual(content.symbolName, "timer.badge.plus")
        XCTAssertEqual(content.contextLabel, "Start")
        XCTAssertEqual(content.primaryText, "REV")
        XCTAssertEqual(content.secondaryText, "New session")
        XCTAssertEqual(content.badges, ["New"])
        XCTAssertEqual(content.primaryMatchRange, 0..<3)
        XCTAssertEqual(
            content.accessibilityHint,
            "Creates this Pomodoro and starts it now."
        )
    }

    func testPomodoroStartNameAgainRowNamesCompletedSessionWithEnDashRange() {
        let candidate = CaptureCompletionCandidate(
            replacement: "plan",
            taskRef: "5:fc7e2072",
            statusSymbol: "x",
            childCount: 1,
            name: "PLAN",
            requiresName: false,
            line: 5,
            state: "completed",
            timeRange: "0830-0855",
            placeholder: false,
            isCurrent: false,
            matchCount: 1,
            createsPomodoro: true
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_start_name", query: "pl")

        XCTAssertEqual(content.category, .pomodoroStart)
        XCTAssertEqual(content.symbolName, "arrow.clockwise.circle")
        XCTAssertEqual(content.contextLabel, "Start")
        XCTAssertEqual(content.primaryText, "PLAN")
        XCTAssertEqual(content.secondaryText, "Last ran 0830–0855")
        XCTAssertEqual(content.badges, ["Again"])
        XCTAssertEqual(content.primaryMatchRange, 0..<2)
        XCTAssertEqual(content.accessibilityHint, "Starts a new PLAN session now.")
    }

    func testPomodoroStartNameItRowKeepsPriorityAndNameItBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "",
            taskRef: "12:5c651ef9",
            statusSymbol: " ",
            childCount: 1,
            name: nil,
            requiresName: true,
            line: 12,
            state: "open",
            timeRange: nil,
            placeholder: true,
            isCurrent: false,
            matchCount: 1,
            nextUp: true
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_start_name", query: "")

        XCTAssertEqual(content.category, .priority)
        XCTAssertEqual(content.symbolName, "square.and.pencil")
        XCTAssertEqual(content.contextLabel, "Start")
        XCTAssertEqual(content.primaryText, "Unnamed Pomodoro")
        XCTAssertEqual(content.secondaryText, "Next up")
        XCTAssertEqual(content.badges, ["1 link", "Name it"])
        XCTAssertEqual(content.accessibilityHint, "Names this Pomodoro, then selects it.")
    }

    func testPomodoroStartNameRunningRowTeachesOverrideRestart() {
        let candidate = CaptureCompletionCandidate(
            replacement: "bugs",
            taskRef: "7:63a70f13",
            statusSymbol: " ",
            childCount: 1,
            name: "BUGS",
            requiresName: false,
            line: 7,
            state: "open",
            timeRange: "0840-0905",
            placeholder: false,
            isCurrent: true,
            matchCount: 1
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_start_name", query: "")

        XCTAssertEqual(content.category, .neutral)
        XCTAssertEqual(content.symbolName, "timer")
        XCTAssertEqual(content.contextLabel, "Start")
        XCTAssertEqual(content.primaryText, "BUGS")
        XCTAssertEqual(content.secondaryText, "Running 0840–0905")
        XCTAssertEqual(content.badges, ["Running"])
        XCTAssertEqual(
            content.accessibilityHint,
            "Already running. Restart it with ==, or close it first with =x."
        )
    }

    func testPomodoroStartNameRunningRowUnderKeepsOverrideTeachesSwap() {
        let candidate = CaptureCompletionCandidate(
            replacement: "capture",
            taskRef: "5:0acd7866",
            statusSymbol: " ",
            childCount: 2,
            name: "CAPTURE",
            requiresName: false,
            line: 5,
            state: "open",
            timeRange: "0920-0945",
            placeholder: false,
            isCurrent: true,
            matchCount: 1
        )
        let override = CaptureCompleteOverride(
            keepsLedger: true,
            running: CaptureCompleteOverrideRunning(
                pomodoroName: "CAPTURE",
                line: 5,
                timeRange: "0920-0945"
            )
        )

        let content = completionRowContent(
            for: candidate,
            context: "pomodoro_start_name",
            query: "",
            override: override
        )

        XCTAssertEqual(content.secondaryText, "Running 0920–0945")
        XCTAssertEqual(content.badges, ["Running"])
        XCTAssertEqual(
            content.accessibilityHint,
            "Already running — == restarts it; pick another Pomodoro to swap in"
        )
    }

    func testPomodoroStartNameRunningRowUnderFreshOverrideRestarts() {
        let candidate = CaptureCompletionCandidate(
            replacement: "capture",
            taskRef: "5:0acd7866",
            statusSymbol: " ",
            childCount: 2,
            name: "CAPTURE",
            requiresName: false,
            line: 5,
            state: "open",
            timeRange: "0920-0945",
            placeholder: false,
            isCurrent: true,
            matchCount: 1
        )
        let override = CaptureCompleteOverride(
            keepsLedger: false,
            running: CaptureCompleteOverrideRunning(
                pomodoroName: "CAPTURE",
                line: 5,
                timeRange: "0920-0945"
            )
        )

        let content = completionRowContent(
            for: candidate,
            context: "pomodoro_start_name",
            query: "",
            override: override
        )

        XCTAssertEqual(content.secondaryText, "Running 0920–0945")
        XCTAssertEqual(content.accessibilityHint, "Restarts it now")
    }

    func testPomodoroStartNameOpenRowUnderKeepsOverrideTakesOverLedger() {
        let candidate = CaptureCompletionCandidate(
            replacement: "bugs",
            taskRef: "9:49ff9cb6",
            statusSymbol: " ",
            childCount: 1,
            name: "BUGS",
            requiresName: false,
            line: 9,
            state: "open",
            timeRange: nil,
            placeholder: true,
            isCurrent: false,
            matchCount: 1,
            nextUp: true
        )
        let override = CaptureCompleteOverride(
            keepsLedger: true,
            running: CaptureCompleteOverrideRunning(
                pomodoroName: "CAPTURE",
                line: 5,
                timeRange: "0920-0945"
            )
        )

        let content = completionRowContent(
            for: candidate,
            context: "pomodoro_start_name",
            query: "bu",
            override: override
        )

        XCTAssertEqual(content.secondaryText, "Takes over 0920–0945")
        XCTAssertEqual(content.badges, ["Next", "1 link"])
        XCTAssertEqual(content.accessibilityHint, "Starts this Pomodoro now.")
    }

    func testPomodoroStartNameOpenRowUnderFreshOverrideKeepsDiscoveryText() {
        let candidate = CaptureCompletionCandidate(
            replacement: "sase",
            taskRef: "8:872a7840",
            statusSymbol: " ",
            childCount: 0,
            name: "SASE",
            requiresName: false,
            line: 8,
            state: "open",
            timeRange: nil,
            placeholder: true,
            isCurrent: false,
            matchCount: 1,
            nextUp: true
        )
        let override = CaptureCompleteOverride(
            keepsLedger: false,
            running: CaptureCompleteOverrideRunning(
                pomodoroName: "CAPTURE",
                line: 5,
                timeRange: "0920-0945"
            )
        )

        let content = completionRowContent(
            for: candidate,
            context: "pomodoro_start_name",
            query: "",
            override: override
        )

        XCTAssertEqual(content.secondaryText, "Next up")
        XCTAssertEqual(content.badges, ["Next", "Empty"])
    }

    func testPomodoroStartNameOpenRowWithoutRunningKeepsDiscoveryText() {
        let candidate = CaptureCompletionCandidate(
            replacement: "sase",
            taskRef: "3:872a7840",
            statusSymbol: " ",
            childCount: 0,
            name: "SASE",
            requiresName: false,
            line: 3,
            state: "open",
            timeRange: nil,
            placeholder: true,
            isCurrent: false,
            matchCount: 1,
            nextUp: true
        )
        let override = CaptureCompleteOverride(keepsLedger: true, running: nil)

        let content = completionRowContent(
            for: candidate,
            context: "pomodoro_start_name",
            query: "",
            override: override
        )

        XCTAssertEqual(content.secondaryText, "Next up")
        XCTAssertEqual(content.accessibilityHint, "Starts this Pomodoro now.")
    }

    func testPomodoroBlockIDContextUsesItsOwnLabel() {
        let candidate = CaptureCompletionCandidate(
            replacement: "goog-exit",
            blockID: "goog-exit",
            text: "Ship the release"
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_block_id", query: "")

        XCTAssertEqual(content.contextLabel, "Pomodoro Task")
    }

    func testProjectTaskBlockIDContextUsesBlockIDLabel() {
        let candidate = CaptureCompletionCandidate(
            replacement: "draft-memo",
            blockID: "draft-memo",
            text: "Draft the memo"
        )

        let content = completionRowContent(
            for: candidate,
            context: "project_task_block_id",
            query: ""
        )

        XCTAssertEqual(content.category, .blockID)
        XCTAssertEqual(content.contextLabel, "Block ID")
    }

    func testActiveTaskQueuedNextRowShowsTaskTextRouteBlockAndPomodoroBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "sase:deep-fix",
            route: "sase",
            blockID: "deep-fix",
            statusSymbol: "*",
            statusName: "Next",
            statusType: "ON_HOLD",
            text: "Fix deep bug",
            section: "Tasks",
            pomodoro: ActiveTaskPomodoro(line: 5, name: "BUGS", isCurrent: false)
        )

        let content = completionRowContent(for: candidate, context: "active_task", query: "dee")

        XCTAssertEqual(content.category, .blockID)
        XCTAssertEqual(content.symbolName, "bookmark")
        XCTAssertEqual(content.contextLabel, "Active Task")
        XCTAssertEqual(content.primaryText, "Fix deep bug")
        XCTAssertEqual(content.primaryMatchRange, 4..<7)
        XCTAssertEqual(content.secondaryText, "sase:deep-fix · Tasks")
        XCTAssertEqual(content.badges, ["BUGS"])
        XCTAssertEqual(
            content.accessibilityLabel,
            "Active Task, Fix deep bug, sase:deep-fix · Tasks, BUGS"
        )
        XCTAssertEqual(
            content.accessibilityHint,
            "Inserts this task's route and block ID."
        )
    }

    func testActiveTaskInProgressRowUsesDistinctGlyphAndTint() {
        let candidate = CaptureCompletionCandidate(
            replacement: "sase:outline",
            route: "sase",
            blockID: "outline",
            statusSymbol: "/",
            statusName: "In Progress",
            statusType: "IN_PROGRESS",
            text: "Outline talk",
            pomodoro: nil
        )

        let content = completionRowContent(for: candidate, context: "active_task", query: "")

        XCTAssertEqual(content.category, .schedule)
        XCTAssertEqual(content.symbolName, "play.circle")
        XCTAssertEqual(content.primaryText, "Outline talk")
        XCTAssertEqual(content.secondaryText, "sase:outline")
        XCTAssertEqual(content.badges, ["Not queued"])
        XCTAssertNil(content.primaryMatchRange)
    }

    func testActiveTaskCurrentPomodoroBadgeNamesNowAndTimeRange() {
        let candidate = CaptureCompletionCandidate(
            replacement: "sase:focus",
            route: "sase",
            blockID: "focus",
            statusSymbol: "/",
            statusName: "In Progress",
            statusType: "IN_PROGRESS",
            text: "Focus work",
            pomodoro: ActiveTaskPomodoro(
                line: 3,
                name: "CODING",
                timeRange: "0900-0930",
                isCurrent: true
            )
        )

        let content = completionRowContent(for: candidate, context: "active_task", query: "")

        XCTAssertEqual(content.badges, ["Now · CODING 0900-0930"])
    }

    func testActiveTaskUnnamedPlaceholderBadgeReadsPlanned() {
        let candidate = CaptureCompletionCandidate(
            replacement: "sase:focus",
            route: "sase",
            blockID: "focus",
            statusSymbol: "*",
            statusName: "Next",
            statusType: "ON_HOLD",
            text: "Focus work",
            pomodoro: ActiveTaskPomodoro(line: 8)
        )

        let content = completionRowContent(for: candidate, context: "active_task", query: "")

        XCTAssertEqual(content.category, .blockID)
        XCTAssertEqual(content.symbolName, "bookmark")
        XCTAssertEqual(content.badges, ["Planned"])
    }

    func testWikilinkNoteContextPrefersAliasAsPrimaryAndFlagsAliasBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "Artificial Intelligence|AI]]",
            path: "Artificial Intelligence.md",
            name: "Artificial Intelligence",
            alias: "AI",
            matchKind: "exact_alias"
        )

        let content = completionRowContent(for: candidate, context: "wikilink_note", query: "AI")

        XCTAssertEqual(content.category, .wikilinkTarget)
        XCTAssertEqual(content.contextLabel, "Note")
        XCTAssertEqual(content.primaryText, "AI")
        XCTAssertEqual(content.secondaryText, "Artificial Intelligence.md")
        XCTAssertEqual(content.badges, ["Alias"])
        XCTAssertEqual(content.primaryMatchRange, 0..<2)
    }

    func testWikilinkNoteContextFallsBackToNameWithoutAlias() {
        let candidate = CaptureCompletionCandidate(
            replacement: "sase",
            path: "sase.md",
            name: "sase",
            matchKind: "exact_stem"
        )

        let content = completionRowContent(for: candidate, context: "wikilink_note", query: "sas")

        XCTAssertEqual(content.primaryText, "sase")
        XCTAssertTrue(content.badges.isEmpty)
        XCTAssertEqual(content.primaryMatchRange, 0..<3)
    }

    func testWikilinkHeadingContextShowsHeadingTextAndLevelBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "Design]]",
            level: 3,
            path: "sase.md",
            name: "sase",
            heading: "Design"
        )

        let content = completionRowContent(for: candidate, context: "wikilink_heading", query: "des")

        XCTAssertEqual(content.category, .wikilinkHeading)
        XCTAssertEqual(content.contextLabel, "Heading")
        XCTAssertEqual(content.primaryText, "Design")
        XCTAssertEqual(content.secondaryText, "sase.md")
        XCTAssertEqual(content.badges, ["H3"])
    }

    func testWikilinkBlockContextShowsBlockIDAndPreviewBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "goog-exit]]",
            blockID: "goog-exit",
            path: "sase.md",
            name: "sase",
            preview: "Paragraph"
        )

        let content = completionRowContent(for: candidate, context: "wikilink_block", query: "")

        XCTAssertEqual(content.category, .wikilinkBlock)
        XCTAssertEqual(content.contextLabel, "Block")
        XCTAssertEqual(content.primaryText, "^goog-exit")
        XCTAssertEqual(content.secondaryText, "sase.md")
        XCTAssertEqual(content.badges, ["Paragraph"])
    }

    func testUnknownContextFallsBackToNeutralCategoryAndReplacementText() {
        let candidate = CaptureCompletionCandidate(replacement: "fallback")

        let content = completionRowContent(for: candidate, context: nil, query: "")

        XCTAssertEqual(content.category, .neutral)
        XCTAssertEqual(content.symbolName, "text.cursor")
        XCTAssertEqual(content.contextLabel, "")
        XCTAssertEqual(content.primaryText, "fallback")
        XCTAssertEqual(content.accessibilityLabel, "fallback")
    }

    func testEmptyQueryProducesNoMatchRange() {
        let candidate = CaptureCompletionCandidate(replacement: "sase", path: "sase.md", name: "sase")

        let content = completionRowContent(for: candidate, context: "wikilink_note", query: "")

        XCTAssertNil(content.primaryMatchRange)
    }

    func testMatchRangeIsCaseInsensitive() {
        XCTAssertEqual(completionMatchRange(in: "Artificial Intelligence", query: "intel"), 11..<16)
        XCTAssertNil(completionMatchRange(in: "Artificial Intelligence", query: "xyz"))
        XCTAssertNil(completionMatchRange(in: "Artificial Intelligence", query: ""))
    }

    func testSpanKindCategoriesCoverExistingCaptureMarkerAndWikilinkKinds() {
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "route"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "task_block_id_route"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_route"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "sub_bullet_route"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "task_toggle_route"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "active_task_route"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "section"), .section)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "sub_bullet_section"), .section)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_name"), .section)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "task_toggle_pomodoro_name"), .section)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "task_block_id"), .blockID)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_block_id"), .blockID)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "project_task_block_id"), .blockID)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "sub_bullet_block_id"), .blockID)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "task_toggle_block_id"), .blockID)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "active_task_block_id"), .blockID)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "schedule"), .schedule)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "priority"), .priority)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "clipboard"), .clipboard)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "wikilink_delimiter"), .wikilinkDelimiter)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "wikilink_target"), .wikilinkTarget)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "wikilink_heading"), .wikilinkHeading)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "wikilink_block_id"), .wikilinkBlock)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "wikilink_alias"), .wikilinkAlias)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "interactive_placeholder"), .interactivePlaceholder)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "task_toggle_explicit_toggle"), .explicitToggle)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "task_toggle_force_next"), .explicitToggle)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "project_note_marker"), .explicitToggle)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "project_task_link_marker"), .explicitToggle)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_start"), .pomodoroStart)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_adjust"), .pomodoroStart)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_shift"), .pomodoroStart)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_close"), .pomodoroStart)
        XCTAssertEqual(
            captureSemanticCategory(forSpanKind: "pomodoro_close_in_progress"),
            .pomodoroCloseInProgress
        )
        XCTAssertEqual(
            captureSemanticCategory(forSpanKind: "pomodoro_close_complete"),
            .pomodoroCloseComplete
        )
        XCTAssertEqual(
            captureSemanticCategory(forSpanKind: "task_complete_sigil"),
            .pomodoroCloseComplete
        )
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "task_complete_note"), .route)
        XCTAssertEqual(
            captureSemanticCategory(forSpanKind: "task_complete_block_id"),
            .blockID
        )
        XCTAssertEqual(
            captureSemanticCategory(forSpanKind: "pomodoro_close_drop"),
            .pomodoroCloseDrop
        )
        XCTAssertEqual(
            captureSemanticCategory(forSpanKind: "pomodoro_close_log_index"),
            .pomodoroCloseLog
        )
        XCTAssertEqual(
            captureSemanticCategory(forSpanKind: "pomodoro_start_drop"),
            .pomodoroStartDrop
        )
        // The retired `#now` span reads as neutral prose, like any
        // unrecognized kind.
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "now_tag"), .neutral)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "unrecognized_future_kind"), .neutral)
    }

    func testNamedStartSpansReadAsTwoTones() {
        // `=3#bugs` colors the `=<X>` start pink and the name purple, with no
        // mapping change: the shared palette already resolves both span kinds.
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_start"), .pomodoroStart)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_name"), .section)
    }

    func testCompletionContextParsesAllWireValuesAndRejectsUnknown() {
        XCTAssertEqual(CaptureCompletionContext(rawContext: "route"), .route)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "section"), .section)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "pomodoro_block_id"), .pomodoroBlockID)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "project_task_block_id"), .projectTaskBlockID)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "pomodoro_name"), .pomodoroName)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "pomodoro_start_name"), .pomodoroStartName)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "task"), .task)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "task_section"), .taskSection)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "active_task"), .activeTask)
        XCTAssertNil(CaptureCompletionContext(rawContext: "now_tag"))
        XCTAssertEqual(CaptureCompletionContext(rawContext: "wikilink_note"), .wikilinkNote)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "wikilink_heading"), .wikilinkHeading)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "wikilink_block"), .wikilinkBlock)
        XCTAssertNil(CaptureCompletionContext(rawContext: "future_context"))
        XCTAssertNil(CaptureCompletionContext(rawContext: nil))
    }

    func testRetiredNowTagContextFallsBackToNeutral() {
        let candidate = CaptureCompletionCandidate(
            replacement: "#now",
            label: "#now",
            kind: "tag",
            text: "This week's bet"
        )
        let content = completionRowContent(for: candidate, context: "now_tag", query: "")

        XCTAssertEqual(content.category, .neutral)
        XCTAssertEqual(content.symbolName, "text.cursor")
        XCTAssertEqual(content.primaryText, "#now")
        XCTAssertEqual(content.badges, [])
    }

    func testActiveTaskRowCarriesNoNowBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "sase:ready",
            route: "sase",
            blockID: "ready",
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: "Ready task"
        )
        let content = completionRowContent(for: candidate, context: "active_task", query: "")

        XCTAssertEqual(content.badges, ["Not queued"])
    }

    func testActiveTaskWithoutNowOmitsNowBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "sase:plain",
            route: "sase",
            blockID: "plain",
            statusSymbol: "*",
            statusName: "Next",
            statusType: "ON_HOLD",
            text: "Plain task"
        )
        let content = completionRowContent(for: candidate, context: "active_task", query: "")

        XCTAssertFalse(content.badges.contains("NOW"))
    }

    func testMiddleTruncatedPathReturnsInputUnchangedWhenWithinBudget() {
        XCTAssertEqual(middleTruncatedPath("sase.md", maxLength: 40), "sase.md")
        XCTAssertEqual(middleTruncatedPath("Projects/Alpha.md", maxLength: 18), "Projects/Alpha.md")
    }

    func testMiddleTruncatedPathPreservesBasenameAndCollapsesDirectory() {
        let path = "Projects/Deeply/Nested/Structure/For/Testing/Truncation/Alpha.md"
        let result = middleTruncatedPath(path, maxLength: 30)

        XCTAssertEqual(result.count, 30)
        XCTAssertTrue(result.hasSuffix("/Alpha.md"))
        XCTAssertTrue(result.contains("\u{2026}"))
    }

    func testMiddleTruncatedPathCollapsesDirectoryEntirelyWhenBudgetIsTiny() {
        let path = "Projects/Deeply/Nested/Structure/Alpha.md"
        let result = middleTruncatedPath(path, maxLength: 10)

        XCTAssertEqual(result, "\u{2026}/Alpha.md")
        XCTAssertLessThanOrEqual(result.count, 10)
    }

    func testMiddleTruncatedPathShowsOneDirectoryCharacterWhenBudgetAllowsExactlyOne() {
        let path = "Projects/Deeply/Nested/Structure/Alpha.md"
        let result = middleTruncatedPath(path, maxLength: 11)

        XCTAssertEqual(result, "P\u{2026}/Alpha.md")
        XCTAssertEqual(result.count, 11)
    }

    func testMiddleTruncatedPathTruncatesBasenameItselfWhenLongerThanBudget() {
        let path = "Projects/an-extremely-long-note-name-that-cannot-fit.md"
        let result = middleTruncatedPath(path, maxLength: 20)

        XCTAssertEqual(result.count, 20)
        XCTAssertFalse(result.contains("/"))
        XCTAssertTrue(result.contains("\u{2026}"))
    }

    func testMiddleTruncatedPathWithoutSlashFallsBackToPlainMiddleTruncation() {
        let result = middleTruncatedPath("abcdefghijklmnopqrstuvwxyz", maxLength: 10)

        XCTAssertEqual(result.count, 10)
        XCTAssertTrue(result.hasPrefix("abcd"))
        XCTAssertTrue(result.hasSuffix("wxyz") || result.hasSuffix("vwxyz"))
    }

    func testMiddleTruncatedPathHandlesDegenerateTinyBudget() {
        XCTAssertEqual(middleTruncatedPath("abcdefghij", maxLength: 1), "\u{2026}")
        XCTAssertEqual(middleTruncatedPath("abcdefghij", maxLength: 0), "abcdefghij")
    }

    func testOverrideCompleteFixtureDecodesKeepsLedgerAndRunning() throws {
        let response = try decodeCompletionFixture("pomodoro-start-override-complete.json")

        XCTAssertEqual(response.context, "pomodoro_start_name")
        let override = try XCTUnwrap(response.overrideInfo)
        XCTAssertTrue(override.keepsLedger)
        let running = try XCTUnwrap(override.running)
        XCTAssertEqual(running.pomodoroName, "CAPTURE")
        XCTAssertEqual(running.line, 5)
        XCTAssertEqual(running.timeRange, "0920-0945")
        XCTAssertEqual(response.candidates.count, 4)
    }

    func testOverrideCompleteFreshFixtureDecodesFreshLedger() throws {
        let response = try decodeCompletionFixture("pomodoro-start-override-complete-fresh.json")

        let override = try XCTUnwrap(response.overrideInfo)
        XCTAssertFalse(override.keepsLedger)
        XCTAssertEqual(override.running?.pomodoroName, "CAPTURE")
        XCTAssertEqual(override.running?.timeRange, "0920-0945")
    }

    func testOverrideCompleteIdleFixtureOmitsRunning() throws {
        let response = try decodeCompletionFixture("pomodoro-start-override-complete-idle.json")

        let override = try XCTUnwrap(response.overrideInfo)
        XCTAssertTrue(override.keepsLedger)
        XCTAssertNil(override.running)
        XCTAssertEqual(response.candidates.count, 2)
    }

    func testPlainStartNameFixtureCarriesNoOverride() throws {
        let response = try decodeCompletionFixture("pomodoro-start-named-complete-running.json")

        XCTAssertEqual(response.context, "pomodoro_start_name")
        XCTAssertNil(response.overrideInfo)
    }

    private func decodeCompletionFixture(_ name: String) throws -> CaptureCompletionResponse {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
        return try JSONDecoder().decode(CaptureCompletionResponse.self, from: Data(text.utf8))
    }
}
