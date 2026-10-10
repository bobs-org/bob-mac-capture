import Foundation

/// First-keystroke dim-hold for the idle agenda: when the draft turns
/// non-blank while the agenda is visible, the agenda dims in place until
/// the auxiliary region swaps to whatever owns it now. Pure so every
/// hold-release path is table-tested on Linux; `CapturePanelModel` owns
/// the 250 ms timer and the wiring, the view owns the 35% opacity.
public enum CaptureAgendaHold {
    /// What can end (or start) a hold, in plan §7 order: the live
    /// preview settling, any picker, completion, prompt, stash, or
    /// error taking the auxiliary region, the 250 ms ceiling, or the
    /// draft returning to blank, which cancels the hold.
    public enum Event: Equatable, Sendable {
        case draftBecameNonBlank
        case previewSettled
        case regionTaken
        case timeoutElapsed
        case draftReturnedToBlank
    }

    public enum State: Equatable, Sendable {
        case idle
        case holding
    }

    public static func next(state: State, event: Event) -> State {
        switch (state, event) {
        case (.idle, .draftBecameNonBlank):
            return .holding
        case (.holding, .previewSettled),
            (.holding, .regionTaken),
            (.holding, .timeoutElapsed),
            (.holding, .draftReturnedToBlank):
            return .idle
        case (.idle, _), (.holding, .draftBecameNonBlank):
            return state
        }
    }

    /// Hold ceiling from plan §7: the region swaps to whatever owns it
    /// now at the first release, or 250 ms after the first keystroke.
    public static let timeoutNanoseconds: UInt64 = 250_000_000

    /// Dimmed opacity while the hold is active, applied without
    /// animation under Reduce Motion.
    public static let dimmedOpacity: Double = 0.35

    /// Opacity cross-fade for in-place agenda updates while visible.
    /// Height is never animated.
    public static let updateFadeSeconds: Double = 0.12

    /// Fade length for the first-keystroke dim.
    public static let dimFadeSeconds: Double = 0.1
}
