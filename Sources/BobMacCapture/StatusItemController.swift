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
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    /// Reflects a (possibly changed) `bob` resolution: cancels any pulse,
    /// renders the resting frame, and applies the conditional menu rows.
    func update(isBobResolved: Bool) {
        pulseTask?.cancel()
        pulseTask = nil
        presentation = StatusItemPresentation(isBobResolved: isBobResolved)
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
            for index in radii.indices.dropFirst() {
                await self.sleep(StatusItemPulse.frameInterval)
                if Task.isCancelled {
                    return
                }
                self.render(StatusItemFrame(
                    glyphState: .ready,
                    bulletRadius: radii[index],
                    toolTip: self.presentation.toolTip,
                    accessibilityLabel: self.presentation.accessibilityLabel
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
