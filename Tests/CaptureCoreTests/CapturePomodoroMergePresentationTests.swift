import Foundation
import XCTest

@testable import CaptureCore

final class CapturePomodoroMergePresentationTests: XCTestCase {
    func testMergePreviewUsesBobNamesAbsorbedRowsAndDuplicateCounts() throws {
        let capture = try decodeFixture("pomodoro-merge-preview.json")
        let presentation = try XCTUnwrap(CapturePomodoroMergePresentation(capture: capture))

        XCTAssertEqual(presentation.before, "BUILD")
        XCTAssertEqual(presentation.after, "BUILD + FIX + READ")
        XCTAssertEqual(presentation.destinationText, "20261102.md · line 8")
        XCTAssertEqual(presentation.absorbedRows.map(\.name), ["FIX", "READ"])
        XCTAssertEqual(presentation.absorbedRows.map(\.movedLines), [3, 1])
        XCTAssertEqual(presentation.absorbedRows.map(\.droppedDuplicates), [1, 0])
        XCTAssertEqual(presentation.primaryActionTitle, "Merge")
        XCTAssertEqual(presentation.statusText, "Would merge FIX, READ into BUILD + FIX + READ")
        XCTAssertTrue(
            presentation.notificationBody.contains("FIX · 3 lines moved · 1 duplicate dropped")
        )
        XCTAssertFalse(presentation.sourceIsImplied)
        XCTAssertEqual(presentation.absorbedRows.map(\.isNext), [false, false])
        XCTAssertNil(presentation.explicitToken)
        XCTAssertNil(presentation.teachingHint)
        XCTAssertFalse(
            presentation.previewAccessibilitySummary.contains("is the current Pomodoro")
        )
    }

    func testImpliedMergeMarksCurrentAndNextAndTeachesTheSpelling() throws {
        let capture = try decodeFixture("pomodoro-merge-implied-preview.json")
        let presentation = try XCTUnwrap(CapturePomodoroMergePresentation(capture: capture))

        XCTAssertEqual(presentation.before, "PLAN")
        XCTAssertEqual(presentation.after, "PLAN + FIX")
        XCTAssertTrue(presentation.sourceIsImplied)
        XCTAssertEqual(presentation.absorbedRows.map(\.isNext), [true])
        XCTAssertEqual(presentation.explicitToken, "=*plan#fix")
        XCTAssertEqual(
            presentation.teachingHint?.text,
            "Same as =*plan#fix · Type #name to absorb a specific Pomodoro"
        )
        XCTAssertEqual(
            presentation.teachingHint?.tokens.map(\.category),
            [.neutral, .pomodoroStart, .neutral, .section, .neutral]
        )
        XCTAssertTrue(
            presentation.previewAccessibilitySummary.contains("PLAN is the current Pomodoro")
        )
        XCTAssertTrue(
            presentation.previewAccessibilitySummary.contains(
                "FIX is the next planned Pomodoro"
            )
        )
        XCTAssertTrue(
            presentation.previewAccessibilitySummary.contains("same as =*plan#fix")
        )
    }

    func testNamedDestinationKeepsImpliedSourceWithoutNameHint() throws {
        let capture = try decodeJSON(
            """
            {"ok":true,"dry_run":true,"routed":false,"route_label":"20261102.md",\
            "relative_target":"20261102.md","target":"/tmp/vault/20261102.md",\
            "text":"=*#fix","task_line":"","kind":"pomodoro_merge",\
            "created":"2026-11-02","placement":"updated","pomodoro_merge":{\
            "path":"20261102.md","entry_line":5,"before":"PLAN","after":"PLAN + FIX",\
            "source_role":"current","explicit":"=*plan#fix",\
            "absorbed":[{"name":"FIX","role":"named","from_line":8,\
            "moved_lines":1,"dropped_duplicates":0}]}}
            """
        )
        let presentation = try XCTUnwrap(CapturePomodoroMergePresentation(capture: capture))

        XCTAssertTrue(presentation.sourceIsImplied)
        XCTAssertEqual(presentation.absorbedRows.map(\.isNext), [false])
        XCTAssertEqual(presentation.explicitToken, "=*plan#fix")
        XCTAssertEqual(presentation.teachingHint?.text, "Same as =*plan#fix")
        XCTAssertFalse(
            presentation.teachingHint?.text.contains("#name") ?? true
        )
        XCTAssertTrue(
            presentation.previewAccessibilitySummary.contains("PLAN is the current Pomodoro")
        )
        XCTAssertFalse(
            presentation.previewAccessibilitySummary.contains(
                "is the next planned Pomodoro"
            )
        )
    }

    func testMissingExplicitTeachesOnlyTheNameHint() throws {
        let capture = try decodeJSON(
            """
            {"ok":true,"dry_run":true,"routed":false,"route_label":"20261102.md",\
            "relative_target":"20261102.md","target":"/tmp/vault/20261102.md",\
            "text":"=*","task_line":"","kind":"pomodoro_merge",\
            "created":"2026-11-02","placement":"updated","pomodoro_merge":{\
            "path":"20261102.md","entry_line":5,"before":"PLAN","after":"PLAN + FIX",\
            "source_role":"current",\
            "absorbed":[{"name":"FIX","role":"next","from_line":8,\
            "moved_lines":1,"dropped_duplicates":0}]}}
            """
        )
        let presentation = try XCTUnwrap(CapturePomodoroMergePresentation(capture: capture))

        XCTAssertTrue(presentation.sourceIsImplied)
        XCTAssertTrue(presentation.absorbedRows[0].isNext)
        XCTAssertNil(presentation.explicitToken)
        XCTAssertEqual(
            presentation.teachingHint?.text,
            "Type #name to absorb a specific Pomodoro"
        )
        XCTAssertFalse(
            presentation.previewAccessibilitySummary.contains("same as")
        )
    }

    func testOlderBobHasNoMergePresentation() throws {
        let capture = try decodeFixture("pomodoro-close-worked.json")

        XCTAssertNil(capture.pomodoroMerge)
        XCTAssertNil(CapturePomodoroMergePresentation(capture: capture))
    }

    private func decodeFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
        return try decodeJSON(text)
    }

    private func decodeJSON(_ text: String) throws -> CaptureCommandSuccess {
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: Data(text.utf8))
        guard case .success(let success) = response else {
            throw NSError(domain: "CapturePomodoroMergePresentationTests", code: 1)
        }
        return success
    }
}
