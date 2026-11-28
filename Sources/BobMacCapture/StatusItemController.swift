import AppKit

/// Owns the menu-bar status item's visual state: the bullet-b glyph, its
/// tooltip and accessibility label, the conditional "bob not resolved" menu
/// rows, and the transient capture-landed pulse. Rendering goes through the
/// injected `render` sink so every state above AppKit stays unit-testable.
@MainActor
final class StatusItemController {
    /// Tag marking the conditional issue rows so `applyIssue` stays idempotent.
    static let issueRowTag = 0xB0B

    private let render: (StatusItemFrame) -> Void
    private let menu: NSMenu
    private let reduceMotion: () -> Bool
    private let sleep: (Duration) async -> Void
    private var presentation = StatusItemPresentation(isBobResolved: true)

    /// The in-flight pulse, if any. Exposed so tests can `await` it.
    var pulseTask: Task<Void, Never>?

    init(
        render: @escaping (StatusItemFrame) -> Void,
        menu: NSMenu,
        reduceMotion: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        sleep: @escaping (Duration) async -> Void = { duration in
            _ = try? await Task.sleep(for: duration)
        }
    ) {
        self.render = render
        self.menu = menu
        self.reduceMotion = reduceMotion
        self.sleep = sleep
    }

    private var restingFrame: StatusItemFrame {
        StatusItemFrame(
            glyphState: presentation.glyphState,
            bulletRadius: StatusItemGlyph.Metrics.bulletRadius,
            toolTip: presentation.toolTip,
            accessibilityLabel: presentation.accessibilityLabel,
            snoozeCount: presentation.snoozeCount
        )
    }

    private var isBobResolved: Bool {
        presentation.glyphState == .ready
    }

    /// Reflects a (possibly changed) `bob` resolution: cancels any pulse,
    /// renders the resting frame, and applies the conditional menu rows.
    /// Preserves the wake-beacon count; use `setSnoozeCount` to change it.
    func update(isBobResolved: Bool) {
        pulseTask?.cancel()
        pulseTask = nil
        presentation = StatusItemPresentation(
            isBobResolved: isBobResolved, snoozeCount: presentation.snoozeCount)
        render(restingFrame)
        Self.applyIssue(title: presentation.issueMenuTitle, to: menu)
    }

    /// Reflects the shared acknowledgement lifecycle's unacknowledged count.
    /// Does not cancel an in-flight pulse: pulse frames read the live
    /// presentation, so a beacon that clears mid-pulse stays cleared.
    func setSnoozeCount(_ count: Int) {
        let clamped = max(0, count)
        guard clamped != presentation.snoozeCount else {
            return
        }
        presentation = StatusItemPresentation(
            isBobResolved: isBobResolved, snoozeCount: clamped)
        // When a pulse is in flight its next frame re-renders with the new
        // count; rendering the resting frame here keeps the non-pulse path
        // immediate without resurrecting a stale count later.
        if pulseTask == nil {
            render(restingFrame)
        } else {
            render(restingFrame)
        }
    }

    /// Acceptance-probe view of the menu-bar beacon. Count, visibility,
    /// tooltip, and AX label only.
    func probeSnapshot() -> [String: Any] {
        [
            "count": presentation.snoozeCount,
            "accessory_visible": presentation.snoozeCount > 0,
            "tooltip": presentation.toolTip,
            "ax_label": presentation.accessibilityLabel,
        ]
    }

    /// Combined update for resolution and beacon, used at launch restore.
    func update(isBobResolved: Bool, snoozeCount: Int) {
        pulseTask?.cancel()
        pulseTask = nil
        presentation = StatusItemPresentation(
            isBobResolved: isBobResolved, snoozeCount: snoozeCount)
        render(restingFrame)
        Self.applyIssue(title: presentation.issueMenuTitle, to: menu)
    }

    /// Swells and settles the bullet once after a successful submit. Ready
    /// state only, skipped under Reduce Motion. A new pulse cancels an
    /// in-flight one; a state change cancels it via `update`.
    func playCaptureLandedPulse() {
        guard presentation.glyphState == .ready, !reduceMotion() else {
            return
        }
        pulseTask?.cancel()
        pulseTask = Task { [weak self] in
            guard let self else {
                return
            }
            let radii = StatusItemPulse.bulletRadii
            // The last pulse sample already equals the resting radius, so the
            // loop lands exactly on the resting frame of the current state.
            // Each frame reads the live presentation so a beacon cleared
            // mid-pulse is never restored by a stale frame.
            for index in radii.indices.dropFirst() {
                await self.sleep(StatusItemPulse.frameInterval)
                if Task.isCancelled {
                    return
                }
                let current = self.presentation
                self.render(
                    StatusItemFrame(
                        glyphState: .ready,
                        bulletRadius: radii[index],
                        toolTip: current.toolTip,
                        accessibilityLabel: current.accessibilityLabel,
                        snoozeCount: current.snoozeCount
                    ))
            }
        }
    }

    /// Idempotently applies the conditional issue rows: removes every item
    /// carrying `issueRowTag`, then, when `title` is non-nil, inserts the
    /// issue item at index 0 and a tagged separator at index 1. The nil target
    /// keeps the responder-chain routing the healthy items use.
    static func applyIssue(title: String?, to menu: NSMenu) {
        for item in menu.items where item.tag == issueRowTag {
            menu.removeItem(item)
        }
        guard let title else {
            return
        }
        let issueItem = NSMenuItem(
            title: title,
            action: #selector(AppDelegate.openSettings),
            keyEquivalent: ""
        )
        issueItem.target = nil
        issueItem.tag = issueRowTag
        issueItem.image = NSImage(
            systemSymbolName: "exclamationmark.triangle",
            accessibilityDescription: title
        )
        let separator = NSMenuItem.separator()
        separator.tag = issueRowTag
        menu.insertItem(issueItem, at: 0)
        menu.insertItem(separator, at: 1)
    }
}
