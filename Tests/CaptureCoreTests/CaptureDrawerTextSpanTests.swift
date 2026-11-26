import CaptureCore
import XCTest

final class CaptureDrawerTextSpanTests: XCTestCase {
    func testDrawerSpansPreserveBobUtf8RangesAndCaretEdges() throws {
        let draft = "🧪 - **Café**"
        let titleEnd = draft.utf8.count - "**".utf8.count
        let titleStart = titleEnd - "Café".utf8.count
        let openingMarkerStart = titleStart - "**".utf8.count
        let closingMarkerStart = titleEnd
        let markerEnd = draft.utf8.count
        let spans = [
            CaptureSpan(start: 0, end: 4, kind: "route"),
            CaptureSpan(start: openingMarkerStart, end: titleStart, kind: "drawer_marker"),
            CaptureSpan(start: titleStart, end: titleEnd, kind: "drawer_bullet"),
            CaptureSpan(start: closingMarkerStart, end: markerEnd, kind: "drawer_marker"),
        ]
        let validated = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        let drawerSpans = captureDrawerTextSpans(from: validated)

        XCTAssertEqual(drawerSpans.map(\.role), [.delimiter, .title, .delimiter])
        XCTAssertEqual(drawerSpans.map { String(draft[$0.range]) }, ["**", "Café", "**"])
        XCTAssertFalse(drawerSpans[0].caretTouches(6))
        XCTAssertTrue(drawerSpans[0].caretTouches(titleStart - 1))
        XCTAssertTrue(drawerSpans[0].caretTouches(titleStart))
        XCTAssertTrue(drawerSpans[2].caretTouches(markerEnd))
        XCTAssertFalse(drawerSpans[2].caretTouches(nil))
    }

    func testEmptySkeletonNeedsTwoMarkersAndAPlaceholderAroundTheCaret() {
        let draft = "Prepare release\n- ****"
        let caret = 20
        let spans = [
            CaptureSpan(start: 18, end: 20, kind: "drawer_marker"),
            CaptureSpan(start: 20, end: 20, kind: "interactive_placeholder"),
            CaptureSpan(start: 20, end: 22, kind: "drawer_marker"),
        ]
        let skeleton = CaptureDrawerEmptySkeleton(spans: spans, caretUTF8: caret)
        XCTAssertEqual(skeleton?.deletionStart, 18)
        XCTAssertEqual(skeleton?.deletionEnd, 22)
        XCTAssertEqual(String(draft[stringRange(in: draft, start: 18, end: 22)!]), "****")
    }

    func testEmptySkeletonRejectsMissingPlaceholder() {
        let spans = [
            CaptureSpan(start: 18, end: 20, kind: "drawer_marker"),
            CaptureSpan(start: 20, end: 22, kind: "drawer_marker"),
        ]
        XCTAssertNil(CaptureDrawerEmptySkeleton(spans: spans, caretUTF8: 20))
    }

    func testEmptySkeletonRejectsNonemptyTitle() {
        let spans = [
            CaptureSpan(start: 18, end: 20, kind: "drawer_marker"),
            CaptureSpan(start: 20, end: 30, kind: "drawer_bullet"),
            CaptureSpan(start: 30, end: 32, kind: "drawer_marker"),
        ]
        XCTAssertNil(CaptureDrawerEmptySkeleton(spans: spans, caretUTF8: 20))
        XCTAssertNil(CaptureDrawerEmptySkeleton(spans: spans, caretUTF8: 32))
    }

    func testEmptySkeletonRejectsMisplacedCaret() {
        let spans = [
            CaptureSpan(start: 18, end: 20, kind: "drawer_marker"),
            CaptureSpan(start: 20, end: 20, kind: "interactive_placeholder"),
            CaptureSpan(start: 20, end: 22, kind: "drawer_marker"),
        ]
        XCTAssertNil(CaptureDrawerEmptySkeleton(spans: spans, caretUTF8: 19))
        XCTAssertNil(CaptureDrawerEmptySkeleton(spans: spans, caretUTF8: 21))
    }

    func testEmptySkeletonIgnoresUnrelatedSpans() {
        let spans = [
            CaptureSpan(start: 0, end: 4, kind: "sub_bullet_route"),
            CaptureSpan(start: 18, end: 20, kind: "drawer_marker"),
            CaptureSpan(start: 20, end: 20, kind: "interactive_placeholder"),
            CaptureSpan(start: 20, end: 22, kind: "drawer_marker"),
            CaptureSpan(start: 0, end: 4, kind: "route"),
        ]
        let skeleton = CaptureDrawerEmptySkeleton(spans: spans, caretUTF8: 20)
        XCTAssertEqual(skeleton?.deletionStart, 18)
        XCTAssertEqual(skeleton?.deletionEnd, 22)
    }
}
