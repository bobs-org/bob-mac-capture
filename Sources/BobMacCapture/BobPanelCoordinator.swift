/// Owns the one-Bob-panel rule: Capture and Refs are never visible
/// together. Showing Refs while Capture is visible first retains the
/// capture draft, so reopening Capture restores it. Showing Capture while
/// Refs is visible hides Refs. Refs work runs on its own `refs-*` lanes,
/// so it can never cancel a capture submit.
@MainActor
final class BobPanelCoordinator {
    private let isCaptureVisible: () -> Bool
    private let isRefsVisible: () -> Bool
    private let closeCaptureRetainingDraft: () -> Void
    private let presentCapture: () -> Void
    private let presentRefs: () -> Void
    private let hideRefs: () -> Void

    init(
        isCaptureVisible: @escaping () -> Bool,
        isRefsVisible: @escaping () -> Bool,
        closeCaptureRetainingDraft: @escaping () -> Void,
        presentCapture: @escaping () -> Void,
        presentRefs: @escaping () -> Void,
        hideRefs: @escaping () -> Void
    ) {
        self.isCaptureVisible = isCaptureVisible
        self.isRefsVisible = isRefsVisible
        self.closeCaptureRetainingDraft = closeCaptureRetainingDraft
        self.presentCapture = presentCapture
        self.presentRefs = presentRefs
        self.hideRefs = hideRefs
    }

    /// Shows Capture, hiding Refs first when it is visible.
    func showCapture() {
        if isRefsVisible() {
            hideRefs()
        }
        presentCapture()
    }

    /// Shows Refs, retaining the capture draft first when Capture
    /// is visible.
    func showRefs() {
        if isCaptureVisible() {
            closeCaptureRetainingDraft()
        }
        presentRefs()
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
}
