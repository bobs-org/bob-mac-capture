import Foundation
import XCTest

@testable import CaptureCore

final class CaptureMoveChoiceTests: XCTestCase {
    func testCaptureSuccessDecodesBobMoveChoiceSlotAndRows() throws {
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(successJSON.utf8)
        )
        guard case .success(let success) = response else {
            return XCTFail("Expected capture success")
        }

        let moveChoice = try XCTUnwrap(success.moveChoice)
        XCTAssertTrue(moveChoice.supported)
        XCTAssertEqual(moveChoice.slots.count, 1)
        let slot = try XCTUnwrap(moveChoice.slots.first)
        XCTAssertEqual(slot.item, 1)
        XCTAssertEqual(slot.itemLine, 4)
        XCTAssertEqual(slot.draftRange, [112, 114])
        XCTAssertEqual(slot.parent, "cash.md")
        XCTAssertEqual(slot.destination, "cash_goog_exit.md")
        XCTAssertEqual(slot.pomodoroName, "ADMIN")
        XCTAssertEqual(slot.openCount, 4)
        XCTAssertEqual(slot.copy?.title, "Move into cash_goog_exit.md")
        XCTAssertEqual(slot.copy?.slot, "Lands between Pay and Book, in cash.md order")

        let first = try XCTUnwrap(slot.rows.first)
        XCTAssertEqual(first.key, "cash.md#^call-ms")
        XCTAssertEqual(first.statusSymbol, " ")
        XCTAssertEqual(first.pomodoro?.name, "WORK")
        XCTAssertEqual(first.choices.map(\.sigil), ["^", ":"])
        XCTAssertTrue(first.choices[1].addsLink)
        XCTAssertNil(first.locked)

        let locked = try XCTUnwrap(slot.rows.first(where: { $0.key == "cash.md#^pay-cc" }))
        XCTAssertEqual(locked.locked?.sigil, "^")
        XCTAssertEqual(locked.locked?.itemLine, 3)
        XCTAssertTrue(locked.choices.isEmpty)

        let idless = try XCTUnwrap(slot.rows.first(where: { $0.key == "cash.md@1a2b3c4d" }))
        XCTAssertNil(idless.blockID)
        XCTAssertEqual(idless.mint, "renew-the-passport")
        XCTAssertEqual(
            CaptureMoveChoicePresentation.rowIdentity(for: idless),
            "⊕ ^renew-the-passport"
        )
    }

    func testCaptureRefusalDecodesMoveChoiceAndOldBobOmitsIt() throws {
        let refusal = try JSONDecoder().decode(
            CaptureCommandFailure.self,
            from: Data(
                #"{"ok":false,"error":"answer move choice","code":"move_choice_required","move_choice":{"supported":true,"slots":[]}}"#
                    .utf8
            )
        )
        XCTAssertEqual(refusal.code, "move_choice_required")
        XCTAssertEqual(refusal.moveChoice, CaptureMoveChoice(supported: true))

        let oldBob = try JSONDecoder().decode(
            CaptureCommandFailure.self,
            from: Data(#"{"ok":false,"error":"old Bob"}"#.utf8)
        )
        XCTAssertNil(oldBob.moveChoice)
    }

    func testMalformedMoveChoiceDegradesWithoutFailingCapture() throws {
        let malformed = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(
                """
                {"ok":true,"dry_run":true,"routed":true,"route_label":"cash.md",
                 "relative_target":"cash.md","target":"/tmp/cash.md","text":"t",
                 "task_line":"- [ ] #task t","kind":"task","created":"2026-11-04",
                 "placement":"inserted","move_choice":"broken"}
                """.utf8
            )
        )
        guard case .success(let success) = malformed else {
            return XCTFail("Expected malformed additive data to preserve capture success")
        }
        XCTAssertNil(success.moveChoice)

        let partial = try JSONDecoder().decode(
            CaptureMoveChoice.self,
            from: Data(
                #"{"supported":true,"slots":[{"item":"bad","rows":[{"key":42},{"key":"cash.md#^ok","n":1,"text":"Good","choices":[{"sigil":"^","consequence":"Moves in","adds_link":false}]}]}]}"#
                    .utf8
            )
        )
        XCTAssertTrue(partial.supported)
        XCTAssertEqual(partial.slots.count, 1)
        XCTAssertEqual(partial.slots[0].item, 0)
        XCTAssertEqual(partial.slots[0].rows.count, 2)
        XCTAssertEqual(partial.slots[0].rows[0].key, "")
        XCTAssertEqual(partial.slots[0].rows[1].key, "cash.md#^ok")
    }

    func testLeaveIsDefaultAndHighlightNeverSelects() {
        var state = CaptureMoveChoiceState(slot: slot())

        XCTAssertEqual(state.currentRow?.key, "cash.md#^first")
        XCTAssertNil(state.answer(for: tryUnwrappedRow(state, key: "cash.md#^first")))
        XCTAssertEqual(state.counterText, "No tasks marked")
        XCTAssertFalse(state.canConfirm)
        XCTAssertEqual(
            state.consequence(for: tryUnwrappedRow(state, key: "cash.md#^first")),
            "Stays in cash.md")

        state.moveHighlight(by: 1)
        XCTAssertEqual(state.currentRow?.key, "cash.md#^locked")
        XCTAssertEqual(state.selectedCount, 0)
    }

    func testAnswersUseBobChoicesAndAdvancePastLockedRows() {
        var state = CaptureMoveChoiceState(slot: slot())

        XCTAssertTrue(state.answerCurrent(.moveAndLink))
        XCTAssertEqual(state.answers["cash.md#^first"], .moveAndLink)
        XCTAssertEqual(state.currentRow?.key, "cash.md#^idless")
        XCTAssertEqual(state.selectedCount, 1)
        XCTAssertEqual(state.linkedCount, 1)
        XCTAssertEqual(state.counterText, "1 move in · 1 link today")
        XCTAssertEqual(state.primaryLabel, "Move 1 · link 1")
        XCTAssertEqual(
            state.consequence(for: tryUnwrappedRow(state, key: "cash.md#^first")),
            "Moves in · becomes Next · links under ADMIN"
        )
        XCTAssertFalse(state.setAnswer(.move, for: "cash.md#^locked"))
        XCTAssertFalse(state.setAnswer(.move, for: "missing"))
    }

    func testMoveAndLinkCountOnlyCountsChoicesThatAddALink() {
        let alreadyLinked = row(
            key: "cash.md#^linked",
            n: 1,
            text: "Already linked task",
            section: nil,
            choices: [
                CaptureMoveChoiceOption(sigil: "^", consequence: "Moves in"),
                CaptureMoveChoiceOption(sigil: ":", consequence: "Moves in", addsLink: false),
            ]
        )
        var state = CaptureMoveChoiceState(
            slot: CaptureMoveChoiceSlot(
                parent: "cash.md",
                destination: "cash_new.md",
                rows: [alreadyLinked]
            )
        )

        XCTAssertTrue(state.setAnswer(.moveAndLink, for: alreadyLinked.key))
        XCTAssertEqual(state.selectedCount, 1)
        XCTAssertEqual(state.linkedCount, 0)
        XCTAssertEqual(state.counterText, "1 move in")
        XCTAssertEqual(state.primaryLabel, "Move 1")
    }

    func testToggleSelectAllAndClearRespectDisabledRows() {
        var state = CaptureMoveChoiceState(slot: slot())

        XCTAssertTrue(state.toggleCurrent())
        XCTAssertEqual(state.answers["cash.md#^first"], .move)
        XCTAssertTrue(state.toggleCurrent())
        XCTAssertNil(state.answers["cash.md#^first"])

        state.selectAll()
        XCTAssertEqual(state.selectedCount, 2)
        XCTAssertEqual(state.linkedCount, 0)
        XCTAssertNil(state.answers["cash.md#^locked"])
        XCTAssertNil(state.answers["cash.md#^disabled"])

        state.clearAnswers()
        XCTAssertFalse(state.canConfirm)
        XCTAssertEqual(state.selectedCount, 0)
    }

    func testSectionsRetainFirstOccurrenceAndPresentationCopy() {
        let state = CaptureMoveChoiceState(slot: slot())
        XCTAssertEqual(state.sections.map(\.title), ["Tasks", "Admin"])
        XCTAssertEqual(state.sections.map { $0.rows.count }, [3, 1])
        XCTAssertEqual(
            CaptureMoveChoicePresentation.title(for: state.slot), "Move into cash_new.md")
        XCTAssertEqual(
            CaptureMoveChoicePresentation.subtitle(for: state.slot), "from cash.md · 4 open")
        XCTAssertEqual(
            CaptureMoveChoicePresentation.statusGlyph(for: state.rows[0]),
            "○"
        )
    }

    func testFilterSelectAllRetainsExplicitLinkAndSerializesInParentOrder() {
        var state = CaptureMoveChoiceState(slot: slot())
        _ = state.setAnswer(.moveAndLink, for: "cash.md#^first")
        state.updateFilter("ID-less")
        state.selectAll()
        XCTAssertEqual(state.selectedCount, 2)
        XCTAssertEqual(state.outsideFilterCount, 1)
        XCTAssertEqual(state.selection, ":cash.md#^first,cash.md#^idless")
        state.selectAll()
        XCTAssertEqual(state.selection, ":cash.md#^first")
        XCTAssertEqual(state.linkedCount, 1)
        state.updateFilter("no matching rows")
        XCTAssertNil(state.currentRow)
        XCTAssertFalse(state.answerCurrent(.move))
    }

    func testReseedKeepsSurvivingKeysAndNameRequiresColonEvenWhenHeld() {
        var state = CaptureMoveChoiceState(slot: slot())
        state.selectAll()
        let rows = Array(state.rows.prefix(1))
        let fresh = CaptureMoveChoiceSlot(
            parent: "cash.md", destination: "cash_new.md", pomodoroName: "ADMIN",
            nameNeedsLink: true, rows: rows
        )
        XCTAssertEqual(state.reseed(slot: fresh), 1)
        XCTAssertEqual(state.selection, "cash.md#^first")
        XCTAssertFalse(state.canConfirm)
        XCTAssertEqual(state.nameRequirementMessage, "#admin needs a : pick, or remove #admin")
        XCTAssertTrue(state.answerCurrent(.moveAndLink))
        XCTAssertTrue(state.canConfirm)
    }

    func testChoiceGhostRequiresExactDraftAndUTF8Anchor() {
        let draft = "Café @cash^exit@\n- ^^"
        let end = draft.utf8.count
        let slot = CaptureMoveChoiceSlot(
            draftRange: [end - 2, end], parent: "cash.md",
            copy: CaptureMoveChoiceCopy(ghost: "choose on ↩")
        )
        let report = CaptureMoveChoice(supported: true, slots: [slot])
        let ghosts = CaptureMoveChoicePresentation.ghosts(
            draft: draft, previewDraft: draft, report: report
        )
        XCTAssertEqual(ghosts.first?.text, "choose on ↩")
        XCTAssertEqual(ghosts.first?.insertionUTF8Offset, end)
        XCTAssertEqual(ghosts.first?.lineNumber, 2)
        XCTAssertTrue(
            CaptureMoveChoicePresentation.ghosts(
                draft: draft + "x", previewDraft: draft, report: report
            ).isEmpty)
        XCTAssertTrue(
            CaptureMoveChoicePresentation.ghosts(
                draft: draft.replacingOccurrences(of: "^^", with: "^x"),
                previewDraft: draft.replacingOccurrences(of: "^^", with: "^x"), report: report
            ).isEmpty)
        XCTAssertFalse(CaptureMoveChoicePresentation.hasWholeLineMarker("task\n  - ^^"))
    }

    func testRealBobAnsweredFixturesAndNotification() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        for name in ["mq7", "mq10"] {
            let data = try Data(
                contentsOf: fixtures.appendingPathComponent("move-choice-\(name).json"))
            let success = try JSONDecoder().decode(CaptureCommandSuccess.self, from: data)
            let slot = try XCTUnwrap(success.moveChoice?.slots.first)
            XCTAssertTrue(slot.answered)
            XCTAssertEqual(slot.movedCount, 2)
            XCTAssertEqual(slot.linkedCount, 1)
            let note = try XCTUnwrap(success.projectNote)
            XCTAssertEqual(note.movedTasks.filter { $0.via == "choice" }.count, 2)
            XCTAssertFalse(
                note.successors.contains { row in
                    note.movedTasks.contains { $0.via == "choice" && $0.blockID == row.blockID }
                })
            let presentation = try XCTUnwrap(CaptureProjectNoteMovePresentation(capture: success))
            XCTAssertTrue(
                presentation.notificationDetail.contains("moved 3 tasks from cash · 1 linked"))
        }
    }

    private func tryUnwrappedRow(
        _ state: CaptureMoveChoiceState,
        key: String
    ) -> CaptureMoveChoiceRow {
        // The helper keeps each state assertion readable; the fixture below
        // always supplies these stable Bob keys.
        state.rows.first(where: { $0.key == key })!
    }

    private func slot() -> CaptureMoveChoiceSlot {
        CaptureMoveChoiceSlot(
            item: 1,
            itemLine: 4,
            draftRange: [12, 14],
            parent: "cash.md",
            destination: "cash_new.md",
            pomodoroName: "ADMIN",
            openCount: 4,
            copy: CaptureMoveChoiceCopy(
                title: "Move into cash_new.md",
                subtitle: "from cash.md · 4 open",
                slot: "Lands between first and last, in cash.md order",
                leave: "Stays in cash.md"
            ),
            rows: [
                row(
                    key: "cash.md#^first",
                    n: 1,
                    text: "First task",
                    section: nil,
                    choices: [
                        CaptureMoveChoiceOption(
                            sigil: "^", consequence: "Moves into cash_new.md", addsLink: false),
                        CaptureMoveChoiceOption(
                            sigil: ":", consequence: "Moves in · becomes Next · links under ADMIN",
                            addsLink: true),
                    ]
                ),
                row(
                    key: "cash.md#^locked",
                    n: 2,
                    text: "Already moving",
                    section: "Tasks",
                    locked: CaptureMoveChoiceLock(sigil: "^", itemLine: 3)
                ),
                row(
                    key: "cash.md#^disabled",
                    n: 3,
                    text: "Cannot move",
                    section: "Tasks",
                    disabledReason: "the project starts tomorrow"
                ),
                row(
                    key: "cash.md#^idless",
                    n: 4,
                    text: "ID-less task",
                    section: "Admin",
                    mint: "idless-task",
                    choices: [
                        CaptureMoveChoiceOption(
                            sigil: "^", consequence: "Moves into cash_new.md · adds ^idless-task",
                            addsLink: false),
                        CaptureMoveChoiceOption(
                            sigil: ":",
                            consequence: "Moves in · adds ^idless-task · links under ADMIN",
                            addsLink: true),
                    ]
                ),
            ]
        )
    }

    private func row(
        key: String,
        n: Int,
        text: String,
        section: String?,
        mint: String? = nil,
        choices: [CaptureMoveChoiceOption] = [],
        locked: CaptureMoveChoiceLock? = nil,
        disabledReason: String? = nil
    ) -> CaptureMoveChoiceRow {
        CaptureMoveChoiceRow(
            key: key,
            n: n,
            line: n + 5,
            section: section,
            blockID: mint == nil ? String(key.split(separator: "^").last ?? "") : nil,
            mint: mint,
            text: text,
            statusSymbol: " ",
            statusName: "Ready",
            choices: choices,
            locked: locked,
            disabledReason: disabledReason
        )
    }

    private var successJSON: String {
        """
        {"ok":true,"dry_run":true,"routed":true,"route_label":"cash_new.md",
         "relative_target":"cash_new.md","target":"/tmp/cash_new.md","text":"Finish the task",
         "task_line":"- [ ] #task Finish the task","kind":"project_note","created":"2026-11-04",
         "placement":"created","move_choice":{"supported":true,"slots":[{"item":1,"item_line":4,
           "draft_range":[112,114],"parent":"cash.md","destination":"cash_goog_exit.md",
           "pomodoro_name":"ADMIN","name_needs_link":false,"open_count":4,"answered":false,
           "moved_count":0,"linked_count":0,"copy":{"title":"Move into cash_goog_exit.md",
             "subtitle":"from cash.md · 4 open","slot":"Lands between Pay and Book, in cash.md order",
             "leave":"Stays in cash.md","ghost":"choose from cash.md's 4 open tasks on ↩",
             "band":"Asks about cash.md's 4 open tasks on ↩","then":null},"rows":[
             {"key":"cash.md#^call-ms","n":1,"line":12,"section":"Tasks","block_id":"call-ms",
              "mint":null,"text":"Call Morgan Stanley about the 401k","status_symbol":" ",
              "status_name":"Ready","hidden":false,"scheduled":null,"pomodoro":{"line":2,"name":"WORK"},
              "choices":[{"sigil":"^","consequence":"Moves into cash_goog_exit.md","adds_link":false},
                {"sigil":":","consequence":"Moves in · becomes Next · links under ADMIN","adds_link":true}],
              "locked":null,"disabled_reason":null,"answer":null},
             {"key":"cash.md#^pay-cc","n":2,"line":20,"section":"Admin","block_id":"pay-cc",
              "text":"Pay the credit card","status_symbol":" ","status_name":"Ready","hidden":false,
              "choices":[],"locked":{"sigil":"^","item_line":3},"disabled_reason":null,"answer":null},
             {"key":"cash.md@1a2b3c4d","n":3,"line":21,"section":"Admin","block_id":null,
              "mint":"renew-the-passport","text":"Renew the passport","status_symbol":" ",
              "status_name":"Ready","hidden":false,"choices":[{"sigil":"^",
                "consequence":"Moves into cash_goog_exit.md · adds ^renew-the-passport","adds_link":false},
                {"sigil":":","consequence":"Moves in · adds ^renew-the-passport · links under ADMIN","adds_link":true}],
              "locked":null,"disabled_reason":null,"answer":null}] }]}}
        """
    }
}
