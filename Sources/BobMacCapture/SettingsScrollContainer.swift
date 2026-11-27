import AppKit
import QuartzCore
import SwiftUI

/// Pure routing for Settings half-viewport paging: Control-D is down,
/// Control-U is up. Matches by key code like `RefsKeyRouter`, ignoring
/// Caps Lock, numeric-pad, and function flags. Shift, Option, or Command
/// added to the chord passes through. Marked (IME-composing) text passes
/// through, and repeats still route because there is no repeat gate.
enum SettingsScrollKeys {
    static func direction(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        markedTextPresent: Bool
    ) -> RefsInspectorScrollDirection? {
        if markedTextPresent {
            return nil
        }
        let flags =
            modifiers
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
            .subtracting(.numericPad)
            .subtracting(.function)
        guard flags == .control else {
            return nil
        }
        if keyCode == 2 {
            return .down
        }
        if keyCode == 32 {
            return .up
        }
        return nil
    }
}

/// Performs a content-top scroll on a scroll view, then calls completion.
/// Tests inject an instant performer to observe targets without animation.
typealias SettingsScrollPerform = (
    _ scrollView: NSScrollView,
    _ target: CGFloat,
    _ flipped: Bool,
    _ completion: @escaping () -> Void
) -> Void

/// Window metrics for the scrollable Settings container. A separate
/// non-generic namespace because static stored properties are not
/// supported in generic types.
enum SettingsScrollMetrics {
    static let fixedWidth: CGFloat = 620
    static let minHeight: CGFloat = 420
    static let maxIdealHeight: CGFloat = 820
    static let screenMargin: CGFloat = 64
    static let footerHeight: CGFloat = 28
}

/// Scrollable Settings container: width and height rules, a vertical
/// scroll view, and the slim footer (decision `hint = footer`). The anchor
/// sits in the content's background, the same placement as
/// `RefsInspectorView`'s anchor, so `enclosingScrollView` resolves.
@available(macOS 26.0, *)
struct SettingsScrollContainer<Content: View>: View {
    let content: Content
    var scrollPerformer: SettingsScrollPerform?

    @State private var idealHeight: CGFloat = Self.computedIdealHeight()

    init(
        scrollPerformer: SettingsScrollPerform? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.scrollPerformer = scrollPerformer
    }

    static func computedIdealHeight(visibleHeight: CGFloat? = nil) -> CGFloat {
        let visible = visibleHeight ?? NSScreen.main?.visibleFrame.height ?? 900
        return max(
            SettingsScrollMetrics.minHeight,
            min(
                SettingsScrollMetrics.maxIdealHeight,
                visible - SettingsScrollMetrics.screenMargin
            )
        )
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .padding(20)
                .background(
                    SettingsScrollKeyAnchor(scrollPerformer: scrollPerformer)
                )
        }
        .safeAreaBar(edge: .bottom) {
            footer
        }
        .frame(width: SettingsScrollMetrics.fixedWidth)
        .frame(
            minHeight: SettingsScrollMetrics.minHeight,
            idealHeight: idealHeight,
            maxHeight: .infinity
        )
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Text("⌃D Down  ⌃U Up")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .frame(
            height: SettingsScrollMetrics.footerHeight,
            alignment: .leading
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Layout marker inside the Settings scroll content: its
/// `enclosingScrollView` is the Settings scroll view. Never hit-tests,
/// so controls keep focus and clicks pass through.
@available(macOS 26.0, *)
struct SettingsScrollKeyAnchor: NSViewRepresentable {
    var scrollPerformer: SettingsScrollPerform?

    func makeNSView(context: Context) -> SettingsScrollKeyView {
        let view = SettingsScrollKeyView()
        view.scrollPerformer = scrollPerformer
        return view
    }

    func updateNSView(_ nsView: SettingsScrollKeyView, context: Context) {
        nsView.scrollPerformer = scrollPerformer
    }
}

/// Owns the Settings scroll keys: a local key-down monitor gated on the
/// Settings window (key, no sheet), plus the ungated scroll path that
/// tests drive directly. Mirrors `RefsPanelController.handleKeyDown` /
/// `processKeyEvent` so the gated entry stays separate from routing.
final class SettingsScrollKeyView: NSView {
    var scrollPerformer: SettingsScrollPerform?
    var planner = RefsInspectorScrollPlanner()
    var generation = 0
    private var keyMonitor: Any?
    private var liveScrollObserver: Any?
    private weak var observedScrollView: NSScrollView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installKeyMonitorIfNeeded()
        ensureLiveObserverIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeMonitors()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func layout() {
        super.layout()
        ensureLiveObserverIfNeeded()
    }

    deinit {
        removeMonitors()
    }

    static func findAnchor(in view: NSView?) -> SettingsScrollKeyView? {
        guard let view else {
            return nil
        }
        if let anchor = view as? SettingsScrollKeyView {
            return anchor
        }
        for subview in view.subviews {
            if let found = findAnchor(in: subview) {
                return found
            }
        }
        return nil
    }

    /// Production gate: the Settings window while it is key with no
    /// attached sheet. Tests that drive routed commands call
    /// `processKeyEvent` directly.
    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let window, window.isKeyWindow, window.attachedSheet == nil else {
            return event
        }
        guard event.type == .keyDown else {
            return event
        }
        return processKeyEvent(event)
    }

    /// Routes Control-D / Control-U from any field, accumulates from the
    /// outstanding target, and consumes every routed press (edges
    /// included) after flashing the scrollers. Returns the event
    /// unchanged when it should pass through to the text system.
    func processKeyEvent(_ event: NSEvent) -> NSEvent? {
        if markedTextPresent() {
            return event
        }
        guard
            let direction = SettingsScrollKeys.direction(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                markedTextPresent: false
            )
        else {
            return event
        }
        guard
            let scrollView = enclosingScrollView,
            let documentView = scrollView.documentView
        else {
            return nil
        }
        ensureLiveObserver(for: scrollView)
        let clipView = scrollView.contentView
        let contentHeight = documentView.frame.height
        let viewportHeight = clipView.bounds.height
        let flipped = documentView.isFlipped
        let offset = RefsInspectorScrollGeometry.offsetFromContentTop(
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            clipOriginY: clipView.bounds.origin.y,
            isFlipped: flipped
        )
        let measured = RefsInspectorScrollGeometry(
            offsetY: offset,
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            topInset: clipView.contentInsets.top,
            bottomInset: clipView.contentInsets.bottom
        )
        _ = planner.applyGeometry(measured)
        let tolerance: CGFloat = 0.5
        if direction == .down, planner.offset >= measured.maxOffset - tolerance {
            scrollView.flashScrollers()
            return nil
        }
        if direction == .up, planner.offset <= measured.minOffset + tolerance {
            scrollView.flashScrollers()
            return nil
        }
        guard let target = planner.command(direction) else {
            scrollView.flashScrollers()
            return nil
        }
        generation += 1
        let current = generation
        let performer = scrollPerformer ?? Self.defaultPerform
        scrollView.flashScrollers()
        performer(scrollView, target, flipped) { [weak self] in
            guard let self, self.generation == current else {
                return
            }
            guard
                let liveScrollView = self.enclosingScrollView,
                let liveDocument = liveScrollView.documentView
            else {
                return
            }
            let liveClip = liveScrollView.contentView
            let liveOffset = RefsInspectorScrollGeometry.offsetFromContentTop(
                contentHeight: liveDocument.frame.height,
                viewportHeight: liveClip.bounds.height,
                clipOriginY: liveClip.bounds.origin.y,
                isFlipped: liveDocument.isFlipped
            )
            let liveMeasured = RefsInspectorScrollGeometry(
                offsetY: liveOffset,
                contentHeight: liveDocument.frame.height,
                viewportHeight: liveClip.bounds.height,
                topInset: liveClip.contentInsets.top,
                bottomInset: liveClip.contentInsets.bottom
            )
            _ = self.planner.applyGeometry(liveMeasured)
        }
        return nil
    }

    static func defaultPerform(
        scrollView: NSScrollView,
        target: CGFloat,
        flipped: Bool,
        completion: @escaping () -> Void
    ) {
        guard let documentView = scrollView.documentView else {
            completion()
            return
        }
        let clipView = scrollView.contentView
        let originY = RefsInspectorScrollGeometry.clipOriginY(
            forContentTopOffset: target,
            contentHeight: documentView.frame.height,
            viewportHeight: clipView.bounds.height,
            isFlipped: flipped
        )
        let origin = NSPoint(x: clipView.bounds.origin.x, y: originY)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                clipView.animator().setBoundsOrigin(origin)
            },
            completionHandler: {
                scrollView.reflectScrolledClipView(clipView)
                completion()
            })
    }

    private func markedTextPresent() -> Bool {
        guard let window else {
            return false
        }
        if let textView = window.firstResponder as? NSTextView,
            textView.hasMarkedText()
        {
            return true
        }
        return false
    }

    private func installKeyMonitorIfNeeded() {
        guard window != nil, keyMonitor == nil else {
            return
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self else {
                return event
            }
            return self.handleKeyDown(event)
        }
    }

    private func ensureLiveObserverIfNeeded() {
        guard let scrollView = enclosingScrollView else {
            return
        }
        ensureLiveObserver(for: scrollView)
    }

    private func ensureLiveObserver(for scrollView: NSScrollView) {
        if observedScrollView === scrollView, liveScrollObserver != nil {
            return
        }
        if let liveScrollObserver {
            NotificationCenter.default.removeObserver(liveScrollObserver)
        }
        liveScrollObserver = nil
        observedScrollView = scrollView
        liveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.cancelPendingForUserScroll()
        }
    }

    private func cancelPendingForUserScroll() {
        guard
            let scrollView = enclosingScrollView,
            let documentView = scrollView.documentView
        else {
            planner.beginUserScroll(at: planner.offset)
            return
        }
        let clipView = scrollView.contentView
        let offset = RefsInspectorScrollGeometry.offsetFromContentTop(
            contentHeight: documentView.frame.height,
            viewportHeight: clipView.bounds.height,
            clipOriginY: clipView.bounds.origin.y,
            isFlipped: documentView.isFlipped
        )
        planner.beginUserScroll(at: offset)
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        if let liveScrollObserver {
            NotificationCenter.default.removeObserver(liveScrollObserver)
        }
        liveScrollObserver = nil
        observedScrollView = nil
    }
}
