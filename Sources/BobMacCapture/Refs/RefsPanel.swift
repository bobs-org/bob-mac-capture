import AppKit
import Combine
import RefsCore
import SwiftUI

/// The accessibility identifier of the Refs search field, so the panel
/// controller can find it in the view tree without a reference back
/// into SwiftUI.
let refsFilterFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.refs-filter"

/// The borderless non-activating glass panel. `canBecomeKey` is true so
/// the search field takes keystrokes; `canBecomeMain` stays false so
/// Highlights, or whatever app was frontmost, stays active.
final class RefsPanel: NSPanel {
    /// Called when the panel resigns key (a click in another window or
    /// app). The controller hides the panel here, like Spotlight.
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Owns the Refs panel window: prewarming, showing, hiding, the local
/// key monitor gated on key status, and search-field focus repair. The
/// panel is fixed-size while visible and never activates the app.
@MainActor
public final class RefsPanelController: NSObject {
    private let model: RefsPanelModel
    private var panel: RefsPanel?
    private var localMonitor: Any?
    private let copyHUD = RefsCopyHUDController()
    private var inspectorScrollCancellable: AnyCancellable?
    private var inspectorRevealCancellable: AnyCancellable?
    private var revealFollowTask: Task<Void, Never>?
    /// While a reveal waits for SwiftUI layout, the next Ctrl+D counts
    /// as at-the-bottom so rapid presses stack into pages.
    private var revealFollowPending = false
    private var pendingRevealGeneration: Int?
    /// While true, a resign-key does not hide the panel. The ⌘K
    /// actions menu sets this while it tracks.
    var suspendHideOnResign = false
    /// Refs hides through the coordinator after a successful copy, which
    /// may restore the retained Capture draft.
    var copyDismisser: () -> Void = {}

    public init(model: RefsPanelModel) {
        self.model = model
        super.init()
        model.panelDismisser = { [weak self] in self?.hide() }
        model.panelPresenter = { [weak self] in self?.show() }
        model.actionsPresenter = { [weak self] in self?.showActionsMenu() }
        copyDismisser = { [weak self] in self?.hide() }
        model.copyCompletion = { [weak self] row in
            self?.copySucceeded(row)
        }
        model.panelIsVisible = { [weak self] in self?.isVisible == true }
        inspectorScrollCancellable = model.inspectorScrolls.sink { [weak self] direction in
            self?.scrollInspector(direction)
        }
        inspectorRevealCancellable = model.inspectorNoteReveals.sink { [weak self] reveal in
            self?.followReveal(reveal)
        }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    /// Whether the panel is currently visible.
    public var isVisible: Bool {
        panel?.isVisible == true
    }

    /// Builds the panel and hosting view at launch, the way capture's
    /// `prewarm` does, so the first show paints from memory.
    public func prewarm() {
        _ = makePanelIfNeeded()
    }

    /// Shows the panel: resets the model, recomputes the frame, fades
    /// in, and focuses the search field. Highlights stays frontmost:
    /// this never calls `NSApp.activate`.
    public func show() {
        let token = CaptureSignpost.begin("refs-panel-show")
        defer { CaptureSignpost.end(token) }
        copyHUD.dismiss()
        model.prepareForPresentation()
        model.refreshForOpen()
        orderFront()
    }

    /// Re-shows the panel after an open error without resetting it: the
    /// query, scope, frozen listing, selection, and pending open all
    /// survive, and the banner set by the model stays up. No refresh
    /// runs here, so no late data can reorder the frozen rows either.
    public func represent() {
        let token = CaptureSignpost.begin("refs-panel-reshow")
        defer { CaptureSignpost.end(token) }
        copyHUD.dismiss()
        orderFront()
    }

    /// Orders the panel front with the show animation: recomputed frame,
    /// 0.12 s fade-in, key monitors, and search-field focus.
    private func orderFront() {
        let panel = makePanelIfNeeded()
        panel.setFrame(
            RefsVisualTokens.panelFrame(for: Self.visibleFrame()),
            display: false
        )
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.12
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.animator().alphaValue = 1
        NSAnimationContext.endGrouping()
        panel.invalidateShadow()
        installMonitorsIfNeeded()
        focusFilterField()
    }

    /// Hides at once, with no fade-out. Key status returns to the
    /// frontmost app on its own. The model clears a seen scan notice
    /// here, so a finished scan's footer text does not linger.
    public func hide() {
        copyHUD.dismiss()
        panel?.orderOut(nil)
        model.panelDidHide()
    }

    private func copySucceeded(_ row: RefsCopyRow) {
        let formerFrame = panel?.frame ?? .zero
        copyDismisser()
        copyHUD.show(
            title: row.confirmationTitle,
            value: row.preview,
            centeredOn: formerFrame
        )
        AccessibilityNotification.Announcement(row.confirmationTitle).post()
    }

    /// Pops the ⌘K actions menu below the selected row, or at the
    /// list's center when the row frame is unknown. The resign-key hide
    /// suspends while the menu tracks, so picking an action never
    /// dismisses the panel first. Toggling lives in
    /// `BobPanelCoordinator.toggleRefs`, which also closes a visible
    /// panel from the global hotkey and the takeover key.
    public func showActionsMenu() {
        guard let panel,
              let contentView = panel.contentView,
              model.selectedItem != nil
        else {
            return
        }
        let sections = model.actionsSections()
        guard !sections.isEmpty else {
            return
        }
        let flat = sections.flatMap { $0 }
        let menu = NSMenu()
        // The menu manages its own enabled state: while a scan runs,
        // the scan item is disabled instead of starting a second scan.
        menu.autoenablesItems = false
        let scanDisabled = model.isScanning
        for (index, section) in sections.enumerated() {
            if index > 0 {
                menu.addItem(NSMenuItem.separator())
            }
            for action in section {
                let item = NSMenuItem(
                    title: action.title,
                    action: #selector(fireActionsMenu(_:)),
                    keyEquivalent: action.keyEquivalent
                )
                item.keyEquivalentModifierMask = action.keyEquivalentModifierMask
                item.target = self
                item.tag = flat.firstIndex(of: action) ?? 0
                if action == .scanLibrary, scanDisabled {
                    item.isEnabled = false
                }
                menu.addItem(item)
            }
        }
        actionsMenuActions = flat
        suspendHideOnResign = true
        defer { suspendHideOnResign = false }
        menu.popUp(
            positioning: nil,
            at: Self.actionsAnchor(
                rowRect: model.selectedRowRect,
                hostingFrame: (contentView as? NSGlassEffectView)?.contentView?.frame
                    ?? contentView.bounds,
                contentSize: contentView.bounds.size,
                panelWidth: contentView.bounds.width
            ),
            in: contentView
        )
    }

    private var actionsMenuActions: [RefsAction] = []

    @objc private func fireActionsMenu(_ sender: NSMenuItem) {
        guard actionsMenuActions.indices.contains(sender.tag) else {
            return
        }
        model.performAction(actionsMenuActions[sender.tag])
    }

    /// The ⌘K anchor in the content view's coordinates: just below
    /// the selected row's leading text, from the row frame the list
    /// keeps live in panel-root SwiftUI coordinates (y-down, relative
    /// to the hosting view). The hosting view is flipped, so its
    /// y-down point maps into the unflipped content view by height.
    /// When the row frame is unknown, the list column's center.
    static func actionsAnchor(
        rowRect: CGRect?,
        hostingFrame: NSRect,
        contentSize: NSSize,
        panelWidth: CGFloat
    ) -> NSPoint {
        if let rowRect, !rowRect.isNull, rowRect != .zero {
            return NSPoint(
                x: hostingFrame.minX + rowRect.minX + 12,
                y: hostingFrame.minY + hostingFrame.height - rowRect.maxY
            )
        }
        let listWidth = RefsVisualTokens.listWidth(panelWidth: panelWidth)
        return NSPoint(
            x: RefsVisualTokens.outerPadding + listWidth / 2,
            y: contentSize.height / 2
        )
    }

    /// The panel configuration, static so geometry tests assert it
    /// without showing anything.
    static func makePanel() -> RefsPanel {
        let panel = RefsPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: RefsVisualTokens.panelWidth,
                height: RefsVisualTokens.panelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        return panel
    }

    func makePanelIfNeeded() -> RefsPanel {
        if let panel {
            return panel
        }
        let created = Self.makePanel()
        created.onResignKey = { [weak self] in
            guard let self, !self.suspendHideOnResign else {
                return
            }
            self.hide()
        }
        panel = created
        let hostingView = NSHostingView(rootView: RefsPanelView(model: model))
        hostingView.sizingOptions = []
        let glass = NSGlassEffectView()
        glass.cornerRadius = RefsVisualTokens.glassRadius
        glass.contentView = hostingView
        created.contentView = glass
        created.contentView?.layoutSubtreeIfNeeded()
        return created
    }

    private func installMonitorsIfNeeded() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .flagsChanged]
            ) { [weak self] event in
                guard let self else {
                    return event
                }
                return self.handleKeyDown(event)
            }
        }
    }

    /// The production monitor's key-window gate. Tests that need the
    /// pass-through when Refs is not key call this; tests that drive
    /// routed commands call `processKeyEvent`.
    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard panel?.isKeyWindow == true else {
            return event
        }
        return processKeyEvent(event)
    }

    /// Focus repair plus router plus model. The local monitor calls this
    /// only while the panel is key.
    func processKeyEvent(_ event: NSEvent) -> NSEvent? {
        if suspendHideOnResign {
            return event
        }
        if event.type == .flagsChanged {
            model.updateCopyModifiers(Self.copyModifiers(event.modifierFlags))
            return event
        }
        if model.copyCard != nil {
            model.handleCopyCardKey(
                characters: event.charactersIgnoringModifiers,
                keyCode: event.keyCode,
                modifiers: Self.copyModifiers(event.modifierFlags)
            )
            return nil
        }
        repairFilterFocusIfNeeded()
        guard let command = command(for: event) else {
            return event
        }
        return model.perform(command) ? nil : event
    }

    private static func copyModifiers(
        _ flags: NSEvent.ModifierFlags
    ) -> RefsCopyKeyModifiers {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: RefsCopyKeyModifiers = []
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        if flags.contains(.numericPad) { result.insert(.numericPad) }
        if flags.contains(.function) { result.insert(.function) }
        if flags.contains(.help) { result.insert(.help) }
        return result
    }

    private func command(for event: NSEvent) -> RefsCommand? {
        RefsKeyRouter.command(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(
                .deviceIndependentFlagsMask
            ),
            context: RefsKeyContext(
                queryIsEmpty: model.query.isEmpty,
                scopeIsAll: model.scope == .all,
                markedTextPresent: markedTextInFilterField(),
                listModeIsBrowse: {
                    if case .browse = model.listing.mode {
                        return true
                    }
                    return false
                }()
            )
        )
    }

    private func markedTextInFilterField() -> Bool {
        guard let field = Self.findFilterField(in: panel?.contentView),
              let editor = field.currentEditor() as? NSTextView
        else {
            return false
        }
        return editor.hasMarkedText()
    }

    /// Claims search-field focus when nothing else holds it, leaving
    /// focused controls such as banner buttons alone.
    private func repairFilterFocusIfNeeded() {
        guard let panel,
              let field = Self.findFilterField(in: panel.contentView)
        else {
            return
        }
        // Re-claim only the orphaned state — no responder, or the
        // content view itself — leaving focused controls such as banner
        // buttons alone.
        guard panel.firstResponder == nil
            || panel.firstResponder === panel.contentView
        else {
            return
        }
        field.requestFirstResponder()
    }

    private func focusFilterField() {
        Self.findFilterField(in: panel?.contentView)?.requestFirstResponder()
        // Retry once the runloop turns over: the field editor may not
        // exist yet on the first pass.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self,
                  let panel = self.panel,
                  panel.isKeyWindow,
                  let field = Self.findFilterField(in: panel.contentView),
                  !field.holdsFirstResponder
            else {
                return
            }
            field.requestFirstResponder()
        }
    }

    static func findFilterField(in view: NSView?) -> CapturePickerFilterNSTextField? {
        guard let view else {
            return nil
        }
        if let field = view as? CapturePickerFilterNSTextField,
           field.accessibilityIdentifier() == refsFilterFieldAccessibilityIdentifier
        {
            return field
        }
        for subview in view.subviews {
            if let found = findFilterField(in: subview) {
                return found
            }
        }
        return nil
    }

    static func findInspectorScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else {
            return nil
        }
        if view is RefsInspectorScrollAnchorView {
            return view.enclosingScrollView
        }
        for subview in view.subviews {
            if let found = findInspectorScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    static func findRevealAnchor(generation: Int, in view: NSView?) -> RefsInspectorRevealAnchorView? {
        guard let view else {
            return nil
        }
        if let anchor = view as? RefsInspectorRevealAnchorView,
           anchor.generation == generation
        {
            return anchor
        }
        for subview in view.subviews {
            if let found = findRevealAnchor(generation: generation, in: subview) {
                return found
            }
        }
        return nil
    }

    /// Measures the inspector scroll geometry, or nil when there is no
    /// inspector scroll view (narrow panel).
    private func measureInspectorScroll() -> (
        scrollView: NSScrollView,
        geometry: RefsInspectorScrollGeometry,
        flipped: Bool
    )? {
        guard let scrollView = Self.findInspectorScrollView(in: panel?.contentView),
              let documentView = scrollView.documentView
        else {
            return nil
        }
        let clip = scrollView.contentView
        let content = documentView.frame.height
        let viewport = clip.bounds.height
        let flipped = documentView.isFlipped
        let offset = flipped
            ? clip.bounds.origin.y : content - viewport - clip.bounds.origin.y
        let geometry = RefsInspectorScrollGeometry(
            offsetY: offset,
            contentHeight: content,
            viewportHeight: viewport,
            topInset: clip.contentInsets.top,
            bottomInset: clip.contentInsets.bottom
        )
        return (scrollView, geometry, flipped)
    }

    /// Sets an offset measured from the content top on the clip view.
    private func setInspectorOffset(
        _ target: CGFloat,
        scrollView: NSScrollView,
        flipped: Bool
    ) {
        guard let documentView = scrollView.documentView else {
            return
        }
        let clip = scrollView.contentView
        let content = documentView.frame.height
        let viewport = clip.bounds.height
        let y = flipped ? target : content - viewport - target
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    private func cancelRevealFollow() {
        revealFollowTask?.cancel()
        revealFollowTask = nil
        revealFollowPending = false
        pendingRevealGeneration = nil
    }

    func scrollInspector(_ direction: RefsInspectorScrollDirection) {
        if direction == .up {
            cancelRevealFollow()
        }
        guard let measured = measureInspectorScroll() else {
            return
        }
        if direction == .down,
           (revealFollowPending || measured.geometry.isAtBottom()),
           model.revealMoreInspectorNotes()
        {
            return
        }
        var planner = RefsInspectorScrollPlanner(geometry: measured.geometry)
        guard let target = planner.command(direction) else {
            return
        }
        setInspectorOffset(
            target,
            scrollView: measured.scrollView,
            flipped: measured.flipped
        )
    }

    private func followReveal(_ reveal: RefsInspectorNotesReveal) {
        revealFollowTask?.cancel()
        revealFollowPending = true
        pendingRevealGeneration = reveal.generation
        let id = reveal.id
        let generation = reveal.generation
        revealFollowTask = Task { [weak self] in
            defer {
                if self?.pendingRevealGeneration == generation {
                    self?.revealFollowPending = false
                    self?.pendingRevealGeneration = nil
                    self?.revealFollowTask = nil
                }
            }
            let deadline = Date().addingTimeInterval(0.5)
            while Date() < deadline {
                if Task.isCancelled {
                    return
                }
                guard let self else {
                    return
                }
                if !self.isVisible {
                    return
                }
                if self.model.selectedID != id {
                    return
                }
                if self.model.inspectorNotesPage(for: id).generation != generation {
                    return
                }
                self.panel?.contentView?.layoutSubtreeIfNeeded()
                if let measured = self.measureInspectorScroll(),
                   let anchor = Self.findRevealAnchor(
                       generation: generation,
                       in: self.panel?.contentView
                   ),
                   let documentView = measured.scrollView.documentView
                {
                    let rect = anchor.convert(anchor.bounds, to: documentView)
                    if rect.height > 0.5 {
                        let documentHeight = documentView.frame.height
                        let batchTop: CGFloat = documentView.isFlipped
                            ? rect.minY : documentHeight - rect.maxY
                        if let target = RefsInspectorScrollPlanner.revealTarget(
                            geometry: measured.geometry,
                            batchTop: batchTop,
                            context: RefsVisualTokens.inspectorRevealContext
                        ) {
                            self.setInspectorOffset(
                                target,
                                scrollView: measured.scrollView,
                                flipped: measured.flipped
                            )
                        }
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    static func scrollViews(in view: NSView?) -> [NSScrollView] {
        guard let view else {
            return []
        }
        var found: [NSScrollView] = []
        if let scroll = view as? NSScrollView {
            found.append(scroll)
        }
        for subview in view.subviews {
            found.append(contentsOf: scrollViews(in: subview))
        }
        return found
    }
}

private extension RefsPanelController {
    /// The visible frame of the screen containing the mouse, falling
    /// back to main. Recomputed on every show.
    static func visibleFrame() -> NSRect {
        let point = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(point, $0.frame, false)
        }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
