import AppKit
import SwiftUI

/// Direction of a bullet-indentation edit between Bob's two supported authored-child
/// prefixes: column zero and exactly two ASCII spaces.
enum CaptureBulletIndentationDirection {
    case increase
    case decrease
}

/// A deterministic single-line source edit that indents or outdents one continuation
/// bullet row, plus the selection that keeps the caret/selection at the same logical
/// position in the bullet body after the edit is applied.
struct CaptureBulletIndentationEdit: Equatable {
    let replacementRange: NSRange
    let replacementText: String
    let resultingSelection: NSRange
}

struct CaptureBulletNewlineEdit: Equatable {
    let replacementRange: NSRange
    let replacementText: String
    let selectedRange: NSRange
}

enum CaptureBulletNewlineEditResolver {
    static func resolve(in text: String, selectedRange: NSRange) -> CaptureBulletNewlineEdit? {
        let nsText = text as NSString
        guard selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.location + selectedRange.length <= nsText.length
        else {
            return nil
        }

        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        nsText.getLineStart(
            &lineStart,
            end: &lineEnd,
            contentsEnd: &contentsEnd,
            for: NSRange(location: selectedRange.location, length: 0)
        )

        let contentRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
        let lineContent = nsText.substring(with: contentRange)

        if selectedRange.length == 0,
           isPlaceholderLine(lineContent)
        {
            let terminatorRange = NSRange(location: contentsEnd, length: lineEnd - contentsEnd)
            let replacementRange: NSRange
            let replacementText: String
            if terminatorRange.length > 0 {
                replacementRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                replacementText = nsText.substring(with: terminatorRange)
            } else {
                replacementRange = contentRange
                replacementText = preferredLineTerminator(in: text)
            }
            let finalLocation = replacementRange.location + (replacementText as NSString).length
            return CaptureBulletNewlineEdit(
                replacementRange: replacementRange,
                replacementText: replacementText,
                selectedRange: NSRange(location: finalLocation, length: 0)
            )
        }

        let indent = supportedAuthoredIndent(in: lineContent)
        let replacementText = "\(preferredLineTerminator(in: text))\(indent)- "
        let finalLocation = selectedRange.location + (replacementText as NSString).length
        return CaptureBulletNewlineEdit(
            replacementRange: selectedRange,
            replacementText: replacementText,
            selectedRange: NSRange(location: finalLocation, length: 0)
        )
    }

    private static func isPlaceholderLine(_ line: String) -> Bool {
        line.range(of: #"^\s*[-*+]\s*$"#, options: .regularExpression) != nil
    }

    private static func supportedAuthoredIndent(in line: String) -> String {
        for indent in ["  ", ""] {
            for marker in ["-", "*", "+"] {
                let prefix = indent + marker
                guard line.hasPrefix(prefix) else {
                    continue
                }
                let suffix = line.dropFirst(prefix.count)
                if suffix.isEmpty || suffix.first?.isWhitespace == true {
                    return indent
                }
            }
        }
        return ""
    }

    private static func preferredLineTerminator(in text: String) -> String {
        if text.contains("\r\n") {
            return "\r\n"
        }
        if text.contains("\r") {
            return "\r"
        }
        return "\n"
    }
}

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

    /// Ctrl-J: resolve a deterministic native text edit, then apply it through
    /// `NSTextView` so undo, IME, and accessibility stay AppKit-owned.
    static func insertBulletNewlineInEditableTextView(
        firstResponder: NSResponder?,
        model: CapturePanelModel
    ) -> Bool {
        guard let textView = editableTextView(firstResponder),
              let edit = CaptureBulletNewlineEditResolver.resolve(
                in: textView.string,
                selectedRange: textView.selectedRange()
              )
        else {
            return false
        }

        model.dismissCompletion()
        textView.insertText(edit.replacementText, replacementRange: edit.replacementRange)
        textView.setSelectedRange(edit.selectedRange)
        return true
    }

    /// Tab/Shift-Tab: indent or outdent the continuation bullet row the caret sits on
    /// between column zero and exactly two ASCII spaces. Returns `false` without
    /// changing state whenever `bulletIndentationEdit(direction:in:selectedRange:)`
    /// declines, so the key event falls through to AppKit's normal focus traversal.
    static func applyBulletIndentation(
        _ direction: CaptureBulletIndentationDirection,
        firstResponder: NSResponder?,
        model: CapturePanelModel
    ) -> Bool {
        guard let textView = editableTextView(firstResponder),
              let edit = bulletIndentationEdit(
                direction: direction,
                in: textView.string as NSString,
                selectedRange: textView.selectedRange()
              )
        else {
            return false
        }

        model.dismissCompletion()
        textView.insertText(edit.replacementText, replacementRange: edit.replacementRange)
        textView.setSelectedRange(edit.resultingSelection)
        return true
    }

    /// Resolves the bounded source edit for one continuation bullet row, or `nil` when
    /// the selection or line is out of scope. This is a pure, deterministic helper: it
    /// only recognizes the two supported source prefixes (column zero and exactly two
    /// ASCII spaces) and never inspects route markers, parses JSON, or infers capture
    /// output. Bob's own parse remains authoritative for contextual validity.
    static func bulletIndentationEdit(
        direction: CaptureBulletIndentationDirection,
        in text: NSString,
        selectedRange: NSRange
    ) -> CaptureBulletIndentationEdit? {
        var lineStart = 0
        var contentsEnd = 0
        text.getLineStart(
            &lineStart,
            end: nil,
            contentsEnd: &contentsEnd,
            for: NSRange(location: selectedRange.location, length: 0)
        )

        // Never transform physical line 1 (the captured parent), and decline a
        // selection that spans more than one physical line or includes a delimiter.
        guard lineStart > 0, NSMaxRange(selectedRange) <= contentsEnd else {
            return nil
        }

        let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
        let lineText = text.substring(with: lineRange) as NSString

        switch direction {
        case .increase:
            guard isAuthoredBulletRow(lineText, leadingSpaces: 0) else {
                return nil
            }
            return CaptureBulletIndentationEdit(
                replacementRange: NSRange(location: lineStart, length: 0),
                replacementText: "  ",
                resultingSelection: NSRange(
                    location: selectedRange.location + 2,
                    length: selectedRange.length
                )
            )
        case .decrease:
            guard isAuthoredBulletRow(lineText, leadingSpaces: 2) else {
                return nil
            }
            let deletionRange = NSRange(location: lineStart, length: 2)
            let newLocation = clampedOffset(selectedRange.location, removing: deletionRange)
            let newEnd = clampedOffset(NSMaxRange(selectedRange), removing: deletionRange)
            return CaptureBulletIndentationEdit(
                replacementRange: deletionRange,
                replacementText: "",
                resultingSelection: NSRange(location: newLocation, length: newEnd - newLocation)
            )
        }
    }

    // Transforms a selection endpoint through a two-character prefix deletion, clamping
    // an endpoint that sat inside the removed prefix to the new line start.
    private static func clampedOffset(_ offset: Int, removing range: NSRange) -> Int {
        if offset <= range.location {
            return offset
        }
        if offset >= NSMaxRange(range) {
            return offset - range.length
        }
        return range.location
    }

    // Recognizes `-`, `*`, and `+` at the given leading-space depth when the marker is
    // at end of line (an interactive placeholder) or is followed by a space or tab.
    // Prose, `-body`, blank rows, leading tabs, and every other depth decline.
    private static func isAuthoredBulletRow(_ lineText: NSString, leadingSpaces: Int) -> Bool {
        guard lineText.length > leadingSpaces else {
            return false
        }
        for index in 0..<leadingSpaces where lineText.character(at: index) != Self.asciiSpace {
            return false
        }

        let markerIndex = leadingSpaces
        guard Self.isBulletMarkerCharacter(lineText.character(at: markerIndex)) else {
            return false
        }

        let afterMarker = markerIndex + 1
        guard afterMarker < lineText.length else {
            return true
        }
        let nextCharacter = lineText.character(at: afterMarker)
        return nextCharacter == Self.asciiSpace || nextCharacter == Self.asciiTab
    }

    private static func isBulletMarkerCharacter(_ character: unichar) -> Bool {
        character == Self.hyphen || character == Self.asterisk || character == Self.plus
    }

    private static let asciiSpace: unichar = 0x20
    private static let asciiTab: unichar = 0x09
    private static let hyphen: unichar = 0x2D
    private static let asterisk: unichar = 0x2A
    private static let plus: unichar = 0x2B

    /// Ctrl-U: use AppKit's native physical-line deletion so line boundaries, undo, IME,
    /// and accessibility stay owned by the text system.
    static func deleteToBeginningOfLineInEditableTextView(
        firstResponder: NSResponder?,
        model: CapturePanelModel
    ) -> Bool {
        guard let textView = editableTextView(firstResponder) else {
            return false
        }

        model.dismissCompletion()
        textView.doCommand(by: Selector(("deleteToBeginningOfLine:")))
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
        case .deleteToBeginningOfLine:
            return Self.deleteToBeginningOfLineInEditableTextView(
                firstResponder: panel?.firstResponder,
                model: model
            )
        case .deleteBackward:
            return Self.deleteEmptyBulletRowInEditableTextView(
                firstResponder: panel?.firstResponder,
                model: model
            )
        case .increaseBulletIndentation:
            return Self.applyBulletIndentation(
                .increase,
                firstResponder: panel?.firstResponder,
                model: model
            )
        case .decreaseBulletIndentation:
            return Self.applyBulletIndentation(
                .decrease,
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
        case .stashDraftAndClose:
            model.stashDraftAndClose()
            return true
        case .toggleStashPicker:
            model.toggleStashPicker()
            return true
        case .dismissStashPicker:
            model.dismissStashPicker()
            return true
        case .clearCanceledDraftStash:
            model.clearCanceledDraftStashFromPicker()
            return true
        case .nextStashEntry:
            model.selectNextStashEntry()
            return true
        case .previousStashEntry:
            model.selectPreviousStashEntry()
            return true
        case .restoreSelectedStashEntry:
            model.restoreSelectedStashEntry()
            return true
        case .restoreStashEntry(let index):
            model.restoreStashEntry(at: index)
            return true
        case .consumeKey:
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
        case .submitTaskIDPrompt:
            model.submitTaskIDPrompt()
            return true
        case .cancelTaskIDPrompt:
            model.cancelTaskIDPrompt()
            return true
        }
    }

    private func hidePanel() {
        CaptureSignpost.event("panel-dismiss")
        model.prepareForDismissal()
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
                    context: CaptureKeyRoutingContext(
                        completionVisible: self.model.completionVisible,
                        stashPickerVisible: self.model.isStashPickerPresented,
                        stashEntryCount: self.model.stashCount,
                        taskIDPromptVisible: self.model.taskIDPromptVisible
                    )
                  )
            else {
                return event
            }

            return self.perform(command) ? nil : event
        }
    }

    // Ctrl-J, Ctrl-U, the placeholder-row Backspace, and Tab/Shift-Tab bullet
    // indentation all act directly on the draft's backing `NSTextView` (found via the
    // first responder) so undo, IME, and accessibility stay native instead of routing
    // through `CapturePanelModel`.
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
