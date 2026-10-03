import CaptureCore
import Foundation

/// Snapshot of one open capture picker session. The draft must still equal
/// `draftSnapshot` for any accept to edit; otherwise the accept is refused as
/// stale so a late pick can never splice into a changed draft.
struct CapturePickerState: Equatable {
    /// Which source this session belongs to.
    var source: CapturePickerSource
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
    /// Physical line (1-based) of the block-ID marker token, shown in the
    /// scope capsule as `· line N`. Set only for the block-ID source on
    /// multi-line drafts; nil for `^`, whose visuals are frozen.
    var scopeLineNumber: Int? = nil
    /// Availability category last announced for the New ID filter
    /// (`available`, `unchecked`, `taken`, `invalid`). Availability is
    /// announced only when this changes, so typing within one category stays
    /// quiet. A fresh session starts unannounced.
    var lastAvailabilityKey: String? = nil
    /// Lexical owner of the `task_dependency` modifier the session opened
    /// on (nil for every other source, and for an ownerless leading `&`).
    /// Command-Return submits after insert only when this is non-nil: an
    /// ownerless pick must first gain task text or `@note+id`.
    var dependencyOwner: DependencyOwner? = nil
}

/// The compact reopen affordance shown instead of the picker: after a
/// two-stage Escape cancel, after a caret-only move into a picker's token, or
/// while auto-open is suppressed for the token.
struct CapturePickerChipState: Equatable {
    /// Which source this chip reopens.
    var source: CapturePickerSource
    /// The draft the chip's snapshot belongs to.
    var draftSnapshot: String
    var replacementRange: CaptureRange
    /// Caret the chip was shown with; the reopen query derives from it.
    var cursor: Int
    var candidates: [CaptureCompletionCandidate]
    var warnings: [String]
    /// Lexical `task_dependency` owner the chip's snapshot belongs to, so a
    /// refetch-free reopen keeps the Command-Return gate. Nil for other
    /// sources and ownerless picks.
    var dependencyOwner: DependencyOwner? = nil
}

/// Whether an analysis was triggered by a draft edit or by a caret-only
/// selection move. Edits may auto-open the picker; selection moves only ever
/// show the reopen chip.
enum CompletionTrigger {
    case edit
    case selection
}

/// The picker's local fuzzy index, wrapping the per-source index.
enum CapturePickerIndex {
    case activeTask(ActiveTaskPickerIndex)
    case taskLink(TaskLinkPickerIndex)
    case dependency(DependencyPickerIndex)
    case blockID(BlockIDPickerIndex)
    case parentTask(ParentTaskPickerIndex)

    func presentation(filter: String) -> CapturePickerPresentation {
        switch self {
        case .activeTask(let index):
            return index.presentation(filter: filter)
        case .taskLink(let index):
            return index.presentation(filter: filter)
        case .dependency(let index):
            return index.presentation(filter: filter)
        case .blockID(let index):
            return index.presentation(filter: filter)
        case .parentTask(let index):
            return index.presentation(filter: filter)
        }
    }

    func actionLine(for row: CapturePickerRow) -> String? {
        switch self {
        case .parentTask(let index):
            return index.actionLine(for: row)
        default:
            return nil
        }
    }
}
