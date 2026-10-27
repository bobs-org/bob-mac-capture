import XCTest

@testable import CaptureCore

final class SimilarTasksBandPolicyTests: XCTestCase {
    private func match(
        _ key: String,
        band: CaptureRelatedBand = .possibleDuplicate,
        title: String? = nil
    ) -> CaptureRelatedMatch {
        CaptureRelatedMatch(
            key: key,
            band: band,
            title: title ?? key,
            actions: [.relate, .note, .needs, .blocks, .open, .discard]
        )
    }

    private func item(
        _ index: Int,
        mode: String = "task",
        matches: [CaptureRelatedMatch],
        linked: [CaptureRelatedLinked] = []
    ) -> CaptureRelatedItem {
        CaptureRelatedItem(index: index, mode: mode, matches: matches, linked: linked)
    }

    func testSingleItemShowsTwoRowsAndCountsTheOverflow() {
        let response = CaptureRelatedResponse(items: [
            item(0, matches: [match("a"), match("b"), match("c"), match("d")]),
        ])

        let state = SimilarTasksBandPolicy.reduce(response, draft: "one task")

        XCTAssertEqual(state.items.count, 1)
        XCTAssertEqual(state.items[0].rows.map(\.match.key), ["a", "b"])
        XCTAssertEqual(state.items[0].rows.map(\.rowNumber), [1, 2])
        XCTAssertEqual(state.items[0].overflowCount, 2)
        XCTAssertTrue(state.items[0].showsHeader)
    }

    func testBulkRowsAreOnePerItemNumberedAcrossDraftAndCappedAtFive() {
        let items = (0..<6).map { index in
            item(index, matches: [match("\(index)-a"), match("\(index)-b")])
        }
        let state = SimilarTasksBandPolicy.reduce(
            CaptureRelatedResponse(items: items),
            draft: "bulk",
            draftItemCount: 6
        )

        XCTAssertEqual(state.rows.count, 5)
        XCTAssertEqual(state.rows.map(\.rowNumber), [1, 2, 3, 4, 5])
        XCTAssertEqual(state.rows.map(\.itemIndex), [0, 1, 2, 3, 4])
        XCTAssertTrue(state.items.allSatisfy { $0.rows.count == 1 && !$0.showsHeader })
        XCTAssertTrue(state.items.allSatisfy { $0.overflowCount == 0 })
    }

    func testSingleTaskInMixedBulkDraftUsesBulkLayoutFromBobParseCount() {
        let state = SimilarTasksBandPolicy.reduce(
            CaptureRelatedResponse(items: [item(0, matches: [match("a"), match("b")])]),
            draft: "task plus note",
            draftItemCount: 2
        )

        XCTAssertEqual(state.rows.count, 1)
        XCTAssertFalse(state.items[0].showsHeader)
        XCTAssertEqual(state.items[0].overflowCount, 0)
    }

    func testHoldKeepsOnlyPreviouslyVisibleRowsAndLinkedTaskStaysInPlace() {
        let initial = SimilarTasksBandPolicy.reduce(
            CaptureRelatedResponse(items: [item(0, matches: [match("a"), match("b")])]),
            draft: "initial"
        )
        let focused = SimilarTasksBandState(
            draft: initial.draft,
            items: initial.items,
            focusedRowID: initial.rows[1].id
        )
        let next = CaptureRelatedResponse(items: [
            item(
                0,
                matches: [
                    match("a", band: .hold),
                    match("new-hold", band: .hold),
                    match("c"),
                ],
                linked: [CaptureRelatedLinked(key: "b", link: .relation)]
            ),
        ])

        let state = SimilarTasksBandPolicy.reduce(next, previous: focused, draft: "edited")

        XCTAssertEqual(state.rows.map(\.match.key), ["a", "b"])
        XCTAssertTrue(state.rows[0].isHeld)
        XCTAssertEqual(state.rows[1].linkedBy, .relation)
        XCTAssertEqual(state.focusedRowID, focused.focusedRowID)
        XCTAssertEqual(state.items[0].overflowCount, 1)
    }

    func testPendingFreezesRowsAndFocusUntilTheSettledResponse() {
        let initial = SimilarTasksBandPolicy.reduce(
            CaptureRelatedResponse(items: [item(0, matches: [match("a")])]),
            draft: "initial"
        )
        let focused = SimilarTasksBandState(
            draft: initial.draft,
            items: initial.items,
            focusedRowID: initial.rows[0].id
        )

        let pending = SimilarTasksBandPolicy.markPending(focused)
        XCTAssertTrue(pending.pending)
        XCTAssertEqual(pending.items, focused.items)
        XCTAssertEqual(pending.focusedRowID, focused.focusedRowID)

        let settled = SimilarTasksBandPolicy.reduce(
            CaptureRelatedResponse(items: [item(0, matches: [match("a"), match("b")])]),
            previous: pending,
            draft: "edited"
        )
        XCTAssertFalse(settled.pending)
        XCTAssertEqual(settled.focusedRowID, focused.focusedRowID)

        let removed = SimilarTasksBandPolicy.reduce(
            CaptureRelatedResponse(items: [item(0, matches: [match("b")])]),
            previous: pending,
            draft: "gone"
        )
        XCTAssertNil(removed.focusedRowID)
    }

    func testModeAndEmptyCountGateKeepTheBandAbsent() {
        let response = CaptureRelatedResponse(items: [
            item(0, mode: "ref", matches: [match("wrong-kind")]),
            item(1, matches: []),
        ])

        let state = SimilarTasksBandPolicy.reduce(response)

        XCTAssertTrue(state.items.isEmpty)
        XCTAssertTrue(state.rows.isEmpty)
    }

    func testReduceStoresTheParseItemCount() {
        let state = SimilarTasksBandPolicy.reduce(
            CaptureRelatedResponse(items: [item(0, matches: [match("a")])]),
            draftItemCount: 3
        )

        XCTAssertEqual(state.parseItemCount, 3)
    }

    func testRenderGateDropsTheBandWhenParseItemCountChanges() {
        let state = SimilarTasksBandPolicy.reduce(
            CaptureRelatedResponse(items: [item(0, matches: [match("a")])]),
            draft: "one",
            draftItemCount: 1
        )

        XCTAssertNotNil(
            SimilarTasksBandPolicy.visibleItem(
                in: state,
                captureIndex: 0,
                parseItems: [SimilarTasksParseItem(index: 0, mode: "task")]
            )
        )
        XCTAssertTrue(
            SimilarTasksBandPolicy.visibleItems(
                in: state,
                parseItems: [
                    SimilarTasksParseItem(index: 0, mode: "task"),
                    SimilarTasksParseItem(index: 1, mode: "task"),
                ]
            ).isEmpty
        )
    }

    func testRenderGateDropsTheBandWhenParseModeChanges() {
        let state = SimilarTasksBandPolicy.reduce(
            CaptureRelatedResponse(items: [item(0, matches: [match("a")])]),
            draftItemCount: 1
        )

        XCTAssertNil(
            SimilarTasksBandPolicy.visibleItem(
                in: state,
                captureIndex: 0,
                parseItems: [SimilarTasksParseItem(index: 0, mode: "sub_bullet")]
            )
        )
    }

    func testRevealShowsNextHiddenMatchesUpToTheDraftCap() {
        let five = (0..<5).map { match("m\($0)") }
        let response = CaptureRelatedResponse(items: [item(0, matches: five)])
        let base = SimilarTasksBandPolicy.reduce(response, draft: "one")
        XCTAssertEqual(base.rows.map(\.rowNumber), [1, 2])
        XCTAssertEqual(base.items[0].overflowCount, 3)

        let revealed = SimilarTasksBandState(
            draft: base.draft,
            items: base.items,
            focusedRowID: base.rows[1].id,
            parseItemCount: base.parseItemCount,
            revealed: [0: 2]
        )
        let grown = SimilarTasksBandPolicy.reduce(response, previous: revealed, draft: "one")
        XCTAssertEqual(grown.rows.map(\.rowNumber), [1, 2, 3, 4])
        XCTAssertEqual(grown.items[0].overflowCount, 1)
        XCTAssertEqual(grown.revealed, [0: 2])
        XCTAssertEqual(grown.focusedRowID, revealed.focusedRowID)
    }

    func testRevealClampedToBobLimitAndDroppedWhenExhausted() {
        let five = (0..<5).map { match("m\($0)") }
        let response = CaptureRelatedResponse(items: [item(0, matches: five)])
        let previous = SimilarTasksBandState(revealed: [0: 9])
        let grown = SimilarTasksBandPolicy.reduce(response, previous: previous, draft: "one")
        XCTAssertEqual(grown.rows.count, 5)
        XCTAssertEqual(grown.items[0].overflowCount, 0)
        // The last hidden match just painted, so the count collapses.
        XCTAssertEqual(grown.revealed, [:])
    }

    func testRevealDropsWhenHiddenMatchesVanish() {
        let two = [match("a"), match("b")]
        let previous = SimilarTasksBandState(revealed: [0: 2])
        let settled = SimilarTasksBandPolicy.reduce(
            CaptureRelatedResponse(items: [item(0, matches: two)]),
            previous: previous,
            draft: "edited"
        )
        XCTAssertEqual(settled.rows.map(\.match.key), ["a", "b"])
        XCTAssertEqual(settled.revealed, [:])
    }

    func testPendingPreservesReveal() {
        let state = SimilarTasksBandState(revealed: [0: 1])
        XCTAssertEqual(SimilarTasksBandPolicy.markPending(state).revealed, [0: 1])
    }

    func testRenderGateKeepsHeldRowsWhenParseIsEmpty() {
        let state = SimilarTasksBandPolicy.reduce(
            CaptureRelatedResponse(items: [item(0, matches: [match("a")])]),
            draftItemCount: 1
        )

        XCTAssertEqual(
            SimilarTasksBandPolicy.visibleItem(
                in: state,
                captureIndex: 0,
                parseItems: []
            )?.rows.map(\.match.key),
            ["a"]
        )
    }
}
