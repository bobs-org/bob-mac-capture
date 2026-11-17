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
        XCTAssertEqual(inline.topLevelChildLines, inline.childLines)
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
        XCTAssertEqual(list.topLevelChildLines, list.childLines)
    }

    func testAttachmentHeadersCountFilesAndImages() throws {
        let image = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-attachments-image.json")))
        XCTAssertEqual(image.headerText, "1 image")
        XCTAssertEqual(image.childLines, ["\t- ![[img/shot.png|400]]"])
        XCTAssertEqual(image.topLevelChildLines, image.childLines)
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
        XCTAssertEqual(mixed.attachmentRows.map(\.isVideo), [false, false])
        XCTAssertTrue(mixed.attachmentRows.allSatisfy { $0.sizeBytes == nil })
    }

    func testAttachmentHeadersCountVideosFromBobsKind() throws {
        let video = try XCTUnwrap(
            CaptureClipPresentation(
                capture: decodeCaptureSuccess(
                    clipCaptureJSON(
                        mode: "attachments",
                        lines: [#"\t- ![[vid/x.mp4|400]]"#],
                        attachments: [
                            attachmentJSON(
                                source: "/tmp/x.mp4",
                                saved: "vid/x.mp4",
                                kind: "video",
                                sizeBytes: 248_678
                            )
                        ]
                    ))))
        XCTAssertEqual(video.headerText, "1 video")
        XCTAssertEqual(video.attachmentRows.map(\.summaryText), ["vid/x.mp4 · video · 242.8 KiB"])
        XCTAssertEqual(video.attachmentRows.map(\.isVideo), [true])
        XCTAssertEqual(video.attachmentRows.map(\.isImage), [false])
        XCTAssertEqual(video.attachmentRows.map(\.sizeBytes), [248_678])
        XCTAssertEqual(
            video.attachmentRows[0].videoAccessibilityLabel(durationSeconds: 6),
            "Video, 6 seconds, vid/x.mp4")

        let imageAndVideo = try XCTUnwrap(
            CaptureClipPresentation(
                capture: decodeCaptureSuccess(
                    clipCaptureJSON(
                        mode: "attachments",
                        lines: [#"\t- ![[img/shot.png|400]]"#, #"\t- ![[vid/x.mp4|400]]"#],
                        attachments: [
                            attachmentJSON(
                                source: "/tmp/shot.png", saved: "img/shot.png", kind: "image",
                                sizeBytes: 512),
                            attachmentJSON(
                                source: "/tmp/x.mp4", saved: "vid/x.mp4", kind: "video",
                                sizeBytes: 248_678),
                        ]
                    ))))
        XCTAssertEqual(imageAndVideo.headerText, "1 image · 1 video")
        XCTAssertEqual(
            imageAndVideo.attachmentRows.map(\.summaryText),
            ["img/shot.png · image · 512 B", "vid/x.mp4 · video · 242.8 KiB"])

        let fileAndVideo = try XCTUnwrap(
            CaptureClipPresentation(
                capture: decodeCaptureSuccess(
                    clipCaptureJSON(
                        mode: "attachments",
                        lines: [#"\t- [[file/notes.pdf]]"#, #"\t- ![[vid/x.mp4|400]]"#],
                        attachments: [
                            attachmentJSON(
                                source: "/tmp/notes.pdf", saved: "file/notes.pdf", kind: "file"),
                            attachmentJSON(
                                source: "/tmp/x.mp4", saved: "vid/x.mp4", kind: "video",
                                sizeBytes: 2 * 1024 * 1024),
                        ]
                    ))))
        XCTAssertEqual(fileAndVideo.headerText, "1 file · 1 video")
        XCTAssertEqual(
            fileAndVideo.attachmentRows.map(\.summaryText),
            ["file/notes.pdf · file", "vid/x.mp4 · video · 2.0 MiB"])
        XCTAssertEqual(fileAndVideo.attachmentRows.map(\.isVideo), [false, true])
        XCTAssertNil(fileAndVideo.attachmentRows[0].sizeBytes)
    }

    func testOldBobAttachmentJSONOmitsSizeBytes() throws {
        let image = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-attachments-image.json")))
        XCTAssertNil(image.attachmentRows.first?.sizeBytes)
        XCTAssertEqual(image.attachmentRows.map(\.summaryText), ["img/shot.png · image"])
    }

    func testHumanBytesMatchesBobsOneDecimalBinaryUnits() {
        XCTAssertEqual(CaptureClipPresentation.humanBytes(0), "0 B")
        XCTAssertEqual(CaptureClipPresentation.humanBytes(512), "512 B")
        XCTAssertEqual(CaptureClipPresentation.humanBytes(248_678), "242.8 KiB")
        XCTAssertEqual(CaptureClipPresentation.humanBytes(2 * 1024 * 1024), "2.0 MiB")
    }

    func testVideoDurationBadgeAndAccessibility() {
        XCTAssertEqual(
            CaptureClipPresentation.AttachmentRow.videoDurationBadge(seconds: 6), "0:06")
        XCTAssertEqual(
            CaptureClipPresentation.AttachmentRow.videoDurationBadge(seconds: 6.4), "0:06")
        XCTAssertEqual(
            CaptureClipPresentation.AttachmentRow.videoDurationBadge(seconds: 61), "1:01")
        XCTAssertEqual(
            CaptureClipPresentation.AttachmentRow.videoDurationBadge(seconds: 3661), "1:01:01")
        XCTAssertEqual(
            CaptureClipPresentation.AttachmentRow.videoAccessibilityLabel(
                savedPath: "vid/x.mp4", durationSeconds: 1),
            "Video, 1 second, vid/x.mp4")
        XCTAssertEqual(
            CaptureClipPresentation.AttachmentRow.videoAccessibilityLabel(
                savedPath: "vid/x.mp4", durationSeconds: 6),
            "Video, 6 seconds, vid/x.mp4")
    }

    func testUnknownStructuredAttachmentWarningRendersBobsMessage() throws {
        let message =
            "vid/x.mp4 is 62.3 MiB; vault sync warns at 50 MiB and refuses 95 MiB"
        let success = try decodeCaptureSuccess(
            clipCaptureJSON(
                mode: "attachments",
                lines: [#"\t- ![[vid/x.mp4|400]]"#],
                attachments: [
                    attachmentJSON(
                        source: "/tmp/x.mp4", saved: "vid/x.mp4", kind: "video",
                        sizeBytes: 65_327_104)
                ],
                warningsJSON:
                    #"[{"code":"attachment_large","message":"\#(message)"}]"#
            ))
        XCTAssertEqual(success.warnings.map(\.message), [message])
        XCTAssertEqual(
            CaptureRelationCancelPresentation.previewWarningRows(for: success), [])
        XCTAssertEqual(
            CaptureRelationCompletePresentation.previewWarningRows(for: success), [])
        let leftover = CapturePreviewWarningRow.leftoverRows(for: success)
        XCTAssertEqual(leftover.map(\.text), [message])
        XCTAssertEqual(leftover.map(\.style), [.amber])
        XCTAssertEqual(leftover.map(\.accessibilityLabel), ["Warning: \(message)"])
    }

    func testSnippetHeaderNamesTheDestination() throws {
        let heading = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-snippet-heading.json")))
        XCTAssertEqual(
            heading.headerText, "Snippet · 1 line → file/clip-20261030-091500-heading.md")
        XCTAssertEqual(heading.snippetDestination, "file/clip-20261030-091500-heading.md")
        XCTAssertEqual(heading.childLines, ["\t- [[file/clip-20261030-091500-heading]]"])
        XCTAssertEqual(heading.topLevelChildLines, heading.childLines)
        XCTAssertFalse(heading.showsPlaceholder)
    }

    func testHistoryEntriesKeepBoundariesAndDividers() throws {
        let history = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-history.json")))
        XCTAssertEqual(history.headerText, "Last 3 clips")
        XCTAssertTrue(history.isHistory)
        XCTAssertEqual(history.childLines, ["\t- newest", "\t- older", "\t- oldest"])
        XCTAssertTrue(history.topLevelChildLines.isEmpty)
        XCTAssertEqual(
            history.historyEntries.map(\.dividerText),
            ["Entry 1 of 3", "Entry 2 of 3", "Entry 3 of 3"])
        XCTAssertEqual(history.historyEntries.map(\.modeText), ["inline", "inline", "inline"])
        XCTAssertEqual(
            history.historyEntries.map(\.lines), [["\t- newest"], ["\t- older"], ["\t- oldest"]])
        XCTAssertEqual(history.accessibilitySummary, "Last 3 clips: 3 lines")
    }

    func testHistoryHeaderShowsProviderAndAges() throws {
        let history = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-history-provenance.json")))
        XCTAssertEqual(history.headerText, "Last 3 clips · Alfred · newest 3s · oldest 2h")
        XCTAssertEqual(
            history.historyEntries.map(\.dividerText),
            [
                "Entry 1 of 3 · 3s ago · Safari",
                "Entry 2 of 3 · 4m ago",
                "Entry 3 of 3 · 2h ago · Notes",
            ])
        XCTAssertEqual(
            history.accessibilitySummary, "Last 3 clips · Alfred · newest 3s · oldest 2h: 3 lines")
    }

    func testCommandHistoryShowsProviderWithoutAges() throws {
        let history = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-history-command.json")))
        XCTAssertEqual(history.headerText, "Last 3 clips · command")
        XCTAssertEqual(
            history.historyEntries.map(\.dividerText),
            ["Entry 1 of 3", "Entry 2 of 3", "Entry 3 of 3"])
        XCTAssertEqual(history.accessibilitySummary, "Last 3 clips · command: 3 lines")
    }

    func testMalformedHistoryKeepsTodaysStrings() throws {
        let history = try XCTUnwrap(
            CaptureClipPresentation(capture: decodeFixture("clip-history-malformed.json")))
        XCTAssertEqual(history.headerText, "Last 3 clips")
        XCTAssertEqual(
            history.historyEntries.map(\.dividerText),
            ["Entry 1 of 3", "Entry 2 of 3", "Entry 3 of 3"])
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

    private func clipCaptureJSON(
        mode: String,
        lines: [String],
        attachments: [String],
        warningsJSON: String? = nil
    ) -> String {
        let lineList = lines.map { "\"\($0)\"" }.joined(separator: ",")
        let attachmentList = attachments.joined(separator: ",")
        var json = """
            {"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"",
            "relative_target":"mac_inbox.md","target":"/tmp/vault/mac_inbox.md","text":"jot idea",
            "task_line":"- [ ] #task jot idea","kind":"task","created":"2026-11-16",
            "scheduled":null,"placement":"inserted",
            "clip":{"status":"read","mode":"\(mode)","lines":[\(lineList)],
            "attachments":[\(attachmentList)],"entries":[]}}
            """
        if let warningsJSON {
            json.removeLast()
            json += ",\"warnings\":\(warningsJSON)}"
        }
        return json
    }

    private func attachmentJSON(
        source: String,
        saved: String,
        kind: String,
        reused: Bool = false,
        sizeBytes: UInt64? = nil
    ) -> String {
        var json =
            #"{"source":"\#(source)","saved":"\#(saved)","kind":"\#(kind)","reused":\#(reused)}"#
        if let sizeBytes {
            json.removeLast()
            json += #","size_bytes":\#(sizeBytes)}"#
        }
        return json
    }
}
