import AppKit
import Carbon
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
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 8, modifiers: .control)), .discardAndClose)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 8, modifiers: .control), completionVisible: true),
            .discardAndClose
        )
        XCTAssertNil(router.command(for: keyEvent(keyCode: 8)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 8, modifiers: .command)))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 8, modifiers: [.control, .shift])))
        XCTAssertNil(router.command(for: keyEvent(keyCode: 8, modifiers: [.control, .command])))
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

    func testEditorHeightPolicyUsesOneLineMinimumAndSixLineCap() {
        let policy = CaptureEditorHeightPolicy(
            lineHeight: 20,
            verticalPadding: 20,
            maximumVisibleLines: 6,
            displayScale: 2
        )

        let oneLineHeight = policy.resolvedHeight(forMeasuredTextHeight: 0)
        let threeLineHeight = policy.resolvedHeight(forMeasuredTextHeight: 60)
        let sixLineHeight = policy.resolvedHeight(forMeasuredTextHeight: 120)
        let overflowingHeight = policy.resolvedHeight(forMeasuredTextHeight: 180)

        XCTAssertEqual(oneLineHeight, 40)
        XCTAssertEqual(policy.resolvedHeight(forMeasuredTextHeight: 12), oneLineHeight)
        XCTAssertGreaterThan(threeLineHeight, oneLineHeight)
        XCTAssertEqual(threeLineHeight, 80)
        XCTAssertEqual(sixLineHeight, 140)
        XCTAssertEqual(overflowingHeight, sixLineHeight)
        XCTAssertEqual(policy.visibleLineCount(forMeasuredTextHeight: 0), 1)
        XCTAssertEqual(policy.visibleLineCount(forMeasuredTextHeight: 60), 3)
        XCTAssertEqual(policy.visibleLineCount(forMeasuredTextHeight: 180), 6)
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

    private func keyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
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
