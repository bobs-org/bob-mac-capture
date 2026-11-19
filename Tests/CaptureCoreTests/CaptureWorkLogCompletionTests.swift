import Foundation
import XCTest

@testable import CaptureCore

/// Inline Work Log recall (`capture-complete` `work_log` context): the
/// response decodes without a selection, and each row renders as neutral
/// history with Bob's `uses`/`last_used` metadata.
final class CaptureWorkLogCompletionTests: XCTestCase {
    private func decodeFixture(_ name: String) throws -> CaptureCompletionResponse {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(
            contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
        return try JSONDecoder().decode(
            CaptureCompletionResponse.self, from: Data(text.utf8))
    }

    func testWorkLogFixtureDecodesContextWithoutSelection() throws {
        let response = try decodeFixture("capture-complete-work-log.json")
        XCTAssertTrue(response.ok)
        XCTAssertEqual(CaptureCompletionContext(rawContext: response.context), .workLog)
        XCTAssertEqual(response.initialSelection, "none")
        XCTAssertTrue(response.opensWithoutSelection)
        XCTAssertNil(
            CaptureCompletionMenu.initialSelectedIndex(
                for: response, queryIsEmpty: false))
        XCTAssertEqual(response.query, "auth")
        XCTAssertEqual(response.candidates.count, 3)
        let top = try XCTUnwrap(response.candidates.first)
        XCTAssertEqual(top.replacement, "auth retry")
        XCTAssertEqual(top.text, "auth retry")
        XCTAssertEqual(top.key, "auth retry")
        XCTAssertEqual(top.uses, 2)
        XCTAssertEqual(top.lastUsed, "2026-11-19 08:30")
    }

    func testWorkLogRowsRenderNeutralHistoryWithCountAndAge() {
        XCTAssertEqual(CaptureCompletionContext(rawContext: "work_log"), .workLog)
        let candidate = CaptureCompletionCandidate(
            replacement: "athena agent",
            text: "athena agent",
            lastUsed: "2020-11-19 08:10",
            uses: 104,
            key: "athena agent"
        )
        let content = completionRowContent(
            for: candidate, context: "work_log", query: "ath")
        XCTAssertEqual(content.category, .neutral)
        XCTAssertEqual(content.symbolName, "clock.arrow.circlepath")
        XCTAssertEqual(content.contextLabel, "")
        XCTAssertEqual(content.primaryText, "athena agent")
        XCTAssertEqual(content.secondaryText, "104×  ·  Nov 19, 2020")
        XCTAssertEqual(content.primaryMatchRange, 0..<3)
        XCTAssertEqual(content.badges, [])
        XCTAssertFalse(content.isDisabled)
        XCTAssertEqual(
            content.accessibilityHint,
            "Replaces the Work Log summary with this phrase.")
    }

    func testWorkLogRowWithoutStampShowsCountOnly() {
        let candidate = CaptureCompletionCandidate(replacement: "wired it", uses: 3)
        let content = completionRowContent(
            for: candidate, context: "work_log", query: "")
        XCTAssertEqual(content.primaryText, "wired it")
        XCTAssertEqual(content.secondaryText, "3×")
        XCTAssertNil(content.primaryMatchRange)
    }

    func testWorkLogCandidateWithoutUsageDecodesAdditively() throws {
        let candidate = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data(
                #"{"replacement": "wired the lexer", "text": "wired the lexer"}"#.utf8)
        )
        XCTAssertNil(candidate.uses)
        XCTAssertNil(candidate.lastUsed)
        let content = completionRowContent(
            for: candidate, context: "work_log", query: "")
        XCTAssertEqual(content.primaryText, "wired the lexer")
        XCTAssertNil(content.secondaryText)
    }

    func testCloseLogSummarySpanStaysNeutral() {
        // An older app maps the additive span kind to neutral text, so an
        // older app is unaffected by the new span.
        XCTAssertEqual(
            captureSemanticCategory(forSpanKind: "pomodoro_close_log_summary"),
            .neutral)
    }
}
