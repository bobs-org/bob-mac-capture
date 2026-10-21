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
}
