/// Owns the one-Bob-panel rule: Capture and Refs are never visible
/// together. Showing Refs while Capture is visible first retains the
/// capture draft, so reopening Capture restores it. Showing Capture while
/// Refs is visible hides Refs. Refs work runs on its own `refs-*` lanes,
/// so it can never cancel a capture submit.
///
/// Ctrl+Tab (and Ctrl+Shift+Tab) switches between the two panels through
/// `switchPanels(from:)`, preserving each panel's state exactly as the
/// hotkeys do.
enum BobPanel {
    case capture
    case refs
}

@MainActor
final class BobPanelCoordinator {
    private let isCaptureVisible: () -> Bool
    private let isRefsVisible: () -> Bool
    private let closeCaptureRetainingDraft: () -> Void
    private let presentCapture: () -> Void
    private let presentRefs: () -> Void
    private let presentRefsWithSource: (RefsPresentationSource) -> Void
    private let presentRefsPreservingState: () -> Void
    private let isRefsInTabs: () -> Bool
    private let setRefsTabsFilter: (Bool) -> Void
    private let hideRefs: () -> Void
    private var returnToCaptureAfterCopy = false

    init(
        isCaptureVisible: @escaping () -> Bool,
        isRefsVisible: @escaping () -> Bool,
        closeCaptureRetainingDraft: @escaping () -> Void,
        presentCapture: @escaping () -> Void,
        presentRefs: @escaping () -> Void,
        presentRefsPreservingState: @escaping () -> Void = {},
        presentRefsWithSource: ((RefsPresentationSource) -> Void)? = nil,
        isRefsInTabs: @escaping () -> Bool = { false },
        setRefsTabsFilter: @escaping (Bool) -> Void = { _ in },
        hideRefs: @escaping () -> Void
    ) {
        self.isCaptureVisible = isCaptureVisible
        self.isRefsVisible = isRefsVisible
        self.closeCaptureRetainingDraft = closeCaptureRetainingDraft
        self.presentCapture = presentCapture
        self.presentRefs = presentRefs
        self.presentRefsWithSource = presentRefsWithSource ?? { _ in presentRefs() }
        self.presentRefsPreservingState = presentRefsPreservingState
        self.isRefsInTabs = isRefsInTabs
        self.setRefsTabsFilter = setRefsTabsFilter
        self.hideRefs = hideRefs
    }

    /// Shows Capture, hiding Refs first when it is visible.
    func showCapture() {
        returnToCaptureAfterCopy = false
        if isRefsVisible() {
            hideRefs()
        }
        presentCapture()
    }

    /// Shows Refs, retaining the capture draft first when Capture
    /// is visible.
    func showRefs(source: RefsPresentationSource = .library) {
        returnToCaptureAfterCopy = isCaptureVisible()
        if returnToCaptureAfterCopy {
            closeCaptureRetainingDraft()
        }
        presentRefsWithSource(source)
    }

    /// Switches to the other panel, preserving state exactly as the
    /// hotkeys do: from Capture retains the draft and shows Refs with
    /// `.panelSwitch` (so a later copy still restores Capture); from Refs
    /// hides Refs and shows Capture. A stale origin whose panel is no
    /// longer visible is a no-op returning nil, so a deferred hop never
    /// bounces back.
    @discardableResult
    func switchPanels(from origin: BobPanel) -> BobPanel? {
        switch origin {
        case .capture:
            guard isCaptureVisible() else { return nil }
            showRefs(source: .panelSwitch)
            return .refs
        case .refs:
            guard isRefsVisible() else { return nil }
            showCapture()
            return .capture
        }
    }

    /// Hides Refs after a copy and restores Capture only when Refs was
    /// opened over a visible Capture draft.
    func dismissRefsAfterCopy() {
        hideRefs()
        guard returnToCaptureAfterCopy else { return }
        returnToCaptureAfterCopy = false
        presentCapture()
    }

    /// Re-shows Refs after an open error without resetting it, retaining
    /// a visible Capture draft first exactly as `showRefs` does.
    func representRefs() {
        if isCaptureVisible() {
            closeCaptureRetainingDraft()
        }
        presentRefsPreservingState()
    }

    /// Toggles Refs: hides it when visible, shows it (retaining a
    /// visible Capture draft) otherwise.
    func toggleRefs() {
        if isRefsVisible() {
            hideRefs()
        } else {
            showRefs()
        }
    }

    /// Opens Refs in Tabs, enables Tabs in an already visible library, or
    /// hides the panel when Tabs is already showing. When Command-T is the
    /// takeover key, it unregisters while Refs is visible so the panel's own
    /// Command-T handler switches between Tabs and the library.
    func toggleRefsTabs() {
        guard isRefsVisible() else {
            showRefs(source: .highlightsTabs)
            return
        }
        if isRefsInTabs() {
            hideRefs()
        } else {
            setRefsTabsFilter(true)
        }
    }
}
