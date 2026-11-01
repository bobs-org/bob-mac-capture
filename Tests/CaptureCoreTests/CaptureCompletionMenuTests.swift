import XCTest

@testable import CaptureCore

final class CaptureCompletionMenuTests: XCTestCase {
    func testOmittedInitialSelectionSelectsTheFirstRow() {
        let completion = response(context: "route", initialSelection: nil, suggestedIndex: nil)
        XCTAssertEqual(
            CaptureCompletionMenu.initialSelectedIndex(for: completion, queryIsEmpty: true),
            0
        )
        XCTAssertEqual(
            CaptureCompletionMenu.initialSelectedIndex(for: completion, queryIsEmpty: false),
            0
        )
    }

    func testNoneOpensWithoutASelectedRow() {
        let completion = response(
            context: "directive", initialSelection: "none", suggestedIndex: 1)
        XCTAssertNil(
            CaptureCompletionMenu.initialSelectedIndex(for: completion, queryIsEmpty: true)
        )
        XCTAssertNil(
            CaptureCompletionMenu.initialSelectedIndex(for: completion, queryIsEmpty: false)
        )
    }

    func testEmptyQueryPomodoroSuggestionWinsOverFirstRow() {
        let completion = response(
            context: "pomodoro_name", initialSelection: nil, suggestedIndex: 1)
        XCTAssertEqual(
            CaptureCompletionMenu.initialSelectedIndex(for: completion, queryIsEmpty: true),
            1
        )
        XCTAssertEqual(
            CaptureCompletionMenu.initialSelectedIndex(for: completion, queryIsEmpty: false),
            0
        )
    }

    func testNoneWinsOverAPomodoroSuggestion() {
        let completion = response(
            context: "pomodoro_name", initialSelection: "none", suggestedIndex: 1)
        XCTAssertNil(
            CaptureCompletionMenu.initialSelectedIndex(for: completion, queryIsEmpty: true)
        )
    }

    func testEmptyCandidateListStaysUnselected() {
        let completion = CaptureCompletionResponse(
            ok: true,
            cursor: 0,
            replacement: CaptureRange(start: 0, end: 0),
            context: "route",
            candidates: []
        )
        XCTAssertNil(
            CaptureCompletionMenu.initialSelectedIndex(for: completion, queryIsEmpty: true)
        )
    }

    func testDisabledReasonAndRefusedConsumeAcceptance() {
        XCTAssertTrue(
            CaptureCompletionMenu.isDisabled(
                CaptureCompletionCandidate(
                    replacement: "",
                    disabledReason:
                        "Configure `highlights.listen_command` to enable companion audio."
                )
            )
        )
        XCTAssertTrue(
            CaptureCompletionMenu.isDisabled(
                CaptureCompletionCandidate(
                    replacement: "#fixs",
                    refused: "type_not_configured"
                )
            )
        )
        XCTAssertFalse(
            CaptureCompletionMenu.isDisabled(
                CaptureCompletionCandidate(replacement: "%c", name: "Clip")
            )
        )
        XCTAssertFalse(
            CaptureCompletionMenu.isDisabled(
                CaptureCompletionCandidate(replacement: "%c", disabledReason: "")
            )
        )
    }

    func testDrawerMenuHonorsNoneAndOtherwiseSelectsTheBestFirstRow() {
        let rows = [
            CaptureCompletionCandidate(replacement: "#requirements", title: "REQUIREMENTS"),
            CaptureCompletionCandidate(replacement: "#future-work", title: "FUTURE WORK"),
        ]
        let empty = CaptureCompletionResponse(
            ok: true,
            cursor: 29,
            replacement: CaptureRange(start: 29, end: 29),
            context: "drawer",
            candidates: rows,
            initialSelection: "none"
        )
        XCTAssertNil(CaptureCompletionMenu.initialSelectedIndex(for: empty, queryIsEmpty: true))

        let typed = CaptureCompletionResponse(
            ok: true,
            cursor: 32,
            replacement: CaptureRange(start: 29, end: 32),
            context: "drawer",
            candidates: rows
        )
        XCTAssertEqual(
            CaptureCompletionMenu.initialSelectedIndex(for: typed, queryIsEmpty: false), 0)
    }

    func testUnselectedFooterHintMatchesTheParentMenuCopy() {
        XCTAssertEqual(
            CaptureCompletionMenu.unselectedFooterHint,
            "⇥ take the first · type a letter · ⏎ capture as typed"
        )
        XCTAssertEqual(CaptureCompletionMenu.directiveTitle, "CAPTURE AS")
    }

    private func response(
        context: String,
        initialSelection: String?,
        suggestedIndex: Int?
    ) -> CaptureCompletionResponse {
        let candidates = [
            CaptureCompletionCandidate(replacement: "a", name: "A"),
            CaptureCompletionCandidate(
                replacement: "b", name: "B", suggested: suggestedIndex == 1),
        ]
        return CaptureCompletionResponse(
            ok: true,
            cursor: 1,
            replacement: CaptureRange(start: 0, end: 1),
            context: context,
            candidates: candidates,
            initialSelection: initialSelection
        )
    }
}
