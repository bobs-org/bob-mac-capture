import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

final class CapturePreviewFullHeightTests: XCTestCase {
    func testContentHeightPolicyIncludesTitlebarSafeAreaInset() {
        let base = CapturePanelContentHeightPolicy(displayScale: 1)
        let inset = CapturePanelContentHeightPolicy(safeAreaTopInset: 32, displayScale: 1)

        let emptyBase = base.metrics(editorHeight: 40, auxiliaryHeight: nil, footerHeight: 30)
        let emptyInset = inset.metrics(editorHeight: 40, auxiliaryHeight: nil, footerHeight: 30)
        XCTAssertEqual(emptyInset.idealContentHeight, emptyBase.idealContentHeight + 32)
        XCTAssertEqual(emptyInset.minimumVisibleContentHeight, emptyBase.minimumVisibleContentHeight + 32)

        let auxBase = base.metrics(editorHeight: 40, auxiliaryHeight: 60, footerHeight: 30)
        let auxInset = inset.metrics(editorHeight: 40, auxiliaryHeight: 60, footerHeight: 30)
        XCTAssertEqual(auxInset.idealContentHeight, auxBase.idealContentHeight + 32)
        XCTAssertEqual(auxInset.minimumVisibleContentHeight, auxBase.minimumVisibleContentHeight + 32)

        XCTAssertEqual(
            inset.nonEditorChromeHeight(footerHeight: 30, hasAuxiliary: false),
            base.nonEditorChromeHeight(footerHeight: 30, hasAuxiliary: false) + 32
        )
        XCTAssertEqual(
            inset.nonEditorChromeHeight(footerHeight: 30, hasAuxiliary: true),
            base.nonEditorChromeHeight(footerHeight: 30, hasAuxiliary: true) + 32
        )

        let tallScreen: CGFloat = 1600
        let baseBudget = CaptureEditorHeightBudget(
            availableScreenHeight: tallScreen,
            footerHeight: 40,
            auxiliary: nil,
            contentPolicy: base
        )
        let insetBudget = CaptureEditorHeightBudget(
            availableScreenHeight: tallScreen,
            footerHeight: 40,
            auxiliary: nil,
            contentPolicy: inset
        )
        XCTAssertEqual(baseBudget.maximumHeight - insetBudget.maximumHeight, 32)

        let tinyBase = CaptureEditorHeightBudget(
            availableScreenHeight: 80,
            footerHeight: 40,
            auxiliary: .overflow(idealHeight: 200),
            contentPolicy: base
        )
        let tinyInset = CaptureEditorHeightBudget(
            availableScreenHeight: 80,
            footerHeight: 40,
            auxiliary: .overflow(idealHeight: 200),
            contentPolicy: inset
        )
        XCTAssertEqual(tinyBase.maximumHeight, tinyBase.minimumEditorHeight)
        XCTAssertEqual(tinyInset.maximumHeight, tinyInset.minimumEditorHeight)

        let negative = CapturePanelContentHeightPolicy(safeAreaTopInset: -10, displayScale: 1)
        XCTAssertEqual(
            negative.nonEditorChromeHeight(footerHeight: 30, hasAuxiliary: false),
            base.nonEditorChromeHeight(footerHeight: 30, hasAuxiliary: false)
        )
        let infinite = CapturePanelContentHeightPolicy(safeAreaTopInset: .infinity, displayScale: 1)
        XCTAssertEqual(
            infinite.nonEditorChromeHeight(footerHeight: 30, hasAuxiliary: false),
            base.nonEditorChromeHeight(footerHeight: 30, hasAuxiliary: false)
        )
        let notANumber = CapturePanelContentHeightPolicy(safeAreaTopInset: .nan, displayScale: 1)
        XCTAssertEqual(
            notANumber.nonEditorChromeHeight(footerHeight: 30, hasAuxiliary: false),
            base.nonEditorChromeHeight(footerHeight: 30, hasAuxiliary: false)
        )
    }

    func testPreviewPaneHeightPolicyHoldsSettledHeightWhileLoading() {
        let floor = CapturePanelLayout.previewMinimumHeight

        XCTAssertEqual(
            CapturePreviewPaneHeightPolicy.minimumHeight(for: .loading, settledHeight: nil),
            floor
        )
        XCTAssertEqual(
            CapturePreviewPaneHeightPolicy.minimumHeight(for: .loading, settledHeight: 180),
            180
        )
        XCTAssertEqual(
            CapturePreviewPaneHeightPolicy.minimumHeight(for: .loading, settledHeight: 20),
            floor
        )

        let success = sampleSuccess()
        XCTAssertEqual(
            CapturePreviewPaneHeightPolicy.minimumHeight(for: .ready(success), settledHeight: 180),
            floor
        )
        XCTAssertEqual(
            CapturePreviewPaneHeightPolicy.minimumHeight(for: .ready(success), settledHeight: nil),
            floor
        )
        XCTAssertEqual(
            CapturePreviewPaneHeightPolicy.minimumHeight(for: .failed("boom"), settledHeight: 180),
            floor
        )
        XCTAssertEqual(
            CapturePreviewPaneHeightPolicy.minimumHeight(for: .failed("boom"), settledHeight: nil),
            floor
        )
    }

    @MainActor
    func testControllerPublishesTitlebarSafeAreaInset() {
        let model = CapturePanelModel()
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        panel.contentView?.layoutSubtreeIfNeeded()

        let expected = panel.contentView?.safeAreaInsets.top ?? 0
        XCTAssertEqual(model.titlebarSafeAreaInset, expected, accuracy: 0.5)
        XCTAssertGreaterThan(model.titlebarSafeAreaInset, 0)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testPreviewPaneTakesNaturalHeight() throws {
        let close = try closeSuccessFixture("pomodoro-close-worked.json")
        let model = CapturePanelModel()
        model.previewResult = close
        model.previewResults = [close]
        model.previewState = .ready(close)

        let height = hostedPreviewHeight(for: model, width: 724)
        XCTAssertGreaterThan(height, CapturePanelLayout.previewMinimumHeight + 20)

        let loadingModel = CapturePanelModel()
        loadingModel.previewState = .loading
        let loadingHeight = hostedPreviewHeight(for: loadingModel, width: 724)
        XCTAssertEqual(loadingHeight, CapturePanelLayout.previewMinimumHeight + 20, accuracy: 0.5)
    }

    @MainActor
    @available(macOS 26.0, *)
    func testPreviewPaneWithBlocksIsTallerThanWithout() throws {
        let close = try closeSuccessFixture("pomodoro-close-blocks.json")
        XCTAssertFalse(close.pomodoroBlocks.isEmpty)
        let emptied = try successStrippingBlocks(close)
        XCTAssertEqual(emptied.pomodoroBlocks, [])

        // The block view adds real height at full and minimum panel widths.
        for width in [724, 620] as [CGFloat] {
            let withBlocks = hostedPreviewHeight(for: readyModel(for: close), width: width)
            let withoutBlocks = hostedPreviewHeight(for: readyModel(for: emptied), width: width)
            XCTAssertGreaterThan(
                withBlocks,
                withoutBlocks,
                "blocks should grow the pane at width \(width)"
            )
        }
    }

    @MainActor
    @available(macOS 26.0, *)
    func testPreviewPaneHoldsHeightWhileReloading() throws {
        let close = try closeSuccessFixture("pomodoro-close-worked.json")
        let model = CapturePanelModel()
        model.previewResult = close
        model.previewResults = [close]
        model.previewState = .ready(close)

        let hostingView = NSHostingView(rootView: PreviewPane(model: model).frame(width: 724))
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hostingView.layoutSubtreeIfNeeded()
        let readyHeight = hostingView.fittingSize.height
        XCTAssertGreaterThan(readyHeight, CapturePanelLayout.previewMinimumHeight + 20)

        model.previewState = .loading
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hostingView.layoutSubtreeIfNeeded()
        let loadingHeight = hostingView.fittingSize.height
        XCTAssertGreaterThan(loadingHeight, CapturePanelLayout.previewMinimumHeight + 20)
        XCTAssertEqual(loadingHeight, readyHeight, accuracy: 1.0)
    }

    @MainActor
    @available(macOS 26.0, *)
    private func hostedPreviewHeight(for model: CapturePanelModel, width: CGFloat) -> CGFloat {
        let hostingView = NSHostingView(rootView: PreviewPane(model: model).frame(width: width))
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }

    @MainActor
    private func readyModel(for success: CaptureCommandSuccess) -> CapturePanelModel {
        let model = CapturePanelModel()
        model.previewResult = success
        model.previewResults = [success]
        model.previewState = .ready(success)
        return model
    }

    private func successStrippingBlocks(_ success: CaptureCommandSuccess) throws -> CaptureCommandSuccess {
        let data = try JSONEncoder().encode(success)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "CapturePreviewFullHeightTests", code: 2)
        }
        object.removeValue(forKey: "pomodoro_blocks")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(CaptureCommandSuccess.self, from: stripped)
    }

    private func closeSuccessFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            XCTFail("expected a successful Bob close response")
            throw NSError(domain: "CapturePreviewFullHeightTests", code: 1)
        }
        return success
    }

    private func sampleSuccess() -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: true,
            routed: true,
            route: "Cash",
            routeLabel: "Cash.md",
            relativeTarget: "Cash.md",
            target: "/tmp/Cash.md",
            text: "Call bank",
            taskLine: "- [ ] Call bank",
            kind: "task",
            created: "2026-08-14",
            placement: "append"
        )
    }
}
