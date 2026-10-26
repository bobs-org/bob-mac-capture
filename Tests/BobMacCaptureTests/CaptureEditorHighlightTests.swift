import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureEditorHighlightTests: XCTestCase {
    func testThemeTintDoesNotLeakPastNameDuringRepaint() throws {
        let draft = "Add bar @bob:theme-day-strip-bar#vibe=\n\nFix theme highlighting! @bob"
        let theme = CapturePomodoroThemeRef(
            key: "vibe",
            name: "vibe",
            hue: .orange,
            hueSource: "hash",
            start: 33,
            end: 37
        )
        let spans = Self.screenshotSpans(theme: theme)
        var text = AttributedString(draft)
        try Self.setAttributes(on: &text, start: 33, end: 37) {
            $0.backgroundColor = .orange
            $0.inlinePresentationIntent = .emphasized
        }
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertEqual(Self.strings(in: text, where: { $0.backgroundColor != nil }), ["vibe"])
        XCTAssertTrue(Self.strings(in: text, where: { $0.inlinePresentationIntent != nil }).isEmpty)
    }

    func testUnknownThemeHasNoTint() throws {
        let draft = "Add bar @bob:theme-day-strip-bar#vibe=\n\nFix theme highlighting! @bob"
        let theme = CapturePomodoroThemeRef(
            key: "vibe",
            name: "vibe",
            hue: .orange,
            hueSource: "hash",
            known: false,
            start: 33,
            end: 37
        )
        let spans = Self.screenshotSpans(theme: theme)
        var text = AttributedString(draft)
        try Self.setAttributes(on: &text, start: 33, end: 37) {
            $0.backgroundColor = .orange
        }
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertTrue(Self.strings(in: text, where: { $0.backgroundColor != nil }).isEmpty)
    }

    func testRelationLabelItalicDoesNotLeakIntoFollowingText() throws {
        let draft = "Use this @mac_inbox+owner ~tasks:target|follow next"
        let spans = [
            CaptureSpan(start: 9, end: 19, kind: "sub_bullet_route"),
            CaptureSpan(start: 20, end: 25, kind: "sub_bullet_block_id"),
            CaptureSpan(start: 26, end: 27, kind: "relation_sigil"),
            CaptureSpan(start: 27, end: 32, kind: "relation_note"),
            CaptureSpan(start: 33, end: 39, kind: "relation_block_id"),
            CaptureSpan(start: 39, end: 40, kind: "relation_label_separator"),
            CaptureSpan(start: 40, end: 46, kind: "relation_label"),
        ]
        var text = AttributedString(draft)
        try Self.setAttributes(on: &text, start: 46, end: draft.utf8.count) {
            $0.inlinePresentationIntent = .emphasized
        }
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertEqual(Self.strings(in: text, where: { $0.inlinePresentationIntent != nil }), ["follow"])
    }

    func testWhitespaceOnlyDraftClearsInheritedTint() throws {
        let model = CapturePanelModel()
        var text = AttributedString("  ")
        try Self.setAttributes(on: &text, start: 0, end: 2) {
            $0.backgroundColor = .orange
        }
        model.attributedDraft = text

        model.editorTextDidChange(cursorUTF8Offset: 2)

        XCTAssertTrue(Self.strings(in: model.attributedDraft, where: { $0.backgroundColor != nil }).isEmpty)
    }

    private static func screenshotSpans(theme: CapturePomodoroThemeRef) -> [CaptureSpan] {
        [
            CaptureSpan(start: 8, end: 12, kind: "pomodoro_route"),
            CaptureSpan(start: 13, end: 32, kind: "pomodoro_block_id"),
            CaptureSpan(start: 33, end: 37, kind: "pomodoro_name", themes: [theme]),
            CaptureSpan(start: 37, end: 38, kind: "pomodoro_start"),
            CaptureSpan(start: 64, end: 68, kind: "route"),
        ]
    }

    private static func parse(draft: String, spans: [CaptureSpan]) -> CaptureParseResponse {
        CaptureParseResponse(
            ok: true,
            schemaVersion: 1,
            input: draft,
            body: draft,
            mode: "incomplete",
            spans: spans
        )
    }

    private static func setAttributes(
        on text: inout AttributedString,
        start: Int,
        end: Int,
        update: (inout AttributeContainer) -> Void
    ) throws {
        let range = try XCTUnwrap(stringRange(in: String(text.characters), start: start, end: end))
        guard let lower = AttributedString.Index(range.lowerBound, within: text),
              let upper = AttributedString.Index(range.upperBound, within: text)
        else {
            XCTFail("Unable to map byte range into attributed text")
            return
        }
        var attributes = AttributeContainer()
        update(&attributes)
        text[lower..<upper].mergeAttributes(attributes)
    }

    private static func strings(
        in text: AttributedString,
        where predicate: (AttributeContainer) -> Bool
    ) -> [String] {
        text.runs.compactMap { run in
            guard predicate(run.attributes) else {
                return nil
            }
            return String(text[run.range].characters)
        }
    }
}
