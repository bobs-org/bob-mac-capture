import Foundation
import XCTest

@testable import CaptureCore

/// The portable Clip presentation model: kind/count headers per mode, Bob's
/// exact child lines, snippet destinations, attachment summaries, history
/// entry dividers, and the quiet `not_read` placeholder. Fixtures come from
/// `Scripts/generate-directive-fixtures.sh` (real-bob `clip-*.json`).
final class CaptureClipPresentationTests: XCTestCase {
    func testNilWithoutClip() throws {
        let success = try decodeCaptureSuccess(
            """
            {"ok":true,"dry_run":true,"routed":true,"route":"cash","route_label":"cash.md",
            "relative_target":"cash.md","target":"/tmp/vault/cash.md","text":"Plain",
            "task_line":"- [ ] #task Plain","kind":"task","created":"2026-10-30",
            "scheduled":null,"placement":"inserted"}
            """
        )

        XCTAssertNil(CaptureClipPresentation(capture: success))
    }

    func testInlineAndLinesHeadersCarryBobsExactLines() throws {
        let inline = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-inline.json")))
        XCTAssertEqual(inline.headerText, "Clipboard · 1 line")
        XCTAssertEqual(inline.childLines, ["\t- hello-clip"])
        XCTAssertFalse(inline.isHistory)
        XCTAssertFalse(inline.showsPlaceholder)
        XCTAssertNil(inline.snippetDestination)
        XCTAssertTrue(inline.attachmentRows.isEmpty)
        XCTAssertTrue(inline.historyEntries.isEmpty)
        XCTAssertEqual(inline.accessibilitySummary, "Clipboard · 1 line")

        let list = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-lines-list.json")))
        XCTAssertEqual(list.headerText, "Clipboard · 2 lines")
        XCTAssertEqual(list.childLines, ["\t- one", "\t- two"])
    }

    func testAttachmentHeadersCountFilesAndImages() throws {
        let image = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-attachments-image.json")))
        XCTAssertEqual(image.headerText, "1 image")
        XCTAssertEqual(image.childLines, ["\t- ![[img/shot.png|400]]"])
        XCTAssertEqual(image.attachmentRows.map(\.summaryText), ["img/shot.png · image"])
        XCTAssertEqual(
            image.attachmentRows.map(\.source),
            ["/tmp/bob-mac-capture-directive-fixture/clipboard/shot.png"])
        XCTAssertTrue(image.attachmentRows.allSatisfy(\.isImage))

        let mixed = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-attachments-mixed.json")))
        XCTAssertEqual(mixed.headerText, "1 file · 1 image")
        XCTAssertEqual(
            mixed.attachmentRows.map(\.summaryText),
            ["img/shot.png · image", "file/notes.pdf · file"])
        XCTAssertEqual(mixed.attachmentRows.map(\.isImage), [true, false])
    }

    func testSnippetHeaderNamesTheDestination() throws {
        let heading = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-snippet-heading.json")))
        XCTAssertEqual(
            heading.headerText, "Snippet · 1 line → file/clip-20261030-091500-heading.md")
        XCTAssertEqual(heading.snippetDestination, "file/clip-20261030-091500-heading.md")
        XCTAssertEqual(heading.childLines, ["\t- [[file/clip-20261030-091500-heading]]"])
        XCTAssertFalse(heading.showsPlaceholder)
    }

    func testHistoryEntriesKeepBoundariesAndDividers() throws {
        let history = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-history.json")))
        XCTAssertEqual(history.headerText, "Last 3 clips")
        XCTAssertTrue(history.isHistory)
        XCTAssertEqual(history.childLines, ["\t- newest", "\t- older", "\t- oldest"])
        XCTAssertEqual(
            history.historyEntries.map(\.dividerText),
            ["Entry 1 of 3", "Entry 2 of 3", "Entry 3 of 3"])
        XCTAssertEqual(history.historyEntries.map(\.modeText), ["inline", "inline", "inline"])
        XCTAssertEqual(
            history.historyEntries.map(\.lines), [["\t- newest"], ["\t- older"], ["\t- oldest"]])
        XCTAssertEqual(history.accessibilitySummary, "Last 3 clips: 3 lines")
    }

    func testHistoryAttachmentEntryKeepsItsRows() throws {
        let history = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-history-attachments.json")))
        XCTAssertEqual(history.headerText, "Last 2 clips")
        XCTAssertEqual(history.historyEntries.map(\.modeText), ["attachments", "inline"])
        XCTAssertEqual(
            history.historyEntries[0].attachmentRows.map(\.summaryText),
            ["img/shot.png · image"])
        XCTAssertTrue(history.historyEntries[1].attachmentRows.isEmpty)
    }

    func testNotReadShowsAQuietPlaceholder() throws {
        let one = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-not-read.json")))
        XCTAssertTrue(one.showsPlaceholder)
        XCTAssertEqual(one.placeholderText, "Clipboard not read")
        XCTAssertEqual(one.headerText, "Clipboard")
        XCTAssertTrue(one.childLines.isEmpty)
        XCTAssertEqual(one.accessibilitySummary, "Clipboard not read, 1 requested")

        let counted = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-not-read-count.json")))
        XCTAssertTrue(counted.showsPlaceholder)
        XCTAssertEqual(counted.accessibilitySummary, "Clipboard not read, 3 requested")
    }

    func testBatchItemsEachCarryTheirOwnClip() throws {
        let batch = try decodeFixture("clip-batch.json")
        let captures = batch.normalizedCaptures
        XCTAssertEqual(captures.count, 3)

        let presentations = captures.map(CaptureClipPresentation.init(capture:))
        XCTAssertEqual(presentations[0]?.headerText, "Clipboard · 1 line")
        XCTAssertEqual(presentations[0]?.childLines, ["\t- hello-clip"])
        XCTAssertNil(presentations[1], "the middle item has no %c and no clip")
        XCTAssertEqual(presentations[2]?.headerText, "Clipboard · 1 line")
        XCTAssertEqual(presentations[2]?.childLines, ["\t- hello-clip"])
    }

    func testReportsClipDirectiveFollowsBobsSpans() throws {
        XCTAssertTrue(try parseFixture("directive-parse-clip.json").reportsClipDirective)
        XCTAssertTrue(try parseFixture("directive-parse-clip-count.json").reportsClipDirective)
        XCTAssertFalse(try parseFixture("directive-parse-bare-percent.json").reportsClipDirective)
        XCTAssertFalse(try parseFixture("directive-parse-escaped.json").reportsClipDirective)
        XCTAssertFalse(
            try parseFixture("directive-parse-literal-percent.json").reportsClipDirective)
        XCTAssertFalse(try parseFixture("directive-parse-unknown.json").reportsClipDirective)
        XCTAssertFalse(try parseFixture("directive-parse-note.json").reportsClipDirective)
    }

    // MARK: - Helpers

    private enum CaptureFixtureError: Error {
        case expectedSuccess
    }

    private func decodeCaptureSuccess(_ json: String) throws -> CaptureCommandSuccess {
        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: Data(json.utf8))
        guard case .success(let success) = decoded else {
            throw CaptureFixtureError.expectedSuccess
        }
        return success
    }

    private func decodeFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
        return try decodeCaptureSuccess(text)
    }

    private func parseFixture(_ name: String) throws -> CaptureParseResponse {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        return try JSONDecoder().decode(CaptureParseResponse.self, from: data)
    }
}
