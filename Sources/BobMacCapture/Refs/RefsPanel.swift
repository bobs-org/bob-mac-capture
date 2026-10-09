import AppKit
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
    /// While true, a resign-key does not hide the panel. The ⌘K
    /// actions menu sets this while it tracks (a later phase).
    var suspendHideOnResign = false

    public init(model: RefsPanelModel) {
        self.model = model
        super.init()
        model.panelDismisser = { [weak self] in self?.hide() }
        model.panelPresenter = { [weak self] in self?.show() }
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
        model.prepareForPresentation()
        model.refreshIfStale()
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
    /// frontmost app on its own.
    public func hide() {
        panel?.orderOut(nil)
    }

    /// Toggles the panel.
    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
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

    private func makePanelIfNeeded() -> RefsPanel {
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
        created.contentView = hostingView
        created.contentView?.layoutSubtreeIfNeeded()
        return created
    }

    private func installMonitorsIfNeeded() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown
            ) { [weak self] event in
                guard let self,
                      self.panel?.isKeyWindow == true
                else {
                    return event
                }
                self.repairFilterFocusIfNeeded()
                guard let command = self.command(for: event) else {
                    return event
                }
                return self.model.perform(command) ? nil : event
            }
        }
    }

    private func command(for event: NSEvent) -> RefsCommand? {
        RefsKeyRouter.command(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(
                .deviceIndependentFlagsMask
            ),
            context: RefsKeyContext(
                bannerVisible: model.banner != nil,
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
