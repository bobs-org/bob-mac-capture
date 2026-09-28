import CaptureCore
import Foundation

/// Snapshot of one open Active Task Picker session. The draft must still equal
/// `draftSnapshot` for any accept to edit; otherwise the accept is refused as
/// stale so a late pick can never splice into a changed draft.
struct ActiveTaskPickerState: Equatable {
    /// The exact draft the snapshot was fetched for.
    var draftSnapshot: String
    /// Bob's replacement range the accept splices into.
    var replacementRange: CaptureRange
    /// Caret to restore on cancel (the caret the picker opened with).
    var restoreCursor: Int
    /// Bob-order candidates from the opening snapshot.
    var candidates: [CaptureCompletionCandidate]
    /// Bob warnings, shown in the picker instead of the status line.
    var warnings: [String]
    /// Current filter text. Seeded from the draft at open; keystrokes typed
    /// before the picker appears are captured by the seed query.
    var filterText: String
    /// Selected row ID (`replacement`). Always a visible row while the picker
    /// is open with candidates, else nil.
    var selectedRowID: String?
    /// Fixed at open from the grouped presentation's budget. Filtering never
    /// resizes the panel.
    var visibleRowBudget: Int
    /// True when the snapshot came from the caret response instead of the
    /// full `r.start` snapshot (the refetch disagreed or failed).
    var snapshotIsPartial: Bool
}

/// The compact "Browse active tasks" affordance shown instead of the picker:
/// after a two-stage Escape cancel, after a caret-only move into a `^` token,
/// or while auto-open is suppressed for the token.
struct ActiveTaskChipState: Equatable {
    /// The draft the chip's snapshot belongs to.
    var draftSnapshot: String
    var replacementRange: CaptureRange
    /// Caret the chip was shown with; the reopen query derives from it.
    var cursor: Int
    var candidates: [CaptureCompletionCandidate]
    var warnings: [String]
}

/// Whether an analysis was triggered by a draft edit or by a caret-only
/// selection move. Edits may auto-open the picker; selection moves only ever
/// show the reopen chip.
enum CompletionTrigger {
    case edit
    case selection
}
