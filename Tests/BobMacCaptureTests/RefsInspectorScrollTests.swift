import AppKit
import Foundation
import RefsCore
import XCTest

@testable import BobMacCapture

/// Planner math for half-viewport inspector scrolling, plus a hosted
/// view test that drives the routed Control-D/U path while search is
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

    func testHostedControlDUScrollsInspectorWhileSearchKeepsFocus() {
        let harness = makeHostedHarness(width: 880)
        defer { harness.panel.orderOut(nil) }
        settle(harness.panel)
        focusSearch(harness)
        let field = tryUnwrapFilter(harness.panel)
        let editor = field.currentEditor() as? NSTextView
        let caret = editor?.selectedRange()
        let selected = harness.model.selectedID
        let query = harness.model.query
        let listOffset = listOffset(in: harness.panel)
        let start = inspectorOffset(in: harness.panel)

        XCTAssertNil(
            harness.controller.processKeyEvent(
                keyEvent(keyCode: Self.dKey, modifiers: .control, characters: "d")
            )
        )
        waitForInspectorOffset(in: harness.panel) { $0 > start + 8 }

        let afterDown = inspectorOffset(in: harness.panel)
        XCTAssertGreaterThan(afterDown, start)
        XCTAssertEqual(listOffset(in: harness.panel), listOffset, accuracy: 1)
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
        XCTAssertLessThan(inspectorOffset(in: harness.panel), afterDown)
        XCTAssertEqual(harness.model.selectedID, selected)
        XCTAssertTrue(field.holdsFirstResponder)
    }

    func testHostedControlDConsumesAtBoundaryAndWhenInspectorHidden() {
        let wide = makeHostedHarness(width: 880)
        defer { wide.panel.orderOut(nil) }
        settle(wide.panel)
        focusSearch(wide)
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
        XCTAssertEqual(inspectorOffset(in: wide.panel), atBottom, accuracy: 2)

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
        let harness = makeHostedHarness(width: 880)
        defer { harness.panel.orderOut(nil) }
        let event = keyEvent(
            keyCode: Self.dKey,
            modifiers: .control,
            characters: "d"
        )
        XCTAssertFalse(harness.panel.isKeyWindow)
        XCTAssertTrue(harness.controller.handleKeyDown(event) === event)
    }

    // MARK: - Hosted harness

    private struct HostedHarness {
        let model: RefsPanelModel
        let controller: RefsPanelController
        let panel: RefsPanel
    }

    private func makeHostedHarness(width: CGFloat) -> HostedHarness {
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
        model.installForPreviews(
            items: items,
            signals: RefsSignals(),
            query: "Overflow",
            scope: .all,
            selectedID: selected,
            banner: nil,
            refreshState: .idle,
            inspector: [
                selected: RefsInspectorContent(
                    summary: RefsSummary(
                        label: "SUMMARY",
                        paragraph: String(
                            repeating: "Long preview paragraph for overflow. ",
                            count: 40
                        )
                    ),
                    outline: (0..<80).map { "Heading \($0)" }
                ),
            ]
        )
        let controller = RefsPanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        panel.setFrame(
            NSRect(x: 80, y: 80, width: width, height: 560),
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
        if let named = RefsPanelController.findInspectorScrollView(in: panel.contentView) {
            return named
        }
        let scrolls = RefsPanelController.scrollViews(in: panel.contentView)
        guard scrolls.count >= 2 else {
            return nil
        }
        return scrolls.max { lhs, rhs in
            lhs.convert(lhs.bounds, to: nil).minX
                < rhs.convert(rhs.bounds, to: nil).minX
        }
    }

    private func inspectorOffset(in panel: RefsPanel) -> CGFloat {
        inspectorScroll(in: panel)?.documentVisibleRect.origin.y ?? 0
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
        XCTFail("inspector offset did not change as expected")
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
    private static let dKey: UInt16 = 2
    private static let uKey: UInt16 = 32
}
