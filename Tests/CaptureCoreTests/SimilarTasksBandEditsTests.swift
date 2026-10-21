import XCTest

@testable import CaptureCore

final class SimilarTasksBandEditsTests: XCTestCase {
  private func item(
    markerAt: Int? = 24,
    routeRange: CaptureRange? = nil,
    discardRange: CaptureRange? = CaptureRange(start: 0, end: 24)
  ) -> CaptureRelatedItem {
    CaptureRelatedItem(
      index: 0,
      mode: "task",
      markerAt: markerAt,
      routeRange: routeRange,
      discardRange: discardRange
    )
  }

  private func match(
    actions: [CaptureRelatedAction] = [.relate, .note, .needs, .blocks, .open, .discard],
    defaultAction: CaptureRelatedAction? = .note
  ) -> CaptureRelatedMatch {
    CaptureRelatedMatch(
      title: "Install new UPS battery",
      replacements: CaptureRelatedReplacements(
        relationTo: "~dev:ups",
        parent: "@dev+ups",
        dependency: "&dev:ups",
        blockedTask: "*dev:ups"
      ),
      actions: actions,
      defaultAction: defaultAction
    )
  }

  func testOrderedActionsFollowStripOrder() {
    let shuffled = CaptureRelatedMatch(
      actions: [.discard, .open, .blocks, .needs, .note, .relate]
    )
    XCTAssertEqual(
      SimilarTasksBandEdits.orderedAvailableActions(for: shuffled),
      [.relate, .note, .needs, .blocks, .open, .discard]
    )
  }

  func testRelateAppendsAtMarker() {
    let draft = "Install new UPS battery @dev"
    let anchored = item(markerAt: draft.utf8.count)
    let edited = SimilarTasksBandEdits.editedDraft(
      draft,
      item: anchored,
      match: match(),
      action: .relate
    )
    XCTAssertEqual(edited?.text, draft + " ~dev:ups")
    XCTAssertEqual(edited?.cursorUTF8, (draft + " ~dev:ups").utf8.count)
  }

  func testNoteReplacesRouteRange() {
    let draft = "Install new UPS battery @dev"
    let route = CaptureRange(start: 24, end: 28)
    let anchored = item(markerAt: 28, routeRange: route)
    let edited = SimilarTasksBandEdits.editedDraft(
      draft,
      item: anchored,
      match: match(),
      action: .note
    )
    XCTAssertEqual(edited?.text, "Install new UPS battery @dev+ups")
  }

  func testNoteAppendsWhenRouteRangeIsNull() {
    let draft = "Install new UPS battery"
    let anchored = item(markerAt: draft.utf8.count, routeRange: nil)
    let edited = SimilarTasksBandEdits.editedDraft(
      draft,
      item: anchored,
      match: match(),
      action: .note
    )
    XCTAssertEqual(edited?.text, draft + " @dev+ups")
  }

  func testDiscardDeletesDiscardRange() {
    let draft = "First @a\n\nSecond @b"
    let range = CaptureRange(start: 0, end: 9)
    let anchored = item(markerAt: 8, discardRange: range)
    let edited = SimilarTasksBandEdits.editedDraft(
      draft,
      item: anchored,
      match: match(),
      action: .discard
    )
    XCTAssertEqual(edited?.text, "\nSecond @b")
    XCTAssertEqual(edited?.cursorUTF8, 0)
  }

  func testOpenNeverEdits() {
    let draft = "Install new UPS battery @dev"
    XCTAssertNil(
      SimilarTasksBandEdits.editedDraft(
        draft,
        item: item(),
        match: match(),
        action: .open
      )
    )
  }

  func testExplicitReplacementSplicesIDLessRow() {
    let draft = "Install new UPS battery @dev"
    let anchored = item(markerAt: draft.utf8.count)
    let edited = SimilarTasksBandEdits.editedDraftWithReplacement(
      draft,
      item: anchored,
      replacement: "~dev:ups-backup",
      action: .relate
    )
    XCTAssertEqual(edited?.text, draft + " ~dev:ups-backup")
    XCTAssertEqual(edited?.cursorUTF8, (draft + " ~dev:ups-backup").utf8.count)
  }

  func testExplicitNoteReplacementReplacesRouteRange() {
    let draft = "Install new UPS battery @dev"
    let route = CaptureRange(start: 24, end: 28)
    let anchored = item(markerAt: 28, routeRange: route)
    let edited = SimilarTasksBandEdits.editedDraftWithReplacement(
      draft,
      item: anchored,
      replacement: "@dev+ups-backup",
      action: .note
    )
    XCTAssertEqual(edited?.text, "Install new UPS battery @dev+ups-backup")
  }

  func testMissingReplacementReturnsNil() {
    let draft = "Install new UPS battery @dev"
    let idless = CaptureRelatedMatch(
      title: "Install new UPS battery",
      replacements: nil,
      actions: [.relate]
    )
    XCTAssertNil(
      SimilarTasksBandEdits.editedDraft(draft, item: item(), match: idless, action: .relate)
    )
  }

  func testAnnouncements() {
    XCTAssertEqual(
      SimilarTasksBandEdits.announcement(for: .relate, title: "Install new UPS battery"),
      "Related to Install new UPS battery"
    )
    XCTAssertEqual(
      SimilarTasksBandEdits.announcement(for: .note, title: "Install new UPS battery"),
      "Added as a note under Install new UPS battery"
    )
    XCTAssertEqual(
      SimilarTasksBandEdits.announcement(for: .discard, title: "Anything"),
      "Removed your item — ⌘Z restores it"
    )
  }

  func testFocusedFooterHintNamesDefault() {
    XCTAssertEqual(
      SimilarTasksBandPresentation.focusedFooterHint(defaultAction: .note),
      "↩ Add as note   ← → choose   ↑ ↓ rows   esc back"
    )
    XCTAssertEqual(
      SimilarTasksBandPresentation.focusedFooterHint(defaultAction: .discard),
      "↩ Discard mine   ← → choose   ↑ ↓ rows   esc back"
    )
  }
}
