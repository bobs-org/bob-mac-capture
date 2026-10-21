import XCTest

@testable import CaptureCore

final class SimilarTasksBandPresentationTests: XCTestCase {
  func testWarningAndClosedCapsulesAndLinkedHoldCapsules() {
    let duplicate = row(band: .possibleDuplicate, title: "Install new UPS battery")
    XCTAssertEqual(
      SimilarTasksBandPresentation.capsuleLabel(for: duplicate),
      "Possible duplicate"
    )

    let same = row(band: .sameTitle, title: "Install new UPS battery")
    XCTAssertEqual(SimilarTasksBandPresentation.capsuleLabel(for: same), "Same title")

    let similar = row(band: .similar, title: "Order a replacement")
    XCTAssertNil(SimilarTasksBandPresentation.capsuleLabel(for: similar))

    let closed = row(
      band: .closedDuplicate,
      title: "Close all open task beads",
      closed: CaptureRelatedClosed(status: "done", date: "2026-10-12", daysAgo: 8)
    )
    XCTAssertEqual(SimilarTasksBandPresentation.capsuleLabel(for: closed), "Done 8d ago")

    let related = SimilarTasksBandRow(
      itemIndex: 0,
      rowNumber: 1,
      match: match(title: "Install new UPS battery", band: .possibleDuplicate),
      linkedBy: .relation
    )
    XCTAssertEqual(SimilarTasksBandPresentation.capsuleLabel(for: related), "Related")
  }

  func testFoldedLineAndCommandHint() {
    let item = SimilarTasksBandItem(
      index: 0,
      mode: "task",
      rows: [
        row(band: .possibleDuplicate, title: "Install new UPS battery", number: 1),
        row(band: .similar, title: "Order a replacement", number: 2),
      ],
      overflowCount: 2,
      showsHeader: true
    )

    XCTAssertEqual(SimilarTasksBandPresentation.commandHint(rows: item.rows), "⌘1–2")
    XCTAssertEqual(SimilarTasksBandPresentation.overflowCapsule(count: 2), "+2")
    XCTAssertEqual(
      SimilarTasksBandPresentation.foldedLine(item: item),
      "⧉ 4 similar tasks · Possible duplicate: Install new UPS battery   ⌘1–2"
    )
  }

  func testRowAccessibilityLabelJoinsTitleCapsuleRouteAndStatus() {
    let duplicate = row(
      band: .possibleDuplicate,
      title: "Install new UPS battery",
      statusName: "Blocked",
      route: "dev"
    )
    XCTAssertEqual(
      SimilarTasksBandPresentation.rowAccessibilityLabel(duplicate),
      "Install new UPS battery, Possible duplicate, dev, Blocked"
    )

    let reading = SimilarTasksBandRow(
      itemIndex: 0,
      rowNumber: 1,
      match: match(
        title: "Read the capture paper",
        band: .similar,
        kind: "reading",
        statusName: "Ready",
        route: "ref"
      )
    )
    XCTAssertEqual(
      SimilarTasksBandPresentation.rowAccessibilityLabel(reading),
      "Read the capture paper, ref, Ready, Reading task"
    )
  }

  func testTitleRunsEmphasizeBobMatchedRanges() {
    let title = "Install new UPS battery"
    let runs = SimilarTasksBandPresentation.titleRuns(
      title: title,
      ranges: [CaptureRange(start: 12, end: 15), CaptureRange(start: 16, end: 23)]
    )
    XCTAssertEqual(runs.map(\.text), ["Install new ", "UPS", " ", "battery"])
    XCTAssertEqual(runs.map(\.emphasized), [false, true, false, true])
  }

  func testFoldBeforeScrollUsesFullHeightAndDoesNotOscillate() {
    let item = SimilarTasksBandItem(
      index: 0,
      mode: "task",
      rows: [
        row(band: .possibleDuplicate, title: "Install new UPS battery", number: 1),
        row(band: .similar, title: "Order a replacement", number: 2),
      ],
      overflowCount: 2,
      showsHeader: true
    )
    let full = SimilarTasksBandMetrics.fullHeight(item: item)
    XCTAssertEqual(full, 8 + 0.5 + 16 + 44)

    XCTAssertTrue(
      SimilarTasksBandMetrics.shouldFold(
        items: [item],
        currentlyFolded: false,
        measuredAuxiliaryHeight: 400,
        availableAuxiliaryHeight: 300
      )
    )

    let foldedHeight = SimilarTasksBandMetrics.currentHeight(item: item, folded: true)
    let measuredFolded = 400 - full + foldedHeight
    XCTAssertTrue(
      SimilarTasksBandMetrics.shouldFold(
        items: [item],
        currentlyFolded: true,
        measuredAuxiliaryHeight: measuredFolded,
        availableAuxiliaryHeight: 300
      )
    )
    XCTAssertFalse(
      SimilarTasksBandMetrics.shouldFold(
        items: [item],
        currentlyFolded: true,
        measuredAuxiliaryHeight: measuredFolded,
        availableAuxiliaryHeight: 500
      )
    )
  }

  func testSettledAnnouncementNamesASingleRowAndCountsMany() {
    let one = SimilarTasksBandItem(
      index: 0,
      mode: "task",
      rows: [row(band: .possibleDuplicate, title: "Install new UPS battery")],
      showsHeader: true
    )
    XCTAssertEqual(
      SimilarTasksBandPresentation.settledAnnouncement(items: [one]),
      "Similar task: Install new UPS battery"
    )

    let two = SimilarTasksBandItem(
      index: 0,
      mode: "task",
      rows: [
        row(band: .possibleDuplicate, title: "Install new UPS battery", number: 1),
        row(band: .similar, title: "Order a replacement", number: 2),
      ],
      showsHeader: true
    )
    XCTAssertEqual(
      SimilarTasksBandPresentation.settledAnnouncement(items: [two]),
      "2 similar tasks"
    )
    XCTAssertNil(SimilarTasksBandPresentation.settledAnnouncement(items: []))
  }

  private func match(
    title: String,
    band: CaptureRelatedBand,
    kind: String = "task",
    statusName: String = "Blocked",
    route: String = "dev",
    closed: CaptureRelatedClosed? = nil
  ) -> CaptureRelatedMatch {
    CaptureRelatedMatch(
      key: "\(route).md#\(title)",
      band: band,
      title: title,
      kind: kind,
      statusSymbol: closed == nil ? "?" : "x",
      statusName: statusName,
      closed: closed,
      route: route,
      locator: route,
      notePath: "\(route).md"
    )
  }

  private func row(
    band: CaptureRelatedBand,
    title: String,
    number: Int = 1,
    statusName: String = "Blocked",
    route: String = "dev",
    closed: CaptureRelatedClosed? = nil
  ) -> SimilarTasksBandRow {
    SimilarTasksBandRow(
      itemIndex: 0,
      rowNumber: number,
      match: match(
        title: title,
        band: band,
        statusName: statusName,
        route: route,
        closed: closed
      )
    )
  }
}
