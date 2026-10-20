import AppKit
import Foundation
import RefsCore
import XCTest

@testable import BobMacCapture

/// Hosted proof that a cross-section re-rank rebuilds moved rows:
/// ⌘0 applies the first Newest row's highlight and caption instead
/// of keeping the ranked listing's stale paint.
@MainActor
final class RefsListRowRefreshHostedTests: XCTestCase {
  func testNewestRerankRefreshesMovedRowHighlightAndCaption() {
    let harness = makeHostedHarness()
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)

    let xID = Self.xID
    let yID = Self.yID
    let r0ID = Self.r0ID
    let probe = harness.probe
    let today = day(harness.now, offset: 0)

    waitUntil(
      in: harness.panel,
      diagnostics: probeDiagnostics(
        model: harness.model, probe: probe, ids: [r0ID, xID, yID])
    ) {
      harness.model.selectedID == r0ID
        && probe.rows[xID]?.isSelected == false
        && probe.rows[xID]?.section == .ready
    }

    XCTAssertEqual(harness.model.listing.orderedIDs.first, r0ID)
    XCTAssertNotEqual(harness.model.listing.orderedIDs.first, xID)

    XCTAssertTrue(harness.model.perform(.toggleNewest))
    XCTAssertEqual(harness.model.selectedID, xID)
    let newestSection = harness.model.listing.sectionKind(for: xID)
    let expectedPhrase = RefsCaption.datePhrase(
      for: harness.xItem, in: newestSection, signals: harness.model.signals
    )
    let expectedTime = RefsCaption.shortTime(
      harness.xAddedAt, calendar: harness.calendar
    )
    XCTAssertTrue(expectedPhrase.contains("added "))
    XCTAssertTrue(expectedPhrase.contains(expectedTime))

    waitUntil(
      in: harness.panel,
      diagnostics: probeDiagnostics(
        model: harness.model, probe: probe, ids: [xID, yID, r0ID])
    ) {
      guard let state = probe.rows[xID] else { return false }
      return state.isSelected
        && isTodayAdded(state.section, today: today)
        && state.caption.contains(expectedPhrase)
    }

    XCTAssertTrue(harness.model.perform(.toggleNewest))
    waitUntil(
      in: harness.panel,
      diagnostics: probeDiagnostics(
        model: harness.model, probe: probe, ids: [xID, r0ID])
    ) {
      probe.rows[xID]?.isSelected == false
        && probe.rows[xID]?.section == .ready
        && probe.rows[r0ID]?.isSelected == true
    }

    XCTAssertTrue(harness.model.perform(.toggleNewest))
    waitUntil(
      in: harness.panel,
      diagnostics: probeDiagnostics(
        model: harness.model, probe: probe, ids: [xID, yID])
    ) {
      probe.rows[xID]?.isSelected == true
        && isTodayAdded(probe.rows[xID]?.section, today: today)
    }

    harness.model.setQuery("bravo")
    XCTAssertEqual(harness.model.selectedID, yID)
    waitUntil(
      in: harness.panel,
      diagnostics: probeDiagnostics(
        model: harness.model, probe: probe, ids: [yID, xID])
    ) {
      probe.rows[yID]?.isSelected == true
        && isTodayAdded(probe.rows[yID]?.section, today: today)
    }
  }

  // MARK: - Hosted harness

  private struct HostedHarness {
    let model: RefsPanelModel
    let controller: RefsPanelController
    let panel: RefsPanel
    let probe: RefsRowRenderProbe
    let now: Date
    let calendar: Calendar
    let xItem: RefItem
    let xAddedAt: Date
  }

  private static let r0ID = "ref/papers/reading_0.md"
  private static let xID = "ref/papers/alpha_newest.md"
  private static let yID = "ref/papers/bravo_newest.md"
  private static let fillerCount = 40

  private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar
  }

  private func fixedNow() -> Date {
    let calendar = utcCalendar()
    return calendar.date(
      from: DateComponents(
        year: 2026, month: 10, day: 8, hour: 12
      )) ?? Date()
  }

  private func day(_ date: Date, offset: Int) -> RefDay {
    let calendar = utcCalendar()
    let shifted =
      calendar.date(
        byAdding: .day, value: offset, to: date
      ) ?? date
    let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
    return RefDay(
      year: parts.year ?? 2026, month: parts.month ?? 10, day: parts.day ?? 8)
  }

  private func time(_ date: Date, hour: Int, minute: Int) -> Date {
    let calendar = utcCalendar()
    var parts = calendar.dateComponents([.year, .month, .day], from: date)
    parts.hour = hour
    parts.minute = minute
    return calendar.date(from: parts) ?? date
  }

  private func makeItem(
    stem: String,
    title: String,
    state: RefState,
    added: RefDay?,
    addedAt: Date? = nil
  ) -> RefItem {
    RefItem(
      id: "ref/papers/\(stem).md",
      link: "[[ref/papers/\(stem)]]",
      rawTitle: title,
      stem: stem,
      kind: .paper,
      state: state,
      isBlocked: false,
      pdfPath: "lib/papers/\(stem).pdf",
      added: added,
      addedAt: addedAt,
      annotationCount: 1
    )
  }

  private func makeHostedHarness() -> HostedHarness {
    let now = fixedNow()
    let calendar = utcCalendar()
    let xAddedAt = time(now, hour: 9, minute: 41)
    let yAddedAt = time(now, hour: 8, minute: 0)
    let today = day(now, offset: 0)
    let monthAgo = day(now, offset: -40)

    var items: [RefItem] = (0..<3).map { index in
      makeItem(
        stem: "reading_\(index)",
        title: "Reading row \(index)",
        state: .reading,
        added: monthAgo
      )
    }
    let xItem = makeItem(
      stem: "alpha_newest",
      title: "Alpha newest",
      state: .ready,
      added: today,
      addedAt: xAddedAt
    )
    let yItem = makeItem(
      stem: "bravo_newest",
      title: "Bravo newest",
      state: .ready,
      added: today,
      addedAt: yAddedAt
    )
    items.append(xItem)
    items.append(yItem)
    items.append(
      contentsOf: (0..<Self.fillerCount).map { index in
        makeItem(
          stem: "filler_\(index)",
          title: "Filler row \(index)",
          state: .ready,
          added: day(now, offset: -(2 + (index % 29)))
        )
      }
    )

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
      now: { now }
    )
    let model = RefsPanelModel(
      library: library,
      opener: FakeOpener(),
      highlights: FakeLocator(appURL: nil),
      pasteboard: FakePasteboard()
    )
    let signals = RefsSignals(now: now, calendar: calendar)
    model.installForPreviews(
      items: items,
      signals: signals,
      query: "",
      scope: .all,
      selectedID: nil,
      banner: nil,
      refreshState: .idle
    )
    if let first = model.listing.orderedIDs.first {
      model.perform(.select(id: first))
    }
    let probe = RefsRowRenderProbe()
    model.rowRenderProbeForTests = probe
    let controller = RefsPanelController(model: model)
    let panel = controller.makePanelIfNeeded()
    panel.setFrame(
      NSRect(x: 80, y: 80, width: 1344, height: 798),
      display: true
    )
    panel.orderFrontRegardless()
    panel.contentView?.layoutSubtreeIfNeeded()
    return HostedHarness(
      model: model,
      controller: controller,
      panel: panel,
      probe: probe,
      now: now,
      calendar: calendar,
      xItem: xItem,
      xAddedAt: xAddedAt
    )
  }

  private func isTodayAdded(_ section: RefsSectionKind?, today: RefDay) -> Bool {
    if case .added(let group) = section {
      return group.id == "day-\(today.isoString)"
    }
    return false
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

  private func probeDiagnostics(
    model: RefsPanelModel,
    probe: RefsRowRenderProbe,
    ids: [String]
  ) -> String {
    let entries = ids.map { id in
      "\(id)=\(String(describing: probe.rows[id]))"
    }.joined(separator: " ")
    return
      "selected=\(model.selectedID ?? "nil") "
      + "order=\(String(describing: model.listing.order)) "
      + "listing=\(model.listing.orderedIDs.prefix(8).joined(separator: ",")) "
      + entries
  }

  private func waitUntil(
    in panel: RefsPanel,
    timeout: TimeInterval = 2,
    diagnostics: @autoclosure () -> String,
    _ predicate: () -> Bool
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      panel.contentView?.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
      if predicate() {
        return
      }
    }
    XCTFail(diagnostics())
  }
}
