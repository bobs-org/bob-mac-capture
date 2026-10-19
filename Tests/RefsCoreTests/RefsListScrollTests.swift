import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest

@testable import RefsCore

/// Pure geometry and reveal policy for the Refs list: row spans mirror
/// the view's fixed layout (6 pt padding, 26 pt pinned headers, 44 pt
/// rows), and the reveal keeps the selected row's title below the
/// pinned section header.
final class RefsListScrollTests: XCTestCase {
    private func browseListing() -> RefsListing {
        RefsListing(
            mode: .browse,
            scope: .all,
            sections: [
                RefsSection(kind: .new, ids: ["n0", "n1"]),
                RefsSection(kind: .today, ids: ["t0", "t1", "t2"]),
                RefsSection(kind: .ready, ids: ["r0"]),
            ],
            orderedIDs: ["n0", "n1", "t0", "t1", "t2", "r0"],
            matches: [:],
            totalCount: 6,
            openCount: 6
        )
    }

    private func searchListing() -> RefsListing {
        RefsListing(
            mode: .search("alpha"),
            scope: .all,
            sections: [RefsSection(kind: nil, ids: ["s0", "s1", "s2"])],
            orderedIDs: ["s0", "s1", "s2"],
            matches: [:],
            totalCount: 3,
            openCount: 3
        )
    }

    func testMetricsMatchTheViewLayout() {
        XCTAssertEqual(RefsListGeometry.rowHeight, 44)
        XCTAssertEqual(RefsListGeometry.sectionHeaderHeight, 26)
        XCTAssertEqual(RefsListGeometry.verticalPadding, 6)
    }

    func testContentHeightAndRowSpansMirrorTheView() {
        let listing = browseListing()
        // 2 x 6 padding + 3 x 26 headers + 6 x 44 rows.
        XCTAssertEqual(RefsListScrollPolicy.contentHeight(of: listing), 354)

        let first = RefsListScrollPolicy.rowSpan(for: "n0", in: listing)
        XCTAssertEqual(first, RefsListRowSpan(top: 32, bottom: 76, pinnedInset: 26))

        // The second section's first row starts after the previous
        // rows plus its own header: 6 + (26 + 2 x 44) + 26.
        let today = RefsListScrollPolicy.rowSpan(for: "t0", in: listing)
        XCTAssertEqual(today, RefsListRowSpan(top: 146, bottom: 190, pinnedInset: 26))

        let last = RefsListScrollPolicy.rowSpan(for: "r0", in: listing)
        XCTAssertEqual(last, RefsListRowSpan(top: 304, bottom: 348, pinnedInset: 26))

        XCTAssertNil(RefsListScrollPolicy.rowSpan(for: "unknown", in: listing))
    }

    func testEmptyHeadedSectionStillCountsItsHeader() {
        let listing = RefsListing(
            mode: .browse,
            scope: .all,
            sections: [
                RefsSection(kind: .new, ids: []),
                RefsSection(kind: .today, ids: ["t0"]),
            ],
            orderedIDs: ["t0"],
            matches: [:],
            totalCount: 1,
            openCount: 1
        )
        XCTAssertEqual(RefsListScrollPolicy.contentHeight(of: listing), 108)
        XCTAssertEqual(
            RefsListScrollPolicy.rowSpan(for: "t0", in: listing),
            RefsListRowSpan(top: 58, bottom: 102, pinnedInset: 26)
        )
    }

    func testSearchListingHasNoHeaderInset() {
        let listing = searchListing()
        XCTAssertEqual(RefsListScrollPolicy.contentHeight(of: listing), 144)
        XCTAssertEqual(
            RefsListScrollPolicy.rowSpan(for: "s0", in: listing),
            RefsListRowSpan(top: 6, bottom: 50, pinnedInset: 0)
        )
        XCTAssertEqual(
            RefsListScrollPolicy.rowSpan(for: "s2", in: listing),
            RefsListRowSpan(top: 94, bottom: 138, pinnedInset: 0)
        )
    }

    func testDuplicateIDResolvesToTheFirstSection() {
        let listing = RefsListing(
            mode: .browse,
            scope: .all,
            sections: [
                RefsSection(kind: .today, ids: ["a", "shared"]),
                RefsSection(kind: .ready, ids: ["b", "shared"]),
            ],
            orderedIDs: ["a", "b", "shared"],
            matches: [:],
            totalCount: 3,
            openCount: 3
        )
        XCTAssertEqual(listing.sectionIndex(for: "shared"), 0)
        XCTAssertEqual(
            RefsListScrollPolicy.rowSpan(for: "shared", in: listing),
            RefsListRowSpan(top: 76, bottom: 120, pinnedInset: 26)
        )
    }

    func testFirstRowAlwaysReturnsTop() {
        let listing = browseListing()
        // The screenshot regression: the panel opens with the list
        // scrolled down, and the first row sits above the viewport.
        XCTAssertEqual(
            RefsListScrollPolicy.reveal("n0", in: listing, offset: 0, viewportHeight: 200),
            .top
        )
        XCTAssertEqual(
            RefsListScrollPolicy.reveal("n0", in: listing, offset: 500, viewportHeight: 200),
            .top
        )
        // A stale offset from taller pre-re-rank content still goes top.
        XCTAssertEqual(
            RefsListScrollPolicy.reveal("n0", in: listing, offset: 10_000, viewportHeight: 200),
            .top
        )
        // Even before geometry is measured, the first row means top.
        XCTAssertEqual(
            RefsListScrollPolicy.reveal("n0", in: listing, offset: 0, viewportHeight: 0),
            .top
        )
    }

    func testRowAboveViewportLandsUnderItsHeader() {
        let listing = browseListing()
        // Viewport 200 over content 354: maxOffset 154. From the
        // bottom, t0 (146...190) sits above the pinned band and lands
        // with its top just under its header.
        XCTAssertEqual(
            RefsListScrollPolicy.reveal("t0", in: listing, offset: 154, viewportHeight: 200),
            .offset(120)
        )
        // 120 is the TODAY header's natural top.
        let span = RefsListScrollPolicy.rowSpan(for: "t0", in: listing)
        XCTAssertEqual((span?.top ?? 0) - (span?.pinnedInset ?? 0), 120)
    }

    func testRowUnderThePinnedHeaderIsRevealed() {
        let listing = browseListing()
        // The arrow-up regression: t0's top (146) is inside the
        // viewport but within 26 pt of the offset, under the pinned
        // header, so it reveals to 120.
        XCTAssertEqual(
            RefsListScrollPolicy.reveal("t0", in: listing, offset: 130, viewportHeight: 200),
            .offset(120)
        )
        // The same row fully below the header band needs no scroll.
        XCTAssertNil(
            RefsListScrollPolicy.reveal("t0", in: listing, offset: 120, viewportHeight: 200)
        )
        // A move within half a point is also a no-op.
        XCTAssertNil(
            RefsListScrollPolicy.reveal("t0", in: listing, offset: 120.4, viewportHeight: 200)
        )
    }

    func testRowBelowViewportAlignsBottomExceptTheLastRow() {
        let listing = browseListing()
        // t2 (234...278) below a top viewport lands bottom-aligned.
        XCTAssertEqual(
            RefsListScrollPolicy.reveal("t2", in: listing, offset: 0, viewportHeight: 200),
            .offset(78)
        )
        // The last row scrolls to the max offset so the bottom
        // padding shows: content 354 - viewport 200 = 154.
        XCTAssertEqual(
            RefsListScrollPolicy.reveal("r0", in: listing, offset: 0, viewportHeight: 200),
            .offset(154)
        )
    }

    func testSearchRowAboveViewportLandsAtItsExactTop() {
        let listing = searchListing()
        // No header band in search: inset 0, so the row lands flush.
        // s1 (50...94) is not the first row, so the minimal scroll
        // applies instead of `.top`. The 60 pt viewport overflows
        // the 144 pt content (maxOffset 84).
        XCTAssertEqual(
            RefsListScrollPolicy.reveal("s1", in: listing, offset: 100, viewportHeight: 60),
            .offset(50)
        )
        XCTAssertNil(
            RefsListScrollPolicy.reveal("s1", in: listing, offset: 0, viewportHeight: 200)
        )
    }

    func testStaleOffsetIsClampedBeforeTheDecision() {
        let listing = browseListing()
        // t2 (234...278) with a stale offset past the new maxOffset
        // (154): clamped, the row is on screen, so nil. Without the
        // clamp the stale offset would wrongly scroll up to 208.
        XCTAssertNil(
            RefsListScrollPolicy.reveal("t2", in: listing, offset: 10_000, viewportHeight: 200)
        )
    }

    func testHeaderWinsWhenTheViewportFitsNeitherHeaderNorRow() {
        let listing = browseListing()
        // A 30 pt viewport holds neither the 26 pt header nor the
        // 44 pt row; the title stays readable under the header.
        XCTAssertEqual(
            RefsListScrollPolicy.reveal("t0", in: listing, offset: 140, viewportHeight: 30),
            .offset(120)
        )
    }

    func testInvalidGeometryReturnsNilForNonFirstRows() {
        let listing = browseListing()
        XCTAssertNil(
            RefsListScrollPolicy.reveal("t0", in: listing, offset: 0, viewportHeight: 0)
        )
        XCTAssertNil(
            RefsListScrollPolicy.reveal("t0", in: listing, offset: 0, viewportHeight: -10)
        )
        XCTAssertNil(
            RefsListScrollPolicy.reveal(
                "t0", in: listing, offset: .infinity, viewportHeight: 200)
        )
        XCTAssertNil(
            RefsListScrollPolicy.reveal(
                "t0", in: listing, offset: 0, viewportHeight: .nan)
        )
        XCTAssertNil(
            RefsListScrollPolicy.reveal("unknown", in: listing, offset: 0, viewportHeight: 200)
        )
        // Non-finite input returns nil even for the first row.
        XCTAssertNil(
            RefsListScrollPolicy.reveal(
                "n0", in: listing, offset: .nan, viewportHeight: 200)
        )
    }
}
