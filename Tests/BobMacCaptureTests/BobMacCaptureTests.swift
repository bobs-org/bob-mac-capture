import AppKit
import Carbon
import Combine
import CaptureCore
import ServiceManagement
import XCTest

@testable import BobMacCapture

final class BobMacCaptureTests: XCTestCase {
    @MainActor
    func testPanelHasStableNonActivatingStyleInInitializer() {
        let panel = CapturePanelController.makePanel()

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertEqual(panel.contentMinSize.width, CapturePanelLayout.panelMinimumContentWidth)

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size
        XCTAssertEqual(contentSize.height, CapturePanelLayout.panelFallbackContentHeight)
        XCTAssertLessThan(contentSize.height, 420)
        XCTAssertGreaterThanOrEqual(contentSize.width, panel.contentMinSize.width)
    }

    func testContentHeightPolicyComposesEmptyAndAuxiliaryStates() {
        let policy = CapturePanelContentHeightPolicy(
            titlebarDragInset: 20,
            rootPadding: 10,
            sectionSpacing: 5,
            displayScale: 1
        )

        let empty = policy.metrics(editorHeight: 40, auxiliaryHeight: nil, footerHeight: 30)
        XCTAssertEqual(empty.idealContentHeight, 105)
        XCTAssertEqual(empty.minimumVisibleContentHeight, 105)

        let withAuxiliary = policy.metrics(editorHeight: 40, auxiliaryHeight: 60, footerHeight: 30)
        XCTAssertEqual(withAuxiliary.idealContentHeight, 170)
        XCTAssertEqual(withAuxiliary.minimumVisibleContentHeight, 110)
    }

    func testStashPickerHeightPolicySizesRowsAndActionChrome() {
        let oneEntry = CanceledDraftStashPickerHeightPolicy(entryCount: 1)
        let fiveEntries = CanceledDraftStashPickerHeightPolicy(entryCount: 5)
        let moreThanFiveEntries = CanceledDraftStashPickerHeightPolicy(entryCount: 36)

        let oneRowViewport = CapturePanelLayout.stashListPadding * 2 + CapturePanelLayout.stashRowHeight
        let cappedViewport = CapturePanelLayout.stashListPadding * 2
            + CapturePanelLayout.stashRowHeight * CGFloat(CapturePanelLayout.stashVisibleRows)
            + CapturePanelLayout.stashRowSpacing * CGFloat(CapturePanelLayout.stashVisibleRows - 1)
        let actionChrome = CapturePanelLayout.stashPickerPadding * 2
            + CapturePanelLayout.stashPickerContentSpacing
            + CapturePanelLayout.stashClearButtonHeight

        XCTAssertEqual(oneEntry.visibleRowCount, 1)
        XCTAssertEqual(oneEntry.rowViewportHeight, oneRowViewport)
        XCTAssertEqual(oneEntry.minimumVisibleHeight, actionChrome)
        XCTAssertEqual(oneEntry.idealHeight, oneRowViewport + actionChrome)

        XCTAssertEqual(fiveEntries.visibleRowCount, 5)
        XCTAssertEqual(fiveEntries.rowViewportHeight, cappedViewport)
        XCTAssertEqual(fiveEntries.idealHeight, cappedViewport + actionChrome)

        XCTAssertEqual(moreThanFiveEntries.visibleRowCount, 5)
        XCTAssertEqual(moreThanFiveEntries.rowViewportHeight, fiveEntries.rowViewportHeight)
        XCTAssertEqual(moreThanFiveEntries.idealHeight, fiveEntries.idealHeight)
        XCTAssertLessThan(oneEntry.idealHeight, fiveEntries.idealHeight)
    }

    func testContentHeightPolicyIncludesStashRequiredVisibleAuxiliaryHeight() {
        let policy = CapturePanelContentHeightPolicy(
            titlebarDragInset: 20,
            rootPadding: 10,
            sectionSpacing: 5,
            displayScale: 1
        )
        let stashHeight = CanceledDraftStashPickerHeightPolicy(entryCount: 1).auxiliaryHeight

        let stash = policy.metrics(editorHeight: 40, auxiliary: stashHeight, footerHeight: 30)

        XCTAssertEqual(stash.idealContentHeight, 110 + stashHeight.idealHeight)
        XCTAssertEqual(stash.minimumVisibleContentHeight, 110 + stashHeight.minimumVisibleHeight)
        XCTAssertGreaterThan(stash.idealContentHeight, stash.minimumVisibleContentHeight)
        XCTAssertGreaterThan(stash.minimumVisibleContentHeight, 110)
    }

    func testContentHeightPolicyUsesMeasuredFooterAndDisplayScaleRounding() {
        let policy = CapturePanelContentHeightPolicy(
            titlebarDragInset: 28,
            rootPadding: 18,
            sectionSpacing: 12,
            displayScale: 2
        )

        let shortFooter = policy.metrics(
            editorHeight: 42.1,
            auxiliaryHeight: nil,
            footerHeight: 37.2
        )
        let tallFooter = policy.metrics(
            editorHeight: 42.1,
            auxiliaryHeight: nil,
            footerHeight: 47.2
        )

        XCTAssertEqual(shortFooter.idealContentHeight, 137.5)
        XCTAssertEqual(shortFooter.minimumVisibleContentHeight, 137.5)
        XCTAssertEqual(tallFooter.idealContentHeight, 147.5)
        XCTAssertEqual(tallFooter.minimumVisibleContentHeight, 147.5)
    }

    func testSizerClampsIdealHeightToFloorCeilingAndPixelRounding() {
        let sizer = CapturePanelWindowSizer(
            minimumContentHeight: 100,
            maximumContentHeight: 500,
            screenMargin: 20,
            displayScale: 1
        )

        XCTAssertEqual(
            sizer.contentHeight(for: contentMetrics(ideal: 10, minimum: 40), availableScreenHeight: nil),
            100
        )
        XCTAssertEqual(
            sizer.contentHeight(for: contentMetrics(ideal: 900, minimum: 120), availableScreenHeight: nil),
            500
        )
        XCTAssertEqual(
            sizer.contentHeight(for: contentMetrics(ideal: 234.2, minimum: 120), availableScreenHeight: nil),
            235
        )
        XCTAssertEqual(
            sizer.contentHeight(for: contentMetrics(ideal: 480, minimum: 120), availableScreenHeight: 300),
            260
        )
    }

    func testSizerPreservesPersistentMinimumUnlessScreenIsTooShort() {
        let sizer = CapturePanelWindowSizer(
            minimumContentHeight: 100,
            maximumContentHeight: 500,
            screenMargin: 20,
            displayScale: 1
        )

        XCTAssertEqual(
            sizer.contentHeight(for: contentMetrics(ideal: 120, minimum: 180), availableScreenHeight: 600),
            180
        )
        XCTAssertEqual(
            sizer.contentHeight(for: contentMetrics(ideal: 900, minimum: 180), availableScreenHeight: 300),
            260
        )
        XCTAssertEqual(
            sizer.contentHeight(for: contentMetrics(ideal: 900, minimum: 280), availableScreenHeight: 300),
            260
        )
    }

    func testSizerAppliesStashMetricsAndClampsOnlyWhenScreenIsTooShort() {
        let policy = CapturePanelContentHeightPolicy(
            titlebarDragInset: 20,
            rootPadding: 10,
            sectionSpacing: 5,
            displayScale: 1
        )
        let stashMetrics = policy.metrics(
            editorHeight: 40,
            auxiliary: CanceledDraftStashPickerHeightPolicy(entryCount: 1).auxiliaryHeight,
            footerHeight: 30
        )
        let normalSizer = CapturePanelWindowSizer(
            minimumContentHeight: 100,
            maximumContentHeight: 500,
            screenMargin: 20,
            displayScale: 1
        )
        let lowMaximumSizer = CapturePanelWindowSizer(
            minimumContentHeight: 100,
            maximumContentHeight: stashMetrics.minimumVisibleContentHeight - 10,
            screenMargin: 20,
            displayScale: 1
        )

        XCTAssertEqual(
            normalSizer.contentHeight(for: stashMetrics, availableScreenHeight: 900),
            stashMetrics.idealContentHeight
        )
        XCTAssertEqual(
            lowMaximumSizer.contentHeight(for: stashMetrics, availableScreenHeight: nil),
            stashMetrics.minimumVisibleContentHeight
        )
        XCTAssertEqual(
            normalSizer.contentHeight(
                for: stashMetrics,
                availableScreenHeight: stashMetrics.minimumVisibleContentHeight + 20
            ),
            stashMetrics.minimumVisibleContentHeight - 20
        )
    }

    func testSizerFramePreservesTopEdgeOriginXAndWidthWhenGrowingAndShrinking() {
        let sizer = CapturePanelWindowSizer()
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let currentFrame = NSRect(x: 100, y: 400, width: 760, height: 200)

        let grown = sizer.frame(
            forCurrentFrame: currentFrame,
            contentHeight: 300,
            chromeHeight: 0,
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(grown.maxY, currentFrame.maxY)
        XCTAssertEqual(grown.origin.x, currentFrame.origin.x)
        XCTAssertEqual(grown.width, currentFrame.width)
        XCTAssertEqual(grown.height, 300)

        let shrunk = sizer.frame(
            forCurrentFrame: currentFrame,
            contentHeight: 100,
            chromeHeight: 0,
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(shrunk.maxY, currentFrame.maxY)
        XCTAssertEqual(shrunk.origin.x, currentFrame.origin.x)
        XCTAssertEqual(shrunk.width, currentFrame.width)
        XCTAssertEqual(shrunk.height, 100)
    }

    func testSizerFramePushesUpWhenGrowingPastScreenBottom() {
        let sizer = CapturePanelWindowSizer()
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let currentFrame = NSRect(x: 100, y: 20, width: 760, height: 120)

        let grown = sizer.frame(
            forCurrentFrame: currentFrame,
            contentHeight: 600,
            chromeHeight: 0,
            visibleFrame: visibleFrame
        )

        XCTAssertTrue(visibleFrame.contains(grown))
        XCTAssertEqual(grown.height, 600)
    }

    func testSizerUsesScreenLimitAsSoleCeilingWhenMaximumIsNil() {
        let sizer = CapturePanelWindowSizer(
            minimumContentHeight: 100,
            maximumContentHeight: nil,
            screenMargin: 24,
            displayScale: 1
        )
        let availableScreenHeight: CGFloat = 800
        let screenLimit = availableScreenHeight - 2 * 24

        XCTAssertEqual(
            sizer.contentHeight(
                for: contentMetrics(ideal: 10_000, minimum: 120),
                availableScreenHeight: availableScreenHeight
            ),
            screenLimit
        )
        XCTAssertEqual(screenLimit, 752)
    }

    func testSizerDoesNotRoundAboveScreenLimit() {
        let sizer = CapturePanelWindowSizer(
            minimumContentHeight: 100,
            maximumContentHeight: nil,
            screenMargin: 24,
            displayScale: 2
        )
        let availableScreenHeight: CGFloat = 801.25
        let rawScreenLimit = availableScreenHeight - 2 * 24
        let result = sizer.contentHeight(
            for: contentMetrics(ideal: 10_000, minimum: 120),
            availableScreenHeight: availableScreenHeight
        )

        XCTAssertLessThanOrEqual(result, rawScreenLimit)
        XCTAssertEqual(result, 753)
        XCTAssertEqual(rawScreenLimit, 753.25)
    }

    @MainActor
    func testReceiveContentMetricsGrowsAndKeepsTopEdge() {
        let model = CapturePanelModel()
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        let initialFrame = panel.frame
        let initialContentHeight = panel.contentRect(forFrameRect: panel.frame).size.height
        let metrics = contentMetrics(ideal: initialContentHeight + 120, minimum: initialContentHeight)
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let expectedContentHeight = CapturePanelWindowSizer(
            displayScale: panel.screen?.backingScaleFactor ?? 1
        ).contentHeight(
            for: metrics,
            availableScreenHeight: visibleFrame?.height
        )
        let expectedFrame = CapturePanelWindowSizer(
            displayScale: panel.screen?.backingScaleFactor ?? 1
        ).frame(
            forCurrentFrame: initialFrame,
            contentHeight: expectedContentHeight,
            chromeHeight: initialFrame.height - initialContentHeight,
            visibleFrame: visibleFrame ?? NSRect(
                x: -1_000_000,
                y: -1_000_000,
                width: 2_000_000,
                height: 2_000_000
            )
        )

        controller.receiveContentMetrics(metrics)

        let grownFrame = panel.frame
        XCTAssertGreaterThan(grownFrame.height, initialFrame.height)
        XCTAssertEqual(grownFrame.maxY, expectedFrame.maxY, accuracy: 0.5)
        XCTAssertEqual(grownFrame.origin.x, expectedFrame.origin.x)
        XCTAssertEqual(grownFrame.width, expectedFrame.width)
    }

    @MainActor
    func testReceiveContentMetricsIsIdempotentForARepeatedMeasurement() {
        let model = CapturePanelModel()
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        let initialContentHeight = panel.contentRect(forFrameRect: panel.frame).size.height
        let metrics = contentMetrics(ideal: initialContentHeight + 120, minimum: initialContentHeight)

        controller.receiveContentMetrics(metrics)
        let firstAppliedFrame = panel.frame

        controller.receiveContentMetrics(metrics)

        XCTAssertEqual(panel.frame, firstAppliedFrame)
    }

    @MainActor
    func testReceiveStashContentMetricsGrowsFromCompactAndShrinksAfterDismissal() {
        let model = CapturePanelModel()
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        let visibleFrame = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let displayScale = panel.screen?.backingScaleFactor ?? 1
        let policy = CapturePanelContentHeightPolicy(displayScale: displayScale)
        let compactMetrics = policy.metrics(editorHeight: 42, auxiliaryHeight: nil, footerHeight: 40)
        let stashMetrics = policy.metrics(
            editorHeight: 42,
            auxiliary: CanceledDraftStashPickerHeightPolicy(
                entryCount: 1,
                displayScale: displayScale
            ).auxiliaryHeight,
            footerHeight: 40
        )
        let sizer = CapturePanelWindowSizer(displayScale: displayScale)
        let expectedStashContentHeight = sizer.contentHeight(
            for: stashMetrics,
            availableScreenHeight: visibleFrame.height
        )
        let initialContentHeight = panel.contentRect(forFrameRect: panel.frame).height
        let chromeHeight = panel.frame.height - initialContentHeight
        let topY = min(
            visibleFrame.maxY - 20,
            visibleFrame.minY + expectedStashContentHeight + chromeHeight + 80
        )
        panel.setFrame(
            NSRect(
                x: visibleFrame.minX + 80,
                y: topY - panel.frame.height,
                width: panel.frame.width,
                height: panel.frame.height
            ),
            display: false
        )

        controller.receiveContentMetrics(compactMetrics)
        let compactFrame = panel.frame
        let compactContentHeight = panel.contentRect(forFrameRect: compactFrame).height

        controller.receiveContentMetrics(stashMetrics)
        let stashFrame = panel.frame

        XCTAssertGreaterThan(stashFrame.height, compactFrame.height)
        XCTAssertEqual(
            panel.contentRect(forFrameRect: stashFrame).height,
            expectedStashContentHeight,
            accuracy: 0.5
        )
        XCTAssertEqual(stashFrame.maxY, compactFrame.maxY, accuracy: 0.5)

        controller.receiveContentMetrics(stashMetrics)
        XCTAssertEqual(panel.frame, stashFrame)

        controller.receiveContentMetrics(compactMetrics)

        XCTAssertEqual(
            panel.contentRect(forFrameRect: panel.frame).height,
            compactContentHeight,
            accuracy: 0.5
        )
        XCTAssertLessThan(panel.frame.height, stashFrame.height)
    }

    @MainActor
    func testShowReplayRestoresCachedMetricsAfterFallbackSizedFrame() {
        let model = CapturePanelModel()
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        let metrics = contentMetrics(ideal: 320, minimum: 180)

        controller.receiveContentMetrics(metrics)
        let measuredContentHeight = panel.contentRect(forFrameRect: panel.frame).height

        panel.contentMinSize = CapturePanelLayout.panelMinimumContentSize
        panel.contentMaxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        panel.setContentSize(
            NSSize(
                width: panel.contentRect(forFrameRect: panel.frame).width,
                height: CapturePanelLayout.panelFallbackContentHeight
            )
        )
        XCTAssertNotEqual(panel.contentRect(forFrameRect: panel.frame).height, measuredContentHeight)

        controller.replayLatestContentMetricsForPresentation()

        XCTAssertEqual(
            panel.contentRect(forFrameRect: panel.frame).height,
            measuredContentHeight,
            accuracy: 0.5
        )
    }

    @MainActor
    func testMetricsReceivedBeforePanelCreationAreCachedForReplay() {
        let model = CapturePanelModel()
        let controller = CapturePanelController(model: model)
        let metrics = contentMetrics(ideal: 280, minimum: 180)

        controller.receiveContentMetrics(metrics)
        let panel = controller.makePanelIfNeeded()
        let expectedContentHeight = panel.contentMaxSize.height
        controller.replayLatestContentMetricsForPresentation()

        XCTAssertEqual(
            panel.contentRect(forFrameRect: panel.frame).height,
            expectedContentHeight,
            accuracy: 0.5
        )
    }

    @MainActor
    func testReceiveContentMetricsIgnoresDegenerateMeasurements() {
        let model = CapturePanelModel()
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        let initialFrame = panel.frame

        controller.receiveContentMetrics(contentMetrics(ideal: 0, minimum: 0))
        controller.receiveContentMetrics(contentMetrics(ideal: -40, minimum: 20))
        controller.receiveContentMetrics(contentMetrics(ideal: .nan, minimum: 20))
        controller.receiveContentMetrics(contentMetrics(ideal: .infinity, minimum: 20))

        XCTAssertEqual(panel.frame, initialFrame)
    }

    @MainActor
    func testWindowWillResizePinsHeightAndPassesWidthThrough() {
        let model = CapturePanelModel()
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        controller.receiveContentMetrics(contentMetrics(ideal: 300, minimum: 180))

        let tallerProposal = NSSize(width: panel.frame.width, height: panel.frame.height + 200)
        let resolvedForTaller = controller.windowWillResize(panel, to: tallerProposal)
        XCTAssertEqual(resolvedForTaller.height, panel.frame.height, accuracy: 0.5)

        let widerProposal = NSSize(width: panel.frame.width + 150, height: panel.frame.height)
        let resolvedForWider = controller.windowWillResize(panel, to: widerProposal)
        XCTAssertEqual(resolvedForWider.width, widerProposal.width)
        XCTAssertEqual(resolvedForWider.height, panel.frame.height, accuracy: 0.5)
    }

    func testKeyRouterMatchesCaptureShortcuts() {
        let router = CaptureKeyCommandRouter()

        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36)), .submit)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36, modifiers: .command)), .submitAndOpen)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36, modifiers: .shift)), .insertNewline)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36, modifiers: .option)), .insertNewline)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 38, modifiers: .control)), .insertBulletNewline)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 32, modifiers: .control)), .deleteToBeginningOfLine)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 53)), .escape)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 33, modifiers: .control)), .escape)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 33, modifiers: .control), completionVisible: true),
            .escape
        )
        XCTAssertNil(router.command(for: keyEvent(keyCode: 33)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 33, modifiers: .shift)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 33, modifiers: .command)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 33, modifiers: .option)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 33, modifiers: [.control, .shift])))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 33, modifiers: [.control, .command])))
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 8, modifiers: .control)), .stashDraftAndClose)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 8, modifiers: .control), completionVisible: true),
            .stashDraftAndClose
        )
        XCTAssertNil(router.command(for: keyEvent(keyCode: 8)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 8, modifiers: .command)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 8, modifiers: [.control, .shift])))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 8, modifiers: [.control, .command])))
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 1, modifiers: .control)), .toggleStashPicker)
        XCTAssertNil(router.command(for: keyEvent(keyCode: 1)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 1, modifiers: [.control, .shift])))
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36), completionVisible: true), .acceptCompletion)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .command), completionVisible: true),
            .acceptCompletion
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: [.command, .shift])),
            .submitAndOpen
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: [.command, .shift]), completionVisible: true),
            .acceptCompletion
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .shift), completionVisible: true),
            .insertNewline
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .option), completionVisible: true),
            .insertNewline
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 38, modifiers: .control), completionVisible: true),
            .insertBulletNewline
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 32, modifiers: .control), completionVisible: true),
            .deleteToBeginningOfLine
        )
        XCTAssertNil(router.command(for: keyEvent(keyCode: 38, modifiers: [.control, .shift])))
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 48), completionVisible: true), .acceptCompletion)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 125), completionVisible: true), .nextCompletion)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 126), completionVisible: true), .previousCompletion)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 45, modifiers: .control), completionVisible: true),
            .nextCompletion
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 35, modifiers: .control), completionVisible: true),
            .previousCompletion
        )
    }

    func testKeyRouterIsolatesTaskIDPromptCommands() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            completionVisible: true,
            stashPickerVisible: false,
            stashEntryCount: 0,
            taskIDPromptVisible: true
        )

        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36), context: context), .submitTaskIDPrompt)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 76), context: context), .submitTaskIDPrompt)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36, modifiers: .command), context: context), .consumeKey)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 53), context: context), .cancelTaskIDPrompt)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 33, modifiers: .control), context: context),
            .cancelTaskIDPrompt
        )
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 48), context: context), .consumeKey)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 125), context: context), .consumeKey)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 126), context: context), .consumeKey)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 8, modifiers: .control), context: context), .stashDraftAndClose)
        XCTAssertNil(router.command(for: keyEvent(keyCode: 0, characters: "a"), context: context))
    }

    func testKeyRouterMatchesStashPickerModalCommands() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            completionVisible: true,
            stashPickerVisible: true,
            stashEntryCount: 36
        )

        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36), context: context), .restoreSelectedStashEntry)
        XCTAssertNil(router.command(for: keyEvent(keyCode: 36, modifiers: .command), context: context))
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 53), context: context), .dismissStashPicker)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 33, modifiers: .control), context: context),
            .dismissStashPicker
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 1, modifiers: .control), context: context),
            .toggleStashPicker
        )
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 125), context: context), .nextStashEntry)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 126), context: context), .previousStashEntry)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 45, modifiers: .control), context: context),
            .nextStashEntry
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 35, modifiers: .control), context: context),
            .previousStashEntry
        )

        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 18, characters: "1"), context: context),
            .restoreStashEntry(0)
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 29, characters: "0"), context: context),
            .restoreStashEntry(9)
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 0, characters: "a"), context: context),
            .restoreStashEntry(10)
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 27, characters: "-"), context: context),
            .restoreStashEntry(13)
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 2, characters: "d"), context: context),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 2, characters: "D"), context: context),
            .clearCanceledDraftStash
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 2, modifiers: .shift, characters: "D"), context: context),
            .clearCanceledDraftStash
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 2, modifiers: .capsLock, characters: "D"), context: context),
            .clearCanceledDraftStash
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 14, characters: "e"), context: context),
            .restoreStashEntry(14)
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 6, characters: "z"), context: context),
            .restoreStashEntry(35)
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 45, characters: "n"), context: context),
            .restoreStashEntry(23)
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 35, characters: "p"), context: context),
            .restoreStashEntry(25)
        )
    }

    func testKeyRouterConsumesPrintableKeysWhileStashPickerIsModalButLeavesCommandShortcuts() {
        let router = CaptureKeyCommandRouter()
        let shortContext = CaptureKeyRoutingContext(stashPickerVisible: true, stashEntryCount: 2)

        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 2, modifiers: .shift, characters: "D"), context: shortContext),
            .clearCanceledDraftStash
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 2, modifiers: .control, characters: "d"), context: shortContext),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 2, modifiers: .option, characters: "d"), context: shortContext),
            .consumeKey
        )
        XCTAssertNil(
            router.command(for: keyEvent(keyCode: 2, modifiers: .command, characters: "d"), context: shortContext)
        )
        XCTAssertNil(
            router.command(
                for: keyEvent(keyCode: 2, modifiers: [.command, .shift], characters: "D"),
                context: shortContext
            )
        )
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 6, characters: "z"), context: shortContext), .consumeKey)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 6, modifiers: .shift, characters: "Z"), context: shortContext),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 6, modifiers: .option, characters: "Ω"), context: shortContext),
            .consumeKey
        )
        XCTAssertNil(
            router.command(for: keyEvent(keyCode: 6, modifiers: .command, characters: "z"), context: shortContext)
        )
        XCTAssertNil(
            router.command(for: keyEvent(keyCode: 18, modifiers: .command, characters: "1"), context: shortContext)
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 18, modifiers: .shift, characters: "!"), context: shortContext),
            .consumeKey
        )
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 49, characters: " "), context: shortContext), .consumeKey)
    }

    func testKeyRouterMatchesControlJAsBulletNewlineOnlyWithControlModifier() {
        let router = CaptureKeyCommandRouter()

        XCTAssertEqual(router.command(for: keyEvent(keyCode: 38, modifiers: .control)), .insertBulletNewline)
        XCTAssertNil(router.command(for: keyEvent(keyCode: 38)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 38, modifiers: .shift)))
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 38, modifiers: .control), completionVisible: true),
            .insertBulletNewline
        )
    }

    func testKeyRouterMatchesTabIndentationAndPreservesCompletionAcceptance() {
        let router = CaptureKeyCommandRouter()

        XCTAssertEqual(router.command(for: keyEvent(keyCode: 48)), .increaseBulletIndentation)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 48), completionVisible: true), .acceptCompletion)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 48, modifiers: .shift)), .decreaseBulletIndentation)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 48, modifiers: .shift), completionVisible: true),
            .decreaseBulletIndentation
        )
        XCTAssertNil(router.command(for: keyEvent(keyCode: 48, modifiers: .command)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 48, modifiers: .option)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 48, modifiers: .control)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 48, modifiers: [.command, .shift])))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 48, modifiers: [.option, .shift])))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 48, modifiers: [.control, .shift])))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 48, modifiers: [.command, .option])))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 48, modifiers: .command), completionVisible: true))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 48, modifiers: .option), completionVisible: true))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 48, modifiers: .control), completionVisible: true))
    }

    func testKeyRouterMatchesControlUAsLinePrefixDeletionOnlyWithControlModifier() {
        let router = CaptureKeyCommandRouter()

        XCTAssertEqual(router.command(for: keyEvent(keyCode: 32, modifiers: .control)), .deleteToBeginningOfLine)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 32, modifiers: .control), completionVisible: true),
            .deleteToBeginningOfLine
        )
        XCTAssertNil(router.command(for: keyEvent(keyCode: 32)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 32, modifiers: .shift)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 32, modifiers: .command)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 32, modifiers: .option)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 32, modifiers: [.control, .shift])))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 32, modifiers: [.control, .command])))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 32, modifiers: [.control, .option])))
    }

    func testKeyRouterMatchesPlainBackspaceButNotModifiedVariants() {
        let router = CaptureKeyCommandRouter()

        XCTAssertEqual(router.command(for: keyEvent(keyCode: 51)), .deleteBackward)
        XCTAssertNil(router.command(for: keyEvent(keyCode: 51, modifiers: .shift)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 51, modifiers: .option)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 51, modifiers: .command)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 51, modifiers: .control)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 51, modifiers: [.control, .shift])))
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 51), completionVisible: true),
            .deleteBackward
        )
    }

    @MainActor
    func testEmptyBulletRowDeletionRangeRemovesMiddleRowAndPrecedingNewline() {
        let textView = NSTextView(frame: .zero)
        textView.string = "Parent\n- \nChild"
        // Caret right after the placeholder's trailing space, before its own newline --
        // exactly where the caret sits right after Ctrl-J inserted the row.
        textView.setSelectedRange(NSRange(location: 9, length: 0))

        let range = CapturePanelController.emptyBulletRowDeletionRange(in: textView)

        XCTAssertEqual(range, NSRange(location: 6, length: 3))
    }

    @MainActor
    func testEmptyBulletRowDeletionRangeRemovesOnlyRowContentOnFirstLine() {
        let textView = NSTextView(frame: .zero)
        textView.string = "- \nChild"
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        let range = CapturePanelController.emptyBulletRowDeletionRange(in: textView)

        XCTAssertEqual(range, NSRange(location: 0, length: 2))
    }

    @MainActor
    func testEmptyBulletRowDeletionRangeIgnoresNonCollapsedSelection() {
        let textView = NSTextView(frame: .zero)
        textView.string = "Parent\n- \nChild"
        textView.setSelectedRange(NSRange(location: 7, length: 1))

        XCTAssertNil(CapturePanelController.emptyBulletRowDeletionRange(in: textView))
    }

    @MainActor
    func testEmptyBulletRowDeletionRangeIgnoresNonPlaceholderRows() {
        let textView = NSTextView(frame: .zero)
        textView.string = "Parent\n- attach checklist\nChild"
        textView.setSelectedRange(NSRange(location: 9, length: 0))

        XCTAssertNil(CapturePanelController.emptyBulletRowDeletionRange(in: textView))
    }

    @MainActor
    func testEmptyBulletRowDeletionRangeIgnoresOrdinaryLines() {
        let textView = NSTextView(frame: .zero)
        textView.string = "Parent text\nChild"
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        XCTAssertNil(CapturePanelController.emptyBulletRowDeletionRange(in: textView))
    }

    @MainActor
    func testEscapeClosesOnceAndRetainsNonemptyDraft() {
        let model = CapturePanelModel()
        model.plainDraft = "Call bank @Cash"
        let controller = CapturePanelController(model: model)
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        XCTAssertTrue(controller.perform(.escape))

        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(model.plainDraft, "Call bank @Cash")
        XCTAssertEqual(model.statusText, "Draft retained")
    }

    @MainActor
    func testEscapeDismissesCompletionBeforeClosingPanel() {
        let model = CapturePanelModel()
        model.plainDraft = "idea @ma"
        model.completionResponse = sampleCompletionResponse()
        let controller = CapturePanelController(model: model)
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        XCTAssertTrue(controller.perform(.escape))

        XCTAssertEqual(dismissCount, 0)
        XCTAssertNil(model.completionResponse)

        XCTAssertTrue(controller.perform(.escape))

        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(model.plainDraft, "idea @ma")
        XCTAssertEqual(model.statusText, "Draft retained")
    }

    @MainActor
    func testDiscardAndCloseClearsDraftCompletionAndDismisses() {
        let model = CapturePanelModel()
        model.plainDraft = "idea @ma"
        model.completionResponse = sampleCompletionResponse()
        let controller = CapturePanelController(model: model)
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        XCTAssertTrue(controller.perform(.discardAndClose))

        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertNil(model.completionResponse)
    }

    @MainActor
    func testStashDraftAndCloseCommandStoresDraftAndDismisses() {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        model.plainDraft = "idea @ma"
        let controller = CapturePanelController(model: model)
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        XCTAssertTrue(controller.perform(.stashDraftAndClose))

        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertEqual(stash.entries.map(\.text), ["idea @ma"])
    }

    @MainActor
    func testClearCanceledDraftStashCommandConsumesClearsAndKeepsPanelOpen() {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        stash.push("older private draft")
        stash.push("newer private draft")
        model.presentStashPicker()
        model.selectedStashIndex = 1
        let controller = CapturePanelController(model: model)
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        XCTAssertTrue(controller.perform(.clearCanceledDraftStash))

        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertFalse(model.isStashPickerPresented)
        XCTAssertEqual(model.selectedStashIndex, 0)
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertEqual(model.statusText, "Canceled draft stash cleared")
        XCTAssertEqual(dismissCount, 0)
        XCTAssertEqual(model.focusRequest.target, .editor)
    }

    @MainActor
    func testCancelTaskIDPromptCommandRestoresSelectionAndEditorFocus() {
        let model = CapturePanelModel()
        model.plainDraft = "note @Cash+goog"
        model.completionResponse = sampleMissingTaskCompletionResponse()
        model.selectedCompletionIndex = 1
        let controller = CapturePanelController(model: model)

        XCTAssertTrue(controller.perform(.acceptCompletion))
        let promptFocusSequence = model.focusRequest.sequence
        XCTAssertTrue(controller.perform(.cancelTaskIDPrompt))

        XCTAssertNil(model.taskIDPrompt)
        XCTAssertTrue(model.completionVisible)
        XCTAssertEqual(model.selectedCompletionIndex, 1)
        XCTAssertEqual(model.focusRequest.target, .editor)
        XCTAssertGreaterThan(model.focusRequest.sequence, promptFocusSequence)
    }

    func testEditorHeightPolicyUsesOneLineMinimumAndInjectedCap() {
        let policy = CaptureEditorHeightPolicy(
            lineHeight: 20,
            verticalPadding: 20,
            maximumHeight: 140,
            displayScale: 2
        )

        let oneLineHeight = policy.resolvedHeight(forMeasuredTextHeight: 0)
        let threeLineHeight = policy.resolvedHeight(forMeasuredTextHeight: 60)
        let cappedHeight = policy.resolvedHeight(forMeasuredTextHeight: 120)
        let overflowingHeight = policy.resolvedHeight(forMeasuredTextHeight: 180)
        let pixelRoundedHeight = policy.resolvedHeight(forMeasuredTextHeight: 21.25)

        XCTAssertEqual(oneLineHeight, 40)
        XCTAssertEqual(policy.resolvedHeight(forMeasuredTextHeight: 12), oneLineHeight)
        XCTAssertGreaterThan(threeLineHeight, oneLineHeight)
        XCTAssertEqual(threeLineHeight, 80)
        XCTAssertEqual(cappedHeight, 140)
        XCTAssertEqual(overflowingHeight, cappedHeight)
        XCTAssertEqual(pixelRoundedHeight, 41.5)
        XCTAssertEqual(policy.minimumHeight, 40)

        let tighterThanMinimum = CaptureEditorHeightPolicy(
            lineHeight: 20,
            verticalPadding: 20,
            maximumHeight: 10,
            displayScale: 2
        )
        XCTAssertEqual(
            tighterThanMinimum.resolvedHeight(forMeasuredTextHeight: 100),
            tighterThanMinimum.minimumHeight
        )
    }

    func testEditorHeightBudgetGrowsOnTallScreensAndReservesAuxiliary() {
        let footerHeight: CGFloat = 40
        let tallScreen: CGFloat = 1600
        let contentPolicy = CapturePanelContentHeightPolicy()
        let none = CaptureEditorHeightBudget(
            availableScreenHeight: tallScreen,
            footerHeight: footerHeight,
            auxiliary: nil,
            contentPolicy: contentPolicy
        )
        let overflowingAuxiliary = CaptureEditorHeightBudget(
            availableScreenHeight: tallScreen,
            footerHeight: footerHeight,
            auxiliary: .overflow(idealHeight: 200),
            contentPolicy: contentPolicy
        )
        let shortAuxiliary = CaptureEditorHeightBudget(
            availableScreenHeight: tallScreen,
            footerHeight: footerHeight,
            auxiliary: .overflow(idealHeight: 50),
            contentPolicy: contentPolicy
        )

        XCTAssertGreaterThan(none.maximumHeight, 152)
        XCTAssertEqual(
            none.maximumHeight - overflowingAuxiliary.maximumHeight,
            CapturePanelLayout.sectionSpacing + CapturePanelLayout.auxiliaryReservedHeight
        )
        XCTAssertEqual(
            none.maximumHeight - shortAuxiliary.maximumHeight,
            CapturePanelLayout.sectionSpacing + 50
        )

        let stash = CanceledDraftStashPickerHeightPolicy(entryCount: 1).auxiliaryHeight
        let withStash = CaptureEditorHeightBudget(
            availableScreenHeight: tallScreen,
            footerHeight: footerHeight,
            auxiliary: stash,
            contentPolicy: contentPolicy
        )
        XCTAssertGreaterThanOrEqual(
            none.maximumHeight - withStash.maximumHeight,
            CapturePanelLayout.sectionSpacing + stash.minimumVisibleHeight
        )
    }

    func testEditorHeightBudgetNeverDropsBelowOneLineMinimum() {
        let short = CaptureEditorHeightBudget(
            availableScreenHeight: 400,
            footerHeight: 40,
            auxiliary: nil
        )
        let tiny = CaptureEditorHeightBudget(
            availableScreenHeight: 80,
            footerHeight: 40,
            auxiliary: .overflow(idealHeight: 200)
        )

        XCTAssertGreaterThanOrEqual(short.maximumHeight, short.minimumEditorHeight)
        XCTAssertEqual(tiny.maximumHeight, tiny.minimumEditorHeight)
        XCTAssertGreaterThan(tiny.maximumHeight, 0)
    }

    func testEditorHeightBudgetFallsBackToPanelMaximumWhenScreenIsUnknown() {
        let footerHeight: CGFloat = 40
        let unknown = CaptureEditorHeightBudget(
            availableScreenHeight: nil,
            footerHeight: footerHeight,
            auxiliary: nil
        )
        let equivalentScreen = CaptureEditorHeightBudget(
            availableScreenHeight: CapturePanelLayout.panelMaximumContentHeight
                + 2 * CapturePanelLayout.panelScreenMargin,
            footerHeight: footerHeight,
            auxiliary: nil
        )

        XCTAssertEqual(unknown.maximumHeight, equivalentScreen.maximumHeight)
        XCTAssertEqual(
            unknown.maximumHeight,
            CapturePanelLayout.panelMaximumContentHeight
                - CapturePanelContentHeightPolicy().nonEditorChromeHeight(
                    footerHeight: footerHeight,
                    hasAuxiliary: false
                )
        )
    }

    func testLongDraftOnTallScreenResolvesToExactScreenLimit() {
        let availableScreenHeight: CGFloat = 900
        let footerHeight: CGFloat = 40
        let displayScale: CGFloat = 1
        let contentPolicy = CapturePanelContentHeightPolicy(displayScale: displayScale)
        let screenLimit = availableScreenHeight - 2 * CapturePanelLayout.panelScreenMargin

        let compactBudget = CaptureEditorHeightBudget(
            availableScreenHeight: availableScreenHeight,
            footerHeight: footerHeight,
            auxiliary: nil,
            contentPolicy: contentPolicy
        )
        let compactEditor = CaptureEditorHeightPolicy(
            maximumHeight: compactBudget.maximumHeight,
            displayScale: displayScale
        ).resolvedHeight(forMeasuredTextHeight: 10_000)
        let compactMetrics = contentPolicy.metrics(
            editorHeight: compactEditor,
            auxiliaryHeight: nil,
            footerHeight: footerHeight
        )
        let sizer = CapturePanelWindowSizer(
            maximumContentHeight: nil,
            displayScale: displayScale
        )

        XCTAssertEqual(compactEditor, compactBudget.maximumHeight)
        XCTAssertEqual(compactMetrics.idealContentHeight, screenLimit)
        XCTAssertEqual(
            sizer.contentHeight(for: compactMetrics, availableScreenHeight: availableScreenHeight),
            screenLimit
        )

        let auxiliary = CapturePanelAuxiliaryHeight.overflow(
            idealHeight: CapturePanelLayout.auxiliaryReservedHeight
        )
        let auxiliaryBudget = CaptureEditorHeightBudget(
            availableScreenHeight: availableScreenHeight,
            footerHeight: footerHeight,
            auxiliary: auxiliary,
            contentPolicy: contentPolicy
        )
        let auxiliaryEditor = CaptureEditorHeightPolicy(
            maximumHeight: auxiliaryBudget.maximumHeight,
            displayScale: displayScale
        ).resolvedHeight(forMeasuredTextHeight: 10_000)
        let auxiliaryMetrics = contentPolicy.metrics(
            editorHeight: auxiliaryEditor,
            auxiliary: auxiliary,
            footerHeight: footerHeight
        )

        XCTAssertEqual(auxiliaryEditor, auxiliaryBudget.maximumHeight)
        XCTAssertEqual(auxiliaryMetrics.idealContentHeight, screenLimit)
        XCTAssertEqual(
            sizer.contentHeight(for: auxiliaryMetrics, availableScreenHeight: availableScreenHeight),
            screenLimit
        )
    }

    @MainActor
    func testCompletionAcceptanceUsesServerByteReplacementRange() {
        let model = CapturePanelModel()
        model.plainDraft = "idea @ma"
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: 8,
            replacement: CaptureRange(start: 6, end: 8),
            context: "route",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "mac_inbox",
                    route: "mac_inbox",
                    label: "mac_inbox.md",
                    kind: "inbox"
                )
            ]
        )

        model.acceptSelectedCompletion()

        XCTAssertEqual(model.plainDraft, "idea @mac_inbox")
        XCTAssertNil(model.completionResponse)
    }

    @MainActor
    func testCompletionAcceptanceUsesServerCursorAfter() {
        let model = CapturePanelModel()
        model.plainDraft = "open [[AI"
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: 9,
            replacement: CaptureRange(start: 7, end: 9),
            context: "wikilink_note",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "Artificial Intelligence|AI]]",
                    cursorAfter: "open [[Artificial Intelligence|AI]]".utf8.count
                )
            ]
        )

        model.acceptSelectedCompletion()

        XCTAssertEqual(model.plainDraft, "open [[Artificial Intelligence|AI]]")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), "open [[Artificial Intelligence|AI]]".utf8.count)
        XCTAssertNil(model.completionResponse)
    }

    @MainActor
    func testCompletionAcceptanceRejectsStaleCursorAfterWithoutChangingDraft() {
        let model = CapturePanelModel()
        model.plainDraft = "open [[AI"
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: 9,
            replacement: CaptureRange(start: 7, end: 9),
            context: "wikilink_note",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "Artificial Intelligence|AI]]",
                    cursorAfter: 1_000
                )
            ]
        )

        model.acceptSelectedCompletion()

        XCTAssertEqual(model.plainDraft, "open [[AI")
        XCTAssertEqual(model.statusText, "Completion cursor is stale")
        XCTAssertNil(model.completionResponse)
    }

    @MainActor
    func testInsertNewlineUsesEditableTextViewResponder() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "ab"
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        XCTAssertTrue(
            CapturePanelController.insertNewlineInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "a\nb")
        XCTAssertNil(model.completionResponse)
    }

    @MainActor
    func testInsertNewlineDeclinesUnrelatedResponder() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        XCTAssertFalse(
            CapturePanelController.insertNewlineInEditableTextView(
                firstResponder: NSButton(title: "Preview", target: nil, action: nil),
                model: model
            )
        )
        XCTAssertNotNil(model.completionResponse)
    }

    @MainActor
    func testInsertBulletNewlineReplacesSelectionAndLeavesCaretAfterTheSpace() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "Prepare the launch review"
        textView.setSelectedRange(NSRange(location: 25, length: 0))

        XCTAssertTrue(
            CapturePanelController.insertBulletNewlineInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "Prepare the launch review\n- ")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 28, length: 0))
        XCTAssertNil(model.completionResponse)
    }

    @MainActor
    func testInsertBulletNewlineSplitsTheDraftInTheMiddleAndConsumesTheSelection() {
        let model = CapturePanelModel()

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "Parent\n- confirm owner"
        // Select "confirm" so the new row replaces it rather than appending after it.
        textView.setSelectedRange(NSRange(location: 9, length: 7))

        XCTAssertTrue(
            CapturePanelController.insertBulletNewlineInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "Parent\n- \n-  owner")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 12, length: 0))
    }

    func testBulletNewlineResolverCopiesSupportedAuthoredIndentation() throws {
        let topLevel = try applyBulletEdit(
            text: "Parent\n- child",
            selectedRange: NSRange(location: "Parent\n- child".utf16.count, length: 0)
        )
        XCTAssertEqual(topLevel.text, "Parent\n- child\n- ")
        XCTAssertEqual(topLevel.selection, NSRange(location: "Parent\n- child\n- ".utf16.count, length: 0))

        let nested = try applyBulletEdit(
            text: "Parent\n  - child",
            selectedRange: NSRange(location: "Parent\n  - child".utf16.count, length: 0)
        )
        XCTAssertEqual(nested.text, "Parent\n  - child\n  - ")
        XCTAssertEqual(nested.selection, NSRange(location: "Parent\n  - child\n  - ".utf16.count, length: 0))

        let parentRow = try applyBulletEdit(
            text: "Parent",
            selectedRange: NSRange(location: "Parent".utf16.count, length: 0)
        )
        XCTAssertEqual(parentRow.text, "Parent\n- ")
    }

    func testBulletNewlineResolverTurnsPlaceholderIntoOneSeparatorAtEOF() throws {
        let resolved = try applyBulletEdit(
            text: "Parent\n- ",
            selectedRange: NSRange(location: "Parent\n- ".utf16.count, length: 0)
        )

        XCTAssertEqual(resolved.text, "Parent\n\n")
        XCTAssertEqual(resolved.selection, NSRange(location: "Parent\n\n".utf16.count, length: 0))
    }

    func testBulletNewlineResolverTurnsWhitespaceWrappedPlaceholderIntoSeparatorBeforeNextLine() throws {
        for marker in ["-", "*", "+"] {
            let text = "Parent\n  \(marker)   \nChild"
            let selectedRange = NSRange(location: "Parent\n  \(marker)".utf16.count, length: 0)

            let resolved = try applyBulletEdit(text: text, selectedRange: selectedRange)

            XCTAssertEqual(resolved.text, "Parent\n\nChild")
            XCTAssertEqual(resolved.selection, NSRange(location: "Parent\n\n".utf16.count, length: 0))
        }
    }

    func testBulletNewlineResolverReusesCRLFTerminatorForPlaceholder() throws {
        let text = "Parent\r\n+ \r\nChild"

        let resolved = try applyBulletEdit(
            text: text,
            selectedRange: NSRange(location: "Parent\r\n+".utf16.count, length: 0)
        )

        XCTAssertEqual(resolved.text, "Parent\r\n\r\nChild")
        XCTAssertEqual(resolved.selection, NSRange(location: "Parent\r\n\r\n".utf16.count, length: 0))
    }

    func testBulletNewlineResolverKeepsSelectionReplacementBehaviorOnPlaceholderSelection() throws {
        let text = "Parent\n- \nChild"

        let resolved = try applyBulletEdit(
            text: text,
            selectedRange: NSRange(location: "Parent\n".utf16.count, length: "- \n".utf16.count)
        )

        XCTAssertEqual(resolved.text, "Parent\n\n- Child")
        XCTAssertEqual(resolved.selection, NSRange(location: "Parent\n\n- ".utf16.count, length: 0))
    }

    @MainActor
    func testInsertBulletNewlineDeclinesNoneditableAndUnrelatedResponders() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        let noneditable = NSTextView()
        noneditable.isEditable = false
        noneditable.string = "Prepare the launch review"

        XCTAssertFalse(
            CapturePanelController.insertBulletNewlineInEditableTextView(
                firstResponder: noneditable,
                model: model
            )
        )
        XCTAssertFalse(
            CapturePanelController.insertBulletNewlineInEditableTextView(
                firstResponder: NSButton(title: "Preview", target: nil, action: nil),
                model: model
            )
        )
        XCTAssertFalse(
            CapturePanelController.insertBulletNewlineInEditableTextView(
                firstResponder: nil,
                model: model
            )
        )
        XCTAssertEqual(noneditable.string, "Prepare the launch review")
        XCTAssertNotNil(model.completionResponse)
    }

    func testBulletIndentationEditIncreasesColumnZeroMarkersToTwoSpaces() {
        for marker in ["-", "*", "+"] {
            let text = "Parent\n\(marker) confirm owner" as NSString

            let edit = CapturePanelController.bulletIndentationEdit(
                direction: .increase,
                in: text,
                selectedRange: NSRange(location: 7, length: 0)
            )

            XCTAssertEqual(
                edit,
                CaptureBulletIndentationEdit(
                    replacementRange: NSRange(location: 7, length: 0),
                    replacementText: "  ",
                    resultingSelection: NSRange(location: 9, length: 0)
                ),
                "marker \(marker)"
            )
        }
    }

    func testBulletIndentationEditDecreasesTwoSpaceMarkersToColumnZero() {
        for marker in ["-", "*", "+"] {
            let text = "Parent\n  \(marker) confirm owner" as NSString

            let edit = CapturePanelController.bulletIndentationEdit(
                direction: .decrease,
                in: text,
                selectedRange: NSRange(location: 9, length: 0)
            )

            XCTAssertEqual(
                edit,
                CaptureBulletIndentationEdit(
                    replacementRange: NSRange(location: 7, length: 2),
                    replacementText: "",
                    resultingSelection: NSRange(location: 7, length: 0)
                ),
                "marker \(marker)"
            )
        }
    }

    func testBulletIndentationEditHandlesEmptyPlaceholderRowsInBothDirections() {
        let bareTopLevel = "Parent\n-" as NSString
        XCTAssertEqual(
            CapturePanelController.bulletIndentationEdit(
                direction: .increase,
                in: bareTopLevel,
                selectedRange: NSRange(location: 8, length: 0)
            ),
            CaptureBulletIndentationEdit(
                replacementRange: NSRange(location: 7, length: 0),
                replacementText: "  ",
                resultingSelection: NSRange(location: 10, length: 0)
            )
        )

        let spacedTopLevel = "Parent\n- " as NSString
        XCTAssertEqual(
            CapturePanelController.bulletIndentationEdit(
                direction: .increase,
                in: spacedTopLevel,
                selectedRange: NSRange(location: 9, length: 0)
            )?.replacementRange,
            NSRange(location: 7, length: 0)
        )

        let bareNested = "Parent\n  -" as NSString
        XCTAssertEqual(
            CapturePanelController.bulletIndentationEdit(
                direction: .decrease,
                in: bareNested,
                selectedRange: NSRange(location: 10, length: 0)
            ),
            CaptureBulletIndentationEdit(
                replacementRange: NSRange(location: 7, length: 2),
                replacementText: "",
                resultingSelection: NSRange(location: 8, length: 0)
            )
        )
    }

    func testBulletIndentationEditTransformsCaretThroughThePrefixOnIncrease() {
        // Indices: Parent(0-5) \n(6) -(7) space(8) c(9) a(10) f(11) é(12) space(13) r-e-v-i-e-w(14-19).
        let text = "Parent\n- caf\u{00e9} review" as NSString

        XCTAssertEqual(
            CapturePanelController.bulletIndentationEdit(
                direction: .increase,
                in: text,
                selectedRange: NSRange(location: 7, length: 0)
            )?.resultingSelection,
            NSRange(location: 9, length: 0),
            "caret before the marker"
        )
        XCTAssertEqual(
            CapturePanelController.bulletIndentationEdit(
                direction: .increase,
                in: text,
                selectedRange: NSRange(location: 8, length: 0)
            )?.resultingSelection,
            NSRange(location: 10, length: 0),
            "caret after the marker"
        )
        XCTAssertEqual(
            CapturePanelController.bulletIndentationEdit(
                direction: .increase,
                in: text,
                selectedRange: NSRange(location: 13, length: 0)
            )?.resultingSelection,
            NSRange(location: 15, length: 0),
            "caret after Unicode body text"
        )
    }

    func testBulletIndentationEditTransformsCaretThroughThePrefixOnDecrease() {
        // Indices: Parent(0-5) \n(6) space(7) space(8) -(9) space(10) c-a-f-é(11-14) space(15) r...(16).
        let text = "Parent\n  - caf\u{00e9} review" as NSString

        XCTAssertEqual(
            CapturePanelController.bulletIndentationEdit(
                direction: .decrease,
                in: text,
                selectedRange: NSRange(location: 7, length: 0)
            )?.resultingSelection,
            NSRange(location: 7, length: 0),
            "caret at the line start, before the prefix"
        )
        XCTAssertEqual(
            CapturePanelController.bulletIndentationEdit(
                direction: .decrease,
                in: text,
                selectedRange: NSRange(location: 8, length: 0)
            )?.resultingSelection,
            NSRange(location: 7, length: 0),
            "caret inside the removed prefix clamps to the new line start"
        )
        XCTAssertEqual(
            CapturePanelController.bulletIndentationEdit(
                direction: .decrease,
                in: text,
                selectedRange: NSRange(location: 9, length: 0)
            )?.resultingSelection,
            NSRange(location: 7, length: 0),
            "caret on the marker"
        )
        XCTAssertEqual(
            CapturePanelController.bulletIndentationEdit(
                direction: .decrease,
                in: text,
                selectedRange: NSRange(location: 10, length: 0)
            )?.resultingSelection,
            NSRange(location: 8, length: 0),
            "caret after the marker"
        )
        XCTAssertEqual(
            CapturePanelController.bulletIndentationEdit(
                direction: .decrease,
                in: text,
                selectedRange: NSRange(location: 15, length: 0)
            )?.resultingSelection,
            NSRange(location: 13, length: 0),
            "caret after Unicode body text"
        )
    }

    func testBulletIndentationEditPreservesSameLineSelectionOnIncrease() {
        let text = "Parent\n- confirm owner" as NSString

        let edit = CapturePanelController.bulletIndentationEdit(
            direction: .increase,
            in: text,
            selectedRange: NSRange(location: 9, length: 7)
        )

        XCTAssertEqual(edit?.resultingSelection, NSRange(location: 11, length: 7))
    }

    func testBulletIndentationEditClampsOutdentSelectionThatIntersectsTheRemovedPrefix() {
        let text = "Parent\n  - confirm owner" as NSString
        // Covers the second prefix space through the marker and its trailing space.
        let selection = NSRange(location: 8, length: 3)

        let edit = CapturePanelController.bulletIndentationEdit(
            direction: .decrease,
            in: text,
            selectedRange: selection
        )

        XCTAssertEqual(edit?.resultingSelection, NSRange(location: 7, length: 2))
    }

    func testBulletIndentationEditChangesOnlyTheSelectedRowInACRLFDraft() {
        let text = "Parent\r\n- first\r\n- second" as NSString
        // Row 3 ("- second") starts at index 17; the caret sits inside "second".
        let selection = NSRange(location: 22, length: 0)

        let edit = CapturePanelController.bulletIndentationEdit(
            direction: .increase,
            in: text,
            selectedRange: selection
        )

        XCTAssertEqual(edit?.replacementRange, NSRange(location: 17, length: 0))
        XCTAssertEqual(edit?.replacementText, "  ")
        XCTAssertEqual(edit?.resultingSelection, NSRange(location: 24, length: 0))
    }

    func testBulletIndentationEditDeclinesPhysicalLineOneEvenWhenItLooksLikeABullet() {
        let text = "- looks like a bullet" as NSString
        let selection = NSRange(location: 2, length: 0)

        XCTAssertNil(
            CapturePanelController.bulletIndentationEdit(direction: .increase, in: text, selectedRange: selection)
        )
        XCTAssertNil(
            CapturePanelController.bulletIndentationEdit(direction: .decrease, in: text, selectedRange: selection)
        )
    }

    func testBulletIndentationEditDeclinesProseBlankAndMalformedRows() {
        let cases: [(name: String, draft: String, location: Int)] = [
            ("prose", "Parent\nJust prose", 8),
            ("blank row", "Parent\n", 7),
            ("marker glued to body", "Parent\n-body", 9),
            ("one leading space", "Parent\n - one space", 9),
            ("leading tab", "Parent\n\t- tab indented", 9),
            ("four leading spaces", "Parent\n    - four spaces", 11),
        ]

        for testCase in cases {
            let text = testCase.draft as NSString
            let selection = NSRange(location: testCase.location, length: 0)

            XCTAssertNil(
                CapturePanelController.bulletIndentationEdit(direction: .increase, in: text, selectedRange: selection),
                "increase should decline for \(testCase.name)"
            )
            XCTAssertNil(
                CapturePanelController.bulletIndentationEdit(direction: .decrease, in: text, selectedRange: selection),
                "decrease should decline for \(testCase.name)"
            )
        }
    }

    func testBulletIndentationEditDeclinesWhenAlreadyAtTheTargetDepth() {
        let alreadyNested = "Parent\n  - nested already" as NSString
        XCTAssertNil(
            CapturePanelController.bulletIndentationEdit(
                direction: .increase,
                in: alreadyNested,
                selectedRange: NSRange(location: 10, length: 0)
            )
        )

        let alreadyTopLevel = "Parent\n- top level already" as NSString
        XCTAssertNil(
            CapturePanelController.bulletIndentationEdit(
                direction: .decrease,
                in: alreadyTopLevel,
                selectedRange: NSRange(location: 8, length: 0)
            )
        )
    }

    func testBulletIndentationEditDeclinesMultilineSelections() {
        let text = "Parent\n- first\n- second" as NSString
        // Starts inside "first" and extends past its line delimiter into "second".
        let selection = NSRange(location: 10, length: 10)

        XCTAssertNil(
            CapturePanelController.bulletIndentationEdit(direction: .increase, in: text, selectedRange: selection)
        )
        XCTAssertNil(
            CapturePanelController.bulletIndentationEdit(direction: .decrease, in: text, selectedRange: selection)
        )
    }

    @MainActor
    func testApplyBulletIndentationEditsTheBackingTextViewAndDismissesCompletion() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "Parent\n- confirm owner"
        textView.setSelectedRange(NSRange(location: 9, length: 0))

        XCTAssertTrue(
            CapturePanelController.applyBulletIndentation(.increase, firstResponder: textView, model: model)
        )
        XCTAssertEqual(textView.string, "Parent\n  - confirm owner")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 11, length: 0))
        XCTAssertNil(model.completionResponse)
    }

    @MainActor
    func testApplyBulletIndentationOutdentsAndDismissesCompletion() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "Parent\n  - confirm owner"
        textView.setSelectedRange(NSRange(location: 11, length: 0))

        XCTAssertTrue(
            CapturePanelController.applyBulletIndentation(.decrease, firstResponder: textView, model: model)
        )
        XCTAssertEqual(textView.string, "Parent\n- confirm owner")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))
        XCTAssertNil(model.completionResponse)
    }

    @MainActor
    func testApplyBulletIndentationDeclinesAndPreservesCompletionWhenLineIsInapplicable() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "Parent\nJust prose"
        textView.setSelectedRange(NSRange(location: 10, length: 0))

        XCTAssertFalse(
            CapturePanelController.applyBulletIndentation(.increase, firstResponder: textView, model: model)
        )
        XCTAssertEqual(textView.string, "Parent\nJust prose")
        XCTAssertNotNil(model.completionResponse)
    }

    @MainActor
    func testApplyBulletIndentationDeclinesNoneditableUnrelatedAndNilResponders() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        let noneditable = NSTextView()
        noneditable.isEditable = false
        noneditable.string = "Parent\n- confirm owner"

        XCTAssertFalse(
            CapturePanelController.applyBulletIndentation(.increase, firstResponder: noneditable, model: model)
        )
        XCTAssertFalse(
            CapturePanelController.applyBulletIndentation(
                .decrease,
                firstResponder: NSButton(title: "Preview", target: nil, action: nil),
                model: model
            )
        )
        XCTAssertFalse(
            CapturePanelController.applyBulletIndentation(.increase, firstResponder: nil, model: model)
        )
        XCTAssertEqual(noneditable.string, "Parent\n- confirm owner")
        XCTAssertNotNil(model.completionResponse)
    }

    @MainActor
    func testDeleteToBeginningOfLineRemovesOnlyCurrentPhysicalLinePrefix() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "Prior line\nprefix 🧪 suffix"
        let caret = (textView.string as NSString).range(of: "🧪 suffix").location
        textView.setSelectedRange(NSRange(location: caret, length: 0))

        XCTAssertTrue(
            CapturePanelController.deleteToBeginningOfLineInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "Prior line\n🧪 suffix")
        XCTAssertEqual(
            textView.selectedRange(),
            NSRange(location: ("Prior line\n" as NSString).length, length: 0)
        )
        XCTAssertNil(model.completionResponse)
    }

    @MainActor
    func testDeleteToBeginningOfLineDeclinesNoneditableUnrelatedAndMissingResponders() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        let noneditable = NSTextView()
        noneditable.isEditable = false
        noneditable.string = "Prior line\nprefix suffix"
        noneditable.setSelectedRange(NSRange(location: 17, length: 0))

        XCTAssertFalse(
            CapturePanelController.deleteToBeginningOfLineInEditableTextView(
                firstResponder: noneditable,
                model: model
            )
        )
        XCTAssertFalse(
            CapturePanelController.deleteToBeginningOfLineInEditableTextView(
                firstResponder: NSButton(title: "Preview", target: nil, action: nil),
                model: model
            )
        )
        XCTAssertFalse(
            CapturePanelController.deleteToBeginningOfLineInEditableTextView(
                firstResponder: nil,
                model: model
            )
        )
        XCTAssertEqual(noneditable.string, "Prior line\nprefix suffix")
        XCTAssertNotNil(model.completionResponse)
    }

    @MainActor
    func testDeleteEmptyBulletRowRemovesFinalPlaceholderRowAndItsNewline() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "Parent\n- "
        textView.setSelectedRange(NSRange(location: 9, length: 0))

        XCTAssertTrue(
            CapturePanelController.deleteEmptyBulletRowInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "Parent")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertNil(model.completionResponse)
    }

    @MainActor
    func testDeleteEmptyBulletRowRemovesMiddlePlaceholderRowOnly() {
        let model = CapturePanelModel()

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "Parent\n- \n- confirm owner"
        textView.setSelectedRange(NSRange(location: 9, length: 0))

        XCTAssertTrue(
            CapturePanelController.deleteEmptyBulletRowInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "Parent\n- confirm owner")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 0))
    }

    @MainActor
    func testDeleteEmptyBulletRowRemovesFirstLinePlaceholderWithoutTouchingTheNewline() {
        let model = CapturePanelModel()

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "- \nChild"
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertTrue(
            CapturePanelController.deleteEmptyBulletRowInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "\nChild")
    }

    @MainActor
    func testDeleteEmptyBulletRowPassesThroughOrdinaryBackspaceCases() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        let nonemptyBullet = NSTextView()
        nonemptyBullet.isEditable = true
        nonemptyBullet.string = "Parent\n- confirm owner"
        nonemptyBullet.setSelectedRange(NSRange(location: 22, length: 0))

        let selection = NSTextView()
        selection.isEditable = true
        selection.string = "Parent\n- "
        selection.setSelectedRange(NSRange(location: 7, length: 2))

        let noneditable = NSTextView()
        noneditable.isEditable = false
        noneditable.string = "Parent\n- "
        noneditable.setSelectedRange(NSRange(location: 9, length: 0))

        for textView in [nonemptyBullet, selection, noneditable] {
            let original = textView.string
            XCTAssertFalse(
                CapturePanelController.deleteEmptyBulletRowInEditableTextView(
                    firstResponder: textView,
                    model: model
                )
            )
            XCTAssertEqual(textView.string, original)
        }

        XCTAssertFalse(
            CapturePanelController.deleteEmptyBulletRowInEditableTextView(
                firstResponder: NSButton(title: "Preview", target: nil, action: nil),
                model: model
            )
        )
        XCTAssertNotNil(model.completionResponse)
    }

    func testHotKeyRegistrationConflictIsReported() {
        let conflictStatus = OSStatus(eventHotKeyExistsErr)
        let registrar = FakeHotKeyRegistrar(status: conflictStatus)
        let manager = HotKeyManager(registrar: registrar) {}

        XCTAssertThrowsError(try manager.register(configuration: .development)) { error in
            XCTAssertEqual(
                error as? HotKeyRegistrationError,
                .registrationFailed(conflictStatus)
            )
        }
    }

    @MainActor
    func testProductionHotkeyIsTheDefaultAndDevelopmentChoicePersists() {
        let suiteName = "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertEqual(AppSettings(defaults: defaults).hotKeyConfiguration, .production)

        defaults.set(false, forKey: "useProductionHotkey")
        XCTAssertEqual(AppSettings(defaults: defaults).hotKeyConfiguration, .development)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testCanceledDraftStashCapacityDefaultsPersistsAndClamps() {
        let suiteName = "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.canceledDraftStashCapacity, 10)

        settings.canceledDraftStashCapacity = 24
        XCTAssertEqual(defaults.integer(forKey: "canceledDraftStashCapacity"), 24)
        XCTAssertEqual(AppSettings(defaults: defaults).canceledDraftStashCapacity, 24)

        settings.canceledDraftStashCapacity = 999
        XCTAssertEqual(settings.canceledDraftStashCapacity, 36)
        XCTAssertEqual(defaults.integer(forKey: "canceledDraftStashCapacity"), 36)

        settings.canceledDraftStashCapacity = -5
        XCTAssertEqual(settings.canceledDraftStashCapacity, 0)
        XCTAssertEqual(defaults.integer(forKey: "canceledDraftStashCapacity"), 0)

        defaults.set("not an integer", forKey: "canceledDraftStashCapacity")
        XCTAssertEqual(AppSettings(defaults: defaults).canceledDraftStashCapacity, 10)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testStashCapacityPropagationTrimsImmediatelyAndPayloadsStayOutOfDefaultsAndDiagnostics() {
        let suiteName = "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        let stash = CanceledDraftStash(capacity: settings.canceledDraftStashCapacity)
        let cancellable = settings.$canceledDraftStashCapacity.sink { capacity in
            stash.updateCapacity(capacity)
        }
        let secret = "private canceled draft"

        stash.push("old")
        stash.push(secret)
        settings.canceledDraftStashCapacity = 1

        XCTAssertEqual(stash.entries.map(\.text), [secret])
        XCTAssertEqual(defaults.integer(forKey: "canceledDraftStashCapacity"), 1)
        XCTAssertFalse(defaults.dictionaryRepresentation().description.contains(secret))

        settings.diagnosticStatus = "Canceled draft stashed"
        XCTAssertFalse(settings.diagnosticHistory.description.contains(secret))
        cancellable.cancel()
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testInfoPlistDeclaresUiElementAndBundleIdentity() throws {
        let plistURL = packageRoot().appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "org.bobs.bob-mac-capture")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Bob Mac Capture")
        XCTAssertEqual(plist["LSUIElement"] as? String, "1")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "26.0")
    }

    @MainActor
    func testMainMenuExposesStandardEditSelectorsAndQuit() throws {
        // Regression guard for the AppKit entry-point migration: without an explicit
        // main menu, the capture editor silently loses Cmd-X/C/V/A/Z and the app loses
        // Cmd-Q, since neither the SwiftUI app lifecycle nor a nib supplies one anymore.
        // Paste intentionally deviates from stock `paste:` so rich browser pasteboards
        // enter the capture grammar as plain text without a synchronous HTML import.
        let mainMenu = AppDelegate.makeMainMenu()

        XCTAssertEqual(mainMenu.items.count, 2)

        let editMenu = try XCTUnwrap(mainMenu.items[1].submenu)
        let editSelectors = editMenu.items.map { $0.action.map(NSStringFromSelector) }
        XCTAssertEqual(
            editSelectors,
            ["undo:", "redo:", nil, "cut:", "copy:", "pastePlainText:", "selectAll:"]
        )
        XCTAssertEqual(editMenu.items.map(\.keyEquivalent), ["z", "z", "", "x", "c", "v", "a"])
        XCTAssertEqual(editMenu.items[1].keyEquivalentModifierMask, [.command, .shift])

        let appMenu = try XCTUnwrap(mainMenu.items[0].submenu)
        let quitItem = try XCTUnwrap(appMenu.items.last)
        XCTAssertEqual(quitItem.title, "Quit Bob Mac Capture")
        XCTAssertEqual(quitItem.action, #selector(NSApplication.terminate(_:)))
        XCTAssertEqual(quitItem.keyEquivalent, "q")
    }

    @MainActor
    func testMenuValidationLeavesUnrelatedSelectorsEnabled() {
        let delegate = AppDelegate()
        let menuItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")

        XCTAssertTrue(delegate.validateMenuItem(menuItem))
    }

    @MainActor
    func testStatusMenuOffersRestartBeforeQuit() {
        // Regression guard for the restart flow: Restart must sit directly below the
        // separator and directly above Quit, and every item's action/key-equivalent
        // must match what configureStatusItem() wires up.
        let menu = AppDelegate.makeStatusMenu()

        XCTAssertEqual(
            menu.items.map(\.title),
            ["Capture", "Settings", "Recheck Bob", "", "Restart Bob Mac Capture", "Quit Bob Mac Capture"]
        )
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        XCTAssertEqual(
            menu.items.map { $0.action.map(NSStringFromSelector) },
            ["openCapturePanel", "openSettings", "recheckBob", nil, "restartApp", "quit"]
        )
        XCTAssertEqual(menu.items.map(\.keyEquivalent), ["", ",", "", "", "", "q"])
    }

    @MainActor
    func testOpenSettingsMenuActionUsesRegisteredSettingsPresenterOnce() {
        let delegate = AppDelegate()
        var openSettingsCount = 0
        var activationCount = 0
        delegate.settingsPresentation = SettingsPresentation(
            openSettings: {
                openSettingsCount += 1
            },
            activateApplication: {
                activationCount += 1
            }
        )

        delegate.openSettings()

        XCTAssertEqual(openSettingsCount, 1)
        XCTAssertEqual(activationCount, 1)
    }

    @MainActor
    func testDiagnosticHistoryRecordsChangesAndStaysBounded() {
        let defaults = UserDefaults(suiteName: "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)

        settings.diagnosticStatus = "Starting"
        XCTAssertTrue(settings.diagnosticHistory.isEmpty, "Setting the same value must not record a duplicate")

        for index in 0..<25 {
            settings.diagnosticStatus = "Status \(index)"
        }

        XCTAssertEqual(settings.diagnosticHistory.count, 20)
        XCTAssertFalse(settings.diagnosticHistory.contains { $0.hasSuffix("Status 0") })
        XCTAssertTrue(settings.diagnosticHistory.contains { $0.hasSuffix("Status 24") })
    }

    func testLaunchAtLoginStateMapping() {
        XCTAssertTrue(LaunchAtLoginState(status: .enabled).enabled)
        XCTAssertFalse(LaunchAtLoginState(status: .notRegistered).enabled)
        XCTAssertFalse(LaunchAtLoginState(status: .requiresApproval).enabled)
        XCTAssertFalse(LaunchAtLoginState(status: .notFound).enabled)
    }

    @MainActor
    private func sampleCompletionResponse() -> CaptureCompletionResponse {
        CaptureCompletionResponse(
            ok: true,
            cursor: 8,
            replacement: CaptureRange(start: 6, end: 8),
            context: "route",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "mac_inbox",
                    route: "mac_inbox",
                    label: "mac_inbox.md",
                    kind: "inbox"
                )
            ]
        )
    }

    private func sampleMissingTaskCompletionResponse() -> CaptureCompletionResponse {
        CaptureCompletionResponse(
            ok: true,
            cursor: 15,
            replacement: CaptureRange(start: 11, end: 15),
            context: "task",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "goog-exit",
                    route: "cash",
                    taskRef: "4:googexit",
                    blockID: "goog-exit",
                    requiresBlockID: false,
                    statusSymbol: "*",
                    statusName: "Next",
                    statusType: "ON_HOLD",
                    text: "Finish Google Exit Packet!",
                    section: "Tasks",
                    depth: 1,
                    childCount: 1
                ),
                CaptureCompletionCandidate(
                    replacement: "",
                    route: "cash",
                    taskRef: "8:missingidea",
                    blockID: nil,
                    requiresBlockID: true,
                    statusSymbol: " ",
                    statusName: "Todo",
                    statusType: "TODO",
                    text: "Plan the handoff",
                    section: "Tasks",
                    depth: 1,
                    childCount: 0
                ),
            ]
        )
    }

    private enum BulletEditTestError: Error {
        case unresolved
    }

    private func applyBulletEdit(
        text: String,
        selectedRange: NSRange
    ) throws -> (text: String, selection: NSRange) {
        guard let edit = CaptureBulletNewlineEditResolver.resolve(
            in: text,
            selectedRange: selectedRange
        ) else {
            throw BulletEditTestError.unresolved
        }
        let result = NSMutableString(string: text)
        result.replaceCharacters(in: edit.replacementRange, with: edit.replacementText)
        return (String(result), edit.selectedRange)
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String = ""
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

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contentMetrics(ideal: CGFloat, minimum: CGFloat) -> CapturePanelContentMetrics {
        CapturePanelContentMetrics(
            idealContentHeight: ideal,
            minimumVisibleContentHeight: minimum
        )
    }
}

private final class FakeHotKeyRegistrar: HotKeyRegistering {
    let status: OSStatus

    init(status: OSStatus) {
        self.status = status
    }

    func register(
        configuration: HotKeyConfiguration,
        identifier: EventHotKeyID,
        reference: UnsafeMutablePointer<EventHotKeyRef?>?
    ) -> OSStatus {
        status
    }

    func unregister(reference: EventHotKeyRef) {}
}
