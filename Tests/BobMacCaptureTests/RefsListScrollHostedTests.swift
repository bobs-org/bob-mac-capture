import AppKit
import Foundation
import RefsCore
import XCTest

@testable import BobMacCapture

/// Hosted reveal tests for the Refs list: the selected row stays fully
/// visible below the pinned section header, shows keep the last selected
/// row visible, and Ctrl-C resets the list to its top.
@MainActor
final class RefsListScrollHostedTests: XCTestCase {
  func testHostedShowKeepsLastSelectionVisible() {
    let harness = makeHostedHarness()
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)
    XCTAssertEqual(harness.model.selectedID, harness.model.listing.orderedIDs.first)

    harness.model.perform(.move(.last))
    waitForListOffset(in: harness.panel, model: harness.model) { $0 > 200 }
    let last = harness.model.listing.orderedIDs.last

    harness.model.prepareForPresentation()
    waitForListOffset(in: harness.panel, model: harness.model) { $0 > 200 }
    XCTAssertEqual(
      harness.model.selectedID, last,
      listDiagnostics(in: harness.panel, model: harness.model))
  }

  func testHostedHighlightsKeySessionRestoresListOffset() {
    let harness = makeHostedHarness()
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)

    harness.model.perform(.move(.last))
    waitForListOffset(in: harness.panel, model: harness.model) { $0 > 200 }
    let kept = harness.model.selectedID

    harness.model.prepareForPresentation(source: .highlightsTabs)
    harness.model.prepareForPresentation(source: .library)
    waitForListOffset(in: harness.panel, model: harness.model) { $0 > 200 }
    XCTAssertEqual(
      harness.model.selectedID, kept,
      listDiagnostics(in: harness.panel, model: harness.model))
  }

  func testHostedResetReturnsSelectionAndListToTop() {
    let harness = makeHostedHarness()
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)

    harness.model.perform(.move(.last))
    waitForListOffset(in: harness.panel, model: harness.model) { $0 > 200 }
    XCTAssertTrue(harness.model.perform(.resetView))

    waitForListOffset(in: harness.panel, model: harness.model) { $0 <= 0.5 }
    XCTAssertEqual(
      harness.model.selectedID, harness.model.listing.orderedIDs.first,
      listDiagnostics(in: harness.panel, model: harness.model))
  }

  func testHostedGrownContentAboveTopStillShowsTop() {
    let harness = makeHostedHarness()
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)
    waitForListOffset(in: harness.panel, model: harness.model) { $0 <= 0.5 }
    let oldFirst = harness.model.listing.orderedIDs.first
    XCTAssertNotNil(oldFirst)

    // A Just scanned section arrives above the old first row while the
    // scroll binding already holds the top edge.
    installScannedFixture(harness)
    harness.model.prepareForPresentation(source: .scanResults)
    waitForListOffset(in: harness.panel, model: harness.model) { $0 <= 0.5 }
    XCTAssertEqual(harness.model.listing.sections.first?.kind, .justScanned)
    XCTAssertNotEqual(harness.model.listing.orderedIDs.first, oldFirst)
    XCTAssertEqual(
      harness.model.selectedID, harness.model.listing.orderedIDs.first,
      listDiagnostics(in: harness.panel, model: harness.model))
  }

  func testHostedMovingUpKeepsTitlesBelowThePinnedHeader() {
    let harness = makeHostedHarness()
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)

    harness.model.perform(.move(.last))
    waitForListOffset(in: harness.panel, model: harness.model) { $0 > 200 }

    let first = harness.model.listing.orderedIDs.first
    for _ in 0..<70 {
      harness.model.perform(.move(.previous))
      waitForRevealCondition(in: harness.panel, model: harness.model)
      if harness.model.selectedID == first {
        break
      }
    }
    XCTAssertEqual(
      harness.model.selectedID, first,
      listDiagnostics(in: harness.panel, model: harness.model))
  }

  // MARK: - Hosted harness

  private struct HostedHarness {
    let model: RefsPanelModel
    let controller: RefsPanelController
    let panel: RefsPanel
  }

  private static let itemCount = 60

  private func makeItems() -> [RefItem] {
    (0..<Self.itemCount).map { index in
      let stem = "hosted_\(index)"
      let state: RefState =
        index < 10 ? .reading : (index < 20 ? .next : .ready)
      return RefItem(
        id: "ref/papers/\(stem).md",
        link: "[[ref/papers/\(stem)]]",
        rawTitle: "Hosted list row \(index)",
        stem: stem,
        kind: .paper,
        state: state,
        isBlocked: false,
        pdfPath: "lib/papers/\(stem).pdf"
      )
    }
  }

  private func makeHostedHarness() -> HostedHarness {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let library = RefsLibrary(
      fetcher: nil,
      snapshotStore: RefsSnapshotStore(
        fileURL: root.appendingPathComponent("refs-snapshot.json")
      ),
      openLogStore: RefsOpenLogStore(
        fileURL: root.appendingPathComponent("refs-open-log.json")
      ),
      newMarkStore: RefsNewMarkStore(
        fileURL: root.appendingPathComponent("refs-new-marks.json")
      ),
      vaultRoot: { root.appendingPathComponent("vault") },
      fileExists: { _ in true },
      spotlight: FakeSpotlight(),
      now: { Date() }
    )
    let model = RefsPanelModel(
      library: library,
      opener: FakeOpener(),
      highlights: FakeLocator(appURL: nil),
      pasteboard: FakePasteboard()
    )
    let items = makeItems()
    model.installForPreviews(
      items: items,
      signals: RefsSignals(),
      query: "",
      scope: .all,
      selectedID: nil,
      banner: nil,
      refreshState: .idle
    )
    if let first = model.listing.orderedIDs.first {
      model.perform(.select(id: first))
    }
    let kinds = model.listing.sections.compactMap(\.kind)
    XCTAssertTrue(kinds.count >= 2, "expected headed browse sections, got \(kinds)")
    let controller = RefsPanelController(model: model)
    let panel = controller.makePanelIfNeeded()
    panel.setFrame(
      NSRect(x: 80, y: 80, width: 1344, height: 798),
      display: true
    )
    panel.orderFrontRegardless()
    panel.contentView?.layoutSubtreeIfNeeded()
    return HostedHarness(model: model, controller: controller, panel: panel)
  }

  /// Reinstalls the same items with a fresh Just scanned mark over three
  /// rows below the top, so the next re-rank grows a section above the
  /// old top.
  private func installScannedFixture(_ harness: HostedHarness) {
    let items = makeItems()
    let scanned = Array(harness.model.listing.orderedIDs.suffix(3))
    XCTAssertEqual(scanned.count, 3)
    var signals = RefsSignals()
    signals.scan = RefsScanMark(ids: scanned, at: Date())
    harness.model.installForPreviews(
      items: items,
      signals: signals,
      query: "",
      scope: .all,
      selectedID: scanned.first,
      banner: nil,
      refreshState: .idle
    )
  }

  private func settle(_ panel: RefsPanel) {
    let deadline = Date().addingTimeInterval(1.5)
    while Date() < deadline {
      panel.contentView?.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
      if let scroll = listScroll(in: panel),
        let documentView = scroll.documentView,
        documentView.frame.height > scroll.contentView.bounds.height + 200
      {
        return
      }
    }
    XCTFail("hosted Refs list did not settle")
  }

  private func listScroll(in panel: RefsPanel) -> NSScrollView? {
    let inspector = RefsPanelController.findInspectorScrollView(
      in: panel.contentView)
    let scrolls = RefsPanelController.scrollViews(in: panel.contentView)
    return scrolls.first { $0 !== inspector }
  }

  private func listOffset(in panel: RefsPanel) -> CGFloat {
    guard let scroll = listScroll(in: panel) else {
      return 0
    }
    return scroll.documentVisibleRect.origin.y
  }

  private func listDiagnostics(in panel: RefsPanel, model: RefsPanelModel) -> String {
    guard let scroll = listScroll(in: panel),
      let documentView = scroll.documentView
    else {
      return "lookup=nil selected=\(model.selectedID ?? "nil")"
    }
    let clip = scroll.contentView
    let offset = scroll.documentVisibleRect.origin.y
    var spanDescription = "span=nil"
    var targetDescription = "target=nil"
    if let selected = model.selectedID,
      let span = RefsListScrollPolicy.rowSpan(for: selected, in: model.listing)
    {
      spanDescription =
        "span(top=\(span.top) bottom=\(span.bottom) inset=\(span.pinnedInset))"
      let target = RefsListScrollPolicy.reveal(
        selected,
        in: model.listing,
        offset: offset,
        viewportHeight: clip.bounds.height
      )
      targetDescription = "target=\(String(describing: target))"
    }
    return
      "clip=\(clip.bounds) docHeight=\(documentView.frame.height) "
      + "offset=\(offset) selected=\(model.selectedID ?? "nil") "
      + "\(spanDescription) \(targetDescription)"
  }

  private func waitForListOffset(
    in panel: RefsPanel,
    model: RefsPanelModel,
    _ predicate: (CGFloat) -> Bool
  ) {
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
      panel.contentView?.layoutSubtreeIfNeeded()
      if predicate(listOffset(in: panel)) {
        return
      }
    }
    XCTFail(
      "list offset did not reach the expected range; "
        + listDiagnostics(in: panel, model: model))
  }

  /// Waits until the selected row's title clears the pinned header
  /// band: its top sits at or below the offset plus the header inset.
  private func waitForRevealCondition(
    in panel: RefsPanel,
    model: RefsPanelModel
  ) {
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
      panel.contentView?.layoutSubtreeIfNeeded()
      guard let selected = model.selectedID,
        let span = RefsListScrollPolicy.rowSpan(for: selected, in: model.listing)
      else {
        XCTFail(
          "selected row has no span; "
            + listDiagnostics(in: panel, model: model))
        return
      }
      if span.top >= listOffset(in: panel) + span.pinnedInset - 0.5 {
        return
      }
    }
    XCTFail(
      "selected row stayed under the pinned header; "
        + listDiagnostics(in: panel, model: model))
  }
}
