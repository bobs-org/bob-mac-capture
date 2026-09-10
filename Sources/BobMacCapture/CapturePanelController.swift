import AppKit
import SwiftUI

/// Direction of a bullet-indentation edit between Bob's two supported authored-child
/// prefixes: column zero and exactly two ASCII spaces.
enum CaptureBulletIndentationDirection {
    case increase
    case decrease
}

/// Which edge of a physical line Ctrl-A / Ctrl-E targets.
enum CaptureLineEdge {
    case beginning
    case end
}

/// Which adjacent physical line Ctrl-Shift-J / Ctrl-Shift-K targets.
enum CaptureVerticalDirection {
    case next
    case previous
}

/// Where a Ctrl-Shift-J / Ctrl-Shift-K move lands, plus the goal column to carry into the next
/// consecutive vertical move so a short line in between does not lose the column.
struct CaptureVerticalMove: Equatable {
    var location: Int
    var goalColumn: Int
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

struct CaptureLineAboveEdit: Equatable {
    let replacementRange: NSRange
    let replacementText: String
    let resultingSelection: NSRange
}

private func preferredCaptureLineTerminator(in text: String) -> String {
    if text.contains("\r\n") {
        return "\r\n"
    }
    if text.contains("\r") {
        return "\r"
    }
    return "\n"
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
                replacementText = preferredCaptureLineTerminator(in: text)
            }
            let finalLocation = replacementRange.location + (replacementText as NSString).length
            return CaptureBulletNewlineEdit(
                replacementRange: replacementRange,
                replacementText: replacementText,
                selectedRange: NSRange(location: finalLocation, length: 0)
            )
        }

        if selectedRange.length == 0,
           let prefixRange = removableDashBulletPrefixRange(
               in: lineContent,
               lineStart: lineStart,
               caretLocation: selectedRange.location
           )
        {
            let replacementText = preferredCaptureLineTerminator(in: text)
            let finalLocation = prefixRange.location + (replacementText as NSString).length
            return CaptureBulletNewlineEdit(
                replacementRange: prefixRange,
                replacementText: replacementText,
                selectedRange: NSRange(location: finalLocation, length: 0)
            )
        }

        let indent = supportedAuthoredIndent(in: lineContent)
        let replacementText = "\(preferredCaptureLineTerminator(in: text))\(indent)- "
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

    private static func removableDashBulletPrefixRange(
        in line: String,
        lineStart: Int,
        caretLocation: Int
    ) -> NSRange? {
        let nsLine = line as NSString
        var hyphenOffset = 0
        while hyphenOffset < nsLine.length {
            let character = nsLine.character(at: hyphenOffset)
            guard character == 0x20 || character == 0x09 else {
                break
            }
            hyphenOffset += 1
        }

        guard hyphenOffset + 1 < nsLine.length,
              nsLine.character(at: hyphenOffset) == 0x2D,
              nsLine.character(at: hyphenOffset + 1) == 0x20
        else {
            return nil
        }

        let hyphenLocation = lineStart + hyphenOffset
        guard caretLocation <= hyphenLocation else {
            return nil
        }

        return NSRange(location: lineStart, length: hyphenOffset + 2)
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
}

enum CaptureLineAboveEditResolver {
    static func resolve(in text: String, selectedRange: NSRange) -> CaptureLineAboveEdit? {
        let nsText = text as NSString
        guard selectedRange.location >= 0,
              selectedRange.length == 0,
              selectedRange.location <= nsText.length
        else {
            return nil
        }

        var lineStart = 0
        nsText.getLineStart(
            &lineStart,
            end: nil,
            contentsEnd: nil,
            for: NSRange(location: selectedRange.location, length: 0)
        )

        let target = NSRange(location: lineStart, length: 0)
        return CaptureLineAboveEdit(
            replacementRange: target,
            replacementText: preferredCaptureLineTerminator(in: text),
            resultingSelection: target
        )
    }
}

@MainActor
final class CapturePanelController: NSObject, NSWindowDelegate {
    private let model: CapturePanelModel
    private let keyRouter = CaptureKeyCommandRouter()
    private var panel: NSPanel?
    private var localMonitor: Any?
    /// Goal column for consecutive Ctrl-Shift-J/Ctrl-Shift-K moves, paired with the exact collapsed
    /// caret this controller last left behind. Any other edit, click, or caret move
    /// changes the text view's selection away from `caret`, so the pairing invalidates
    /// itself without this controller having to observe every other input path.
    private var verticalMovementGoal: (column: Int, caret: NSRange)?
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
        model.requestFocus(.editor)
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

    func windowDidChangeScreen(_: Notification) {
        updateAvailableScreenHeight()
        applyLatestContentMetricsIfPossible()
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
        updateAvailableScreenHeight()
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
        updateAvailableScreenHeight(visibleFrame?.height)
        let sizer = CapturePanelWindowSizer(
            maximumContentHeight: visibleFrame == nil ? CapturePanelLayout.panelMaximumContentHeight : nil,
            displayScale: panel.screen?.backingScaleFactor ?? 1
        )
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
        }

        let frame = sizer.frame(
            forCurrentFrame: panel.frame,
            contentHeight: target,
            chromeHeight: Self.chromeHeight(for: panel),
            visibleFrame: visibleFrame ?? Self.unlimitedVisibleFrame
        )
        panel.setFrame(frame, display: true, animate: false)
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
        updateAvailableScreenHeight()
        let hostingView = NSHostingView(
            rootView: CapturePanelView(model: model) { [weak self] metrics in
                self?.receiveContentMetrics(metrics)
            }
        )
        hostingView.sizingOptions = []
        created.contentView = hostingView
        updateAvailableScreenHeight()
        created.contentView?.layoutSubtreeIfNeeded()
        applyLatestContentMetricsIfPossible()
        return created
    }

    /// Publishes the hosting screen's visible height to the model so SwiftUI can budget
    /// the editor against it. Assigns only on an actual change to avoid a metrics
    /// feedback loop; the budget depends on the screen, never on the applied window
    /// height.
    private func updateAvailableScreenHeight(_ height: CGFloat? = nil) {
        let resolved = height
            ?? panel?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
        guard model.availableScreenHeight != resolved else {
            return
        }
        model.availableScreenHeight = resolved
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

    /// Ctrl-Shift-O: insert one blank physical line above the current caret line through
    /// `NSTextView` so undo, IME, and accessibility stay AppKit-owned.
    static func insertLineAboveInEditableTextView(
        firstResponder: NSResponder?,
        model: CapturePanelModel
    ) -> Bool {
        guard let textView = editableTextView(firstResponder),
              let edit = CaptureLineAboveEditResolver.resolve(
                in: textView.string,
                selectedRange: textView.selectedRange()
              )
        else {
            return false
        }

        model.dismissCompletion()
        textView.insertText(edit.replacementText, replacementRange: edit.replacementRange)
        textView.setSelectedRange(edit.resultingSelection)
        textView.scrollRangeToVisible(edit.resultingSelection)
        return true
    }

    /// Plain Tab, first assist: expand an immediately preceding snippet trigger (`--` ->
    /// em dash today) at a collapsed caret. Returns `false` without changing state
    /// whenever `CaptureSnippetResolver.resolve` declines, so the caller can fall
    /// through to bullet indentation and then to AppKit's normal focus traversal.
    static func applySnippetExpansion(
        firstResponder: NSResponder?,
        model: CapturePanelModel
    ) -> Bool {
        guard let textView = editableTextView(firstResponder),
              let edit = CaptureSnippetResolver.resolve(
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

    /// Plain Tab's full ordered editor-assist chain: snippet expansion first, then
    /// continuation-bullet indentation. Returns `false` without changing state when both
    /// decline, so the key event falls through to AppKit's normal focus traversal.
    static func applyTabEditorAssist(
        firstResponder: NSResponder?,
        model: CapturePanelModel
    ) -> Bool {
        if applySnippetExpansion(firstResponder: firstResponder, model: model) {
            return true
        }
        return applyBulletIndentation(.increase, firstResponder: firstResponder, model: model)
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
    nonisolated static func bulletIndentationEdit(
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
    private nonisolated static func clampedOffset(_ offset: Int, removing range: NSRange) -> Int {
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
    private nonisolated static func isAuthoredBulletRow(_ lineText: NSString, leadingSpaces: Int) -> Bool {
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

    private nonisolated static func isBulletMarkerCharacter(_ character: unichar) -> Bool {
        character == Self.hyphen || character == Self.asterisk || character == Self.plus
    }

    private nonisolated static let asciiSpace: unichar = 0x20
    private nonisolated static let asciiTab: unichar = 0x09
    private nonisolated static let hyphen: unichar = 0x2D
    private nonisolated static let asterisk: unichar = 0x2A
    private nonisolated static let plus: unichar = 0x2B

    /// Ctrl-A / Ctrl-E target for a collapsed caret. Returns the new caret location, or
    /// `nil` when the key should fall through to AppKit: a non-collapsed selection, an
    /// out-of-bounds selection, or a caret already on the requested edge of the first
    /// (`.beginning`) or last (`.end`) physical line, where there is no line to step to.
    ///
    /// "Line" means a physical line as `NSString.getLineStart(_:end:contentsEnd:for:)`
    /// defines it, matching Ctrl-U, Ctrl-J, and Tab bullet indentation. Working from
    /// `lineStart` / `contentsEnd` / `lineEnd` rather than from raw offsets keeps this
    /// correct for CRLF terminators and for a draft that ends in a newline.
    nonisolated static func lineEdgeCyclingLocation(
        _ edge: CaptureLineEdge,
        in text: NSString,
        selectedRange: NSRange
    ) -> Int? {
        guard selectedRange.location >= 0,
              selectedRange.length == 0,
              selectedRange.location <= text.length
        else {
            return nil
        }

        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        text.getLineStart(
            &lineStart,
            end: &lineEnd,
            contentsEnd: &contentsEnd,
            for: NSRange(location: selectedRange.location, length: 0)
        )

        switch edge {
        case .beginning:
            if selectedRange.location > lineStart {
                return lineStart
            }
            // A previous line exists exactly when this one does not start the draft.
            guard lineStart > 0 else {
                return nil
            }
            var previousLineStart = 0
            text.getLineStart(
                &previousLineStart,
                end: nil,
                contentsEnd: nil,
                for: NSRange(location: lineStart - 1, length: 0)
            )
            return previousLineStart
        case .end:
            if selectedRange.location < contentsEnd {
                return contentsEnd
            }
            // A next line exists exactly when this one carries a terminator; the draft's
            // final line has `contentsEnd == lineEnd`.
            guard contentsEnd < lineEnd else {
                return nil
            }
            let nextLineStart = lineEnd
            // A draft ending in a newline has an empty final line whose start, contents
            // end, and end all equal the length.
            guard nextLineStart < text.length else {
                return nextLineStart
            }
            var nextContentsEnd = 0
            text.getLineStart(
                nil,
                end: nil,
                contentsEnd: &nextContentsEnd,
                for: NSRange(location: nextLineStart, length: 0)
            )
            return nextContentsEnd
        }
    }

    /// Ctrl-Shift-J / Ctrl-Shift-K target. Returns the new collapsed caret location and the goal
    /// column to carry forward, or `nil` when there is no adjacent physical line -- the
    /// last line for `.next`, the first line for `.previous` -- or when the selection is
    /// out of bounds. Unlike `lineEdgeCyclingLocation`, `nil` does **not** mean "fall
    /// through to AppKit": see `moveVertically(_:firstResponder:)`.
    ///
    /// A non-collapsed selection collapses toward the direction of travel first, so
    /// `.next` measures its column from the selection's end and `.previous` from its
    /// start.
    ///
    /// The column is the UTF-16 offset from the physical line's start, and it is clamped
    /// to the target line's `contentsEnd` so the caret never lands on or past a line
    /// terminator. A clamped target that would split a surrogate pair or a combining
    /// sequence snaps back to that sequence's start.
    ///
    /// "Line" means a physical line as `NSString.getLineStart(_:end:contentsEnd:for:)`
    /// defines it, matching Ctrl-J, Ctrl-U, and Ctrl-A/Ctrl-E. Working from `lineStart` /
    /// `contentsEnd` / `lineEnd` rather than from raw offsets keeps this correct for CRLF
    /// terminators and for a draft that ends in a newline.
    nonisolated static func verticalMovementTarget(
        _ direction: CaptureVerticalDirection,
        in text: NSString,
        selectedRange: NSRange,
        goalColumn: Int?
    ) -> CaptureVerticalMove? {
        guard selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.location + selectedRange.length <= text.length
        else {
            return nil
        }

        let anchor = direction == .next ? NSMaxRange(selectedRange) : selectedRange.location

        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        text.getLineStart(
            &lineStart,
            end: &lineEnd,
            contentsEnd: &contentsEnd,
            for: NSRange(location: anchor, length: 0)
        )

        let column = goalColumn ?? (anchor - lineStart)

        var targetStart = 0
        var targetContentsEnd = 0
        switch direction {
        case .previous:
            // A previous line exists exactly when this one does not start the draft.
            guard lineStart > 0 else {
                return nil
            }
            text.getLineStart(
                &targetStart,
                end: nil,
                contentsEnd: &targetContentsEnd,
                for: NSRange(location: lineStart - 1, length: 0)
            )
        case .next:
            // A next line exists exactly when this one carries a terminator; the draft's
            // final line has `contentsEnd == lineEnd`.
            guard contentsEnd < lineEnd else {
                return nil
            }
            targetStart = lineEnd
            if targetStart >= text.length {
                // A draft ending in a newline has an empty final line whose start,
                // contents end, and end all equal the length.
                targetContentsEnd = targetStart
            } else {
                text.getLineStart(
                    nil,
                    end: nil,
                    contentsEnd: &targetContentsEnd,
                    for: NSRange(location: targetStart, length: 0)
                )
            }
        }

        var location = min(targetStart + column, targetContentsEnd)
        if location > targetStart, location < targetContentsEnd {
            let composed = text.rangeOfComposedCharacterSequence(at: location)
            if composed.location < location {
                location = composed.location
            }
        }
        return CaptureVerticalMove(location: location, goalColumn: column)
    }

    /// Ctrl-U fallback: the range of the previous physical line, including its terminator,
    /// for a collapsed caret that already sits at the start of its own physical line --
    /// the state where deleting to the beginning of the line would remove nothing.
    ///
    /// Returns `nil` whenever the ordinary deletion still has work to do or there is no
    /// line above, so the caller falls through to AppKit's native
    /// `deleteToBeginningOfLine:`: a non-collapsed selection, an out-of-bounds selection, a
    /// caret past column zero, or a caret on the draft's first line.
    ///
    /// "Line" means a physical line as `NSString.getLineStart(_:end:contentsEnd:for:)`
    /// defines it, matching Ctrl-J, Ctrl-A/Ctrl-E, and Tab bullet indentation. Taking the
    /// previous line as `[previousLineStart, lineStart)` rather than as raw offset
    /// arithmetic keeps this correct for CRLF terminators, for blank lines, and for a draft
    /// that ends in a newline.
    nonisolated static func previousLineDeletionRange(
        in text: NSString,
        selectedRange: NSRange
    ) -> NSRange? {
        guard selectedRange.length == 0,
              selectedRange.location > 0,
              selectedRange.location <= text.length
        else {
            return nil
        }

        var lineStart = 0
        text.getLineStart(
            &lineStart,
            end: nil,
            contentsEnd: nil,
            for: NSRange(location: selectedRange.location, length: 0)
        )
        // Anything left before the caret on this line is the ordinary Ctrl-U deletion.
        guard selectedRange.location == lineStart else {
            return nil
        }

        // `location > 0` already guarantees `lineStart > 0`, so a previous line exists.
        var previousLineStart = 0
        text.getLineStart(
            &previousLineStart,
            end: nil,
            contentsEnd: nil,
            for: NSRange(location: lineStart - 1, length: 0)
        )
        return NSRange(location: previousLineStart, length: lineStart - previousLineStart)
    }

    /// Ctrl-U: delete from the caret to the beginning of the current physical line. When
    /// the caret is already at that line's start -- where the ordinary deletion would
    /// remove nothing -- delete the whole previous physical line instead, so repeated
    /// presses walk up the draft line by line and stop on the first line. The ordinary
    /// branch stays AppKit's native deletion so line boundaries, undo, IME, and
    /// accessibility remain owned by the text system.
    static func deleteToBeginningOfLineInEditableTextView(
        firstResponder: NSResponder?,
        model: CapturePanelModel
    ) -> Bool {
        guard let textView = editableTextView(firstResponder) else {
            return false
        }

        model.dismissCompletion()

        if let deletionRange = previousLineDeletionRange(
            in: textView.string as NSString,
            selectedRange: textView.selectedRange()
        ) {
            textView.insertText("", replacementRange: deletionRange)
            textView.scrollRangeToVisible(NSRange(location: deletionRange.location, length: 0))
            return true
        }

        textView.doCommand(by: Selector(("deleteToBeginningOfLine:")))
        return true
    }

    /// Ctrl-A / Ctrl-E: move the caret to a physical-line edge, stepping to the adjacent
    /// line when it is already there. Returns `false` without changing state whenever
    /// `lineEdgeCyclingLocation` declines, so the key event falls through to AppKit's
    /// native paragraph movement. This never dismisses completion: a caret move is not an
    /// edit, and `editorSelectionDidChange` re-anchors the completion list at the new
    /// caret on its own.
    static func moveLineEdge(
        _ edge: CaptureLineEdge,
        firstResponder: NSResponder?
    ) -> Bool {
        guard let textView = editableTextView(firstResponder),
              let location = lineEdgeCyclingLocation(
                edge,
                in: textView.string as NSString,
                selectedRange: textView.selectedRange()
              )
        else {
            return false
        }

        let target = NSRange(location: location, length: 0)
        textView.setSelectedRange(target)
        textView.scrollRangeToVisible(target)
        return true
    }

    /// Ctrl-Shift-J / Ctrl-Shift-K: move the caret to the next / previous physical line,
    /// keeping the column across consecutive presses. Returns `true` whenever the draft's
    /// text view holds focus, **including** when the move declines at the first or last
    /// line: Ctrl-Shift-K is consumed at the first line so the binding stays symmetric
    /// with Ctrl-Shift-J and a declined upward move cannot reach an unexpected native
    /// command. Exact Ctrl-K is not claimed by this keymap. Returns `false` only when
    /// there is no editable text view to move in, where falling through is harmless.
    /// Like Ctrl-A/Ctrl-E this never dismisses completion: a caret move is not an edit,
    /// and `editorSelectionDidChange` re-anchors the completion list at the new caret on
    /// its own.
    func moveVertically(
        _ direction: CaptureVerticalDirection,
        firstResponder: NSResponder?
    ) -> Bool {
        guard let textView = Self.editableTextView(firstResponder) else {
            verticalMovementGoal = nil
            return false
        }

        let selection = textView.selectedRange()
        let carriedColumn = verticalMovementGoal.flatMap {
            $0.caret == selection ? $0.column : nil
        }

        guard let move = Self.verticalMovementTarget(
            direction,
            in: textView.string as NSString,
            selectedRange: selection,
            goalColumn: carriedColumn
        ) else {
            // The caret did not move, so any carried goal stays valid and a press back the
            // other way still restores the column.
            return true
        }

        let target = NSRange(location: move.location, length: 0)
        textView.setSelectedRange(target)
        textView.scrollRangeToVisible(target)
        verticalMovementGoal = (column: move.goalColumn, caret: target)
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
        case .insertLineAbove:
            let inserted = Self.insertLineAboveInEditableTextView(
                firstResponder: panel?.firstResponder,
                model: model
            )
            if inserted {
                verticalMovementGoal = nil
            }
            return inserted
        case .deleteToBeginningOfLineOrPreviousLine:
            return Self.deleteToBeginningOfLineInEditableTextView(
                firstResponder: panel?.firstResponder,
                model: model
            )
        case .moveToBeginningOfLineOrPreviousLine:
            return Self.moveLineEdge(.beginning, firstResponder: panel?.firstResponder)
        case .moveToEndOfLineOrNextLine:
            return Self.moveLineEdge(.end, firstResponder: panel?.firstResponder)
        case .moveToNextLineKeepingColumn:
            return moveVertically(.next, firstResponder: panel?.firstResponder)
        case .moveToPreviousLineKeepingColumn:
            return moveVertically(.previous, firstResponder: panel?.firstResponder)
        case .deleteBackward:
            return Self.deleteEmptyBulletRowInEditableTextView(
                firstResponder: panel?.firstResponder,
                model: model
            )
        case .tabEditorAssist:
            return Self.applyTabEditorAssist(
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
        case .submitPomodoroNamePrompt:
            model.submitPomodoroNamePrompt()
            return true
        case .cancelPomodoroNamePrompt:
            model.cancelPomodoroNamePrompt()
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
                  self.panel?.isKeyWindow == true
            else {
                return event
            }
            self.repairPromptFieldFocusIfOrphaned()
            guard let command = self.keyRouter.command(
                for: event,
                context: CaptureKeyRoutingContext(
                    completionVisible: self.model.completionVisible,
                    stashPickerVisible: self.model.isStashPickerPresented,
                    stashEntryCount: self.model.stashCount,
                    taskIDPromptVisible: self.model.taskIDPromptVisible,
                    pomodoroNamePromptVisible: self.model.pomodoroNamePromptVisible
                )
            ) else {
                return event
            }

            return self.perform(command) ? nil : event
        }
    }

    /// While an inline naming prompt is open, a key event with no control holding first
    /// responder would be dropped. Re-claim only that orphaned state, leaving focused
    /// controls such as buttons alone.
    private func repairPromptFieldFocusIfOrphaned() {
        guard let panel, Self.blockIDFocusIsOrphaned(in: panel) else {
            return
        }

        if model.taskIDPromptVisible,
           model.taskIDPrompt?.isSaving != true,
           let field = Self.findBlockIDField(in: panel.contentView)
        {
            field.requestFirstResponder()
            CaptureSignpost.event("block-id-focus-repaired")
            return
        }

        if model.pomodoroNamePromptVisible,
           model.pomodoroNamePrompt?.isSaving != true,
           let field = Self.findPomodoroNameField(in: panel.contentView)
        {
            field.requestFirstResponder()
            CaptureSignpost.event("pomodoro-name-focus-repaired")
        }
    }

    static func blockIDFocusIsOrphaned(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder as? NSView else {
            return true
        }
        return responder === window.contentView
    }

    static func findBlockIDField(in view: NSView?) -> BlockIDNSTextField? {
        findTextField(
            in: view,
            identifier: blockIDFieldAccessibilityIdentifier
        )
    }

    static func findPomodoroNameField(in view: NSView?) -> PomodoroNameNSTextField? {
        findTextField(
            in: view,
            identifier: pomodoroNameFieldAccessibilityIdentifier
        )
    }

    private static func findTextField<Field: NSTextField>(
        in view: NSView?,
        identifier: String
    ) -> Field? {
        guard let view else {
            return nil
        }
        if let field = view as? Field,
           field.accessibilityIdentifier() == identifier
        {
            return field
        }
        for subview in view.subviews {
            if let field: Field = findTextField(in: subview, identifier: identifier) {
                return field
            }
        }
        return nil
    }

    // Ctrl-J, Ctrl-Shift-O, Ctrl-U, the placeholder-row Backspace, and Tab/Shift-Tab bullet
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
