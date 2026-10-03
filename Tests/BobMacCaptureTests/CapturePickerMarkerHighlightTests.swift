import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Design-phase model tests for the picker's marker highlight: while any
/// picker is open, the marker token being completed carries an accent wash
/// in the dimmed editor (`marker_range` for block-ID sources,
/// `[r.start - 1, r.end)` for `^`). The wash is attribute-only — it never
/// changes `plainDraft`, the selection, or undo — and every close path
/// removes it.
@MainActor
final class CapturePickerMarkerHighlightTests: XCTestCase {
    func testMarkerHighlightRangeForActiveTaskIncludesTrigger() {
        XCTAssertEqual(
            CapturePanelModel.pickerMarkerHighlightRange(
                source: .activeTask,
                replacementRange: CaptureRange(start: 5, end: 9),
                markerRange: nil
            ),
            CaptureRange(start: 4, end: 9)
        )
        // No trigger byte before the range start: no highlight.
        XCTAssertNil(
            CapturePanelModel.pickerMarkerHighlightRange(
                source: .activeTask,
                replacementRange: CaptureRange(start: 0, end: 1),
                markerRange: nil
            )
        )
        // Degenerate ranges never highlight.
        XCTAssertNil(
            CapturePanelModel.pickerMarkerHighlightRange(
                source: .activeTask,
                replacementRange: CaptureRange(start: 9, end: 5),
                markerRange: nil
            )
        )
    }

    func testMarkerHighlightRangeForBlockIDPrefersMarkerRange() {
        let link = CapturePickerSource.blockID(
            BlockIDPickerContext(field: nil, route: "sase", marker: ":", intent: .link, rules: nil)
        )
        XCTAssertEqual(
            CapturePanelModel.pickerMarkerHighlightRange(
                source: link,
                replacementRange: CaptureRange(start: 6, end: 6),
                markerRange: CaptureRange(start: 0, end: 6)
            ),
            CaptureRange(start: 0, end: 6)
        )
        // Older Bob sends no marker range: fall back to the replacement.
        XCTAssertEqual(
            CapturePanelModel.pickerMarkerHighlightRange(
                source: link,
                replacementRange: CaptureRange(start: 6, end: 6),
                markerRange: nil
            ),
            CaptureRange(start: 6, end: 6)
        )
    }

    func testMarkerHighlightRangeForTaskLinkKeepsSigilRange() {
        // Bob's `task_link` replacement already includes the `:` sigil.
        XCTAssertEqual(
            CapturePanelModel.pickerMarkerHighlightRange(
                source: .taskLink,
                replacementRange: CaptureRange(start: 0, end: 4),
                markerRange: nil
            ),
            CaptureRange(start: 0, end: 4)
        )
    }

    func testMarkerHighlightRangeForParentTaskUsesDescriptorRange() {
        let context = ParentTaskPickerContext.note(
            route: "cash",
            noteTarget: "cash.md",
            markerRange: CaptureRange(start: 0, end: 6),
            triggerRemovalRange: CaptureRange(start: 5, end: 6)
        )
        XCTAssertEqual(
            CapturePanelModel.pickerMarkerHighlightRange(
                source: .parentTask(context),
                replacementRange: CaptureRange(start: 6, end: 6),
                markerRange: nil
            ),
            CaptureRange(start: 0, end: 6)
        )
    }

    func testScopeLineNumberNeedsMultilineDraft() {
        XCTAssertNil(CapturePanelModel.scopeLineNumber(draft: "@sase:", markerStart: 0))
        XCTAssertEqual(CapturePanelModel.scopeLineNumber(draft: "one\ntwo", markerStart: 4), 2)
        XCTAssertEqual(CapturePanelModel.scopeLineNumber(draft: "one\ntwo", markerStart: 0), 1)
        XCTAssertNil(CapturePanelModel.scopeLineNumber(draft: "one\ntwo", markerStart: 99))
        XCTAssertNil(CapturePanelModel.scopeLineNumber(draft: "one\ntwo", markerStart: -1))
    }

    func testBlockIDPreviewInstallsMarkerWashWithoutTouchingTextOrSelection() {
        let model = CapturePanelModel()
        let draft = "@sase:flaky"
        model.installBlockIDPickerForPreviews(
            field: Self.linkField,
            candidates: [],
            context: "pomodoro_block_id",
            replacement: CaptureRange(start: 6, end: 11),
            filter: "flaky",
            draft: draft,
            restoreCursor: 6
        )

        XCTAssertEqual(model.pickerMarkerHighlight, CaptureRange(start: 0, end: 6))
        XCTAssertEqual(model.plainDraft, draft)
        // setPlainDraft parks the caret at the end; the wash must not move it.
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), draft.utf8.count)
        XCTAssertEqual(
            Self.washedStrings(in: model.attributedDraft),
            ["@sase:"]
        )

        model.cancelPicker()

        XCTAssertNil(model.pickerMarkerHighlight)
        XCTAssertTrue(Self.washedStrings(in: model.attributedDraft).isEmpty)
        XCTAssertEqual(model.plainDraft, draft)
        // Cancel restores the opening caret; the wash is gone with it.
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 6)
    }

    func testAvailabilityAnnouncedOnlyOnCategoryChange() {
        let model = CapturePanelModel()
        model.installBlockIDPickerForPreviews(
            field: Self.newIDField,
            candidates: [],
            context: "task_block_id",
            replacement: CaptureRange(start: 27, end: 27),
            draft: "Fix flaky gkeep test @sase^"
        )

        model.updatePickerFilter("fix")
        XCTAssertEqual(model.statusText, "fix is available")
        let tick = model.statusAnnouncementTick

        // Same category, longer filter: stays quiet.
        model.updatePickerFilter("fix-")
        XCTAssertEqual(model.statusAnnouncementTick, tick)

        // Taken ID names the conflict and the next-free alternative.
        model.updatePickerFilter("tool")
        XCTAssertEqual(model.statusText, "tool is already used on line 36; tool-2 is available")
    }

    private static var linkField: CaptureBlockIDField {
        CaptureBlockIDField(
            route: "sase",
            relativeTarget: "sase.md",
            marker: ":",
            markerRange: CaptureRange(start: 0, end: 6),
            intent: .link,
            allowedCharacter: "[A-Za-z0-9-]",
            allowedDescription: "A-Z, a-z, 0-9 or '-'"
        )
    }

    private static var newIDField: CaptureBlockIDField {
        CaptureBlockIDField(
            route: "sase",
            relativeTarget: "sase.md",
            marker: "^",
            markerRange: CaptureRange(start: 21, end: 27),
            intent: .new,
            body: "Fix flaky gkeep test",
            allowedCharacter: "[A-Za-z0-9-]",
            allowedDescription: "A-Z, a-z, 0-9 or '-'",
            suggestions: ["fix-flaky-gkeep"],
            used: [
                CaptureUsedBlockID(
                    id: "tool",
                    line: 36,
                    isTask: true,
                    statusSymbol: " ",
                    statusName: "Todo",
                    text: "Add `sase tool` command to wrap common tool calls!"
                ),
            ]
        )
    }

    /// The washed substrings of an attributed draft, in order.
    private static func washedStrings(in text: AttributedString) -> [String] {
        text.runs.compactMap { run in
            guard text[run.range].backgroundColor != nil else {
                return nil
            }
            return String(text[run.range].characters)
        }
    }
}
