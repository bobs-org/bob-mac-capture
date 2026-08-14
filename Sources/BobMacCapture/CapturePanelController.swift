import AppKit
import SwiftUI

@MainActor
final class CapturePanelController: NSObject, NSWindowDelegate {
    private let model: CapturePanelModel
    private let keyRouter = CaptureKeyCommandRouter()
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var latestContentMetrics: CapturePanelContentMetrics?
    private var appliedContentHeight: CGFloat?
    private var pendingRecenter = false
    private var isApplyingContentHeight = false
    private var metricsArrivedDuringApplication = false

    init(model: CapturePanelModel) {
        self.model = model
        super.init()
        model.panelDismisser = { [weak self] in self?.hidePanel() }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    func prewarm() {
        _ = makePanelIfNeeded()
    }

    func show() {
        let token = CaptureSignpost.begin("panel-order")
        model.prepareForPresentation()
        let panel = makePanelIfNeeded()
        replayLatestContentMetricsForPresentation()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitorIfNeeded()
        CaptureSignpost.end(token)
        CaptureSignpost.event("editor-focus-requested")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.prepareForRetainedClose()
        return true
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let panel, let appliedContentHeight else {
            return frameSize
        }
        return NSSize(width: frameSize.width, height: appliedContentHeight + Self.chromeHeight(for: panel))
    }

    /// Receives rendered SwiftUI metrics and caches them before trying to apply them to
    /// the live panel. Reports can arrive during prewarm or a reentrant resize; neither
    /// case should lose the newest measurement.
    func receiveContentMetrics(_ metrics: CapturePanelContentMetrics) {
        guard metrics.isValid else {
            return
        }
        latestContentMetrics = metrics
        applyLatestContentMetricsIfPossible()
    }

    /// Replays the cached report for first presentation and re-show paths. This is
    /// intentionally explicit because unchanged SwiftUI geometry does not emit a second
    /// change notification.
    func replayLatestContentMetricsForPresentation() {
        guard let panel else {
            return
        }

        pendingRecenter = true
        panel.contentView?.layoutSubtreeIfNeeded()
        if latestContentMetrics == nil {
            applyFallbackContentHeight(force: true)
        } else {
            applyLatestContentMetricsIfPossible(force: true)
        }
    }

    /// Resolves SwiftUI-measured content metrics to a target size, then applies them to
    /// the live panel: anchored at the top edge, clamped inside the screen, and guarded
    /// against feedback loops from resizing itself.
    private func applyContentMetrics(
        _ metrics: CapturePanelContentMetrics,
        force: Bool = false
    ) {
        guard metrics.isValid else {
            return
        }
        guard let panel else {
            return
        }
        guard !isApplyingContentHeight else {
            metricsArrivedDuringApplication = true
            return
        }

        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let sizer = CapturePanelWindowSizer(displayScale: panel.screen?.backingScaleFactor ?? 1)
        let target = sizer.contentHeight(
            for: metrics,
            availableScreenHeight: visibleFrame?.height
        )

        let heightChanged = appliedContentHeight.map { abs($0 - target) >= 0.5 } ?? true
        guard force || heightChanged || pendingRecenter else {
            return
        }

        isApplyingContentHeight = true
        defer {
            isApplyingContentHeight = false
            if metricsArrivedDuringApplication {
                metricsArrivedDuringApplication = false
                applyLatestContentMetricsIfPossible()
            }
        }

        panel.contentMinSize = NSSize(width: CapturePanelLayout.panelMinimumContentWidth, height: target)
        panel.contentMaxSize = NSSize(width: .greatestFiniteMagnitude, height: target)
        appliedContentHeight = target

        if pendingRecenter {
            panel.setContentSize(NSSize(width: panel.frame.width, height: target))
            panel.center()
            pendingRecenter = false
        } else {
            let frame = sizer.frame(
                forCurrentFrame: panel.frame,
                contentHeight: target,
                chromeHeight: Self.chromeHeight(for: panel),
                visibleFrame: visibleFrame ?? Self.unlimitedVisibleFrame
            )
            panel.setFrame(frame, display: true, animate: false)
        }
    }

    private func applyLatestContentMetricsIfPossible(force: Bool = false) {
        guard let latestContentMetrics else {
            return
        }
        applyContentMetrics(latestContentMetrics, force: force)
    }

    private func applyFallbackContentHeight(force: Bool = false) {
        applyContentMetrics(
            CapturePanelContentMetrics(
                idealContentHeight: CapturePanelLayout.panelFallbackContentHeight,
                minimumVisibleContentHeight: CapturePanelLayout.panelFallbackContentHeight
            ),
            force: force
        )
    }

    func makePanelIfNeeded() -> NSPanel {
        if let panel {
            return panel
        }

        let created = Self.makePanel()
        created.delegate = self
        panel = created
        let hostingView = NSHostingView(
            rootView: CapturePanelView(model: model) { [weak self] metrics in
                self?.receiveContentMetrics(metrics)
            }
        )
        hostingView.sizingOptions = []
        created.contentView = hostingView
        created.contentView?.layoutSubtreeIfNeeded()
        applyLatestContentMetricsIfPossible()
        return created
    }

    private static func chromeHeight(for panel: NSPanel) -> CGFloat {
        let referenceContentRect = NSRect(x: 0, y: 0, width: panel.frame.width, height: 100)
        let referenceFrameRect = panel.frameRect(forContentRect: referenceContentRect)
        return referenceFrameRect.height - referenceContentRect.height
    }

    private static let unlimitedVisibleFrame = NSRect(x: -1_000_000, y: -1_000_000, width: 2_000_000, height: 2_000_000)

    static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(
                origin: .zero,
                size: CapturePanelLayout.panelInitialContentSize
            ),
            styleMask: [
                .nonactivatingPanel,
                .titled,
                .fullSizeContentView,
                .resizable,
            ],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentMinSize = CapturePanelLayout.panelMinimumContentSize
        return panel
    }

    static func insertNewlineInEditableTextView(
        firstResponder: NSResponder?,
        model: CapturePanelModel
    ) -> Bool {
        guard let textView = editableTextView(firstResponder) else {
            return false
        }

        model.dismissCompletion()
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        return true
    }

    /// Ctrl-J: replace the current selection with a fresh `- ` row and leave the caret
    /// after the space. Returns `false` for any responder that is not an editable text
    /// view so the key event falls through to AppKit untouched.
    static func insertBulletNewlineInEditableTextView(
        firstResponder: NSResponder?,
        model: CapturePanelModel
    ) -> Bool {
        guard let textView = editableTextView(firstResponder) else {
            return false
        }

        model.dismissCompletion()
        textView.insertText("\n- ", replacementRange: textView.selectedRange())
        return true
    }

    /// Backspace: remove an unused `- ` placeholder row in one action. Returns `false`
    /// whenever `emptyBulletRowDeletionRange(in:)` declines, so ordinary Backspace
    /// behavior stays AppKit's.
    static func deleteEmptyBulletRowInEditableTextView(
        firstResponder: NSResponder?,
        model: CapturePanelModel
    ) -> Bool {
        guard let textView = editableTextView(firstResponder),
              let deletionRange = emptyBulletRowDeletionRange(in: textView)
        else {
            return false
        }

        model.dismissCompletion()
        textView.insertText("", replacementRange: deletionRange)
        return true
    }

    /// Applies a routed key command. Returns `true` when the key event is consumed.
    @discardableResult
    func perform(_ command: CaptureKeyCommand) -> Bool {
        switch command {
        case .submit:
            model.submit(openAfterCapture: false)
            return true
        case .submitAndOpen:
            model.submit(openAfterCapture: true)
            return true
        case .insertNewline:
            return Self.insertNewlineInEditableTextView(
                firstResponder: panel?.firstResponder,
                model: model
            )
        case .insertBulletNewline:
            return Self.insertBulletNewlineInEditableTextView(
                firstResponder: panel?.firstResponder,
                model: model
            )
        case .deleteBackward:
            return Self.deleteEmptyBulletRowInEditableTextView(
                firstResponder: panel?.firstResponder,
                model: model
            )
        case .escape:
            if model.completionVisible {
                model.dismissCompletion()
            } else {
                model.closeRetainingDraft()
            }
            return true
        case .discardAndClose:
            model.discardDraftAndClose()
            return true
        case .acceptCompletion:
            model.acceptSelectedCompletion()
            return true
        case .nextCompletion:
            model.selectNextCompletion()
            return true
        case .previousCompletion:
            model.selectPreviousCompletion()
            return true
        }
    }

    private func hidePanel() {
        CaptureSignpost.event("panel-dismiss")
        panel?.orderOut(nil)
    }

    private func installKeyMonitorIfNeeded() {
        guard localMonitor == nil else {
            return
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.panel?.isKeyWindow == true,
                  let command = self.keyRouter.command(
                    for: event,
                    completionVisible: self.model.completionVisible
                  )
            else {
                return event
            }

            return self.perform(command) ? nil : event
        }
    }

    // Ctrl-J and the placeholder-row Backspace both act directly on the draft's backing
    // `NSTextView` (found via the first responder) so undo, IME, and accessibility stay
    // native instead of routing through `CapturePanelModel`.
    static func editableTextView(_ responder: NSResponder?) -> NSTextView? {
        guard let textView = responder as? NSTextView, textView.isEditable else {
            return nil
        }
        return textView
    }

    // Intervenes only when the caret's collapsed selection sits on a physical line whose
    // complete content is exactly the empty-bullet placeholder `- ` that Ctrl-J inserts.
    // Every other selection, line, or content passes back `nil` so AppKit's ordinary
    // Backspace behavior is untouched.
    static func emptyBulletRowDeletionRange(in textView: NSTextView) -> NSRange? {
        let selection = textView.selectedRange()
        guard selection.length == 0 else {
            return nil
        }

        let text = textView.string as NSString
        var lineStart = 0
        var contentsEnd = 0
        text.getLineStart(
            &lineStart,
            end: nil,
            contentsEnd: &contentsEnd,
            for: NSRange(location: selection.location, length: 0)
        )
        let contentRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
        guard text.substring(with: contentRange) == "- " else {
            return nil
        }

        if lineStart == 0 {
            return contentRange
        }
        return NSRange(location: lineStart - 1, length: contentRange.length + 1)
    }
}
