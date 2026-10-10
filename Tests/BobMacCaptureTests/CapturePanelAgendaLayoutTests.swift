import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Native composition proof for the idle-agenda return: the production
/// panel, hosting view, and window size the real editor, agenda, and
/// footer together after first show and after clearing a settled draft.
///
/// Unlike the eye-line suite (synthetic metrics), the height-consistency
/// suite (rows view alone), and the model suite (booleans), these tests
/// drive the production `CapturePanelController` + `NSPanel` +
/// `NSHostingView` with fixture-backed store state and assert the composed
/// result: the editor stays at its eye line, visible and focused; the
/// agenda occupies the shared bounded viewport below it; the footer stays
/// inside the controller-sized window; repeated cycles neither clip nor
/// drift. The production root view is never replaced and no expected
/// content metrics are hand-fed: every assertion reads the live panel.
///
/// MACOS-ONLY: geometry tests need a screen (`visibleFrame`) and skip
/// headless like `CapturePanelEyeLineTests`. The viewport arithmetic test
/// runs anywhere. When `BOB_MAC_CAPTURE_RENDER_DIR` is set, representative
/// full hosted-panel images are exported after first show and after clear
/// at both widths; geometry assertions stay active without it.
@MainActor
final class CapturePanelAgendaLayoutTests: XCTestCase {
    // MARK: - Harness

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }

    private func waitUntil(
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail(
                    "Condition not met before timeout",
                    file: file,
                    line: line
                )
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Fixture-backed model pinned to the fixture day, exactly as the panel
    /// show path drives it. Pass `captureEnvironment` (even empty) to attach
    /// the fake-bob capture client for preview transitions.
    private func makeModel(
        agendaFixture: String? = nil,
        agendaEnvironment: [String: String] = [:],
        captureEnvironment: [String: String]? = nil
    ) throws -> CapturePanelModel {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
        ]
        if let agendaFixture {
            environment["FAKE_BOB_AGENDA_FIXTURE"] = agendaFixture
        }
        for (key, value) in agendaEnvironment {
            environment[key] = value
        }
        let store = CaptureAgendaStore(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: environment
            ),
            vaultRootPath: "/tmp",
            today: { "2026-08-28" }
        )
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.agendaStore = store
        if let captureEnvironment {
            var capture = [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
            ]
            for (key, value) in captureEnvironment {
                capture[key] = value
            }
            model.processClient = BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: capture
            )
        }
        store.refresh(reason: .show)
        return model
    }

    private func swapAgendaClient(
        _ model: CapturePanelModel,
        environment: [String: String]
    ) throws {
        var full = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
        ]
        for (key, value) in environment {
            full[key] = value
        }
        model.agendaStore?.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: full
        )
        model.agendaStore?.refresh(reason: .show)
    }

    private func typeDraft(_ model: CapturePanelModel, _ text: String) {
        model.plainDraft = text
        model.editorTextDidChange(cursorUTF8Offset: text.utf8.count)
    }

    private func visibleFrame(for panel: NSPanel) -> NSRect? {
        panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    }

    /// Bounded settle: SwiftUI rarely flushes in one
    /// `layoutSubtreeIfNeeded`, so repeat until the panel height stops
    /// moving, then drain one trailing turn for late geometry callbacks.
    private func settlePanel(_ panel: NSPanel, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        var last: CGFloat = -1_000_000
        while Date() < deadline {
            panel.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            panel.contentView?.layoutSubtreeIfNeeded()
            let height = panel.frame.height
            if abs(height - last) < 0.5 {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
                panel.contentView?.layoutSubtreeIfNeeded()
                return
            }
            last = height
        }
    }

    private func editableTextViews(in view: NSView?) -> [NSTextView] {
        guard let view else {
            return []
        }
        var out: [NSTextView] = []
        if let textView = view as? NSTextView, textView.isEditable {
            out.append(textView)
        }
        for subview in view.subviews {
            out.append(contentsOf: editableTextViews(in: subview))
        }
        return out
    }

    private func chromeHeight(for panel: NSPanel) -> CGFloat {
        let reference = NSRect(x: 0, y: 0, width: panel.frame.width, height: 100)
        return panel.frameRect(forContentRect: reference).height - reference.height
    }

    private func waitForEditorFocus(_ panel: NSPanel, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !(panel.firstResponder is NSTextView) {
            if Date() > deadline {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func expectedPaneHeight(_ model: CapturePanelModel) -> CGFloat? {
        guard let plan = model.agendaPlan else {
            return nil
        }
        return CGFloat(
            CaptureAgendaViewport.paneHeight(
                planTotalHeight: plan.totalHeight,
                budget: plan.budget
            )
        )
    }

    private func diagnostics(_ model: CapturePanelModel, _ panel: NSPanel) -> String {
        let plan = model.agendaPlan
        let editors = editableTextViews(in: panel.contentView)
        let editorDesc = editors.map {
            "frame=\($0.frame) visible=\($0.visibleRect) chars=\($0.string.count)"
        }.joined(separator: "; ")
        return "agendaVisible=\(model.agendaVisible) planTotal=\(plan?.totalHeight ?? -1)"
            + " planBudget=\(plan?.budget ?? -1) overflows=\(plan?.overflows ?? false)"
            + " liveBudget=\(model.agendaBudget) inset=\(model.titlebarSafeAreaInset)"
            + " panelFrame=\(panel.frame) layoutRect=\(panel.contentLayoutRect)"
            + " editors=[\(editorDesc)] firstResponder=\(String(describing: panel.firstResponder))"
    }

    /// The composed contract: the window sits inside the screen, the
    /// native editor exists in this panel with a non-empty visible
    /// rectangle (existence alone cannot pass), and it holds focus.
    private func assertComposedPanel(
        _ model: CapturePanelModel,
        _ panel: NSPanel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let info = diagnostics(model, panel)
        guard let visible = visibleFrame(for: panel) else {
            XCTFail("no visible frame on this host; \(info)", file: file, line: line)
            return
        }
        XCTAssertLessThanOrEqual(panel.frame.maxY, visible.maxY + 1, info, file: file, line: line)
        XCTAssertGreaterThanOrEqual(panel.frame.minY, visible.minY - 1, info, file: file, line: line)
        XCTAssertEqual(panel.frame.midX, visible.midX, accuracy: 2, info, file: file, line: line)
        let editors = editableTextViews(in: panel.contentView)
        XCTAssertFalse(editors.isEmpty, "no editable text view; \(info)", file: file, line: line)
        guard let editor = editors.first else {
            return
        }
        XCTAssertTrue(editor.window === panel, "editor not in panel; \(info)", file: file, line: line)
        XCTAssertGreaterThan(
            editor.visibleRect.height,
            1,
            "editor has no visible rectangle; \(info)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            panel.firstResponder is NSTextView,
            "editor lost focus; \(info)",
            file: file,
            line: line
        )
    }

    /// Full hosted-panel image including the AppKit text editor. An
    /// isolated `ImageRenderer` agenda render cannot expose this bug, so
    /// the harness captures the live content view. No-op without
    /// `BOB_MAC_CAPTURE_RENDER_DIR`; geometry assertions never depend on it.
    private func exportPanelImage(_ panel: NSPanel, named base: String) throws {
        guard let renderDir = ProcessInfo.processInfo.environment["BOB_MAC_CAPTURE_RENDER_DIR"],
              !renderDir.isEmpty
        else {
            return
        }
        guard let contentView = panel.contentView else {
            return
        }
        contentView.layoutSubtreeIfNeeded()
        let bounds = contentView.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            return
        }
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return
        }
        contentView.cacheDisplay(in: bounds, to: rep)
        guard let tiff = rep.tiffRepresentation,
              let image = NSImage(data: tiff),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return
        }
        let pngRep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = pngRep.representation(using: .png, properties: [:]) else {
            return
        }
        let url = URL(fileURLWithPath: renderDir, isDirectory: true)
            .appendingPathComponent(base + ".png")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: url)
    }

    // MARK: - Shared viewport arithmetic

    func testViewportBoundsPlanByBudgetAndPadsOnce() {
        let pad = CaptureAgendaLayoutMetrics.panePadding
        XCTAssertEqual(CaptureAgendaViewport.rowsHeight(planTotalHeight: 300, budget: 533), 300)
        XCTAssertEqual(
            CaptureAgendaViewport.paneHeight(planTotalHeight: 300, budget: 533),
            300 + 2 * pad
        )
        XCTAssertEqual(CaptureAgendaViewport.rowsHeight(planTotalHeight: 800, budget: 533), 533)
        XCTAssertEqual(
            CaptureAgendaViewport.paneHeight(planTotalHeight: 800, budget: 533),
            533 + 2 * pad
        )
        // An actual zero budget is zero agenda space, never unbounded.
        XCTAssertEqual(CaptureAgendaViewport.rowsHeight(planTotalHeight: 300, budget: 0), 0)
        XCTAssertEqual(
            CaptureAgendaViewport.paneHeight(planTotalHeight: 300, budget: 0),
            2 * pad
        )
        // Invalid inputs collapse to the safe bound, never to an
        // unbounded pane that could displace the editor or footer.
        XCTAssertEqual(CaptureAgendaViewport.rowsHeight(planTotalHeight: .nan, budget: 533), 0)
        XCTAssertEqual(CaptureAgendaViewport.rowsHeight(planTotalHeight: 300, budget: .nan), 0)
        XCTAssertEqual(
            CaptureAgendaViewport.rowsHeight(planTotalHeight: .infinity, budget: 533),
            0
        )
        XCTAssertEqual(
            CaptureAgendaViewport.rowsHeight(planTotalHeight: 300, budget: .infinity),
            0
        )
        XCTAssertEqual(CaptureAgendaViewport.rowsHeight(planTotalHeight: -40, budget: 533), 0)
    }

    // MARK: - Cached first show

    func testCachedAgendaFirstShowKeepsEditorAndFooter() async throws {
        let model = try makeModel(agendaFixture: "agenda-nothing-running.json")
        await waitUntil { model.agendaStore?.snapshot != nil }
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        guard visibleFrame(for: panel) != nil else {
            throw XCTSkip("no visible frame on this host")
        }
        // Compact baseline without the agenda.
        model.agendaEnabled = false
        controller.show()
        settlePanel(panel)
        let compactTop = panel.frame.maxY
        let compactContent = panel.frame.height - chromeHeight(for: panel)
        // Cached populated agenda on first show.
        model.agendaEnabled = true
        controller.show()
        settlePanel(panel)
        await waitForEditorFocus(panel)
        let info = diagnostics(model, panel)
        XCTAssertTrue(model.agendaVisible, info)
        guard let pane = expectedPaneHeight(model) else {
            XCTFail("no agenda plan after enable; \(info)")
            return
        }
        XCTAssertGreaterThan(pane, 0, info)
        XCTAssertEqual(panel.frame.maxY, compactTop, accuracy: 1.0, info)
        let agendaContent = panel.frame.height - chromeHeight(for: panel)
        let growth = agendaContent - compactContent
        XCTAssertGreaterThan(growth, 0, info)
        XCTAssertEqual(
            growth,
            pane + CGFloat(CapturePanelLayout.sectionSpacing),
            accuracy: 24,
            info
        )
        assertComposedPanel(model, panel)
        try exportPanelImage(panel, named: "agenda-first-show-nothing-running")
    }

    // MARK: - Settled preview cleared to empty

    func testSettledPreviewClearedRestoresAgendaAndFocus() async throws {
        let model = try makeModel(
            agendaFixture: "agenda-nothing-running.json",
            captureEnvironment: [:]
        )
        await waitUntil { model.agendaStore?.snapshot != nil }
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        guard visibleFrame(for: panel) != nil else {
            throw XCTSkip("no visible frame on this host")
        }
        controller.show()
        settlePanel(panel)
        await waitForEditorFocus(panel)
        let baselineTop = panel.frame.maxY
        XCTAssertTrue(model.agendaVisible, diagnostics(model, panel))
        typeDraft(model, "=")
        await waitUntil {
            if case .ready = model.previewState {
                return true
            }
            return false
        }
        XCTAssertFalse(model.agendaVisible, diagnostics(model, panel))
        settlePanel(panel)
        typeDraft(model, "")
        settlePanel(panel)
        await waitForEditorFocus(panel)
        var info = diagnostics(model, panel)
        XCTAssertTrue(model.agendaVisible, info)
        XCTAssertEqual(model.previewState, .idle, info)
        XCTAssertEqual(panel.frame.maxY, baselineTop, accuracy: 1.0, info)
        assertComposedPanel(model, panel)
        // A whitespace-only draft still shows the idle agenda.
        typeDraft(model, " \n")
        settlePanel(panel)
        await waitForEditorFocus(panel)
        info = diagnostics(model, panel)
        XCTAssertTrue(model.agendaVisible, info)
        assertComposedPanel(model, panel)
        try exportPanelImage(panel, named: "agenda-after-clear-nothing-running")
    }

    func testClearWhilePreviewFinishingKeepsGeometryValid() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let termURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = try makeModel(
            agendaFixture: "agenda-nothing-running.json",
            captureEnvironment: [
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_TERM_PATH": termURL.path,
                "FAKE_BOB_DELAY_SECONDS": "0.4",
            ]
        )
        await waitUntil { model.agendaStore?.snapshot != nil }
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        guard visibleFrame(for: panel) != nil else {
            throw XCTSkip("no visible frame on this host")
        }
        controller.show()
        settlePanel(panel)
        await waitForEditorFocus(panel)
        typeDraft(model, "=")
        await waitUntil {
            (try? String(contentsOf: recordURL))?.contains("argv=") == true
        }
        // Clear before the preview settles: request retirement must win.
        typeDraft(model, "")
        settlePanel(panel)
        await waitForEditorFocus(panel)
        var info = diagnostics(model, panel)
        XCTAssertTrue(model.agendaVisible, info)
        assertComposedPanel(model, panel)
        await waitUntil { FileManager.default.fileExists(atPath: termURL.path) }
        settlePanel(panel)
        info = diagnostics(model, panel)
        XCTAssertTrue(model.agendaVisible, info)
        XCTAssertNil(model.sessionStartPresentation, info)
        assertComposedPanel(model, panel)
    }

    // MARK: - Repeated cycles and reopen

    func testRepeatedTypeClearAndReopenDoesNotDrift() async throws {
        let model = try makeModel(
            agendaFixture: "agenda-nothing-running.json",
            captureEnvironment: [:]
        )
        await waitUntil { model.agendaStore?.snapshot != nil }
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        guard visibleFrame(for: panel) != nil else {
            throw XCTSkip("no visible frame on this host")
        }
        controller.show()
        settlePanel(panel)
        await waitForEditorFocus(panel)
        let firstHeight = panel.frame.height
        for _ in 0..<3 {
            typeDraft(model, "=")
            await waitUntil {
                if case .ready = model.previewState {
                    return true
                }
                return false
            }
            typeDraft(model, "")
            settlePanel(panel)
        }
        await waitForEditorFocus(panel)
        var info = diagnostics(model, panel)
        XCTAssertTrue(model.agendaVisible, info)
        XCTAssertEqual(panel.frame.height, firstHeight, accuracy: 1.0, info)
        // Hide/reopen with identical cached bytes: no fresh snapshot
        // dependency and no cumulative drift.
        for _ in 0..<2 {
            model.prepareForDismissal()
            panel.orderOut(nil)
            controller.show()
            settlePanel(panel)
        }
        await waitForEditorFocus(panel)
        info = diagnostics(model, panel)
        XCTAssertTrue(model.agendaVisible, info)
        XCTAssertEqual(panel.frame.height, firstHeight, accuracy: 1.0, info)
        assertComposedPanel(model, panel)
    }

    // MARK: - Width change and heavy agendas

    func testWidthChangeAndHeavyAgendaKeepsControlsVisible() async throws {
        let model = try makeModel(agendaFixture: "agenda-heavy.json")
        await waitUntil { model.agendaStore?.snapshot != nil }
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        guard visibleFrame(for: panel) != nil else {
            throw XCTSkip("no visible frame on this host")
        }
        controller.show()
        settlePanel(panel)
        await waitForEditorFocus(panel)
        // 760 pt and 620 pt window widths drive these content widths.
        for width in [724, 584] as [CGFloat] {
            model.agendaContentWidth = width
            settlePanel(panel)
            await waitForEditorFocus(panel)
            let info = diagnostics(model, panel) + " contentWidth=\(width)"
            XCTAssertTrue(model.agendaVisible, info)
            assertComposedPanel(model, panel)
        }
        try exportPanelImage(panel, named: "agenda-heavy-620")
        // A current agenda remeasures and folds within the same shared
        // budget at both widths; controls remain visible throughout.
        let first = model.agendaPresentation
        try swapAgendaClient(model, environment: ["FAKE_BOB_AGENDA_FIXTURE": "agenda-current.json"])
        await waitUntil { model.agendaPresentation != first }
        for width in [724, 584] as [CGFloat] {
            model.agendaContentWidth = width
            settlePanel(panel)
            await waitForEditorFocus(panel)
            let info = diagnostics(model, panel) + " contentWidth=\(width)"
            XCTAssertTrue(model.agendaVisible, info)
            assertComposedPanel(model, panel)
        }
        try exportPanelImage(panel, named: "agenda-current-620")
    }

    // MARK: - Small budget and expanded overflow

    func testSmallBudgetAndExpandedOverflowStaysBounded() async throws {
        let model = try makeModel(agendaFixture: "agenda-heavy.json")
        await waitUntil { model.agendaStore?.snapshot != nil }
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        guard visibleFrame(for: panel) != nil else {
            throw XCTSkip("no visible frame on this host")
        }
        controller.show()
        settlePanel(panel)
        await waitForEditorFocus(panel)
        let settledHeight = panel.frame.height
        // The overflow presentation stays inside the shared bounded
        // viewport even with an expanded unit.
        model.expandAgendaUnit(.strip)
        settlePanel(panel)
        await waitForEditorFocus(panel)
        var info = diagnostics(model, panel)
        XCTAssertTrue(model.agendaVisible, info)
        XCTAssertLessThanOrEqual(panel.frame.height, settledHeight + 400, info)
        assertComposedPanel(model, panel)
        // A zero budget bounds the region to the pane chrome instead of
        // going unbounded: the editor and footer cannot be displaced.
        model.agendaBudget = 0
        settlePanel(panel)
        await waitForEditorFocus(panel)
        info = diagnostics(model, panel)
        XCTAssertTrue(model.agendaVisible, info)
        XCTAssertEqual(
            CGFloat(
                CaptureAgendaViewport.rowsHeight(
                    planTotalHeight: model.agendaPlan?.totalHeight ?? -1,
                    budget: model.agendaPlan?.budget ?? -1
                )
            ),
            0,
            info
        )
        XCTAssertLessThanOrEqual(panel.frame.height, settledHeight, info)
        assertComposedPanel(model, panel)
    }

    // MARK: - Invalidation with unchanged target metrics

    func testEqualMetricsAfterInvalidationRepairsFrameWithoutMovingEyeLine() async throws {
        let model = try makeModel(agendaFixture: "agenda-nothing-running.json")
        await waitUntil { model.agendaStore?.snapshot != nil }
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        guard visibleFrame(for: panel) != nil else {
            throw XCTSkip("no visible frame on this host")
        }
        controller.show()
        settlePanel(panel)
        await waitForEditorFocus(panel)
        let settledFrame = panel.frame
        // Replaying the cached report repairs any probe/screen drift even
        // when the target is unchanged, and never moves a settled panel.
        controller.replayLatestContentMetricsForPresentation()
        settlePanel(panel)
        await waitForEditorFocus(panel)
        var info = diagnostics(model, panel)
        XCTAssertEqual(panel.frame.height, settledFrame.height, accuracy: 1.0, info)
        XCTAssertEqual(panel.frame.maxY, settledFrame.maxY, accuracy: 1.0, info)
        // Inset invalidation followed by the same target metrics: the
        // actual panel size and editor position settle back, with no
        // destructive probe or reentrant sizing loop.
        let settledInset = model.titlebarSafeAreaInset
        model.titlebarSafeAreaInset = 0
        settlePanel(panel)
        model.titlebarSafeAreaInset = settledInset
        controller.replayLatestContentMetricsForPresentation()
        settlePanel(panel)
        await waitForEditorFocus(panel)
        info = diagnostics(model, panel)
        XCTAssertEqual(panel.frame.height, settledFrame.height, accuracy: 1.0, info)
        XCTAssertEqual(panel.frame.maxY, settledFrame.maxY, accuracy: 1.0, info)
        assertComposedPanel(model, panel)
    }

    // MARK: - Agenda disabled and ordinary preview

    func testAgendaDisabledAndPreviewStillFit() async throws {
        let model = try makeModel(
            agendaFixture: "agenda-current.json",
            captureEnvironment: [:]
        )
        await waitUntil { model.agendaStore?.snapshot != nil }
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        guard visibleFrame(for: panel) != nil else {
            throw XCTSkip("no visible frame on this host")
        }
        model.agendaEnabled = false
        controller.show()
        settlePanel(panel)
        await waitForEditorFocus(panel)
        XCTAssertFalse(model.agendaVisible, diagnostics(model, panel))
        let compactTop = panel.frame.maxY
        // A normal typed preview keeps the existing auxiliary layout and
        // controls fitting while the agenda is off.
        typeDraft(model, "=")
        await waitUntil {
            if case .ready = model.previewState {
                return true
            }
            return false
        }
        settlePanel(panel)
        await waitForEditorFocus(panel)
        var info = diagnostics(model, panel)
        XCTAssertFalse(model.agendaVisible, info)
        XCTAssertEqual(panel.frame.maxY, compactTop, accuracy: 1.0, info)
        assertComposedPanel(model, panel)
        // Clearing with no agenda to show still cleans the draft UI.
        typeDraft(model, "")
        settlePanel(panel)
        await waitForEditorFocus(panel)
        info = diagnostics(model, panel)
        XCTAssertFalse(model.agendaVisible, info)
        XCTAssertEqual(model.previewState, .idle, info)
        assertComposedPanel(model, panel)
    }
}
