import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Design-phase tests for the capture picker card: fixed-height sizing,
/// panel metrics wiring, footer hints, and the gated rendered-image review.
final class CapturePickerDesignTests: XCTestCase {
    func testPickerHeightPolicyMath() {
        let policy = CapturePickerHeightPolicy(visibleRowBudget: 11, displayScale: 1)

        // listViewport = 2·padding + row·budget = 12 + 374
        XCTAssertEqual(policy.listViewportHeight, 386)
        // ideal = filterBar + 1 + listViewport + 1 + detail = 46 + 1 + 386 + 1 + 80
        XCTAssertEqual(policy.idealHeight, 514)
        // minimum uses 3 rows: 46 + 1 + (12 + 102) + 1 + 80
        XCTAssertEqual(policy.minimumVisibleHeight, 242)
        XCTAssertEqual(policy.auxiliaryHeight.idealHeight, 514)
        XCTAssertEqual(policy.auxiliaryHeight.minimumVisibleHeight, 242)
    }

    func testPickerHeightPolicyClampsBudget() {
        let oversized = CapturePickerHeightPolicy(visibleRowBudget: 99, displayScale: 1)
        let maxed = CapturePickerHeightPolicy(
            visibleRowBudget: CapturePanelLayout.pickerMaxRows,
            displayScale: 1
        )
        XCTAssertEqual(oversized.clampedBudget, CapturePanelLayout.pickerMaxRows)
        XCTAssertEqual(oversized.idealHeight, maxed.idealHeight)
        XCTAssertEqual(oversized.minimumVisibleHeight, maxed.minimumVisibleHeight)

        let empty = CapturePickerHeightPolicy(visibleRowBudget: 0, displayScale: 1)
        let single = CapturePickerHeightPolicy(visibleRowBudget: 1, displayScale: 1)
        XCTAssertEqual(empty.clampedBudget, 1)
        XCTAssertEqual(empty.idealHeight, single.idealHeight)
        // A one-row budget keeps its single row in the minimum too.
        XCTAssertEqual(empty.minimumRowCount, 1)
        XCTAssertEqual(empty.minimumVisibleHeight, empty.idealHeight)
    }

    func testPickerHeightPolicyPixelRounds() {
        let integral = CapturePickerHeightPolicy(visibleRowBudget: 7, displayScale: 2)
        // 2·6 + 34·7 = 250; 46 + 1 + 250 + 1 + 80 = 378
        XCTAssertEqual(integral.listViewportHeight, 250)
        XCTAssertEqual(integral.idealHeight, 378)

        let degenerateScale = CapturePickerHeightPolicy(visibleRowBudget: 7, displayScale: 0)
        XCTAssertEqual(degenerateScale.idealHeight, integral.idealHeight)
    }

    func testPickerHeightPolicyLayoutConstants() {
        XCTAssertEqual(CapturePanelLayout.pickerFilterBarHeight, 46)
        XCTAssertEqual(CapturePanelLayout.pickerRowHeight, 34)
        XCTAssertEqual(CapturePanelLayout.pickerSectionHeaderHeight, 26)
        XCTAssertEqual(CapturePanelLayout.pickerDetailStripHeight, 80)
        XCTAssertEqual(CapturePanelLayout.pickerMaxRows, 11)
        XCTAssertEqual(CapturePanelLayout.pickerMinRows, 3)
    }

    @MainActor
    func testPickerMetricsGrowFromCompactKeepHeightAcrossFiltersAndShrinkAfterCancel() {
        let model = CapturePanelModel()
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        let visibleFrame = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let displayScale = panel.screen?.backingScaleFactor ?? 1
        let contentPolicy = CapturePanelContentHeightPolicy(displayScale: displayScale)
        let compactMetrics = contentPolicy.metrics(editorHeight: 42, auxiliaryHeight: nil, footerHeight: 40)
        // The budget is fixed at open from the grouped snapshot, so two
        // different filters over the same snapshot share one height.
        let pickerAuxiliary = CapturePickerHeightPolicy(visibleRowBudget: 11, displayScale: displayScale)
            .auxiliaryHeight
        let pickerMetrics = contentPolicy.metrics(
            editorHeight: 42,
            auxiliary: pickerAuxiliary,
            footerHeight: 40
        )
        let sizer = CapturePanelWindowSizer(displayScale: displayScale)
        let expectedPickerContentHeight = sizer.contentHeight(
            for: pickerMetrics,
            availableScreenHeight: visibleFrame.height
        )
        let chromeHeight = panel.frame.height - panel.contentRect(forFrameRect: panel.frame).height
        let topY = min(
            visibleFrame.maxY - 20,
            visibleFrame.minY + expectedPickerContentHeight + chromeHeight + 80
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

        controller.receiveContentMetrics(pickerMetrics)
        let pickerFrame = panel.frame

        XCTAssertGreaterThan(pickerFrame.height, compactFrame.height)
        XCTAssertEqual(
            panel.contentRect(forFrameRect: pickerFrame).height,
            expectedPickerContentHeight,
            accuracy: 0.5
        )
        XCTAssertEqual(pickerFrame.maxY, compactFrame.maxY, accuracy: 0.5)

        // A filter change keeps the fixed budget, so re-reporting the same
        // metrics is a no-op on the frame.
        controller.receiveContentMetrics(pickerMetrics)
        XCTAssertEqual(panel.frame, pickerFrame)

        controller.receiveContentMetrics(compactMetrics)
        XCTAssertEqual(
            panel.contentRect(forFrameRect: panel.frame).height,
            compactContentHeight,
            accuracy: 0.5
        )
        XCTAssertLessThan(panel.frame.height, pickerFrame.height)
    }

    func testPickerMinimumHoldsOnShortScreen() {
        let displayScale: CGFloat = 1
        let contentPolicy = CapturePanelContentHeightPolicy(displayScale: displayScale)
        let pickerAuxiliary = CapturePickerHeightPolicy(visibleRowBudget: 11, displayScale: displayScale)
            .auxiliaryHeight
        let metrics = contentPolicy.metrics(
            editorHeight: 42,
            auxiliary: pickerAuxiliary,
            footerHeight: 40
        )
        let sizer = CapturePanelWindowSizer(displayScale: displayScale)

        let tallContentHeight = sizer.contentHeight(for: metrics, availableScreenHeight: 1600)
        XCTAssertEqual(tallContentHeight, metrics.idealContentHeight)

        // A short screen clamps to the visible frame, never below it, while
        // the picker's required minimum stays the floor for the editor budget.
        let shortContentHeight = sizer.contentHeight(for: metrics, availableScreenHeight: 300)
        XCTAssertEqual(shortContentHeight, 300 - 2 * CapturePanelLayout.panelScreenMargin)

        let budget = CaptureEditorHeightBudget(
            availableScreenHeight: 300,
            footerHeight: 40,
            auxiliary: pickerAuxiliary,
            contentPolicy: contentPolicy
        )
        XCTAssertGreaterThanOrEqual(
            budget.maximumHeight,
            CaptureEditorHeightPolicy(displayScale: displayScale).minimumHeight
        )
    }

    func testEditorBudgetReservesPickerMinimum() {
        let footerHeight: CGFloat = 40
        let tallScreen: CGFloat = 1600
        let contentPolicy = CapturePanelContentHeightPolicy()
        let none = CaptureEditorHeightBudget(
            availableScreenHeight: tallScreen,
            footerHeight: footerHeight,
            auxiliary: nil,
            contentPolicy: contentPolicy
        )
        let picker = CapturePickerHeightPolicy(visibleRowBudget: 11).auxiliaryHeight
        let withPicker = CaptureEditorHeightBudget(
            availableScreenHeight: tallScreen,
            footerHeight: footerHeight,
            auxiliary: picker,
            contentPolicy: contentPolicy
        )
        XCTAssertGreaterThanOrEqual(
            none.maximumHeight - withPicker.maximumHeight,
            CapturePanelLayout.sectionSpacing + picker.minimumVisibleHeight
        )
    }

    func testKeyHintsDocumentPickerKeyboardContract() {
        XCTAssertEqual(
            CapturePickerKeyHints.items(for: .activeTask).map { $0.keys },
            ["↑↓", "↩", "⌘↩", "esc"]
        )
        XCTAssertEqual(
            CapturePickerKeyHints.items(for: .activeTask).map { $0.action },
            ["Move", "Insert", "Insert & Capture", "Clear / Cancel"]
        )
    }

    /// Rendered-image review for the picker card. Skipped unless
    /// `BOB_MAC_CAPTURE_RENDER_DIR` points at a writable directory; when set,
    /// writes light/dark PNGs at 760pt width for the grouped, filtered,
    /// no-matches, and no-active-tasks states. Inspect the PNGs with an image
    /// reader and iterate on spacing, contrast, truncation, and alignment.
    @MainActor
    func testRenderPickerCardStatesToPNG() throws {
        guard let renderDir = ProcessInfo.processInfo.environment["BOB_MAC_CAPTURE_RENDER_DIR"],
              !renderDir.isEmpty
        else {
            throw XCTSkip("Set BOB_MAC_CAPTURE_RENDER_DIR to render the picker card review images.")
        }
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let states: [(name: String, candidates: [CaptureCompletionCandidate], filter: String)] = [
            ("grouped", Self.renderCandidates, ""),
            ("filtered", Self.renderCandidates, "q weight"),
            ("no-matches", Self.renderCandidates, "zzz-no-match"),
            ("no-active-tasks", [], ""),
        ]
        for state in states {
            for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
                let model = CapturePanelModel()
                model.installPickerForPreviews(
                    candidates: state.candidates,
                    filter: state.filter
                )
                let card = CapturePickerCard(model: model)
                    .frame(width: 760)
                    .environment(
                        \.colorScheme,
                        appearance == .darkAqua ? .dark : .light
                    )
                let renderer = ImageRenderer(content: card)
                renderer.scale = 2
                guard let image = renderer.nsImage else {
                    XCTFail("Could not render \(state.name) (\(appearance.rawValue))")
                    continue
                }
                let url = directory.appendingPathComponent(
                    "capture-picker-\(state.name)-\(appearance == .darkAqua ? "dark" : "light").png"
                )
                try Self.pngData(for: image).write(to: url)
            }
        }
    }

    private static func pngData(for image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "CapturePickerDesignTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode picker render as PNG."]
            )
        }
        return png
    }

    /// Small fixture modeled on the real data profile: two SASE entries on
    /// different lines, a current timed entry, an unnamed placeholder, an
    /// unqueued In Progress and Next task, code spans, aliased and unaliased
    /// wikilinks, and a curly quote.
    private static var renderCandidates: [CaptureCompletionCandidate] {
        [
            CaptureCompletionCandidate(
                replacement: "sase:recovery-panel",
                route: "sase",
                blockID: "recovery-panel",
                statusSymbol: "/",
                statusName: "In Progress",
                text: "Read and act on core_schema_skew_outage_recovery_ux!",
                section: "Next & In Progress",
                pomodoro: ActiveTaskPomodoro(line: 53, name: "SASE")
            ),
            CaptureCompletionCandidate(
                replacement: "sase:tui-cli",
                route: "sase",
                blockID: "tui-cli",
                statusSymbol: "/",
                statusName: "In Progress",
                text: "Bug bash and improve sase TUI `command-mode` panel",
                section: "Next & In Progress",
                pomodoro: ActiveTaskPomodoro(line: 53, name: "SASE")
            ),
            CaptureCompletionCandidate(
                replacement: "sase:card-blocks",
                route: "sase",
                blockID: "card-blocks",
                statusSymbol: "*",
                statusName: "Next",
                text: "Add support for “card blocks”",
                section: "Next & In Progress",
                pomodoro: ActiveTaskPomodoro(line: 68, name: "SASE")
            ),
            CaptureCompletionCandidate(
                replacement: "sase:weight-queue",
                route: "sase",
                blockID: "weight-queue",
                statusSymbol: "*",
                statusName: "Next",
                text: "Queue weight calibration from [[ref/chat/notes|review notes]]",
                section: "Next & In Progress",
                pomodoro: ActiveTaskPomodoro(
                    line: 71,
                    name: "FAST TESTS",
                    timeRange: "0900-0930",
                    isCurrent: true
                )
            ),
            CaptureCompletionCandidate(
                replacement: "bob:later-cleanup",
                route: "bob",
                blockID: "later-cleanup",
                statusSymbol: "*",
                statusName: "Next",
                text: "Tidy [[ref/chat/later]] follow-ups",
                section: "Next & In Progress",
                pomodoro: ActiveTaskPomodoro(line: 90, name: "LATER")
            ),
            CaptureCompletionCandidate(
                replacement: "bob:unnamed-plan",
                route: "bob",
                blockID: "unnamed-plan",
                statusSymbol: "/",
                statusName: "In Progress",
                text: "Draft the unnamed plan",
                section: "Next & In Progress",
                pomodoro: ActiveTaskPomodoro(line: 95)
            ),
            CaptureCompletionCandidate(
                replacement: "sase:solo-fix",
                route: "sase",
                blockID: "solo-fix",
                statusSymbol: "/",
                statusName: "In Progress",
                text: "Fix solo `glitch` without a Pomodoro",
                section: "Next & In Progress"
            ),
            CaptureCompletionCandidate(
                replacement: "bob:solo-next",
                route: "bob",
                blockID: "solo-next",
                statusSymbol: "*",
                statusName: "Next",
                text: "Queue the solo next step",
                section: "Next & In Progress"
            ),
        ]
    }
}
