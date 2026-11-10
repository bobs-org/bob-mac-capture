import XCTest

@testable import CaptureCore

final class GcalNotePresentationTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/gcal-note")
    }

    private func decode<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        return try JSONDecoder().decode(T.self, from: data)
    }

    func testHighlightRolesAndUnknownStayNeutral() {
        XCTAssertEqual(GcalNotePresentation.highlightRole(forKind: "route"), .route)
        XCTAssertEqual(GcalNotePresentation.highlightRole(forKind: "root"), .root)
        XCTAssertEqual(GcalNotePresentation.highlightRole(forKind: "clock"), .clock)
        XCTAssertEqual(GcalNotePresentation.highlightRole(forKind: "buffer"), .buffer)
        XCTAssertEqual(GcalNotePresentation.highlightRole(forKind: "reason_sign"), .reasonSign)
        XCTAssertEqual(GcalNotePresentation.highlightRole(forKind: "reason"), .reason)
        XCTAssertEqual(GcalNotePresentation.highlightRole(forKind: "prose"), .prose)
        XCTAssertEqual(GcalNotePresentation.highlightRole(forKind: "mystery"), .unknown)
    }

    func testPaintOnlyMatchingInputText() throws {
        let preview = try decode("preview.json", as: GcalNoteWriteResponse.self)
        XCTAssertNotNil(
            GcalNotePresentation.matchingWrite(
                preview,
                text: "@family -30 Drive there +15 Drive home"
            )
        )
        XCTAssertNil(
            GcalNotePresentation.matchingWrite(preview, text: "@family\nchanged")
        )
    }

    func testCleanShowPreviewIsCurrentWithoutSpans() throws {
        let show = try decode("show.json", as: GcalNoteShowResponse.self)
        let live = GcalNotePresentation.livePreview(
            editorText: show.event?.note?.text ?? "",
            isDirty: false,
            phase: .editing,
            show: show,
            preview: nil,
            lastValid: nil,
            previewError: nil
        )
        XCTAssertTrue(live.isCurrent)
        XCTAssertFalse(live.isInvalid)
        XCTAssertEqual(live.spans.count, 0)
        XCTAssertEqual(live.effective?.root?.value, "family")
        XCTAssertEqual(live.preview?.path, show.preview?.path)
    }

    func testInvalidPreviewKeepsLastValidLandsAndReportsError() throws {
        let show = try decode("show.json", as: GcalNoteShowResponse.self)
        let valid = try decode("preview.json", as: GcalNoteWriteResponse.self)
        let invalid = try decode("invalid.json", as: GcalNoteWriteResponse.self)
        let live = GcalNotePresentation.livePreview(
            editorText: invalid.input?.text ?? "@famly",
            isDirty: true,
            phase: .editing,
            show: show,
            preview: invalid,
            lastValid: valid,
            previewError: invalid.error?.message
        )
        XCTAssertTrue(live.isInvalid)
        XCTAssertFalse(live.isCurrent)
        XCTAssertEqual(live.preview?.row, valid.preview?.row)
        XCTAssertEqual(live.statusLabel, "This note is invalid")
        XCTAssertEqual(live.errors.first?.kind, "route_unknown")
        XCTAssertNotNil(live.errorMessage)
    }

    func testPendingPreviewDimsRetainedPreview() throws {
        let show = try decode("show.json", as: GcalNoteShowResponse.self)
        let valid = try decode("preview.json", as: GcalNoteWriteResponse.self)
        let live = GcalNotePresentation.livePreview(
            editorText: "in flight",
            isDirty: true,
            phase: .previewPending,
            show: show,
            preview: valid,
            lastValid: valid,
            previewError: nil
        )
        XCTAssertTrue(live.isPending)
        XCTAssertFalse(live.isCurrent)
        XCTAssertEqual(live.statusLabel, "Updating preview…")
        XCTAssertEqual(live.preview?.row, valid.preview?.row)
    }

    func testWaitingInvitationHasNoFabricatedTaskRow() throws {
        let event = GcalNoteEvent(
            from: """
                {
                  "calendar_id": "primary",
                  "event_id": "waiting-reply",
                  "answer": "no_reply",
                  "lands": "waiting_reply",
                  "title": "Review proposal"
                }
                """
        )
        let preview = GcalNotePreview(
            from: """
                {"path": "2026/20261111.md", "row": null, "bullets": []}
                """
        )
        XCTAssertEqual(
            GcalNotePresentation.landsExplanation(event: event, preview: preview),
            "Waiting for a reply — this invitation has no Event Task yet."
        )
    }

    func testFooterAndIdentityCopy() throws {
        let show = try decode("show.json", as: GcalNoteShowResponse.self)
        let event = try XCTUnwrap(show.event)
        XCTAssertEqual(
            GcalNotePresentation.organizerLabel(for: event),
            "Kelly"
        )
        XCTAssertTrue(
            GcalNotePresentation.identitySubtitle(for: event).contains("10:00-12:00")
        )
        XCTAssertEqual(
            GcalNotePresentation.footerOwnership(scope: .event),
            "Only in Bob · This event"
        )
        XCTAssertEqual(
            GcalNotePresentation.footerOwnership(scope: .series),
            "Only in Bob · All events"
        )
        let keys = GcalNotePresentation.footerKeys(recurring: true, canUndo: true)
        XCTAssertTrue(keys.contains("⏎ Save"))
        XCTAssertTrue(keys.contains("⇧⏎ New line"))
        XCTAssertTrue(keys.contains("⌘⌫ Clear"))
        XCTAssertTrue(keys.contains("⎋ Back"))
        XCTAssertTrue(keys.contains("⌃⌥S Scope"))
        XCTAssertTrue(keys.contains("⌘Z Undo last save"))
        XCTAssertEqual(GcalNotePresentation.answerLabel("no_reply"), "Awaiting reply")
    }

    func testErrorsWithoutPreviewDoNotInventARow() throws {
        let invalid = try decode("invalid.json", as: GcalNoteWriteResponse.self)
        XCTAssertNil(invalid.preview)
        let live = GcalNotePresentation.livePreview(
            editorText: invalid.input?.text ?? "@famly",
            isDirty: true,
            phase: .editing,
            show: nil,
            preview: invalid,
            lastValid: nil,
            previewError: invalid.error?.message
        )
        XCTAssertTrue(live.isInvalid)
        XCTAssertNil(live.preview?.row)
        XCTAssertEqual(live.statusLabel, "This note is invalid")
        XCTAssertEqual(live.errors.first?.kind, "route_unknown")
    }

    func testUnsafeErrorRangesAreIgnored() {
        let issues = [
            GcalNoteIssue(start: 1, end: 2, kind: "split-scalar", message: "bad"),
            GcalNoteIssue(start: 2, end: 3, kind: "route_unknown", message: "ok"),
        ]
        let validated = GcalNoteSpanAdapter.validatedIssueRanges(in: "éx", errors: issues)
        XCTAssertEqual(validated.map(\.issue.kind), ["route_unknown"])
    }
}

extension GcalNoteEvent {
    fileprivate init(from json: String) {
        self = try! JSONDecoder().decode(Self.self, from: Data(json.utf8))
    }
}

extension GcalNotePreview {
    fileprivate init(from json: String) {
        self = try! JSONDecoder().decode(Self.self, from: Data(json.utf8))
    }
}
