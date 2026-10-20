import AppKit
import Foundation
import RefsCore
import XCTest

@testable import BobMacCapture

/// Planner math for half-viewport inspector scrolling, plus a hosted
/// view test that drives the routed Control-D/Control-U path while search is
/// first responder.
@MainActor
final class RefsInspectorScrollTests: XCTestCase {
  func testHalfViewportStepsAndReverses() {
    var planner = RefsInspectorScrollPlanner(geometry: Self.overflow)
    XCTAssertEqual(planner.command(.down), 200)
    XCTAssertEqual(planner.command(.down), 400)
    XCTAssertEqual(planner.command(.up), 200)
    XCTAssertEqual(planner.offset, 200)
  }

  func testClampsAtTopAndBottom() {
    var planner = RefsInspectorScrollPlanner(geometry: Self.overflow)
    XCTAssertEqual(planner.command(.up), 0)
    XCTAssertEqual(planner.command(.up), 0)
    for _ in 0..<20 {
      _ = planner.command(.down)
    }
    XCTAssertEqual(planner.offset, 1000)
    XCTAssertEqual(planner.command(.down), 1000)
  }

  func testFittingContentStaysAtZero() {
    var planner = RefsInspectorScrollPlanner(
      geometry: RefsInspectorScrollGeometry(
        offsetY: 0,
        contentHeight: 400,
        viewportHeight: 400,
        topInset: 0,
        bottomInset: 0
      )
    )
    XCTAssertEqual(planner.command(.down), 0)
    XCTAssertEqual(planner.command(.up), 0)
    XCTAssertEqual(planner.offset, 0)
  }

  func testRestoreTargetWaitsClampsAndHonorsInsets() {
    let short = RefsInspectorScrollGeometry(
      offsetY: 0,
      contentHeight: 500,
      viewportHeight: 400,
      topInset: 0,
      bottomInset: 0
    )
    XCTAssertNil(short.restoreTarget(offset: 300, contentIsFinal: false))
    XCTAssertEqual(short.restoreTarget(offset: 300, contentIsFinal: true), 100)

    let tall = RefsInspectorScrollGeometry(
      offsetY: 0,
      contentHeight: 900,
      viewportHeight: 400,
      topInset: 0,
      bottomInset: 0
    )
    XCTAssertEqual(tall.restoreTarget(offset: 300, contentIsFinal: false), 300)
    XCTAssertNil(RefsInspectorScrollGeometry.invalid.restoreTarget(
      offset: 300,
      contentIsFinal: true
    ))

    let inset = RefsInspectorScrollGeometry(
      offsetY: 0,
      contentHeight: 1400,
      viewportHeight: 400,
      topInset: 12,
      bottomInset: 8
    )
    XCTAssertEqual(inset.restoreTarget(offset: -30, contentIsFinal: true), -12)
    XCTAssertEqual(inset.restoreTarget(offset: 2_000, contentIsFinal: true), 1_008)
  }

  func testCommandAfterUserOffsetUsesMeasuredPosition() {
    var planner = RefsInspectorScrollPlanner(geometry: Self.overflow)
    planner.beginUserScroll(at: 350)
    XCTAssertEqual(planner.command(.down), 550)
    planner.beginUserScroll(at: 50)
    XCTAssertEqual(planner.command(.up), 0)
  }

  func testViewportResizeClampsOutstandingTarget() {
    var planner = RefsInspectorScrollPlanner(geometry: Self.overflow)
    XCTAssertEqual(planner.command(.down), 200)
    XCTAssertEqual(planner.command(.down), 400)
    XCTAssertEqual(planner.command(.down), 600)
    XCTAssertEqual(planner.command(.down), 800)
    let clamped = planner.applyGeometry(
      RefsInspectorScrollGeometry(
        offsetY: 0,
        contentHeight: 1400,
        viewportHeight: 900,
        topInset: 0,
        bottomInset: 0
      )
    )
    XCTAssertEqual(clamped, 500)
    XCTAssertEqual(planner.offset, 500)
  }

  func testInsetAwareBounds() {
    let geometry = RefsInspectorScrollGeometry(
      offsetY: 0,
      contentHeight: 1400,
      viewportHeight: 400,
      topInset: 12,
      bottomInset: 8
    )
    XCTAssertEqual(geometry.minOffset, -12)
    XCTAssertEqual(geometry.maxOffset, 1008)
    var planner = RefsInspectorScrollPlanner(geometry: geometry)
    planner.beginUserScroll(at: -12)
    XCTAssertEqual(planner.command(.up), -12)
    XCTAssertEqual(planner.command(.down), 188)
    planner.beginUserScroll(at: 1008)
    XCTAssertEqual(planner.command(.down), 1008)
  }

  func testInvalidGeometryIsNoOp() {
    var planner = RefsInspectorScrollPlanner()
    XCTAssertNil(planner.command(.down))
    XCTAssertNil(planner.command(.up))
    XCTAssertNil(
      planner.applyGeometry(
        RefsInspectorScrollGeometry(
          offsetY: 10,
          contentHeight: 100,
          viewportHeight: 0,
          topInset: 0,
          bottomInset: 0
        )
      )
    )
    XCTAssertNil(planner.command(.down))
  }

  func testRapidCommandsAccumulateBeforeGeometryCatchesUp() {
    var planner = RefsInspectorScrollPlanner(geometry: Self.overflow)
    XCTAssertEqual(planner.command(.down), 200)
    XCTAssertEqual(planner.command(.down), 400)
    XCTAssertEqual(planner.command(.up), 200)
    // Delayed geometry still reports the old offset.
    XCTAssertNil(
      planner.applyGeometry(
        RefsInspectorScrollGeometry(
          offsetY: 0,
          contentHeight: 1400,
          viewportHeight: 400,
          topInset: 0,
          bottomInset: 0
        )
      )
    )
    XCTAssertEqual(planner.offset, 200)
    XCTAssertEqual(planner.command(.down), 400)
  }

  func testSameReferenceHydrationKeepsOffset() {
    var planner = RefsInspectorScrollPlanner(geometry: Self.overflow)
    XCTAssertEqual(planner.command(.down), 200)
    XCTAssertNil(
      planner.applyGeometry(
        RefsInspectorScrollGeometry(
          offsetY: 200,
          contentHeight: 1800,
          viewportHeight: 400,
          topInset: 0,
          bottomInset: 0
        )
      )
    )
    XCTAssertEqual(planner.offset, 200)
    XCTAssertEqual(planner.command(.down), 400)
  }

  func testResetDropsPendingWithoutReplay() {
    var planner = RefsInspectorScrollPlanner(geometry: Self.overflow)
    XCTAssertEqual(planner.command(.down), 200)
    XCTAssertEqual(planner.command(.down), 400)
    planner.reset()
    XCTAssertNil(planner.pendingTarget)
    planner.applyGeometry(Self.overflow)
    XCTAssertEqual(planner.command(.down), 200)
    XCTAssertEqual(planner.offset, 200)
  }

  func testIsAtBottom() {
    XCTAssertTrue(Self.overflowAtBottom.isAtBottom())
    XCTAssertTrue(Self.overflowAtBottom.isAtBottom(tolerance: 1))
    XCTAssertFalse(Self.overflow.isAtBottom())
    // Within tolerance counts as the bottom.
    let nearBottom = RefsInspectorScrollGeometry(
      offsetY: 999.5,
      contentHeight: 1400,
      viewportHeight: 400,
      topInset: 0,
      bottomInset: 0
    )
    XCTAssertTrue(nearBottom.isAtBottom())
    XCTAssertFalse(nearBottom.isAtBottom(tolerance: 0.2))
    // Content that fits the viewport is always at the bottom.
    let fitting = RefsInspectorScrollGeometry(
      offsetY: 0,
      contentHeight: 400,
      viewportHeight: 400,
      topInset: 0,
      bottomInset: 0
    )
    XCTAssertTrue(fitting.isAtBottom())
    XCTAssertFalse(RefsInspectorScrollGeometry.invalid.isAtBottom())
  }

  func testRevealTarget() {
    // Content that fits gives nil: nothing to scroll to.
    let fitting = RefsInspectorScrollGeometry(
      offsetY: 0,
      contentHeight: 400,
      viewportHeight: 400,
      topInset: 0,
      bottomInset: 0
    )
    XCTAssertNil(
      RefsInspectorScrollPlanner.revealTarget(
        geometry: fitting,
        batchTop: 300,
        context: 24
      ))
    // A short batch pins to the new maxOffset.
    let short = RefsInspectorScrollGeometry(
      offsetY: 800,
      contentHeight: 1600,
      viewportHeight: 400,
      topInset: 0,
      bottomInset: 0
    )
    XCTAssertEqual(
      RefsInspectorScrollPlanner.revealTarget(
        geometry: short,
        batchTop: 1500,
        context: 24
      ),
      1200
    )
    // A tall batch is capped at batchTop − context.
    let tall = RefsInspectorScrollGeometry(
      offsetY: 1000,
      contentHeight: 3000,
      viewportHeight: 400,
      topInset: 0,
      bottomInset: 0
    )
    XCTAssertEqual(
      RefsInspectorScrollPlanner.revealTarget(
        geometry: tall,
        batchTop: 1400,
        context: 24
      ),
      1376
    )
    // Never upward: at or above the target gives nil.
    XCTAssertNil(
      RefsInspectorScrollPlanner.revealTarget(
        geometry: tall,
        batchTop: 900,
        context: 24
      ))
    XCTAssertNil(
      RefsInspectorScrollPlanner.revealTarget(
        geometry: .invalid,
        batchTop: 1400,
        context: 24
      ))
  }

  func testContainsRow() {
    let geometry = RefsInspectorScrollGeometry(
      offsetY: 100,
      contentHeight: 1400,
      viewportHeight: 400,
      topInset: 0,
      bottomInset: 0
    )
    // Fully inside, including the exact edges.
    XCTAssertTrue(geometry.containsRow(top: 120, bottom: 140))
    XCTAssertTrue(geometry.containsRow(top: 100, bottom: 500))
    // Partially visible is not contained.
    XCTAssertFalse(geometry.containsRow(top: 80, bottom: 120))
    XCTAssertFalse(geometry.containsRow(top: 480, bottom: 520))
    // Fully outside.
    XCTAssertFalse(geometry.containsRow(top: 0, bottom: 50))
    XCTAssertFalse(geometry.containsRow(top: 600, bottom: 700))
    // Tolerance admits a row one point proud of the viewport.
    XCTAssertTrue(geometry.containsRow(top: 99, bottom: 501))
    XCTAssertFalse(
      geometry.containsRow(top: 99, bottom: 501, tolerance: 0)
    )
    XCTAssertFalse(
      geometry.containsRow(top: 98, bottom: 140)
    )
    // Invalid geometry never contains.
    XCTAssertFalse(
      RefsInspectorScrollGeometry.invalid.containsRow(top: 0, bottom: 10)
    )
    // Non-finite inputs never contain.
    XCTAssertFalse(
      geometry.containsRow(top: .infinity, bottom: 140)
    )
  }

  func testHostedControlDUScrollsInspectorWhileSearchKeepsFocus() {
    let harness = makeHostedHarness()
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)
    focusSearch(harness)
    XCTAssertNotNil(RefsPanelController.findInspectorScrollView(in: harness.panel.contentView))
    let field = tryUnwrapFilter(harness.panel)
    let editor = field.currentEditor() as? NSTextView
    let caret = editor?.selectedRange()
    let selected = harness.model.selectedID
    let query = harness.model.query
    let listOffsetBefore = listOffset(in: harness.panel)
    let start = inspectorOffset(in: harness.panel)

    XCTAssertNil(
      harness.controller.processKeyEvent(
        keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
      )
    )
    waitForInspectorOffset(in: harness.panel) { $0 > start + 8 }

    let afterDown = inspectorOffset(in: harness.panel)
    XCTAssertGreaterThan(afterDown, start, inspectorDiagnostics(in: harness.panel))
    XCTAssertEqual(listOffset(in: harness.panel), listOffsetBefore, accuracy: 1)
    XCTAssertEqual(harness.model.selectedID, selected)
    XCTAssertEqual(harness.model.query, query)
    XCTAssertEqual((field.currentEditor() as? NSTextView)?.selectedRange(), caret)
    XCTAssertTrue(field.holdsFirstResponder)

    XCTAssertNil(
      harness.controller.processKeyEvent(
        keyEvent(keyCode: Self.uKey, modifiers: .control, characters: "u")
      )
    )
    waitForInspectorOffset(in: harness.panel) { $0 < afterDown - 8 }
    XCTAssertLessThan(
      inspectorOffset(in: harness.panel), afterDown, inspectorDiagnostics(in: harness.panel))
    XCTAssertEqual(listOffset(in: harness.panel), listOffsetBefore, accuracy: 1)
    XCTAssertEqual(harness.model.selectedID, selected)
    XCTAssertEqual(harness.model.query, query)
    XCTAssertEqual((field.currentEditor() as? NSTextView)?.selectedRange(), caret)
    XCTAssertTrue(field.holdsFirstResponder)
  }

  func testHostedShowKeepsPreviewOffsetAndMovesFilterCaretToEnd() {
    let harness = makeHostedHarness()
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)
    focusSearch(harness)

    for _ in 0..<3 {
      XCTAssertNil(
        harness.controller.processKeyEvent(
          keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
        )
      )
    }
    waitForInspectorOffset(in: harness.panel) { $0 > 100 }
    let rememberedOffset = inspectorOffset(in: harness.panel)

    harness.controller.hide()
    harness.controller.show()
    waitForInspectorSettled(in: harness.panel, around: rememberedOffset, tolerance: 1)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))

    let field = tryUnwrapFilter(harness.panel)
    let editor = field.currentEditor() as? NSTextView
    XCTAssertEqual(
      editor?.selectedRange().location,
      (harness.model.query as NSString).length
    )
    XCTAssertTrue(field.holdsFirstResponder)

    let beforeCard = inspectorOffset(in: harness.panel)
    XCTAssertTrue(harness.model.perform(.showCopyCard))
    harness.panel.contentView?.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))
    XCTAssertTrue(harness.model.perform(.escape))
    waitForInspectorSettled(in: harness.panel, around: beforeCard, tolerance: 1)
  }

  func testHostedControlZResetsPreviewAndQuery() {
    let harness = makeHostedHarness()
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)
    focusSearch(harness)
    for _ in 0..<3 {
      _ = harness.controller.processKeyEvent(
        keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
      )
    }
    waitForInspectorOffset(in: harness.panel) { $0 > 100 }

    XCTAssertNil(
      harness.controller.processKeyEvent(
        keyEvent(keyCode: Self.zKey, modifiers: .control, characters: "z")
      )
    )
    waitForInspectorOffset(in: harness.panel) { $0 <= 0.5 }
    XCTAssertEqual(harness.model.query, "")
    XCTAssertEqual(harness.model.selectedID, harness.model.listing.orderedIDs.first)
  }

  func testHostedControlDConsumesAtBoundaryAndWhenInspectorHidden() {
    let wide = makeHostedHarness(width: 880, height: 560)
    defer { wide.panel.orderOut(nil) }
    settle(wide.panel)
    focusSearch(wide)
    XCTAssertNotNil(RefsPanelController.findInspectorScrollView(in: wide.panel.contentView))
    for _ in 0..<40 {
      XCTAssertNil(
        wide.controller.processKeyEvent(
          keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
        )
      )
    }
    let atBottom = inspectorOffset(in: wide.panel)
    XCTAssertNil(
      wide.controller.processKeyEvent(
        keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
      )
    )
    XCTAssertEqual(
      inspectorOffset(in: wide.panel), atBottom, accuracy: 2, inspectorDiagnostics(in: wide.panel))

    let narrow = makeHostedHarness(width: 700)
    defer { narrow.panel.orderOut(nil) }
    settle(narrow.panel)
    focusSearch(narrow)
    XCTAssertNil(RefsPanelController.findInspectorScrollView(in: narrow.panel.contentView))
    let listBefore = listOffset(in: narrow.panel)
    let selected = narrow.model.selectedID
    XCTAssertNil(
      narrow.controller.processKeyEvent(
        keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
      )
    )
    XCTAssertEqual(listOffset(in: narrow.panel), listBefore, accuracy: 1)
    XCTAssertEqual(narrow.model.selectedID, selected)
    XCTAssertEqual(narrow.model.query, "Overflow")
  }

  func testHostedHandleKeyDownPassesThroughWhenPanelIsNotKey() {
    let harness = makeHostedHarness()
    defer { harness.panel.orderOut(nil) }
    let event = keyEvent(
      keyCode: Self.dKey,
      modifiers: .control,
      characters: "d"
    )
    XCTAssertFalse(harness.panel.isKeyWindow)
    XCTAssertTrue(harness.controller.handleKeyDown(event) === event)
  }

  func testHostedNotesAboveBottomScrollsHalfPageAndRevealsNothing() {
    let harness = makeHostedHarness(highlights: Self.eightNotes())
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)
    focusSearch(harness)
    let selected = tryUnwrapSelected(harness)
    XCTAssertEqual(harness.model.inspectorNotesPage(for: selected).generation, 0)
    let start = inspectorOffset(in: harness.panel)

    XCTAssertNil(
      harness.controller.processKeyEvent(
        keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
      )
    )
    waitForInspectorOffset(in: harness.panel) { $0 > start + 8 }

    XCTAssertEqual(harness.model.inspectorNotesPage(for: selected).generation, 0)
    XCTAssertEqual(
      harness.model.inspectorNotesPage(for: selected).visibleCount(
        total: 8
      ),
      5
    )
  }

  func testHostedDisclosureVisibleAboveBottomReveals() {
    let harness = makeHostedHarness(highlights: Self.eightNotes())
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)
    focusSearch(harness)
    let selected = tryUnwrapSelected(harness)
    XCTAssertEqual(harness.model.inspectorNotesPage(for: selected).generation, 0)
    // Rest just above the bottom: the footer below the disclosure
    // row keeps the offset off the bottom while the row stays
    // fully on screen.
    scrollInspectorAboveBottom(in: harness.panel, by: 8)
    let measured = tryUnwrapMeasured(harness.panel)
    XCTAssertLessThan(
      measured.geometry.offsetY, measured.geometry.maxOffset - 1)
    XCTAssertTrue(
      RefsPanelController.isDisclosureRowFullyVisible(
        measured: measured,
        in: harness.panel.contentView
      ))

    XCTAssertNil(
      harness.controller.processKeyEvent(
        keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
      )
    )
    XCTAssertEqual(
      harness.model.inspectorNotesPage(for: selected).visibleCount(total: 8),
      8
    )
    XCTAssertEqual(
      harness.model.inspectorNotesPage(for: selected).generation,
      1
    )
    XCTAssertTrue(tryUnwrapFilter(harness.panel).holdsFirstResponder)
  }

  func testHostedNotesAtBottomRevealsTheRemainingEntries() {
    let harness = makeHostedHarness(highlights: Self.eightNotes())
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)
    focusSearch(harness)
    let selected = tryUnwrapSelected(harness)
    let query = harness.model.query
    scrollInspectorToBottom(in: harness.panel)
    let oldBottom = inspectorOffset(in: harness.panel)

    XCTAssertNil(
      harness.controller.processKeyEvent(
        keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
      )
    )
    XCTAssertEqual(
      harness.model.inspectorNotesPage(for: selected).visibleCount(total: 8),
      8
    )
    XCTAssertEqual(
      harness.model.inspectorNotesPage(for: selected).generation,
      1
    )
    waitForInspectorOffset(in: harness.panel) { $0 > oldBottom + 2 }
    let newBottom = inspectorOffset(in: harness.panel)
    waitForInspectorSettled(in: harness.panel, around: newBottom, tolerance: 2)

    XCTAssertEqual(harness.model.selectedID, selected)
    XCTAssertEqual(harness.model.query, query)
    XCTAssertTrue(tryUnwrapFilter(harness.panel).holdsFirstResponder)
  }

  func testHostedShortContentRevealsWithNoOffsetChange() throws {
    let harness = makeHostedHarness(
      highlights: Self.eightNotes(),
      shortContent: true,
      notesPageSize: 1
    )
    defer { harness.panel.orderOut(nil) }
    settleShort(harness.panel)
    focusSearch(harness)
    let selected = tryUnwrapSelected(harness)
    let before = inspectorOffset(in: harness.panel)
    try assertInspectorFits(harness.panel)

    XCTAssertNil(
      harness.controller.processKeyEvent(
        keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
      )
    )
    XCTAssertEqual(
      harness.model.inspectorNotesPage(for: selected).visibleCount(total: 8),
      2
    )
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))
    try assertInspectorFits(harness.panel)
    XCTAssertEqual(
      inspectorOffset(in: harness.panel),
      before,
      accuracy: 2,
      inspectorDiagnostics(in: harness.panel)
    )
  }

  func testHostedRevealKeepsDocumentHeightWhileImageBitmapsLoad() {
    assertHostedImageRevealStable(
      width: 1344,
      height: 798,
      failDecode: false,
      pinAboveBottom: false
    )
  }

  func testHostedCompactRevealKeepsDocumentHeightWhileImageBitmapsLoad() {
    assertHostedImageRevealStable(
      width: 880,
      height: 560,
      failDecode: false,
      pinAboveBottom: false
    )
  }

  func testHostedRevealKeepsDocumentHeightWhenImageDecodeFails() {
    assertHostedImageRevealStable(
      width: 1344,
      height: 798,
      failDecode: true,
      pinAboveBottom: false
    )
  }

  func testHostedDisclosureVisibleAboveBottomRevealsHeldImages() {
    assertHostedImageRevealStable(
      width: 1344,
      height: 798,
      failDecode: false,
      pinAboveBottom: true
    )
  }

  func testHostedTwoRapidRevealsStackTwoPages() {
    let harness = makeHostedHarness(highlights: Self.thirteenNotes())
    defer { harness.panel.orderOut(nil) }
    settle(harness.panel)
    focusSearch(harness)
    let selected = tryUnwrapSelected(harness)
    scrollInspectorToBottom(in: harness.panel)

    XCTAssertNil(
      harness.controller.processKeyEvent(
        keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
      )
    )
    XCTAssertNil(
      harness.controller.processKeyEvent(
        keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
      )
    )
    XCTAssertEqual(
      harness.model.inspectorNotesPage(for: selected).visibleCount(total: 13),
      13
    )
    XCTAssertEqual(
      harness.model.inspectorNotesPage(for: selected).generation,
      2
    )
  }

  /// Reveal page two while the bitmap is held, record height, then
  /// release and assert the reserved frame did not jump.
  private func assertHostedImageRevealStable(
    width: CGFloat,
    height: CGFloat,
    failDecode: Bool,
    pinAboveBottom: Bool
  ) {
    let images = StubAnnotationImages()
    let metrics = RefsImageMetrics(pixelWidth: 800, pixelHeight: 400)
    images.metricsByLastComponent = ["crop.jpg": metrics]
    if !failDecode {
      images.imageByLastComponent = [
        "crop.jpg": makeTestImage(
          size: NSSize(width: 800, height: 400),
          color: .systemOrange
        )
      ]
    }
    images.beginHoldingImages()
    let highlights =
      Self.eightNotes().prefix(5).map { $0 }
      + [
        RefsShowAnnotation(
          pageLabel: "Page 6",
          kind: "image",
          asset: "ref/docs/crop.jpg"
        ),
        RefsShowAnnotation(
          pageLabel: "Page 7",
          kind: "highlight",
          quote: "A later quote on the revealed page."
        ),
      ]
    let harness = makeHostedHarness(
      width: width,
      height: height,
      highlights: highlights,
      notesPageSize: 5,
      imageProvider: images,
      imageMetrics: ["ref/docs/crop.jpg": metrics]
    )
    defer {
      images.releaseHeldImages()
      harness.panel.orderOut(nil)
    }
    settle(harness.panel)
    focusSearch(harness)
    let selected = tryUnwrapSelected(harness)
    if pinAboveBottom {
      scrollInspectorAboveBottom(in: harness.panel, by: 8)
      let measured = tryUnwrapMeasured(harness.panel)
      XCTAssertLessThan(
        measured.geometry.offsetY, measured.geometry.maxOffset - 1)
      XCTAssertTrue(
        RefsPanelController.isDisclosureRowFullyVisible(
          measured: measured,
          in: harness.panel.contentView
        ))
    } else {
      scrollInspectorToBottom(in: harness.panel)
    }

    XCTAssertNil(
      harness.controller.processKeyEvent(
        keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
      )
    )
    XCTAssertEqual(
      harness.model.inspectorNotesPage(for: selected).visibleCount(total: 7),
      7
    )
    XCTAssertEqual(
      harness.model.inspectorNotesPage(for: selected).generation,
      1
    )
    XCTAssertTrue(
      waitUntilRunLoop(timeout: 1.5) {
        revealAnchor(in: harness.panel, generation: 1) != nil
      }
    )
    harness.panel.contentView?.layoutSubtreeIfNeeded()
    let heightBefore = inspectorDocumentHeight(in: harness.panel)
    XCTAssertGreaterThan(heightBefore, 0)
    XCTAssertTrue(
      waitUntilRunLoop(timeout: 1.5) { images.imageURLCount >= 1 }
    )

    images.releaseHeldImages()
    XCTAssertTrue(
      waitUntilRunLoop(timeout: 1.5) { images.imageCompletionCount >= 1 }
    )
    harness.panel.contentView?.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    let heightAfter = inspectorDocumentHeight(in: harness.panel)
    XCTAssertEqual(heightBefore, heightAfter, accuracy: 1)
    assertFollowedReveal(in: harness.panel, generation: 1)
  }

  private func revealAnchor(
    in panel: RefsPanel,
    generation: Int
  ) -> RefsInspectorRevealAnchorView? {
    RefsPanelController.findRevealAnchor(
      generation: generation,
      in: panel.contentView
    )
  }

  private func assertFollowedReveal(in panel: RefsPanel, generation: Int) {
    let measured = tryUnwrapMeasured(panel)
    guard let anchor = revealAnchor(in: panel, generation: generation),
      let documentView = measured.scrollView.documentView
    else {
      XCTFail("reveal anchor missing after bitmap completion")
      return
    }
    let rect = anchor.convert(anchor.bounds, to: documentView)
    XCTAssertGreaterThan(rect.height, 0.5)
    let documentHeight = documentView.frame.height
    let batchTop: CGFloat =
      documentView.isFlipped
      ? rect.minY : documentHeight - rect.maxY
    let raw = min(
      measured.geometry.maxOffset,
      batchTop - RefsVisualTokens.inspectorRevealContext
    )
    let target = measured.geometry.clamped(raw)
    XCTAssertEqual(inspectorOffset(in: panel), target, accuracy: 2)
  }

  // MARK: - Hosted harness

  private struct HostedHarness {
    let model: RefsPanelModel
    let controller: RefsPanelController
    let panel: RefsPanel
  }

  private func makeHostedHarness(
    width: CGFloat = 1344,
    height: CGFloat = 798,
    highlights: [RefsShowAnnotation]? = nil,
    shortContent: Bool = false,
    notesPageSize: Int? = nil,
    imageProvider: RefsAnnotationImageProviding? = nil,
    imageMetrics: [String: RefsImageMetrics] = [:]
  ) -> HostedHarness {
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
      pasteboard: FakePasteboard(),
      imageProvider: imageProvider
    )
    if let notesPageSize {
      model.notesPageSize = notesPageSize
    }
    let items = (0..<12).map { index in
      RefItem(
        id: "ref/chat/overflow_\(index).md",
        link: "[[ref/chat/overflow_\(index)]]",
        rawTitle: index == 0 ? "Overflow Preview" : "Filler \(index)",
        stem: "overflow_\(index)",
        kind: .chat,
        state: .ready,
        isBlocked: false,
        pdfPath: "lib/chat/overflow_\(index).pdf"
      )
    }
    let selected = items[0].id
    let inspectorContent: RefsInspectorContent
    if shortContent {
      inspectorContent = RefsInspectorContent(
        summary: RefsSummary(
          label: "SUMMARY",
          paragraph: "Short preview."
        ),
        outline: [],
        highlights: highlights ?? [],
        images: imageMetrics
      )
    } else if let highlights {
      inspectorContent = RefsInspectorContent(
        summary: RefsSummary(
          label: "SUMMARY",
          paragraph: String(
            repeating: "Long preview paragraph for overflow. ",
            count: 40
          )
        ),
        outline: (0..<80).map { "Heading \($0)" },
        highlights: highlights,
        images: imageMetrics
      )
    } else {
      inspectorContent = RefsInspectorContent(
        summary: RefsSummary(
          label: "SUMMARY",
          paragraph: String(
            repeating: "Long preview paragraph for overflow. ",
            count: 40
          )
        ),
        outline: (0..<80).map { "Heading \($0)" },
        images: imageMetrics
      )
    }
    model.installForPreviews(
      items: items,
      signals: RefsSignals(),
      query: "Overflow",
      scope: .all,
      selectedID: selected,
      banner: nil,
      refreshState: .idle,
      inspector: [selected: inspectorContent]
    )
    let controller = RefsPanelController(model: model)
    let panel = controller.makePanelIfNeeded()
    panel.setFrame(
      NSRect(x: 80, y: 80, width: width, height: height),
      display: true
    )
    panel.orderFrontRegardless()
    panel.contentView?.layoutSubtreeIfNeeded()
    return HostedHarness(model: model, controller: controller, panel: panel)
  }

  private func settle(_ panel: RefsPanel) {
    let deadline = Date().addingTimeInterval(1.5)
    while Date() < deadline {
      panel.contentView?.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
      if panel.frame.width >= 760 {
        if let scroll = inspectorScroll(in: panel),
          scroll.documentView?.bounds.height ?? 0
            > scroll.documentVisibleRect.height + 40
        {
          return
        }
      } else if RefsPanelController.findFilterField(in: panel.contentView) != nil {
        return
      }
    }
    XCTFail("hosted Refs panel did not settle")
  }

  private func focusSearch(_ harness: HostedHarness) {
    let field = tryUnwrapFilter(harness.panel)
    field.requestFirstResponder()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    XCTAssertTrue(field.holdsFirstResponder)
  }

  private func tryUnwrapFilter(_ panel: RefsPanel) -> CapturePickerFilterNSTextField {
    let field = RefsPanelController.findFilterField(in: panel.contentView)
    XCTAssertNotNil(field)
    return field!
  }

  private func inspectorScroll(in panel: RefsPanel) -> NSScrollView? {
    RefsPanelController.findInspectorScrollView(in: panel.contentView)
  }

  private func inspectorDiagnostics(in panel: RefsPanel) -> String {
    guard let scroll = RefsPanelController.findInspectorScrollView(in: panel.contentView),
      let documentView = scroll.documentView
    else {
      return "lookup=nil"
    }
    let clip = scroll.contentView
    return
      "lookup=found clip=\(clip.bounds) docHeight=\(documentView.frame.height) flipped=\(documentView.isFlipped) insets=\(clip.contentInsets)"
  }

  private func assertInspectorFits(_ panel: RefsPanel) throws {
    let diagnostics = inspectorDiagnostics(in: panel)
    let scroll = try XCTUnwrap(inspectorScroll(in: panel), diagnostics)
    let documentView = try XCTUnwrap(scroll.documentView, diagnostics)
    XCTAssertLessThanOrEqual(
      documentView.frame.height,
      scroll.contentView.bounds.height,
      diagnostics
    )
  }

  private func inspectorOffset(in panel: RefsPanel) -> CGFloat {
    inspectorScroll(in: panel)?.documentVisibleRect.origin.y ?? 0
  }

  private func inspectorDocumentHeight(in panel: RefsPanel) -> CGFloat {
    inspectorScroll(in: panel)?.documentView?.frame.height ?? 0
  }

  private func listOffset(in panel: RefsPanel) -> CGFloat {
    let inspector = inspectorScroll(in: panel)
    let scrolls = RefsPanelController.scrollViews(in: panel.contentView)
    return scrolls.first { $0 !== inspector }?.documentVisibleRect.origin.y ?? 0
  }

  private func waitForInspectorOffset(
    in panel: RefsPanel,
    _ predicate: (CGFloat) -> Bool
  ) {
    let deadline = Date().addingTimeInterval(1)
    while Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
      if predicate(inspectorOffset(in: panel)) {
        return
      }
    }
    XCTFail("inspector offset did not change as expected; \(inspectorDiagnostics(in: panel))")
  }

  private func waitForInspectorSettled(
    in panel: RefsPanel,
    around expected: CGFloat,
    tolerance: CGFloat
  ) {
    let deadline = Date().addingTimeInterval(1.5)
    while Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
      panel.contentView?.layoutSubtreeIfNeeded()
      if abs(inspectorOffset(in: panel) - expected) <= tolerance {
        // One more turn to catch a late follow-scroll.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        if abs(inspectorOffset(in: panel) - expected) <= tolerance {
          return
        }
      }
    }
    XCTFail(
      "inspector offset did not settle around \(expected); "
        + inspectorDiagnostics(in: panel)
    )
  }

  private func tryUnwrapSelected(_ harness: HostedHarness) -> String {
    let selected = harness.model.selectedID
    XCTAssertNotNil(selected)
    return selected!
  }

  private func scrollInspectorToBottom(in panel: RefsPanel) {
    guard let scroll = inspectorScroll(in: panel),
      let documentView = scroll.documentView
    else {
      XCTFail("no inspector scroll view to pin to the bottom")
      return
    }
    let clip = scroll.contentView
    let content = documentView.frame.height
    let viewport = clip.bounds.height
    let flipped = documentView.isFlipped
    let maxOffset = max(content - viewport + clip.contentInsets.bottom, -clip.contentInsets.top)
    let y = flipped ? maxOffset : content - viewport - maxOffset
    clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
    scroll.reflectScrolledClipView(clip)
    panel.contentView?.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
  }

  /// Pins the inspector `delta` points above the bottom, so the
  /// disclosure row can sit fully on screen while the offset is
  /// off the bottom.
  private func scrollInspectorAboveBottom(in panel: RefsPanel, by delta: CGFloat) {
    guard let scroll = inspectorScroll(in: panel),
      let documentView = scroll.documentView
    else {
      XCTFail("no inspector scroll view to pin above the bottom")
      return
    }
    let clip = scroll.contentView
    let content = documentView.frame.height
    let viewport = clip.bounds.height
    let flipped = documentView.isFlipped
    let maxOffset = max(content - viewport + clip.contentInsets.bottom, -clip.contentInsets.top)
    let target = max(maxOffset - delta, -clip.contentInsets.top)
    let y = flipped ? target : content - viewport - target
    clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
    scroll.reflectScrolledClipView(clip)
    panel.contentView?.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
  }

  /// The live inspector scroll measurement, mirroring the
  /// controller's own, for disclosure-visibility assertions.
  private func tryUnwrapMeasured(
    _ panel: RefsPanel
  ) -> (
    scrollView: NSScrollView,
    geometry: RefsInspectorScrollGeometry,
    flipped: Bool
  ) {
    guard let scroll = inspectorScroll(in: panel),
      let documentView = scroll.documentView
    else {
      XCTFail("no inspector scroll view to measure")
      return (
        scrollView: NSScrollView(),
        geometry: .invalid,
        flipped: true
      )
    }
    let clip = scroll.contentView
    let content = documentView.frame.height
    let viewport = clip.bounds.height
    let flipped = documentView.isFlipped
    let offset =
      flipped
      ? clip.bounds.origin.y : content - viewport - clip.bounds.origin.y
    return (
      scrollView: scroll,
      geometry: RefsInspectorScrollGeometry(
        offsetY: offset,
        contentHeight: content,
        viewportHeight: viewport,
        topInset: clip.contentInsets.top,
        bottomInset: clip.contentInsets.bottom
      ),
      flipped: flipped
    )
  }

  private func settleShort(_ panel: RefsPanel) {
    let deadline = Date().addingTimeInterval(1.5)
    while Date() < deadline {
      panel.contentView?.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
      if RefsPanelController.findFilterField(in: panel.contentView) != nil,
        inspectorScroll(in: panel) != nil
      {
        return
      }
    }
    XCTFail("hosted Refs panel did not settle")
  }

  private func keyEvent(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags,
    characters: String
  ) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: keyCode
    )!
  }

  private static let overflow = RefsInspectorScrollGeometry(
    offsetY: 0,
    contentHeight: 1400,
    viewportHeight: 400,
    topInset: 0,
    bottomInset: 0
  )
  private static let overflowAtBottom = RefsInspectorScrollGeometry(
    offsetY: 1000,
    contentHeight: 1400,
    viewportHeight: 400,
    topInset: 0,
    bottomInset: 0
  )
  private static let dKey: UInt16 = 2
  private static let uKey: UInt16 = 32
  private static let zKey: UInt16 = 6

  private static func eightNotes() -> [RefsShowAnnotation] {
    (1...8).map { index in
      RefsShowAnnotation(
        pageLabel: "\(index)",
        kind: "highlight",
        quote: "Quote \(index)",
        comment: "Comment \(index)"
      )
    }
  }

  private static func thirteenNotes() -> [RefsShowAnnotation] {
    (1...13).map { index in
      RefsShowAnnotation(
        pageLabel: "\(index)",
        kind: "highlight",
        quote: "Quote \(index)",
        comment: "Comment \(index)"
      )
    }
  }
}
