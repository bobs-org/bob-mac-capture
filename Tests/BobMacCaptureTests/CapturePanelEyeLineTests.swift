import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Fixed eye-line placement: every show, with or without the agenda
/// or a retained draft, puts the input line in the same place, while
/// typed previews keep growing downward and slide up only at the
/// screen's edges.
@MainActor
final class CapturePanelEyeLineTests: XCTestCase {
    private func contentMetrics(ideal: CGFloat, minimum: CGFloat)
        -> CapturePanelContentMetrics
    {
        CapturePanelContentMetrics(
            idealContentHeight: ideal,
            minimumVisibleContentHeight: minimum
        )
    }

    private func visibleFrame(for panel: NSPanel) -> NSRect? {
        panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    }

    func testTopIdenticalAcrossShowsWithAndWithoutAgenda() {
        let model = CapturePanelModel()
        model.footerHeight = 40
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        let policy = CapturePanelContentHeightPolicy(displayScale: 1)

        let compact = policy.metrics(
            editorHeight: 42,
            auxiliaryHeight: nil,
            footerHeight: 40
        )
        controller.receiveContentMetrics(compact)
        controller.replayLatestContentMetricsForPresentation()
        let compactTop = panel.frame.maxY

        // The panel reports the agenda through the production cap
        // (below-eye-line budget plus pane padding, mirroring
        // `agendaPaneHeightCap`), so the eye line holds on any screen
        // size. An uncapped synthetic height would slide up on short
        // screens, an input the product never emits.
        let cappedAgendaIdeal: CGFloat
        if model.agendaBudget > 0 {
            cappedAgendaIdeal = min(
                300,
                CGFloat(model.agendaBudget)
                    + 2 * CGFloat(CaptureAgendaLayoutMetrics.panePadding)
            )
        } else {
            cappedAgendaIdeal = 300
        }
        let agenda = policy.metrics(
            editorHeight: 42,
            auxiliary: .overflow(idealHeight: cappedAgendaIdeal),
            footerHeight: 40
        )
        controller.receiveContentMetrics(agenda)
        controller.replayLatestContentMetricsForPresentation()
        XCTAssertEqual(panel.frame.maxY, compactTop, accuracy: 0.5)
    }

    func testTopIdenticalWithRetainedDraftPreview() {
        let model = CapturePanelModel()
        model.footerHeight = 40
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        let policy = CapturePanelContentHeightPolicy(displayScale: 1)

        let compact = policy.metrics(
            editorHeight: 42,
            auxiliaryHeight: nil,
            footerHeight: 40
        )
        controller.receiveContentMetrics(compact)
        controller.replayLatestContentMetricsForPresentation()
        let compactTop = panel.frame.maxY

        let preview = policy.metrics(
            editorHeight: 60,
            auxiliary: .overflow(idealHeight: 200),
            footerHeight: 40
        )
        controller.receiveContentMetrics(preview)
        controller.replayLatestContentMetricsForPresentation()
        XCTAssertEqual(panel.frame.maxY, compactTop, accuracy: 0.5)
    }

    func testTallPreviewGrowsDownwardAndClampsAtScreenEdges() throws {
        let model = CapturePanelModel()
        model.footerHeight = 40
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        guard let visible = visibleFrame(for: panel) else {
            throw XCTSkip("no visible frame on this host")
        }
        let policy = CapturePanelContentHeightPolicy(displayScale: 1)

        let compact = policy.metrics(
            editorHeight: 42,
            auxiliaryHeight: nil,
            footerHeight: 40
        )
        controller.receiveContentMetrics(compact)
        controller.replayLatestContentMetricsForPresentation()
        let compactTop = panel.frame.maxY

        let tall = policy.metrics(
            editorHeight: 42,
            auxiliary: .overflow(idealHeight: 5_000),
            footerHeight: 40
        )
        controller.receiveContentMetrics(tall)
        controller.replayLatestContentMetricsForPresentation()
        XCTAssertGreaterThan(panel.frame.height, 500)
        XCTAssertLessThanOrEqual(panel.frame.maxY, visible.maxY + 0.5)
        XCTAssertGreaterThanOrEqual(panel.frame.minY, visible.minY - 0.5)
        // A clamped panel keeps the eye line when it fits below it.
        XCTAssertLessThanOrEqual(compactTop, visible.maxY + 0.5)
    }

    func testControllerWiresSettleHook() {
        let model = CapturePanelModel()
        XCTAssertNil(model.agendaPlanDidChange)
        _ = CapturePanelController(model: model)
        XCTAssertNotNil(model.agendaPlanDidChange)
    }

    func testPanelHorizontallyCentredAfterPresentation() throws {
        let model = CapturePanelModel()
        model.footerHeight = 40
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        guard let visible = visibleFrame(for: panel) else {
            throw XCTSkip("no visible frame on this host")
        }
        let policy = CapturePanelContentHeightPolicy(displayScale: 1)
        let compact = policy.metrics(
            editorHeight: 42,
            auxiliaryHeight: nil,
            footerHeight: 40
        )
        controller.receiveContentMetrics(compact)
        controller.replayLatestContentMetricsForPresentation()
        XCTAssertEqual(panel.frame.midX, visible.midX, accuracy: 1)
    }

    func testCompactTopMatchesCenter() throws {
        let model = CapturePanelModel()
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        guard visibleFrame(for: panel) != nil else {
            throw XCTSkip("no visible frame on this host")
        }
        // The controller refreshes the titlebar safe-area inset from
        // the live panel on every metrics report, so settle it before
        // building the reference input: a policy built with the
        // pre-layout inset centres a different height and the tops
        // disagree by half the gap. The footer stays 0 until the
        // inset settles so the pre-layout derivation never pins the
        // cached eye line.
        let settle = CapturePanelContentHeightPolicy(displayScale: 1).metrics(
            editorHeight: 42,
            auxiliaryHeight: nil,
            footerHeight: 40
        )
        controller.receiveContentMetrics(settle)
        controller.replayLatestContentMetricsForPresentation()
        // The hosted SwiftUI view measures the real footer asynchronously
        // and publishes it on the model, so a hardcoded footer fights the
        // live view: drain those callbacks, then derive the reference from
        // the observed footer like the inset and scale below. A stale 40
        // pins the cached eye line below the reference (CI: 607 vs 611).
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        controller.replayLatestContentMetricsForPresentation()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        let observedFooter = model.footerHeight > 1 ? model.footerHeight : 40
        model.footerHeight = observedFooter
        // The eye line is derived from the compact height with the
        // observed safe-area inset and display scale, so the reference
        // metrics must use those same inputs: a default policy centres
        // a different height and the tops disagree by half the gap.
        let policy = CapturePanelContentHeightPolicy(
            safeAreaTopInset: model.titlebarSafeAreaInset,
            displayScale: panel.screen?.backingScaleFactor ?? 1
        )
        let compact = policy.metrics(
            editorHeight: 42,
            auxiliaryHeight: nil,
            footerHeight: observedFooter
        )
        controller.receiveContentMetrics(compact)
        controller.replayLatestContentMetricsForPresentation()
        // The reference goes through AppKit itself: the compact
        // frame size, centred, so the eye line is where the compact
        // bar opened before the epic.
        let reference = CapturePanelController.makePanel()
        reference.setFrame(panel.frame, display: false)
        reference.center()
        XCTAssertEqual(
            panel.frame.maxY,
            reference.frame.maxY,
            accuracy: 1
        )
    }
}
