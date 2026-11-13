import AppKit
import Combine
import CaptureCore
import Foundation
import SwiftUI

enum CapturePreviewState: Equatable {
    case idle
    case loading
    case ready(CaptureCommandSuccess)
    case failed(String)
}

/// Relation-card row identity comes from Bob's canonical label key. Refused cancel rows
/// can share an empty replacement, so candidate identity is not unique.
struct CaptureRelationLabelRowEntry: Identifiable {
    let id: String
    let candidate: CaptureCompletionCandidate
}

/// One-shot expected buffer after native separator insertion or a sigil alias.
/// Cleared on consume, mismatch, or lifecycle invalidation; never used to parse grammar.
/// The keystroke's completion waits on the eager rewrite (the completion gate):
/// an accepted toggle supersedes that analysis, while any other outcome completes
/// like an ordinary keystroke.
private struct SeparatorToggleIntent: Equatable {
    let typed: String
    let expectedDraft: String
    let expectedCursorUTF8: Int
    let timestamp: TimeInterval
    let expectsRelationDirectionToggle: Bool
}

/// One-shot expected buffer after a physically Shift- or Option-typed
/// `@` or `#`. Separate from the rewrite-lane separator intent.
private struct TypedSigilIntent: Equatable {
    let sigil: String
    let expectedDraft: String
    let expectedCaretUTF8: Int
}

private enum AliasTipSurface: Equatable {
    case completionList
    case picker

    var lessonHost: CaptureAliasTipHost {
        switch self {
        case .completionList: return .completionList
        case .picker: return .picker
        }
    }
}

private struct AliasTipSurfaceSnapshot {
    let kind: AliasTipSurface
    let draft: String
    let replacementRange: CaptureRange
}

private struct AliasTipAnchor: Equatable {
    let draft: String
    let sigilRange: CaptureRange
    let sigil: String
}

/// One physical request owns exactly one first-surface opening opportunity.
private struct AliasTipRequest: Equatable {
    let generation: UInt64
    let cursorUTF8Offset: Int
    let anchor: AliasTipAnchor
    var openedSurface: AliasTipSurface? = nil
    var dropReason: AliasTipDropReason? = nil
}

/// A bob-proved tip waiting for the first surface opened by its request.
private struct PendingAliasTip: Equatable {
    let tip: CaptureSigilAliasTip
    let anchor: AliasTipAnchor
    let generation: UInt64
}

/// A forward alias credit that remains undoable in the native editor.
private struct AliasTipHitRecord: Equatable {
    let id: String
    let credit: AliasTipHitCredit
    let preDraft: String
    let postDraft: String
}

/// One-shot arm after Bob rewrites a `\` or `/` alias to `#` or `%`: the very
/// next press of the same key replaces that sigil with one literal key and
/// closes the menu. The UTF-16 caret and sigil range come from Bob's response
/// so the action can judge the live editor instead of the SwiftUI mirror.
struct CaptureHashAliasArm: Equatable {
    /// The alias key Bob replaced (`\` or `/`), taken from Bob's response.
    let key: String
    /// The sigil Bob inserted (`#` or `%`), taken from Bob's response.
    let sigil: String
    let draft: String
    let hashUTF8: Int
    let caretUTF8: Int
    let caretUTF16: Int
    let hashUTF16Range: NSRange
}

/// One-shot probe for a second `=`, `~`, `.`, or `;` typed before Bob
/// answers the first key. It re-asks Bob about `firstDraft` and collapses
/// the pair only when Bob confirms the first key was an alias.
struct CaptureEqualsProbe: Equatable {
    let secondKey: String
    let firstDraft: String
    let firstCaretUTF8: Int
    let secondDraft: String
    let secondCaretUTF8: Int
    let secondTimestamp: TimeInterval
    var firstKey: String = "="
}

/// One-shot record after Bob rewrites a relation `=` flip (`~=` or `~~=`):
/// lets the still-matching completion open in the direction Bob returned,
/// even when a caret-selection analysis beats the edit-triggered request.
struct CaptureRelationFlipAliasOpen: Equatable {
    let draft: String
    let caretUTF8: Int
}

/// One-shot probe for a second alias key that lands before Bob answers the
/// first: re-asks Bob about `firstDraft` and deletes the extra key only when
/// Bob says the first key would have become `#` or `%`.
struct HashAliasProbe: Equatable {
    let key: String
    let firstDraft: String
    let firstCaretUTF8: Int
    let secondDraft: String
    let secondCaretUTF8: Int
}

/// One shared modifier-gesture record: after an `=` opener reply, a `~=` /
/// `~~=` flip, a `toggle_relation_direction` reply triggered by `=`, a picker
/// `=` flip, or a card `=` flip, a fast second key undoes whatever the first
/// key did and types one literal key. Only an opener (`isOpener`) arms the
/// Space/Escape restores.
struct CaptureEqualsGestureArm: Equatable {
    enum Surface: Equatable {
        case editor
        case picker
        case relationLabelCard
    }

    var surface: Surface
    /// Key-down timestamp of the first key, from `NSEvent.timestamp`.
    var firstTimestamp: TimeInterval
    /// Only an opener arms the Space/Escape restores.
    var isOpener: Bool
    /// Draft before the first keystroke (without the trigger byte).
    var preDraft: String
    var preCaretUTF8: Int
    /// Draft after the first key took effect (Bob's reply or the native
    /// picker flip). The fast second key must still see this to fire.
    var postDraft: String
    var postCaretUTF8: Int
    /// Pre-flip picker session for `surface == .picker`.
    var pickerSnapshot: CapturePickerState?
    /// The first key that armed this record (`=`, `.`, or `;`).
    var key: String = "="
    /// Bob's replacement sigil (`~`, `@`, `&`, or `*`).
    var sigil: String = "~"
}

/// What follows a successful Add block ID assignment.
enum CaptureTaskLinkFollowUp: Equatable, Sendable {
    case none
    case start
    case submit
    case submitAndOpen
}

/// Why the Add block ID prompt is open.
enum CaptureTaskIDPromptPurpose: Equatable {
    /// Today's `@route+` flow, byte-for-byte unchanged.
    case parentTask
    /// Card-mode parent-task ID-less row: name the task, then splice Bob's
    /// `parent_replacement` (vault) or the returned ID (scoped). `.start`
    /// never occurs: Shift-Return cannot start a plus-selected task.
    case parentTaskPicker(
        route: String,
        taskRef: String,
        suggestions: [String],
        followUp: CaptureTaskLinkFollowUp,
        returnPicker: CapturePickerState,
        scope: ParentTaskPickerScope
    )
    /// Move-picker ID-less row: name the task via `bob capture-task-id`,
    /// then splice the bare block ID into the picker's replacement range.
    /// Shift-Return chains via the picker's continuation, never via the prompt.
    case projectTaskMove(
        route: String,
        taskRef: String,
        suggestions: [String],
        followUp: CaptureTaskLinkFollowUp,
        returnPicker: CapturePickerState
    )
    /// Link mode for an ID-less `:` row: name the task, then splice its link.
    case taskLink(
        route: String,
        taskRef: String,
        suggestions: [String],
        followUp: CaptureTaskLinkFollowUp,
        returnPicker: CapturePickerState
    )
    /// Dependency mode for an ID-less `&` row: name the task with the exact
    /// vault-relative note path (never the lowercased route), then splice
    /// Bob's `dependency_replacement`. No start-session follow-up exists on
    /// this source: `.none`, `.submit`, and `.submitAndOpen` occur. `allowClosed` permits
    /// Done/Cancelled history rows without reopening them.
    case dependency(
        notePath: String,
        taskRef: String,
        suggestions: [String],
        followUp: CaptureTaskLinkFollowUp,
        returnPicker: CapturePickerState,
        allowClosed: Bool = false
    )
    /// Blocks mode for an ID-less `*` row: name the task with its exact
    /// vault-relative note path, then splice Bob's `blocked_task_replacement`.
    case blockedTask(
        notePath: String,
        taskRef: String,
        suggestions: [String],
        followUp: CaptureTaskLinkFollowUp,
        returnPicker: CapturePickerState
    )
    /// Complete mode for an ID-less `!` row: name the task with the exact
    /// vault-relative note path (never the lowercased route), then splice
    /// Bob's `complete_replacement`. Shift-Return chains via the picker,
    /// never via the prompt.
    case taskComplete(
        notePath: String,
        taskRef: String,
        suggestions: [String],
        followUp: CaptureTaskLinkFollowUp,
        returnPicker: CapturePickerState
    )
    /// Task Wikilink mode for an ID-less `((` row: name the task with the
    /// exact vault-relative note path, then splice Bob's
    /// `wikilink_replacement`. Carries the closed flag so history rows pass
    /// `--allow-closed`, the display-only `link_target`, and the picker
    /// snapshot to restore on Escape.
    case wikilinkTask(
        notePath: String,
        taskRef: String,
        suggestions: [String],
        followUp: CaptureTaskLinkFollowUp,
        returnPicker: CapturePickerState,
        allowClosed: Bool = false,
        linkTarget: String? = nil
    )
    /// Relation mode for an ID-less `~` / `~~` row: name the task, then
    /// splice Bob's `relation_to_replacement` or `relation_from_replacement`.
    case relation(
        notePath: String,
        taskRef: String,
        suggestions: [String],
        followUp: CaptureTaskLinkFollowUp,
        returnPicker: CapturePickerState,
        direction: DependencyPickerDirection
    )
    /// Similar-tasks band mode for an ID-less row: name the task with
    /// `capture-task-id --route`, then splice the matching replacement
    /// (`~`/`@+`/`&`/`*`) into the draft at Bob's anchors. The ID is
    /// written now, before Return, as the pickers already do. Escape
    /// cancels with no write and keeps the similar-tasks focus.
    case similarTask(
        route: String,
        taskRef: String,
        suggestions: [String],
        action: CaptureRelatedAction,
        itemIndex: Int
    )
}

struct CaptureTaskIDPromptState: Equatable {
    let candidate: CaptureCompletionCandidate
    let draftSnapshot: String
    let replacementRange: CaptureRange
    let selectedCompletionIndex: Int?
    var authoredID: String
    var isSaving: Bool
    var errorMessage: String?
    var purpose: CaptureTaskIDPromptPurpose = .parentTask

    /// Suggestions when `purpose` is link mode, else empty.
    var linkSuggestions: [String] {
        if case .taskLink(_, _, let suggestions, _, _) = purpose {
            return suggestions
        }
        if case .dependency(_, _, let suggestions, _, _, _) = purpose {
            return suggestions
        }
        if case .blockedTask(_, _, let suggestions, _, _) = purpose {
            return suggestions
        }
        if case .taskComplete(_, _, let suggestions, _, _) = purpose {
            return suggestions
        }
        if case .wikilinkTask(_, _, let suggestions, _, _, _, _) = purpose {
            return suggestions
        }
        if case .parentTaskPicker(_, _, let suggestions, _, _, _) = purpose {
            return suggestions
        }
        if case .projectTaskMove(_, _, let suggestions, _, _) = purpose {
            return suggestions
        }
        if case .relation(_, _, let suggestions, _, _, _) = purpose {
            return suggestions
        }
        if case .similarTask(_, _, let suggestions, _, _) = purpose {
            return suggestions
        }
        return []
    }

    /// Follow-up when `purpose` is link mode, else nil.
    var linkFollowUp: CaptureTaskLinkFollowUp? {
        if case .taskLink(_, _, _, let followUp, _) = purpose {
            return followUp
        }
        if case .dependency(_, _, _, let followUp, _, _) = purpose {
            return followUp
        }
        if case .blockedTask(_, _, _, let followUp, _) = purpose {
            return followUp
        }
        if case .taskComplete(_, _, _, let followUp, _) = purpose {
            return followUp
        }
        if case .wikilinkTask(_, _, _, let followUp, _, _, _) = purpose {
            return followUp
        }
        if case .parentTaskPicker(_, _, _, let followUp, _, _) = purpose {
            return followUp
        }
        if case .projectTaskMove(_, _, _, let followUp, _) = purpose {
            return followUp
        }
        if case .relation(_, _, _, let followUp, _, _) = purpose {
            return followUp
        }
        return nil
    }
}

struct CapturePomodoroNamePromptState: Equatable {
    let candidate: CaptureCompletionCandidate
    let draftSnapshot: String
    let replacementRange: CaptureRange
    let selectedCompletionIndex: Int?
    var authoredName: String
    var suggestions: [CapturePomodoroTheme]
    var suggestionQuery: String?
    var suggestionsLoading: Bool
    var suggestionsUnavailable: Bool
    /// Present when Bob's themes list included `configured_themes`.
    var configuredThemes: [CaptureConfiguredTheme]?
    var isSaving: Bool
    var errorMessage: String?
}

/// Relation-label card state for `~` / `~~` picks. The token (`~note:id`)
/// already sits in `draftSnapshot` at `tokenRange`; the card authors only
/// the `|label` suffix via Bob's `relation_label` probe.
struct CaptureRelationLabelPromptState: Equatable {
    /// Draft containing the accepted relation token. The rename draft
    /// fix-up rebases this when the apply rewrites matching relations.
    var draftSnapshot: String
    /// UTF-8 byte range of the `~note:id` token (excluding any `|label`).
    var tokenRange: CaptureRange
    /// UTF-8 byte range replaced when committing the `|label` suffix. The
    /// rename draft fix-up rebases this along with the draft text.
    var labelRange: CaptureRange
    /// Relation direction for the live sentence.
    var direction: DependencyPickerDirection
    /// Draft task text (source side for `~`, target side for `~~`).
    let ownerText: String
    /// Picked task text.
    let targetText: String
    /// Caret to restore on cancel. The rename draft fix-up rebases this
    /// when the rewritten draft is shorter than the restore offset.
    var restoreCursor: Int
    /// Picker snapshot to return to on Escape (nil for the `|` flow).
    var returnPicker: CapturePickerState?
    /// Current field text (without `|`, quotes, or escapes).
    var authoredLabel: String
    /// Latest Bob response for the authored label, used only to validate and
    /// commit the typed row (bob-cli-al).
    var suggestions: [CaptureCompletionCandidate]
    /// Existing relation labels returned by the empty-label probe at open.
    /// Filtering and ranking are local so navigation never asks Bob again.
    var catalog: [CaptureCompletionCandidate]
    var catalogLoaded: Bool
    var catalogErrorMessage: String?
    /// Authored label the current `suggestions` were produced for, or nil
    /// when no in-flight or completed fetch covers `authoredLabel`. Every
    /// label edit clears it, so submit can never commit a candidate fetched
    /// for a previous label (bob-cli-al).
    var suggestionAuthoredLabel: String?
    /// Return was pressed before a fresh typed row arrived. Commit once bob
    /// supplies a valid replacement for this exact `authoredLabel`; cancel on
    /// edit, dismissal, a different prompt, a draft change, or a superseding
    /// request (bob-cli-al).
    var pendingSubmit: Bool
    /// Selected catalog label key. It is bob's canonical `key` when the
    /// response carries one, else the locally folded display label.
    var selectedKey: String?
    /// Whether the Hidden section is open (Ctrl+H). The query and the
    /// selection are kept across toggles.
    var showHidden: Bool
    /// A pending "hide on capture" for whatever Return inserts. Typed `|`
    /// turns it on, Backspace on an empty field turns it off, and the card
    /// opens with it on when it opens on a `||` token.
    var oneOff: Bool
    /// Hidden catalog rows, prefetched when `hiddenCount` > 0.
    var hiddenRows: [CaptureRelationLabelInfo]
    /// How many labels are hidden, from the latest probe (`hidden_count`).
    /// An older bob omits it and the card shows no Hidden pill.
    var hiddenCount: Int
    /// Whether any probe has reported `hidden_count`: false means an older
    /// bob, where Ctrl+D and Ctrl+H give the update hint.
    var hiddenCountKnown: Bool
    /// Whether the hidden rows were loaded (or failed) for this card, so
    /// the prefetch runs once per open and once per write.
    var hiddenRowsLoaded: Bool
    /// Ghost keys with their pending hidden state: true is an optimistic
    /// hide, false an optimistic unhide. The row stays as a ghost until the
    /// query changes; Ctrl+D on a ghost flips it back.
    var ghosts: [String: Bool]
    /// Neutral card notice (hints, already-hidden notes). Errors stay red
    /// in `errorMessage`; invalid labels stay red in the capsule.
    var noticeMessage: String?
    /// In-flight hide/unhide write, so a late reply cannot clobber a newer
    /// toggle. A pending write survives card dismissal.
    var visibilityWriteID: UUID?
    /// Ctrl+R rename mode (nil in choose mode). The choose query, selection,
    /// and Hidden section are kept underneath and restored on cancel; a
    /// successful apply selects NEW back in choose mode.
    var rename: CaptureRelationRenameState?
    var isSaving: Bool
    var errorMessage: String?
    /// Latest `relation_cancel` from a catalog, suggestion, or opening
    /// completion. Nil on older Bob and when no cancel labels are configured.
    var relationCancel: CaptureCompletionRelationCancel?
    /// Latest `relation_complete` from a catalog, suggestion, or opening
    /// completion. Nil on older Bob and when no complete labels are
    /// configured.
    var relationComplete: CaptureCompletionRelationComplete?
    /// Latest Bob-authored successor-label consequence or inverse hint.
    /// An inverse hint may have no verdict.
    var relationSuccessor: CaptureCompletionRelationSuccessor?
}

/// Ctrl+R rename mode over one existing relation label. `oldKey` is the
/// catalog key being renamed; `newName` is the rename field text. `preview`
/// is the latest dry run for exactly (`oldKey`, `newName`, `previewMerge`);
/// `refusalCode`/`refusalMessage` carry bob's latest inline refusal (a
/// `label_exists` refusal arms the merge confirm on the next Return when
/// `mergeArmed` is set). `pendingApply` replays a Return pressed before the
/// fresh preview arrived; `isApplying` gates the serial apply lane.
struct CaptureRelationRenameState: Equatable {
    var oldKey: String
    /// Display spelling of OLD, prefilled into the rename field.
    var oldName: String
    var newName: String
    var preview: CaptureRelationRenameResponse?
    /// (`newName`, `merge`) the loaded `preview` was produced for.
    var previewNewName: String?
    var previewMerge: Bool
    var refusalCode: String?
    var refusalMessage: String?
    var mergeArmed: Bool
    var pendingApply: Bool
    var isApplying: Bool
    /// One-shot select-all for the prefilled field, consumed by the view
    /// on the focus claim rename mode raises.
    var selectAllOnFocus: Bool
}

enum CapturePanelFocusTarget: Hashable {
    case editor
    /// Model-level focus intent owned by `BlockIDField` / AppKit, not `@FocusState`.
    case taskIDPromptBlockID
    /// Model-level focus intent owned by `PomodoroNameField` / AppKit, not `@FocusState`.
    case pomodoroNamePromptName
    /// Model-level focus intent owned by the relation-label field / AppKit.
    case relationLabelPromptField
    /// Model-level focus intent owned by `CapturePickerFilterField` / AppKit,
    /// not `@FocusState`.
    case pickerFilter
    case moveChoiceFilter
    case moveChoiceRows
    case pullInFilter
    case pullInOfferList
    case pullInReasonField
    case inboxRouteFilter
    case inboxRouteRows
}

struct CapturePanelFocusRequest: Equatable {
    let sequence: UInt64
    let target: CapturePanelFocusTarget
}

private struct CapturePullInPreviewSnapshot {
    let draft: String
    let clientIdentity: String
    let seed: String
    let generation: UInt64
    let requestID: UUID?
    let pullIn: CapturePullIn?
    let inboxRoute: CaptureInboxRoute?
    let planBudget: CapturePlanBudget?
    let offers: [TaskCompleteUnblocked]
    let stillBlocked: [TaskCompleteStillBlocked]
    let hasOverride: Bool
    var moveChoice: CaptureMoveChoice? = nil
}

private struct CaptureInboxRouteSubmitContext {
    var choice: CaptureInboxRouteChoiceState
    let draft: String
    let clientIdentity: String
    var openAfterCapture: Bool
    let seed: String
    let generation: UInt64
    let requestID: UUID?
    let pullInSelection: CapturePullInSelection?
    let pullInChoiceForBack: CapturePullInChoiceState?
    let pullInCapabilityAdvertised: Bool
    let offerVerdicts: CapturePullInOfferVerdicts?
    let offerCloseCapabilityAdvertised: Bool
    let inboxRouteCapabilityAdvertised: Bool
    let hasOverride: Bool
    let vaultDirectoryIdentity: String
    var moveInSelection: String? = nil
    var moveInCapabilityAdvertised = false
}

private struct CaptureMoveChoiceSubmitContext {
    let preview: CapturePullInPreviewSnapshot
    var openAfterCapture: Bool
    var needsPreview = false
}

private struct PendingExplicitSubmitIntent: Equatable {
    let draft: String
    let processClientIdentity: String
    let analysisGeneration: UInt64
    let openAfterCapture: Bool
}

private struct CaptureRecordAnalysisRequest: Equatable {
    let draft: String
    let generation: UInt64
    let sequence: UInt64
    let processClientIdentity: String
    let cursor: Int?
    let itemIndex: Int?
    let fieldKey: String?
    let nextMissingField: Bool
}

private struct CaptureRecordCompletionSnapshot: Equatable {
    let draft: String
    let generation: UInt64
    let sequence: UInt64
    let processClientIdentity: String
    let cursor: Int
    let itemIndex: Int?
    let recordType: String
    let fieldKey: String?
}

private struct CaptureRecordReturnBlocker {
    let cursor: Int
    let fieldKey: String?
    let fieldLabel: String?
    let message: String?
}

/// Bob's read-only pending merge result, scoped to the exact parse/preview
/// revision that produced it. The next draft or executable cannot inherit it.
struct CaptureMergeInPendingRevision: Equatable {
    let pending: CaptureMergeInPending
    let draft: String
    let generation: UInt64
    let processClientIdentity: String
}

private struct PendingRewriteSubmitIntent: Equatable {
    let inputDraft: String
    let processClientIdentity: String
    let rewriteGeneration: UInt64
    let openAfterCapture: Bool
}

@MainActor
final class CapturePanelModel: ObservableObject {
    private struct PlaceMenuScope: Equatable {
        let context: String?
        let kind: String
        let destination: String
        let fieldStart: Int
    }

    private struct PlaceMenuCandidateKey: Equatable {
        let group: String?
        let title: String
        let kind: String?
    }

    private var placeMenuSelectionWasExplicit = false

    @Published var attributedDraft = AttributedString()
    @Published var editorSelection = AttributedTextSelection()
    @Published var statusText = "" {
        didSet {
            statusIsRefusal = false
        }
    }
    /// True when `statusText` is a Record Card refusal. Any later
    /// `statusText` assignment clears it, so informational status cannot
    /// keep painting the footer red.
    @Published private(set) var statusIsRefusal = false
    @Published var previewState: CapturePreviewState = .idle {
        didSet {
            switch previewState {
            case .ready, .failed:
                releaseAgendaHold(event: .previewSettled)
            case .idle, .loading:
                break
            }
        }
    }
    @Published var parseDiagnostics: [CaptureDiagnostic] = []
    /// Latest applied parse, used to suppress unconfigured-theme flicker
    /// while the caret sits at the end of a prefix of a configured name.
    @Published var latestParse: CaptureParseResponse?
    /// Bob's `configured_themes` from the last themes-list response that
    /// included the field. Empty when no vocabulary is configured.
    var configuredThemes: [CaptureConfiguredTheme] = []
    /// Bob's additive template parse object for the current draft, if any.
    @Published var parsedTemplate: CaptureParseTemplate?
    @Published var completionResponse: CaptureCompletionResponse?
    @Published var selectedCompletionIndex: Int?
    /// Fresh Bob-authored record metadata for the caret's item. The surface
    /// renders this state; only Bob supplies edits and value candidates.
    @Published private(set) var recordPresentation: CaptureRecordPresentation?
    /// True while the visible inline completion list is the File-under
    /// parent picker for a bare-URL reference draft (a synthesized route
    /// list, not a server completion). The view headers it `File under`;
    /// accepting splices ` @<route>` at the end of the draft, and Esc
    /// dismisses it without reopening until the URL changes.
    @Published var fileUnderActive = false
    @Published var targetCacheSnapshot = CaptureTargetsSnapshot(
        targets: nil,
        refreshedAt: nil,
        stale: false,
        errorDescription: nil
    )
    @Published var isSubmitting = false {
        didSet {
            guard oldValue != isSubmitting else { return }
            refreshRecordRouteConcealmentIfNeeded()
        }
    }
    @Published var isPreviewing = false
    /// The pending-list notice (`"Type a task number after ,"`) while a close
    /// draft dangles on `,`/`!`/`~`/`*` or a start draft dangles on `~`/`,`.
    /// Non-nil exactly while the visible card previews the trimmed draft: the
    /// card renders dimmed and the footer action named by `closePendingAction`
    /// is disabled. Nil for every other draft, including a valid list.
    @Published var closePendingText: String?
    /// The footer action the pending card disables: `"Start"` when every
    /// pending scope is a start list, else `"Close"`. Meaningful only while
    /// `closePendingText` is non-nil; reset to `"Close"` with it.
    @Published var closePendingAction = "Close"
    @Published var errorMessage: String?
    /// Machine-readable failure code for the current error callout, when Bob
    /// reported one; nil for errors without a code and when there is no
    /// error. Cleared together with `errorMessage`.
    @Published var errorCode: String?
    /// Shown when `capture-parse` grammar is missing or below 2. Capture
    /// stays disabled and the draft is kept.
    @Published var captureGrammarWarning: String?
    /// Calm capability warning when the draft contains `~` but the latest
    /// parse for this draft lacks `relation_grammar` (an older Bob would
    /// capture the sigil literally). Nil when the draft has no `~` or Bob
    /// understands relations. Rendered as secondary text, never red.
    @Published var relationCapabilityWarning: String?
    @Published var lastSuccess: CaptureCommandSuccess?
    @Published var previewResult: CaptureCommandSuccess?
    @Published var lastSuccessResults: [CaptureCommandSuccess] = []
    @Published var previewResults: [CaptureCommandSuccess] = []
    /// Calm-card state for Bob's `nothing_to_pull_in` refusal.
    @Published var emptyNotePullPresentation: CaptureNotePullEmptyPresentation?
    /// Calm in-progress transfer context returned by Bob's `transfer_pending` payload.
    @Published var transferPendingPresentation: CaptureTransferPendingPresentation?
    /// Designed refusal content for a failed live transfer preview.
    @Published var transferRefusalPresentation: CaptureTransferRefusalPresentation?
    /// Designed refusal content for a failed live merge-in preview, with
    /// explicit rewrite buttons. Return never rewrites; only a button does.
    @Published var mergeInRefusalPresentation: CaptureMergeInRefusalPresentation?
    /// Inline record refusal from Bob's structured failure payload: the
    /// message, missing/invalid field details, and the ready-to-copy
    /// draft. The draft is never applied; the user keeps the original.
    @Published var recordRefusalPresentation: CaptureRecordRefusalPresentation?
    /// Revision-bound Bob context while a `<` source is being completed.
    @Published private(set) var mergeInPendingRevision: CaptureMergeInPendingRevision?
    /// The exact draft string the current preview outputs were computed
    /// for. The move ghost titles render only while this still equals the
    /// current draft; any keystroke hides them until the next preview lands.
    /// Nil when there is no preview.
    @Published var previewOutputsDraft: String?
    @Published var lastSuccessGlobalDestination: CaptureGlobalDestination?
    @Published var previewGlobalDestination: CaptureGlobalDestination?
    /// The latest settled related-task response, shaped for the band renderer.
    /// Pending edits retain these rows until Bob returns for the new draft.
    @Published var similarTasks = SimilarTasksBandState.empty
    /// Latest parse index/mode pairs, used by the band render gate.
    @Published var similarTasksParseItems: [SimilarTasksParseItem] = []
    /// True when every band folds to one line so the auxiliary region
    /// does not scroll. Published from the panel view's metrics pass.
    @Published var similarTasksFolded = false
    /// Strip selection for the focused similar-task row. The default is
    /// preselected on focus; Left/Right moves within bob's offered actions.
    @Published var similarChosenAction: CaptureRelatedAction?
    /// Action chosen while the lane refreshes stale anchors. It waits for the
    /// fresh response, then applies against the fresh anchors.
    private var similarPendingAction: CaptureRelatedAction?
    /// Settled response that arrived while a row was focused. The band stays
    /// frozen, so this waits for unfocus before it paints.
    private var similarPendingResponse: (response: CaptureRelatedResponse, draft: String, itemCount: Int?)?
    /// Item anchors for the latest settled response, keyed by item index.
    /// Rows carry only the match; splices need the item's byte ranges.
    private var similarItemAnchors: [Int: CaptureRelatedItem] = [:]
    /// Draft the anchors above were computed for. Splices re-check this.
    private var similarAnchorsDraft: String?
#if DEBUG
    var similarPendingActionForTesting: CaptureRelatedAction? { similarPendingAction }
    var hasSimilarPendingResponseForTesting: Bool { similarPendingResponse != nil }
#endif
    /// Settled `bob gmail peek` messages keyed by Gmail URL. The item
    /// preview shows the peek line in place of the dry-run offline line
    /// while `gmailPeekDraft` still equals the current draft; any keystroke
    /// re-arms the settle and the offline lines show until the fresh peek
    /// lands. A URL with no entry keeps its offline line (peek failed or
    /// is still settling).
    @Published var gmailPeekMessages: [String: String] = [:]
    /// Draft the peek messages above were computed for. Nil when no peek
    /// has settled for the current draft.
    @Published var gmailPeekDraft: String?
    /// Latest live-preview open plan, built from bob's `open_notes` or the
    /// legacy fallback. Nil means this draft has no preview yet.
    @Published var previewOpenPlan: CaptureOpenPlan?
    /// True after Control has been held alone for the reveal delay.
    @Published var openHintRevealed = false
    var openHintRevealDelayNanoseconds: UInt64 = 400_000_000
    private var openHintRevealTask: Task<Void, Never>?
    // Incremented on every successful capture so the view can drive a VoiceOver
    // announcement without needing `CaptureCommandSuccess` to be diffed for equality.
    @Published var successAnnouncementTick = 0
    @Published var statusAnnouncementTick = 0
    @Published var transferVerbAnnouncementTick = 0
    @Published var transferVerbAnnouncement: String?
    @Published var mergeInAnnouncementTick = 0
    @Published var mergeInAnnouncement: String?
    /// Remembers the last previewed transfer verb across the preview caches
    /// that `clearPreviewOutputs()` resets, so a move → merge flip for the
    /// same draft announces once. Set whenever a preview assigns a
    /// single-transfer result; untouched through transfer pending and
    /// refusal states; nil once the draft stops being a transfer.
    private var lastPreviewTransferVerb: CaptureTransferPresentation.Verb?
    private var lastPreviewMergeInKey: String?
    /// The footer text `showTransferFailure` last wrote (pending title,
    /// older-bob diagnostic, or refusal title). A later successful preview
    /// or non-transfer parse resets the footer to Ready only while it still
    /// shows this text, never clobbering unrelated notices.
    private var transferOwnedStatusText: String?
    @Published var isStashPickerPresented = false
    @Published var selectedStashIndex = 0
    @Published var isTemplateShelfPresented = false
    @Published var selectedTemplateIndex = 0
    @Published var armedDeleteTemplateID: String?
    @Published var templateOrigin: String? {
        didSet {
            guard oldValue != templateOrigin else {
                return
            }
            clampTemplateSelection(templates: templateEntries)
        }
    }
    @Published private(set) var isSavingTemplate = false
    @Published var taskIDPrompt: CaptureTaskIDPromptState?
    @Published var pomodoroNamePrompt: CapturePomodoroNamePromptState?
  @Published private(set) var temporarilyHiddenThemeKey: String?
  @Published private(set) var isWritingThemeVisibility = false
    @Published var relationLabelPrompt: CaptureRelationLabelPromptState?
    @Published var moveChoice: CaptureMoveChoiceState?
    @Published var moveChoiceMessage: String?
    @Published var moveChoiceCapabilityWarning: String?
    private var moveChoiceAcknowledgedDraft: String?
    private var moveChoiceContext: CaptureMoveChoiceSubmitContext?
    private var rememberedMoveChoice: CaptureMoveChoiceState?
    @Published var pullInChoice: CapturePullInChoiceState?
    @Published var inboxRouteChoice: CaptureInboxRouteChoiceState?
    @Published var picker: CapturePickerState?
    /// Recomputed only when the picker snapshot or the filter text changes.
    @Published var pickerPresentation: CapturePickerPresentation?
    @Published var pickerChip: CapturePickerChipState?
    @Published private(set) var focusRequest = CapturePanelFocusRequest(sequence: 0, target: .editor)
    @Published private(set) var editorInputLocked = false {
        didSet {
            guard oldValue != editorInputLocked else { return }
            refreshRecordRouteConcealmentIfNeeded()
        }
    }
    /// True while Control-G is waiting for its one follow-up key.
    @Published private(set) var editorLeaderPending = false
    /// One-shot arm after `\` opens Go To: the very next `\` on a bare `/`
    /// draft types a literal `\` instead. Cleared on consume or dismissal.
    @Published private(set) var backslashLiteralArmed = false
    /// One-shot arm after Bob rewrites `\` or `/` to a sigil: the very next
    /// same key replaces that sigil with one literal key and closes the menu.
    /// Cleared on consume or dismissal.
    var hashAliasLiteralArm: CaptureHashAliasArm?
    /// One-shot allowance for the `=` → `~~` Linked From alias.
    var relationFlipAliasOpen: CaptureRelationFlipAliasOpen?
    /// One shared equals-gesture record after an `=` opener reply, a `~=`
    /// flip, a `toggle_relation_direction` reply triggered by `=`, a picker
    /// `=` flip, or a card `=` flip. A fast second `=` undoes the first and
    /// types one literal `=`.
    var equalsGestureArm: CaptureEqualsGestureArm?
    /// First `=`, `.`, or `;` keystroke awaiting Bob's reply: key, draft,
    /// caret, and key-down timestamp from `noteSeparatorToggleIntent`.
    /// Feeds the before-reply double-key probe; cleared when the reply lands.
    var pendingEqualsFirstKey: (
        key: String, draft: String, caretUTF8: Int, timestamp: TimeInterval
    )?
    /// A pending dot/semicolon alias rewrite whose fast escape/restore
    /// eligibility was interrupted before Bob replied. Keep its identity long
    /// enough to apply Bob's ordinary rewrite without arming stale state.
    var interruptedModifierAliasReply: (draft: String, timestamp: TimeInterval)?
    /// One-shot probe for a second `=`/`~`/`.` typed before Bob answers the
    /// first key. Re-asks Bob about `firstDraft`; see `CaptureEqualsProbe`.
    var equalsProbe: CaptureEqualsProbe?
    static let editorLeaderStatusHint = "⌃G · U toggle line case · esc cancel"
    /// Visible-frame height of the screen hosting the panel. `nil` until the controller
    /// observes a screen; the editor height budget then falls back to
    /// `CapturePanelLayout.panelMaximumContentHeight`.
    @Published var availableScreenHeight: CGFloat?
    /// Top safe-area inset imposed by the full-size-content panel's titlebar strip.
    /// Published by the controller from the hosting view's `safeAreaInsets.top`
    /// (equivalently, the part of the content rect above `contentLayoutRect`); 0
    /// until the controller observes a panel. Counted in the content-height policy
    /// so measured heights describe the whole content view.
    @Published var titlebarSafeAreaInset: CGFloat = 0

    var processClient: BobProcessClient? {
        didSet {
            guard oldValue !== processClient else {
                startCloseAliasProbeIfNeeded()
                return
            }
            // A replacement can have the same executable identity while the
            // previous client's probe is still pending. Retire that task first.
            closeAliasProbeTask?.cancel()
            closeAliasProbeTask = nil
            closeAliasProbeInFlightIdentity = nil
            retireAliasTipDisplayEligibility()
            cancelAliasTipLane()
            invalidateRecordInteraction(clearPresentation: true)
            invalidateRewrite()
            invalidateAnalysis()
            stopClipboardPolling()
            lastAppliedParseDraft = nil
            lastAppliedParseGeneration = nil
            lastAppliedParseGrammar = nil
            lastAppliedParseClientIdentity = nil
            captureGrammarWarning = nil
            cancelSimilarTasks(clear: true)
            previewPullInSnapshot = nil
            resetMoveChoice()
            inboxRouteChoice = nil
            inboxRouteChoiceContext = nil
            activeInboxRouteSubmitContext = nil
            clearPreviewOutputs()
            previewState = .idle
            if isPreviewing {
                activeRequestID = nil
                isPreviewing = false
            }
            if pullInChoice != nil {
                cancelPullInChoiceFromKeyboard()
            }
            clearEditorInputLockIfFree()
            savedTemplateShelf.processClient = processClient
            savedTemplateShelf.refresh(reason: .recheck)
            if processClient != nil {
                startCloseAliasProbeIfNeeded()
            }
            processClientDidReplace?()
        }
    }
    var notificationService: NotificationService?
    /// Optional notification seams for model tests; production leaves these
    /// nil and posts through `notificationService`.
    var captureSuccessNotifier: ((
        [CaptureCommandSuccess],
        CaptureGlobalDestination?,
        CaptureOpenPlan
    ) -> Void)?
    var captureOpenFailureNotifier: ((String) -> Void)?
    /// Capture note dispatch. Production opens bob's single
    /// `obsidian://bob-open-notes` URL through an activating workspace call
    /// and reports success on the main actor. Tests inject a closure.
    var noteOpener: (
        URL,
        @escaping @MainActor (Error?) -> Void
    ) -> Void = { url, completion in
        CapturePanelModel.openObsidianURL(url, completion: completion)
    }
    /// Read-only Go To dispatch. Production opens `obsidian://bob-goto-task`
    /// through `NSWorkspace` with `activates = true` and reports success on
    /// the main actor. Tests inject a closure.
    var taskGotoOpener: (
        URL,
        @escaping @MainActor (Bool) -> Void
    ) -> Void = { url, completion in
        CapturePanelModel.openObsidianURL(url) { error in
            completion(error == nil)
        }
    }
    var panelDismisser: () -> Void = {}
    /// Narrow controller bridge: apply Bob's separator-toggle replacement
    /// through the focused `NSTextView` so Undo stays native. Nil in tests
    /// that do not wire a text view; those results are left as typed.
    var applyNativeRewriteEdit: ((CaptureNativeRewriteEdit) -> Bool)?
    /// The controller holds later key-downs only while a meaning-changing
    /// rewrite is outstanding. A false start result means the current focus
    /// is not the main draft editor, so the rewrite keeps its legacy behavior.
    var meaningChangingRewriteHoldDidStart: ((UInt64) -> Bool)?
    /// `didReceiveReply` distinguishes a Bob verdict from a cancelled or
    /// failed request; only a verdict may replay a buffered submit.
    var meaningChangingRewriteHoldDidEnd: ((UInt64, Bool) -> Void)?
    /// Fired after an actual client replacement (`!==`), never a same-object
    /// Recheck. The controller uses this to retire a replay tail after the
    /// rewrite hold has already ended.
    var processClientDidReplace: (() -> Void)?
    /// Narrow controller bridge: insert a saved template through the
    /// focused `NSTextView` so Undo stays native. Nil in tests that do
    /// not wire a text view; those apply `setPlainDraft` as a fallback.
    var applyTemplateInsert: ((CaptureTemplateInsertEdit) -> Bool)?
    let canceledDraftStash: CanceledDraftStash
    let savedTemplateShelf: SavedTemplateShelf

    private let debounceNanoseconds: UInt64
    private let similarTasksSettleNanoseconds: UInt64
    private let gmailPeekSettleNanoseconds: UInt64
    private var analysisTask: Task<Void, Never>?
    private var pendingExplicitSubmitIntent: PendingExplicitSubmitIntent?
    private var pendingExplicitSubmitTask: Task<Void, Never>?
    private var livePreviewTask: Task<Void, Never>?
    private var livePreviewGeneration: UInt64 = 0
    /// Cancellable five-minute boundary refresh for a visible past preview.
    /// While the panel shows a valid current past preview, one dry-run
    /// request fires at the next wall-clock boundary and re-arms. Local clock
    /// math only decides when to ask Bob again; windows come from Bob.
    private var pastRefreshTask: Task<Void, Never>?
    /// Injectable clock/scheduling seam for deterministic hosted tests.
    var pastNow: () -> Date = { Date() }
    var pastSleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    private var similarTasksTask: Task<Void, Never>?
    private var gmailPeekTask: Task<Void, Never>?
    private var rewriteTask: Task<Void, Never>?
    private var aliasTipTask: Task<Void, Never>?
    private var aliasTipGeneration: UInt64 = 0
    private var pendingTypedSigilIntent: TypedSigilIntent?
    private var pendingAliasTip: PendingAliasTip?
    private var aliasTipRequest: AliasTipRequest?
    private var aliasTipSession = AliasTipSession()
    private var aliasTipIncapableIdentity: String?
    private var aliasTipHitRecords: [AliasTipHitRecord] = []
    private var pendingRewriteSubmitIntent: PendingRewriteSubmitIntent?
    private var deferredRewriteInputDraft: String?
    private var completedDeferredRewriteDraft: String?
    /// Exact native-editor echo for an accepted meaning-changing rewrite. It lets
    /// editor echoes preserve a Return intent while later edits still cancel it.
    private var deferredRewriteEchoDraft: String?
    private var deferredRewriteEchoCursorUTF8: Int?
    private var stashCancellable: AnyCancellable?
    private var templateShelfCancellable: AnyCancellable?
    private var rememberedSelectedTemplateID: String?
    private var lastAppliedParseDraft: String?
    private var lastAppliedParseItemCount: Int?
    /// Latest parse's `grammar` for `lastAppliedParseDraft`. Nil until a
    /// parse lands or when that parse omitted the field.
    private var lastAppliedParseGrammar: Int?
    /// Analysis generation whose parse produced the current capability
    /// evidence. A same-draft refresh invalidates the previous parse until
    /// its own response lands.
    private var lastAppliedParseGeneration: UInt64?
    /// Process-client identity that produced `lastAppliedParseDraft`. A
    /// Recheck Bob / client replacement clears it so a stale parse cannot
    /// authorize capture.
    private var lastAppliedParseClientIdentity: String?
    /// Latest parse's `relation_grammar` for `lastAppliedParseDraft` (nil
    /// when the Bob predates relations or no parse has landed yet).
    private var lastRelationGrammar: Int?
    /// Draft the capability warning was already shown for (first ⌘↩). A
    /// second ⌘↩ on the same draft submits. Cleared when the draft changes.
    private var relationCapabilityAcknowledgedDraft: String?
    /// Close-outcome alias probe verdicts, cached by process-client identity.
    /// Supported only when `captureRewrite("xx", cursor: 2)` answers changed
    /// with text `x!`. Until a supported verdict arrives, `x`/`s` stay literal.
    static let closeAliasProbeDraft = "xx"
    static let closeAliasProbeCursor = 2
    static let closeAliasOldBobMessage = "This bob predates x/s close aliases · update bob"
    private var closeAliasSupportedIdentities: Set<String> = []
    private var closeAliasUnsupportedIdentities: Set<String> = []
    private var closeAliasAnnouncedIdentities: Set<String> = []
    private var closeAliasProbeTask: Task<Void, Never>?
    private var closeAliasProbeInFlightIdentity: String?
    private var analysisGeneration: UInt64 = 0
    private var recordRequestSequence: UInt64 = 0
    private var recordAnalysisRequest: CaptureRecordAnalysisRequest?
    private var recordCompletionSnapshot: CaptureRecordCompletionSnapshot?
    private var recordFocusState: CaptureRecordFocusState?
    private var recordAssistVersion: Int?
    private var recordCardDismissedDraft: String?
    private var recordInteractionPending = false
    private var recordReturnTask: Task<Void, Never>?
    /// Pasteboard-counter poll refreshes `%c` previews while the panel is
    /// key and the current compatible parse reports a clip directive. The
    /// counter reads no content; a change re-runs the debounced preview.
    /// Nil unless polling is armed. Stopped on hide, focus loss, draft
    /// removal, evidence lapse, and analysis reset.
    private var clipboardPollTask: Task<Void, Never>?
    private var lastSeenClipboardChangeCount: Int?
    /// True while the panel holds key focus. The controller reports
    /// become-key/resign-key; defaults true because the panel is created to
    /// take key on show, and `panelVisible` gates polling regardless.
    private var panelIsKey = true
    /// Pasteboard-counter source. Production reads
    /// `NSPasteboard.general.changeCount`; tests inject a counter.
    var clipboardChangeCounter: () -> Int = { NSPasteboard.general.changeCount }
    /// Maximum pasteboard poll rate: the ticker sleeps this long between
    /// counter reads, so observation stays at or under 1 Hz.
    static let clipboardPollIntervalNanoseconds: UInt64 = 1_000_000_000
    private var similarTasksGeneration: UInt64 = 0
    /// Settled-peek generation for `bob gmail peek`: typing or a client
    /// replacement bumps it so a stale peek can never overwrite the
    /// current draft's lines.
    private var gmailPeekGeneration: UInt64 = 0
    /// Candidate provenance and request ordering for the active Go To session.
    /// Core keeps requested scope separate from the scope of the displayed rows.
    private var gotoClosedTasksState: CaptureTaskGotoScopeState?
    private var relationLabelSuggestionGeneration: UInt64 = 0
    /// In-flight `relation_label` probe. Submit must not start a second
    /// request for the same prompt/draft/authored label: bumping generation
    /// would drop the response the pending Return is waiting for.
    private var relationLabelInFlight: (generation: UInt64, draft: String, authored: String)?
    private var relationLabelCatalogGeneration: UInt64 = 0
    private var relationLabelCatalogInFlight: (generation: UInt64, draft: String)?
    /// Rename dry-run preview generations: typing or arming bumps the
    /// generation so a stale preview can never overwrite the current one.
    /// The debounce sleep is a timed wait, never an untimed continuation.
    private var relationLabelRenameGeneration: UInt64 = 0
    private var relationLabelRenameInFlight: (generation: UInt64, draft: String, oldKey: String, newName: String, merge: Bool)?
    private var rewriteGeneration: UInt64 = 0
    private var meaningChangingRewriteHoldGeneration: UInt64?
    private var rewriteExpectedCursorUTF8: Int?
    private var rewriteSawMatchingSelection = false
    private var pendingSeparatorToggleIntent: SeparatorToggleIntent?
    /// A `\` sent to the rewrite lane whose reply has not landed: the
    /// expected post-key draft and caret from key-down time. Lets a second
    /// `\` before Bob's reply re-ask Bob about the first `\`.
    var pendingHashAlias: (key: String, draft: String, caretUTF8: Int)?
    /// One-shot fast double-tap probe; see `HashAliasProbe`.
    var hashAliasProbe: HashAliasProbe?
    private var isApplyingProgrammaticDraft = false
    // SwiftUI can deliver the text-change callback after a programmatic binding update.
    // Remember the accepted value so that callback cannot start completion analysis again.
    private var suppressedCompletionAcceptanceDraft: String?
    // The draft that produced the visible `completionResponse`, so a `+` commit can
    // locate the route text by byte range instead of trusting the view-supplied caret.
    private var completionDraftSnapshot: String?
    /// The draft the last completion step settled on; the Block ID and Active
    /// Task pickers auto-open only when the edits since this draft wrote the
    /// separator or trigger before Bob's replacement part.
    private var editAnalysisBaseline = ""
#if DEBUG
    var analysisBaselineForTesting: String { editAnalysisBaseline }
#endif
    /// Every capture-rewrite launch sets `rewriteTask` synchronously, so a
    /// test can read this right after an edit to learn whether the key went
    /// to Bob's rewrite lane, and wait on it for Bob's reply.
    var rewriteInFlightForTesting: Bool { rewriteTask != nil }
    /// True while the non-blocking alias-tip rewrite is in flight.
    var aliasTipInFlightForTesting: Bool { aliasTipTask != nil }
    var aliasTipGenerationForTesting: UInt64 { aliasTipGeneration }
    var pendingAliasTipForTesting: CaptureSigilAliasTip? { pendingAliasTip?.tip }
    var aliasTipSessionForTesting: AliasTipSession { aliasTipSession }
    var completionDraftSnapshotForTesting: String? { completionDraftSnapshot }
    /// The trimmed bare-URL draft Esc dismissed the File-under list for.
    /// The list does not reopen for this URL until the draft changes to a
    /// different URL. Cleared on accept and on successful submit.
    private var fileUnderDismissedURL: String?
    private var programmaticSelectionOffsetToIgnore: Int?
    private var priorityRollSeed: String?
    private var previewPullInSnapshot: CapturePullInPreviewSnapshot?
    private var inboxRouteChoiceContext: CaptureInboxRouteSubmitContext?
    private var activeInboxRouteSubmitContext: CaptureInboxRouteSubmitContext?
    private var overrideRefusalDraft: String?
    private var focusSequence: UInt64 = 0
    /// Display text of accepted `&` / `*` picker replacements, used for the
    /// calm `dependency_target` hint. Cleared when the draft resets.
    private var relationshipDisplayNames: [String: String] = [:]

    // Shared by submit and preview so a late callback from either one can never mutate
    // state on behalf of a request that is no longer the active one.
    private var activeRequestID: UUID?
    private var activeTaskIDRequestID: UUID?
    private var activePomodoroNameRequestID: UUID?
  private var activePomodoroThemeSuggestionRequestID: UUID?
  private var activeThemeVisibilityRequestID: UUID?
  private var pomodoroThemeSuggestionsTask: Task<Void, Never>?
  private var hiddenThemeDraftSnapshot: String?
    /// Local fuzzy index for the picker's snapshot. Kept private; the view only
    /// sees the derived `pickerPresentation`.
    private var pickerIndex: CapturePickerIndex?
    /// True while a Go To `NSWorkspace` open is in flight. Picker keys are
    /// swallowed until the opener reports, so a double Return cannot dispatch
    /// twice.
    private(set) var taskGotoDispatchInFlight = false
    /// True while Command-\ is fetching today's Pomodoros or dispatching
    /// the goto URL. A second press is a no-op until it clears.
    private(set) var todayPomodoroGotoInFlight = false
    private var todayPomodoroGotoGeneration: UInt64 = 0
    private var todayPomodoroGotoTask: Task<Void, Never>?
    /// Latest parse reported the `task_goto` need. Ctrl-C uses this so a `/`
    /// draft is discarded even when the picker has already chipped.
    private var lastAnalysisNeedsTaskGoto = false
    /// Replacement-range start of a `^` or block-ID token auto-open is
    /// suppressed for (set by the two-stage Escape cancel). Cleared when an
    /// `.edit` analysis leaves the token.
    private var pickerAutoOpenSuppressedStart: Int?
    /// Draft-global UTF-8 byte range of the marker token the open picker
    /// edits (`marker_range` for block-ID sources, `[r.start - 1, r.end)` for
    /// `^`). While set, the dimmed editor washes that token in accent so the
    /// multi-item draft shows which marker is being completed. Cleared with
    /// its wash on every close path; the wash never touches `plainDraft`,
    /// the selection, undo, or `editorTextDidChange`.
    var pickerMarkerHighlight: CaptureRange?
    /// The validated spans of the latest highlight paint, so closing a picker
    /// over a sealed project-note marker can put its manila wash back after the
    /// picker's accent wash comes off.
    private var paintedSpanRanges: (draft: String, ranges: [ValidatedCaptureSpan])?

    /// Numbered Task Link count of the running Pomodoro, derived from
    /// the agenda store's snapshot (or its plain-lane fallback on an old
    /// bob). It gates `x` and link close lists.
    private(set) var currentPomodoroTaskLinkCount: Int?

    /// Largest numbered Task Link lineup among today's open entries.
    /// It gates `x=` close lists and stays nil when an older bob omits it.
    private(set) var maxTaskLinkCount: Int?

    /// The agenda store that owns these gates. The model subscribes to its
    /// count and bound publishers; the store refreshes on launch, show, submit, and
    /// filtered vault events instead of the old per-show spawn.
    var agendaStore: CaptureAgendaStore? {
        didSet {
            subscribeToAgendaStore()
        }
    }

    private var agendaCancellable: AnyCancellable?
    private var agendaMaxTaskLinkCountCancellable: AnyCancellable?

    // MARK: - Idle agenda view state

    /// The Settings toggle, observed live from AppDelegate. While off,
    /// the store keeps refreshing for the close-list bounds, but
    /// nothing is measured, planned, or shown.
    @Published var agendaEnabled = true {
        didSet {
            guard agendaEnabled != oldValue else {
                return
            }
            refreshAgendaPlan()
        }
    }

    /// Live Settings control for the related-task lane. Turning it off
    /// cancels outstanding work and removes the band state immediately.
    @Published var similarTasksEnabled = true {
        didSet {
            guard similarTasksEnabled != oldValue else { return }
            if similarTasksEnabled {
                scheduleSimilarTasks(draft: plainDraft)
            } else {
                cancelSimilarTasks(clear: true)
            }
        }
    }

    /// Live Settings control for typing tips. Off records no intents, spawns
    /// no alias-tip lane, and shows no tips. Hits still count.
    @Published var typingTipsEnabled = true {
        didSet {
            guard typingTipsEnabled != oldValue else { return }
            if !typingTipsEnabled {
                cancelAliasTipLane()
                dropPendingAliasTip(reason: .closed)
                presentedAliasTip = nil
                pendingTypedSigilIntent = nil
            }
        }
    }

    /// Pinned completion-list tip. Nil while the list is closed.
    @Published private(set) var presentedAliasTip: CaptureSigilAliasTip? {
        didSet {
            if presentedAliasTip == nil {
                presentedAliasTipAnchor = nil
            }
        }
    }
    private var presentedAliasTipAnchor: AliasTipAnchor?

    /// Test-injectable ledger. Production uses the standard defaults store.
    var aliasTipLedgerStore = AliasTipLedgerStore()

    /// Alias-tip rewrite timeout. Production is 500 ms; tests can lengthen it.
    var aliasTipTimeout: TimeInterval = 0.5

    /// Fire-time gate for the settled related lane. True only while the
    /// panel is visible, the setting is on, and no picker, prompt, choice,
    /// stash picker, or template shelf owns the panel.
    var similarTasksMayRequest: Bool {
        panelVisible && similarTasksEnabled && !pickerVisible && !taskIDPromptVisible
            && !pomodoroNamePromptVisible && !relationLabelPromptVisible && !pullInChoiceVisible
            && !inboxRouteChoiceVisible
            && !isStashPickerPresented && !isTemplateShelfPresented
    }

    /// Clears only the pending mark while keeping the held rows, for a
    /// fire-time gate refusal. The next draft edit re-arms the settle.
    private func clearSimilarTasksPendingKeepingRows() {
        similarTasks = SimilarTasksBandState(
            draft: similarTasks.draft,
            items: similarTasks.items,
            pending: false,
            focusedRowID: similarTasks.focusedRowID,
            parseItemCount: similarTasks.parseItemCount,
            revealed: similarTasks.revealed
        )
        similarTasksTask = nil
    }

    /// The latest planned agenda, or nil when there is no snapshot or
    /// state line to show.
    @Published var agendaPresentation: CaptureAgendaPresentation?
    @Published var agendaPlan: CaptureAgendaPlan?

    /// Below-eye-line budget for the agenda, published by the panel
    /// controller. Planning is arithmetic on cached heights, so a
    /// screen change re-plans without re-measuring.
    @Published var agendaBudget: Double = 533 {
        didSet {
            guard agendaBudget != oldValue else {
                return
            }
            refreshAgendaPlan()
        }
    }

    /// Agenda content width, reported by the agenda pane. A width
    /// change re-measures what is missing, then re-plans.
    @Published var agendaContentWidth: CGFloat = 724 {
        didSet {
            guard agendaContentWidth != oldValue else {
                return
            }
            refreshAgendaPlan()
        }
    }

    /// Manually expanded fold units, pinned at full by the planner.
    /// Reset on hide and when the snapshot changes.
    @Published var agendaExpanded: Set<CaptureAgendaUnitID> = []

    /// First-keystroke dim-hold (plan §7): true from the first non-blank
    /// keystroke while the agenda shows until the preview settles, the
    /// region is taken, 250 ms elapse, or the draft returns to blank.
    /// The view dims the agenda to 35% while this holds.
    @Published private(set) var agendaDimmed = false

    private var agendaHold: CaptureAgendaHold.State = .idle
    private var agendaHoldTask: Task<Void, Never>?
    private var agendaHoldGeneration: UInt64 = 0
    /// The pending `.eventBoundary` refresh sleep. Re-armed on every
    /// agenda plan; cancelled by the next arm.
    private var agendaBoundaryTask: Task<Void, Never>?

    /// Opens a calendar join URL from a band join button. Only http(s)
    /// URLs open; anything else announces instead of failing silently.
    func joinCalendarEvent(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            announceStatus("That join link is not a web URL")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Command-J in an empty draft: opens the focus event's join URL.
    /// Opening a URL writes nothing, so the idle agenda stays
    /// read-only.
    func joinFocusCalendarEvent() {
        guard !hasDraft else {
            return
        }
        guard let raw = agendaPresentation?.calendar?.focusJoinURL,
            let url = URL(string: raw),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http"
        else {
            announceStatus("No join link for the focus event")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Measured footer height, reported by the panel view. The
    /// controller derives the compact panel's top from it.
    @Published var footerHeight: CGFloat = 0

    /// Fires when a new plan publishes, so the controller can settle
    /// the layout while the panel is hidden.
    var agendaPlanDidChange: (() -> Void)?

    private let agendaMeasurer = CaptureAgendaRowMeasurer()
    private var agendaSnapshotCancellable: AnyCancellable?
    private var agendaDayChangeCancellable: AnyCancellable?

    /// Whether the panel itself is ordered front. The countdown
    /// ticker mounts only while this is true, so a hidden panel never
    /// re-plans every minute.
    @Published private(set) var panelVisible = false {
        didSet {
            if oldValue && !panelVisible {
                resetCalendarBoundaryRefresh()
            }
        }
    }

    /// Whether the agenda paints: the setting is on, the draft is
    /// blank, nothing else owns the auxiliary region, no live preview
    /// is showing, and a plan is ready. While the dim-hold is active
    /// the agenda stays mounted (dimmed) even with a non-blank draft,
    /// so the region swaps with one height change when the hold ends.
    var agendaVisible: Bool {
        if agendaHold == .holding {
            let previewPending = previewState == .idle || previewState == .loading
            return agendaEnabled && !auxiliaryOwnedByOther && previewPending
                && agendaPlan != nil
        }
        return CaptureAgendaVisibility.isVisible(
            settingOn: agendaEnabled,
            draftBlank: !hasDraft,
            regionFree: !auxiliaryOwnedByOther,
            previewIdle: previewState == .idle,
            hasPlan: agendaPlan != nil
        )
    }

    /// True while a current entry carries an end time: the view mounts
    /// its minute-granularity countdown only then.
    var agendaHasLiveCountdown: Bool {
        agendaPresentation?.hasLiveCountdown == true
    }

    /// True while the Calendar band shows a running or upcoming event:
    /// the view ticks every minute for the band's countdowns even with
    /// no running Pomodoro.
    var agendaHasCalendarTick: Bool {
        agendaPresentation?.calendarNeedsTick == true
    }

    private var auxiliaryOwnedByOther: Bool {
        isStashPickerPresented || isTemplateShelfPresented || inlinePromptVisible || pickerVisible
            || pickerChipVisible || completionVisible
            || destinationSummary != nil || errorMessage != nil
            || taskIDPromptVisible || pomodoroNamePromptVisible
    }

    /// Expands one fold unit in place and returns focus to the editor,
    /// so keyboard focus never leaves the editor in v1.
    func expandAgendaUnit(_ unit: CaptureAgendaUnitID) {
        agendaExpanded.insert(unit)
        requestFocus(.editor)
        refreshAgendaPlan()
    }

    /// Starts the dim-hold when the draft turns non-blank while the
    /// agenda shows. Called from the non-blank path of
    /// `editorTextDidChange`, where the pre-keystroke visibility is
    /// exactly setting-on, plan-ready, region-free, and preview-idle.
    func noteAgendaFirstKeystroke() {
        let wasShowing = agendaEnabled && agendaPlan != nil
            && !auxiliaryOwnedByOther && previewState == .idle
        guard wasShowing else {
            return
        }
        let advanced = CaptureAgendaHold.next(
            state: agendaHold,
            event: .draftBecameNonBlank
        )
        guard advanced == .holding, agendaHold != .holding else {
            return
        }
        agendaHold = .holding
        agendaDimmed = true
        agendaHoldGeneration &+= 1
        let generation = agendaHoldGeneration
        agendaHoldTask?.cancel()
        agendaHoldTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: CaptureAgendaHold.timeoutNanoseconds
            )
            await MainActor.run {
                self?.expireAgendaHold(generation: generation)
            }
        }
    }

    /// Cancels the hold when the draft returns to blank. The cached
    /// plan repaints immediately and one background revalidation
    /// always follows, per plan §7.
    func noteAgendaDraftCleared() {
        releaseAgendaHold(event: .draftReturnedToBlank)
        agendaStore?.refresh(reason: .show)
    }

    /// Releases the hold when the agenda stops showing because the
    /// preview settled or another owner took the auxiliary region. The
    /// view calls this from its `agendaVisible` transition; the live
    /// preview's settled height resets structurally there, because the
    /// preview pane remounts fresh at the 92 pt floor.
    func noteAgendaStoppedShowing() {
        if previewState == .idle {
            releaseAgendaHold(event: .regionTaken)
        } else {
            releaseAgendaHold(event: .previewSettled)
        }
    }

    private func expireAgendaHold(generation: UInt64) {
        guard generation == agendaHoldGeneration else {
            return
        }
        releaseAgendaHold(event: .timeoutElapsed)
    }

    private func releaseAgendaHold(event: CaptureAgendaHold.Event) {
        let advanced = CaptureAgendaHold.next(state: agendaHold, event: event)
        guard advanced == .idle, agendaHold != .idle else {
            return
        }
        agendaHold = .idle
        agendaDimmed = false
        agendaHoldGeneration &+= 1
        agendaHoldTask?.cancel()
        agendaHoldTask = nil
        CaptureSignpost.event(CaptureSignpost.agendaHoldReleased)
    }

    /// Test-only release covering every hold-release path without a
    /// draft or a timer.
    func releaseAgendaHoldForTests(event: CaptureAgendaHold.Event) {
        releaseAgendaHold(event: event)
    }

    /// The day the current plan is built for. An explicit `today`
    /// pins it; internal re-plans (expansion, width or budget change)
    /// reuse it, so an expansion never re-plans for a different day
    /// than the visible plan. A new snapshot clears it, so a
    /// day-rollover fetch plans against the new day.
    private var agendaPlanningDay: String?

    /// The store values the current plan is built from. The store's
    /// `@Published` properties emit in `willSet`, so planning must
    /// read these cached emissions, never the store directly: the
    /// subscription below refreshes them before re-planning, and
    /// every re-plan (budget, width, expansion, countdown) reuses
    /// them.
    private var agendaSourceSnapshot: CaptureAgendaSnapshot?
    private var agendaSourceStatus: CaptureAgendaStoreStatus = .idle
    private var agendaLastFiredBoundary: Date?

    /// Measures what is missing, plans, and publishes. Runs on store
    /// publish, width change, screen change (via the budget), and
    /// expansion. Planning iterates to a fixpoint: a freshly folded
    /// plan can surface new row variants (chips, strips) that need
    /// measuring before the final plan.
    func refreshAgendaPlan(today: String? = nil) {
        // A published snapshot carries its own date, which is today on
        // the store's clock: plan against it, not the pinned day, so a
        // store pinned to another date (tests) still paints content.
        let day =
            today ?? agendaSourceSnapshot?.date ?? agendaPlanningDay
            ?? CaptureAgendaStore.localToday()
        if let agendaPlanningDay, agendaPlanningDay != day {
            resetCalendarBoundaryRefresh()
        }
        agendaPlanningDay = day
        guard agendaEnabled, agendaStore != nil else {
            agendaPresentation = nil
            agendaPlan = nil
            return
        }
        guard let snapshot = agendaSourceSnapshot else {
            publishAgendaLoading(today: day)
            return
        }
        let stale: Bool
        if case .stale = agendaSourceStatus {
            stale = true
        } else {
            stale = false
        }
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: day,
            now: Date(),
            isStale: stale
        )
        publishAgendaPlan(presentation)
        scheduleCalendarBoundaryRefresh()
    }

    /// Schedules one `.eventBoundary` refresh at the band's next event
    /// boundary while the agenda is visible. A new plan cancels and
    /// re-arms the sleep; each boundary fires at most once until the
    /// panel hides or the day or snapshot changes.
    private func scheduleCalendarBoundaryRefresh() {
        agendaBoundaryTask?.cancel()
        agendaBoundaryTask = nil
        guard agendaVisible,
            let raw = agendaPresentation?.calendar?.refreshAt,
            let fireAt = CaptureAgendaClock.date(fromNaiveLocal: raw)
        else {
            return
        }
        guard let agendaStore else {
            return
        }
        switch CaptureAgendaBoundaryRefresh.decision(
            refreshAt: fireAt,
            lastFiredBoundary: agendaLastFiredBoundary,
            now: Date()
        ) {
        case .none:
            return
        case .immediate:
            agendaLastFiredBoundary = fireAt
            agendaStore.refresh(reason: .eventBoundary)
        case .sleep(let delay):
            agendaBoundaryTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
                await MainActor.run {
                    guard let self, self.agendaVisible,
                        CaptureAgendaBoundaryRefresh.decision(
                            refreshAt: fireAt,
                            lastFiredBoundary: self.agendaLastFiredBoundary,
                            now: Date()
                        ) == .immediate
                    else {
                        return
                    }
                    self.agendaLastFiredBoundary = fireAt
                    self.agendaStore?.refresh(reason: .eventBoundary)
                }
            }
        }
    }

    private func resetCalendarBoundaryRefresh() {
        agendaBoundaryTask?.cancel()
        agendaBoundaryTask = nil
        agendaLastFiredBoundary = nil
    }

    /// Paints one quiet "Loading today…" line while the setting is on
    /// and the store has nothing current yet. Unsupported bobs keep
    /// the compact bar with no agenda at all.
    private func publishAgendaLoading(today: String) {
        // The store's `@Published` properties emit in `willSet`: read
        // the cached emission, never the store, or the unsupported plan
        // never clears (the sink runs before `status` lands).
        if agendaSourceStatus == .unsupported {
            agendaPresentation = nil
            agendaPlan = nil
            return
        }
        publishAgendaPlan(CaptureAgendaPresentation.loading(today: today))
    }

    private func publishAgendaPlan(_ presentation: CaptureAgendaPresentation) {
        if agendaPresentation != presentation {
            agendaPresentation = presentation
        }
        let plan = CaptureAgendaHeightResolver.resolve(
            presentation: presentation,
            budget: agendaBudget,
            expanded: agendaExpanded,
            width: max(1, agendaContentWidth),
            measurer: agendaMeasurer
        )
        guard agendaPlan != plan else {
            return
        }
        agendaPlan = plan
        agendaPlanDidChange?()
    }

    /// True while either close-list gate has a known lineup below the
    /// single-digit limit.
    var closeTaskCommaArmed: Bool {
        CaptureCloseTaskCommaAssist.isArmed(
            taskLinkCount: currentPomodoroTaskLinkCount,
            pastTaskLinkCount: maxTaskLinkCount
        )
    }

    /// Latest `capture-parse` close-list spans, stored only while they
    /// describe exactly the visible draft.
    private var closeListParseSnapshot: CaptureParseSnapshot?

    /// Set by the digit key event before AppKit types the digit, so the
    /// next `editorTextDidChange` starts an immediate assist parse of the
    /// draft that key produces. The view-supplied caret can lag one edit
    /// behind, so the caret must not gate the request.
    private var closeListAssistParsePending = false
    private var closeListAssistParseTask: Task<Void, Never>?

    /// Guards in-flight close-list assist parses across client replacement:
    /// only parses belonging to the active client publish their snapshot.
    private var closeAssistParseGeneration: UInt64 = 0

    /// Provenance for auto-comma insertions the controller actually applied.
    /// Each entry is a `,<digit>` pair in UTF-16 coordinates; Backspace
    /// removes only an intact recorded pair, never an inferred comma-digit
    /// substring. Ordinary edits reconcile via prefix/suffix diff so
    /// unaffected pairs survive shifts; wholesale replacement clears it.
    private var closeCommaProvenance = CaptureCloseTaskCommaProvenance()
    private var lastProvenanceDraft = ""

    func setCurrentPomodoroTaskLinkCountForTests(_ count: Int?) {
        currentPomodoroTaskLinkCount = count
    }

    func setMaxTaskLinkCountForTests(_ count: Int?) {
        maxTaskLinkCount = count
    }

    func setCloseListParseSnapshotForTests(
        _ snapshot: CaptureParseSnapshot?
    ) {
        closeListParseSnapshot = snapshot
    }

    var closeListAssistParsePendingForTests: Bool {
        closeListAssistParsePending
    }

    func closeCommaProvenanceForTests() -> CaptureCloseTaskCommaProvenance {
        closeCommaProvenance
    }

    func setCloseCommaProvenanceForTests(_ provenance: CaptureCloseTaskCommaProvenance) {
        closeCommaProvenance = provenance
        lastProvenanceDraft = plainDraft
    }

    func setEditorInputLockedForTests(_ locked: Bool) {
        editorInputLocked = locked
    }

    /// Requests an immediate close-list assist parse of whatever draft
    /// the in-flight digit key produces. Called first by the key-driven
    /// insertion path, on both the accept and decline paths.
    func requestCloseListAssistParse() {
        closeListAssistParsePending = true
    }

    init(
        processClient: BobProcessClient? = nil,
        debounceNanoseconds: UInt64 = 50_000_000,
        similarTasksSettleNanoseconds: UInt64 = 350_000_000,
        gmailPeekSettleNanoseconds: UInt64 = 350_000_000,
        canceledDraftStash: CanceledDraftStash? = nil,
        savedTemplateShelf: SavedTemplateShelf? = nil
    ) {
        self.processClient = processClient
        self.debounceNanoseconds = debounceNanoseconds
        self.similarTasksSettleNanoseconds = similarTasksSettleNanoseconds
        self.gmailPeekSettleNanoseconds = gmailPeekSettleNanoseconds
        let canceledDraftStash = canceledDraftStash ?? CanceledDraftStash()
        self.canceledDraftStash = canceledDraftStash
        let savedTemplateShelf = savedTemplateShelf ?? SavedTemplateShelf(processClient: processClient)
        self.savedTemplateShelf = savedTemplateShelf
        stashCancellable = canceledDraftStash.$entries.sink { [weak self] entries in
            guard let self else {
                return
            }
            self.objectWillChange.send()
            self.clampStashSelection(afterEntriesChange: entries)
        }
        templateShelfCancellable = savedTemplateShelf.$templates.sink { [weak self] templates in
            guard let self else {
                return
            }
            self.objectWillChange.send()
            self.clampTemplateSelection(templates: self.visibleTemplateEntries(from: templates))
        }
        startCloseAliasProbeIfNeeded()
    }

    deinit {
        closeAliasProbeTask?.cancel()
        closeListAssistParseTask?.cancel()
        analysisTask?.cancel()
        pendingExplicitSubmitTask?.cancel()
        livePreviewTask?.cancel()
        clipboardPollTask?.cancel()
        pastRefreshTask?.cancel()
        similarTasksTask?.cancel()
        gmailPeekTask?.cancel()
        rewriteTask?.cancel()
        aliasTipTask?.cancel()
        todayPomodoroGotoTask?.cancel()
        pomodoroThemeSuggestionsTask?.cancel()
    }

    var plainDraft: String {
        get { String(attributedDraft.characters) }
        set { setPlainDraft(newValue) }
    }

    /// Ghost titles for the editor overlay, in draft order. Empty unless
    /// the latest successful preview's draft still equals the current
    /// draft; any keystroke hides them until the next preview lands. The
    /// overlay draws these without touching the text storage, so the
    /// submitted draft is exactly what was typed.
    /// Overlay and highlighter share this gate so a visible `@` never loses
    /// its emoji and the emoji never sits over a visible `@`.
    var showsRecordRouteEmoji: Bool {
        !isSubmitting && !editorInputLocked
    }

    func recordRouteAdornments() -> [CaptureRecordRouteAdornment] {
        guard showsRecordRouteEmoji,
            let parse = latestParse, parse.input == plainDraft
        else {
            return []
        }
        return CaptureRecordRouteAdornment.all(in: parse)
    }

    /// The footer bare-album one-key fix, only while the parse still
    /// describes the current draft. The footer button and hosted tests
    /// share this gate so a discarded or edited draft cannot resurrect
    /// a stale rewrite; `applyDiagnosticRewrite` stays the last line
    /// of defense.
    var bareAlbumRewrite: CaptureDiagnosticRewrite? {
        guard let parse = latestParse, parse.input == plainDraft else {
            return nil
        }
        return CaptureBareAlbumRefusal.rewrite(in: parse)
    }

    func moveGhostTitles() -> [CaptureProjectNoteMoveGhost] {
        guard let previewDraft = previewOutputsDraft,
              previewDraft == plainDraft
        else {
            return []
        }
        let moved = previewResults.flatMap { $0.projectNote?.movedTasks ?? [] }
        return CaptureMoveChoicePresentation.ghosts(
            draft: plainDraft, previewDraft: previewDraft,
            report: previewPullInSnapshot?.moveChoice
        )
            + CaptureProjectNoteMoveGhosts.ghosts(
                draft: plainDraft,
                previewDraft: previewDraft,
                movedTasks: moved
            )
    }

    var hasDraft: Bool {
        !plainDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var notebookSectionEditorHelp: String? {
        guard let parse = latestParse,
              parse.input == plainDraft,
              let cursor = collapsedSelectionUTF8Offset()
        else {
            return nil
        }
        return CaptureNotebookPresentation.editorSectionHelp(parse: parse, cursorUTF8: cursor)
    }

    var completionVisible: Bool {
        !isStashPickerPresented
            && !isTemplateShelfPresented
            && !inlinePromptVisible
            && completionResponse.map { response in
                !response.candidates.isEmpty || Self.hasVisiblePlaceMenuHint(response)
            } == true
            && (completionResponse.map(Self.isRecordCompletion) != true
                || recordCompletionSnapshotIsCurrent)
    }

    private static func hasVisiblePlaceMenuHint(_ response: CaptureCompletionResponse) -> Bool {
        guard response.placeMenu != nil,
              let hint = response.placeMenu?.emptyHint
        else {
            return false
        }
        return !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var recordCardActive: Bool {
        recordPresentation != nil || recordInteractionPending
    }

    var recordAssistAvailable: Bool {
        recordAssistVersion == 1 && recordCardActive
    }

    var recordCompletionSurface: CaptureRecordCompletionSurface {
        CaptureRecordCompletionSurface.make(
            context: completionResponse?.context,
            candidateCount: completionResponse?.candidates.count ?? 0,
            snapshotCurrent: recordCompletionSnapshotIsCurrent,
            isRecordCompletion: completionResponse.map(Self.isRecordCompletion) ?? false
        )
    }

    var recordCompletionListVisible: Bool {
        recordCompletionSurface.listVisibleOnCard
    }

    var recordShowsGenericCompletionFallback: Bool {
        recordCompletionSurface.showsGenericFallback
    }

    var recordEditAvailable: Bool {
        recordCompletionSnapshotIsCurrent && completionResponse?.record?.edit != nil
    }

    var inlinePromptVisible: Bool {
        taskIDPrompt != nil || pomodoroNamePrompt != nil || relationLabelPrompt != nil
            || moveChoice != nil || pullInChoice != nil || inboxRouteChoice != nil
    }

    var moveChoiceVisible: Bool { moveChoice != nil }

    var pullInChoiceVisible: Bool {
        pullInChoice != nil
    }

    var inboxRouteChoiceVisible: Bool {
        inboxRouteChoice != nil
    }

    var previewInboxRoute: CaptureInboxRoute? {
        guard let processClient else {
            return nil
        }
        return currentPullInPreview(for: plainDraft, processClient: processClient)?.inboxRoute
    }

    var pickerVisible: Bool {
        picker != nil
    }

    /// False while any modal, prompt, or completion list is visible.
    var pickerChipVisible: Bool {
        pickerChip != nil
            && !isStashPickerPresented
            && !isTemplateShelfPresented
            && !inlinePromptVisible
            && !completionVisible
    }

    var pickerFilterIsEmpty: Bool {
        picker?.filterText.isEmpty ?? true
    }

    var selectedPickerRow: CapturePickerRow? {
        guard let selectedRowID = picker?.selectedRowID else {
            return nil
        }
        return pickerPresentation?.row(id: selectedRowID)
    }

    var taskIDPromptVisible: Bool {
        taskIDPrompt != nil
    }

    /// True when the Add block ID prompt is open in link mode.
    var taskIDPromptIsTaskLink: Bool {
        guard let prompt = taskIDPrompt else {
            return false
        }
        if case .taskLink = prompt.purpose {
            return true
        }
        return false
    }

    /// True when the Add block ID prompt is open in dependency mode.
    var taskIDPromptIsDependency: Bool {
        guard let prompt = taskIDPrompt else {
            return false
        }
        if case .dependency = prompt.purpose {
            return true
        }
        if case .blockedTask = prompt.purpose {
            return true
        }
        if case .relation = prompt.purpose {
            return true
        }
        return false
    }

    /// True when Tab / Shift-Tab cycle ID suggestions (link, dependency,
    /// Complete, Task Wikilink, parent-task card, move card, and similar-tasks band).
    /// The old inline `.parentTask` path keeps Tab consumed.
    var taskIDPromptCyclesSuggestions: Bool {
        taskIDPromptIsTaskLink || taskIDPromptIsDependency || taskIDPromptIsTaskComplete || taskIDPromptIsWikilinkTask || taskIDPromptIsParentTaskPicker || taskIDPromptIsProjectTaskMove || taskIDPromptIsSimilarTask
    }

    /// True when the Add block ID prompt is open for a similar-tasks row.
    var taskIDPromptIsSimilarTask: Bool {
        guard let prompt = taskIDPrompt else {
            return false
        }
        if case .similarTask = prompt.purpose {
            return true
        }
        return false
    }

    /// True when the Add block ID prompt is open for a parent-task card row.
    var taskIDPromptIsParentTaskPicker: Bool {
        guard let prompt = taskIDPrompt else {
            return false
        }
        if case .parentTaskPicker = prompt.purpose {
            return true
        }
        return false
    }

    /// True when the Add block ID prompt is open for a move card row.
    var taskIDPromptIsProjectTaskMove: Bool {
        guard let prompt = taskIDPrompt else {
            return false
        }
        if case .projectTaskMove = prompt.purpose {
            return true
        }
        return false
    }

    /// True when the open picker belongs to the `:` source.
    var pickerSourceIsTaskLink: Bool {
        picker?.source == .taskLink
    }

    /// True when the open picker belongs to the move (`^` / `:`) source.
    var pickerSourceIsProjectTaskMove: Bool {
        if case .projectTaskMove = picker?.source {
            return true
        }
        return false
    }

    /// True when the open picker belongs to the `/` source.
    var pickerSourceIsTaskGoto: Bool {
        picker?.source == .taskGoto
    }

    /// True when the open picker belongs to the `&` source.
    var pickerSourceIsDependency: Bool {
        picker?.source == .dependency
    }

    var pickerSourceIsBlockedTask: Bool {
        picker?.source == .blockedTask
    }

    var pickerSourceIsRelation: Bool {
        picker?.source.isRelation == true
    }

    /// Picker opened by Bob's sigil reply. `@` opens route completion and
    /// therefore has no picker source.
    private func modifierAliasPickerSource(for sigil: String) -> CapturePickerSource? {
        switch sigil {
        case "@":
            return nil
        case "~":
            return .linksTo
        case "&":
            return .dependency
        case "*":
            return .blockedTask
        default:
            return nil
        }
    }

    private func modifierAliasArm(
        _ arm: CaptureEqualsGestureArm,
        owns openPicker: CapturePickerState
    ) -> Bool {
        guard let source = modifierAliasPickerSource(for: arm.sigil) else {
            return false
        }
        return openPicker.source == source
            && openPicker.draftSnapshot == arm.postDraft
            && openPicker.replacementRange.start == arm.preCaretUTF8
    }

    /// True only when the active opener's own picker is visible with an
    /// empty filter. Routed to the key router for Space/Escape restoration.
    var modifierAliasOpenerOwnPickerIsEmpty: Bool {
        guard let arm = equalsGestureArm,
              arm.isOpener,
              let openPicker = picker,
              modifierAliasArm(arm, owns: openPicker)
        else {
            return false
        }
        return openPicker.filterText.isEmpty
    }

    func pickerActionLine(for row: CapturePickerRow) -> String? {
        guard let line = pickerIndex?.actionLine(for: row) else {
            return nil
        }
        // While an `=` opener record is live, the relation picker teaches
        // the fast escape instead of the plain flip hint. A `.` arm never
        // teaches here: it opens route completion, not a relation picker.
        if let arm = equalsGestureArm,
           arm.isOpener,
           arm.key == "=",
           arm.surface == .editor,
           picker?.source.isRelation == true
        {
            return line.replacingOccurrences(
                of: "~ or = flips direction",
                with: "== types = · ~ flips"
            )
        }
        if let arm = equalsGestureArm,
           arm.isOpener,
           arm.surface == .editor,
           (arm.sigil == "&" || arm.sigil == "*"),
           let openPicker = picker,
           modifierAliasArm(arm, owns: openPicker)
        {
            return line.replacingOccurrences(
                of: "space adds another \(arm.sigil)",
                with: "\(arm.key)\(arm.key) types \(arm.key)"
            )
        }
        return line
    }

    /// True when the open picker belongs to the `!` source.
    var pickerSourceIsTaskComplete: Bool {
        picker?.source == .taskComplete
    }

    /// True when the Add block ID prompt is open in Complete mode.
    var taskIDPromptIsTaskComplete: Bool {
        guard let prompt = taskIDPrompt else {
            return false
        }
        if case .taskComplete = prompt.purpose {
            return true
        }
        return false
    }

    /// True when the open picker belongs to the `((` source.
    var pickerSourceIsWikilinkTask: Bool {
        picker?.source.isWikilinkTask == true
    }

    /// True when the Add block ID prompt is open in Task Wikilink mode.
    var taskIDPromptIsWikilinkTask: Bool {
        guard let prompt = taskIDPrompt else {
            return false
        }
        if case .wikilinkTask = prompt.purpose {
            return true
        }
        return false
    }

    /// True when the open picker belongs to the parent-task source.
    var pickerSourceIsParentTask: Bool {
        if case .parentTask = picker?.source {
            return true
        }
        return false
    }

    /// Lone-plus operator-continuation keys while the parent-task filter is
    /// empty, plus Bob's Complete (`!`) continuation keys while its filter
    /// is empty. Empty for every other source, a nonempty filter, and scoped
    /// or prose-terminal plus pickers (Bob omits the keys there), plus the
    /// move picker's server-authored marker continuation.
    var pickerOperatorContinuationKeys: [String] {
        guard pickerFilterIsEmpty else {
            return []
        }
        if case .parentTask(let context) = picker?.source {
            return context.actionContinuationKeys
        }
        if picker?.source == .taskComplete {
            return picker?.taskCompleteContinuationKeys ?? []
        }
        if case .projectTaskMove(let context) = picker?.source {
            return context.actionContinuationKeys
        }
        return []
    }

    /// Bob's alias map for continuation keys: comma to plus on a lone `+`,
    /// or period to caret on a lone `- ^`. Empty for other sources, a
    /// nonempty filter, or an older Bob that omits the field.
    var pickerOperatorContinuationAliases: [String: String] {
        guard pickerFilterIsEmpty else {
            return [:]
        }
        if case .parentTask(let context) = picker?.source,
            context.isLonePlusOperator
        {
            return context.actionContinuationAliases
        }
        if case .projectTaskMove(let context) = picker?.source {
            return context.actionContinuationAliases
        }
        return [:]
    }

    var pickerParentContinuationAvailable: Bool {
        guard case .parentTask(let context) = picker?.source else {
            return false
        }
        return context.continuation != nil
    }

    var taskIDPromptCanSubmit: Bool {
        guard let prompt = taskIDPrompt, !prompt.isSaving else {
            return false
        }
        return Self.isValidBlockID(prompt.authoredID)
    }

    var pomodoroNamePromptVisible: Bool {
        pomodoroNamePrompt != nil
    }

    var completionHasSelectedHistoryTheme: Bool {
        selectedHistoryThemeCandidate != nil
    }

    var completionThemeVisibilityWriteInFlight: Bool {
        isWritingThemeVisibility
    }

    var pomodoroNamePromptCanSubmit: Bool {
        guard let prompt = pomodoroNamePrompt, !prompt.isSaving else {
            return false
        }
        return Self.isValidPomodoroName(prompt.authoredName)
    }

    var pomodoroNamePromptCanonicalName: String? {
        guard let prompt = pomodoroNamePrompt else {
            return nil
        }
        let canonical = Self.canonicalPomodoroName(prompt.authoredName)
        return Self.isValidCanonicalPomodoroName(canonical) ? canonical : nil
    }

    /// Name-it warnings for components outside Bob's configured vocabulary.
    var pomodoroNamePromptWarnings: [StructuredCaptureWarning] {
        guard let prompt = pomodoroNamePrompt,
              let configured = prompt.configuredThemes,
              !configured.isEmpty
        else {
            return []
        }
        let name = pomodoroNamePromptCanonicalName ?? prompt.authoredName
        return CaptureUnconfiguredThemePresentation.nameItWarnings(
            authoredName: name,
            configuredThemes: configured
        )
    }

    func visibleThemeNotConfiguredWarnings(
        from success: CaptureCommandSuccess
    ) -> [StructuredCaptureWarning] {
        let themeSpans = (latestParse?.spans ?? []).filter {
            $0.kind == "pomodoro_name"
                || $0.kind == "task_toggle_pomodoro_name"
                || $0.kind == "task_type"
                || $0.kind == "task_type_marker"
        }.flatMap(\.themes)
        return CaptureUnconfiguredThemePresentation.visibleWarnings(
            from: success.warnings,
            draft: plainDraft,
            caretUTF8: collapsedSelectionUTF8Offset(),
            themeSpans: themeSpans,
            configuredNames: visibleConfiguredThemeNames()
        )
    }

    func visibleConfiguredThemeNames() -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        func add(_ name: String) {
            let key = PomodoroThemeSwatches.normalizeThemeKey(name)
            guard !key.isEmpty, seen.insert(key).inserted else {
                return
            }
            names.append(name)
        }
        for theme in configuredThemes {
            add(theme.name)
            add(theme.key)
        }
        if let completion = completionResponse {
            for candidate in completion.candidates {
                for theme in candidate.themes where theme.configured == true {
                    add(theme.name)
                }
            }
        }
        return names
    }

    var stashEntries: [CanceledDraftEntry] {
        canceledDraftStash.entries
    }

    var stashCount: Int {
        canceledDraftStash.count
    }

    var selectedStashEntry: CanceledDraftEntry? {
        canceledDraftStash.entry(at: selectedStashIndex)
    }

    var templateEntries: [CaptureSavedTemplate] {
        visibleTemplateEntries(from: savedTemplateShelf.templates)
    }

    var templateShelfCount: Int {
        templateEntries.count
    }

    var selectedTemplateEntry: CaptureSavedTemplate? {
        guard templateEntries.indices.contains(selectedTemplateIndex) else {
            return nil
        }
        return templateEntries[selectedTemplateIndex]
    }

    var savedTemplatesFooterVisible: Bool {
        !savedTemplateShelf.isUnsupported
    }

    var currentDraftHasTemplate: Bool {
        parsedTemplate != nil && lastAppliedParseDraft == plainDraft
    }

    /// What the newline key inserts instead of a bare newline: `\n- ` when
    /// Bob's parse of this exact draft reports `list_item` for the lone
    /// `@file` header the caret ends, so the next keystroke is the first
    /// bullet. Nil for every other caret, draft, and stale parse, which keep
    /// the plain newline. `caretUTF8` is the collapsed caret as a UTF-8 offset.
    func listHeaderNewlineInsertion(caretUTF8: Int) -> String? {
        guard picker == nil,
              let parse = latestParse,
              lastAppliedParseDraft == plainDraft,
              CaptureListHeaderNewline.startsFirstBullet(
                  parse: parse,
                  draft: plainDraft,
                  caretUTF8: caretUTF8
              )
        else {
            return nil
        }
        return CaptureListHeaderNewline.insertion
    }

    var destinationSummary: String? {
        if !previewResults.isEmpty {
            return captureSummary(
                prefix: "Preview",
                captures: previewResults,
                globalDestination: previewGlobalDestination
            )
        }
        if !lastSuccessResults.isEmpty {
            return captureSummary(
                prefix: "Captured",
                captures: lastSuccessResults,
                globalDestination: lastSuccessGlobalDestination
            )
        }
        return nil
    }

    var selectedCompletion: CaptureCompletionCandidate? {
        guard let candidates = completionResponse?.candidates,
              let index = selectedCompletionIndex,
              candidates.indices.contains(index)
        else {
            return nil
        }
        return candidates[index]
    }

    var captureGrammarAllowsSubmit: Bool {
        guard let processClient,
              lastAppliedParseDraft == plainDraft,
              lastAppliedParseGeneration == analysisGeneration,
              lastAppliedParseClientIdentity == processClient.identityToken
        else {
            return false
        }
        return CaptureGrammarGate.isCompatible(lastAppliedParseGrammar)
    }

    /// The pending merge-in payload only belongs to the exact parse and Bob
    /// executable that resolved it. A new edit, analysis, or client hides it
    /// before its replacement request settles.
    var currentMergeInPending: CaptureMergeInPending? {
        guard let state = mergeInPendingRevision,
              let latestParse,
              state.draft == plainDraft,
              state.generation == analysisGeneration,
              state.processClientIdentity == processClient?.identityToken,
              Self.pickerNeed(in: latestParse) == .mergeInSource,
              lastAppliedParseDraft == state.draft,
              lastAppliedParseGeneration == state.generation,
              lastAppliedParseClientIdentity == state.processClientIdentity
        else {
            return nil
        }
        return state.pending
    }

    /// The target header from Bob's parse for the pending item's one-based
    /// index. Never infer it by scanning the draft text.
    var currentMergeInPendingTargetTitle: String? {
        guard let pending = currentMergeInPending,
            let latestParse
        else {
            return nil
        }
        let body: String
        if latestParse.items.isEmpty {
            body = latestParse.body
        } else {
            let index = pending.item - 1
            guard latestParse.items.indices.contains(index) else {
                return nil
            }
            body = latestParse.items[index].body
        }
        let title = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// A Bob parse explicitly says this capture item still needs a source
    /// after `<`; Return and every primary action stay disabled in that state.
    var mergeInNeedsSource: Bool {
        guard let latestParse,
              latestParse.input == plainDraft,
              lastAppliedParseDraft == plainDraft,
              lastAppliedParseGeneration == analysisGeneration,
              lastAppliedParseClientIdentity == processClient?.identityToken
        else {
            return false
        }
        return Self.pickerNeed(in: latestParse) == .mergeInSource
    }

    /// The live preview's toggle presentation, when the current draft is exactly one
    /// `task_toggle` item. `nil` for an empty draft, a non-toggle draft, or a batch of
    /// more than one item, where "Set Next"/"Set Open" would misname the primary action.
    var togglePresentation: CaptureTogglePresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CaptureTogglePresentation(capture: previewResult)
    }

    /// The live preview's link presentation, when the current draft is exactly one
    /// `pomodoro_link` item — the same single-item gate as the toggle presentation.
    var linkPresentation: CapturePomodoroLinkPresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CapturePomodoroLinkPresentation(capture: previewResult)
    }

    /// Split/merge previews are single-item cards; batches retain the generic
    /// Capture footer wording.
    var pomodoroSplitPresentation: CapturePomodoroSplitPresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CapturePomodoroSplitPresentation(capture: previewResult)
    }

    var pomodoroMergePresentation: CapturePomodoroMergePresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CapturePomodoroMergePresentation(capture: previewResult)
    }

    /// The live preview's reference presentation, when the current draft is
    /// exactly one `ref` item — the same single-item gate as the toggle
    /// presentation. Batches keep today's footer title.
    var refPresentation: CaptureRefPresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CaptureRefPresentation(capture: previewResult)
    }

    /// The live preview's task-complete presentation, when the current draft
    /// is exactly one whole-item `!note:block-id` completion — the same
    /// single-item gate as the toggle presentation.
    var taskCompletePresentation: CaptureTaskCompletePresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CaptureTaskCompletePresentation(capture: previewResult)
    }

    /// The live preview's close presentation for a single plain, linked-task, or
    /// new-task close. Bob's additive summary is the sole source of close effects.
    var closePresentation: CapturePomodoroClosePresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CapturePomodoroClosePresentation(capture: previewResult)
    }

    /// Past-work groups for the on-screen preview, one card per stack. Nil
    /// when the preview holds no `pomodoro_past` captures. Mixed batches keep
    /// their ordinary item order; homogeneous past batches use the new card
    /// and the Record footer action.
    var pastPresentation: CapturePomodoroPastPresentation? {
        guard !previewResults.isEmpty else {
            return nil
        }
        return CapturePomodoroPastPresentation(captures: previewResults)
    }

    /// True when every preview result is a recorded past session.
    var isHomogeneousPastPreview: Bool {
        pastPresentation?.isHomogeneous == true
    }

    /// The live preview's reset presentation for a single plain, linked-task,
    /// or new-task note-free `x0` reset. Bob's additive summary is the sole
    /// source of reset effects; mutually exclusive with the close above.
    var resetPresentation: CapturePomodoroResetPresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CapturePomodoroResetPresentation(capture: previewResult)
    }

    /// The live preview's adjustment presentation for a single `pomodoro_adjust`
    /// item — the same single-item gate as the toggle presentation.
    var adjustPresentation: CapturePomodoroAdjustPresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CapturePomodoroAdjustPresentation(capture: previewResult)
    }

    /// The live preview's shift presentation for a single `pomodoro_shift`
    /// item — the same single-item gate as the toggle presentation.
    var shiftPresentation: CapturePomodoroShiftPresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CapturePomodoroShiftPresentation(capture: previewResult)
    }

    /// The live preview's session-start presentation for a single whole-item
    /// `=`/`=<X>` start — the same single-item gate as the toggle
    /// presentation. Link and task starts keep their own presentations.
    var sessionStartPresentation: CapturePomodoroStartPresentation? {
        guard previewResults.count == 1, let previewResult,
              CapturePomodoroStartPresentation.isSessionStart(previewResult)
        else {
            return nil
        }
        return CapturePomodoroStartPresentation(capture: previewResult)
    }

    /// The live preview's transfer result for a single capture item.
    var transferPresentation: CaptureTransferPresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CaptureTransferPresentation(capture: previewResult)
    }

    /// The live preview's merge-in result for a single new-task item.
    /// Bulk drafts keep the aggregate `Capture` title; the band renders per item.
    var mergeInPresentation: CaptureMergeInPresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CaptureMergeInPresentation(capture: previewResult)
    }

    /// True when any capture in the on-screen preview is a restart or swap,
    /// so the footer's primary Return tints orange.
    var primaryActionIsOverride: Bool {
        previewResults.contains { capture in
            CapturePomodoroStartPresentation(capture: capture)?.isOverride == true
        }
    }

    /// The footer's primary action verb. Single close, start, toggle, link,
    /// adjust, and shift previews name their action so Return's meaning is
    /// clear. A `=` override start names its own verb (`Restart` / `Swap`)
    /// via its presentation. It never varies with `dryRun` — it always names
    /// what Return will do next.
    var primaryActionTitle: String {
        if !previewResults.isEmpty, previewResults.allSatisfy({ $0.kind == "note_pull" }) {
            return "Pull In"
        }
        if let transfer = transferPresentation {
            return transfer.primaryActionTitle
        }
        if let mergeIn = mergeInPresentation {
            return mergeIn.primaryActionTitle
        }
        if resetPresentation != nil {
            return "Reset"
        }
        if pomodoroSplitPresentation != nil {
            return "Split"
        }
        if pomodoroMergePresentation != nil {
            return "Merge"
        }
        if isHomogeneousPastPreview, let past = pastPresentation {
            return past.primaryActionTitle
        }
        if closePresentation != nil {
            return "Close"
        }
        if let start = sessionStartPresentation {
            return start.primaryActionTitle
        }
        if let title = togglePresentation?.primaryActionTitle {
            return title
        }
        if let title = linkPresentation?.primaryActionTitle {
            return title
        }
        if let title = taskCompletePresentation?.primaryActionTitle {
            return title
        }
        if let title = refPresentation?.primaryActionTitle {
            return title
        }
        if shiftPresentation != nil {
            return "Shift"
        }
        if adjustPresentation != nil {
            return "Adjust"
        }
        if let hint = CaptureRelationCompletePresentation.submitHint(
            cancelCount: CaptureRelationCancelPresentation.cancelCount(in: previewResults),
            completeCount: CaptureRelationCompletePresentation.completeCount(
                in: previewResults
            )
        ) {
            return hint
        }
        return "Capture"
    }

    /// The footer Open chip uses the same enablement as Capture.
    var primaryActionEnabled: Bool {
        hasDraft
            && !isSubmitting
            && !inlinePromptVisible
            && !pickerVisible
            && !isClosePending
            && !mergeInNeedsSource
            && mergeInRefusalPresentation == nil
            && captureGrammarAllowsSubmit
    }

    /// Plan used by the footer chip: the stored preview plan, else a
    /// legacy plan from `previewResults` when tests assign those directly.
    var previewOpenHintPlan: CaptureOpenPlan? {
        if let previewOpenPlan {
            return previewOpenPlan
        }
        guard !previewResults.isEmpty else {
            return nil
        }
        return CaptureOpenPlan(openNotes: nil, captures: previewResults)
    }

    var openHintPresentation: CaptureOpenHintPresentation {
        CaptureOpenHintPresentation(plan: previewOpenHintPlan)
    }

    /// Visibility is independent of Capture enablement: the chip stays on
    /// while this draft has no preview yet, and while the open plan is
    /// non-empty. The chip button is disabled until Capture is enabled.
    var openHintChipVisible: Bool {
        hasDraft && openHintPresentation.isAvailable
    }

    static func isControlHeldAlone(_ flags: NSEvent.ModifierFlags) -> Bool {
        let significant = flags.intersection([.control, .shift, .option, .command])
        return significant == .control
    }

    func noteModifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        if Self.isControlHeldAlone(flags) {
            beginOpenHintRevealIfNeeded()
        } else {
            clearOpenHintReveal()
        }
    }

    func beginOpenHintRevealIfNeeded() {
        guard openHintRevealTask == nil, !openHintRevealed else {
            return
        }
        let delay = openHintRevealDelayNanoseconds
        openHintRevealTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self?.openHintRevealed = true
            self?.openHintRevealTask = nil
        }
    }

    func clearOpenHintReveal() {
        openHintRevealTask?.cancel()
        openHintRevealTask = nil
        if openHintRevealed {
            openHintRevealed = false
        }
    }

    private static func openObsidianURL(
        _ url: URL,
        completion: @escaping @MainActor (Error?) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            Task { @MainActor in
                completion(error)
            }
        }
    }

    private func assignPreviewOutputs(
        captures: [CaptureCommandSuccess],
        openNotes: [CaptureOpenNote]?,
        globalDestination: CaptureGlobalDestination?,
        previewDraft: String
    ) {
        let nextTransfer: CaptureTransferPresentation? =
            captures.count == 1 ? CaptureTransferPresentation(capture: captures[0]) : nil
        if let nextTransfer {
            if let remembered = lastPreviewTransferVerb, remembered != nextTransfer.verb {
                let destination = CaptureTransferPresentation.announcementDestinationText(
                    destination: nextTransfer.destination
                )
                transferVerbAnnouncement = "Now \(nextTransfer.verb.gerund) into \(destination)"
                transferVerbAnnouncementTick += 1
            }
            lastPreviewTransferVerb = nextTransfer.verb
        } else {
            lastPreviewTransferVerb = nil
        }
        let nextMergeIn: CaptureMergeInPresentation? =
            captures.count == 1 ? CaptureMergeInPresentation(capture: captures[0]) : nil
        if let nextMergeIn {
            let keyParts =
                [nextMergeIn.relativeTarget]
                + nextMergeIn.sourceRows.flatMap {
                    [$0.stableID, $0.targetStatusName ?? ""]
                }
            let key = keyParts.map { "\($0.utf8.count):\($0)" }.joined()
            if lastPreviewMergeInKey != key {
                mergeInAnnouncement = nextMergeIn.settledAnnouncement
                mergeInAnnouncementTick += 1
            }
            lastPreviewMergeInKey = key
        } else {
            lastPreviewMergeInKey = nil
        }
        emptyNotePullPresentation = nil
        transferPendingPresentation = nil
        transferRefusalPresentation = nil
        mergeInRefusalPresentation = nil
        recordRefusalPresentation = nil
        previewResult = captures.first
        previewResults = captures
        previewGlobalDestination = globalDestination
        previewOpenPlan = CaptureOpenPlan(openNotes: openNotes, captures: captures)
        previewOutputsDraft = previewDraft
        schedulePastBoundaryRefresh()
    }

    /// Drops the remembered transfer footer after a later preview or parse
    /// overwrote it, or resets the footer to Ready while it still shows the
    /// remembered text. Unrelated notices are never clobbered.
    private func consumeTransferOwnedStatus() {
        guard let owned = transferOwnedStatusText else {
            return
        }
        transferOwnedStatusText = nil
        if statusText == owned {
            statusText = ""
        }
    }

    private func clearPreviewOutputs() {
        emptyNotePullPresentation = nil
        transferPendingPresentation = nil
        transferRefusalPresentation = nil
        mergeInRefusalPresentation = nil
        recordRefusalPresentation = nil
        previewResult = nil
        previewResults = []
        previewGlobalDestination = nil
        previewOpenPlan = nil
        previewOutputsDraft = nil
        cancelPastBoundaryRefresh()
        cancelGmailPeek(clear: true)
    }

    /// Follows both close-list gates from the agenda store. The store
    /// clears them on failure, a non-today snapshot, and client replacement.
    private func subscribeToAgendaStore() {
        agendaCancellable = nil
        agendaMaxTaskLinkCountCancellable = nil
        agendaSnapshotCancellable = nil
        agendaDayChangeCancellable = nil
        guard let agendaStore else {
            return
        }
        agendaCancellable = agendaStore.$currentTaskLinkCount.sink { [weak self] count in
            guard let self else {
                return
            }
            self.currentPomodoroTaskLinkCount = count
        }
        agendaMaxTaskLinkCountCancellable = agendaStore.$maxTaskLinkCount.sink {
            [weak self] count in
            guard let self else {
                return
            }
            self.maxTaskLinkCount = count
        }
        // The store's `@Published` properties emit in `willSet`, so
        // the sink plans from the emitted values, never the store:
        // the first emission after launch would otherwise plan
        // against nil ("Loading today…") and every later snapshot
        // would render the one before it. Status-only changes (stale,
        // recovery, unsupported) re-plan through the same path. The
        // store only publishes on change, so byte-identical output
        // stays a no-op here too.
        agendaSnapshotCancellable = agendaStore.$snapshot
            .combineLatest(agendaStore.$status)
            .sink { [weak self] snapshot, status in
                guard let self else {
                    return
                }
                let snapshotChanged = snapshot != self.agendaSourceSnapshot
                self.agendaSourceSnapshot = snapshot
                self.agendaSourceStatus = status
                if snapshotChanged {
                    self.resetCalendarBoundaryRefresh()
                    self.agendaExpanded = []
                    self.agendaMeasurer.noteSnapshotChange()
                    self.agendaPlanningDay = nil
                }
                self.refreshAgendaPlan()
            }
        agendaDayChangeCancellable = NotificationCenter.default
            .publisher(for: .NSCalendarDayChanged)
            .merge(
                with: NotificationCenter.default.publisher(
                    for: .NSSystemClockDidChange
                )
            )
            // Foundation posts day-change notifications in the background; keep agenda
            // measurement on the main thread, matching CaptureAgendaStore's observers.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.noteAgendaDayChanged()
            }
    }

    /// A day or clock change retires the pinned planning day and
    /// parks the agenda on "Loading today…" until the store's refresh
    /// lands, so a hidden panel never paints yesterday's plan at the
    /// next show.
    private func noteAgendaDayChanged() {
        resetCalendarBoundaryRefresh()
        cancelPastBoundaryRefresh()
        agendaPlanningDay = nil
        publishAgendaLoading(today: CaptureAgendaStore.localToday())
    }

    func setProcessClient(_ processClient: BobProcessClient?) {
        let changed = self.processClient !== processClient
        self.processClient = processClient
        if changed {
            cancelPendingExplicitSubmit()
            cancelPastBoundaryRefresh()
            // Recheck Bob is not an editor echo of the last splice: drop the
            // suppression so the re-parse below actually runs.
            suppressedCompletionAcceptanceDraft = nil
            // An old count or assist parse must never re-arm the assist
            // after Bob becomes unavailable or the executable/vault changes.
            // The agenda store owns recounting; it clears and repopulates
            // the count through the subscription above.
            closeListAssistParseTask?.cancel()
            closeListAssistParseTask = nil
            closeAssistParseGeneration &+= 1
            currentPomodoroTaskLinkCount = nil
            maxTaskLinkCount = nil
            closeListParseSnapshot = nil
            closeListAssistParsePending = false
            closeCommaProvenance.clear()
            lastProvenanceDraft = plainDraft
            invalidateRewrite()
            if relationLabelPrompt != nil {
                relationLabelCatalogGeneration &+= 1
                relationLabelCatalogInFlight = nil
                relationLabelSuggestionGeneration &+= 1
                relationLabelInFlight = nil
            }
        }
        if processClient == nil {
            if changed {
                statusText = "Bob is not resolved"
                previewState = .idle
                clearPreviewOutputs()
                completionResponse = nil
                completionDraftSnapshot = nil
                fileUnderActive = false
                clearPickerState()
                invalidateAnalysis()
                invalidateRewrite()
            }
        } else {
            if changed, var prompt = relationLabelPrompt {
                prompt.catalogLoaded = false
                prompt.catalogErrorMessage = nil
                prompt.suggestionAuthoredLabel = nil
                relationLabelPrompt = prompt
                fetchRelationLabelCatalog()
                fetchRelationLabelSuggestions()
            }
            if hasDraft {
                editorTextDidChange()
            }
        }
    }

    /// Cancels the exact rewrite whose later keys are currently held. The
    /// controller calls this before replaying a non-empty flushed queue.
    func cancelMeaningChangingRewrite(generation: UInt64) {
        guard rewriteGeneration == generation,
            meaningChangingRewriteHoldGeneration == generation
        else {
            return
        }
        invalidateRewrite()
    }

    /// True only after the one-time old-bob probe for the current client
    /// answered supported. Unknown, unsupported, and failure states all stay
    /// literal.
    func closeAliasForwardingAllowed() -> Bool {
        guard let client = processClient else {
            return false
        }
        return closeAliasSupportedIdentities.contains(client.identityToken)
    }

    /// Records the one-time old-bob status the first time an `x`/`s` key
    /// would have been forwarded but the probe already reported unsupported.
    /// Unknown (probe in flight or transport failure) stays silent.
    func noteCloseAliasBlocked() {
        guard let client = processClient else {
            return
        }
        let identity = client.identityToken
        guard closeAliasUnsupportedIdentities.contains(identity),
              !closeAliasAnnouncedIdentities.contains(identity)
        else {
            return
        }
        closeAliasAnnouncedIdentities.insert(identity)
        announceStatus(Self.closeAliasOldBobMessage)
    }

    /// Starts the one-time old-bob probe for the current client when its
    /// verdict is not yet cached. Supported only when `captureRewrite("xx")`
    /// answers changed with text `x!`. Transport failures stay uncached so
    /// the next resolution retries.
    func startCloseAliasProbeIfNeeded() {
        guard let client = processClient else {
            return
        }
        let identity = client.identityToken
        if closeAliasSupportedIdentities.contains(identity)
            || closeAliasUnsupportedIdentities.contains(identity)
        {
            return
        }
        if closeAliasProbeInFlightIdentity == identity {
            return
        }
        closeAliasProbeTask?.cancel()
        closeAliasProbeInFlightIdentity = identity
        closeAliasProbeTask = Task { [weak self, client] in
            do {
                try Task.checkCancellation()
                let response = try await client.captureRewrite(
                    Self.closeAliasProbeDraft,
                    cursor: Self.closeAliasProbeCursor,
                    lane: "close-alias-probe"
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard !Task.isCancelled, let self,
                        self.processClient === client,
                        self.processClient?.identityToken == identity
                    else {
                        return
                    }
                    self.closeAliasProbeInFlightIdentity = nil
                    if response.changed, response.text == "x!" {
                        self.closeAliasSupportedIdentities.insert(identity)
                    } else {
                        self.closeAliasUnsupportedIdentities.insert(identity)
                    }
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled, let self,
                        self.processClient === client
                    else {
                        return
                    }
                    self.closeAliasProbeInFlightIdentity = nil
                }
            }
        }
    }

    /// Awaits the in-flight close-alias probe, if any. Tests use this after
    /// installing a fake Bob so forwarding gates settle deterministically.
    func awaitCloseAliasProbeForTests() async {
        await closeAliasProbeTask?.value
    }

    /// Test seam: marks the current client identity as supporting (or
    /// predating) close-outcome aliases without spawning Bob.
    func installCloseAliasSupportForTests(supported: Bool) {
        guard let client = processClient else {
            return
        }
        closeAliasProbeTask?.cancel()
        closeAliasProbeTask = nil
        closeAliasProbeInFlightIdentity = nil
        let identity = client.identityToken
        if supported {
            closeAliasSupportedIdentities.insert(identity)
            closeAliasUnsupportedIdentities.remove(identity)
        } else {
            closeAliasUnsupportedIdentities.insert(identity)
            closeAliasSupportedIdentities.remove(identity)
        }
    }

    /// Test seam: whether the old-bob close-alias warning was announced for
    /// the current client identity.
    func closeAliasAnnouncedForTests() -> Bool {
        guard let client = processClient else {
            return false
        }
        return closeAliasAnnouncedIdentities.contains(client.identityToken)
    }

    /// Forwards one typed digit to the pure close-comma helper with the
    /// latest parse snapshot and both list bounds. Nil means type the digit natively.
    func closeTaskCommaEdit(
        typed: String,
        text: String,
        selectedRange: NSRange
    ) -> CaptureCloseTaskCommaEdit? {
        CaptureCloseTaskCommaAssist.edit(
            typed: typed,
            text: text,
            selectedRange: selectedRange,
            snapshot: closeListParseSnapshot,
            taskLinkCount: currentPomodoroTaskLinkCount,
            pastTaskLinkCount: maxTaskLinkCount
        )
    }

    /// Records an auto-comma pair the controller just applied via native
    /// `insertText`. Only the accepted insertion is recorded; Bob's spans
    /// already authorized it, so Swift never re-derives close grammar here.
    func recordCloseTaskCommaInsertion(commaLocation: Int, digit: String, resultingText: String) {
        closeCommaProvenance.record(commaLocation: commaLocation, digit: digit)
        lastProvenanceDraft = resultingText
    }

    /// Returns the native deletion range when the collapsed caret sits
    /// immediately after an intact recorded `,<digit>` pair, else nil.
    func closeTaskCommaBackspaceDeletionRange(caretLocation: Int, text: String) -> NSRange? {
        closeCommaProvenance.deletionRange(caretLocation: caretLocation, text: text)
    }

    /// Removes the recorded pair under the caret and shifts later pairs.
    /// Returns the deleted range, or nil when Backspace stays native.
    /// The caller applies the deletion through native `insertText` so
    /// undo/redo stays with the text system.
    @discardableResult
    func consumeCloseTaskCommaBackspace(caretLocation: Int, text: String) -> NSRange? {
        guard let range = closeCommaProvenance.consume(caretLocation: caretLocation, text: text) else {
            return nil
        }
        let nsText = text as NSString
        let newText = nsText.replacingCharacters(in: range, with: "")
        lastProvenanceDraft = newText
        return range
    }

    /// Reconciles ordinary text edits so pairs before/after the edit
    /// survive with shifted offsets. Called for every observed draft
    /// change outside wholesale programmatic replacement.
    func reconcileCloseCommaProvenance(oldText: String, newText: String) {
        closeCommaProvenance.reconcile(oldText: oldText, newText: newText)
        lastProvenanceDraft = newText
    }

    /// Records the expected post-key draft and caret for a rewrite-lane
    /// separator gesture or sigil alias (`:`, `^`, `+`, `|`, `,`, `.`, `;`,
    /// `\\`, `/`, the Pomodoro-segment `-` alias, relation `=` / `~` aliases,
    /// or close-outcome `x` / `s` aliases).
    /// The character still inserts natively; `editorTextDidChange` consumes
    /// this only when the resulting buffer matches.
    func noteSeparatorToggleIntent(
        typed: String,
        text: String,
        selectedRange: NSRange,
        timestamp: TimeInterval = 0,
        expectsRelationDirectionToggle: Bool = false
    ) {
        guard
            typed == ":" || typed == "^" || typed == "+" || typed == "|"
                || typed == "," || typed == "." || typed == ";" || typed == "\\"
                || typed == "/" || typed == "-" || typed == "=" || typed == "~"
                || typed == "x" || typed == "s",
            selectedRange.length == 0,
            selectedRange.location >= 0
        else {
            pendingSeparatorToggleIntent = nil
            return
        }
        let nsText = text as NSString
        guard selectedRange.location <= nsText.length else {
            pendingSeparatorToggleIntent = nil
            return
        }
        let expectedDraft = nsText.replacingCharacters(in: selectedRange, with: typed)
        let expectedUTF16 = selectedRange.location + (typed as NSString).length
        guard let expectedCursorUTF8 = utf8Offset(in: expectedDraft, utf16Offset: expectedUTF16)
        else {
            pendingSeparatorToggleIntent = nil
            return
        }
        pendingSeparatorToggleIntent = SeparatorToggleIntent(
            typed: typed,
            expectedDraft: expectedDraft,
            expectedCursorUTF8: expectedCursorUTF8,
            timestamp: timestamp,
            expectsRelationDirectionToggle: expectsRelationDirectionToggle
        )
        if typed == "=" {
            pendingEqualsFirstKey = (
                key: "=",
                draft: expectedDraft,
                caretUTF8: expectedCursorUTF8,
                timestamp: timestamp
            )
        }
        if typed == "." || typed == ";" {
            interruptedModifierAliasReply = nil
            // Mirror the alias's space/tab prefilter for the probe only: the
            // rewrite intent above is always recorded, but a fast double-key
            // probe matters only where Bob can replace the first key.
            let caretBytes = Array(text.utf8)
            let caretUTF8Count = utf8Offset(in: text, utf16Offset: selectedRange.location) ?? 0
            let previousIsBlank: Bool = {
                guard caretUTF8Count > 0, caretUTF8Count <= caretBytes.count else { return false }
                let previous = caretBytes[caretUTF8Count - 1]
                return previous == 0x20 || previous == 0x09
            }()
            if previousIsBlank {
                pendingEqualsFirstKey = (
                    key: typed,
                    draft: expectedDraft,
                    caretUTF8: expectedCursorUTF8,
                    timestamp: timestamp
                )
            }
        }
        if typed == "\\" || typed == "/" {
            pendingHashAlias = (
                key: typed,
                draft: expectedDraft,
                caretUTF8: expectedCursorUTF8
            )
        }
    }

    /// Stores the one-shot fast double-tap probe for a second alias key
    /// typed before Bob answers the first. Called from the
    /// `.typeKeyBeforeHashAliasReply` command; returns nothing so the caller
    /// passes the key through for native insertion.
    func noteHashAliasBeforeReply(
        secondDraft: String,
        secondCaretUTF8: Int
    ) {
        guard let pending = pendingHashAlias else {
            return
        }
        hashAliasProbe = HashAliasProbe(
            key: pending.key,
            firstDraft: pending.draft,
            firstCaretUTF8: pending.caretUTF8,
            secondDraft: secondDraft,
            secondCaretUTF8: secondCaretUTF8
        )
    }

    /// True when a second alias key before Bob's reply should re-ask Bob
    /// about the first: no live arm, a pending first key matching `typedKey`,
    /// and the live editor still showing that pending draft and caret.
    func hashAliasReplyPending(
        liveString: String,
        liveCaretUTF16: Int,
        hasMarkedText: Bool,
        typedKey: String
    ) -> Bool {
        guard hashAliasLiteralArm == nil,
              let pending = pendingHashAlias,
              pending.key == typedKey,
              !hasMarkedText,
              liveString == pending.draft,
              let pendingCaretUTF16 = utf16Range(
                  in: pending.draft,
                  start: pending.caretUTF8,
                  end: pending.caretUTF8
              )?.location,
              liveCaretUTF16 == pendingCaretUTF16
        else {
            return false
        }
        return true
    }

    /// Stores the one-shot probe for a second `=`/`~` typed fast after a
    /// first `=` while Bob's reply is still pending. Called from the
    /// `.typeKeyBeforeEqualsReply` command; returns nothing so the caller
    /// passes the key through for native insertion.
    func noteEqualsBeforeReply(
        secondDraft: String,
        secondCaretUTF8: Int,
        secondKey: String,
        secondTimestamp: TimeInterval
    ) {
        guard let pending = pendingEqualsFirstKey else {
            return
        }
        equalsProbe = CaptureEqualsProbe(
            secondKey: secondKey,
            firstDraft: pending.draft,
            firstCaretUTF8: pending.caretUTF8,
            secondDraft: secondDraft,
            secondCaretUTF8: secondCaretUTF8,
            secondTimestamp: secondTimestamp,
            firstKey: pending.key
        )
    }

    /// True when a second `=`, `~`, `.`, or `;` before Bob's reply should
    /// re-ask Bob about the first key: a pending first key still showing in
    /// the live editor, typed fast, unmodified, and without marked text.
    func equalsProbeReplyPending(
        liveString: String,
        liveCaretUTF16: Int,
        hasMarkedText: Bool,
        typedKey: String,
        timestamp: TimeInterval
    ) -> Bool {
        guard !hasMarkedText,
              typedKey == "=" || typedKey == "~" || typedKey == "." || typedKey == ";",
              let pending = pendingEqualsFirstKey,
              (pending.key == "=" && (typedKey == "=" || typedKey == "~"))
                  || ((pending.key == "." || pending.key == ";") && typedKey == pending.key),
              liveString == pending.draft,
              CaptureEqualsGesture.isFastSecond(
                  first: pending.timestamp,
                  second: timestamp
              ),
              let pendingCaretUTF16 = utf16Range(
                  in: pending.draft,
                  start: pending.caretUTF8,
                  end: pending.caretUTF8
              )?.location,
              liveCaretUTF16 == pendingCaretUTF16
        else {
            return false
        }
        return true
    }

    func updateTargetCacheSnapshot(_ snapshot: CaptureTargetsSnapshot) {
        let contentChanged =
            targetCacheSnapshot.targets != snapshot.targets
            || targetCacheSnapshot.stale != snapshot.stale
            || targetCacheSnapshot.errorDescription != snapshot.errorDescription
        if contentChanged {
            targetCacheSnapshot = snapshot
        }
        if let error = snapshot.errorDescription {
            statusText = snapshot.stale ? "Target cache stale" : error
        }
    }

    func editorTextDidChange(cursorUTF8Offset: Int? = nil) {
        guard !isApplyingProgrammaticDraft else {
            return
        }

        let draft = plainDraft
        if recordCardDismissedDraft != draft {
            recordCardDismissedDraft = nil
        }
        let deferredRewriteInputEcho = rewriteTask != nil
            && deferredRewriteInputDraft == draft
        if deferredRewriteInputEcho {
            // A native rewrite can notify the editor before the model mirror
            // receives Bob's replacement. The unchanged input is not a user
            // edit, so keep the rewrite alive until its reply arrives.
            return
        }
        if deferredRewriteEchoDraft != draft {
            deferredRewriteEchoDraft = nil
            deferredRewriteEchoCursorUTF8 = nil
        }
        reconcileAliasTipHit(with: draft)
        if let presentedAliasTipAnchor, !aliasTipIsIntact(presentedAliasTipAnchor) {
            retireAliasTipDisplayEligibility(reason: .sigilEdited)
        }
        if let request = aliasTipRequest, !aliasTipIsIntact(request.anchor) {
            retireAliasTipDisplayEligibility(reason: .sigilEdited)
        }
        if let pending = pendingAliasTip, !aliasTipIsIntact(pending.anchor) {
            dropPendingAliasTip(reason: .sigilEdited)
        }
        let acceptedDeferredRewriteEcho = deferredRewriteEchoDraft == draft
            && (pendingRewriteSubmitIntent != nil
                || pendingExplicitSubmitIntent?.draft == draft
                || isSubmitting)
        if !acceptedDeferredRewriteEcho {
            cancelPendingExplicitSubmit()
        }

        invalidateMoveChoiceForEdit(draft)
        if let hiddenThemeDraftSnapshot, hiddenThemeDraftSnapshot != draft {
            temporarilyHiddenThemeKey = nil
            self.hiddenThemeDraftSnapshot = nil
        }
        if draft.isEmpty {
            templateOrigin = nil
        }
        if let pullInChoice, pullInChoice.draftSnapshot != draft {
            cancelPullInChoiceFromKeyboard()
        }
        if let context = inboxRouteChoiceContext, context.draft != draft {
            discardInboxRouteChoiceForInvalidation()
        }
        if activeInboxRouteSubmitContext?.draft != draft {
            activeInboxRouteSubmitContext = nil
        }
        if previewPullInSnapshot?.draft != draft {
            previewPullInSnapshot = nil
        }
        if draft != lastProvenanceDraft {
            closeCommaProvenance.reconcile(oldText: lastProvenanceDraft, newText: draft)
            lastProvenanceDraft = draft
        }
        if let prompt = taskIDPrompt, prompt.draftSnapshot != draft {
            cancelTaskIDPrompt(clearCompletion: true)
        }
        if let prompt = pomodoroNamePrompt, prompt.draftSnapshot != draft {
            cancelPomodoroNamePrompt(clearCompletion: true)
        }

        if let suppressedDraft = suppressedCompletionAcceptanceDraft {
            if draft == suppressedDraft {
                return
            }
            suppressedCompletionAcceptanceDraft = nil
        }
        if !acceptedDeferredRewriteEcho {
            cancelPendingRewriteSubmit()
        }
        if shouldDismissPickerAfterEditorDraftChange(draft: draft) {
            closePickerAfterStaleDraft()
        }

        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            priorityRollSeed = nil
            resetAnalysisState()
            if !draft.isEmpty {
                isApplyingProgrammaticDraft = true
                attributedDraft.transform(updating: &editorSelection) { text in
                    Self.clearEditorHighlightAttributes(&text)
                }
                isApplyingProgrammaticDraft = false
            }
            noteAgendaDraftCleared()
            return
        }

        noteAgendaFirstKeystroke()

        if commitRouteCompletionOnAcceptKey(draft: draft) {
            pendingSeparatorToggleIntent = nil
            pendingTypedSigilIntent = nil
            return
        }

        let insertionOffset = cursorUTF8Offset ?? collapsedSelectionUTF8Offset()
        if let intent = consumeTypedSigilIntent(
            draft: draft,
            cursorUTF8Offset: insertionOffset
        ) {
            startAliasTipLane(
                draft: draft,
                cursorUTF8Offset: intent.expectedCaretUTF8,
                sigil: intent.sigil
            )
        }
        var analysisCursor = insertionOffset
        let requestCompletion = insertionOffset != nil
        var completionGate: Task<Void, Never>?
        if let probe = hashAliasProbe,
           draft == probe.secondDraft,
           Self.hashAliasProbeCursorMatches(insertionOffset, probe: probe)
        {
            completionGate = startHashAliasProbeRewrite(probe: probe)
            analysisCursor = probe.secondCaretUTF8
        } else if let probe = equalsProbe,
                  draft == probe.secondDraft,
                  Self.equalsProbeCursorMatches(insertionOffset, probe: probe)
        {
            completionGate = startEqualsProbeRewrite(probe: probe)
            analysisCursor = probe.secondCaretUTF8
        } else if let intent = consumeSeparatorToggleIntent(
            draft: draft,
            cursorUTF8Offset: insertionOffset
        ) {
            completionGate = startCaptureRewrite(
                draft: draft,
                cursorUTF8Offset: intent.expectedCursorUTF8,
                triggeredCharacter: intent.typed,
                triggerTimestamp: intent.timestamp,
                expectsRelationDirectionToggle: intent.expectsRelationDirectionToggle,
                deferSubmitForMeaningChangingAlias: Self.isMeaningChangingAlias(
                    trigger: intent.typed,
                    draft: intent.expectedDraft
                )
            )
            analysisCursor = intent.expectedCursorUTF8
        } else if let insertionOffset,
                  // A lone declaration has nothing to absorb.
                  draft != "@@",
                  Self.isBareAtAtTrigger(in: draft, cursorUTF8Offset: insertionOffset)
        {
            startCaptureRewrite(draft: draft, cursorUTF8Offset: insertionOffset)
        } else {
            invalidateRewrite()
        }
        if closeListAssistParsePending {
            closeListAssistParsePending = false
            if closeTaskCommaArmed {
                startCloseListAssistParse(draft: draft)
            }
        }
        scheduleAnalysis(
            cursorUTF8Offset: analysisCursor,
            requestCompletion: requestCompletion,
            trigger: .edit,
            completionGate: completionGate
        )
    }

    /// Immediate un-debounced parse feeding the close-comma snapshot.
    /// Stored only while the draft is still current; errors are swallowed.
    private func startCloseListAssistParse(draft: String) {
        guard let processClient else {
            return
        }
        closeAssistParseGeneration &+= 1
        let generation = closeAssistParseGeneration
        closeListAssistParseTask?.cancel()
        closeListAssistParseTask = Task { [weak self, processClient] in
            do {
                let parse = try await processClient.captureParse(
                    draft,
                    lane: "close-task-comma"
                )
                await MainActor.run {
                    guard self?.closeAssistParseGeneration == generation,
                          self?.processClient === processClient,
                          self?.plainDraft == draft
                    else {
                        return
                    }
                    self?.closeListParseSnapshot = CaptureParseSnapshot(
                        draft: draft,
                        parse: parse
                    )
                }
            } catch {
            }
        }
    }

    /// Replayed digits need Bob's spans for the preceding digit before
    /// attempting the comma assist. The subprocess has its normal timeout.
    func waitForCloseListAssistBeforeTypeAheadReplay() async {
        await closeListAssistParseTask?.value
    }

    func editorSelectionDidChange() {
        editorSelectionDidChange(cursorUTF8Offset: collapsedSelectionUTF8Offset())
    }

    func editorSelectionDidChange(to selection: AttributedTextSelection) {
        editorSelectionDidChange(cursorUTF8Offset: collapsedSelectionUTF8Offset(of: selection))
    }

    func editorSelectionDidChange(cursorUTF8Offset: Int?) {
        let insertionOffset = cursorUTF8Offset
        if let ignoredOffset = programmaticSelectionOffsetToIgnore {
            if ignoredOffset == insertionOffset {
                programmaticSelectionOffsetToIgnore = nil
                return
            }
            programmaticSelectionOffsetToIgnore = nil
        }
        let deferredRewriteSubmitIsPending = pendingRewriteSubmitIntent != nil
            || pendingExplicitSubmitIntent?.draft == plainDraft
            || isSubmitting
        if deferredRewriteEchoDraft == plainDraft,
           deferredRewriteSubmitIsPending,
           let expectedCursor = deferredRewriteEchoCursorUTF8,
           insertionOffset == expectedCursor || insertionOffset == expectedCursor - 1
        {
            return
        }
        if let intent = pendingRewriteSubmitIntent,
           intent.inputDraft == plainDraft,
           let expected = rewriteExpectedCursorUTF8,
           insertionOffset == expected || insertionOffset == expected - 1
        {
            return
        }
        if let expected = rewriteExpectedCursorUTF8 {
            if insertionOffset == expected {
                rewriteSawMatchingSelection = true
            } else {
                let laggedPreInsertCaret =
                    !rewriteSawMatchingSelection
                    && insertionOffset == expected - 1
                if !laggedPreInsertCaret {
                    cancelInFlightRewrite()
                    // The selection publisher fires before the text `.onChange`, so this
                    // caret move can be the keystroke that recorded the pending intent.
                    let matchesPendingIntent =
                        pendingSeparatorToggleIntent.map { intent in
                            insertionOffset == intent.expectedCursorUTF8
                                || insertionOffset == intent.expectedCursorUTF8 - 1
                        } ?? false
                    if !matchesPendingIntent {
                        pendingSeparatorToggleIntent = nil
                    }
                }
            }
        }
        guard !isApplyingProgrammaticDraft, hasDraft else {
            return
        }
        // A click or caret move clears the equals record, unless the caret
        // still sits where the gesture left it (the arming echo).
        if let arm = equalsGestureArm,
           arm.surface != .relationLabelCard,
           !(plainDraft == arm.postDraft && insertionOffset == arm.postCaretUTF8)
        {
            clearEqualsGestureArm()
        }

        // Invariant: selection callbacks never write attributedDraft or
        // editorSelection; those writes echo back through the TextEditor into
        // another selection callback and wedge the main thread. Caret-dependent
        // paint (the unconfigured-theme underline) refreshes via the
        // selection-triggered analysis below, which paints with this event's
        // caret: by the time the async parse returns, the live selection may
        // already belong to the next move.

        // A caret-only move never auto-opens the picker; at most it shows the
        // reopen chip.
        scheduleAnalysis(
            cursorUTF8Offset: insertionOffset,
            requestCompletion: insertionOffset != nil,
            trigger: .selection
        )
    }

    func collapsedSelectionUTF8Offset() -> Int? {
        collapsedSelectionUTF8Offset(of: editorSelection)
    }

    func collapsedSelectionUTF8Offset(of selection: AttributedTextSelection) -> Int? {
        switch selection.indices(in: attributedDraft) {
        case .insertionPoint(let index):
            return utf8Offset(in: attributedDraft, at: index)
        case .ranges(_):
            return nil
        }
    }

    // Treats `+` as "accept the visible route completion" the same way Return does,
    // and lets `,` accept a partial route before Bob rewrites it to `+`.
    // This lets the user accept the route and open its task picker in one gesture.
    // Decides purely from the draft diff against `completionDraftSnapshot` — never
    // from the view-supplied caret, which SwiftUI can report one edit behind.
    private func commitRouteCompletionOnAcceptKey(draft: String) -> Bool {
        guard completionVisible, completionResponse?.context == "route",
              let completionResponse, let snapshot = completionDraftSnapshot
        else {
            return false
        }
        guard selectedCompletion?.kind != "template" else {
            return false
        }
        if selectedCompletion.map(Self.isRecordCandidate) == true {
            // Record destinations start their field flow only through an
            // explicit accept; `+` and `,` stay literal while the row is open.
            return false
        }

        let r = completionResponse.replacement
        guard let typedRange = stringRange(in: snapshot, byteRange: r) else {
            return false
        }
        let typed = String(snapshot[typedRange])
        guard !typed.isEmpty else {
            return false
        }

        guard let prefixRange = stringRange(in: snapshot, start: 0, end: r.end),
              let suffixRange = stringRange(in: snapshot, start: r.end, end: snapshot.utf8.count)
        else {
            return false
        }
        let prefix = String(snapshot[prefixRange])
        let suffix = String(snapshot[suffixRange])
        let typedKey: String
        if draft == prefix + "+" + suffix {
            typedKey = "+"
        } else if draft == prefix + "," + suffix {
            typedKey = ","
        } else {
            return false
        }

        let exactTypedMatch = completionResponse.candidates.first { candidate in
            guard let route = candidate.route else {
                return false
            }
            return route.caseInsensitiveCompare(typed) == .orderedSame
        }

        if let exactTypedMatch {
            guard !Self.isRecordCandidate(exactTypedMatch) else {
                return false
            }
            guard typedKey == "+" else {
                // An exact route plus comma should go through Bob's rewrite
                // lane, which authors the plus and owns its eligibility.
                return false
            }
            dismissCompletion()
            scheduleAnalysis(cursorUTF8Offset: r.end + 1, requestCompletion: true, trigger: .edit)
            return true
        }

        guard let candidate = selectedCompletion,
              let routeRange = stringRange(in: draft, start: r.start, end: r.end)
        else {
            return false
        }

        var text = draft
        text.replaceSubrange(routeRange, with: candidate.replacement)
        let caret = r.start + candidate.replacement.utf8.count + typedKey.utf8.count
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            return false
        }

        dismissCompletion()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        if typedKey == "," {
            pendingSeparatorToggleIntent = nil
            let completionGate = startCaptureRewrite(
                draft: text,
                cursorUTF8Offset: caret
            )
            scheduleAnalysis(
                cursorUTF8Offset: caret,
                requestCompletion: true,
                trigger: .edit,
                completionGate: completionGate
            )
        } else {
            scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
        }
        return true
    }

    /// True while a close/start draft dangles on a list separator: the visible
    /// card previews the trimmed draft, so Return must not submit it.
    var isClosePending: Bool {
        closePendingText != nil
    }

    /// Carries an explicit submit or submit-and-open gesture through the
    /// analysis required after Bob inserts the accepted completion. The
    /// continuation is tied to that exact draft, client, and analysis.
    private func submitAfterCurrentAnalysis(openAfterCapture: Bool) {
        cancelPendingExplicitSubmit()
        guard let processClient, let analysisTask, hasDraft else {
            return
        }
        let intent = PendingExplicitSubmitIntent(
            draft: plainDraft,
            processClientIdentity: processClient.identityToken,
            analysisGeneration: analysisGeneration,
            openAfterCapture: openAfterCapture
        )
        pendingExplicitSubmitIntent = intent
        pendingExplicitSubmitTask = Task { [weak self, processClient, analysisTask] in
            await analysisTask.value
            guard !Task.isCancelled, let self else {
                return
            }
            self.resumeExplicitSubmit(intent, processClient: processClient)
        }
    }

    /// A held Return is replayed after its buffered edits. Those edits can
    /// start a fresh parse and preview, so keep the explicit submit attached
    /// to that final draft until its analysis completes.
    func submitAfterTypeAheadReplay(openAfterCapture: Bool) {
        if analysisTask != nil {
            submitAfterCurrentAnalysis(openAfterCapture: openAfterCapture)
        } else {
            submit(openAfterCapture: openAfterCapture)
        }
    }

    /// A fast Return after a rewrite-trigger key waits for Bob's answer first.
    /// If Bob replaces the typed dash with `~`, submission then waits for the
    /// analysis and preview of that rewritten draft. Editing or moving the
    /// caret cancels this continuation through the rewrite generation.
    private func waitForRewriteBeforeSubmit(inputDraft: String, openAfterCapture: Bool) {
        guard let processClient else {
            return
        }
        cancelPendingRewriteSubmit()
        pendingRewriteSubmitIntent = PendingRewriteSubmitIntent(
            inputDraft: inputDraft,
            processClientIdentity: processClient.identityToken,
            rewriteGeneration: rewriteGeneration,
            openAfterCapture: openAfterCapture
        )
    }

    private func submitDeferredRewriteAfterAnalysis(
        draft: String,
        generation: UInt64,
        processClient: BobProcessClient
    ) {
        guard isCurrentAnalysis(generation),
              self.processClient === processClient,
              let intent = pendingRewriteSubmitIntent,
              intent.rewriteGeneration == rewriteGeneration,
              intent.inputDraft != draft,
              intent.processClientIdentity == processClient.identityToken,
              completedDeferredRewriteDraft == draft,
              plainDraft == draft,
              hasDraft
        else {
            return
        }
        pendingRewriteSubmitIntent = nil
        completedDeferredRewriteDraft = nil
        submit(openAfterCapture: intent.openAfterCapture)
    }

    private func continueSubmitAfterDeferredRewrite(openAfterCapture: Bool) {
        if analysisTask != nil {
            submitAfterCurrentAnalysis(openAfterCapture: openAfterCapture)
        } else {
            submit(openAfterCapture: openAfterCapture)
        }
    }

    private func resumeExplicitSubmit(
        _ intent: PendingExplicitSubmitIntent,
        processClient: BobProcessClient
    ) {
        guard pendingExplicitSubmitIntent == intent else {
            return
        }
        pendingExplicitSubmitIntent = nil
        pendingExplicitSubmitTask = nil

        guard analysisGeneration == intent.analysisGeneration,
              plainDraft == intent.draft,
              self.processClient === processClient,
              processClient.identityToken == intent.processClientIdentity,
              lastAppliedParseDraft == intent.draft,
              lastAppliedParseGeneration == intent.analysisGeneration,
              lastAppliedParseClientIdentity == intent.processClientIdentity
        else {
            return
        }
        guard CaptureGrammarGate.isCompatible(lastAppliedParseGrammar) else {
            captureGrammarWarning = CaptureGrammarGate.blockedMessage
            statusText = CaptureGrammarGate.blockedMessage
            return
        }
        guard !inlinePromptVisible, !isSubmitting, !isPreviewing, hasDraft else {
            return
        }
        submit(openAfterCapture: intent.openAfterCapture)
    }

    private func cancelPendingExplicitSubmit() {
        pendingExplicitSubmitTask?.cancel()
        pendingExplicitSubmitTask = nil
        pendingExplicitSubmitIntent = nil
    }

    func submit(openAfterCapture: Bool) {
        cancelPendingExplicitSubmit()
        cancelPastBoundaryRefresh()
        clearOpenHintReveal()
        guard !inlinePromptVisible, !isSubmitting, hasDraft else {
            return
        }
        if mergeInNeedsSource {
            statusText = CapturePickerNeed.mergeInSource.statusText
            return
        }
        if let refusal = mergeInRefusalPresentation {
            statusText = refusal.message.text
            return
        }
        if rewriteTask != nil, let deferredRewriteInputDraft {
            waitForRewriteBeforeSubmit(
                inputDraft: deferredRewriteInputDraft,
                openAfterCapture: openAfterCapture
            )
            return
        }
        if completedDeferredRewriteDraft == plainDraft {
            completedDeferredRewriteDraft = nil
            continueSubmitAfterDeferredRewrite(openAfterCapture: openAfterCapture)
            return
        }
        guard !isPreviewing else {
            return
        }
        // A pending card previews the trimmed draft, never the real one: a
        // stale pending card can never be submitted. The footer disables the
        // pending action too; this guard covers Return arriving between drafts.
        if let pending = closePendingText {
            statusText = "\(pending) — \(closePendingAction) is disabled"
            return
        }
        guard let processClient else {
            errorMessage = "Bob is not resolved. Check Settings and Recheck Bob."
            errorCode = nil
            return
        }
        if !captureGrammarAllowsSubmit {
            let knownIncompatible =
                lastAppliedParseDraft == plainDraft
                && lastAppliedParseGeneration == analysisGeneration
                && lastAppliedParseClientIdentity == processClient.identityToken
                && !CaptureGrammarGate.isCompatible(lastAppliedParseGrammar)
            if knownIncompatible {
                captureGrammarWarning = CaptureGrammarGate.blockedMessage
                statusText = CaptureGrammarGate.blockedMessage
            }
            return
        }

        let draft = plainDraft
        // Old-Bob relation gate: the first ⌘↩ on a `~` draft without
        // `relation_grammar` only shows the calm warning; a second ⌘↩ on
        // the same draft submits. New drafts re-arm the gate.
        if draft.contains("~"),
           lastAppliedParseDraft == draft,
           lastRelationGrammar == nil
        {
            if relationCapabilityAcknowledgedDraft != draft {
                relationCapabilityWarning =
                    "This bob predates ~ links; ~ text would be captured literally · update bob"
                relationCapabilityAcknowledgedDraft = draft
                statusText = relationCapabilityWarning ?? statusText
                return
            }
        } else if relationCapabilityAcknowledgedDraft != nil,
                  !draft.contains("~") || lastRelationGrammar != nil
        {
            relationCapabilityAcknowledgedDraft = nil
        }
        let preview = currentPullInPreview(for: draft, processClient: processClient)
        if preview?.moveChoice?.supported != true,
            CaptureMoveChoicePresentation.hasWholeLineMarker(draft)
        {
            if moveChoiceAcknowledgedDraft != draft {
                moveChoiceCapabilityWarning = CaptureMoveChoicePresentation.oldBobWarning
                moveChoiceAcknowledgedDraft = draft
                announceStatus(CaptureMoveChoicePresentation.oldBobWarning)
                return
            }
        }
        if let preview, preview.moveChoice?.supported == true,
            let slot = preview.moveChoice?.slots.first(where: { !$0.answered })
        {
            openMoveChoice(slot: slot, preview: preview, openAfterCapture: openAfterCapture)
            return
        }
        continueSubmit(draft: draft, openAfterCapture: openAfterCapture, preview: preview)
    }

    private func continueSubmit(
        draft: String,
        openAfterCapture: Bool,
        preview: CapturePullInPreviewSnapshot?,
        moveInSelection: String? = nil
    ) {
        guard let processClient else { return }
        if let preview,
            preview.pullIn?.supported == true,
            preview.offers.contains(where: { $0.offer.map { !$0.key.isEmpty } == true })
        {
            _ = openPullInChoice(
                offers: preview.offers,
                stillBlocked: preview.stillBlocked,
                pullIn: preview.pullIn!,
                planBudget: preview.planBudget,
                draft: draft,
                processClientIdentity: preview.clientIdentity,
                openAfterCapture: openAfterCapture,
                seed: preview.seed,
                generation: preview.generation,
                requestID: preview.requestID,
                moveInSelection: moveInSelection
            )
            return
        }
        if let preview,
           let inboxRoute = preview.inboxRoute,
           inboxRoute.supported,
           !inboxRoute.candidates.isEmpty
        {
            let context = CaptureInboxRouteSubmitContext(
                choice: CaptureInboxRouteChoiceState(
                    candidates: inboxRoute.candidates,
                    destinations: inboxRoute.destinations ?? []
                ),
                draft: draft,
                clientIdentity: preview.clientIdentity,
                openAfterCapture: openAfterCapture,
                seed: preview.seed,
                generation: preview.generation,
                requestID: preview.requestID,
                pullInSelection: nil,
                pullInChoiceForBack: nil,
                pullInCapabilityAdvertised: preview.pullIn?.supported == true,
                offerVerdicts: nil,
                offerCloseCapabilityAdvertised: preview.pullIn?.close?.supported == true,
                inboxRouteCapabilityAdvertised: true,
                hasOverride: preview.hasOverride,
                vaultDirectoryIdentity: processClient.vaultDirectoryIdentity,
                moveInSelection: moveInSelection,
                moveInCapabilityAdvertised: preview.moveChoice?.supported == true
            )
            if openInboxRouteChoice(inboxRoute, context: context) {
                return
            }
        }
        // Positive capability gate (bob-cli-8a): `--require-pull-in-choice`
        // goes out only after a preview from this same executable advertised
        // `pull_in.supported`. Without that proof no flag is sent, so an
        // older bob files the clean draft instead of a junk flag task.
        let capabilityAdvertised = preview?.pullIn?.supported == true
        dispatchCapture(
            draft: draft,
            openAfterCapture: openAfterCapture,
            selection: nil,
            capabilityAdvertised: capabilityAdvertised,
            seed: preview?.seed ?? activePriorityRollSeed(),
            inboxRouteCapabilityAdvertised: preview?.inboxRoute?.supported == true,
            moveInSelection: moveInSelection,
            moveInCapabilityAdvertised: preview?.moveChoice?.supported == true
        )
    }

    private func dispatchCapture(
        draft: String,
        openAfterCapture: Bool,
        selection: CapturePullInSelection?,
        capabilityAdvertised: Bool,
        seed: String,
        inboxRouteAnswers: [CaptureInboxRouteSubmission]? = nil,
        inboxRouteCapabilityAdvertised: Bool = false,
        routeContext: CaptureInboxRouteSubmitContext? = nil,
        pullInChoiceForBack: CapturePullInChoiceState? = nil,
        moveInSelection: String? = nil,
        moveInCapabilityAdvertised: Bool = false,
        offerVerdicts: CapturePullInOfferVerdicts? = nil,
        offerCloseCapabilityAdvertised: Bool = false
    ) {
        cancelSimilarTasks(clear: true)
        guard let processClient else {
            errorMessage = "Bob is not resolved. Check Settings and Recheck Bob."
            errorCode = nil
            return
        }
        let matchingPreview = currentPullInPreview(for: draft, processClient: processClient)
        let allowsOverride = routeContext?.hasOverride ?? (matchingPreview?.hasOverride == true)
        let submitContext = routeContext ?? CaptureInboxRouteSubmitContext(
            choice: CaptureInboxRouteChoiceState(),
            draft: draft,
            clientIdentity: processClient.identityToken,
            openAfterCapture: openAfterCapture,
            seed: seed,
            generation: matchingPreview?.generation ?? analysisGeneration,
            requestID: matchingPreview?.requestID,
            pullInSelection: selection,
            pullInChoiceForBack: pullInChoiceForBack,
            pullInCapabilityAdvertised: capabilityAdvertised
                || matchingPreview?.pullIn?.supported == true,
            offerVerdicts: offerVerdicts,
            offerCloseCapabilityAdvertised: offerCloseCapabilityAdvertised
                || matchingPreview?.pullIn?.close?.supported == true,
            inboxRouteCapabilityAdvertised: inboxRouteCapabilityAdvertised
                || matchingPreview?.inboxRoute?.supported == true,
            hasOverride: allowsOverride,
            vaultDirectoryIdentity: processClient.vaultDirectoryIdentity,
            moveInSelection: moveInSelection,
            moveInCapabilityAdvertised: moveInCapabilityAdvertised
        )
        activeInboxRouteSubmitContext = submitContext
        retireAliasTipDisplayEligibility()
        invalidateRewrite()
        let expectPastWindows = expectedPastWindows(for: draft, processClient: processClient)
        let requestID = UUID()
        let processClientIdentity = processClient.identityToken
        activeRequestID = requestID
        isSubmitting = true
        errorMessage = nil
        errorCode = nil
        statusText = openAfterCapture ? "Capturing and opening\u{2026}" : "Capturing\u{2026}"
        Task { [weak self, processClient] in
            do {
                let response = try await CaptureSignpost.measure("submit") {
                    try await processClient.capture(
                        draft,
                        dryRun: false,
                        readClipboard: true,
                        priorityRollSeed: seed,
                        moveInSelection: submitContext.moveInSelection,
                        moveInCapabilityAdvertised: submitContext.moveInCapabilityAdvertised,
                        pullInSelection: selection,
                        offerVerdicts: submitContext.offerVerdicts,
                        requirePullInChoice: selection == nil && inboxRouteAnswers == nil,
                        refuseOverride: !allowsOverride,
                        pullInCapabilityAdvertised: capabilityAdvertised,
                        offerCloseCapabilityAdvertised: submitContext
                            .offerCloseCapabilityAdvertised,
                        inboxRouteAnswers: inboxRouteAnswers,
                        requireInboxRouteChoice: true,
                        inboxRouteCapabilityAdvertised: submitContext.inboxRouteCapabilityAdvertised,
                        templateOrigin: currentDraftHasTemplate ? templateOrigin : nil,
                        expectPastWindows: expectPastWindows
                    )
                }
                await MainActor.run {
                    self?.completeSubmit(
                        requestID: requestID,
                        response: response,
                        openAfterCapture: openAfterCapture,
                        draft: draft,
                        choiceSeed: seed,
                        processClientIdentity: processClientIdentity
                    )
                }
            } catch {
                await MainActor.run {
                    self?.failSubmit(requestID: requestID, error: error)
                }
            }
        }
    }

    /// Build Bob's stale-preview token only when the latest parse and preview
    /// both describe this exact draft from the same executable. Older Bob
    /// treats unknown flags as capture text, so grammar 14 is a positive
    /// capability proof, not a best-effort hint.
    private func expectedPastWindows(
        for draft: String,
        processClient: BobProcessClient
    ) -> String? {
        guard (latestParse?.grammar ?? 0) >= 14,
              lastAppliedParseDraft == draft,
              lastAppliedParseGeneration == analysisGeneration,
              lastAppliedParseClientIdentity == processClient.identityToken,
              previewOutputsDraft == draft,
              currentPullInPreview(for: draft, processClient: processClient) != nil
        else {
            return nil
        }
        let past = previewResults.filter { $0.kind == "pomodoro_past" }
        guard !past.isEmpty else {
            return nil
        }
        let windows = past.compactMap { capture -> String? in
            guard let window = capture.pomodoroPast?.window,
                  !window.start.isEmpty,
                  !window.end.isEmpty
            else {
                return nil
            }
            return "\(window.start)-\(window.end)"
        }
        guard windows.count == past.count else {
            return nil
        }
        return windows.joined(separator: ",")
    }

    private func openMoveChoice(
        slot: CaptureMoveChoiceSlot,
        preview: CapturePullInPreviewSnapshot,
        openAfterCapture: Bool,
        stale: Bool = false,
        needsPreview: Bool = false
    ) {
        var state =
            rememberedMoveChoice?.slot.parent == slot.parent
            ? rememberedMoveChoice! : CaptureMoveChoiceState(slot: slot)
        let lost = state.reseed(slot: slot)
        rememberedMoveChoice = state
        moveChoice = state
        moveChoiceContext = CaptureMoveChoiceSubmitContext(
            preview: preview, openAfterCapture: openAfterCapture, needsPreview: needsPreview
        )
        moveChoiceMessage =
            stale
            ? "\(slot.parent) changed · \(lost) marked task\(lost == 1 ? " is" : "s are") gone"
            : nil
        moveChoiceCapabilityWarning = nil
        pullInChoice = nil
        inboxRouteChoice = nil
        inboxRouteChoiceContext = nil
        editorInputLocked = true
        completionResponse = nil
        pickerChip = nil
        errorMessage = nil
        errorCode = nil
        requestFocus(.moveChoiceRows)
        announceStatus(moveChoiceMessage ?? CaptureMoveChoicePresentation.title(for: slot))
    }

    var moveChoiceTodayBadge: TodayBadgePresentation? {
        guard let budget = moveChoiceContext?.preview.planBudget else { return nil }
        return TodayBadgePresentation(
            count: budget.links.count + (moveChoice?.linkedCount ?? 0), cap: budget.links.cap
        )
    }

    func updateMoveChoice(_ state: CaptureMoveChoiceState) {
        moveChoice = state
        rememberedMoveChoice = state
    }

    func updateMoveChoiceFilter(_ text: String) {
        guard var state = moveChoice else { return }
        state.updateFilter(text)
        updateMoveChoice(state)
    }

    func editMoveChoiceFilter(_ text: String?) {
        guard let state = moveChoice else { return }
        updateMoveChoiceFilter(
            text.map { state.filterText + $0 } ?? String(state.filterText.dropLast()))
        requestFocus(.moveChoiceFilter)
    }

    func moveMoveChoiceHighlight(by delta: Int) {
        guard var state = moveChoice else { return }
        state.moveHighlight(by: delta)
        updateMoveChoice(state)
        requestFocus(.moveChoiceRows)
    }

    func setMoveChoiceAnswer(_ answer: CaptureMoveChoiceAnswer) {
        guard var state = moveChoice else { return }
        if !state.answerCurrent(answer) {
            announceStatus(
                state.currentRow?.disabledReason
                    ?? state.currentRow.flatMap(CaptureMoveChoicePresentation.lockText)
                    ?? "This task cannot move")
        }
        updateMoveChoice(state)
        requestFocus(.moveChoiceRows)
    }

    func toggleMoveChoice() {
        guard var state = moveChoice else { return }
        _ = state.toggleCurrent()
        updateMoveChoice(state)
    }

    func selectAllMoveChoices() {
        guard var state = moveChoice else { return }
        state.selectAll()
        updateMoveChoice(state)
    }

    func confirmMoveChoice(none: Bool = false, openAfterCapture: Bool = false) {
        guard let state = moveChoice, let context = moveChoiceContext,
            let processClient, !isSubmitting, !isPreviewing,
            context.preview.draft == plainDraft,
            context.preview.clientIdentity == processClient.identityToken,
            context.preview.generation == analysisGeneration
        else { return }
        if let message = state.nameRequirementMessage {
            moveChoiceMessage = message
            announceStatus(message)
            return
        }
        if none && state.slot.nameNeedsLink {
            let empty = CaptureMoveChoiceState(slot: state.slot)
            moveChoiceMessage = empty.nameRequirementMessage
            announceStatus(moveChoiceMessage ?? "Choose a : pick first")
            return
        }
        guard none || state.canConfirm else {
            moveChoiceMessage = "Mark tasks with ^ or :"
            announceStatus("Mark tasks with ^ or :")
            return
        }
        rememberedMoveChoice = state
        moveChoice = nil
        clearEditorInputLockIfFree()
        let shouldOpen = context.openAfterCapture || openAfterCapture
        moveChoiceContext?.openAfterCapture = shouldOpen
        if context.needsPreview {
            refreshMoveChoiceBeforeSubmit(
                context: context, selection: none ? "none" : state.selection,
                openAfterCapture: shouldOpen, processClient: processClient
            )
            return
        }
        continueSubmit(
            draft: context.preview.draft, openAfterCapture: shouldOpen,
            preview: context.preview, moveInSelection: none ? "none" : state.selection
        )
    }

    /// Move refusals may carry only fresh move rows. Refresh the answered preview
    /// before continuing so Pull-In and inbox routing still get their own capability
    /// evidence and offers; no write is attempted using missing follow-on metadata.
    private func refreshMoveChoiceBeforeSubmit(
        context: CaptureMoveChoiceSubmitContext,
        selection: String,
        openAfterCapture: Bool,
        processClient: BobProcessClient
    ) {
        let previous = context.preview
        let requestID = UUID()
        activeRequestID = requestID
        isPreviewing = true
        editorInputLocked = true
        statusText = "Refreshing move choices…"
        Task { [weak self] in
            do {
                let response = try await processClient.capture(
                    previous.draft, dryRun: true, priorityRollSeed: previous.seed,
                    moveInSelection: selection, moveInCapabilityAdvertised: true
                )
                guard let self, self.activeRequestID == requestID else { return }
                self.isPreviewing = false
                self.clearEditorInputLockIfFree()
                guard self.plainDraft == previous.draft,
                    self.analysisGeneration == previous.generation,
                    self.processClient?.identityToken == previous.clientIdentity
                else {
                    self.activeRequestID = nil
                    return
                }
                switch response {
                case .success(let success):
                    self.activeRequestID = nil
                    let preview = self.makePullInPreviewSnapshot(
                        success: success, captures: success.normalizedCaptures,
                        draft: previous.draft, processClientIdentity: previous.clientIdentity,
                        seed: previous.seed, generation: previous.generation, requestID: requestID
                    )
                    self.moveChoiceContext = CaptureMoveChoiceSubmitContext(
                        preview: preview, openAfterCapture: openAfterCapture
                    )
                    self.continueSubmit(
                        draft: previous.draft, openAfterCapture: openAfterCapture,
                        preview: preview, moveInSelection: selection
                    )
                case .failure:
                    self.completeSubmit(
                        requestID: requestID, response: response,
                        openAfterCapture: openAfterCapture, draft: previous.draft,
                        choiceSeed: previous.seed, processClientIdentity: previous.clientIdentity
                    )
                }
            } catch {
                guard let self, self.activeRequestID == requestID else { return }
                self.isPreviewing = false
                self.clearEditorInputLockIfFree()
                self.failSubmit(requestID: requestID, error: error)
            }
        }
    }

    func cancelMoveChoice() {
        if let moveChoice { rememberedMoveChoice = moveChoice }
        moveChoice = nil
        moveChoiceContext = nil
        clearEditorInputLockIfFree()
        requestFocus(.editor)
        announceStatus("Move choice canceled")
    }

    private func restoreMoveChoiceForBack() -> Bool {
        guard let context = moveChoiceContext, let state = rememberedMoveChoice,
            context.preview.draft == plainDraft,
            context.preview.clientIdentity == processClient?.identityToken,
            context.preview.generation == analysisGeneration
        else { return false }
        moveChoice = state
        editorInputLocked = true
        requestFocus(.moveChoiceRows)
        announceStatus(CaptureMoveChoicePresentation.title(for: state.slot))
        return true
    }

    private func invalidateMoveChoiceForEdit(_ draft: String) {
        if draft != moveChoiceAcknowledgedDraft {
            moveChoiceAcknowledgedDraft = nil
            moveChoiceCapabilityWarning = nil
        }
        if moveChoiceContext?.preview.draft != draft {
            if let moveChoice { rememberedMoveChoice = moveChoice }
            moveChoice = nil
            moveChoiceContext = nil
            clearEditorInputLockIfFree()
        }
        if draft.isEmpty { resetMoveChoice() }
    }

    private func resetMoveChoice() {
        moveChoice = nil
        moveChoiceContext = nil
        rememberedMoveChoice = nil
        moveChoiceMessage = nil
        moveChoiceAcknowledgedDraft = nil
        moveChoiceCapabilityWarning = nil
    }

    private func currentPullInPreview(
        for draft: String,
        processClient: BobProcessClient
    ) -> CapturePullInPreviewSnapshot? {
        guard let previewPullInSnapshot,
              previewPullInSnapshot.draft == draft,
              previewPullInSnapshot.clientIdentity == processClient.identityToken,
              previewPullInSnapshot.generation == analysisGeneration
        else {
            return nil
        }
        return previewPullInSnapshot
    }

    private func openPullInChoice(
        offers: [TaskCompleteUnblocked],
        stillBlocked: [TaskCompleteStillBlocked],
        pullIn: CapturePullIn,
        planBudget: CapturePlanBudget?,
        draft: String,
        processClientIdentity: String,
        openAfterCapture: Bool,
        seed: String,
        generation: UInt64,
        requestID: UUID?,
        moveInSelection: String? = nil
    ) -> Bool {
        guard pullIn.supported else {
            return false
        }
        let unique = Self.uniquePullInRows(offers)
        guard unique.contains(where: { $0.offer?.key.isEmpty == false }) else {
            errorMessage = "Bob requested a successor choice but returned no usable offer keys. Preview again before submitting."
            errorCode = nil
            statusText = "Successor offers need refresh"
            return false
        }
        let rows = unique.compactMap { item -> CapturePullInChoiceRow? in
            guard let offer = item.offer, !offer.key.isEmpty else {
                return nil
            }
            return CapturePullInChoiceRow(
                offerRow: item,
                blockedRow: nil,
                group: offer.group,
                project: offer.project
            )
        } + stillBlocked.map { item in
            CapturePullInChoiceRow(
                offerRow: nil,
                blockedRow: item,
                group: item.project == nil ? "" : "project",
                project: item.project
            )
        }
        let firstKey = unique
            .filter { $0.offer?.key.isEmpty == false }
            .sorted { ($0.offer?.n ?? .max) < ($1.offer?.n ?? .max) }
            .first?.offer?.key
        pullInChoice = CapturePullInChoiceState(
            moveInSelection: moveInSelection,
            draftSnapshot: draft,
            processClientIdentity: processClientIdentity,
            openAfterCapture: openAfterCapture,
            priorityRollSeed: seed,
            generation: generation,
            requestID: requestID,
            pullIn: pullIn,
            planBudget: planBudget,
            rows: rows,
            highlightedKey: firstKey
        )
        editorInputLocked = true
        completionResponse = nil
        pickerChip = nil
        statusText = pullInChoice?.promptStatusText ?? "Choose successor offers"
        requestFocus(.pullInOfferList)
        return true
    }

    private static func uniquePullInRows(_ offers: [TaskCompleteUnblocked]) -> [TaskCompleteUnblocked] {
        var seen = Set<String>()
        return offers.filter { row in
            guard let key = row.offer?.key, !key.isEmpty else {
                return false
            }
            return seen.insert(key).inserted
        }.sorted {
            let left = $0.offer?.n ?? .max
            let right = $1.offer?.n ?? .max
            return left == right ? ($0.offer?.key ?? "") < ($1.offer?.key ?? "") : left < right
        }
    }

    private static let inboxRouteLastUsedDestinationKeyPrefix = "inboxRouteLastUsedDestination."

    private static func inboxRouteLastUsedDestinationKey(vaultDirectoryIdentity: String) -> String {
        let hash = vaultDirectoryIdentity.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return inboxRouteLastUsedDestinationKeyPrefix + String(hash, radix: 16)
    }

    private func lastUsedInboxRouteDestination(vaultDirectoryIdentity: String) -> String? {
        UserDefaults.standard.string(
            forKey: Self.inboxRouteLastUsedDestinationKey(
                vaultDirectoryIdentity: vaultDirectoryIdentity
            )
        )
    }

    private func rememberInboxRouteDestination(
        _ destination: String,
        vaultDirectoryIdentity: String
    ) {
        UserDefaults.standard.set(
            destination,
            forKey: Self.inboxRouteLastUsedDestinationKey(
                vaultDirectoryIdentity: vaultDirectoryIdentity
            )
        )
    }

    private func openInboxRouteChoice(
        _ report: CaptureInboxRoute,
        context: CaptureInboxRouteSubmitContext,
        refused: CaptureInboxRouteRefused? = nil,
        refusalMessage: String? = nil
    ) -> Bool {
        guard report.supported, !report.candidates.isEmpty else {
            return false
        }

        var nextContext = context
        var choice = context.choice
        choice.reseed(
            candidates: report.candidates,
            destinations: report.destinations ?? []
        )
        if let refused {
            choice.reopenAtRefusedKey(refused.key, message: refused.message)
        } else if let refusalMessage, let current = choice.currentCandidate {
            choice.reopenAtRefusedKey(current.key, message: refusalMessage)
        } else {
            choice.refusalMessage = nil
            choice.refusedKey = nil
            choice.filterText = ""
            choice.cursor = choice.candidates.firstIndex { choice.answers[$0.key] == nil } ?? 0
            let previousDestination = choice.cursor > 0
                ? Self.routeDestination(for: choice.answers[choice.candidates[choice.cursor - 1].key])
                : nil
            choice.applyInitialHighlight(
                previousAnswerDestination: previousDestination,
                lastUsedDestination: lastUsedInboxRouteDestination(
                    vaultDirectoryIdentity: context.vaultDirectoryIdentity
                )
            )
        }

        nextContext.choice = choice
        inboxRouteChoiceContext = nextContext
        inboxRouteChoice = choice
        editorInputLocked = true
        completionResponse = nil
        pickerChip = nil
        requestFocus(.inboxRouteFilter)
        if let refused {
            announceStatus(refused.message)
        } else if let refusalMessage {
            announceStatus(refusalMessage)
        } else if let candidate = choice.currentCandidate {
            announceStatus("Route out of \(candidate.inbox). \(choice.candidates.count) inbox task\(choice.candidates.count == 1 ? "" : "s")")
        }
        return true
    }

    private static func routeDestination(
        for decision: CaptureInboxRouteDecision?
    ) -> String? {
        guard case .move(let destination)? = decision else {
            return nil
        }
        return destination
    }

    private func updateInboxRouteChoice(_ choice: CaptureInboxRouteChoiceState) {
        inboxRouteChoice = choice
        if var context = inboxRouteChoiceContext {
            context.choice = choice
            inboxRouteChoiceContext = context
        }
    }

    private func inboxRouteContextIsCurrent(_ context: CaptureInboxRouteSubmitContext) -> Bool {
        plainDraft == context.draft
            && processClient?.identityToken == context.clientIdentity
            && context.generation == analysisGeneration
    }

    private func showReseededPullInChoice(
        _ choice: CapturePullInChoiceState,
        error: String,
        lostCount: Int,
        status: String? = nil
    ) {
        var next = choice
        next.verdictRefusalMessage = error
        next.errorMessage = error
        pullInChoice = next
        editorInputLocked = true
        completionResponse = nil
        pickerChip = nil
        requestFocus(.pullInOfferList)
        let announcement: String
        if let status {
            announcement = status
        } else if lostCount > 0 {
            announcement =
                "\(error) · \(lostCount) staged choice\(lostCount == 1 ? "" : "s") lost"
        } else {
            announcement = error
        }
        announceStatus(announcement)
    }

    private func reopenPullInChoiceAfterOfferRefusal(
        failure: CaptureCommandFailure,
        draft: String,
        processClientIdentity: String,
        openAfterCapture: Bool,
        choiceSeed: String,
        remembered: CapturePullInChoiceState?
    ) -> Bool {
        guard plainDraft == draft,
            processClient?.identityToken == processClientIdentity
        else {
            return false
        }
        guard var choice = remembered else {
            return false
        }
        // Refresh row data/descriptors from Bob, preserving marks, verdicts,
        // reasons, and highlight. Removed keys are dropped and counted.
        // Keep the original capability proof; fresh descriptors arrive via
        // the refreshed offers. Never silently discard a still-present
        // staged verdict: it stays visible with Bob's error until changed.
        if !failure.offers.isEmpty {
            let lost = choice.refresh(offers: failure.offers)
            showReseededPullInChoice(choice, error: failure.error, lostCount: lost)
            return true
        }
        // No structured offers: fall through to the dry-run refresh path.
        return reopenPullInChoiceAfterStalePick(
            failure: failure,
            draft: draft,
            processClientIdentity: processClientIdentity,
            openAfterCapture: openAfterCapture,
            choiceSeed: choiceSeed,
            remembered: remembered)
    }

    private func reopenPullInChoiceAfterStalePick(
        failure: CaptureCommandFailure,
        draft: String,
        processClientIdentity: String,
        openAfterCapture: Bool,
        choiceSeed: String,
        remembered: CapturePullInChoiceState?
    ) -> Bool {
        guard plainDraft == draft,
            let processClient,
            processClient.identityToken == processClientIdentity
        else {
            return false
        }
        guard let remembered else {
            return false
        }
        // Write-free refusal: at most one fresh dry-run of the same guarded
        // draft/seed to obtain authoritative rows. Never retry the write.
        isPreviewing = true
        statusText = "Refreshing successor offers…"
        let generation = analysisGeneration
        let requestID = UUID()
        Task { [weak self, processClient] in
            do {
                let response = try await processClient.capture(
                    draft,
                    dryRun: true,
                    readClipboard: true,
                    priorityRollSeed: choiceSeed)
                await MainActor.run {
                    guard let self else { return }
                    let sameGeneration = self.analysisGeneration == generation
                    if sameGeneration {
                        self.isPreviewing = false
                    }
                    guard sameGeneration,
                        self.plainDraft == draft,
                        self.processClient?.identityToken == processClientIdentity
                    else {
                        return
                    }
                    switch response {
                    case .success(let success):
                        var choice = remembered
                        var offers: [TaskCompleteUnblocked] = []
                        for capture in success.normalizedCaptures {
                            if let complete = capture.taskComplete {
                                offers.append(contentsOf: complete.unblocked)
                                offers.append(contentsOf: complete.keepMoving)
                            }
                            if let close = capture.pomodoroClose {
                                offers.append(contentsOf: close.unblocked)
                                offers.append(contentsOf: close.keepMoving)
                            }
                            if let past = capture.pomodoroPast {
                                offers.append(contentsOf: past.close.unblocked)
                                offers.append(contentsOf: past.close.keepMoving)
                            }
                            if let projectNote = capture.projectNote,
                                projectNote.form == "offer"
                            {
                                offers.append(contentsOf: projectNote.successors)
                            }
                            offers.append(contentsOf: capture.allNotePullRows)
                            for relationComplete in capture.relationCompletes {
                                guard let complete = relationComplete.taskComplete else {
                                    continue
                                }
                                offers.append(contentsOf: complete.unblocked)
                                offers.append(contentsOf: complete.keepMoving)
                            }
                        }
                        if offers.isEmpty {
                            // Refresh with no offers: empty recovery state,
                            // route back to the draft, no enabled commit.
                            self.pullInChoice = nil
                            self.errorMessage = failure.error
                            self.errorCode = failure.code
                            self.statusText = failure.error
                            self.announceStatus(
                                "\(failure.error) · no offers remain")
                            return
                        }
                        let lost = choice.refresh(offers: offers)
                        self.showReseededPullInChoice(
                            choice, error: failure.error, lostCount: lost)
                    case .failure(let refreshFailure):
                        self.showReseededPullInChoice(
                            remembered,
                            error: failure.error,
                            lostCount: 0,
                            status: "\(failure.error) · refresh failed: \(refreshFailure.error)")
                        self.errorMessage = failure.error
                        self.errorCode = failure.code
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    let sameGeneration = self.analysisGeneration == generation
                    if sameGeneration {
                        self.isPreviewing = false
                    }
                    guard sameGeneration,
                        self.plainDraft == draft,
                        self.processClient?.identityToken == processClientIdentity
                    else {
                        return
                    }
                    // Timeout/unknown outcome is never a write-free refusal:
                    // keep the error and remembered choices available.
                    self.showReseededPullInChoice(
                        remembered, error: failure.error, lostCount: 0)
                    self.errorMessage = failure.error
                    self.errorCode = failure.code
                }
            }
        }
        return true
    }

    func updateInboxRouteChoiceFilter(_ text: String) {
        guard var choice = inboxRouteChoice else {
            return
        }
        choice.filterText = text
        updateInboxRouteChoice(choice)
    }

    func focusInboxRouteChoiceFilter() {
        requestFocus(.inboxRouteFilter)
    }

    func moveInboxRouteDestinationHighlight(by delta: Int) {
        guard var choice = inboxRouteChoice else {
            return
        }
        let previous = choice.highlightedRow?.relativePath
        if delta < 0 {
            choice.moveHighlightBackward()
        } else {
            choice.moveHighlightForward()
        }
        let highlighted = choice.highlightedRow
        updateInboxRouteChoice(choice)
        requestFocus(.inboxRouteRows)
        if let highlighted, highlighted.relativePath != previous {
            announceStatus(CaptureInboxRoutePresentation.rowText(destination: highlighted))
        }
    }

    func selectInboxRouteDestination(_ path: String) {
        guard var choice = inboxRouteChoice,
              choice.destinations.contains(where: { $0.relativePath == path })
        else {
            return
        }
        choice.highlightedDestination = path
        updateInboxRouteChoice(choice)
        requestFocus(.inboxRouteRows)
        if let destination = choice.highlightedRow {
            announceStatus(CaptureInboxRoutePresentation.rowText(destination: destination))
        }
    }

    func confirmInboxRouteChoice(openAfterCapture: Bool = false) {
        guard var choice = inboxRouteChoice,
              var context = inboxRouteChoiceContext,
              !isSubmitting
        else {
            return
        }
        guard inboxRouteContextIsCurrent(context) else {
            discardInboxRouteChoiceForInvalidation()
            return
        }
        guard choice.currentCandidate != nil,
              let destination = choice.highlightedRow
        else {
            announceStatus("No matching destinations")
            return
        }

        if openAfterCapture {
            context.openAfterCapture = true
        }
        let advanced = choice.answerMoveCurrent(destination: destination.relativePath)
        rememberInboxRouteDestination(
            destination.relativePath,
            vaultDirectoryIdentity: context.vaultDirectoryIdentity
        )
        context.choice = choice
        if advanced {
            choice.applyInitialHighlight(
                previousAnswerDestination: destination.relativePath,
                lastUsedDestination: lastUsedInboxRouteDestination(
                    vaultDirectoryIdentity: context.vaultDirectoryIdentity
                )
            )
            context.choice = choice
            updateInboxRouteChoice(choice)
            inboxRouteChoiceContext = context
            requestFocus(.inboxRouteFilter)
            if let next = choice.currentCandidate {
                announceStatus(
                    CaptureInboxRoutePresentation.contextLine(
                        candidate: next,
                        index: choice.cursor,
                        total: choice.candidates.count
                    )
                )
            }
            return
        }
        guard choice.isComplete else {
            announceStatus("Route choice is incomplete")
            return
        }
        context.choice = choice
        inboxRouteChoice = nil
        inboxRouteChoiceContext = nil
        clearEditorInputLockIfFree()
        submitInboxRouteAnswers(context)
    }

    func keepInboxRouteCandidate() {
        guard var choice = inboxRouteChoice,
              var context = inboxRouteChoiceContext,
              !isSubmitting
        else {
            return
        }
        guard inboxRouteContextIsCurrent(context) else {
            discardInboxRouteChoiceForInvalidation()
            return
        }
        guard choice.currentCandidate != nil else {
            return
        }
        let advanced = choice.answerKeepCurrent()
        context.choice = choice
        if advanced {
            choice.applyInitialHighlight(
                previousAnswerDestination: nil,
                lastUsedDestination: lastUsedInboxRouteDestination(
                    vaultDirectoryIdentity: context.vaultDirectoryIdentity
                )
            )
            context.choice = choice
            updateInboxRouteChoice(choice)
            inboxRouteChoiceContext = context
            requestFocus(.inboxRouteFilter)
            if let next = choice.currentCandidate {
                announceStatus(
                    CaptureInboxRoutePresentation.contextLine(
                        candidate: next,
                        index: choice.cursor,
                        total: choice.candidates.count
                    )
                )
            }
            return
        }
        guard choice.isComplete else {
            announceStatus("Route choice is incomplete")
            return
        }
        context.choice = choice
        inboxRouteChoice = nil
        inboxRouteChoiceContext = nil
        clearEditorInputLockIfFree()
        submitInboxRouteAnswers(context)
    }

    private func submitInboxRouteAnswers(_ context: CaptureInboxRouteSubmitContext) {
        guard inboxRouteContextIsCurrent(context) else {
            discardInboxRouteChoiceForInvalidation()
            return
        }
        let answers = context.choice.answersForSubmit
        guard answers.count == context.choice.candidates.count else {
            announceStatus("Route choice is incomplete")
            return
        }
        dispatchCapture(
            draft: context.draft,
            openAfterCapture: context.openAfterCapture,
            selection: context.pullInSelection,
            capabilityAdvertised: context.pullInCapabilityAdvertised,
            seed: context.seed,
            inboxRouteAnswers: answers,
            inboxRouteCapabilityAdvertised: context.inboxRouteCapabilityAdvertised,
            routeContext: context
        )
    }

    func backInboxRouteChoice() {
        guard var choice = inboxRouteChoice,
              let context = inboxRouteChoiceContext
        else {
            return
        }
        if choice.goBack() {
            updateInboxRouteChoice(choice)
            requestFocus(.inboxRouteFilter)
            if let candidate = choice.currentCandidate {
                announceStatus(
                    CaptureInboxRoutePresentation.contextLine(
                        candidate: candidate,
                        index: choice.cursor,
                        total: choice.candidates.count
                    )
                )
            }
            return
        }

        inboxRouteChoice = nil
        inboxRouteChoiceContext = nil
        if let pullInChoice = context.pullInChoiceForBack,
           inboxRouteContextIsCurrent(context)
        {
            self.pullInChoice = pullInChoice
            editorInputLocked = true
            requestFocus(.pullInOfferList)
            announceStatus(pullInChoice.promptStatusText)
        } else if !restoreMoveChoiceForBack() {
            clearEditorInputLockIfFree()
            requestFocus(.editor)
            announceStatus("Inbox route choice canceled")
        }
    }

    private func discardInboxRouteChoiceForInvalidation() {
        inboxRouteChoice = nil
        inboxRouteChoiceContext = nil
        activeInboxRouteSubmitContext = nil
        clearEditorInputLockIfFree()
        requestFocus(.editor)
    }

    func confirmPullInChoice() {
        confirmPullInChoice(openAfterCapture: false)
    }

    func confirmPullInChoice(openAfterCapture: Bool) {
        clearOpenHintReveal()
        guard var choice = pullInChoice, !isSubmitting else {
            return
        }
        // An active reason edit confirms first; blur also confirms once.
        if choice.activeReasonKey != nil {
            choice.confirmOfferCancel()
            pullInChoice = choice
            announceStatus(choice.consequenceMessage ?? "Cancel staged")
            requestFocus(.pullInOfferList)
        }
        let selection = pullInSelectionForCommit(choice)
        let verdicts = choice.outcomes.argvSelection().offerVerdicts
        guard !selectionKeys(selection).isEmpty || !verdicts.isEmpty else {
            announceStatus("No visible successor offer is selected")
            return
        }
        if openAfterCapture {
            choice.openAfterCapture = true
            pullInChoice = choice
        }
        commitPullInChoice(choice, selection: selection)
    }

    private func pullInSelectionForCommit(_ choice: CapturePullInChoiceState) -> CapturePullInSelection {
        let keys = choice.effectiveSelectionKeys
        return keys.isEmpty ? .none : .keys(keys)
    }

    private func selectionKeys(_ selection: CapturePullInSelection) -> [String] {
        switch selection {
        case .keys(let keys):
            return keys
        case .none:
            return []
        }
    }

    func chooseNoPullInOffers() {
        guard var choice = pullInChoice, !isSubmitting else {
            return
        }
        if choice.activeReasonKey != nil {
            choice.confirmOfferCancel()
            pullInChoice = choice
        }
        if choice.isOnlyNotePull, choice.closeCount == 0 {
            announceStatus("Escape returns to the draft without pulling in")
            return
        }
        // Shift-Return sends explicit .none and retains every verdict.
        commitPullInChoice(choice, selection: .none)
    }

    private func commitPullInChoice(
        _ choice: CapturePullInChoiceState,
        selection: CapturePullInSelection
    ) {
        guard plainDraft == choice.draftSnapshot,
              processClient?.identityToken == choice.processClientIdentity,
              choice.generation == analysisGeneration,
              choice.pullIn.supported
        else {
            dismissPullInChoice(status: "Successor choice canceled")
            return
        }
        // Never emit verdicts without the matching preview capability proof.
        let verdicts: CapturePullInOfferVerdicts? = {
            let built = choice.outcomes.argvSelection().offerVerdicts
            guard !built.isEmpty, choice.pullIn.close?.supported == true else {
                return nil
            }
            return built
        }()
        pullInChoice = nil
        clearEditorInputLockIfFree()
        dispatchCapture(
            draft: choice.draftSnapshot,
            openAfterCapture: choice.openAfterCapture,
            selection: selection,
            capabilityAdvertised: choice.pullIn.supported,
            seed: choice.priorityRollSeed,
            inboxRouteCapabilityAdvertised: processClient?.inboxRouteCapabilityKnown == true,
            pullInChoiceForBack: choice,
            moveInSelection: choice.moveInSelection,
            moveInCapabilityAdvertised: choice.moveInSelection != nil,
            offerVerdicts: verdicts,
            offerCloseCapabilityAdvertised: choice.pullIn.close?.supported == true
        )
    }

    func cancelPullInChoiceFromKeyboard() {
        guard var choice = pullInChoice else {
            return
        }
        // An active reason edit restores the exact prior outcome without
        // arming the card discard warning.
        if choice.activeReasonKey != nil {
            choice.restoreOfferCancel()
            pullInChoice = choice
            requestFocus(.pullInOfferList)
            return
        }
        // Two-step Esc while verdicts are staged.
        if choice.closeCount > 0, !choice.outcomes.isEscArmed {
            choice.armEscDiscard()
            pullInChoice = choice
            let text = choice.outcomes.escArmedText ?? "Esc again to discard closes"
            statusText = text
            announceStatus(text)
            return
        }
        dismissPullInChoice(status: "Successor choice canceled")
    }

    private func dismissPullInChoice(status: String) {
        pullInChoice = nil
        errorMessage = nil
        errorCode = nil
        if restoreMoveChoiceForBack() { return }
        clearEditorInputLockIfFree()
        requestFocus(.editor)
        statusText = status
    }

    func disarmPullInDiscardForNativeKey() {
        guard var choice = pullInChoice, choice.outcomes.isEscArmed else {
            return
        }
        choice.disarmEscDiscard()
        pullInChoice = choice
    }

    func stagePullInDoneForRow(_ key: String) {
        guard var choice = pullInChoice, !isSubmitting else {
            return
        }
        guard choice.closeSupported else {
            announceStatus("Closing offers needs a newer bob")
            NSSound.beep()
            return
        }
        guard choice.outcomes.isEligible(.done, for: key) || choice.verdicts[key] == .done else {
            announceStatus(choice.refusalReason(for: key) ?? "This offer cannot close here")
            NSSound.beep()
            return
        }
        // Pointer actions target the acted-on row and never advance.
        let highlight = choice.highlightedKey
        choice.toggleOfferDone(key)
        // Restore highlight when the pointer acted off-highlight.
        if highlight != key, choice.highlightedKey == key {
            choice.highlightedKey = highlight
        }
        pullInChoice = choice
        if let verdict = choice.verdicts[key] {
            announceStatus(choice.consequenceText(for: verdict, rowKey: key) ?? "Done staged")
        } else {
            announceStatus("Back to Leave")
        }
        requestFocus(.pullInOfferList)
    }

    func beginPullInCancelForRow(_ key: String) {
        guard var choice = pullInChoice, !isSubmitting else {
            return
        }
        guard choice.closeSupported else {
            announceStatus("Closing offers needs a newer bob")
            NSSound.beep()
            return
        }
        if choice.verdicts[key] != nil, case .cancel = choice.verdicts[key] {
            choice.beginOfferCancel(key)
            pullInChoice = choice
            announceStatus("Back to Leave")
            requestFocus(.pullInOfferList)
            return
        }
        guard choice.outcomes.isEligible(.cancel(""), for: key) else {
            announceStatus(choice.refusalReason(for: key) ?? "This offer cannot close here")
            NSSound.beep()
            return
        }
        choice.beginOfferCancel(key)
        pullInChoice = choice
        requestFocus(.pullInReasonField)
    }

    func clearPullInVerdictForRow(_ key: String) {
        guard var choice = pullInChoice, choice.verdicts[key] != nil else {
            return
        }
        let highlight = choice.highlightedKey
        _ = choice.outcomes.clearVerdict(for: key)
        choice.consequenceMessage = nil
        if highlight != key {
            choice.highlightedKey = highlight
        }
        pullInChoice = choice
        announceStatus("Back to Leave")
        requestFocus(.pullInOfferList)
    }

    func stagePullInDoneForHighlight() {
        guard var choice = pullInChoice, !isSubmitting else {
            return
        }
        guard let key = choice.highlightedKey else {
            return
        }
        guard choice.closeSupported else {
            announceStatus("Closing offers needs a newer bob")
            NSSound.beep()
            return
        }
        guard choice.outcomes.isEligible(.done, for: key) || choice.verdicts[key] == .done else {
            announceStatus(choice.refusalReason(for: key) ?? "This offer cannot close here")
            NSSound.beep()
            return
        }
        choice.toggleOfferDone(key)
        pullInChoice = choice
        if let verdict = choice.verdicts[key] {
            announceStatus(choice.consequenceText(for: verdict, rowKey: key) ?? "Done staged")
        } else {
            announceStatus("Back to Leave")
        }
        requestFocus(.pullInOfferList)
    }

    func beginPullInCancelForHighlight() {
        guard var choice = pullInChoice, !isSubmitting else {
            return
        }
        guard let key = choice.highlightedKey else {
            return
        }
        guard choice.closeSupported else {
            announceStatus("Closing offers needs a newer bob")
            NSSound.beep()
            return
        }
        // Same chord on staged Cancel clears; otherwise open the reason.
        if choice.verdicts[key] != nil, case .cancel = choice.verdicts[key] {
            choice.beginOfferCancel(key)
            pullInChoice = choice
            announceStatus("Back to Leave")
            requestFocus(.pullInOfferList)
            return
        }
        guard choice.outcomes.isEligible(.cancel(""), for: key) else {
            announceStatus(choice.refusalReason(for: key) ?? "This offer cannot close here")
            NSSound.beep()
            return
        }
        choice.beginOfferCancel(key)
        pullInChoice = choice
        requestFocus(.pullInReasonField)
    }

    func confirmPullInReason() {
        guard var choice = pullInChoice, choice.activeReasonKey != nil else {
            return
        }
        choice.confirmOfferCancel()
        pullInChoice = choice
        announceStatus(choice.consequenceMessage ?? "Cancel staged")
        requestFocus(.pullInOfferList)
    }

    func restorePullInReason() {
        guard var choice = pullInChoice, choice.activeReasonKey != nil else {
            return
        }
        choice.restoreOfferCancel()
        pullInChoice = choice
        requestFocus(.pullInOfferList)
    }

    func updatePullInReasonText(_ text: String) {
        guard var choice = pullInChoice, choice.activeReasonKey != nil else {
            return
        }
        choice.updateReasonText(text)
        pullInChoice = choice
    }

    func movePullInChoiceHighlight(by delta: Int) {
        guard var choice = pullInChoice else {
            return
        }
        choice.disarmEscDiscard()
        choice.moveHighlight(by: delta)
        choice.updateConsequenceForHighlight()
        pullInChoice = choice
        requestFocus(.pullInOfferList)
    }

    func toggleHighlightedPullInOffer() {
        guard var choice = pullInChoice else {
            return
        }
        choice.toggleHighlighted()
        pullInChoice = choice
        requestFocus(.pullInOfferList)
    }

    func togglePullInOffer(_ key: String) {
        guard var choice = pullInChoice else {
            return
        }
        choice.toggleOffer(key)
        pullInChoice = choice
        requestFocus(.pullInOfferList)
    }

    func markAllPullInOffers() {
        guard var choice = pullInChoice else {
            return
        }
        choice.markAll()
        pullInChoice = choice
        requestFocus(.pullInOfferList)
    }

    func updatePullInChoiceFilter(_ text: String) {
        guard var choice = pullInChoice else {
            return
        }
        choice.disarmEscDiscard()
        choice.updateFilter(text)
        pullInChoice = choice
    }

    func focusPullInChoiceFilter() {
        requestFocus(.pullInFilter)
    }

    func togglePullInChoiceGroup(_ id: String) {
        guard var choice = pullInChoice else {
            return
        }
        choice.toggleGroup(id)
        pullInChoice = choice
    }

    func installPullInChoiceForPreviews(
        offers: [TaskCompleteUnblocked],
        stillBlocked: [TaskCompleteStillBlocked] = [],
        pullIn: CapturePullIn,
        planBudget: CapturePlanBudget? = nil,
        draft: String,
        openAfterCapture: Bool = false
    ) {
        _ = openPullInChoice(
            offers: offers,
            stillBlocked: stillBlocked,
            pullIn: pullIn,
            planBudget: planBudget,
            draft: draft,
            processClientIdentity: processClient?.identityToken ?? "preview-test",
            openAfterCapture: openAfterCapture,
            seed: activePriorityRollSeed(),
            generation: analysisGeneration,
            requestID: nil
        )
    }

    func installInboxRouteChoiceForPreviews(
        route: CaptureInboxRoute,
        draft: String,
        openAfterCapture: Bool = false
    ) {
        let context = CaptureInboxRouteSubmitContext(
            choice: CaptureInboxRouteChoiceState(
                candidates: route.candidates,
                destinations: route.destinations ?? []
            ),
            draft: draft,
            clientIdentity: processClient?.identityToken ?? "preview-test",
            openAfterCapture: openAfterCapture,
            seed: activePriorityRollSeed(),
            generation: analysisGeneration,
            requestID: nil,
            pullInSelection: nil,
            pullInChoiceForBack: nil,
            pullInCapabilityAdvertised: false,
            offerVerdicts: nil,
            offerCloseCapabilityAdvertised: false,
            inboxRouteCapabilityAdvertised: route.supported,
            hasOverride: false,
            vaultDirectoryIdentity: processClient?.vaultDirectoryIdentity ?? "preview-vault"
        )
        _ = openInboxRouteChoice(route, context: context)
    }

    func preview() {
        guard !inlinePromptVisible, !isSubmitting, !isPreviewing, hasDraft else {
            return
        }
        guard let processClient else {
            errorMessage = "Bob is not resolved. Check Settings and Recheck Bob."
            errorCode = nil
            return
        }

        let draft = plainDraft
        let requestID = UUID()
        let generation = analysisGeneration
        let seed = activePriorityRollSeed()
        let processClientIdentity = processClient.identityToken
        activeRequestID = requestID
        isPreviewing = true
        previewPullInSnapshot = nil
        errorMessage = nil
        errorCode = nil
        statusText = "Resolving clipboard preview\u{2026}"

        Task {
            do {
                let response = try await CaptureSignpost.measure("preview-explicit") {
                    try await processClient.capture(
                        draft,
                        dryRun: true,
                        readClipboard: true,
                        priorityRollSeed: seed
                    )
                }
                await MainActor.run {
                    self.completePreview(
                        requestID: requestID,
                        response: response,
                        draft: draft,
                        seed: seed,
                        generation: generation,
                        processClient: processClient,
                        processClientIdentity: processClientIdentity
                    )
                }
            } catch {
                await MainActor.run {
                    self.failPreview(
                        requestID: requestID,
                        error: error,
                        draft: draft,
                        generation: generation,
                        processClient: processClient,
                        processClientIdentity: processClientIdentity
                    )
                }
            }
        }
    }

    func copyDiagnosticToPasteboard() {
        guard let errorMessage else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(errorMessage, forType: .string)
    }

    /// Records a close that keeps the draft. Closing the panel is never destructive;
    /// permanent discarding is an explicit action from the Discard button.
    func prepareForRetainedClose() {
        panelVisible = false
        invalidateRecordInteraction(clearPresentation: true)
        cancelPendingExplicitSubmit()
        stopClipboardPolling()
        cancelSimilarTasks(clear: false)
        previewPullInSnapshot = nil
        dismissStashPicker()
        dismissTemplateShelf()
        clearInlinePrompts()
        agendaExpanded = []
        invalidateTodayPomodoroGoto()
        if hasDraft {
            statusText = "Draft retained"
        }
    }

    func closeRetainingDraft() {
        prepareForRetainedClose()
        panelDismisser()
    }

    func discardDraftAndClose() {
        discardDraft()
        panelDismisser()
    }

    func discardDraft() {
        dismissStashPicker()
        dismissTemplateShelf()
        clearInlinePrompts()
        templateOrigin = nil
        setPlainDraft("")
        suppressedCompletionAcceptanceDraft = nil
        priorityRollSeed = nil
        resetAnalysisState()
    }

    private var draftIsTaskGoto: Bool {
        picker?.source == .taskGoto
            || pickerChip?.source == .taskGoto
            || lastAnalysisNeedsTaskGoto
    }

    func stashDraftAndClose() {
        if hasDraft {
            let draft = plainDraft
            let keptTemplate = templateOrigin != nil
            let stashed = draftIsTaskGoto ? false : canceledDraftStash.push(draft) != nil
            discardDraft()
            let status: String
            if stashed && keptTemplate {
                status = "Canceled draft stashed · template kept"
            } else if stashed {
                status = "Canceled draft stashed"
            } else {
                status = "Canceled draft discarded"
            }
            announceStatus(status)
        } else {
            discardDraft()
        }
        panelDismisser()
    }

    /// Called once from applicationWillTerminate so Quit, Restart, and an install
    /// restart never drop unsent text. It only pushes onto the write-through stash: the
    /// process is exiting, so no status, dismissal, clearing, or analysis runs.
    @discardableResult
    func stashDraftForTermination() -> CanceledDraftEntry? {
        guard hasDraft, !draftIsTaskGoto else {
            return nil
        }
        return canceledDraftStash.push(plainDraft)
    }

    func toggleStashPicker() {
        if picker != nil {
            return
        }
        if isTemplateShelfPresented {
            switchTemplateShelfToStash()
            return
        }
        if isStashPickerPresented {
            dismissStashPicker()
        } else {
            presentStashPicker()
        }
    }

    func presentStashPicker() {
        if picker != nil {
            return
        }
        if taskIDPrompt != nil {
            announceStatus("Finish or cancel the block ID prompt before opening stash")
            requestFocus(.taskIDPromptBlockID)
            return
        }
        if pomodoroNamePrompt != nil {
            announceStatus("Finish or cancel the Pomodoro name prompt before opening stash")
            requestFocus(.pomodoroNamePromptName)
            return
        }
        guard plainDraft.isEmpty else {
            announceStatus("Capture, retain, or cancel the current draft before opening stash")
            return
        }
        guard !canceledDraftStash.isEmpty else {
            announceStatus("No canceled drafts yet")
            return
        }

        dismissCompletion()
        selectedStashIndex = 0
        isStashPickerPresented = true
        announceStatus("Canceled draft stash opened")
    }

    func dismissStashPicker() {
        guard isStashPickerPresented || selectedStashIndex != 0 else {
            return
        }
        isStashPickerPresented = false
        selectedStashIndex = 0
        requestFocus(.editor)
    }

    func selectNextStashEntry() {
        selectedStashIndex = canceledDraftStash.nextSelectionIndex(after: selectedStashIndex)
    }

    func selectPreviousStashEntry() {
        selectedStashIndex = canceledDraftStash.previousSelectionIndex(before: selectedStashIndex)
    }

    func restoreSelectedStashEntry() {
        guard let entry = selectedStashEntry else {
            announceStatus("No canceled drafts yet")
            dismissStashPicker()
            return
        }
        restoreStashEntry(id: entry.id)
    }

    func restoreStashEntry(at index: Int) {
        guard let entry = canceledDraftStash.entry(at: index) else {
            return
        }
        restoreStashEntry(id: entry.id)
    }

    func restoreStashEntry(id: UUID) {
        guard plainDraft.isEmpty else {
            announceStatus("Capture, retain, or cancel the current draft before opening stash")
            return
        }
        guard let entry = canceledDraftStash.entry(id: id) else {
            announceStatus("Canceled draft is no longer available")
            clampStashSelectionAfterStoreChange()
            return
        }

        let text = entry.text
        dismissStashPicker()
        suppressedCompletionAcceptanceDraft = nil
        priorityRollSeed = nil
        resetAnalysisState()
        setPlainDraft(text, cursorUTF8Offset: text.utf8.count, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: text.utf8.count, requestCompletion: false, trigger: .edit)
        canceledDraftStash.remove(id: entry.id)
        announceStatus("Restored canceled draft")
    }

    func clearCanceledDraftStashFromPicker() {
        guard isStashPickerPresented else {
            return
        }
        canceledDraftStash.clear()
        dismissStashPicker()
        requestFocus(.editor)
        announceStatus("Canceled draft stash cleared")
    }

    func toggleTemplateShelf() {
        if isStashPickerPresented {
            dismissStashPicker()
            presentTemplateShelf()
            return
        }
        if isTemplateShelfPresented {
            dismissTemplateShelf()
        } else {
            presentTemplateShelf()
        }
    }

    func presentTemplateShelf() {
        if picker != nil {
            announceStatus("Finish or cancel the picker before opening templates")
            return
        }
        if taskIDPrompt != nil {
            announceStatus("Finish or cancel the block ID prompt before opening templates")
            requestFocus(.taskIDPromptBlockID)
            return
        }
        if pomodoroNamePrompt != nil {
            announceStatus("Finish or cancel the Pomodoro name prompt before opening templates")
            requestFocus(.pomodoroNamePromptName)
            return
        }
        if pullInChoice != nil {
            announceStatus("Finish or cancel the successor choice before opening templates")
            return
        }
        if currentDraftHasTemplate {
            announceStatus("This draft already has a template")
            return
        }
        switch savedTemplateShelf.availability {
        case .unsupported:
            announceStatus("Update bob to use saved templates")
            return
        case .unknown:
            announceStatus("Loading saved templates…")
            savedTemplateShelf.refresh(reason: .show)
            return
        case .failed(let message):
            if savedTemplateShelf.isEmpty {
                announceStatus(message)
                savedTemplateShelf.refresh(reason: .show)
                return
            }
        case .available:
            break
        }
        let entries = templateEntries
        guard !entries.isEmpty else {
            announceStatus("No saved templates yet — add %t to the first item to start one")
            return
        }

        dismissCompletion()
        dismissStashPicker()
        selectedTemplateIndex = 0
        rememberedSelectedTemplateID = entries.first?.id
        armedDeleteTemplateID = nil
        isTemplateShelfPresented = true
        announceStatus("Saved templates opened")
    }

    func dismissTemplateShelf() {
        guard isTemplateShelfPresented || selectedTemplateIndex != 0 || armedDeleteTemplateID != nil
        else {
            return
        }
        isTemplateShelfPresented = false
        selectedTemplateIndex = 0
        rememberedSelectedTemplateID = nil
        armedDeleteTemplateID = nil
        requestFocus(.editor)
    }

    func escapeTemplateShelf() {
        if armedDeleteTemplateID != nil {
            armedDeleteTemplateID = nil
            return
        }
        dismissTemplateShelf()
    }

    func selectNextTemplateEntry() {
        disarmTemplateDeleteIfNeeded()
        selectedTemplateIndex = CapturePickerHelpers.nextSelectionIndex(
            after: selectedTemplateIndex,
            entryCount: templateEntries.count
        )
        rememberedSelectedTemplateID = selectedTemplateEntry?.id
    }

    func selectPreviousTemplateEntry() {
        disarmTemplateDeleteIfNeeded()
        selectedTemplateIndex = CapturePickerHelpers.previousSelectionIndex(
            before: selectedTemplateIndex,
            entryCount: templateEntries.count
        )
        rememberedSelectedTemplateID = selectedTemplateEntry?.id
    }

    func useSelectedTemplate() {
        guard let entry = selectedTemplateEntry else {
            announceStatus("No saved templates yet — add %t to the first item to start one")
            dismissTemplateShelf()
            return
        }
        useTemplate(id: entry.id)
    }

    func useTemplate(at index: Int) {
        guard templateEntries.indices.contains(index) else {
            return
        }
        useTemplate(id: templateEntries[index].id)
    }

    func useTemplate(id: String) {
        if currentDraftHasTemplate {
            announceStatus("This draft already has a template")
            return
        }
        guard let template = templateEntries.first(where: { $0.id == id }) else {
            announceStatus("Saved template is no longer available")
            clampTemplateSelection(templates: templateEntries)
            return
        }
        guard let edit = templateInsertEdit(for: template) else {
            announceStatus("Could not insert saved template")
            return
        }

        dismissTemplateShelf()
        suppressedCompletionAcceptanceDraft = nil
        if applyTemplateInsert?(edit) == true {
            templateOrigin = template.id
            requestFocus(.editor)
            return
        }
        setPlainDraft(
            edit.resultingDraft,
            cursorUTF8Offset: edit.cursorUTF8Offset,
            suppressSelectionCallbacks: true
        )
        templateOrigin = template.id
        scheduleAnalysis(
            cursorUTF8Offset: edit.cursorUTF8Offset,
            requestCompletion: false,
            trigger: .edit
        )
        requestFocus(.editor)
    }

    func templateInsertEdit(for template: CaptureSavedTemplate) -> CaptureTemplateInsertEdit? {
        let existing = plainDraft
        let insertion = template.draft
        if existing.isEmpty {
            let cursor = min(max(template.cursor, 0), insertion.utf8.count)
            guard let selection = utf16Range(in: insertion, start: cursor, end: cursor) else {
                return nil
            }
            return CaptureTemplateInsertEdit(
                replacementRange: NSRange(location: 0, length: 0),
                replacementText: insertion,
                resultingSelection: selection,
                resultingDraft: insertion,
                cursorUTF8Offset: cursor
            )
        }

        let resulting = insertion + existing
        let caretUTF8 = (collapsedSelectionUTF8Offset() ?? 0) + insertion.utf8.count
        guard caretUTF8 <= resulting.utf8.count,
            let selection = utf16Range(in: resulting, start: caretUTF8, end: caretUTF8)
        else {
            return nil
        }
        return CaptureTemplateInsertEdit(
            replacementRange: NSRange(location: 0, length: 0),
            replacementText: insertion,
            resultingSelection: selection,
            resultingDraft: resulting,
            cursorUTF8Offset: caretUTF8
        )
    }

    func armOrConfirmTemplateDelete() {
        guard isTemplateShelfPresented, let entry = selectedTemplateEntry else {
            return
        }
        if armedDeleteTemplateID == entry.id {
            confirmTemplateDelete(id: entry.id)
            return
        }
        armedDeleteTemplateID = entry.id
        announceStatus("Press Delete again to delete template \(entry.index)")
    }

    func disarmTemplateDeleteIfNeeded() {
        armedDeleteTemplateID = nil
    }

    func switchTemplateShelfToStash() {
        guard isTemplateShelfPresented else {
            return
        }
        isTemplateShelfPresented = false
        armedDeleteTemplateID = nil
        presentStashPicker()
        if !isStashPickerPresented {
            isTemplateShelfPresented = true
        } else {
            selectedTemplateIndex = 0
            rememberedSelectedTemplateID = nil
        }
    }

    func saveTemplateFromKeyboard() {
        guard !isSavingTemplate else {
            return
        }
        guard !savedTemplateShelf.isUnsupported else {
            announceStatus("Update bob to use saved templates")
            return
        }
        guard let processClient else {
            announceStatus("Bob is not resolved")
            return
        }

        let draft = plainDraft
        let origin = templateOrigin
        isSavingTemplate = true
        Task { [weak self, processClient] in
            do {
                let response = try await processClient.saveTemplate(draft, origin: origin)
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.isSavingTemplate = false
                    self.savedTemplateShelf.refresh(reason: .mutation)
                    guard response.ok, let saved = response.saved else {
                        if self.plainDraft == draft {
                            self.announceStatus(response.error ?? "Template could not be saved")
                        }
                        return
                    }
                    if self.plainDraft == draft {
                        self.templateOrigin = saved.id
                    } else if let origin, self.templateOrigin == origin {
                        // Keep an active checkout pointed at the replacement id if
                        // the user edited again while this save was in flight.
                        self.templateOrigin = saved.id
                    }
                    guard self.plainDraft == draft else {
                        return
                    }
                    let status: String
                    switch saved.status {
                    case .new:
                        status = "Template saved — ⌃T to reuse"
                    case .updated:
                        status = "Template already saved"
                    case .replaced:
                        status = "Template updated"
                    case .unknown:
                        status = "Template saved"
                    }
                    self.announceStatus(status)
                }
            } catch let error as BobClientError {
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.isSavingTemplate = false
                    if case .unsupportedCommand = error {
                        self.savedTemplateShelf.refresh(reason: .recheck)
                        if self.plainDraft == draft {
                            self.announceStatus("Update bob to use saved templates")
                        }
                    } else if self.plainDraft == draft {
                        self.announceStatus(error.description)
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.isSavingTemplate = false
                    if self.plainDraft == draft {
                        self.announceStatus(String(describing: error))
                    }
                }
            }
        }
    }

    func setParsedTemplateForTests(_ template: CaptureParseTemplate?, draft: String) {
        parsedTemplate = template
        lastAppliedParseDraft = draft
    }

    private func confirmTemplateDelete(id: String) {
        armedDeleteTemplateID = nil
        let snapshot = savedTemplateShelf.templates
        let remaining = savedTemplateShelf.removeLocally(id: id)
        let visibleRemaining = visibleTemplateEntries(from: remaining)
        rememberedSelectedTemplateID = visibleRemaining.first?.id
        selectedTemplateIndex = CapturePickerHelpers.clampedSelectionIndex(
            selectedTemplateIndex,
            entryCount: visibleRemaining.count
        )
        if visibleRemaining.isEmpty {
            isTemplateShelfPresented = false
            announceStatus("Template deleted · shelf is empty")
            requestFocus(.editor)
        } else {
            announceStatus("Template deleted")
        }
        Task { [weak self] in
            await self?.finishTemplateDelete(id: id, snapshot: snapshot)
        }
    }

    private func finishTemplateDelete(id: String, snapshot: [CaptureSavedTemplate]) async {
        guard let client = processClient else {
            await MainActor.run {
                self.savedTemplateShelf.restoreLocally(snapshot)
                self.clampTemplateSelection(templates: self.visibleTemplateEntries(from: snapshot))
                self.announceStatus("Bob is not resolved")
            }
            return
        }
        do {
            let response = try await client.deleteSavedTemplates(ids: [id])
            await MainActor.run {
                if response.ok {
                    self.savedTemplateShelf.refresh(reason: .mutation)
                    return
                }
                self.savedTemplateShelf.restoreLocally(snapshot)
                self.clampTemplateSelection(templates: self.visibleTemplateEntries(from: snapshot))
                self.announceStatus(response.error ?? "Template not deleted")
                self.savedTemplateShelf.refresh(reason: .mutation)
            }
        } catch {
            await MainActor.run {
                self.savedTemplateShelf.restoreLocally(snapshot)
                self.clampTemplateSelection(templates: self.visibleTemplateEntries(from: snapshot))
                self.announceStatus(String(describing: error))
                self.savedTemplateShelf.refresh(reason: .mutation)
            }
        }
    }

    private func clampTemplateSelection(templates: [CaptureSavedTemplate]) {
        guard !templates.isEmpty else {
            selectedTemplateIndex = 0
            rememberedSelectedTemplateID = nil
            armedDeleteTemplateID = nil
            if isTemplateShelfPresented {
                isTemplateShelfPresented = false
                requestFocus(.editor)
            }
            return
        }
        if let id = rememberedSelectedTemplateID,
            let index = templates.firstIndex(where: { $0.id == id })
        {
            selectedTemplateIndex = index
        } else {
            selectedTemplateIndex = CapturePickerHelpers.clampedSelectionIndex(
                selectedTemplateIndex,
                entryCount: templates.count
            )
            rememberedSelectedTemplateID = templates[selectedTemplateIndex].id
        }
        if let armed = armedDeleteTemplateID, !templates.contains(where: { $0.id == armed }) {
            armedDeleteTemplateID = nil
        }
    }

    private func visibleTemplateEntries(
        from templates: [CaptureSavedTemplate]
    ) -> [CaptureSavedTemplate] {
        let available = templates.filter { $0.id != templateOrigin }
        guard templateOrigin != nil else {
            return available
        }
        return available.enumerated().map { offset, entry in
            CaptureSavedTemplate(
                index: offset + 1,
                id: entry.id,
                text: entry.text,
                draft: entry.draft,
                cursor: entry.cursor,
                fieldCount: entry.fieldCount,
                lineCount: entry.lineCount,
                route: entry.route,
                spans: entry.spans,
                firstSavedAt: entry.firstSavedAt,
                lastUsedAt: entry.lastUsedAt,
                useCount: entry.useCount
            )
        }
    }

    // Called before the panel is (re)shown. A retained draft (from Escape or a failed
    // capture) must reopen exactly as the user left it, error and all; only a panel with
    // no draft — i.e. one that just dismissed after a success — needs its leftover
    // success summary and status cleared so the next capture starts clean. A retained
    // non-empty draft still re-runs analysis: a close preview's `closed_at` and timing
    // go stale while the panel is hidden, so the card must resolve them fresh.
    func prepareForPresentation() {
        panelVisible = true
        aliasTipSession = AliasTipSession()
        dismissStashPicker()
        dismissTemplateShelf()
        guard !hasDraft else {
            editorTextDidChange()
            requestSimilarTasksNow()
            return
        }
        resetAnalysisState()
        lastSuccess = nil
        lastSuccessResults = []
        lastSuccessGlobalDestination = nil
        selectedCompletionIndex = nil
    }

    func prepareForDismissal() {
        panelVisible = false
        invalidateRecordInteraction(clearPresentation: true)
        cancelPendingExplicitSubmit()
        stopClipboardPolling()
        cancelPastBoundaryRefresh()
        if similarTasks.focusedRowID != nil {
            unfocusSimilarRow(applyPending: false)
        }
        cancelSimilarTasks(clear: false)
        clearOpenHintReveal()
        previewPullInSnapshot = nil
        dismissStashPicker()
        dismissTemplateShelf()
        closePickerForDismissal()
        clearInlinePrompts()
        agendaExpanded = []
        invalidateRewrite()
        invalidateTodayPomodoroGoto()
        clearEditorLeader()
        clearBackslashLiteralArm()
        clearHashAliasLiteralArm()
        cancelAliasTipLane()
        dropPendingAliasTip()
        presentedAliasTip = nil
        pendingTypedSigilIntent = nil
        aliasTipHitRecords.removeAll()
    }

    func armEditorLeader() {
        editorLeaderPending = true
    }

    func clearEditorLeader() {
        editorLeaderPending = false
    }

    func armBackslashLiteral() {
        backslashLiteralArmed = true
    }

    func clearBackslashLiteralArm() {
        backslashLiteralArmed = false
    }

    /// Takes and clears the one-shot backslash arm, like the editor leader.
    func takeBackslashLiteralArm() -> Bool {
        let armed = backslashLiteralArmed
        backslashLiteralArmed = false
        return armed
    }

    func clearHashAliasLiteralArm() {
        hashAliasLiteralArm = nil
        equalsGestureArm = nil
        pendingEqualsFirstKey = nil
        equalsProbe = nil
        relationFlipAliasOpen = nil
    }

    /// Takes and clears the one-shot hash-alias arm.
    func takeHashAliasLiteralArm() -> CaptureHashAliasArm? {
        let arm = hashAliasLiteralArm
        hashAliasLiteralArm = nil
        return arm
    }

    func restoreHashAliasLiteralArm(_ arm: CaptureHashAliasArm) {
        hashAliasLiteralArm = arm
    }

    /// Clears the one-shot relation-flip allowance on the next key-down.
    func clearRelationFlipAliasOpen() {
        relationFlipAliasOpen = nil
    }

    /// True when the trimmed draft is exactly `/`, the Go To trigger.
    var draftIsBareGotoSigil: Bool {
        plainDraft.trimmingCharacters(in: .whitespacesAndNewlines) == "/"
    }

    func requestFocus(_ target: CapturePanelFocusTarget) {
        focusSequence &+= 1
        focusRequest = CapturePanelFocusRequest(sequence: focusSequence, target: target)
    }

    private func resetAnalysisState() {
        invalidateAnalysis()
        stopClipboardPolling()
        lastPreviewTransferVerb = nil
        transferOwnedStatusText = nil
        cancelSimilarTasks(clear: true)
        editAnalysisBaseline = plainDraft
        invalidateRewrite()
        cancelInFlightExplicitPreview()
        latestParse = nil
        parseDiagnostics = []
        parsedTemplate = nil
        lastAppliedParseDraft = nil
        lastAppliedParseGeneration = nil
        lastAppliedParseItemCount = nil
        lastAppliedParseGrammar = nil
        lastAppliedParseClientIdentity = nil
        captureGrammarWarning = nil
        similarTasksParseItems = []
        similarTasksFolded = false
        dropPendingAliasTip()
        presentedAliasTip = nil
        completionResponse = nil
        completionDraftSnapshot = nil
        recordPresentation = nil
        recordFocusState = nil
        recordAnalysisRequest = nil
        recordCompletionSnapshot = nil
        recordInteractionPending = false
        recordAssistVersion = nil
        recordCardDismissedDraft = nil
        fileUnderActive = false
        closeListParseSnapshot = nil
        closeListAssistParsePending = false
        closeCommaProvenance.clear()
        lastProvenanceDraft = plainDraft
        taskGotoDispatchInFlight = false
        invalidateTodayPomodoroGoto()
        lastAnalysisNeedsTaskGoto = false
        clearPickerState()
        clearInlinePrompts()
        previewState = .idle
        statusText = ""
        errorMessage = nil
        errorCode = nil
        clearPreviewOutputs()
        previewPullInSnapshot = nil
        closePendingText = nil
        closePendingAction = "Close"
        relationshipDisplayNames = [:]
    }

    /// Explicit Preview shares `activeRequestID` with submit. Retire only
    /// a preview request so a late callback cannot refill a cleared draft,
    /// and leave an in-flight capture alone.
    private func cancelInFlightExplicitPreview() {
        guard isPreviewing else {
            return
        }
        activeRequestID = nil
        isPreviewing = false
    }

    private func clearInlinePrompts() {
        clearTaskIDPrompt()
        clearPomodoroNamePrompt()
        resetMoveChoice()
        pullInChoice = nil
        inboxRouteChoice = nil
        inboxRouteChoiceContext = nil
        activeInboxRouteSubmitContext = nil
        clearEditorInputLockIfFree()
    }

    private func clearTaskIDPrompt() {
        taskIDPrompt = nil
        activeTaskIDRequestID = nil
        clearEditorInputLockIfFree()
    }

    private func clearPomodoroNamePrompt() {
        pomodoroNamePrompt = nil
        activePomodoroNameRequestID = nil
        activePomodoroThemeSuggestionRequestID = nil
        pomodoroThemeSuggestionsTask?.cancel()
        pomodoroThemeSuggestionsTask = nil
        clearEditorInputLockIfFree()
    }

    private func clearEditorInputLock() {
        if editorInputLocked {
            editorInputLocked = false
        }
    }

    /// The editor stays locked while the picker or a choice prompt is open.
    private func clearEditorInputLockIfFree() {
        if taskIDPrompt == nil, pomodoroNamePrompt == nil, pullInChoice == nil,
            inboxRouteChoice == nil, moveChoice == nil, picker == nil
        {
            clearEditorInputLock()
        }
    }

    private func announceStatus(_ message: String) {
        statusText = message
        statusAnnouncementTick += 1
    }

    /// Assigns panel status and then marks it as a Record Card refusal.
    /// Callers that assign `statusText` directly stay informational.
    private func refuseStatus(_ message: String) {
        statusText = message
        statusIsRefusal = true
    }

    func announceTypeAheadSubmitDropped() {
        announceStatus("Bob did not answer; press Return again")
    }

    private func clampStashSelectionAfterStoreChange() {
        clampStashSelection(afterEntriesChange: canceledDraftStash.entries)
    }

    private func clampStashSelection(afterEntriesChange entries: [CanceledDraftEntry]) {
        guard !entries.isEmpty else {
            isStashPickerPresented = false
            selectedStashIndex = 0
            return
        }
        selectedStashIndex = min(max(selectedStashIndex, 0), entries.count - 1)
    }

    func dismissCompletion(
        cancelPendingRecordReturn: Bool = true,
        preservePendingAliasTip: Bool = false,
        preservePresentedAliasTip: Bool = false
    ) {
        // Esc on the File-under list keeps the default inbox parent: remember
        // the URL so the list does not reopen until the URL changes. Accept
        // paths clear the record after splicing (see
        // `applySelectedCompletionReplacement`).
        if fileUnderActive {
            fileUnderDismissedURL = plainDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        completionResponse = nil
        completionDraftSnapshot = nil
        selectedCompletionIndex = nil
        placeMenuSelectionWasExplicit = false
        fileUnderActive = false
        recordAnalysisRequest = nil
        recordCompletionSnapshot = nil
        if cancelPendingRecordReturn {
            recordRequestSequence &+= 1
            recordReturnTask?.cancel()
            recordReturnTask = nil
        }
        if !preservePendingAliasTip {
            deferAliasTipOpportunity(reason: .closed)
        }
        if !preservePresentedAliasTip {
            presentedAliasTip = nil
        }
    }

    // MARK: - Capture picker

    /// Test and render support: mounts a Record Card from fixture
    /// presentation without a subprocess round trip.
    func installRecordCardForPreviews(
        presentation: CaptureRecordPresentation,
        parse: CaptureParseResponse? = nil,
        completion: CaptureCompletionResponse? = nil,
        statusText: String = "",
        statusIsRefusal: Bool = false
    ) {
        recordPresentation = presentation
        latestParse = parse
        completionResponse = completion
        selectedCompletionIndex = completion?.candidates.isEmpty == false ? 0 : nil
        self.statusText = statusText
        self.statusIsRefusal = statusIsRefusal
    }

    /// Test and render support: installs a picker session directly from a
    /// snapshot, bypassing the subprocess round trip. Production code opens
    /// the picker through `scheduleAnalysis`; this exists so design tests and
    /// the `BOB_MAC_CAPTURE_RENDER_DIR` image review can mount
    /// `CapturePickerCard` on fixture data.
    func installPickerForPreviews(
        candidates: [CaptureCompletionCandidate],
        warnings: [String] = [],
        filter: String = ""
    ) {
        let index = CapturePickerIndex.activeTask(ActiveTaskPickerIndex(candidates: candidates))
        installPickerSessionForPreviews(
            source: .activeTask,
            index: index,
            candidates: candidates,
            warnings: warnings,
            draftSnapshot: "^",
            replacementRange: CaptureRange(start: 0, end: 1),
            restoreCursor: 1,
            filter: filter,
            snapshotIsPartial: false
        )
    }

    /// Go To preview hook: mounts the `/` session production presents for a
    /// decoded `task_goto` response, so panel tests can dispatch without a
    /// subprocess round trip.
    func installTaskGotoPickerForPreviews(
        candidates: [CaptureCompletionCandidate],
        warnings: [String] = [],
        filter: String = "",
        draft: String = "/",
        replacement: CaptureRange = CaptureRange(start: 0, end: 1)
    ) {
        let index = CapturePickerIndex.taskGoto(
            TaskLinkPickerIndex(candidates: candidates, mode: .taskGoto)
        )
        installPickerSessionForPreviews(
            source: .taskGoto,
            index: index,
            candidates: candidates,
            warnings: warnings,
            draftSnapshot: draft,
            replacementRange: replacement,
            restoreCursor: replacement.end,
            filter: filter,
            snapshotIsPartial: false
        )
    }

    /// Task-link preview hook: mounts the `:` session production presents for
    /// a decoded `task_link` response, so design tests and the image review
    /// render the card production mounts.
    func installTaskLinkPickerForPreviews(
        candidates: [CaptureCompletionCandidate],
        warnings: [String] = [],
        filter: String = "",
        draft: String = ":",
        replacement: CaptureRange = CaptureRange(start: 0, end: 1)
    ) {
        let index = CapturePickerIndex.taskLink(TaskLinkPickerIndex(candidates: candidates))
        installPickerSessionForPreviews(
            source: .taskLink,
            index: index,
            candidates: candidates,
            warnings: warnings,
            draftSnapshot: draft,
            replacementRange: replacement,
            restoreCursor: replacement.end,
            filter: filter,
            snapshotIsPartial: false
        )
    }

    /// Parent-task preview hook: mounts the `+` / `@route+` session
    /// production presents for a descriptor-bearing response.
    func installParentTaskPickerForPreviews(
        candidates: [CaptureCompletionCandidate],
        context: ParentTaskPickerContext,
        warnings: [String] = [],
        filter: String = "",
        draft: String = "+",
        replacement: CaptureRange = CaptureRange(start: 0, end: 1)
    ) {
        let index = CapturePickerIndex.parentTask(
            ParentTaskPickerIndex(candidates: candidates, context: context)
        )
        installPickerSessionForPreviews(
            source: .parentTask(context),
            index: index,
            candidates: candidates,
            warnings: warnings,
            draftSnapshot: draft,
            replacementRange: replacement,
            restoreCursor: replacement.end,
            filter: filter,
            snapshotIsPartial: false
        )
    }

    /// Move-picker preview hook: mounts the `project_task_move` session
    /// production presents for a decoded move response.
    func installProjectTaskMovePickerForPreviews(
        candidates: [CaptureCompletionCandidate],
        context: ProjectTaskMovePickerContext,
        warnings: [String] = [],
        filter: String = "",
        draft: String = "Finish @cash^goog-exit@\n- ^",
        replacement: CaptureRange = CaptureRange(start: 43, end: 43)
    ) {
        let enriched = ProjectTaskMovePickerContext(
            scopeToken: context.scopeToken,
            noteTarget: context.noteTarget,
            destination: context.destination,
            continuation: context.continuation,
            markerRange: context.markerRange,
            triggerRemovalRange: context.triggerRemovalRange,
            openCount: context.openCount,
            actionContinuationKeys: context.actionContinuationKeys,
            actionContinuationAliases: context.actionContinuationAliases
        )
        let index = CapturePickerIndex.projectTaskMove(
            ProjectTaskMovePickerIndex(candidates: candidates, context: enriched)
        )
        installPickerSessionForPreviews(
            source: .projectTaskMove(enriched),
            index: index,
            candidates: candidates,
            warnings: warnings,
            draftSnapshot: draft,
            replacementRange: replacement,
            restoreCursor: replacement.end,
            filter: filter,
            snapshotIsPartial: false
        )
    }

    /// Dependency preview hook: mounts the `&` session production presents
    /// for a decoded `task_dependency` response, so design tests and the
    /// image review render the card production mounts.
    func installDependencyPickerForPreviews(
        candidates: [CaptureCompletionCandidate],
        warnings: [String] = [],
        filter: String = "",
        draft: String = "&",
        replacement: CaptureRange = CaptureRange(start: 0, end: 1),
        owner: DependencyOwner? = nil
    ) {
        let index = CapturePickerIndex.dependency(DependencyPickerIndex(candidates: candidates))
        installPickerSessionForPreviews(
            source: .dependency,
            index: index,
            candidates: candidates,
            warnings: warnings,
            draftSnapshot: draft,
            replacementRange: replacement,
            restoreCursor: replacement.end,
            filter: filter,
            snapshotIsPartial: false,
            dependencyOwner: owner
        )
    }

    /// Relation preview hook, parallel to the production `relation_to` /
    /// `relation_from` path.
    func installRelationPickerForPreviews(
        candidates: [CaptureCompletionCandidate],
        warnings: [String] = [],
        filter: String = "",
        draft: String = "~",
        replacement: CaptureRange = CaptureRange(start: 0, end: 1),
        owner: DependencyOwner? = nil,
        direction: DependencyPickerDirection = .linksTo
    ) {
        let index = Self.dependencyPickerIndex(candidates, direction: direction)
        installPickerSessionForPreviews(
            source: Self.pickerSource(for: direction),
            index: index,
            candidates: candidates,
            warnings: warnings,
            draftSnapshot: draft,
            replacementRange: replacement,
            restoreCursor: replacement.end,
            filter: filter,
            snapshotIsPartial: false,
            dependencyOwner: owner
        )
    }

    /// Blocks preview hook, parallel to the production `blocked_task` path.
    func installBlockedTaskPickerForPreviews(
        candidates: [CaptureCompletionCandidate],
        warnings: [String] = [],
        filter: String = "",
        draft: String = "*",
        replacement: CaptureRange = CaptureRange(start: 0, end: 1),
        owner: DependencyOwner? = nil
    ) {
        let index = CapturePickerIndex.blockedTask(
            DependencyPickerIndex(candidates: candidates, direction: .blocks)
        )
        installPickerSessionForPreviews(
            source: .blockedTask,
            index: index,
            candidates: candidates,
            warnings: warnings,
            draftSnapshot: draft,
            replacementRange: replacement,
            restoreCursor: replacement.end,
            filter: filter,
            snapshotIsPartial: false,
            dependencyOwner: owner
        )
    }

    /// Complete preview hook: mounts the `!` session production presents
    /// for a decoded `task_complete` response, so design tests and the
    /// image review render the card production mounts.
    func installTaskCompletePickerForPreviews(
        candidates: [CaptureCompletionCandidate],
        warnings: [String] = [],
        filter: String = "",
        draft: String = "!",
        replacement: CaptureRange = CaptureRange(start: 0, end: 1),
        continuationKeys: [String] = ["!", "["]
    ) {
        let index = CapturePickerIndex.taskComplete(TaskCompletePickerIndex(candidates: candidates))
        installPickerSessionForPreviews(
            source: .taskComplete,
            index: index,
            candidates: candidates,
            warnings: warnings,
            draftSnapshot: draft,
            replacementRange: replacement,
            restoreCursor: replacement.end,
            filter: filter,
            snapshotIsPartial: false,
            taskCompleteContinuationKeys: continuationKeys
        )
    }

    /// Task Wikilink preview hook: mounts the `((` session production
    /// presents for a decoded `wikilink_task` response, so design tests and
    /// the image review render the card production mounts.
    func installWikilinkTaskPickerForPreviews(
        candidates: [CaptureCompletionCandidate],
        warnings: [String] = [],
        filter: String = "",
        draft: String = "Follow up ((",
        replacement: CaptureRange = CaptureRange(start: 10, end: 12)
    ) {
        let context = WikilinkTaskPickerContext(
            markerRange: replacement,
            triggerRemovalRange: CaptureRange(start: replacement.start + 1, end: replacement.end),
            query: filter
        )
        let index = CapturePickerIndex.wikilinkTask(WikilinkTaskPickerIndex(candidates: candidates))
        installPickerSessionForPreviews(
            source: .wikilinkTask(context),
            index: index,
            candidates: candidates,
            warnings: warnings,
            draftSnapshot: draft,
            replacementRange: replacement,
            restoreCursor: replacement.end,
            filter: filter,
            snapshotIsPartial: false
        )
    }

    /// Block-ID preview hook: mounts the same Link or New ID session
    /// production presents for a decoded `block_id` field, so design tests
    /// and the image review render the card production mounts. `draft` seeds
    /// the editor text (and the marker wash while it still spans the marker
    /// range); pass an explicit `scopeLineNumber` for multi-line drafts.
    func installBlockIDPickerForPreviews(
        field: CaptureBlockIDField?,
        candidates: [CaptureCompletionCandidate],
        context contextName: String,
        replacement: CaptureRange,
        warnings: [String] = [],
        filter: String = "",
        draft: String? = nil,
        restoreCursor: Int? = nil,
        scopeLineNumber: Int? = nil
    ) {
        let response = CaptureCompletionResponse(
            ok: true,
            cursor: replacement.end,
            replacement: replacement,
            context: contextName,
            candidates: candidates,
            warnings: warnings,
            blockID: field
        )
        let source = Self.blockIDSource(for: response)
        let route: String
        if case .blockID(let context) = source {
            route = context.route
        } else {
            route = field?.route ?? ""
        }
        let index = CapturePickerIndex.blockID(
            BlockIDPickerIndex(
                field: field,
                candidates: candidates,
                route: route,
                scope: source.blockIDScope,
                markerLine: field?.markerLine(in: draft ?? "")
            )
        )
        installPickerSessionForPreviews(
            source: source,
            index: index,
            candidates: candidates,
            warnings: warnings,
            draftSnapshot: draft ?? "",
            replacementRange: replacement,
            restoreCursor: restoreCursor ?? replacement.end,
            filter: filter,
            snapshotIsPartial: false,
            scopeLineNumber: scopeLineNumber
        )
    }

    private func installPickerSessionForPreviews(
        source: CapturePickerSource,
        index: CapturePickerIndex,
        candidates: [CaptureCompletionCandidate],
        warnings: [String],
        draftSnapshot: String,
        replacementRange: CaptureRange,
        restoreCursor: Int,
        filter: String,
        snapshotIsPartial: Bool,
        scopeLineNumber: Int? = nil,
        dependencyOwner: DependencyOwner? = nil,
        taskCompleteContinuationKeys: [String] = []
    ) {
        if !draftSnapshot.isEmpty {
            plainDraft = draftSnapshot
        }
        let presentation = index.presentation(filter: filter)
        pickerIndex = index
        pickerPresentation = presentation
        picker = CapturePickerState(
            source: source,
            draftSnapshot: draftSnapshot,
            replacementRange: replacementRange,
            restoreCursor: restoreCursor,
            candidates: candidates,
            warnings: warnings,
            filterText: filter,
            selectedRowID: CapturePickerNavigation.first(in: presentation.orderedRowIDs),
            visibleRowBudget: presentation.visibleRowBudget,
            snapshotIsPartial: snapshotIsPartial,
            scopeLineNumber: scopeLineNumber,
            dependencyOwner: dependencyOwner,
            taskCompleteContinuationKeys: taskCompleteContinuationKeys
        )
        if source == .taskGoto {
            var gotoState = CaptureTaskGotoScopeState()
            gotoState.beginSession(
                candidates: candidates,
                appliedIncludesClosedTasks: false
            )
            gotoClosedTasksState = gotoState
        } else {
            gotoClosedTasksState = nil
        }
        pickerMarkerHighlight = Self.pickerMarkerHighlightRange(
            source: source,
            replacementRange: replacementRange,
            markerRange: Self.blockIDMarkerRange(for: source)
        )
        applyPickerMarkerHighlight()
        applyOwnerModeParentStatus(source: source)
    }

    /// Routes one completion result: `active_task`, `task_link`,
    /// `task_goto`, `task_dependency`, and block-ID responses feed the
    /// picker or the reopen chip and never populate the inline list; every
    /// other context keeps the inline list and clears the chip.
    private static func isRecordCandidate(_ candidate: CaptureCompletionCandidate) -> Bool {
        candidate.recordType != nil
            || candidate.recordContinuation != nil
            || candidate.kind == "record"
            || candidate.kind == "record_create"
    }

    /// Record Card completions are identified by context or the `record`
    /// object. A `route` or `section` list may include `record` rows without
    /// becoming a Record Card completion.
    private static func isRecordCompletion(_ completion: CaptureCompletionResponse) -> Bool {
        completion.context == "record_field"
            || completion.context == "record_value"
            || completion.context == "record_target"
            || completion.record != nil
    }

    private func recordCompletionDidArrive(
        _ completion: CaptureCompletionResponse,
        parse: CaptureParseResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient
    ) -> Bool {
        guard Self.isRecordCompletion(completion) else {
            return true
        }
        guard let request = recordAnalysisRequest,
              request.draft == draft,
              request.generation == generation,
              request.sequence == recordRequestSequence,
              request.processClientIdentity == processClient.identityToken,
              request.cursor == cursor,
              completion.cursor == cursor,
              plainDraft == draft,
              self.processClient === processClient
        else {
            return false
        }
        let itemIndex = Self.recordItemIndex(in: parse, cursor: cursor)
        if let requestedItem = request.itemIndex, requestedItem != itemIndex {
            return false
        }
        if let requestedField = request.fieldKey,
           let returnedField = completion.record?.field,
           returnedField != requestedField
        {
            return false
        }
        let presentation = CaptureRecordPresentation.make(parse: parse, cursor: cursor)
        let recordType = completion.record?.recordType
            ?? completion.candidates.compactMap(\.recordType).first
            ?? presentation?.record.recordType
            ?? ""
        recordCompletionSnapshot = CaptureRecordCompletionSnapshot(
            draft: draft,
            generation: generation,
            sequence: request.sequence,
            processClientIdentity: processClient.identityToken,
            cursor: cursor,
            itemIndex: itemIndex,
            recordType: recordType,
            fieldKey: completion.record?.field ?? request.fieldKey
        )
        if let fieldKey = completion.record?.field,
           let presentation,
           presentation.rows.contains(where: { $0.key == fieldKey })
        {
            let sameItemFocus = recordFocusState?.draft == draft
                && recordFocusState?.itemIndex == presentation.itemIndex
            recordFocusState = CaptureRecordFocusState(
                draft: draft,
                generation: generation,
                sequence: request.sequence,
                clientIdentity: processClient.identityToken,
                itemIndex: presentation.itemIndex,
                fieldKey: fieldKey,
                showsMore: sameItemFocus
                    ? recordFocusState?.showsMore ?? presentation.showsMore
                    : presentation.showsMore,
                selectedRowKey: fieldKey
            )
            recordPresentation = CaptureRecordPresentation(
                record: presentation.record,
                itemIndex: presentation.itemIndex,
                rows: presentation.rows,
                activeFieldKey: fieldKey,
                selectedRowKey: fieldKey,
                showsMore: recordFocusState?.showsMore ?? presentation.showsMore
            )
        }
        return true
    }

    private func handleCompletionResponse(
        _ completion: CaptureCompletionResponse,
        parse: CaptureParseResponse,
        draft: String,
        cursor: Int,
        trigger: CompletionTrigger,
        writtenRange: CaptureRange?,
        generation: UInt64,
        processClient: BobProcessClient
    ) async {
        guard isCurrentAnalysis(generation) else {
            return
        }
        guard recordCompletionDidArrive(
            completion,
            parse: parse,
            draft: draft,
            cursor: cursor,
            generation: generation,
            processClient: processClient
        ) else {
            return
        }
        // While the picker is open, analysis results never modify picker or
        // chip state and never populate the inline list — except a live
        // relation flip: a `relation_to` ↔ `relation_from` completion at the
        // same replacement start re-presents in place and keeps the filter.
        if let openPicker = picker,
           openPicker.source.isRelation,
           let context = completion.context,
           context == "relation_to" || context == "relation_from",
           completion.replacement.start == openPicker.replacementRange.start
        {
            await handleRelationLiveFlip(
                completion,
                draft: draft,
                cursor: cursor,
                generation: generation,
                processClient: processClient,
                keptFilter: openPicker.filterText,
                restoreCursor: openPicker.restoreCursor
            )
            return
        }
        if picker != nil {
            if Self.isRecordCompletion(completion) {
                closePickerForAccept()
            } else {
                dismissCompletion()
                return
            }
        }
        if let context = completion.context, context == "task_link" || context == "task_goto" {
            await handleTaskLinkCompletion(
                completion,
                draft: draft,
                cursor: cursor,
                generation: generation,
                processClient: processClient,
                trigger: trigger,
                source: context == "task_goto" ? .taskGoto : .taskLink,
                expectedContext: context
            )
            return
        }
        if completion.context == "task_parent" {
            let mergeInTargetTitle = Self.mergeInTargetTitle(
                in: parse,
                replacement: completion.replacement
            )
            await handleParentTaskCompletion(
                completion,
                mergeInTargetTitle: mergeInTargetTitle,
                draft: draft,
                cursor: cursor,
                generation: generation,
                processClient: processClient,
                trigger: trigger
            )
            return
        }
        if completion.context == "task",
           let picker = completion.picker,
           picker.isParentTask,
           picker.parentTaskContext != nil
        {
            let mergeInTargetTitle = Self.mergeInTargetTitle(
                in: parse,
                replacement: completion.replacement
            )
            await handleParentTaskCompletion(
                completion,
                mergeInTargetTitle: mergeInTargetTitle,
                draft: draft,
                cursor: cursor,
                generation: generation,
                processClient: processClient,
                trigger: trigger
            )
            return
        }
        if completion.context == "project_task_move" {
            await handleProjectTaskMoveCompletion(
                completion,
                draft: draft,
                cursor: cursor,
                generation: generation,
                processClient: processClient,
                trigger: trigger
            )
            return
        }
        if completion.context == "task_dependency" || completion.context == "blocked_task"
            || completion.context == "relation_to" || completion.context == "relation_from"
        {
            let direction: DependencyPickerDirection
            switch completion.context {
            case "blocked_task":
                direction = .blocks
            case "relation_to":
                direction = .linksTo
            case "relation_from":
                direction = .linkedFrom
            default:
                direction = .prerequisite
            }
            await handleDependencyCompletion(
                completion,
                draft: draft,
                cursor: cursor,
                generation: generation,
                processClient: processClient,
                trigger: trigger,
                direction: direction,
                expectedContext: completion.context ?? "task_dependency"
            )
            return
        }
        if completion.context == "task_complete" {
            await handleTaskCompleteCompletion(
                completion,
                draft: draft,
                cursor: cursor,
                generation: generation,
                processClient: processClient,
                trigger: trigger
            )
            return
        }
        if completion.context == "wikilink_task" {
            await handleWikilinkTaskCompletion(
                completion,
                draft: draft,
                cursor: cursor,
                generation: generation,
                processClient: processClient,
                trigger: trigger,
                writtenRange: writtenRange
            )
            return
        }
        if completion.context == "relation_label" {
            await handleRelationLabelCompletion(
                completion,
                draft: draft,
                cursor: cursor,
                generation: generation,
                trigger: trigger
            )
            return
        }
        guard completion.context == "active_task" else {
            if completion.context == "pomodoro_block_id" || completion.context == "task_block_id"
                || completion.context == "project_task_block_id"
            {
                await handleBlockIDCompletion(
                    completion,
                    draft: draft,
                    cursor: cursor,
                    generation: generation,
                    processClient: processClient,
                    trigger: trigger,
                    writtenRange: writtenRange
                )
                return
            }
            applyNonActiveTaskCompletion(completion, draft: draft, trigger: trigger)
            return
        }
        await handleActiveTaskCompletion(
            completion,
            draft: draft,
            cursor: cursor,
            generation: generation,
            processClient: processClient,
            trigger: trigger,
            writtenRange: writtenRange
        )
    }

    /// A block-ID response is usable when it is `pomodoro_block_id` (older
    /// Bob binaries omit the `block_id` object there and still get a Link
    /// picker without New ID rows) or `task_block_id` / `project_task_block_id`
    /// with a `block_id` object. A response in either newer context without one
    /// is treated as no completion: older Bob never sends those contexts at
    /// all, so there is no picker and no inline list.
    private static func isUsableBlockIDCompletion(_ completion: CaptureCompletionResponse) -> Bool {
        if completion.context == "pomodoro_block_id" {
            return true
        }
        return (completion.context == "task_block_id"
            || completion.context == "project_task_block_id")
            && completion.blockID != nil
    }

    /// Builds the picker source for a usable block-ID response: the decoded
    /// field (nil for older Bob), the route, the marker, the intent (older
    /// Bob means Link), Bob's ID rules, and the project-task scope for
    /// `project_task_block_id` (a trailing ` :id` / ` ^id` token inside a
    /// project-note item, which names an ID in the new project note).
    private static func blockIDSource(for completion: CaptureCompletionResponse) -> CapturePickerSource {
        let field = completion.blockID
        let marker: String
        if let fieldMarker = field?.marker, !fieldMarker.isEmpty {
            marker = fieldMarker
        } else {
            marker = completion.context == "task_block_id" ? "^" : ":"
        }
        let route: String
        if let fieldRoute = field?.route, !fieldRoute.isEmpty {
            route = fieldRoute
        } else {
            route = completion.candidates.first?.route ?? ""
        }
        let intent = field?.intent ?? .link
        let rules = field.flatMap {
            BlockIDRules(allowedCharacter: $0.allowedCharacter, description: $0.allowedDescription)
        }
        let scope: CaptureBlockIDScope =
            completion.context == "project_task_block_id" ? .projectTask : .note
        return .blockID(
            BlockIDPickerContext(
                field: field,
                route: route,
                marker: marker,
                intent: intent,
                rules: rules,
                scope: scope
            )
        )
    }

    /// Routes `pomodoro_block_id`/`task_block_id`/`project_task_block_id`
    /// responses into the generic picker with intent-aware opening rules.
    /// `project_task_block_id` always carries intent `new`, so it follows the
    /// New ID rules below with the project-task scope. An exact Link part opens
    /// nothing. Otherwise either intent auto-opens only when this edit wrote
    /// the separator byte immediately before Bob's ID part; caret-only moves,
    /// Escape suppression, and other edits show the reopen chip. New ID still
    /// requires an empty part or the caret at the part's end (typing forward).
    private func handleBlockIDCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger,
        writtenRange: CaptureRange?
    ) async {
        // Block-ID responses never populate the inline list, even when empty.
        dismissCompletion(preservePendingAliasTip: true)
        defer {
            if picker == nil {
                deferAliasTipOpportunity(reason: .unanchored)
            }
        }
        guard Self.isUsableBlockIDCompletion(completion) else {
            clearPickerInterruption(trigger: trigger)
            return
        }
        let r = completion.replacement
        let separatorTyped = captureEditWroteSeparator(writtenRange, before: r.start)
        guard stringRange(in: draft, byteRange: r) != nil,
              stringRange(in: draft, start: r.start, end: min(cursor, r.end)) != nil
        else {
            return
        }
        let source = Self.blockIDSource(for: completion)
        guard case .blockID(let context) = source else {
            return
        }
        if !context.isNewIDMode {
            let partRange = stringRange(in: draft, byteRange: r)!
            let part = String(draft[partRange])
            if completion.candidates.contains(where: { $0.replacement == part }) {
                // The token is already an exact candidate: no picker, no chip.
                clearPickerInterruption(trigger: trigger)
                return
            }
            guard trigger == .edit, separatorTyped, pickerAutoOpenSuppressedStart != r.start else {
                pickerChip = CapturePickerChipState(
                    source: source,
                    draftSnapshot: draft,
                    replacementRange: r,
                    cursor: cursor,
                    candidates: completion.candidates,
                    warnings: completion.warnings
                )
                return
            }
            let query = Self.pickerQuery(in: draft, range: r, cursor: cursor)
            if cursor != r.start {
                // Fetch the unfiltered snapshot at the token start in this
                // same analysis task; Bob answers the full list there.
                if let snapshot = try? await processClient.captureComplete(draft, cursor: r.start),
                   isCurrentAnalysis(generation),
                   plainDraft == draft,
                   Self.isUsableBlockIDCompletion(snapshot),
                   snapshot.replacement == r
                {
                    presentBlockIDPicker(
                        snapshot,
                        draft: draft,
                        range: r,
                        restoreCursor: cursor,
                        query: query,
                        snapshotIsPartial: false
                    )
                    return
                }
                // Fall back to the caret response and say so in the view.
                guard isCurrentAnalysis(generation), plainDraft == draft else {
                    return
                }
                presentBlockIDPicker(
                    completion,
                    draft: draft,
                    range: r,
                    restoreCursor: cursor,
                    query: query,
                    snapshotIsPartial: true
                )
                return
            }
            presentBlockIDPicker(
                completion,
                draft: draft,
                range: r,
                restoreCursor: cursor,
                query: query,
                snapshotIsPartial: false
            )
            return
        }
        guard trigger == .edit, separatorTyped, pickerAutoOpenSuppressedStart != r.start else {
            pickerChip = CapturePickerChipState(
                source: source,
                draftSnapshot: draft,
                replacementRange: r,
                cursor: cursor,
                candidates: completion.candidates,
                warnings: completion.warnings
            )
            return
        }
        let partRange = stringRange(in: draft, byteRange: r)!
        let part = String(draft[partRange])
        guard part.isEmpty || cursor == r.end else {
            // A mid-part edit, or a caret that is not typing forward, shows
            // the chip instead of opening.
            pickerChip = CapturePickerChipState(
                source: source,
                draftSnapshot: draft,
                replacementRange: r,
                cursor: cursor,
                candidates: completion.candidates,
                warnings: completion.warnings
            )
            return
        }
        presentBlockIDPicker(
            completion,
            draft: draft,
            range: r,
            restoreCursor: cursor,
            query: part,
            snapshotIsPartial: false
        )
    }

    /// Presents a usable block-ID snapshot through the generic picker. The
    /// seed is the caller's query: range-start-to-caret for Link, the whole
    /// part for New ID.
    private func presentBlockIDPicker(
        _ completion: CaptureCompletionResponse,
        draft: String,
        range: CaptureRange,
        restoreCursor: Int,
        query: String,
        snapshotIsPartial: Bool
    ) {
        let source = Self.blockIDSource(for: completion)
        guard case .blockID(let context) = source else {
            return
        }
        let index = CapturePickerIndex.blockID(
            BlockIDPickerIndex(
                field: completion.blockID,
                candidates: completion.candidates,
                route: context.route,
                scope: context.scope,
                markerLine: completion.blockID?.markerLine(in: draft)
            )
        )
        presentPicker(
            source: source,
            index: index,
            candidates: completion.candidates,
            warnings: completion.warnings,
            draft: draft,
            range: range,
            restoreCursor: restoreCursor,
            query: query,
            snapshotIsPartial: snapshotIsPartial,
            opensWithoutSelection: completion.opensWithoutSelection
        )
    }

    private func applyNonActiveTaskCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        trigger: CompletionTrigger
    ) {
        if picker != nil {
            dismissCompletion()
            return
        }
        clearPickerInterruption(trigger: trigger)
        let keepsRecordEdit = Self.isRecordCompletion(completion)
            && completion.record?.edit != nil
        let keepsEmptyPlaceMenu = Self.hasVisiblePlaceMenuHint(completion)
        let oldResponse = completionResponse
        let oldIndex = selectedCompletionIndex
        let retainedKey: PlaceMenuCandidateKey? = {
            guard placeMenuSelectionWasExplicit,
                  let oldResponse,
                  let oldIndex,
                  oldResponse.candidates.indices.contains(oldIndex)
            else {
                return nil
            }
            return Self.placeMenuCandidateKey(oldResponse.candidates[oldIndex])
        }()
        let oldScope = oldResponse.flatMap(Self.placeMenuScope)

        completionResponse = completion.candidates.isEmpty && !keepsRecordEdit && !keepsEmptyPlaceMenu
            ? nil : completion
        completionDraftSnapshot = completionResponse == nil ? nil : draft
        let newScope = Self.placeMenuScope(completion)
        let preservedIndex: Int? = {
            guard let retainedKey, oldScope == newScope, newScope != nil else {
                return nil
            }
            return completion.candidates.firstIndex { candidate in
                !CaptureCompletionMenu.isDisabled(candidate)
                    && Self.placeMenuCandidateKey(candidate) == retainedKey
            }
        }()
        if preservedIndex != nil {
            selectedCompletionIndex = preservedIndex
            placeMenuSelectionWasExplicit = true
        } else if completion.placeMenu?.kind == "notebook_section" {
            selectedCompletionIndex = Self.notebookPlaceMenuInitialIndex(completion)
            placeMenuSelectionWasExplicit = false
        } else {
            selectedCompletionIndex = CaptureCompletionMenu.initialSelectedIndex(
                for: completion,
                queryIsEmpty: completionQueryText().isEmpty
            )
            placeMenuSelectionWasExplicit = false
        }
        // A fresh server or cached completion is never the File-under list:
        // only the File-under opener sets the header back below.
        fileUnderActive = false
        // A `pomodoro_start_name` list that opened on the quiet incomplete
        // picker (`=#`, `=3#`) still shows that calm status line: refresh
        // it from Bob's override object once completion arrives, so a `=#`
        // pick names the running session it displaces. Any other status (a
        // live preview, a prompt) is left alone.
        if completion.context == "pomodoro_start_name",
           statusText == CapturePickerNeed.pomodoroStart.statusText
        {
            statusText = pomodoroStartPickerStatus(override: completion.overrideInfo)
        }
        applyCompletionWarnings(completion.warnings)
        consumePendingAliasTipOnListUpdate(draft: draft)
        if !completionVisible {
            presentedAliasTip = nil
        }
    }

    /// An analysis that ends with no completion at all (nothing requested, or
    /// nothing offered) still retires the `^` affordances per trigger.
    private func handleMissingCompletion(trigger: CompletionTrigger) {
        if picker != nil {
            deferAliasTipOpportunity(reason: .unanchored)
            dismissCompletion(
                cancelPendingRecordReturn: false,
                preservePendingAliasTip: true
            )
            return
        }
        clearPickerInterruption(trigger: trigger)
        // This is the analysis Return is waiting on. Clearing the empty
        // completion list must not cancel that submit.
        deferAliasTipOpportunity(reason: .unanchored)
        dismissCompletion(
            cancelPendingRecordReturn: false,
            preservePendingAliasTip: true
        )
    }

    /// An `.edit` analysis without an `active_task` result leaves the token:
    /// it clears the suppression and the chip. A `.selection` analysis only
    /// ever clears the chip.
    private func clearPickerInterruption(trigger: CompletionTrigger) {
        if trigger == .edit {
            pickerAutoOpenSuppressedStart = nil
            gotoClosedTasksState = nil
        }
        pickerChip = nil
    }

    /// An exact candidate opens nothing. Otherwise auto-open only when the
    /// edit wrote the `^` before Bob's replacement range and the token is not
    /// suppressed; other edits and caret-only moves offer the reopen chip.
    private func handleActiveTaskCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger,
        writtenRange: CaptureRange?
    ) async {
        // An `active_task` response never sets `completionResponse`, even when
        // `candidates` is empty.
        dismissCompletion(preservePendingAliasTip: true)
        defer {
            if picker == nil {
                deferAliasTipOpportunity(reason: .unanchored)
            }
        }
        let r = completion.replacement
        guard stringRange(in: draft, byteRange: r) != nil,
              stringRange(in: draft, start: r.start, end: min(cursor, r.end)) != nil
        else {
            return
        }
        let partRange = stringRange(in: draft, byteRange: r)!
        let part = String(draft[partRange])
        if completion.candidates.contains(where: { $0.replacement == part }) {
            // The token is already an exact candidate: no picker, no chip.
            clearPickerInterruption(trigger: trigger)
            return
        }
        let triggerTyped = captureEditWroteSeparator(writtenRange, before: r.start)
        guard trigger == .edit, triggerTyped, pickerAutoOpenSuppressedStart != r.start else {
            pickerChip = CapturePickerChipState(
                source: .activeTask,
                draftSnapshot: draft,
                replacementRange: r,
                cursor: cursor,
                candidates: completion.candidates,
                warnings: completion.warnings
            )
            return
        }
        let query = Self.pickerQuery(in: draft, range: r, cursor: cursor)
        if cursor != r.start {
            // Fetch the unfiltered snapshot at the token start in this same
            // analysis task; Bob answers the full list there.
            if let snapshot = try? await processClient.captureComplete(draft, cursor: r.start),
               isCurrentAnalysis(generation),
               plainDraft == draft,
               snapshot.context == "active_task",
               snapshot.replacement == r
            {
                presentPicker(
                    source: .activeTask,
                    index: .activeTask(ActiveTaskPickerIndex(candidates: snapshot.candidates)),
                    candidates: snapshot.candidates,
                    warnings: snapshot.warnings,
                    draft: draft,
                    range: r,
                    restoreCursor: cursor,
                    query: query,
                    snapshotIsPartial: false,
                    opensWithoutSelection: snapshot.opensWithoutSelection
                )
                return
            }
            // Fall back to the caret response and say so in the view.
            guard isCurrentAnalysis(generation), plainDraft == draft else {
                return
            }
            presentPicker(
                source: .activeTask,
                index: .activeTask(ActiveTaskPickerIndex(candidates: completion.candidates)),
                candidates: completion.candidates,
                warnings: completion.warnings,
                draft: draft,
                range: r,
                restoreCursor: cursor,
                query: query,
                snapshotIsPartial: true,
                opensWithoutSelection: completion.opensWithoutSelection
            )
            return
        }
        presentPicker(
            source: .activeTask,
            index: .activeTask(ActiveTaskPickerIndex(candidates: completion.candidates)),
            candidates: completion.candidates,
            warnings: completion.warnings,
            draft: draft,
            range: r,
            restoreCursor: cursor,
            query: query,
            snapshotIsPartial: false,
            opensWithoutSelection: completion.opensWithoutSelection
        )
    }

    /// Routes a `task_link` or `task_goto` completion response into the picker
    /// card: dismiss the inline list, auto-open only on `.edit` when not
    /// suppressed, show the
    /// chip on `.selection`, and refetch the full list at `r.start` when the
    /// caret is past the sigil. The catalog source decides the index mode
    /// (link vs Go To) and the expected Bob context.
    private func handleTaskLinkCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger,
        source: CapturePickerSource = .taskLink,
        expectedContext: String = "task_link"
    ) async {
        // A catalog response never sets `completionResponse`, even when
        // `candidates` is empty.
        dismissCompletion(preservePendingAliasTip: true)
        defer {
            if picker == nil {
                deferAliasTipOpportunity(reason: .unanchored)
            }
        }
        let r = completion.replacement
        guard stringRange(in: draft, byteRange: r) != nil,
              stringRange(in: draft, start: r.start, end: min(cursor, r.end)) != nil
        else {
            return
        }
        guard trigger == .edit, pickerAutoOpenSuppressedStart != r.start else {
            pickerChip = CapturePickerChipState(
                source: source,
                draftSnapshot: draft,
                replacementRange: r,
                cursor: cursor,
                candidates: completion.candidates,
                warnings: completion.warnings
            )
            return
        }
        let query = Self.taskLinkPickerQuery(in: draft, range: r, cursor: cursor)
        if cursor > r.start + 1 {
            if let snapshot = try? await processClient.captureComplete(draft, cursor: r.start),
               isCurrentAnalysis(generation),
               plainDraft == draft,
               snapshot.context == expectedContext,
               snapshot.replacement == r
            {
                presentPicker(
                    source: source,
                    index: Self.taskCatalogIndex(source: source, candidates: snapshot.candidates),
                    candidates: snapshot.candidates,
                    warnings: snapshot.warnings,
                    draft: draft,
                    range: r,
                    restoreCursor: cursor,
                    query: query,
                    snapshotIsPartial: false,
                    opensWithoutSelection: snapshot.opensWithoutSelection
                )
                return
            }
            guard isCurrentAnalysis(generation), plainDraft == draft else {
                return
            }
            presentPicker(
                source: source,
                index: Self.taskCatalogIndex(source: source, candidates: completion.candidates),
                candidates: completion.candidates,
                warnings: completion.warnings,
                draft: draft,
                range: r,
                restoreCursor: cursor,
                query: query,
                snapshotIsPartial: true,
                opensWithoutSelection: completion.opensWithoutSelection
            )
            return
        }
        presentPicker(
            source: source,
            index: Self.taskCatalogIndex(source: source, candidates: completion.candidates),
            candidates: completion.candidates,
            warnings: completion.warnings,
            draft: draft,
            range: r,
            restoreCursor: cursor,
            query: query,
            snapshotIsPartial: false,
            opensWithoutSelection: completion.opensWithoutSelection
        )
    }

    private static func taskCatalogIndex(
        source: CapturePickerSource,
        candidates: [CaptureCompletionCandidate]
    ) -> CapturePickerIndex {
        if source == .taskGoto {
            return .taskGoto(TaskLinkPickerIndex(candidates: candidates, mode: .taskGoto))
        }
        return .taskLink(TaskLinkPickerIndex(candidates: candidates))
    }

    /// Routes `task_parent` and descriptor-bearing scoped `task` responses
    /// into the parent-task picker card. Older Bob `task` without a picker
    /// descriptor stays on the inline list. Vault refetch mirrors `:`
    /// (`cursor > r.start + 1`); scoped refetch mirrors `^` (`cursor !=
    /// r.start`). Bob's `query` seeds the filter when present.
    private func handleParentTaskCompletion(
        _ completion: CaptureCompletionResponse,
        mergeInTargetTitle: String?,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger
    ) async {
        dismissCompletion(preservePendingAliasTip: true)
        defer {
            if picker == nil {
                deferAliasTipOpportunity(reason: .unanchored)
            }
        }
        guard let baseContext = completion.picker?.parentTaskContext else {
            clearPickerInterruption(trigger: trigger)
            return
        }
        let context = mergeInTargetTitle.map {
            baseContext.asMergeInSource(targetTitle: $0)
        } ?? baseContext
        let r = completion.replacement
        guard stringRange(in: draft, byteRange: r) != nil,
              stringRange(in: draft, start: r.start, end: min(cursor, r.end)) != nil
        else {
            return
        }
        let partRange = stringRange(in: draft, byteRange: r)!
        let part = String(draft[partRange])
        if !context.isVault,
           completion.candidates.contains(where: { $0.replacement == part && !$0.replacement.isEmpty })
        {
            clearPickerInterruption(trigger: trigger)
            return
        }
        let source = CapturePickerSource.parentTask(context)
        guard trigger == .edit, pickerAutoOpenSuppressedStart != r.start else {
            pickerChip = CapturePickerChipState(
                source: source,
                draftSnapshot: draft,
                replacementRange: r,
                cursor: cursor,
                candidates: completion.candidates,
                warnings: completion.warnings
            )
            return
        }
        let query = completion.query ?? Self.parentTaskPickerQuery(
            in: draft,
            range: r,
            cursor: cursor,
            context: context
        )
        let needsRefetch = context.isVault ? cursor > r.start + 1 : cursor != r.start
        if needsRefetch {
            if let snapshot = try? await processClient.captureComplete(draft, cursor: r.start),
               isCurrentAnalysis(generation),
               plainDraft == draft,
               Self.isMatchingParentTaskSnapshot(snapshot, expected: completion, context: context),
               snapshot.replacement == r
            {
                if !context.isVault {
                    let snapshotPart = stringRange(in: draft, byteRange: r).map { String(draft[$0]) } ?? part
                    if snapshot.candidates.contains(where: {
                        $0.replacement == snapshotPart && !$0.replacement.isEmpty
                    }) {
                        clearPickerInterruption(trigger: trigger)
                        return
                    }
                }
                presentParentTaskPicker(
                    snapshot,
                    context: context,
                    draft: draft,
                    range: r,
                    restoreCursor: cursor,
                    query: query,
                    snapshotIsPartial: false
                )
                return
            }
            guard isCurrentAnalysis(generation), plainDraft == draft else {
                return
            }
            presentParentTaskPicker(
                completion,
                context: context,
                draft: draft,
                range: r,
                restoreCursor: cursor,
                query: query,
                snapshotIsPartial: true
            )
            return
        }
        presentParentTaskPicker(
            completion,
            context: context,
            draft: draft,
            range: r,
            restoreCursor: cursor,
            query: query,
            snapshotIsPartial: false
        )
    }

    private static func isMatchingParentTaskSnapshot(
        _ snapshot: CaptureCompletionResponse,
        expected: CaptureCompletionResponse,
        context: ParentTaskPickerContext
    ) -> Bool {
        if context.isVault {
            return snapshot.context == "task_parent"
        }
        return snapshot.context == expected.context
            && snapshot.picker?.parentTaskContext?.scope == context.scope
    }

    private func presentParentTaskPicker(
        _ completion: CaptureCompletionResponse,
        context: ParentTaskPickerContext,
        draft: String,
        range: CaptureRange,
        restoreCursor: Int,
        query: String,
        snapshotIsPartial: Bool
    ) {
        presentPicker(
            source: .parentTask(context),
            index: .parentTask(ParentTaskPickerIndex(candidates: completion.candidates, context: context)),
            candidates: completion.candidates,
            warnings: completion.warnings,
            draft: draft,
            range: range,
            restoreCursor: restoreCursor,
            query: query,
            snapshotIsPartial: snapshotIsPartial,
            opensWithoutSelection: completion.opensWithoutSelection
        )
    }

    /// Parent-task filter seed: Bob's `query` is preferred by the caller.
    /// Vault strips the `+` sigil; scoped uses the ID-only range.
    private static func parentTaskPickerQuery(
        in draft: String,
        range: CaptureRange,
        cursor: Int,
        context: ParentTaskPickerContext
    ) -> String {
        let start = context.isVault ? range.start + 1 : range.start
        guard start <= range.end,
              let queryRange = stringRange(in: draft, start: start, end: min(cursor, range.end))
        else {
            return ""
        }
        return String(draft[queryRange])
    }

    /// Routes `project_task_move` responses into the move picker card.
    /// The replacement covers only the ID; the typed sigil survives. Stale
    /// drafts never edit: generation, draft-snapshot, and parent-route
    /// checks all hold before presenting.
    private func handleProjectTaskMoveCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger
    ) async {
        dismissCompletion(preservePendingAliasTip: true)
        defer {
            if picker == nil {
                deferAliasTipOpportunity(reason: .unanchored)
            }
        }
        guard let context = completion.picker?.projectTaskMoveContext else {
            clearPickerInterruption(trigger: trigger)
            return
        }
        let r = completion.replacement
        guard stringRange(in: draft, byteRange: r) != nil,
              stringRange(in: draft, start: r.start, end: min(cursor, r.end)) != nil
        else {
            return
        }
        let source = CapturePickerSource.projectTaskMove(context)
        guard trigger == .edit, pickerAutoOpenSuppressedStart != r.start else {
            pickerChip = CapturePickerChipState(
                source: source,
                draftSnapshot: draft,
                replacementRange: r,
                cursor: cursor,
                candidates: completion.candidates,
                warnings: completion.warnings
            )
            return
        }
        let query = completion.query ?? Self.projectTaskMovePickerQuery(
            in: draft,
            range: r,
            cursor: cursor
        )
        let needsRefetch = cursor != r.start
        if needsRefetch {
            if let snapshot = try? await processClient.captureComplete(draft, cursor: r.start),
               isCurrentAnalysis(generation),
               plainDraft == draft,
               Self.isMatchingProjectTaskMoveSnapshot(snapshot, expected: completion, context: context),
               snapshot.replacement == r
            {
                presentProjectTaskMovePicker(
                    snapshot,
                    context: context,
                    draft: draft,
                    range: r,
                    restoreCursor: cursor,
                    query: query,
                    snapshotIsPartial: false
                )
                return
            }
            guard isCurrentAnalysis(generation), plainDraft == draft else {
                return
            }
            presentProjectTaskMovePicker(
                completion,
                context: context,
                draft: draft,
                range: r,
                restoreCursor: cursor,
                query: query,
                snapshotIsPartial: true
            )
            return
        }
        presentProjectTaskMovePicker(
            completion,
            context: context,
            draft: draft,
            range: r,
            restoreCursor: cursor,
            query: query,
            snapshotIsPartial: false
        )
    }

    private static func isMatchingProjectTaskMoveSnapshot(
        _ snapshot: CaptureCompletionResponse,
        expected: CaptureCompletionResponse,
        context: ProjectTaskMovePickerContext
    ) -> Bool {
        guard snapshot.context == "project_task_move" else {
            return false
        }
        guard let snapshotContext = snapshot.picker?.projectTaskMoveContext else {
            return false
        }
        if snapshotContext.noteTarget != context.noteTarget {
            return false
        }
        if snapshotContext.scopeToken != context.scopeToken {
            return false
        }
        if let expectedParent = expected.projectTaskMove?.parentRoute,
           let snapshotParent = snapshot.projectTaskMove?.parentRoute,
           expectedParent != snapshotParent
        {
            return false
        }
        return true
    }

    private func presentProjectTaskMovePicker(
        _ completion: CaptureCompletionResponse,
        context: ProjectTaskMovePickerContext,
        draft: String,
        range: CaptureRange,
        restoreCursor: Int,
        query: String,
        snapshotIsPartial: Bool
    ) {
        let enriched = ProjectTaskMovePickerContext(
            scopeToken: context.scopeToken,
            noteTarget: context.noteTarget,
            destination: context.destination,
            continuation: context.continuation,
            markerRange: context.markerRange,
            triggerRemovalRange: context.triggerRemovalRange,
            openCount: completion.projectTaskMove?.openCount,
            actionContinuationKeys: context.actionContinuationKeys,
            actionContinuationAliases: context.actionContinuationAliases
        )
        presentPicker(
            source: .projectTaskMove(enriched),
            index: .projectTaskMove(ProjectTaskMovePickerIndex(candidates: completion.candidates, context: enriched)),
            candidates: completion.candidates,
            warnings: completion.warnings,
            draft: draft,
            range: range,
            restoreCursor: restoreCursor,
            query: query,
            snapshotIsPartial: snapshotIsPartial,
            opensWithoutSelection: completion.opensWithoutSelection
        )
    }

    /// Move-picker filter seed: the ID-only range, so the typed sigil never
    /// enters the filter.
    private static func projectTaskMovePickerQuery(
        in draft: String,
        range: CaptureRange,
        cursor: Int
    ) -> String {
        guard let queryRange = stringRange(in: draft, start: range.start, end: min(cursor, range.end)) else {
            return ""
        }
        return String(draft[queryRange])
    }

    /// Calm Esc status for the move picker: leaves the lone sigil so the
    /// draft stays incomplete instead of silently becoming an empty task.
    private func movePickerEscStatus(context: ProjectTaskMovePickerContext) -> String {
        context.escStatusText
    }

    /// The filter seed: the draft text typed after `^` so far, by UTF-8 byte
    /// range. Text typed before the picker appears seeds the filter.
    private static func pickerQuery(in draft: String, range: CaptureRange, cursor: Int) -> String {
        guard let queryRange = stringRange(in: draft, start: range.start, end: min(cursor, range.end)) else {
            return ""
        }
        return String(draft[queryRange])
    }

    /// The `:` filter seed: draft bytes `(r.start + 1)..<caret`, so the sigil
    /// itself never filters. The index also strips a leading `:` defensively.
    private static func taskLinkPickerQuery(in draft: String, range: CaptureRange, cursor: Int) -> String {
        let start = range.start + 1
        guard start <= range.end,
              let queryRange = stringRange(in: draft, start: start, end: min(cursor, range.end))
        else {
            return ""
        }
        return String(draft[queryRange])
    }

    /// Routes a `task_dependency` completion response into the picker card,
    /// mirroring `handleTaskLinkCompletion`: dismiss the inline list,
    /// auto-open only on `.edit` when not suppressed, show the chip on
    /// `.selection`, and refetch the full list at `r.start` when the caret
    /// is past it. Choosing a prerequisite stays allowed before the
    /// dependent exists: the owner rides along for the header and capture
    /// follow-up gate, never to block the pick itself.
    private func handleDependencyCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger,
        direction: DependencyPickerDirection,
        expectedContext: String
    ) async {
        // A `task_dependency` response never sets `completionResponse`, even
        // when `candidates` is empty.
        dismissCompletion(preservePendingAliasTip: true)
        defer {
            if picker == nil {
                deferAliasTipOpportunity(reason: .unanchored)
            }
        }
        let r = completion.replacement
        guard stringRange(in: draft, byteRange: r) != nil,
              stringRange(in: draft, start: r.start, end: min(cursor, r.end)) != nil
        else {
            return
        }
        let source = Self.pickerSource(for: direction)
        // A sigil alias replaces its key through the native editor before
        // requesting completion. AppKit can deliver a caret-selection
        // analysis for that splice, so let the still-matching one-shot arm
        // open its picker even when that analysis wins the race with the
        // edit-triggered request.
        let openedBySigilAlias = equalsGestureArm.map {
            $0.isOpener
                && $0.surface == .editor
                && $0.sigil == direction.leadingSigil
                && $0.postDraft == draft
                && $0.preCaretUTF8 == r.start
                && $0.postCaretUTF8 == cursor
                && cursor == r.end
        } == true
        // `~=` and `~~=` replace their trailing sigil through the native
        // editor before requesting completion. Their output direction comes
        // from Bob's parse, so the matching arm allows either relation picker.
        let openedByRelationFlipAlias =
            relationFlipAliasOpen.map {
                $0.draft == draft
                    && $0.caretUTF8 == cursor
                    && cursor == r.end
            } == true
        guard trigger == .edit || openedBySigilAlias || openedByRelationFlipAlias,
            pickerAutoOpenSuppressedStart != r.start
        else {
            var chip = CapturePickerChipState(
                source: source,
                draftSnapshot: draft,
                replacementRange: r,
                cursor: cursor,
                candidates: completion.candidates,
                warnings: completion.warnings
            )
            chip.dependencyOwner = completion.owner
            pickerChip = chip
            return
        }
        let query = Self.dependencyPickerQuery(
            in: draft,
            range: r,
            cursor: cursor,
            leadingSigil: direction.leadingSigil
        )
        let sigilBytes = direction.leadingSigil.utf8.count
        if cursor > r.start + sigilBytes {
            if let snapshot = try? await processClient.captureComplete(draft, cursor: r.start),
               isCurrentAnalysis(generation),
               plainDraft == draft,
               snapshot.context == expectedContext,
               snapshot.replacement == r
            {
                presentPicker(
                    source: source,
                    index: Self.dependencyPickerIndex(snapshot.candidates, direction: direction),
                    candidates: snapshot.candidates,
                    warnings: snapshot.warnings,
                    draft: draft,
                    range: r,
                    restoreCursor: cursor,
                    query: query,
                    snapshotIsPartial: false,
                    dependencyOwner: snapshot.owner,
                    opensWithoutSelection: snapshot.opensWithoutSelection
                )
                return
            }
            guard isCurrentAnalysis(generation), plainDraft == draft else {
                return
            }
            presentPicker(
                source: source,
                index: Self.dependencyPickerIndex(completion.candidates, direction: direction),
                candidates: completion.candidates,
                warnings: completion.warnings,
                draft: draft,
                range: r,
                restoreCursor: cursor,
                query: query,
                snapshotIsPartial: true,
                dependencyOwner: completion.owner,
                opensWithoutSelection: completion.opensWithoutSelection
            )
            return
        }
        presentPicker(
            source: source,
            index: Self.dependencyPickerIndex(completion.candidates, direction: direction),
            candidates: completion.candidates,
            warnings: completion.warnings,
            draft: draft,
            range: r,
            restoreCursor: cursor,
            query: query,
            snapshotIsPartial: false,
            dependencyOwner: completion.owner,
            opensWithoutSelection: completion.opensWithoutSelection
        )
    }

    /// The directional dependency filter seed: text after the `&` or `*`
    /// sigil. Quoted locators stay raw; Bob's decoded query remains
    /// authoritative for anything but the seed.
    private static func dependencyPickerQuery(
        in draft: String,
        range: CaptureRange,
        cursor: Int,
        leadingSigil: String = "&"
    ) -> String {
        let start = range.start + leadingSigil.utf8.count
        guard start <= range.end,
              let queryRange = stringRange(in: draft, start: start, end: min(cursor, range.end))
        else {
            return ""
        }
        return String(draft[queryRange])
    }

    private static func dependencyPickerIndex(
        _ candidates: [CaptureCompletionCandidate],
        direction: DependencyPickerDirection
    ) -> CapturePickerIndex {
        let index = DependencyPickerIndex(candidates: candidates, direction: direction)
        switch direction {
        case .blocks:
            return .blockedTask(index)
        case .prerequisite:
            return .dependency(index)
        case .linksTo:
            return .linksTo(index)
        case .linkedFrom:
            return .linkedFrom(index)
        }
    }

    private static func pickerSource(for direction: DependencyPickerDirection) -> CapturePickerSource {
        switch direction {
        case .prerequisite:
            return .dependency
        case .blocks:
            return .blockedTask
        case .linksTo:
            return .linksTo
        case .linkedFrom:
            return .linkedFrom
        }
    }

    /// Re-present a relation picker in place when `~` / `~~` flips at the
    /// same replacement start. Keeps the filter, never suppresses auto-open.
    private func handleRelationLiveFlip(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        keptFilter: String,
        restoreCursor: Int
    ) async {
        dismissCompletion(
            preservePendingAliasTip: true,
            preservePresentedAliasTip: true
        )
        defer {
            if picker == nil {
                deferAliasTipOpportunity(reason: .unanchored)
            }
        }
        let r = completion.replacement
        guard stringRange(in: draft, byteRange: r) != nil else {
            return
        }
        let direction: DependencyPickerDirection =
            completion.context == "relation_from" ? .linkedFrom : .linksTo
        let source = Self.pickerSource(for: direction)
        let sigilBytes = direction.leadingSigil.utf8.count
        if cursor > r.start + sigilBytes {
            if let snapshot = try? await processClient.captureComplete(draft, cursor: r.start),
               isCurrentAnalysis(generation),
               plainDraft == draft,
               snapshot.context == completion.context,
               snapshot.replacement.start == r.start
            {
                presentPicker(
                    source: source,
                    index: Self.dependencyPickerIndex(snapshot.candidates, direction: direction),
                    candidates: snapshot.candidates,
                    warnings: snapshot.warnings,
                    draft: draft,
                    range: snapshot.replacement,
                    restoreCursor: restoreCursor,
                    query: keptFilter,
                    snapshotIsPartial: false,
                    dependencyOwner: snapshot.owner,
                    opensWithoutSelection: snapshot.opensWithoutSelection
                )
                return
            }
            guard isCurrentAnalysis(generation), plainDraft == draft else {
                return
            }
        }
        presentPicker(
            source: source,
            index: Self.dependencyPickerIndex(completion.candidates, direction: direction),
            candidates: completion.candidates,
            warnings: completion.warnings,
            draft: draft,
            range: r,
            restoreCursor: restoreCursor,
            query: keptFilter,
            snapshotIsPartial: cursor > r.start + sigilBytes,
            dependencyOwner: completion.owner,
            opensWithoutSelection: completion.opensWithoutSelection
        )
    }

    /// Routes a `task_complete` completion response into the picker card,
    /// mirroring `handleDependencyCompletion`: dismiss the inline list,
    /// auto-open only on `.edit` when not suppressed, show the chip on
    /// `.selection`, and refetch the full list at `r.start` when the caret
    /// is past it. Bob's `query` seeds the filter; the stale-safe refetch
    /// uses the same guards.
    private func handleTaskCompleteCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger
    ) async {
        dismissCompletion(preservePendingAliasTip: true)
        defer {
            if picker == nil {
                deferAliasTipOpportunity(reason: .unanchored)
            }
        }
        let r = completion.replacement
        guard stringRange(in: draft, byteRange: r) != nil,
              stringRange(in: draft, start: r.start, end: min(cursor, r.end)) != nil
        else {
            return
        }
        guard trigger == .edit, pickerAutoOpenSuppressedStart != r.start else {
            pickerChip = CapturePickerChipState(
                source: .taskComplete,
                draftSnapshot: draft,
                replacementRange: r,
                cursor: cursor,
                candidates: completion.candidates,
                warnings: completion.warnings
            )
            return
        }
        let query = completion.query ?? Self.taskCompletePickerQuery(in: draft, range: r, cursor: cursor)
        let continuationKeys = completion.picker?.actionContinuationKeys ?? []
        if cursor > r.start + 1 {
            if let snapshot = try? await processClient.captureComplete(draft, cursor: r.start),
               isCurrentAnalysis(generation),
               plainDraft == draft,
               snapshot.context == "task_complete",
               snapshot.replacement == r
            {
                presentPicker(
                    source: .taskComplete,
                    index: .taskComplete(TaskCompletePickerIndex(candidates: snapshot.candidates)),
                    candidates: snapshot.candidates,
                    warnings: snapshot.warnings,
                    draft: draft,
                    range: r,
                    restoreCursor: cursor,
                    query: query,
                    snapshotIsPartial: false,
                    taskCompleteContinuationKeys: snapshot.picker?.actionContinuationKeys ?? [],
                    opensWithoutSelection: snapshot.opensWithoutSelection
                )
                return
            }
            guard isCurrentAnalysis(generation), plainDraft == draft else {
                return
            }
            presentPicker(
                source: .taskComplete,
                index: .taskComplete(TaskCompletePickerIndex(candidates: completion.candidates)),
                candidates: completion.candidates,
                warnings: completion.warnings,
                draft: draft,
                range: r,
                restoreCursor: cursor,
                query: query,
                snapshotIsPartial: true,
                taskCompleteContinuationKeys: continuationKeys,
                opensWithoutSelection: completion.opensWithoutSelection
            )
            return
        }
        presentPicker(
            source: .taskComplete,
            index: .taskComplete(TaskCompletePickerIndex(candidates: completion.candidates)),
            candidates: completion.candidates,
            warnings: completion.warnings,
            draft: draft,
            range: r,
            restoreCursor: cursor,
            query: query,
            snapshotIsPartial: false,
            taskCompleteContinuationKeys: continuationKeys,
            opensWithoutSelection: completion.opensWithoutSelection
        )
    }

    /// Routes a `wikilink_task` completion response into the picker card,
    /// mirroring `handleTaskCompleteCompletion`: dismiss the inline list,
    /// auto-open only on `.edit` when the edit wrote the second `(` and when
    /// not suppressed, show the chip otherwise, and refetch the full snapshot
    /// at `r.start + 2` when the caret is past it. Bob's `query` seeds the
    /// filter; the stale-safe refetch uses the same guards.
    private func handleWikilinkTaskCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger,
        writtenRange: CaptureRange?
    ) async {
        dismissCompletion(preservePendingAliasTip: true)
        defer {
            if picker == nil {
                deferAliasTipOpportunity(reason: .unanchored)
            }
        }
        let r = completion.replacement
        guard stringRange(in: draft, byteRange: r) != nil,
              stringRange(in: draft, start: r.start, end: min(cursor, r.end)) != nil
        else {
            return
        }
        // Thin-client guard: without Bob's descriptor and query there is no
        // contract to present. Keep the token plain, like an older Bob.
        guard let bobQuery = completion.query,
              let descriptor = completion.picker,
              descriptor.isWikilinkTask,
              stringRange(in: draft, byteRange: descriptor.markerRange) != nil,
              stringRange(in: draft, byteRange: descriptor.triggerRemovalRange) != nil
        else {
            return
        }
        let context = WikilinkTaskPickerContext(
            markerRange: descriptor.markerRange,
            triggerRemovalRange: descriptor.triggerRemovalRange,
            query: bobQuery
        )
        let source = CapturePickerSource.wikilinkTask(context)
        let query = bobQuery
        let separatorTyped = captureEditWroteSeparator(writtenRange, before: r.start + 2)
        guard trigger == .edit, separatorTyped, pickerAutoOpenSuppressedStart != r.start else {
            pickerChip = CapturePickerChipState(
                source: source,
                draftSnapshot: draft,
                replacementRange: r,
                cursor: cursor,
                candidates: completion.candidates,
                warnings: completion.warnings
            )
            return
        }
        if cursor > r.start + 2 {
            // Multiword full-pool refetch: Bob's unclosed replacement end is
            // caret-dependent by design, so only the opener must match.
            // Keep the original ranges, descriptor, and query; take only the
            // complete candidate pool from the refetch.
            if let snapshot = try? await processClient.captureComplete(draft, cursor: r.start + 2),
               isCurrentAnalysis(generation),
               plainDraft == draft,
               snapshot.context == "wikilink_task",
               snapshot.replacement.start == r.start
            {
                presentPicker(
                    source: source,
                    index: .wikilinkTask(WikilinkTaskPickerIndex(candidates: snapshot.candidates)),
                    candidates: snapshot.candidates,
                    warnings: snapshot.warnings,
                    draft: draft,
                    range: r,
                    restoreCursor: cursor,
                    query: query,
                    snapshotIsPartial: false,
                    opensWithoutSelection: snapshot.opensWithoutSelection
                )
                return
            }
            guard isCurrentAnalysis(generation), plainDraft == draft else {
                return
            }
            presentPicker(
                source: source,
                index: .wikilinkTask(WikilinkTaskPickerIndex(candidates: completion.candidates)),
                candidates: completion.candidates,
                warnings: completion.warnings,
                draft: draft,
                range: r,
                restoreCursor: cursor,
                query: query,
                snapshotIsPartial: true,
                opensWithoutSelection: completion.opensWithoutSelection
            )
            return
        }
        presentPicker(
            source: source,
            index: .wikilinkTask(WikilinkTaskPickerIndex(candidates: completion.candidates)),
            candidates: completion.candidates,
            warnings: completion.warnings,
            draft: draft,
            range: r,
            restoreCursor: cursor,
            query: query,
            snapshotIsPartial: false,
            opensWithoutSelection: completion.opensWithoutSelection
        )
    }

    /// Row key matching `WikilinkTaskPickerIndex.key`: exact note path plus
    /// the stale-safe task ref, so `cursor_after` lookup never collides on
    /// Bob's empty replacement for ID-less and guarded rows.
    private static func wikilinkTaskKey(for candidate: CaptureCompletionCandidate) -> String {
        let note = candidate.notePath ?? candidate.locator ?? candidate.route ?? ""
        return "\(note)|\(candidate.taskRef ?? "")"
    }

    /// The `((` filter seed: draft bytes `(r.start + 2)..<caret`, so the
    /// trigger itself never filters. The index also strips a leading `((`
    /// defensively.
    private static func wikilinkTaskPickerQuery(in draft: String, range: CaptureRange, cursor: Int) -> String {
        let start = range.start + 2
        guard start <= range.end,
              let queryRange = stringRange(in: draft, start: start, end: min(cursor, range.end))
        else {
            return ""
        }
        return String(draft[queryRange])
    }

    /// The `!` filter seed: draft bytes `(r.start + 1)..<caret`, so the sigil
    /// itself never filters. The index also strips a leading `!`
    /// defensively.
    private static func taskCompletePickerQuery(in draft: String, range: CaptureRange, cursor: Int) -> String {
        let start = range.start + 1
        guard start <= range.end,
              let queryRange = stringRange(in: draft, start: start, end: min(cursor, range.end))
        else {
            return ""
        }
        return String(draft[queryRange])
    }

    func presentPicker(
        source: CapturePickerSource,
        index: CapturePickerIndex,
        candidates: [CaptureCompletionCandidate],
        warnings: [String],
        draft: String,
        range: CaptureRange,
        restoreCursor: Int,
        query: String,
        snapshotIsPartial: Bool,
        dependencyOwner: DependencyOwner? = nil,
        taskCompleteContinuationKeys: [String] = [],
        opensWithoutSelection: Bool = false,
        includesClosedTasks: Bool = false,
        gotoDesiredIncludesClosedTasks: Bool? = nil
    ) {
        let pickerWasVisible = picker != nil
        if source == .taskGoto {
            var state = CaptureTaskGotoScopeState()
            state.beginSession(
                candidates: candidates,
                appliedIncludesClosedTasks: includesClosedTasks,
                desiredIncludesClosedTasks: gotoDesiredIncludesClosedTasks
            )
            gotoClosedTasksState = state
        } else {
            gotoClosedTasksState = nil
        }
        let presentation = index.presentation(filter: query)
        pickerIndex = index
        pickerPresentation = presentation
        let markerRange = Self.pickerMarkerHighlightRange(
            source: source,
            replacementRange: range,
            markerRange: Self.blockIDMarkerRange(for: source)
        )
        var scopeLine: Int? = nil
        if case .blockID = source, let marker = markerRange {
            scopeLine = Self.scopeLineNumber(draft: draft, markerStart: marker.start)
        }
        picker = CapturePickerState(
            source: source,
            draftSnapshot: draft,
            replacementRange: range,
            restoreCursor: restoreCursor,
            candidates: candidates,
            warnings: warnings,
            filterText: query,
            selectedRowID: opensWithoutSelection
                ? nil
                : CapturePickerNavigation.first(in: presentation.orderedRowIDs),
            visibleRowBudget: presentation.visibleRowBudget,
            snapshotIsPartial: snapshotIsPartial,
            scopeLineNumber: scopeLine,
            dependencyOwner: dependencyOwner,
            taskCompleteContinuationKeys: taskCompleteContinuationKeys,
            includesClosedTasks: includesClosedTasks
        )
        pickerMarkerHighlight = markerRange
        applyPickerMarkerHighlight()
        dismissCompletion(
            preservePendingAliasTip: true,
            preservePresentedAliasTip: pickerWasVisible
        )
        consumePendingAliasTipOnPickerOpen(
            draft: draft,
            range: range,
            visibleRowBudget: presentation.visibleRowBudget
        )
        relationFlipAliasOpen = nil
        pickerChip = nil
        editorInputLocked = true
        applyOwnerModeParentStatus(source: source)
        requestFocus(.pickerFilter)
    }

    /// Toggle completed rows for the current Go To session. Each fetch is a
    /// full Bob snapshot at the replacement start; only the latest response
    /// for the unchanged draft/session can replace the rows.
    func toggleGotoClosedTasks() {
        guard let openPicker = picker,
            openPicker.source == .taskGoto,
            plainDraft == openPicker.draftSnapshot,
            let processClient,
            var state = gotoClosedTasksState,
            let request = state.toggle()
        else {
            return
        }
        gotoClosedTasksState = state
        let draft = openPicker.draftSnapshot
        let range = openPicker.replacementRange
        startGotoClosedTasksFetch(
            request: request,
            draft: draft,
            range: range,
            cursor: range.start,
            processClient: processClient
        )
    }

    private func startGotoClosedTasksFetch(
        request: CaptureTaskGotoScopeState.Request,
        draft: String,
        range: CaptureRange,
        cursor: Int,
        processClient: BobProcessClient
    ) {
        announceStatus(
            request.includesClosedTasks ? "Loading completed tasks…" : "Loading open tasks…"
        )
        Task { [weak self, processClient] in
            do {
                let snapshot = try await processClient.captureComplete(
                    draft,
                    cursor: cursor,
                    includeClosedTasks: request.includesClosedTasks
                )
                await MainActor.run {
                    guard let self,
                        self.isCurrentGotoClosedTasksFetch(
                            request: request,
                            draft: draft,
                            range: range
                        )
                    else {
                        return
                    }
                    let responseRange = snapshot.replacement
                    guard snapshot.context == "task_goto",
                        responseRange.start == range.start,
                        responseRange.end >= responseRange.start,
                        responseRange.end <= range.end
                    else {
                        if self.settleFailedGotoClosedTasksFetch(
                            request: request,
                            draft: draft,
                            range: range
                        ) {
                            self.announceStatus("Bob returned a different Go To result")
                        }
                        return
                    }
                    guard var state = self.gotoClosedTasksState,
                        state.apply(candidates: snapshot.candidates, for: request)
                    else {
                        return
                    }
                    self.gotoClosedTasksState = state
                    self.applyGotoClosedTasksSnapshot(snapshot, state: state)
                }
            } catch let error as BobClientError {
                let unsupportedClosedTasks: Bool
                if case .unsupportedOption(let option) = error {
                    unsupportedClosedTasks = option == "--closed-tasks"
                } else {
                    unsupportedClosedTasks = false
                }
                let errorMessage: String
                if case .processFailed(_, _, let stderr) = error {
                    NSLog("%@", error.description)
                    let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    errorMessage = trimmedStderr.isEmpty ? error.description : trimmedStderr
                } else {
                    errorMessage = error.description
                }
                await MainActor.run {
                    guard let self,
                        self.settleFailedGotoClosedTasksFetch(
                            request: request,
                            draft: draft,
                            range: range
                        )
                    else {
                        return
                    }
                    if unsupportedClosedTasks {
                        let updateHint = "Update bob to show completed tasks"
                        if self.picker?.warnings.contains(updateHint) != true {
                            self.picker?.warnings.append(updateHint)
                        }
                        self.announceStatus(updateHint)
                    } else {
                        self.announceStatus(errorMessage)
                    }
                }
            } catch {
                let errorMessage = error.localizedDescription
                await MainActor.run {
                    guard let self,
                        self.settleFailedGotoClosedTasksFetch(
                            request: request,
                            draft: draft,
                            range: range
                        )
                    else {
                        return
                    }
                    self.announceStatus(errorMessage)
                }
            }
        }
    }

    private func isCurrentGotoClosedTasksFetch(
        request: CaptureTaskGotoScopeState.Request,
        draft: String,
        range: CaptureRange
    ) -> Bool {
        guard let state = gotoClosedTasksState else {
            return false
        }
        return state.isCurrent(request)
            && plainDraft == draft
            && picker?.source == .taskGoto
            && picker?.draftSnapshot == draft
            && picker?.replacementRange == range
    }

    private func settleFailedGotoClosedTasksFetch(
        request: CaptureTaskGotoScopeState.Request,
        draft: String,
        range: CaptureRange
    ) -> Bool {
        guard isCurrentGotoClosedTasksFetch(request: request, draft: draft, range: range),
            var state = gotoClosedTasksState,
            state.fail(request)
        else {
            return false
        }
        gotoClosedTasksState = state
        return true
    }

    private func applyGotoClosedTasksSnapshot(
        _ snapshot: CaptureCompletionResponse,
        state: CaptureTaskGotoScopeState
    ) {
        guard var openPicker = picker else {
            return
        }
        let index = TaskLinkPickerIndex(candidates: snapshot.candidates, mode: .taskGoto)
        let presentation = index.presentation(filter: openPicker.filterText)
        let selectedID =
            openPicker.selectedRowID.flatMap {
                presentation.rowsByID[$0] == nil ? nil : $0
            } ?? CapturePickerNavigation.first(in: presentation.orderedRowIDs)

        pickerIndex = .taskGoto(index)
        pickerPresentation = presentation
        openPicker.candidates = state.candidates
        openPicker.warnings = snapshot.warnings
        openPicker.includesClosedTasks = state.appliedIncludesClosedTasks
        openPicker.selectedRowID = selectedID
        openPicker.visibleRowBudget = presentation.visibleRowBudget
        openPicker.snapshotIsPartial = false
        picker = openPicker

        let countText =
            state.candidates.count == 1
            ? "1 task"
            : "\(state.candidates.count) tasks"
        let scope = state.appliedIncludesClosedTasks ? "completed" : "open"
        announceStatus("Showing \(scope) tasks, \(countText)")
    }

    private func applyOwnerModeParentStatus(source: CapturePickerSource) {
        if case .parentTask(let context) = source {
            if context.mergeInTargetTitle != nil {
                statusText = CapturePickerNeed.mergeInSource.statusText
            } else if context.isOwnerMode {
                statusText = CaptureRelationshipCopy.relateStatusText
            }
        }
    }

    /// Draft-global byte range of the marker token the picker edits: Bob's
    /// `marker_range` for block-ID sources (the replacement range when an
    /// older Bob sends none), `[r.start - 1, r.end)` for `^` so the trigger
    /// is included.
    static func pickerMarkerHighlightRange(
        source: CapturePickerSource,
        replacementRange: CaptureRange,
        markerRange: CaptureRange?
    ) -> CaptureRange? {
        switch source {
        case .activeTask:
            guard replacementRange.start >= 1,
                  replacementRange.start <= replacementRange.end
            else {
                return nil
            }
            return CaptureRange(start: replacementRange.start - 1, end: replacementRange.end)
        case .taskLink:
            // Bob's `task_link` replacement already includes the `:` sigil.
            return replacementRange
        case .taskGoto:
            // Bob's `task_goto` replacement already includes the `/` sigil.
            return replacementRange
        case .dependency, .blockedTask, .linksTo, .linkedFrom:
            // Bob's directional replacement includes `&`, `*`, `~`, or `~~`,
            // with any quoted note included.
            return replacementRange
        case .taskComplete:
            // Bob's `task_complete` replacement already includes the `!`
            // sigil, quoted note included.
            return replacementRange
        case .wikilinkTask(let context):
            // Bob's verbatim `marker_range` for the `((query` token.
            return context.markerRange
        case .blockID:
            return markerRange ?? replacementRange
        case .parentTask(let context):
            return context.markerRange
        case .projectTaskMove(let context):
            return context.markerRange
        }
    }

    /// Physical line (1-based) of a draft-global byte offset. Nil on
    /// single-line drafts, where the scope token needs no disambiguation.
    static func scopeLineNumber(draft: String, markerStart: Int) -> Int? {
        guard draft.contains("\n"),
              markerStart >= 0,
              markerStart <= draft.utf8.count
        else {
            return nil
        }
        let newlines = draft.utf8.prefix(markerStart).filter { $0 == 10 }.count
        return newlines + 1
    }

    private static func blockIDMarkerRange(for source: CapturePickerSource) -> CaptureRange? {
        guard case .blockID(let context) = source else {
            return nil
        }
        return context.field?.markerRange
    }

    /// Bob's `block_id.splice` for a project-task session, which an accept
    /// writes in place of the ID-only `replacement` range. Nil for every other
    /// source and for an older Bob that sends no splice, which keep the
    /// ordinary insertion.
    private static func blockIDSplice(for source: CapturePickerSource) -> CaptureBlockIDSplice? {
        guard case .blockID(let context) = source, context.scope == .projectTask else {
            return nil
        }
        return context.field?.splice
    }

    /// One native undoable edit for an accepted block-ID splice. The splice
    /// range is draft-global UTF-8 bytes; the replacement text is Bob's
    /// `before + ID + after (+ remainder for type-through)`. Returns nil when
    /// the range is not on UTF-8 character boundaries, so a stale draft is
    /// never edited.
    private static func nativeEditForBlockIDSplice(
        id: String,
        remainder: String = "",
        draft: String,
        splice: CaptureBlockIDSplice
    ) -> CaptureNativeRewriteEdit? {
        guard let applied = splice.applied(id: id, remainder: remainder, to: draft) else {
            return nil
        }
        guard let replacementRange = utf16Range(in: draft, byteRange: splice.range) else {
            return nil
        }
        guard
            let caretUTF16 = utf16Range(
                in: applied.draft,
                start: applied.caret,
                end: applied.caret
            )?.location
        else {
            return nil
        }
        return CaptureNativeRewriteEdit(
            replacementRange: replacementRange,
            replacementText: applied.written,
            resultingSelection: NSRange(location: caretUTF16, length: 0),
            expectedDraft: draft,
            resultingDraft: applied.draft
        )
    }

    /// Applies an accepted splice through the focused `NSTextView` so Undo
    /// restores the pre-accept draft in one step. Returns true when the
    /// native bridge wrote `edit.resultingDraft`; the model then mirrors the
    /// draft without wholesale replacement so the undo stack survives.
    /// Returns false without changing state when no text view is wired or
    /// the bridge declines, so the caller falls back to `setPlainDraft`.
    private func applyBlockIDSpliceNatively(
        edit: CaptureNativeRewriteEdit,
        caretUTF8: Int
    ) -> Bool {
        suppressedCompletionAcceptanceDraft = edit.resultingDraft
        guard applyNativeRewriteEdit?(edit) == true else {
            suppressedCompletionAcceptanceDraft = nil
            return false
        }
        if plainDraft != edit.resultingDraft {
            isApplyingProgrammaticDraft = true
            attributedDraft = AttributedString(edit.resultingDraft)
            isApplyingProgrammaticDraft = false
        }
        restoreSelection(cursorUTF8Offset: caretUTF8, suppressEditorCallbacks: true)
        return true
    }

    /// One native undoable edit for an ordinary insertion (older Bob with no
    /// splice, or any non-splice picker accept): Bob's `replacement` range
    /// with `insertion` written over it.
    private static func nativeEditForOrdinaryInsertion(
        insertion: String,
        draft: String,
        range: CaptureRange
    ) -> CaptureNativeRewriteEdit? {
        guard let target = stringRange(in: draft, byteRange: range) else {
            return nil
        }
        var text = draft
        text.replaceSubrange(target, with: insertion)
        let caret = range.start + insertion.utf8.count
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            return nil
        }
        guard let replacementRange = utf16Range(in: draft, byteRange: range) else {
            return nil
        }
        guard let caretUTF16 = utf16Range(in: text, start: caret, end: caret)?.location else {
            return nil
        }
        return CaptureNativeRewriteEdit(
            replacementRange: replacementRange,
            replacementText: insertion,
            resultingSelection: NSRange(location: caretUTF16, length: 0),
            expectedDraft: draft,
            resultingDraft: text
        )
    }

    /// Washes the picker's marker token in accent inside the dimmed editor.
    /// Attribute-only: `plainDraft`, the selection, and undo are untouched,
    /// and the characters-change callback that drives `editorTextDidChange`
    /// never fires for attribute edits (plus the programmatic-draft guard).
    private func applyPickerMarkerHighlight() {
        guard let highlight = pickerMarkerHighlight,
              let openPicker = picker,
              plainDraft == openPicker.draftSnapshot,
              let stringRange = stringRange(in: plainDraft, byteRange: highlight)
        else {
            return
        }
        let fillsStrengthened = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        isApplyingProgrammaticDraft = true
        attributedDraft.transform(updating: &editorSelection) { text in
            guard let lower = AttributedString.Index(stringRange.lowerBound, within: text),
                  let upper = AttributedString.Index(stringRange.upperBound, within: text)
            else {
                return
            }
            text[lower..<upper].backgroundColor = Color.accentColor.opacity(
                fillsStrengthened ? 0.35 : 0.22
            )
        }
        isApplyingProgrammaticDraft = false
    }

    /// Removes the marker wash for `draftSnapshot` without touching text,
    /// selection, or undo. A snapshot mismatch means the draft already moved
    /// through `setPlainDraft`, which replaces the attributed value wholesale
    /// and took the wash with it.
    private func clearPickerMarkerHighlight(draftSnapshot: String) {
        guard let highlight = pickerMarkerHighlight else {
            return
        }
        pickerMarkerHighlight = nil
        guard plainDraft == draftSnapshot,
              let stringRange = stringRange(in: plainDraft, byteRange: highlight)
        else {
            return
        }
        // The picker's accent wash replaced the project-note chip on a sealed
        // marker; put the manila wash back under the same range. Resolved
        // before the transform: `plainDraft` reads `attributedDraft`, which the
        // transform holds for writing.
        let chipRanges = paintedSpanRanges.flatMap { painted in
            painted.draft == draftSnapshot ? painted.ranges : nil
        }
        isApplyingProgrammaticDraft = true
        attributedDraft.transform(updating: &editorSelection) { text in
            guard let lower = AttributedString.Index(stringRange.lowerBound, within: text),
                  let upper = AttributedString.Index(stringRange.upperBound, within: text)
            else {
                return
            }
            text[lower..<upper].backgroundColor = nil
            if let chipRanges {
                Self.paintProjectNoteWash(&text, ranges: chipRanges, within: stringRange)
            }
        }
        isApplyingProgrammaticDraft = false
    }

    /// Washes each project-note span that overlaps `bounds`. Used to restore
    /// the chip after a picker's marker wash is removed; the full paint in
    /// `paintHighlighting` washes the same spans inline.
    static func paintProjectNoteWash(
        _ text: inout AttributedString,
        ranges: [ValidatedCaptureSpan],
        within bounds: Range<String.Index>
    ) {
        let wash = CaptureEditorPalette.projectNoteWash(
            increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
        for item in ranges where item.span.projectNote != nil {
            guard item.range.overlaps(bounds),
                  let lower = AttributedString.Index(item.range.lowerBound, within: text),
                  let upper = AttributedString.Index(item.range.upperBound, within: text)
            else {
                continue
            }
            text[lower..<upper].backgroundColor = wash
        }
    }

    func updatePickerFilter(_ text: String) {
        guard var updated = picker,
              let index = pickerIndex
        else {
            return
        }
        if updated.filterText != text {
            clearEqualsGestureArm()
        }
        // Type-through (New ID source only, rules present): the field only
        // ever holds ID characters. When the appended text contains a
        // character outside Bob's allowed set, commit the ID and insert the
        // rest into the editor after it, so `@sase^flaky-test Fix it` types
        // exactly the draft it would without the picker.
        if case .blockID(let context) = updated.source,
           context.isNewIDMode,
           let rules = context.rules,
           let split = rules.typeThroughSplit(old: updated.filterText, new: text),
           !split.id.isEmpty
        {
            commitBlockIDTypeThrough(id: split.id, remainder: split.remainder)
            return
        }
        updated.filterText = text
        let presentation = index.presentation(filter: text)
        updated.selectedRowID = CapturePickerNavigation.first(in: presentation.orderedRowIDs)
        announceBlockIDAvailabilityIfChanged(state: &updated, presentation: presentation)
        picker = updated
        pickerPresentation = presentation
    }

    /// Announces New ID availability only when its category changes, so typing
    /// within one category stays quiet. A taken ID names the conflict and the
    /// next-free alternative Bob's rule derives.
    private func announceBlockIDAvailabilityIfChanged(
        state: inout CapturePickerState,
        presentation: CapturePickerPresentation
    ) {
        guard case .blockID(let context) = state.source,
              context.isNewIDMode,
              let status = presentation.blockIDStatus,
              !status.isProjectNote,
              !state.filterText.isEmpty,
              case .blockID(let blockIndex)? = pickerIndex
        else {
            return
        }
        let availability = blockIndex.availability(of: state.filterText)
        let key: String
        switch availability {
        case .available:
            key = "available"
        case .unchecked:
            key = "unchecked"
        case .taken:
            key = "taken"
        case .invalid:
            key = "invalid"
        }
        guard key != state.lastAvailabilityKey else {
            return
        }
        state.lastAvailabilityKey = key
        switch availability {
        case .available:
            announceStatus("\(state.filterText) is available")
        case .unchecked:
            break
        case .taken(let line, _):
            var message = "\(state.filterText) is already used"
            if let line {
                message += " on line \(line)"
            }
            if let rules = context.rules, let field = context.field {
                let used = Set(field.used.map { $0.id })
                if let variant = rules.nextFreeVariant(of: state.filterText, used: used) {
                    message += "; \(variant) is available"
                }
            }
            announceStatus(message)
        case .invalid(let description):
            announceStatus(description)
        }
    }

    /// Commits a type-through split: the ID splices into Bob's range and the
    /// remainder (from the first disallowed character on) lands in the editor
    /// right after it. The commit is literal even when the ID is taken or
    /// invalid, because Bob's preview reports that exactly as without the
    /// picker. Runs an `.edit` analysis with completion at the new caret so
    /// `#` opens Pomodoro-name completion; a single separator key (`.`, `^`,
    /// `:`, `+`, `;`, or `,`) also passes through Bob's rewrite lane before
    /// completion. The caret sits past the committed token, so the ID picker
    /// cannot reopen for it.
    private func blockIDSeparatorTypeThroughRewrite(
        remainder: String,
        draft: String,
        caretUTF8Offset: Int
    ) -> Task<Void, Never>? {
        guard [".", "^", ":", "+", ";", ","].contains(remainder) else {
            return nil
        }
        return startCaptureRewrite(
            draft: draft,
            cursorUTF8Offset: caretUTF8Offset,
            triggeredCharacter: remainder
        )
    }

    private func commitBlockIDTypeThrough(id: String, remainder: String) {
        guard let openPicker = picker,
              plainDraft == openPicker.draftSnapshot,
              let idRange = stringRange(in: plainDraft, byteRange: openPicker.replacementRange)
        else {
            // The draft moved under the picker: never edit a stale draft.
            closePickerAfterStaleDraft()
            return
        }
        if let splice = Self.blockIDSplice(for: openPicker.source) {
            // The ID goes on the owning task's line; the remainder stays where
            // the user was typing, after what the splice wrote there. Apply
            // through the focused text view so Undo restores the pre-commit
            // draft in one step; fall back to a wholesale replacement when no
            // text view is wired.
            guard let applied = splice.applied(id: id, remainder: remainder, to: plainDraft) else {
                closePickerAfterStaleDraft()
                return
            }
            guard stringRange(in: applied.draft, start: applied.caret, end: applied.caret) != nil
            else {
                closePickerAfterStaleDraft()
                return
            }
            if let edit = Self.nativeEditForBlockIDSplice(
                id: id,
                remainder: remainder,
                draft: plainDraft,
                splice: splice
            ),
                applyBlockIDSpliceNatively(edit: edit, caretUTF8: applied.caret)
            {
                closePickerForAccept()
                let completionGate = blockIDSeparatorTypeThroughRewrite(
                    remainder: remainder,
                    draft: plainDraft,
                    caretUTF8Offset: applied.caret
                )
                scheduleAnalysis(
                    cursorUTF8Offset: applied.caret,
                    requestCompletion: true,
                    trigger: .edit,
                    completionGate: completionGate
                )
                return
            }
            let text = applied.draft
            let caret = applied.caret
            closePickerForAccept()
            suppressedCompletionAcceptanceDraft = text
            setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
            let completionGate = blockIDSeparatorTypeThroughRewrite(
                remainder: remainder,
                draft: text,
                caretUTF8Offset: caret
            )
            scheduleAnalysis(
                cursorUTF8Offset: caret,
                requestCompletion: true,
                trigger: .edit,
                completionGate: completionGate
            )
            return
        }
        let insertion = id + remainder
        let caret = openPicker.replacementRange.start + insertion.utf8.count
        if let edit = Self.nativeEditForOrdinaryInsertion(
            insertion: insertion,
            draft: plainDraft,
            range: openPicker.replacementRange
        ),
            applyBlockIDSpliceNatively(edit: edit, caretUTF8: caret)
        {
            closePickerForAccept()
            let completionGate = blockIDSeparatorTypeThroughRewrite(
                remainder: remainder,
                draft: plainDraft,
                caretUTF8Offset: caret
            )
            scheduleAnalysis(
                cursorUTF8Offset: caret,
                requestCompletion: true,
                trigger: .edit,
                completionGate: completionGate
            )
            return
        }
        var text = plainDraft
        text.replaceSubrange(idRange, with: insertion)
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            closePickerAfterStaleDraft()
            return
        }
        closePickerForAccept()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        let completionGate = blockIDSeparatorTypeThroughRewrite(
            remainder: remainder,
            draft: text,
            caretUTF8Offset: caret
        )
        scheduleAnalysis(
            cursorUTF8Offset: caret,
            requestCompletion: true,
            trigger: .edit,
            completionGate: completionGate
        )
    }

    func selectPickerRow(id: String) {
        guard picker != nil,
              let presentation = pickerPresentation,
              presentation.orderedRowIDs.contains(id)
        else {
            return
        }
        picker?.selectedRowID = id
    }

    func selectNextPickerRow() {
        if picker?.selectedRowID == nil {
            selectFirstPickerRow()
            return
        }
        movePickerSelection { CapturePickerNavigation.next(after: $0, in: $1) }
    }

    func selectPreviousPickerRow() {
        if picker?.selectedRowID == nil {
            selectLastPickerRow()
            return
        }
        movePickerSelection { CapturePickerNavigation.previous(before: $0, in: $1) }
    }

    func pagePickerRowsDown() {
        guard let picker = picker else {
            return
        }
        let step = max(picker.visibleRowBudget - 1, 1)
        movePickerSelection { CapturePickerNavigation.page(from: $0, by: step, in: $1) }
    }

    func pagePickerRowsUp() {
        guard let picker = picker else {
            return
        }
        let step = max(picker.visibleRowBudget - 1, 1)
        movePickerSelection { CapturePickerNavigation.page(from: $0, by: -step, in: $1) }
    }

    func selectFirstPickerRow() {
        guard picker != nil,
              let presentation = pickerPresentation
        else {
            return
        }
        picker?.selectedRowID = CapturePickerNavigation.first(in: presentation.orderedRowIDs)
    }

    func selectLastPickerRow() {
        guard picker != nil,
              let presentation = pickerPresentation
        else {
            return
        }
        picker?.selectedRowID = CapturePickerNavigation.last(in: presentation.orderedRowIDs)
    }

    private func movePickerSelection(
        _ move: (String, [String]) -> String?
    ) {
        guard let selectedRowID = picker?.selectedRowID,
              let presentation = pickerPresentation,
              let next = move(selectedRowID, presentation.orderedRowIDs)
        else {
            return
        }
        picker?.selectedRowID = next
    }

    func acceptSelectedPickerRow(submitAfterInsert: Bool) {
        acceptSelectedPickerRow(followUp: submitAfterInsert ? .submit : .none)
    }

    func acceptSelectedPickerRowAndSubmitAndOpen() {
        acceptSelectedPickerRow(followUp: .submitAndOpen)
    }

    private func acceptSelectedPickerRow(followUp: CaptureTaskLinkFollowUp) {
        let selectedRowID = picker?.selectedRowID
            ?? CapturePickerNavigation.first(in: pickerPresentation?.orderedRowIDs ?? [])
        guard let selectedRowID else {
            return
        }
        acceptPickerRow(id: selectedRowID, followUp: followUp)
    }

    func acceptSelectedPickerRowAndStart() {
        guard let selectedRowID = picker?.selectedRowID else {
            return
        }
        acceptPickerRowAndStart(id: selectedRowID)
    }

    func acceptSelectedPickerRowAndContinue() {
        guard let selectedRowID = picker?.selectedRowID else {
            return
        }
        acceptPickerRowAndContinue(id: selectedRowID)
    }

    func acceptPickerRow(id: String, submitAfterInsert: Bool) {
        acceptPickerRow(id: id, followUp: submitAfterInsert ? .submit : .none)
    }

    private func acceptPickerRow(id: String, followUp: CaptureTaskLinkFollowUp) {
        if picker?.source == .taskGoto {
            acceptTaskGotoRow(id: id)
            return
        }
        guard let picker = picker,
              plainDraft == picker.draftSnapshot,
              let range = stringRange(in: plainDraft, byteRange: picker.replacementRange)
        else {
            // The draft moved under the picker: never edit a stale draft.
            closePickerAfterStaleDraft()
            return
        }
        guard let row = pickerPresentation?.row(id: id) else {
            // No selectable row: a no-op that announces why, leaving the
            // picker open. `^` keeps its silent no-op.
            if case .blockID = picker.source {
                announceStatus(
                    Self.blockIDNoAcceptReason(filter: picker.filterText, presentation: pickerPresentation)
                )
            }
            return
        }
        if picker.source == .taskLink, row.insertion == nil, let pending = row.pendingBlockID {
            presentTaskLinkIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: followUp
            )
            return
        }
        if case .parentTask = picker.source, row.insertion == nil, let pending = row.pendingBlockID {
            presentParentTaskIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: followUp
            )
            return
        }
        if case .projectTaskMove = picker.source, row.insertion == nil, let pending = row.pendingBlockID {
            presentProjectTaskMoveIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: followUp
            )
            return
        }
        if picker.source == .dependency, row.insertion == nil, let pending = row.pendingBlockID {
            presentDependencyIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: followUp
            )
            return
        }
        if picker.source == .blockedTask, row.insertion == nil, let pending = row.pendingBlockID {
            presentBlockedTaskIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: followUp
            )
            return
        }
        if picker.source.isRelation, row.insertion == nil, let pending = row.pendingBlockID {
            presentRelationIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: followUp
            )
            return
        }
        if picker.source == .taskComplete, row.insertion == nil, let pending = row.pendingBlockID {
            presentTaskCompleteIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: followUp
            )
            return
        }
        if picker.source.isWikilinkTask, row.insertion == nil, let pending = row.pendingBlockID {
            presentWikilinkTaskIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: followUp
            )
            return
        }
        guard let insertion = row.insertion else {
            if case .blockID = picker.source {
                announceStatus(
                    Self.blockIDNoAcceptReason(filter: picker.filterText, presentation: pickerPresentation)
                )
            } else if picker.source.isRelationshipModifier
                || picker.source == .taskComplete
                || picker.source.isWikilinkTask
            {
                // Already-added and guarded rows keep the draft unchanged and
                // say why, leaving the picker open.
                announceStatus(row.badgeText ?? "That task cannot be used yet")
            } else if case .parentTask = picker.source {
                announceStatus(row.badgeText ?? "That task cannot be used yet")
            } else if case .projectTaskMove = picker.source {
                announceStatus(row.badgeText ?? "That task cannot be used yet")
            }
            return
        }

        // At a terminal `&` token, leave one separating space for typing
        // another `&`; preserve existing suffix whitespace when editing a
        // token in place.
        let insertionText: String
        if picker.source.isRelationshipModifier,
           picker.replacementRange.end >= plainDraft.utf8.count
        {
            insertionText = insertion.hasSuffix(" ") ? insertion : insertion + " "
        } else {
            insertionText = insertion
        }
        if let splice = Self.blockIDSplice(for: picker.source) {
            // A project-task prompt sends Bob's splice: the ID goes on the
            // owning task's line, which is not the caret's line when the prompt
            // opened on a nested line, and the caret ends where the user was
            // typing. A same-line splice is the ID-only range, so this is the
            // ordinary insertion there. Apply through the focused text view
            // so Undo restores the pre-accept draft in one step; fall back to
            // a wholesale replacement when no text view is wired (tests) or
            // the bridge declines. Older Bob sends no splice and keeps the
            // ordinary insertion below.
            guard let applied = splice.applied(id: insertionText, to: plainDraft) else {
                closePickerAfterStaleDraft()
                return
            }
            guard stringRange(in: applied.draft, start: applied.caret, end: applied.caret) != nil
            else {
                closePickerAfterStaleDraft()
                return
            }
            let spliceSource = picker.source
            let spliceOwner = picker.dependencyOwner
            let spliceScopeLine = picker.scopeLineNumber
            let spliceIsRelation = spliceSource.isRelationshipModifier
            let spliceDisplay = row.displayText
            let spliceInsertion = insertion
            if let edit = Self.nativeEditForBlockIDSplice(
                id: insertionText,
                draft: plainDraft,
                splice: splice
            ),
                applyBlockIDSpliceNatively(edit: edit, caretUTF8: applied.caret)
            {
                if spliceIsRelation {
                    rememberRelationshipDisplayName(
                        replacement: spliceInsertion,
                        text: spliceDisplay
                    )
                }
                closePickerForAccept()
                scheduleAnalysis(
                    cursorUTF8Offset: applied.caret,
                    requestCompletion: false,
                    trigger: .edit
                )
                if case .blockID(let context) = spliceSource {
                    announceStatus(
                        context.insertedAnnouncement(
                            id: insertionText,
                            markerLine: spliceScopeLine
                        )
                    )
                } else if spliceSource == .taskLink || spliceIsRelation || spliceSource == .taskComplete
                    || spliceSource.isWikilinkTask
                {
                    announceStatus("Inserted \(insertionText)")
                } else if case .parentTask = spliceSource {
                    announceStatus("Inserted \(insertionText)")
                } else {
                    announceStatus("Inserted \(row.detail.insertionPrefix)\(insertionText)")
                }
                if followUp == .submit || followUp == .submitAndOpen {
                    if spliceIsRelation, spliceOwner == nil {
                        announceStatus("Add task text or @note+id, then capture")
                        return
                    }
                    submitAfterCurrentAnalysis(openAfterCapture: followUp == .submitAndOpen)
                }
                return
            }
            let text = applied.draft
            let caret = applied.caret
            guard stringRange(in: text, start: caret, end: caret) != nil else {
                closePickerAfterStaleDraft()
                return
            }
            let source = picker.source
            let owner = picker.dependencyOwner
            if source.isRelationshipModifier {
                rememberRelationshipDisplayName(replacement: insertion, text: row.displayText)
            }
            closePickerForAccept()
            suppressedCompletionAcceptanceDraft = text
            setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
            scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: false, trigger: .edit)
            if case .blockID(let context) = source {
                announceStatus(
                    context.insertedAnnouncement(id: insertionText, markerLine: picker.scopeLineNumber)
                )
            } else if source == .taskLink || source.isRelationshipModifier || source == .taskComplete || source.isWikilinkTask {
                announceStatus("Inserted \(insertionText)")
            } else if case .parentTask = source {
                announceStatus("Inserted \(insertionText)")
            } else {
                announceStatus("Inserted \(row.detail.insertionPrefix)\(insertionText)")
            }
            if followUp == .submit || followUp == .submitAndOpen {
                if source.isRelationshipModifier, owner == nil {
                    announceStatus("Add task text or @note+id, then capture")
                    return
                }
                submitAfterCurrentAnalysis(openAfterCapture: followUp == .submitAndOpen)
            }
            return
        }
        let isWikilinkCursorAfter: Int? = {
            if picker.source.isWikilinkTask,
               let match = picker.candidates.first(where: {
                   Self.wikilinkTaskKey(for: $0) == row.id
               }),
               let after = match.cursorAfter
            {
                return after
            }
            return nil
        }()
        if isWikilinkCursorAfter == nil,
           let edit = Self.nativeEditForOrdinaryInsertion(
               insertion: insertionText,
               draft: plainDraft,
               range: picker.replacementRange
           ),
           applyBlockIDSpliceNatively(
               edit: edit,
               caretUTF8: picker.replacementRange.start + insertionText.utf8.count
           )
        {
            // Ordinary insertion through the text view so Undo works; the
            // caret is the end of the inserted text.
            let caret = picker.replacementRange.start + insertionText.utf8.count
            let source = picker.source
            let owner = picker.dependencyOwner
            if source.isRelationshipModifier {
                rememberRelationshipDisplayName(replacement: insertion, text: row.displayText)
            }
            closePickerForAccept()
            scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: false, trigger: .edit)
            if case .blockID(let context) = source {
                announceStatus(
                    context.insertedAnnouncement(id: insertionText, markerLine: picker.scopeLineNumber)
                )
            } else if source == .taskLink || source.isRelationshipModifier || source == .taskComplete || source.isWikilinkTask {
                announceStatus("Inserted \(insertionText)")
            } else if case .parentTask = source {
                announceStatus("Inserted \(insertionText)")
            } else {
                announceStatus("Inserted \(row.detail.insertionPrefix)\(insertionText)")
            }
            if followUp == .submit || followUp == .submitAndOpen {
                if source.isRelationshipModifier, owner == nil {
                    announceStatus("Add task text or @note+id, then capture")
                    return
                }
                submitAfterCurrentAnalysis(openAfterCapture: followUp == .submitAndOpen)
            }
            return
        }
        var text = plainDraft
        text.replaceSubrange(range, with: insertionText)
        let caret: Int
        if let after = isWikilinkCursorAfter {
            caret = after
        } else {
            caret = picker.replacementRange.start + insertionText.utf8.count
        }
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            closePickerAfterStaleDraft()
            return
        }

        let source = picker.source
        let owner = picker.dependencyOwner
        if source.isRelationshipModifier {
            rememberRelationshipDisplayName(replacement: insertion, text: row.displayText)
        }
        closePickerForAccept()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: false, trigger: .edit)
        // Block-ID insertions are bare IDs; name the marker they landed on.
        // Active-task insertions are bare locators; prefix the `^` so the
        // announcement matches the pre-epic "Inserted ^route:block-id".
        // Task-link and dependency insertions already include their sigil.
        if case .blockID(let context) = source {
            announceStatus(
                context.insertedAnnouncement(id: insertionText, markerLine: picker.scopeLineNumber)
            )
        } else if source == .taskLink || source.isRelationshipModifier || source == .taskComplete || source.isWikilinkTask {
            announceStatus("Inserted \(insertionText)")
        } else if case .parentTask = source {
            announceStatus("Inserted \(insertionText)")
        } else {
            announceStatus("Inserted \(row.detail.insertionPrefix)\(insertionText)")
        }
        if followUp == .submit || followUp == .submitAndOpen {
            if source.isRelationshipModifier, owner == nil {
                // No dependent yet: keep the draft open and teach the next
                // step instead of submitting an ownerless pick.
                announceStatus("Add task text or @note+id, then capture")
                return
            }
            submitAfterCurrentAnalysis(openAfterCapture: followUp == .submitAndOpen)
        }
    }

    /// Opens today's daily note on the running Pomodoro (or the nearest
    /// fallback) through `obsidian://bob-goto-task`. Fetches a fresh
    /// `capture-pomodoros --all` snapshot, never the idle-agenda cache.
    /// Success retains a nonempty draft the way Escape does. A second press
    /// while a fetch or open is in flight is a no-op.
    func openTodayPomodoroInObsidian() {
        if isSubmitting {
            announceStatus("Wait for the capture to finish")
            return
        }
        if todayPomodoroGotoInFlight {
            return
        }
        guard let processClient else {
            announceStatus("Bob is not resolved")
            return
        }

        todayPomodoroGotoInFlight = true
        todayPomodoroGotoGeneration &+= 1
        let generation = todayPomodoroGotoGeneration
        announceStatus("Opening today's note…")

        todayPomodoroGotoTask = Task { [weak self, processClient] in
            let outcome: Result<CapturePomodorosResponse, Error>
            do {
                outcome = .success(
                    try await processClient.capturePomodoros(includeCompleted: true)
                )
            } catch {
                outcome = .failure(error)
            }
            guard let self else {
                return
            }
            self.finishTodayPomodoroGoto(generation: generation, outcome: outcome)
        }
    }

    private func finishTodayPomodoroGoto(
        generation: UInt64,
        outcome: Result<CapturePomodorosResponse, Error>
    ) {
        guard todayPomodoroGotoGeneration == generation else {
            return
        }
        guard panelVisible else {
            todayPomodoroGotoInFlight = false
            return
        }
        switch outcome {
        case .failure:
            todayPomodoroGotoInFlight = false
            announceStatus("Couldn't read today's Pomodoros")
        case .success(let response):
            switch CaptureTodayPomodoroGoto.resolve(response) {
            case .refused(let refusal):
                todayPomodoroGotoInFlight = false
                announceStatus(refusal.statusText)
            case .destination(let destination):
                taskGotoOpener(destination.url) { [weak self] success in
                    guard let self else {
                        return
                    }
                    guard self.todayPomodoroGotoGeneration == generation else {
                        return
                    }
                    self.todayPomodoroGotoInFlight = false
                    if success {
                        self.prepareForRetainedClose()
                        self.panelDismisser()
                    } else {
                        self.announceStatus("Couldn't open Obsidian")
                    }
                }
            }
        }
    }

    private func invalidateTodayPomodoroGoto() {
        todayPomodoroGotoTask?.cancel()
        todayPomodoroGotoTask = nil
        todayPomodoroGotoInFlight = false
        todayPomodoroGotoGeneration &+= 1
    }

    /// Dispatches `obsidian://bob-goto-task` for a Go To row. Command-Return
    /// equals Return: `submitAfterInsert` is ignored and nothing is captured.
    /// A missing destination keeps the picker open; a failed open keeps it
    /// open with an error; success discards the draft (no stash) and hides
    /// the panel. In-flight accepts are no-ops so a double Return opens once.
    func acceptTaskGotoRow(id: String) {
        if taskGotoDispatchInFlight {
            return
        }
        guard let picker = picker,
              picker.source == .taskGoto,
              plainDraft == picker.draftSnapshot,
              stringRange(in: plainDraft, byteRange: picker.replacementRange) != nil
        else {
            closePickerAfterStaleDraft()
            return
        }
        guard let row = pickerPresentation?.row(id: id),
              let destination = row.taskGotoDestination,
              let url = ObsidianOpenURL.taskGotoURL(
                  path: destination.target,
                  line: destination.line,
                  ref: destination.ref,
                  blockID: destination.blockID
              )
        else {
            announceStatus("bob sent no location for this task — update bob")
            return
        }
        taskGotoDispatchInFlight = true
        announceStatus("Opening in Obsidian…")
        taskGotoOpener(url) { [weak self] success in
            guard let self else {
                return
            }
            self.taskGotoDispatchInFlight = false
            if success {
                self.discardDraft()
                self.panelDismisser()
            } else {
                self.announceStatus("Couldn't open Obsidian")
            }
        }
    }

    /// Shift-Return on a `:` row: splice the link plus `=`, so the live preview
    /// shows the start before Return captures. Only the task-link source maps
    /// here; other sources keep Shift-Return consumed.
    func acceptPickerRowAndStart(id: String) {
        guard let picker = picker,
              picker.source == .taskLink
        else {
            return
        }
        guard plainDraft == picker.draftSnapshot,
              let range = stringRange(in: plainDraft, byteRange: picker.replacementRange)
        else {
            closePickerAfterStaleDraft()
            return
        }
        guard let row = pickerPresentation?.row(id: id) else {
            return
        }
        if row.insertion == nil, let pending = row.pendingBlockID {
            presentTaskLinkIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: .start
            )
            return
        }
        guard let insertion = row.insertion else {
            return
        }
        let started = insertion + "="
        var text = plainDraft
        text.replaceSubrange(range, with: started)
        let caret = picker.replacementRange.start + started.utf8.count
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            closePickerAfterStaleDraft()
            return
        }
        closePickerForAccept()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: false, trigger: .edit)
        announceStatus("Inserted \(started) — starts its session when captured")
    }

    /// Shift-Return on a `!` row: insert Bob's replacement, append a blank
    /// line plus `!`, and re-analyse with completion requested so the fresh
    /// item auto-opens a new picker with the just-picked task marked
    /// "Already in this draft". The move picker also maps here: it inserts
    /// the ID plus Bob's continuation (for example `"\n- ^"`).
    func acceptPickerRowAndContinue(id: String) {
        if case .parentTask = picker?.source {
            acceptParentTaskRowAndContinue(id: id)
            return
        }
        if case .projectTaskMove = picker?.source {
            acceptProjectTaskMoveRowAndContinue(id: id)
            return
        }
        guard let picker = picker,
              picker.source == .taskComplete
        else {
            return
        }
        guard plainDraft == picker.draftSnapshot,
              let range = stringRange(in: plainDraft, byteRange: picker.replacementRange)
        else {
            closePickerAfterStaleDraft()
            return
        }
        guard let row = pickerPresentation?.row(id: id) else {
            return
        }
        if row.insertion == nil, let pending = row.pendingBlockID {
            presentTaskCompleteIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: .none
            )
            return
        }
        guard let insertion = row.insertion else {
            announceStatus(row.badgeText ?? "That task cannot be used yet")
            return
        }
        let continued = insertion + "\n\n!"
        var text = plainDraft
        text.replaceSubrange(range, with: continued)
        let caret = picker.replacementRange.start + continued.utf8.count
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            closePickerAfterStaleDraft()
            return
        }
        closePickerForAccept()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
        announceStatus("Inserted \(insertion) — pick the next task to complete")
    }

    /// Accept a Parent Task row and continue the target run when Bob supplied
    /// a continuation. ID-less rows still open the ordinary Add block ID
    /// prompt and do not continue.
    private func acceptParentTaskRowAndContinue(id: String) {
        guard let picker = picker,
            case .parentTask(let context) = picker.source,
            let continuation = context.continuation,
            plainDraft == picker.draftSnapshot,
            let range = stringRange(in: plainDraft, byteRange: picker.replacementRange)
        else {
            closePickerAfterStaleDraft()
            return
        }
        guard let row = pickerPresentation?.row(id: id) else {
            return
        }
        if row.insertion == nil, let pending = row.pendingBlockID {
            presentParentTaskIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: .none
            )
            return
        }
        guard let insertion = row.insertion else {
            announceStatus(row.badgeText ?? "That task cannot be used yet")
            return
        }
        let continued = insertion + continuation
        var text = plainDraft
        text.replaceSubrange(range, with: continued)
        let caret = picker.replacementRange.start + continued.utf8.count
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            closePickerAfterStaleDraft()
            return
        }
        let edit = Self.nativeEditForOrdinaryInsertion(
            insertion: continued,
            draft: plainDraft,
            range: picker.replacementRange
        )
        let appliedNatively =
            edit.map {
                applyBlockIDSpliceNatively(edit: $0, caretUTF8: caret)
            } ?? false
        closePickerForAccept()
        if !appliedNatively {
            suppressedCompletionAcceptanceDraft = text
            setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        }
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
        let marker =
            insertion.hasPrefix("@")
            ? insertion
            : context.scopeToken + insertion
        announceStatus("Inserted \(marker) — pick the next task")
    }

    /// First Escape clears a non-empty filter; otherwise the picker cancels.
    func escapePicker() {
        guard let picker = picker else {
            return
        }
        if !picker.filterText.isEmpty {
            updatePickerFilter("")
        } else {
            cancelPicker()
        }
    }

    /// Lone-plus operator continuation, plus the Complete (`!`) continuation:
    /// insert `key` once at the restored caret, close the picker without a
    /// chip, and suppress reopening so `+2` / `++` match fast typing and
    /// `!!` / `![` fall back to prose or embed completion.
    func continuePickerOperator(_ key: String) {
        guard let openPicker = picker,
              openPicker.filterText.isEmpty,
              plainDraft == openPicker.draftSnapshot,
              let insertRange = stringRange(
                  in: plainDraft,
                  start: openPicker.restoreCursor,
                  end: openPicker.restoreCursor
              )
        else {
            return
        }
        if case .parentTask(let context) = openPicker.source {
            guard context.isLonePlusOperator,
                  context.actionContinuationKeys.contains(key)
            else {
                return
            }
        } else if openPicker.source == .taskComplete {
            guard openPicker.taskCompleteContinuationKeys.contains(key) else {
                return
            }
        } else if case .projectTaskMove(let context) = openPicker.source {
            guard context.actionContinuationKeys.contains(key) else {
                return
            }
        } else {
            return
        }
        var text = plainDraft
        text.replaceSubrange(insertRange, with: key)
        let caret = openPicker.restoreCursor + key.utf8.count
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            closePickerAfterStaleDraft()
            return
        }
        let suppressedStart = openPicker.replacementRange.start
        closePickerForAccept()
        pickerAutoOpenSuppressedStart = suppressedStart
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
    }

    /// Cancel leaves the draft unchanged, restores the caret, suppresses
    /// auto-open for this token, and shows the reopen chip.
    func cancelPicker() {
        guard let openPicker = picker else {
            return
        }
        clearEqualsGestureArm()
        var gotoSnapshot: CaptureTaskGotoScopeState.Snapshot?
        if openPicker.source == .taskGoto {
            var state = gotoClosedTasksState ?? CaptureTaskGotoScopeState()
            if state.sessionID == nil {
                state.beginSession(
                    candidates: openPicker.candidates,
                    appliedIncludesClosedTasks: openPicker.includesClosedTasks
                )
            }
            state.invalidatePendingRequest()
            gotoClosedTasksState = state
            gotoSnapshot = state.snapshot
        }
        let range = openPicker.replacementRange
        clearPickerMarkerHighlight(draftSnapshot: openPicker.draftSnapshot)
        picker = nil
        presentedAliasTip = nil
        pickerPresentation = nil
        pickerIndex = nil
        clearEditorInputLockIfFree()
        if plainDraft == openPicker.draftSnapshot,
           stringRange(in: plainDraft, start: openPicker.restoreCursor, end: openPicker.restoreCursor) != nil
        {
            setPlainDraft(
                plainDraft,
                cursorUTF8Offset: openPicker.restoreCursor,
                suppressSelectionCallbacks: true
            )
        }
        requestFocus(.editor)
        pickerAutoOpenSuppressedStart = range.start
        pickerChip = CapturePickerChipState(
            source: openPicker.source,
            draftSnapshot: openPicker.draftSnapshot,
            replacementRange: range,
            cursor: openPicker.restoreCursor,
            candidates: gotoSnapshot?.candidates ?? openPicker.candidates,
            warnings: openPicker.warnings,
            includesClosedTasks: gotoSnapshot?.desiredIncludesClosedTasks
                ?? openPicker.includesClosedTasks,
            snapshotIncludesClosedTasks: gotoSnapshot?.appliedIncludesClosedTasks
                ?? openPicker.includesClosedTasks
        )
        if case .projectTaskMove(let context) = openPicker.source {
            statusText = movePickerEscStatus(context: context)
        }
    }

    /// `~` or `=` anywhere in a relation picker filter flips the direction
    /// in place: it inserts or removes one tilde at the sigil, keeps the
    /// picker open with the filter untouched, and never suppresses
    /// auto-open. Analysis then live-flips `relation_to` ↔ `relation_from`.
    /// A `=` flip arms the shared equals record so a fast second `=` undoes
    /// the flip and types one `=` into the filter.
    func flipRelationDirection(key: String? = nil, timestamp: TimeInterval = 0) {
        guard let openPicker = picker,
              openPicker.source.isRelation,
              plainDraft == openPicker.draftSnapshot
        else {
            return
        }
        let r = openPicker.replacementRange
        let caretBytes = Array(plainDraft.utf8)
        guard r.start < caretBytes.count, caretBytes[r.start] == 126 else {
            return
        }
        let editPoint = r.start + 1
        let isLinkedFrom =
            editPoint < r.end && editPoint < caretBytes.count && caretBytes[editPoint] == 126
        let text: String
        let caret: Int
        let newRange: CaptureRange
        if !isLinkedFrom {
            guard let insertRange = stringRange(
                in: plainDraft,
                start: editPoint,
                end: editPoint
            ) else {
                return
            }
            var next = plainDraft
            next.replaceSubrange(insertRange, with: "~")
            text = next
            var shiftedRestore = openPicker.restoreCursor
            if shiftedRestore >= editPoint {
                shiftedRestore += 1
            }
            caret = shiftedRestore
            let shiftedEnd = r.end >= editPoint ? r.end + 1 : r.end
            newRange = CaptureRange(start: r.start, end: shiftedEnd)
        } else {
            guard editPoint <= r.end,
                  let deleteRange = stringRange(
                      in: plainDraft, start: editPoint, end: editPoint + 1
                  )
            else {
                return
            }
            var next = plainDraft
            next.removeSubrange(deleteRange)
            text = next
            var shiftedRestore = openPicker.restoreCursor
            if shiftedRestore > editPoint {
                shiftedRestore -= 1
            }
            caret = max(r.start + 1, shiftedRestore)
            newRange = CaptureRange(start: r.start, end: max(r.start + 1, r.end - 1))
        }
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            closePickerAfterStaleDraft()
            return
        }
        pickerAutoOpenSuppressedStart = nil
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        if key == "=" {
            equalsGestureArm = CaptureEqualsGestureArm(
                surface: .picker,
                firstTimestamp: timestamp,
                isOpener: false,
                preDraft: openPicker.draftSnapshot,
                preCaretUTF8: openPicker.restoreCursor,
                postDraft: text,
                postCaretUTF8: caret,
                pickerSnapshot: openPicker
            )
        } else {
            equalsGestureArm = nil
        }
        if var updated = picker {
            updated.draftSnapshot = text
            updated.replacementRange = newRange
            updated.restoreCursor = caret
            picker = updated
            pickerMarkerHighlight = Self.pickerMarkerHighlightRange(
                source: updated.source,
                replacementRange: newRange,
                markerRange: nil
            )
            applyPickerMarkerHighlight()
        }
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
    }

    /// Backspace on an empty filter removes the source's trigger byte together
    /// with any fragment it opened on (`^` for active tasks, `:` for task
    /// links, `/` for Go To, `&` for dependencies, `*` for Blocks, and `~`
    /// for links-to). On linked-from (`~~`) it removes one tilde and flips
    /// back. Parent-task uses Bob's `trigger_removal_range` and never hunts
    /// for the marker. The Task Wikilink picker deletes Bob's
    /// `trigger_removal_range` (the second `(` plus any fragment), leaving
    /// one literal `(`. Otherwise behaves like cancel.
    func removePickerTrigger() {
        guard let picker = picker, picker.filterText.isEmpty else {
            return
        }
        if picker.source == .linkedFrom {
            flipRelationDirection()
            return
        }
        let r = picker.replacementRange
        let caretBytes = Array(plainDraft.utf8)
        if case .wikilinkTask(let context) = picker.source {
            // Bob's verbatim `trigger_removal_range`; deleting it leaves one
            // literal `(`.
            let removal = context.triggerRemovalRange
            if plainDraft == picker.draftSnapshot,
               let deleteRange = stringRange(in: plainDraft, byteRange: removal)
            {
                var text = plainDraft
                text.removeSubrange(deleteRange)
                let caret = removal.start
                closePickerForAccept()
                pickerAutoOpenSuppressedStart = nil
                suppressedCompletionAcceptanceDraft = text
                setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
                scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
                return
            }
            cancelPicker()
            return
        }
        if case .parentTask(let context) = picker.source {
            let removal = context.triggerRemovalRange
            if plainDraft == picker.draftSnapshot,
               let deleteRange = stringRange(in: plainDraft, byteRange: removal)
            {
                var text = plainDraft
                text.removeSubrange(deleteRange)
                let caret = removal.start
                closePickerForAccept()
                pickerAutoOpenSuppressedStart = nil
                suppressedCompletionAcceptanceDraft = text
                setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
                scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
                return
            }
            cancelPicker()
            return
        }
        if case .projectTaskMove(let context) = picker.source {
            let removal = context.triggerRemovalRange
            if plainDraft == picker.draftSnapshot,
               let deleteRange = stringRange(in: plainDraft, byteRange: removal)
            {
                var text = plainDraft
                text.removeSubrange(deleteRange)
                let caret = removal.start
                closePickerForAccept()
                pickerAutoOpenSuppressedStart = nil
                suppressedCompletionAcceptanceDraft = text
                setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
                scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
                return
            }
            cancelPicker()
            return
        }
        if picker.source == .taskLink || picker.source == .taskGoto
            || picker.source == .dependency || picker.source == .blockedTask
            || picker.source == .linksTo || picker.source == .taskComplete
        {
            let sigil: UInt8
            if picker.source == .taskLink {
                sigil = 58 // `:`
            } else if picker.source == .taskGoto {
                sigil = 47 // `/`
            } else if picker.source == .dependency {
                sigil = 38 // `&`
            } else if picker.source == .blockedTask {
                sigil = 42 // `*`
            } else if picker.source == .linksTo {
                sigil = 126 // `~`
            } else {
                sigil = 33 // `!`
            }
            if plainDraft == picker.draftSnapshot,
               r.start < caretBytes.count,
               caretBytes[r.start] == sigil,
               let deleteRange = stringRange(in: plainDraft, start: r.start, end: r.end)
            {
                var text = plainDraft
                text.removeSubrange(deleteRange)
                let caret = r.start
                closePickerForAccept()
                pickerAutoOpenSuppressedStart = nil
                suppressedCompletionAcceptanceDraft = text
                setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
                scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
                return
            }
            cancelPicker()
            return
        }
        if plainDraft == picker.draftSnapshot,
           r.start >= 1,
           r.start - 1 < caretBytes.count,
           caretBytes[r.start - 1] == picker.source.triggerByte,
           let deleteRange = stringRange(in: plainDraft, start: r.start - 1, end: r.end)
        {
            var text = plainDraft
            text.removeSubrange(deleteRange)
            let caret = r.start - 1
            closePickerForAccept()
            pickerAutoOpenSuppressedStart = nil
            suppressedCompletionAcceptanceDraft = text
            setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
            scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
            return
        }
        cancelPicker()
    }

    /// Second `\` right after the alias: rewrites the bare `/` Go To draft
    /// to one literal `\`, mirroring the non-wikilink tail of
    /// `removePickerTrigger()`. Bob never claims `\`, so no Go To picker
    /// can reopen for the new draft.
    func replaceGotoSigilWithLiteralBackslash() {
        guard draftIsBareGotoSigil else {
            return
        }
        closePickerForAccept()
        dismissPickerChip()
        pickerAutoOpenSuppressedStart = nil
        let text = "\\"
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: 1, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: 1, requestCompletion: true, trigger: .edit)
    }

    func openPickerFromChip() {
        guard let chip = pickerChip else {
            return
        }
        guard chip.draftSnapshot == plainDraft else {
            // The draft moved on; rerun analysis instead of opening stale.
            editAnalysisBaseline = ""
            scheduleAnalysis(
                cursorUTF8Offset: collapsedSelectionUTF8Offset(),
                requestCompletion: true,
                trigger: .edit
            )
            return
        }
        pickerAutoOpenSuppressedStart = nil
        let draft = plainDraft
        let r = chip.replacementRange
        // Link seeds from the range start to the caret; New ID seeds the
        // whole part. `:` seeds after the sigil.
        let query: String
        if case .blockID(let context) = chip.source,
           context.isNewIDMode,
           let partRange = stringRange(in: draft, byteRange: r)
        {
            query = String(draft[partRange])
        } else if chip.source == .taskLink || chip.source == .taskGoto {
            query = Self.taskLinkPickerQuery(in: draft, range: r, cursor: chip.cursor)
        } else if let direction = chip.source.dependencyDirection {
            query = Self.dependencyPickerQuery(
                in: draft,
                range: r,
                cursor: chip.cursor,
                leadingSigil: direction.leadingSigil
            )
        } else if chip.source == .taskComplete {
            query = Self.taskCompletePickerQuery(in: draft, range: r, cursor: chip.cursor)
        } else if case .wikilinkTask(let wikilinkContext) = chip.source {
            // Closed-token reopen must seed Bob's query, never a draft slice
            // that would include the closing parentheses.
            query = wikilinkContext.query
        } else if case .parentTask(let context) = chip.source {
            query = Self.parentTaskPickerQuery(in: draft, range: r, cursor: chip.cursor, context: context)
        } else if case .projectTaskMove = chip.source {
            query = Self.projectTaskMovePickerQuery(in: draft, range: r, cursor: chip.cursor)
        } else {
            query = Self.pickerQuery(in: draft, range: r, cursor: chip.cursor)
        }
        // `:` and `&` include the sigil in `r`, so a bare chip always has
        // `cursor == r.start + 1` with no query typed: present from the chip's
        // candidates instead of refetching the same large list. Only a query
        // after the sigil refetches at `r.start`. Vault parent-task matches
        // that rule; scoped parent-task matches `^` (ID-only range).
        let needsRefetch: Bool
        if chip.source == .taskLink || chip.source == .taskGoto || chip.source == .taskComplete {
            needsRefetch = chip.cursor > r.start + 1
        } else if chip.source.isWikilinkTask {
            needsRefetch = chip.cursor > r.start + 2
        } else if let direction = chip.source.dependencyDirection {
            needsRefetch = chip.cursor > r.start + direction.leadingSigil.utf8.count
        } else if case .parentTask(let context) = chip.source {
            needsRefetch = context.isVault ? chip.cursor > r.start + 1 : chip.cursor != r.start
        } else if case .projectTaskMove = chip.source {
            needsRefetch = chip.cursor != r.start
        } else {
            needsRefetch = chip.cursor != r.start
        }
        if chip.source == .taskGoto {
            presentPicker(
                source: chip.source,
                index: Self.taskCatalogIndex(
                    source: chip.source,
                    candidates: chip.candidates
                ),
                candidates: chip.candidates,
                warnings: chip.warnings,
                draft: draft,
                range: r,
                restoreCursor: chip.cursor,
                query: query,
                snapshotIsPartial: false,
                includesClosedTasks: chip.snapshotIncludesClosedTasks,
                gotoDesiredIncludesClosedTasks: chip.includesClosedTasks
            )

            guard
                needsRefetch
                    || chip.includesClosedTasks != chip.snapshotIncludesClosedTasks
            else {
                return
            }
            guard let processClient,
                var state = gotoClosedTasksState,
                let request = state.request(includesClosedTasks: chip.includesClosedTasks)
            else {
                if var state = gotoClosedTasksState,
                    let request = state.request(includesClosedTasks: chip.includesClosedTasks)
                {
                    _ = state.fail(request)
                    gotoClosedTasksState = state
                }
                announceStatus("Could not refresh completed tasks")
                return
            }
            gotoClosedTasksState = state
            startGotoClosedTasksFetch(
                request: request,
                draft: draft,
                range: r,
                cursor: r.start,
                processClient: processClient
            )
            return
        }
        if needsRefetch, let processClient {
            // The chip came from a caret snapshot; refetch the full list at
            // the token start (`r.start + 2` for `((`, where the empty query
            // lives). A keystroke in the meantime abandons the open.
            let refetchCursor = chip.source.isWikilinkTask ? r.start + 2 : r.start
            Task { [weak self, processClient] in
                guard
                    let snapshot = try? await processClient.captureComplete(
                        draft,
                        cursor: refetchCursor,
                        includeClosedTasks: chip.source == .taskGoto && chip.includesClosedTasks
                    )
                else {
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.pickerChip?.draftSnapshot == draft,
                          self.plainDraft == draft,
                          chip.source.isWikilinkTask
                            ? snapshot.replacement.start == r.start
                            : snapshot.replacement == r
                    else {
                        return
                    }
                    switch chip.source {
                    case .activeTask:
                        guard snapshot.context == "active_task" else {
                            return
                        }
                        self.presentPicker(
                            source: chip.source,
                            index: .activeTask(ActiveTaskPickerIndex(candidates: snapshot.candidates)),
                            candidates: snapshot.candidates,
                            warnings: snapshot.warnings,
                            draft: draft,
                            range: r,
                            restoreCursor: chip.cursor,
                            query: query,
                            snapshotIsPartial: false
                        )
                    case .blockID:
                        guard Self.isUsableBlockIDCompletion(snapshot) else {
                            return
                        }
                        self.presentBlockIDPicker(
                            snapshot,
                            draft: draft,
                            range: r,
                            restoreCursor: chip.cursor,
                            query: query,
                            snapshotIsPartial: false
                        )
                    case .taskLink:
                        guard snapshot.context == "task_link" else {
                            return
                        }
                        self.presentPicker(
                            source: chip.source,
                            index: .taskLink(TaskLinkPickerIndex(candidates: snapshot.candidates)),
                            candidates: snapshot.candidates,
                            warnings: snapshot.warnings,
                            draft: draft,
                            range: r,
                            restoreCursor: chip.cursor,
                            query: query,
                            snapshotIsPartial: false
                        )
                    case .taskGoto:
                        return
                    case .dependency, .blockedTask, .linksTo, .linkedFrom:
                        let direction = chip.source.dependencyDirection ?? .prerequisite
                        let expectedContext: String
                        switch direction {
                        case .blocks:
                            expectedContext = "blocked_task"
                        case .linksTo:
                            expectedContext = "relation_to"
                        case .linkedFrom:
                            expectedContext = "relation_from"
                        case .prerequisite:
                            expectedContext = "task_dependency"
                        }
                        guard snapshot.context == expectedContext else {
                            return
                        }
                        self.presentPicker(
                            source: chip.source,
                            index: Self.dependencyPickerIndex(snapshot.candidates, direction: direction),
                            candidates: snapshot.candidates,
                            warnings: snapshot.warnings,
                            draft: draft,
                            range: r,
                            restoreCursor: chip.cursor,
                            query: query,
                            snapshotIsPartial: false,
                            dependencyOwner: snapshot.owner
                        )
                    case .taskComplete:
                        guard snapshot.context == "task_complete" else {
                            return
                        }
                        self.presentPicker(
                            source: chip.source,
                            index: .taskComplete(TaskCompletePickerIndex(candidates: snapshot.candidates)),
                            candidates: snapshot.candidates,
                            warnings: snapshot.warnings,
                            draft: draft,
                            range: r,
                            restoreCursor: chip.cursor,
                            query: query,
                            snapshotIsPartial: false,
                            taskCompleteContinuationKeys: snapshot.picker?.actionContinuationKeys ?? []
                        )
                    case .wikilinkTask(_):
                        guard snapshot.context == "wikilink_task" else {
                            return
                        }
                        self.presentPicker(
                            source: chip.source,
                            index: .wikilinkTask(WikilinkTaskPickerIndex(candidates: snapshot.candidates)),
                            candidates: snapshot.candidates,
                            warnings: snapshot.warnings,
                            draft: draft,
                            range: r,
                            restoreCursor: chip.cursor,
                            query: query,
                            snapshotIsPartial: false
                        )
                    case .parentTask(let context):
                        guard Self.isMatchingParentTaskSnapshot(
                            snapshot,
                            expected: snapshot,
                            context: context
                        ) else {
                            return
                        }
                        self.presentParentTaskPicker(
                            snapshot,
                            context: context,
                            draft: draft,
                            range: r,
                            restoreCursor: chip.cursor,
                            query: query,
                            snapshotIsPartial: false
                        )
                    case .projectTaskMove(let context):
                        guard Self.isMatchingProjectTaskMoveSnapshot(
                            snapshot,
                            expected: snapshot,
                            context: context
                        ) else {
                            return
                        }
                        self.presentProjectTaskMovePicker(
                            snapshot,
                            context: context,
                            draft: draft,
                            range: r,
                            restoreCursor: chip.cursor,
                            query: query,
                            snapshotIsPartial: false
                        )
                    }
                }
            }
            return
        }
        switch chip.source {
        case .activeTask:
            presentPicker(
                source: chip.source,
                index: .activeTask(ActiveTaskPickerIndex(candidates: chip.candidates)),
                candidates: chip.candidates,
                warnings: chip.warnings,
                draft: draft,
                range: r,
                restoreCursor: chip.cursor,
                query: query,
                snapshotIsPartial: false
            )
        case .taskLink:
            presentPicker(
                source: chip.source,
                index: .taskLink(TaskLinkPickerIndex(candidates: chip.candidates)),
                candidates: chip.candidates,
                warnings: chip.warnings,
                draft: draft,
                range: r,
                restoreCursor: chip.cursor,
                query: query,
                snapshotIsPartial: false
            )
        case .taskGoto:
            return
        case .dependency, .blockedTask, .linksTo, .linkedFrom:
            let direction = chip.source.dependencyDirection ?? .prerequisite
            presentPicker(
                source: chip.source,
                index: Self.dependencyPickerIndex(chip.candidates, direction: direction),
                candidates: chip.candidates,
                warnings: chip.warnings,
                draft: draft,
                range: r,
                restoreCursor: chip.cursor,
                query: query,
                snapshotIsPartial: false,
                dependencyOwner: chip.dependencyOwner
            )
        case .taskComplete:
            presentPicker(
                source: chip.source,
                index: .taskComplete(TaskCompletePickerIndex(candidates: chip.candidates)),
                candidates: chip.candidates,
                warnings: chip.warnings,
                draft: draft,
                range: r,
                restoreCursor: chip.cursor,
                query: query,
                snapshotIsPartial: false
            )
        case .wikilinkTask(_):
            presentPicker(
                source: chip.source,
                index: .wikilinkTask(WikilinkTaskPickerIndex(candidates: chip.candidates)),
                candidates: chip.candidates,
                warnings: chip.warnings,
                draft: draft,
                range: r,
                restoreCursor: chip.cursor,
                query: query,
                snapshotIsPartial: false
            )
        case .blockID(let context):
            // The chip's source already carries the opening snapshot's
            // field, route, marker, intent, and rules.
            presentPicker(
                source: chip.source,
                index: .blockID(
                    BlockIDPickerIndex(
                        field: context.field,
                        candidates: chip.candidates,
                        route: context.route,
                        scope: context.scope,
                        markerLine: context.field?.markerLine(in: draft)
                    )
                ),
                candidates: chip.candidates,
                warnings: chip.warnings,
                draft: draft,
                range: r,
                restoreCursor: chip.cursor,
                query: query,
                snapshotIsPartial: false
            )
        case .parentTask(let context):
            presentPicker(
                source: chip.source,
                index: .parentTask(ParentTaskPickerIndex(candidates: chip.candidates, context: context)),
                candidates: chip.candidates,
                warnings: chip.warnings,
                draft: draft,
                range: r,
                restoreCursor: chip.cursor,
                query: query,
                snapshotIsPartial: false
            )
        case .projectTaskMove(let context):
            presentPicker(
                source: chip.source,
                index: .projectTaskMove(ProjectTaskMovePickerIndex(candidates: chip.candidates, context: context)),
                candidates: chip.candidates,
                warnings: chip.warnings,
                draft: draft,
                range: r,
                restoreCursor: chip.cursor,
                query: query,
                snapshotIsPartial: false
            )
        }
    }

    func dismissPickerChip() {
        pickerChip = nil
    }

    /// Why Return with no selectable Block ID row is a no-op: an empty
    /// field names the missing ID, a taken or invalid ID names its state,
    /// and anything else means no rows matched.
    private static func blockIDNoAcceptReason(
        filter: String,
        presentation: CapturePickerPresentation?
    ) -> String {
        if filter.isEmpty {
            return "Type a new ID"
        }
        switch presentation?.blockIDStatus?.availability {
        case .taken(let line, _):
            if let line {
                return "\(filter) is already used on line \(line)"
            }
            return "\(filter) is already used"
        case .invalid(let description):
            return description
        case .available, .unchecked, nil:
            break
        }
        return "No matches"
    }

    /// An incomplete picker token is a state, not an error: skip the doomed
    /// live dry run and show a calm status line instead of red errors.
    /// Precedence is `active_task`, then `task_link`, then `task_goto`, then
    /// `task_parent`, then `task_dependency`, then `blocked_task`, then
    /// `task_complete`, then `dependency_target`, then `pomodoro_id`, then
    /// `block_id`, then `template_row`, then `list_item`, then `section`,
    /// then the `=<X>#` named-start incomplete, checked top-level or in any
    /// item.
    /// Suffix-only states such as `@sase:x#` (`pomodoro_name` without a
    /// `pomodoro_start` object) keep today's behavior.
    static func pickerNeed(in parse: CaptureParseResponse) -> CapturePickerNeed? {
        let itemNeeds = parse.items.flatMap { $0.needs }
        func needs(_ need: String) -> Bool {
            parse.needs.contains(need) || itemNeeds.contains(need)
        }
        let hasTransferSource = parse.spans.contains { $0.kind == "transfer_source" }
        if needs("active_task") {
            return .activeTask
        }
        if needs("task_link") {
            return .taskLink
        }
        if needs("task_goto") {
            return .taskGoto
        }
        if needs("merge_in_source") {
            return .mergeInSource
        }
        if needs("task_parent") {
            return .taskParent
        }
        if needs("task_dependency") {
            return .dependency
        }
        if needs("blocked_task") {
            return .blockedTask
        }
        if needs("relation_target") || needs("relation_to") || needs("relation_from") {
            return .relationTarget
        }
        if needs("relation_label") {
            return .relationLabel
        }
        if needs("task_complete") {
            return .taskComplete
        }
        if needs("wikilink_task") {
            return .wikilinkTask
        }
        if needs("dependency_target") {
            return .dependencyTarget
        }
        if needs("pomodoro_id") {
            return .pomodoroID
        }
        if needs("pomodoro_split_type") {
            return .pomodoroSplitType
        }
        if needs("pomodoro_merge_dest") {
            return .pomodoroMergeDestination
        }
        // Transfer destination needs run Bob's read-only dry run so the panel
        // can show resolved sources and destination forms. Ordinary block-ID
        // and section pickers retain their existing quiet behavior.
        if needs("block_id"), !hasTransferSource {
            return .blockID
        }
        if needs("project_task_move") {
            return .projectTaskMove
        }
        if needs("template_row") {
            return .templateRow
        }
        // A lone `@file` or `@file#section` header has no bullet to file yet:
        // a state to finish, not a refusal to flash.
        if needs("list_item") {
            return .listItem
        }
        // An unterminated quoted section selector (`@route#"…`) is an
        // editing state with a `section` need, never a mistake: keep the
        // preview calm like `list_item`, never a flashed refusal.
        if needs("section"), !hasTransferSource {
            return .section
        }
        // A `=<X>#` draft (or chain token) is `incomplete` with a
        // `pomodoro_name` need and a partial `pomodoro_start` spec. It keeps
        // the completion list open while the preview stays calm. An `x=#`
        // past draft is the same calm state with a partial `pomodoro_past`
        // spec; Bob's `pomodoro_past_name` menu applies where the name menu does.
        let scopes: [(mode: String, needs: [String], hasStart: Bool, hasPast: Bool)] =
            if parse.items.isEmpty {
                [(
                    parse.mode,
                    parse.needs,
                    parse.pomodoroStart != nil,
                    parse.pomodoroPast != nil
                )]
            } else {
                parse.items.map {
                    ($0.mode, $0.needs, $0.pomodoroStart != nil, $0.pomodoroPast != nil)
                }
            }
        if scopes.contains(where: {
            $0.mode == "incomplete" && $0.needs.contains("pomodoro_name")
                && ($0.hasStart || $0.hasPast)
        }) {
            return .pomodoroStart
        }
        return nil
    }

    private func applyQuietIncompletePicker(_ need: CapturePickerNeed, parse: CaptureParseResponse) {
        previewState = .idle
        clearPreviewOutputs()
        closePendingText = nil
        closePendingAction = "Close"
        errorMessage = nil
        errorCode = nil
        switch need {
        case .templateRow:
            statusText = parse.diagnostics.first(where: { $0.code == "template_missing_rows" })?.message
                ?? need.statusText
        case .dependencyTarget:
            statusText = CaptureRelationshipCopy.dependencyTargetHint(
                parse: parse,
                names: relationshipDisplayNames
            )
        case .taskParent where CaptureRelationshipCopy.parseHasRelationshipModifiers(parse):
            statusText = CaptureRelationshipCopy.relateStatusText
        default:
            statusText = need.statusText
        }
    }

    /// Bob's parsed merge-in clause identifies which task-parent completion
    /// replacement is a source slot. Return that task's parsed body for the
    /// picker header; Swift does not scan the draft for `<` or task syntax.
    static func mergeInTargetTitle(
        in parse: CaptureParseResponse,
        replacement: CaptureRange
    ) -> String? {
        let scopes: [(range: CaptureRange?, body: String, mergeIn: CaptureMergeIn?)]
        if parse.items.isEmpty {
            scopes = [(nil, parse.body, parse.mergeIn)]
        } else {
            scopes = parse.items.map { ($0.range, $0.body, $0.mergeIn) }
        }
        guard let scope = scopes.first(where: { scope in
            guard let mergeIn = scope.mergeIn,
                  replacement.start >= mergeIn.arrow.end
            else {
                return false
            }
            if let range = scope.range {
                return range.start <= replacement.start && replacement.start <= range.end
            }
            return true
        }) else {
            return nil
        }
        let title = scope.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func rememberRelationshipDisplayName(replacement: String, text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }
        let trimmed = replacement.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return
        }
        relationshipDisplayNames[trimmed] = trimmedText
        relationshipDisplayNames[replacement] = trimmedText
        if trimmed.hasPrefix("~~") {
            let locator = String(trimmed.dropFirst(2))
            if !locator.isEmpty {
                relationshipDisplayNames[locator] = trimmedText
            }
        } else if trimmed.hasPrefix("&") || trimmed.hasPrefix("*") || trimmed.hasPrefix("~") {
            let locator = String(trimmed.dropFirst())
            if !locator.isEmpty {
                relationshipDisplayNames[locator] = trimmedText
            }
        }
    }

    /// The pending close/start-list trim for a draft that dangles on a list
    /// separator or a Work Log entry: for every item whose `needs` contains
    /// `pomodoro_close_task` (`,`/`!`/`~`/`*`), `pomodoro_start_task` (`~`/`,`),
    /// or `pomodoro_close_log_text` (a `- <n>` bullet or an inline `x 2`
    /// number with no entry text yet), the one `interactive_placeholder`
    /// span Bob reported inside that item's range is removed, so the live
    /// preview runs on the trimmed draft — exactly what has been typed so
    /// far. For a dangling bullet the removal leaves a `- ` placeholder row
    /// (or `-` after the trailing-space strip), which bob treats as a
    /// harmless placeholder, so the card previews the rest. For a dangling
    /// inline number the removal leaves `x` (or `x =` from `x 2 =`),
    /// which bob reads as the chain. Behavior is unchanged. Returns the trimmed draft, the dangling separator
    /// (or task number for a log pend) for the pending notice, and the footer
    /// action the pending card disables (`"Start"` when every pending scope
    /// is a start list, else `"Close"`). Single-item drafts carry no
    /// `items[]`; then the top-level `needs` and spans apply. Nil when nothing
    /// dangles, when the picker needs win (checked by the caller), or when the
    /// placeholder shape is unexpected — then the draft previews exactly as
    /// today. No Swift-side ledger logic: the placeholder range comes straight
    /// from Bob. Chains trim per item, as closes do.
    static func closePendingTrim(
        in parse: CaptureParseResponse,
        draft: String
    ) -> (trimmed: String, separator: String, action: String)? {
        let scopes: [(range: CaptureRange?, needsTask: Bool, needsLog: Bool, isStart: Bool)]
        if parse.items.isEmpty {
            let isStart = parse.needs.contains("pomodoro_start_task")
            let needsTask = parse.needs.contains("pomodoro_close_task") || isStart
            let needsLog = parse.needs.contains("pomodoro_close_log_text")
            scopes = [(nil, needsTask, needsLog, isStart)]
        } else {
            scopes = parse.items.map { item in
                let isStart = item.needs.contains("pomodoro_start_task")
                let needsTask =
                    item.needs.contains("pomodoro_close_task") || isStart
                let needsLog = item.needs.contains("pomodoro_close_log_text")
                return (item.range, needsTask, needsLog, isStart)
            }
        }
        let pending = scopes.filter { $0.needsTask || $0.needsLog }
        guard !pending.isEmpty else {
            return nil
        }
        var removals: [Range<String.Index>] = []
        for scope in pending {
            let placeholders = parse.spans.filter { span in
                guard span.kind == "interactive_placeholder" else {
                    return false
                }
                guard let scopeRange = scope.range else {
                    return true
                }
                return scopeRange.start <= span.start && span.end <= scopeRange.end
            }
            guard placeholders.count == 1,
                  let span = placeholders.first,
                  let range = stringRange(in: draft, start: span.start, end: span.end)
            else {
                return nil
            }
            removals.append(range)
        }
        guard !removals.isEmpty else {
            return nil
        }
        let ordered = removals.sorted { $0.lowerBound < $1.lowerBound }
        guard let first = ordered.first else {
            return nil
        }
        let separator = String(draft[first])
        let isListSeparator = separator == "," || separator == "!" || separator == "~" || separator == "*"
        let isLogIndex = !separator.isEmpty && separator.allSatisfy { $0.isASCII && $0.isNumber }
        guard isListSeparator || isLogIndex else {
            return nil
        }
        var trimmed = draft
        for range in ordered.reversed() {
            trimmed.removeSubrange(range)
        }
        // A dangling bullet leaves a trailing space (`x\n- 1` trims to
        // `x\n- `): strip it so the preview runs on the placeholder row
        // (`x\n-`, still a harmless placeholder).
        if isLogIndex {
            while trimmed.hasSuffix(" ") || trimmed.hasSuffix("\t") {
                trimmed.removeLast()
            }
        }
        let action = pending.allSatisfy { $0.isStart } ? "Start" : "Close"
        return (trimmed, separator, action)
    }

    private func closePickerForAccept() {
        retireAliasTipDisplayEligibility()
        clearEqualsGestureArm()
        if let openPicker = picker {
            clearPickerMarkerHighlight(draftSnapshot: openPicker.draftSnapshot)
        }
        picker = nil
        presentedAliasTip = nil
        pickerPresentation = nil
        pickerIndex = nil
        gotoClosedTasksState = nil
        pickerChip = nil
        clearEditorInputLockIfFree()
        requestFocus(.editor)
    }

    /// Native undo of a `.` / move-bullet alias restores the literal while the
    /// picker still holds the rewritten snapshot. Dismiss only those token
    /// sessions. Modal dependency pickers keep owning the panel while the user
    /// types, and `=` rewrite echoes must not clear `equalsGestureArm`.
    private func shouldDismissPickerAfterEditorDraftChange(draft: String) -> Bool {
        guard let openPicker = picker, openPicker.draftSnapshot != draft else {
            return false
        }
        switch openPicker.source {
        case .blockID, .projectTaskMove:
            return true
        default:
            return false
        }
    }

    private func closePickerAfterStaleDraft() {
        clearEqualsGestureArm()
        if let openPicker = picker {
            clearPickerMarkerHighlight(draftSnapshot: openPicker.draftSnapshot)
        }
        picker = nil
        presentedAliasTip = nil
        pickerPresentation = nil
        pickerIndex = nil
        gotoClosedTasksState = nil
        clearEditorInputLockIfFree()
        requestFocus(.editor)
        announceStatus("Draft changed — reopen the task picker")
    }

    /// Hide path: close the picker without suppression, restore the caret,
    /// and clear the chip. Re-show reopens via the retained-draft analysis.
    private func closePickerForDismissal() {
        clearEqualsGestureArm()
        guard let openPicker = picker else {
            pickerMarkerHighlight = nil
            pickerChip = nil
            pickerAutoOpenSuppressedStart = nil
            gotoClosedTasksState = nil
            return
        }
        clearPickerMarkerHighlight(draftSnapshot: openPicker.draftSnapshot)
        editAnalysisBaseline = ""
        picker = nil
        presentedAliasTip = nil
        pickerPresentation = nil
        pickerIndex = nil
        gotoClosedTasksState = nil
        pickerChip = nil
        pickerAutoOpenSuppressedStart = nil
        clearEditorInputLockIfFree()
        if plainDraft == openPicker.draftSnapshot,
           stringRange(in: plainDraft, start: openPicker.restoreCursor, end: openPicker.restoreCursor) != nil
        {
            setPlainDraft(
                plainDraft,
                cursorUTF8Offset: openPicker.restoreCursor,
                suppressSelectionCallbacks: true
            )
        }
    }

    private func clearPickerState() {
        clearPickerMarkerHighlight(draftSnapshot: plainDraft)
        picker = nil
        presentedAliasTip = nil
        pickerPresentation = nil
        pickerIndex = nil
        gotoClosedTasksState = nil
        pickerChip = nil
        pickerAutoOpenSuppressedStart = nil
    }

    func selectNextCompletion() {
        guard let count = completionResponse?.candidates.count, count > 0 else {
            return
        }
        if let completionResponse, Self.placeMenuScope(completionResponse) != nil {
            placeMenuSelectionWasExplicit = true
        }
        if let index = selectedCompletionIndex {
            selectedCompletionIndex = (index + 1) % count
        } else {
            selectedCompletionIndex = 0
        }
    }

    func selectPreviousCompletion() {
        guard let count = completionResponse?.candidates.count, count > 0 else {
            return
        }
        if let completionResponse, Self.placeMenuScope(completionResponse) != nil {
            placeMenuSelectionWasExplicit = true
        }
        if let index = selectedCompletionIndex {
            selectedCompletionIndex = (index + count - 1) % count
        } else {
            selectedCompletionIndex = count - 1
        }
    }

    func acceptSelectedCompletionThenSubmitAndOpen() {
        guard acceptSelectedCompletion(),
              !completionVisible,
              !pickerVisible,
              !inlinePromptVisible,
              hasDraft
        else {
            return
        }
        submitAfterCurrentAnalysis(openAfterCapture: true)
    }

    func setRecordMoreExpanded(_ expanded: Bool) {
        guard let presentation = currentRecordPresentation() else {
            return
        }
        let key = recordFocusState?.fieldKey ?? presentation.activeFieldKey
        let selected = recordFocusState?.selectedRowKey ?? presentation.selectedRowKey
        recordFocusState = CaptureRecordFocusState(
            draft: plainDraft,
            generation: analysisGeneration,
            sequence: recordRequestSequence,
            clientIdentity: processClient?.identityToken ?? "",
            itemIndex: presentation.itemIndex,
            fieldKey: key,
            showsMore: expanded,
            selectedRowKey: selected
        )
        recordPresentation = CaptureRecordPresentation(
            record: presentation.record,
            itemIndex: presentation.itemIndex,
            rows: presentation.rows,
            activeFieldKey: key,
            selectedRowKey: selected,
            showsMore: expanded
        )
    }

    @discardableResult
    func requestRecordField(_ key: String) -> Bool {
        guard let presentation = currentRecordPresentation(),
              let cursor = collapsedSelectionUTF8Offset()
        else {
            return false
        }
        return requestRecordField(key, cursor: cursor, itemIndex: presentation.itemIndex)
    }

    private func requestRecordField(
        _ key: String,
        cursor: Int,
        itemIndex: Int?
    ) -> Bool {
        guard let processClient,
              let parse = latestParse,
              parse.input == plainDraft,
              lastAppliedParseDraft == plainDraft,
              lastAppliedParseGeneration == analysisGeneration,
              lastAppliedParseClientIdentity == processClient.identityToken,
              let presentation = CaptureRecordPresentation.make(parse: parse, cursor: cursor),
              presentation.itemIndex == itemIndex,
              presentation.record.assistVersion == 1,
              presentation.rows.contains(where: { $0.key == key })
        else {
            return false
        }

        recordFocusState = CaptureRecordFocusState(
            draft: plainDraft,
            generation: analysisGeneration,
            sequence: recordRequestSequence,
            clientIdentity: processClient.identityToken,
            itemIndex: itemIndex,
            fieldKey: key,
            showsMore: recordFocusState?.showsMore ?? presentation.showsMore,
            selectedRowKey: key
        )
        scheduleAnalysis(
            cursorUTF8Offset: cursor,
            requestCompletion: true,
            trigger: .selection,
            recordField: key,
            recordItemIndex: itemIndex
        )
        return true
    }

    func recordTab() {
        guard recordAssistAvailable,
              let presentation = currentRecordPresentation()
        else {
            return
        }
        if recordCompletionListVisible {
            _ = acceptSelectedCompletion()
            return
        }
        guard let key = presentation.firstMissingFieldKey,
              let cursor = collapsedSelectionUTF8Offset()
        else {
            requestFocus(.editor)
            return
        }
        recordFocusState = CaptureRecordFocusState(
            draft: plainDraft,
            generation: analysisGeneration,
            sequence: recordRequestSequence,
            clientIdentity: processClient?.identityToken ?? "",
            itemIndex: presentation.itemIndex,
            fieldKey: key,
            showsMore: presentation.showsMore,
            selectedRowKey: key
        )
        scheduleAnalysis(
            cursorUTF8Offset: cursor,
            requestCompletion: true,
            trigger: .selection,
            nextMissingRecordField: true,
            recordItemIndex: presentation.itemIndex
        )
    }

    func recordShiftTab() {
        guard recordAssistAvailable,
              let presentation = currentRecordPresentation()
        else {
            return
        }
        guard !presentation.record.missing.isEmpty else {
            requestFocus(.editor)
            return
        }
        let missing = presentation.record.missing
        let currentKey = recordFocusState?.fieldKey ?? presentation.activeFieldKey
        let currentPosition = currentKey.flatMap { missing.firstIndex(of: $0) } ?? 0
        let previousKey = missing[max(0, currentPosition - 1)]
        guard let cursor = collapsedSelectionUTF8Offset() else {
            return
        }
        _ = requestRecordField(previousKey, cursor: cursor, itemIndex: presentation.itemIndex)
    }

    func recordReturn(openAfterCapture: Bool = false) {
        if selectedCompletionIndex != nil,
           recordCompletionListVisible || recordShowsGenericCompletionFallback
        {
            _ = acceptSelectedCompletion()
            return
        }
        guard let processClient, hasDraft else {
            return
        }
        let draft = plainDraft
        let generation = analysisGeneration
        let sequence = recordRequestSequence
        let clientIdentity = processClient.identityToken
        guard let analysisTask else {
            finishRecordReturn(
                draft: draft,
                generation: generation,
                clientIdentity: clientIdentity,
                openAfterCapture: openAfterCapture
            )
            return
        }
        recordReturnTask?.cancel()
        recordReturnTask = Task { [weak self, processClient, analysisTask] in
            await analysisTask.value
            guard !Task.isCancelled, let self,
                  self.analysisGeneration == generation,
                  self.recordRequestSequence == sequence,
                  self.plainDraft == draft,
                  self.processClient === processClient,
                  processClient.identityToken == clientIdentity
            else {
                return
            }
            self.recordReturnTask = nil
            self.finishRecordReturn(
                draft: draft,
                generation: generation,
                clientIdentity: clientIdentity,
                openAfterCapture: openAfterCapture
            )
        }
    }

    private func finishRecordReturn(
        draft: String,
        generation: UInt64,
        clientIdentity: String,
        openAfterCapture: Bool
    ) {
        guard let parse = latestParse,
              parse.input == draft,
              lastAppliedParseDraft == draft,
              lastAppliedParseGeneration == generation,
              lastAppliedParseClientIdentity == clientIdentity
        else {
            return
        }
        if selectedCompletionIndex != nil,
           recordCompletionListVisible || recordShowsGenericCompletionFallback
        {
            _ = acceptSelectedCompletion()
            return
        }
        if let blocker = recordReturnBlocker(in: parse) {
            if let fieldKey = blocker.fieldKey,
               let presentation = CaptureRecordPresentation.make(
                   parse: parse,
                   cursor: blocker.cursor
               ),
               presentation.record.assistVersion == 1
            {
                if let fieldLabel = blocker.fieldLabel {
                    refuseStatus(blocker.message ?? "Needs \(fieldLabel)")
                }
                _ = requestRecordField(
                    fieldKey,
                    cursor: blocker.cursor,
                    itemIndex: presentation.itemIndex
                )
            } else {
                if let message = blocker.message {
                    refuseStatus(message)
                }
                requestFocus(.editor)
                restoreSelection(cursorUTF8Offset: blocker.cursor, suppressEditorCallbacks: true)
            }
            return
        }
        if case .failed(let message) = previewState {
            refuseStatus(errorMessage ?? message)
            requestFocus(.editor)
            return
        }
        submit(openAfterCapture: openAfterCapture)
    }

    private func recordReturnBlocker(
        in parse: CaptureParseResponse
    ) -> CaptureRecordReturnBlocker? {
        var blockers: [CaptureRecordReturnBlocker] = []
        let scopes: [(record: CaptureRecord, start: Int)]
        if parse.items.isEmpty {
            scopes = parse.record.map { [($0, 0)] } ?? []
        } else {
            scopes = parse.items.compactMap { item in
                item.record.map { ($0, item.range.start) }
            }
        }

        for (record, itemStart) in scopes {
            if let field = record.fields.first(where: { $0.state == "invalid" }) {
                let message = parse.diagnostics.first(where: { diagnostic in
                    guard diagnostic.severity == "error", let range = diagnostic.range else {
                        return false
                    }
                    return field.range.map { range.start <= $0.end && range.end >= $0.start }
                        ?? field.valueRanges.contains {
                            range.start <= $0.end && range.end >= $0.start
                        }
                })?.message
                blockers.append(CaptureRecordReturnBlocker(
                    cursor: itemStart,
                    fieldKey: field.key,
                    fieldLabel: field.label,
                    message: message ?? "Fix \(field.label)"
                ))
            } else if let key = record.missing.first,
                      let field = record.fields.first(where: { $0.key == key })
            {
                blockers.append(CaptureRecordReturnBlocker(
                    cursor: itemStart,
                    fieldKey: key,
                    fieldLabel: field.label,
                    message: "Needs \(field.label)"
                ))
            }
        }

        let recordNeeds: Set<String> = ["record_field", "record_value", "record_create"]
        let allNeeds = Set(parse.needs + parse.items.flatMap(\.needs))
        if !allNeeds.subtracting(recordNeeds).isEmpty {
            blockers.append(CaptureRecordReturnBlocker(
                cursor: 0,
                fieldKey: nil,
                fieldLabel: nil,
                message: Self.pickerNeed(in: parse)?.statusText
            ))
        }

        for diagnostic in parse.diagnostics where diagnostic.severity == "error" {
            blockers.append(CaptureRecordReturnBlocker(
                cursor: diagnostic.range?.start ?? 0,
                fieldKey: nil,
                fieldLabel: nil,
                message: diagnostic.message
            ))
        }
        return blockers.min(by: { $0.cursor < $1.cursor })
    }

    func dismissRecordCard() {
        recordCardDismissedDraft = plainDraft
        invalidateRecordInteraction(clearPresentation: true)
        dismissCompletion()
        requestFocus(.editor)
    }

    @discardableResult
    func editRecordField() -> Bool {
        guard recordCompletionSnapshotIsCurrent,
              let response = completionResponse,
              let edit = response.record?.edit,
              let range = stringRange(in: plainDraft, byteRange: edit.replacementRange)
        else {
            return false
        }
        let continuation = edit.continuation
        let cursor = continuation.cursor
        let itemIndex = recordCompletionSnapshot?.itemIndex
        var text = plainDraft
        text.replaceSubrange(range, with: edit.replacement)
        guard stringRange(in: text, start: cursor, end: cursor) != nil else {
            statusText = "Completion cursor is stale"
            dismissCompletion()
            return false
        }
        return applyRecordDraftEdit(
            text: text,
            cursor: cursor,
            continuation: continuation,
            itemIndex: itemIndex,
            replacementRange: edit.replacementRange,
            replacementText: edit.replacement
        )
    }

    @discardableResult
    func acceptRecordCandidate(_ candidate: CaptureCompletionCandidate) -> Bool {
        guard recordCompletionSnapshotIsCurrent,
              let response = completionResponse,
              response.candidates.contains(candidate),
              let range = stringRange(in: plainDraft, byteRange: response.replacement)
        else {
            return false
        }
        retireAliasTipDisplayEligibility()
        let continuation = candidate.recordContinuation
        let itemIndex = recordCompletionSnapshot?.itemIndex
        let cursor = continuation?.cursor
            ?? candidate.cursorAfter
            ?? response.replacement.start + candidate.replacement.utf8.count
        var text = plainDraft
        text.replaceSubrange(range, with: candidate.replacement)
        guard stringRange(in: text, start: cursor, end: cursor) != nil else {
            statusText = "Completion cursor is stale"
            dismissCompletion()
            return false
        }
        return applyRecordDraftEdit(
            text: text,
            cursor: cursor,
            continuation: continuation,
            itemIndex: itemIndex,
            replacementRange: response.replacement,
            replacementText: candidate.replacement
        )
    }

    private func applyRecordDraftEdit(
        text: String,
        cursor: Int,
        continuation: CaptureRecordContinuation?,
        itemIndex: Int? = nil,
        replacementRange: CaptureRange? = nil,
        replacementText: String
    ) -> Bool {
        let nativeEdit: CaptureNativeRewriteEdit?
        if let replacementRange,
           let utf16Replacement = utf16Range(in: plainDraft, byteRange: replacementRange),
           let cursorUTF16 = utf16Range(in: text, start: cursor, end: cursor)?.location
        {
            nativeEdit = CaptureNativeRewriteEdit(
                replacementRange: utf16Replacement,
                replacementText: replacementText,
                resultingSelection: NSRange(location: cursorUTF16, length: 0),
                expectedDraft: plainDraft,
                resultingDraft: text
            )
        } else {
            nativeEdit = nil
        }
        dismissCompletion()
        if plainDraft != text {
            recordCardDismissedDraft = nil
        }
        suppressedCompletionAcceptanceDraft = text
        if let nativeEdit, applyNativeRewriteEdit?(nativeEdit) == true {
            if plainDraft != text {
                isApplyingProgrammaticDraft = true
                attributedDraft = AttributedString(text)
                isApplyingProgrammaticDraft = false
            }
            restoreSelection(cursorUTF8Offset: cursor, suppressEditorCallbacks: true)
        } else {
            suppressedCompletionAcceptanceDraft = nil
            setPlainDraft(text, cursorUTF8Offset: cursor, suppressSelectionCallbacks: true)
        }
        scheduleAnalysis(
            cursorUTF8Offset: cursor,
            requestCompletion: continuation != nil,
            trigger: .edit,
            nextMissingRecordField: continuation?.nextMissingField ?? false,
            recordItemIndex: itemIndex
        )
        requestFocus(.editor)
        return true
    }

    private func currentRecordPresentation() -> CaptureRecordPresentation? {
        guard let parse = latestParse,
              parse.input == plainDraft,
              let processClient,
              lastAppliedParseDraft == plainDraft,
              lastAppliedParseGeneration == analysisGeneration,
              lastAppliedParseClientIdentity == processClient.identityToken,
              let cursor = collapsedSelectionUTF8Offset()
        else {
            return nil
        }
        return CaptureRecordPresentation.make(
            parse: parse,
            cursor: cursor,
            showsMore: recordFocusState?.showsMore ?? false,
            selectedRowKey: recordFocusState?.selectedRowKey
        )
    }

    private func invalidateRecordInteraction(clearPresentation: Bool) {
        recordRequestSequence &+= 1
        recordAnalysisRequest = nil
        recordCompletionSnapshot = nil
        recordReturnTask?.cancel()
        recordReturnTask = nil
        recordInteractionPending = false
        if clearPresentation {
            recordPresentation = nil
            recordFocusState = nil
            recordAssistVersion = nil
        }
    }

    @discardableResult
    func acceptSelectedCompletion() -> Bool {
        guard let completionResponse else {
            statusText = "Completion range is stale"
            dismissCompletion()
            return false
        }
        if completionResponse.candidates.isEmpty {
            return false
        }
        // Notebook near-miss and refused menus stay unselected; Tab/Return
        // must not invent a choice. Drawer and other lists still take the
        // first row on Tab when Bob opened them without a selection.
        if completionResponse.placeMenu?.kind == "notebook_section",
            selectedCompletionIndex == nil
        {
            return false
        }
        if selectedCompletionIndex == nil {
            selectedCompletionIndex = completionResponse.candidates.isEmpty ? nil : 0
        }
        guard let candidate = selectedCompletion,
              let range = stringRange(in: plainDraft, byteRange: completionResponse.replacement)
        else {
            statusText = "Completion range is stale"
            dismissCompletion()
            return false
        }

        if CaptureCompletionMenu.isDisabled(candidate) {
            return true
        }

        retireAliasTipDisplayEligibility()

        if Self.isRecordCompletion(completionResponse) {
            return acceptRecordCandidate(candidate)
        }

        if completionResponse.context == "task", candidate.requiresBlockID {
            presentTaskIDPrompt(
                candidate: candidate,
                draftSnapshot: plainDraft,
                replacementRange: completionResponse.replacement
            )
            return true
        }

        // A `pomodoro_start_name` create row either makes a brand-new session
        // or starts a new session named like a completed one ("again",
        // `state == "completed"`); both only splice the slug, and the daily
        // note is not mutated until the later `bob capture` transaction.
        if completionResponse.context == "pomodoro_start_name", candidate.createsPomodoro {
            guard applySelectedCompletionReplacement(
                candidate: candidate,
                range: range,
                completionResponse: completionResponse
            ) else {
                return false
            }
            let name = candidate.name.flatMap { $0.isEmpty ? nil : $0 } ?? candidate.replacement
            if candidate.state == "completed" {
                announceStatus("Starts a new \(name) session when captured")
            } else {
                announceStatus("\(name) will be created and started when captured")
            }
            requestFocus(.editor)
            return true
        }

        if completionResponse.context == "pomodoro_name"
            || completionResponse.context == "pomodoro_past_name",
            candidate.createsPomodoro
        {
            guard applySelectedCompletionReplacement(
                candidate: candidate,
                range: range,
                completionResponse: completionResponse
            ) else {
                return false
            }
            let name = candidate.name.flatMap { $0.isEmpty ? nil : $0 } ?? candidate.replacement
            announceStatus("\(name) will be created when captured")
            requestFocus(.editor)
            return true
        }

        // A `pomodoro_start_name` name-it row shares the `pomodoro_name`
        // prompt flow and the slug splice: naming the placeholder selects it
        // for the pending named start. A `pomodoro_past_name` name-it row
        // shares the same calm flow; Bob's replacement already preserves
        // `@D`, repair `!`, and the second `=` close selection.
        if completionResponse.context == "pomodoro_name"
            || completionResponse.context == "pomodoro_start_name"
            || completionResponse.context == "pomodoro_past_name",
            candidate.requiresName
        {
            presentPomodoroNamePrompt(
                candidate: candidate,
                draftSnapshot: plainDraft,
                replacementRange: completionResponse.replacement
            )
            return true
        }

        return applySelectedCompletionReplacement(
            candidate: candidate,
            range: range,
            completionResponse: completionResponse
        )
    }

    @discardableResult
    private func applySelectedCompletionReplacement(
        candidate: CaptureCompletionCandidate,
        range: Range<String.Index>,
        completionResponse: CaptureCompletionResponse
    ) -> Bool {
        var text = plainDraft
        text.replaceSubrange(range, with: candidate.replacement)
        let continuation = candidate.recordContinuation
        let itemIndex = recordCompletionSnapshot?.itemIndex
        let cursor = continuation?.cursor
            ?? candidate.cursorAfter
            ?? completionResponse.replacement.start + candidate.replacement.utf8.count
        guard stringRange(in: text, start: cursor, end: cursor) != nil else {
            statusText = "Completion cursor is stale"
            dismissCompletion()
            return false
        }

        retireAliasTipDisplayEligibility()

        // A File-under accept files the link under the chosen route, so the
        // Esc record for the bare URL must not survive the splice (the
        // dismiss below runs while the draft is still bare).
        let wasFileUnder = fileUnderActive
        dismissCompletion()
        if wasFileUnder {
            fileUnderDismissedURL = nil
        }
        if plainDraft != text {
            recordCardDismissedDraft = nil
        }
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(
            text,
            cursorUTF8Offset: cursor,
            suppressSelectionCallbacks: true
        )
        scheduleAnalysis(
            cursorUTF8Offset: cursor,
            requestCompletion: continuation != nil,
            trigger: .edit,
            nextMissingRecordField: continuation?.nextMissingField ?? false,
            recordItemIndex: continuation == nil ? nil : itemIndex
        )
        return true
    }

    func updateTaskIDPromptBlockID(_ blockID: String) {
        guard var prompt = taskIDPrompt, !prompt.isSaving else {
            return
        }
        prompt.authoredID = blockID
        prompt.errorMessage = Self.blockIDValidationMessage(for: blockID)
        taskIDPrompt = prompt
    }

    func cancelTaskIDPrompt(clearCompletion: Bool = false) {
        guard let prompt = taskIDPrompt else {
            return
        }
        let returnPicker: CapturePickerState?
        switch prompt.purpose {
        case .taskLink(_, _, _, _, let pickerSnapshot):
            returnPicker = pickerSnapshot
        case .dependency(_, _, _, _, let pickerSnapshot, _):
            returnPicker = pickerSnapshot
        case .blockedTask(_, _, _, _, let pickerSnapshot):
            returnPicker = pickerSnapshot
        case .relation(_, _, _, _, let pickerSnapshot, _):
            returnPicker = pickerSnapshot
        case .taskComplete(_, _, _, _, let pickerSnapshot):
            returnPicker = pickerSnapshot
        case .wikilinkTask(_, _, _, _, let pickerSnapshot, _, _):
            returnPicker = pickerSnapshot
        case .parentTaskPicker(_, _, _, _, let pickerSnapshot, _):
            returnPicker = pickerSnapshot
        case .projectTaskMove(_, _, _, _, let pickerSnapshot):
            returnPicker = pickerSnapshot
        case .similarTask:
            // No picker to restore: Escape returns to the focused band row.
            returnPicker = nil
        case .parentTask:
            returnPicker = nil
        }
        if let returnPicker {
            if clearCompletion {
                // The draft changed under a link-mode prompt: dismiss the
                // stashed picker and completion instead of restoring a stale
                // picker, matching the `.parentTask` path.
                clearTaskIDPrompt()
                selectedCompletionIndex = prompt.selectedCompletionIndex
                dismissCompletion()
                requestFocus(.editor)
                return
            }
            // Escape returns to the picker with the same filter and selection,
            // without a refetch.
            clearTaskIDPrompt()
            selectedCompletionIndex = prompt.selectedCompletionIndex
            let index: CapturePickerIndex
            switch returnPicker.source {
            case .dependency:
                index = .dependency(DependencyPickerIndex(candidates: returnPicker.candidates))
            case .blockedTask:
                index = .blockedTask(
                    DependencyPickerIndex(candidates: returnPicker.candidates, direction: .blocks)
                )
            case .linksTo:
                index = .linksTo(
                    DependencyPickerIndex(candidates: returnPicker.candidates, direction: .linksTo)
                )
            case .linkedFrom:
                index = .linkedFrom(
                    DependencyPickerIndex(candidates: returnPicker.candidates, direction: .linkedFrom)
                )
            case .taskLink:
                index = .taskLink(TaskLinkPickerIndex(candidates: returnPicker.candidates))
            case .taskGoto:
                index = .taskGoto(
                    TaskLinkPickerIndex(candidates: returnPicker.candidates, mode: .taskGoto)
                )
            case .taskComplete:
                index = .taskComplete(TaskCompletePickerIndex(candidates: returnPicker.candidates))
            case .wikilinkTask(_):
                index = .wikilinkTask(WikilinkTaskPickerIndex(candidates: returnPicker.candidates))
            case .activeTask:
                index = .activeTask(ActiveTaskPickerIndex(candidates: returnPicker.candidates))
            case .blockID:
                index = .taskLink(TaskLinkPickerIndex(candidates: returnPicker.candidates))
            case .parentTask(let context):
                index = .parentTask(
                    ParentTaskPickerIndex(candidates: returnPicker.candidates, context: context)
                )
            case .projectTaskMove(let context):
                index = .projectTaskMove(
                    ProjectTaskMovePickerIndex(candidates: returnPicker.candidates, context: context)
                )
            }
            let presentation = index.presentation(filter: returnPicker.filterText)
            pickerIndex = index
            pickerPresentation = presentation
            picker = returnPicker
            pickerMarkerHighlight = Self.pickerMarkerHighlightRange(
                source: returnPicker.source,
                replacementRange: returnPicker.replacementRange,
                markerRange: Self.blockIDMarkerRange(for: returnPicker.source)
            )
            applyPickerMarkerHighlight()
            dismissCompletion()
            pickerChip = nil
            editorInputLocked = true
            if case .parentTask(let context) = returnPicker.source {
                if context.mergeInTargetTitle != nil {
                    statusText = CapturePickerNeed.mergeInSource.statusText
                } else {
                    statusText = context.isOwnerMode
                        ? CaptureRelationshipCopy.relateStatusText
                        : CapturePickerNeed.taskParent.statusText
                }
            } else if returnPicker.source == .dependency {
                statusText = CapturePickerNeed.dependency.statusText
            } else if returnPicker.source == .blockedTask {
                statusText = CapturePickerNeed.blockedTask.statusText
            } else if returnPicker.source.isRelation {
                statusText = CapturePickerNeed.relationTarget.statusText
            } else if returnPicker.source == .taskComplete {
                statusText = CapturePickerNeed.taskComplete.statusText
            } else if returnPicker.source == .taskGoto {
                statusText = CapturePickerNeed.taskGoto.statusText
            } else if case .projectTaskMove = returnPicker.source {
                statusText = CapturePickerNeed.projectTaskMove.statusText
            } else {
                statusText = "Pick any open task — press Tab to browse"
            }
            requestFocus(.pickerFilter)
            return
        }
        clearTaskIDPrompt()
        selectedCompletionIndex = prompt.selectedCompletionIndex
        if clearCompletion {
            dismissCompletion()
        } else {
            statusText = "Ready"
        }
        requestFocus(.editor)
    }

    func updatePomodoroNamePromptName(_ name: String) {
        guard var prompt = pomodoroNamePrompt, !prompt.isSaving else {
            return
        }
        prompt.authoredName = name
        prompt.errorMessage = Self.pomodoroNameValidationMessage(for: name)
        prompt.suggestions = []
        prompt.suggestionsLoading = true
        prompt.suggestionsUnavailable = false
        pomodoroNamePrompt = prompt
        refreshPomodoroThemeSuggestions(query: name)
    }

    func usePomodoroNameSuggestion(_ theme: CapturePomodoroTheme) {
        updatePomodoroNamePromptName(theme.name)
    }

    private func refreshPomodoroThemeSuggestions(query: String) {
        guard var prompt = pomodoroNamePrompt, !prompt.isSaving else {
            return
        }
        pomodoroThemeSuggestionsTask?.cancel()
        let requestID = UUID()
        activePomodoroThemeSuggestionRequestID = requestID
        prompt.suggestions = []
        prompt.suggestionQuery = query
        prompt.suggestionsLoading = true
        prompt.suggestionsUnavailable = false
        pomodoroNamePrompt = prompt

        guard let processClient else {
            prompt.suggestionsLoading = false
            prompt.suggestionsUnavailable = true
            pomodoroNamePrompt = prompt
            activePomodoroThemeSuggestionRequestID = nil
            return
        }

        let delay = debounceNanoseconds
        let limit = 12
        pomodoroThemeSuggestionsTask = Task { [weak self] in
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else {
                return
            }
            do {
                let response = try await processClient.pomodoroThemes(query: query, limit: limit)
                await MainActor.run {
                    self?.finishPomodoroThemeSuggestions(
                        requestID: requestID,
                        query: query,
                        response: response
                    )
                }
            } catch {
                await MainActor.run {
                    self?.failPomodoroThemeSuggestions(requestID: requestID, query: query)
                }
            }
        }
    }

    private func finishPomodoroThemeSuggestions(
        requestID: UUID,
        query: String,
        response: CapturePomodoroThemesResponse
    ) {
        guard activePomodoroThemeSuggestionRequestID == requestID,
              var prompt = pomodoroNamePrompt,
              prompt.suggestionQuery == query
        else {
            return
        }
        activePomodoroThemeSuggestionRequestID = nil
        pomodoroThemeSuggestionsTask = nil
        prompt.configuredThemes = response.configuredThemes
        if let configured = response.configuredThemes {
            configuredThemes = configured
            prompt.suggestions = CaptureUnconfiguredThemePresentation.nameItSuggestions(
                configuredThemes: configured,
                list: response.themes
            )
        } else {
            configuredThemes = []
            prompt.suggestions = response.themes.filter { !$0.hidden }
        }
        prompt.suggestionsLoading = false
        prompt.suggestionsUnavailable = false
        pomodoroNamePrompt = prompt
    }

    private func failPomodoroThemeSuggestions(requestID: UUID, query: String) {
        guard activePomodoroThemeSuggestionRequestID == requestID,
              var prompt = pomodoroNamePrompt,
              prompt.suggestionQuery == query
        else {
            return
        }
        activePomodoroThemeSuggestionRequestID = nil
        pomodoroThemeSuggestionsTask = nil
        prompt.suggestions = []
        prompt.suggestionsLoading = false
        prompt.suggestionsUnavailable = true
        pomodoroNamePrompt = prompt
    }

    func cancelPomodoroNamePrompt(clearCompletion: Bool = false) {
        guard let prompt = pomodoroNamePrompt else {
            return
        }
        clearPomodoroNamePrompt()
        selectedCompletionIndex = prompt.selectedCompletionIndex
        if clearCompletion {
            dismissCompletion()
        } else {
            statusText = "Ready"
        }
        requestFocus(.editor)
    }

    func submitPomodoroNamePrompt() {
        guard var prompt = pomodoroNamePrompt, !prompt.isSaving else {
            return
        }
        guard let processClient else {
            prompt.errorMessage = "Bob is not resolved. Check Settings and Recheck Bob."
            pomodoroNamePrompt = prompt
            requestFocus(.pomodoroNamePromptName)
            return
        }
        if let validationMessage = Self.pomodoroNameValidationMessage(for: prompt.authoredName) {
            prompt.errorMessage = validationMessage
            pomodoroNamePrompt = prompt
            requestFocus(.pomodoroNamePromptName)
            return
        }
        guard prompt.draftSnapshot == plainDraft else {
            prompt.errorMessage = "Draft changed. Return to the Pomodoro list and choose again."
            pomodoroNamePrompt = prompt
            requestFocus(.pomodoroNamePromptName)
            return
        }
        guard stringRange(in: prompt.draftSnapshot, byteRange: prompt.replacementRange) != nil else {
            prompt.errorMessage = "Completion range is stale. Return to the Pomodoro list and choose again."
            pomodoroNamePrompt = prompt
            requestFocus(.pomodoroNamePromptName)
            return
        }
        guard let pomodoroRef = prompt.candidate.taskRef else {
            prompt.errorMessage = "Pomodoro candidate is missing a ref. Refresh the list and choose again."
            pomodoroNamePrompt = prompt
            requestFocus(.pomodoroNamePromptName)
            return
        }

        let requestID = UUID()
        activePomodoroNameRequestID = requestID
        prompt.isSaving = true
        prompt.errorMessage = nil
        pomodoroNamePrompt = prompt
        statusText = "Naming Pomodoro\u{2026}"
        let name = prompt.authoredName

        Task {
            do {
                let response = try await CaptureSignpost.measure("capture-pomodoro-name") {
                    try await processClient.assignPomodoroName(
                        ref: pomodoroRef,
                        name: name
                    )
                }
                await MainActor.run {
                    self.completePomodoroNameAssignment(requestID: requestID, response: response)
                }
            } catch {
                await MainActor.run {
                    self.failPomodoroNameAssignment(requestID: requestID, error: error)
                }
            }
        }
    }

    // MARK: - Relation label card (`~` / `~~` + `|`)

    var relationLabelPromptVisible: Bool {
        relationLabelPrompt != nil
    }

    private func relationLabelKey(_ label: String) -> String {
        label.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Canonical row key: bob's `key` when the response carries one, else
    /// the locally folded display label.
    private func relationLabelKey(_ candidate: CaptureCompletionCandidate) -> String {
        if let key = candidate.key, !key.isEmpty {
            return key
        }
        return relationLabelKey(candidate.label ?? "")
    }

    func relationLabelSelectionKey(for label: String) -> String {
        relationLabelKey(label)
    }

    func relationLabelSelectionKey(for candidate: CaptureCompletionCandidate) -> String {
        relationLabelKey(candidate)
    }

    /// A hidden row as an insertable candidate. Hidden labels stay usable
    /// and stay hidden, so the card builds the same replacement bob sent.
    private func relationLabelHiddenCandidate(
        _ info: CaptureRelationLabelInfo
    ) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: info.replacement,
            label: info.name,
            count: info.count,
            key: info.key,
            inverse: info.inverse,
            hideReplacement: info.hideReplacement,
            existing: true
        )
    }

    /// Ghost-hide rows a refetched catalog no longer contains, rebuilt from
    /// the prefetched hidden rows so the row stays visible as a ghost.
    private func relationLabelGhostHideCandidates(
        _ prompt: CaptureRelationLabelPromptState,
        query: String
    ) -> [CaptureCompletionCandidate] {
        let catalogKeys = Set(prompt.catalog.map { relationLabelKey($0) })
        return prompt.hiddenRows
            .filter { info in
                prompt.ghosts[info.key] == true && !catalogKeys.contains(info.key)
                    && (query.isEmpty || info.key.contains(query))
            }
            .map { relationLabelHiddenCandidate($0) }
    }

    /// Local Bob-compatible filtering: prefix matches first, then substring
    /// matches, preserving Bob's catalog order within each group.
    /// Hidden labels never appear here; they live in the Hidden section.
    var relationLabelPromptRows: [CaptureCompletionCandidate] {
        guard let prompt = relationLabelPrompt else {
            return []
        }
        let query = relationLabelKey(prompt.authoredLabel)
        let ranked = prompt.catalog.enumerated()
            .filter { entry in
                let candidate = entry.element
                guard candidate.label != nil, !candidate.typed, !candidate.hidden else {
                    return false
                }
                let key = relationLabelKey(candidate)
                return !key.isEmpty && (query.isEmpty || key.contains(query))
            }
            .sorted { left, right in
                let leftKey = relationLabelKey(left.element)
                let rightKey = relationLabelKey(right.element)
                let leftPrefix = query.isEmpty || leftKey.hasPrefix(query)
                let rightPrefix = query.isEmpty || rightKey.hasPrefix(query)
                if leftPrefix != rightPrefix {
                    return leftPrefix
                }
                return left.offset < right.offset
            }
            .map(\.element)
        return ranked + relationLabelGhostHideCandidates(prompt, query: query)
    }

    /// Hidden-section rows, most-used first with prefix matches on top.
    /// Ghost-unhide rows stay here as ghosts until the query changes.
    var relationLabelHiddenPromptRows: [CaptureCompletionCandidate] {
        guard let prompt = relationLabelPrompt, prompt.showHidden else {
            return []
        }
        let query = relationLabelKey(prompt.authoredLabel)
        return prompt.hiddenRows.enumerated()
            .filter { entry in
                // A ghost-hide row lives in the visible list until the query
                // changes, so the Hidden section skips it to avoid a double.
                prompt.ghosts[entry.element.key] != true
                    && (query.isEmpty || entry.element.key.contains(query))
            }
            .sorted { left, right in
                let leftPrefix = query.isEmpty || left.element.key.hasPrefix(query)
                let rightPrefix = query.isEmpty || right.element.key.hasPrefix(query)
                if leftPrefix != rightPrefix {
                    return leftPrefix
                }
                return left.offset < right.offset
            }
            .map { relationLabelHiddenCandidate($0.element) }
    }

    var relationLabelPromptRowEntries: [CaptureRelationLabelRowEntry] {
        relationLabelPromptRows.map {
            CaptureRelationLabelRowEntry(
                id: relationLabelSelectionKey(for: $0),
                candidate: $0
            )
        }
    }

    var relationLabelHiddenPromptRowEntries: [CaptureRelationLabelRowEntry] {
        relationLabelHiddenPromptRows.map {
            CaptureRelationLabelRowEntry(
                id: relationLabelSelectionKey(for: $0),
                candidate: $0
            )
        }
    }

    /// Pending ghost state for a row key: true is an optimistic hide,
    /// false an optimistic unhide, nil is no ghost.
    func relationLabelGhostState(forKey key: String) -> Bool? {
        relationLabelPrompt?.ghosts[key]
    }

    var relationLabelSelectedCandidate: CaptureCompletionCandidate? {
        guard let key = relationLabelPrompt?.selectedKey else {
            return nil
        }
        if let visible = relationLabelPromptRows.first(where: { relationLabelKey($0) == key }) {
            return visible
        }
        return relationLabelHiddenPromptRows.first(where: { relationLabelKey($0) == key })
    }

    var relationLabelDisplayedLabel: String? {
        if let selected = relationLabelSelectedCandidate {
            return selected.label
        }
        guard let prompt = relationLabelPrompt else {
            return nil
        }
        let label = prompt.authoredLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    var relationLabelSentenceSource: String {
        guard let prompt = relationLabelPrompt else { return "This task" }
        let base: String
        if prompt.direction == .linkedFrom {
            base = prompt.targetText.isEmpty ? "That task" : "“\(prompt.targetText)”"
        } else {
            base = prompt.ownerText.isEmpty ? "This task" : "“\(prompt.ownerText)”"
        }
        if relationLabelCompletesSource {
            return "✓ \(base)"
        }
        if relationLabelDimsSource {
            return "⊘ \(base)"
        }
        return base
    }

    /// The selected catalog row, else the fresh typed row, for cancel cues.
    var relationLabelCancelCandidate: CaptureCompletionCandidate? {
        relationLabelSelectedCandidate ?? relationLabelFreshTypedRow
    }

    var relationLabelSourceCandidate: CaptureCompletionCandidate? {
        relationLabelSelectedCandidate ?? relationLabelFreshTypedRow
    }

    var relationLabelSourceEffect: RelationSourceEffect? {
        guard let candidate = relationLabelSourceCandidate else {
            return nil
        }
        if candidate.completesSource {
            return .complete
        }
        if candidate.cancelsSource {
            return .cancel
        }
        return candidate.offersSource ? .offers : nil
    }

    /// Palette role for the live-sentence label pill: the close-effect
    /// tint when the active row carries one, else the mint relation sigil.
    var relationLabelCloseEffectCategory: CaptureSemanticCategory {
        relationLabelSourceEffect?.semanticCategory ?? .relationSigil
    }

    /// The selected catalog row, else the fresh typed row, for complete
    /// cues. One label carries at most one close effect, so at most one of
    /// the cancel and complete cues is ever active.
    var relationLabelCompleteCandidate: CaptureCompletionCandidate? {
        relationLabelSelectedCandidate ?? relationLabelFreshTypedRow
    }

    var relationLabelDimsSource: Bool {
        CaptureRelationCancelPresentation.dimsSource(
            candidate: relationLabelCancelCandidate,
            cancel: relationLabelPrompt?.relationCancel
        )
    }

    /// True when the active complete label dims the live-sentence source
    /// (verdict `completes`).
    var relationLabelCompletesSource: Bool {
        CaptureRelationCompletePresentation.dimsSource(
            candidate: relationLabelCompleteCandidate,
            complete: relationLabelPrompt?.relationComplete
        )
    }

    /// True when either close effect dims the source.
    var relationLabelCloseDimsSource: Bool {
        relationLabelDimsSource || relationLabelCompletesSource
    }

    var relationLabelCancelSlot: CaptureRelationCancelSlot? {
        CaptureRelationCancelPresentation.slot(
            candidate: relationLabelCancelCandidate,
            cancel: relationLabelPrompt?.relationCancel
        )
    }

    var relationLabelCompleteSlot: CaptureRelationCompleteSlot? {
        CaptureRelationCompletePresentation.slot(
            candidate: relationLabelCompleteCandidate,
            complete: relationLabelPrompt?.relationComplete
        )
    }

    /// The relation-effect slot: Bob's successor consequence when selected,
    /// followed by the existing complete/cancel cues and their inverse hints.
    var relationLabelCloseSlot: RelationSourceSlot? {
        let candidate = relationLabelSourceCandidate
        if candidate?.offersSource == true,
            let successor = relationLabelPrompt?.relationSuccessor
        {
            return CaptureRelationCloseEffect.slot(
                effect: .offers,
                appliesToSource: true,
                verdict: successor.verdict,
                message: successor.message,
                hint: successor.hint
            )
        }
        if candidate?.completesSource == true, let complete = relationLabelCompleteSlot {
            return RelationSourceSlot(
                text: complete.text,
                style: complete.style == .completes ? .complete : .muted,
                effect: .complete
            )
        }
        if candidate?.cancelsSource == true, let cancel = relationLabelCancelSlot {
            return RelationSourceSlot(
                text: cancel.text,
                style: cancel.style == .cancels ? .cancel : .muted,
                effect: .cancel
            )
        }
        if let hint = relationLabelPrompt?.relationSuccessor?.hint,
            !hint.isEmpty,
            candidate?.completesSource != true,
            candidate?.cancelsSource != true
        {
            return CaptureRelationCloseEffect.slot(
                effect: nil,
                appliesToSource: false,
                verdict: nil,
                message: nil,
                hint: hint
            )
        }
        if let complete = relationLabelCompleteSlot {
            return RelationSourceSlot(
                text: complete.text,
                style: complete.style == .completes ? .complete : .muted,
                effect: .complete
            )
        }
        if let cancel = relationLabelCancelSlot {
            return RelationSourceSlot(
                text: cancel.text,
                style: cancel.style == .cancels ? .cancel : .muted,
                effect: .cancel
            )
        }
        return nil
    }

    /// VoiceOver for the live sentence. A canceling source reads
    /// "Cancels Sell stocks!" and a completing source reads
    /// "Completes Sell stocks!" instead of the quoted task name.
    var relationLabelSentenceAccessibilityLabel: String {
        let sourceName: String
        if let prompt = relationLabelPrompt {
            if prompt.direction == .linkedFrom {
                sourceName = prompt.targetText
            } else {
                sourceName = prompt.ownerText
            }
        } else {
            sourceName = ""
        }
        let source: String
        if relationLabelCompletesSource {
            source = CaptureRelationCompletePresentation.sourceAccessibilityLabel(
                sourceText: sourceName,
                dimsSource: true
            )
        } else {
            source = CaptureRelationCancelPresentation.sourceAccessibilityLabel(
                sourceText: sourceName,
                dimsSource: relationLabelDimsSource
            )
        }
        let sentence = relationLabelSentence
        if relationLabelSourceEffect == .offers {
            return "Relation sentence: \(sentence). Offers source"
        }
        if relationLabelCloseDimsSource, !source.isEmpty {
            return "Relation sentence: \(source). \(sentence)"
        }
        return "Relation sentence: \(sentence)"
    }

    var relationLabelSentenceTarget: String {
        guard let prompt = relationLabelPrompt else { return "that task" }
        if prompt.direction == .linkedFrom {
            return prompt.ownerText.isEmpty ? "this task" : "“\(prompt.ownerText)”"
        }
        return prompt.targetText.isEmpty ? "that task" : "“\(prompt.targetText)”"
    }

    /// Live sentence for the card. Highlighted selection previews in the
    /// label pill without changing the query field.
    var relationLabelSentence: String {
        let source = relationLabelSentenceSource
        let target = relationLabelSentenceTarget
        guard let label = relationLabelDisplayedLabel else {
            return "\(source) → \(target)"
        }
        return "\(source) — \(label) → \(target)"
    }

    var relationLabelPromptHint: String? {
        guard let prompt = relationLabelPrompt else { return nil }
        if let error = prompt.catalogErrorMessage {
            return error
        }
        if !prompt.catalogLoaded {
            return "Loading relation labels…"
        }
        if !relationLabelKey(prompt.authoredLabel).isEmpty && relationLabelPromptRows.isEmpty {
            return "No matching labels · type a relation name"
        }
        if relationLabelPromptRows.isEmpty {
            return "No saved labels · type a relation name"
        }
        return nil
    }

    /// The typed row Bob validated for the current field, if fresh.
    private var relationLabelFreshTypedRow: CaptureCompletionCandidate? {
        guard let prompt = relationLabelPrompt,
              prompt.suggestionAuthoredLabel == prompt.authoredLabel
        else {
            return nil
        }
        return prompt.suggestions.first(where: { $0.typed })
    }

    /// Whether a key is hidden in the vault (prefetched hidden rows).
    private func relationLabelIsHiddenKey(_ key: String, in prompt: CaptureRelationLabelPromptState) -> Bool {
        prompt.hiddenRows.contains { $0.key == key }
    }

    /// The field's trailing capsule: `new`, `N links`, `hidden`,
    /// `one-off · …`, or the red `invalid` reason.
    var relationLabelPromptBadgeText: String? {
        guard let prompt = relationLabelPrompt else { return nil }
        if let typed = relationLabelFreshTypedRow,
           let reason = typed.disabledReason, !reason.isEmpty,
           !typed.cancelsSource, !typed.completesSource
        {
            return "invalid"
        }
        if let selected = relationLabelSelectedCandidate {
            let key = relationLabelKey(selected)
            let hidden =
                selected.hidden || relationLabelIsHiddenKey(key, in: prompt)
                || prompt.ghosts[key] == true
            let base: String
            if hidden {
                base = "hidden"
            } else if let count = selected.count, count > 0 {
                base = count == 1 ? "1 link" : "\(count) links"
            } else {
                base = "new"
            }
            return prompt.oneOff ? "one-off · \(base)" : base
        }
        let query = relationLabelKey(prompt.authoredLabel)
        guard !query.isEmpty, prompt.catalogLoaded else { return nil }
        if let typed = relationLabelFreshTypedRow {
            let base: String
            if typed.hidden == true {
                base = "hidden"
            } else if typed.existing == true, let count = typed.count, count > 0 {
                base = count == 1 ? "1 link" : "\(count) links"
            } else {
                base = "new"
            }
            return prompt.oneOff ? "one-off · \(base)" : base
        }
        if let existing = prompt.catalog.first(where: { relationLabelKey($0) == query }),
           let count = existing.count, count > 0
        {
            let countText = count == 1 ? "1 link" : "\(count) links"
            return prompt.oneOff ? "one-off · \(countText)" : countText
        }
        return prompt.oneOff ? "one-off · new" : "new"
    }

    /// Amber one-off warning (state D): one-off is on and the typed label
    /// names an existing visible label, so capturing hides it everywhere.
    /// Nil for new labels, hidden labels, and invalid labels.
    var relationLabelOneOffWarning: String? {
        guard let prompt = relationLabelPrompt, prompt.oneOff,
              let typed = relationLabelFreshTypedRow,
              typed.disabledReason?.isEmpty != false,
              typed.existing == true,
              typed.hidden != true,
              let count = typed.count, count > 0,
              let label = typed.label
        else {
            return nil
        }
        return
            "Capturing will also hide “\(label)” (\(count) links) from suggestions everywhere. Existing links keep their label."
    }

    /// Neutral note when one-off targets an already-hidden label: the
    /// capture keeps it hidden and writes no hide event.
    var relationLabelAlreadyHiddenNote: String? {
        guard let prompt = relationLabelPrompt, prompt.oneOff,
              let typed = relationLabelFreshTypedRow,
              typed.disabledReason?.isEmpty != false,
              typed.hidden == true
        else {
            return nil
        }
        return "Already hidden — capturing keeps it hidden."
    }

    /// `Inserts <replacement>` line for the card, from Bob's typed row.
    /// Shown only when the typed row was produced for the current input;
    /// a stale row must never advertise a commit it cannot make (bob-cli-al).
    var relationLabelInsertsText: String? {
        guard let prompt = relationLabelPrompt else { return nil }
        if let selected = relationLabelSelectedCandidate {
            guard selected.disabledReason?.isEmpty != false else { return nil }
            let replacement = relationLabelInsertion(for: selected, oneOff: prompt.oneOff)
            guard !replacement.isEmpty else { return nil }
            return "Inserts \(replacement)"
        }
        guard prompt.suggestionAuthoredLabel == prompt.authoredLabel else { return nil }
        let trimmed = prompt.authoredLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let typed = prompt.suggestions.first(where: { $0.typed }),
              typed.disabledReason?.isEmpty != false
        else { return nil }
        let replacement = relationLabelInsertion(for: typed, oneOff: prompt.oneOff)
        guard !replacement.isEmpty else { return nil }
        return "Inserts \(replacement)"
    }

    var relationLabelPromptCanSubmit: Bool {
        guard let prompt = relationLabelPrompt, !prompt.isSaving else {
            return false
        }
        if prompt.rename != nil {
            return !prompt.rename!.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let selected = relationLabelSelectedCandidate {
            return !selected.replacement.isEmpty && selected.disabledReason?.isEmpty != false
        }
        let trimmed = prompt.authoredLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        guard prompt.suggestionAuthoredLabel == prompt.authoredLabel,
              let typed = prompt.suggestions.first(where: { $0.typed })
        else {
            return true
        }
        if let reason = typed.disabledReason, !reason.isEmpty {
            return false
        }
        return !typed.replacement.isEmpty
    }

    /// Control-Return on a relation picker row: insert the token like Return,
    /// then open the label card for the inserted token.
    func openRelationLabelPromptFromPickerRow(id: String) {
        guard let picker, let presentation = pickerPresentation,
              plainDraft == picker.draftSnapshot,
              picker.source.isRelation,
              let row = presentation.row(id: id)
        else {
            return
        }
        let direction: DependencyPickerDirection =
            picker.source == .linkedFrom ? .linkedFrom : .linksTo
        if row.insertion == nil, let pending = row.pendingBlockID {
            presentRelationIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: .none
            )
            return
        }
        guard let insertion = row.insertion else {
            return
        }
        guard let range = stringRange(in: plainDraft, byteRange: picker.replacementRange) else {
            return
        }
        var text = plainDraft
        let insertionText: String
        if picker.replacementRange.end >= plainDraft.utf8.count {
            insertionText = insertion.hasSuffix(" ") ? insertion : insertion + " "
        } else {
            insertionText = insertion
        }
        text.replaceSubrange(range, with: insertionText)
        let tokenEnd = picker.replacementRange.start + insertionText.trimmingCharacters(in: .whitespaces).utf8.count
        let caret = picker.replacementRange.start + insertionText.utf8.count
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            return
        }
        let ownerText = picker.dependencyOwner?.text ?? ""
        let targetText = row.displayText
        let tokenRange = CaptureRange(start: picker.replacementRange.start, end: tokenEnd)
        let labelRange = CaptureRange(start: tokenEnd, end: caret)
        let returnPicker = picker
        closePickerForAccept()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: false, trigger: .edit)
        rememberRelationshipDisplayName(replacement: insertion, text: row.displayText)
        openRelationLabelPrompt(
            draftSnapshot: text,
            tokenRange: tokenRange,
            labelRange: labelRange,
            direction: direction,
            ownerText: ownerText,
            targetText: targetText,
            restoreCursor: caret,
            returnPicker: returnPicker
        )
    }

    private func openRelationLabelPrompt(
        draftSnapshot: String,
        tokenRange: CaptureRange,
        labelRange: CaptureRange,
        direction: DependencyPickerDirection,
        ownerText: String,
        targetText: String,
        restoreCursor: Int,
        returnPicker: CapturePickerState?
    ) {
        clearTaskIDPrompt()
        clearPomodoroNamePrompt()
        invalidateAnalysis()
        relationLabelPrompt = CaptureRelationLabelPromptState(
            draftSnapshot: draftSnapshot,
            tokenRange: tokenRange,
            labelRange: labelRange,
            direction: direction,
            ownerText: ownerText,
            targetText: targetText,
            restoreCursor: restoreCursor,
            returnPicker: returnPicker,
            authoredLabel: "",
            suggestions: [],
            catalog: [],
            catalogLoaded: false,
            catalogErrorMessage: nil,
            suggestionAuthoredLabel: nil,
            pendingSubmit: false,
            selectedKey: nil,
            showHidden: false,
            oneOff: false,
            hiddenRows: [],
            hiddenCount: 0,
            hiddenCountKnown: false,
            hiddenRowsLoaded: false,
            ghosts: [:],
            noticeMessage: nil,
            visibilityWriteID: nil,
            rename: nil,
            isSaving: false,
            errorMessage: nil,
            relationCancel: nil,
            relationComplete: nil,
            relationSuccessor: nil
        )
        statusText = "Link with a relation"
        requestFocus(.relationLabelPromptField)
        editorInputLocked = true
        fetchRelationLabelCatalog()
    }

    func updateRelationLabelPromptLabel(_ label: String) {
        guard var prompt = relationLabelPrompt, !prompt.isSaving, prompt.rename == nil else {
            return
        }
        clearEqualsGestureArm()
        // A typed `|` never enters the field: it turns one-off on, so
        // `~note:id |label` typed straight through still works.
        if label.contains("|") {
            prompt.oneOff = true
        }
        prompt.authoredLabel = label.replacingOccurrences(of: "|", with: "")
        prompt.selectedKey = nil
        // Ghosts belong to the previous query; a new query clears them.
        prompt.ghosts = [:]
        // The catalog remains visible and is filtered locally. Only the typed
        // row is invalidated while Bob validates the new field text (bob-cli-al).
        prompt.suggestionAuthoredLabel = nil
        prompt.relationSuccessor = nil
        prompt.pendingSubmit = false
        prompt.errorMessage = nil
        prompt.noticeMessage = nil
        relationLabelPrompt = prompt
        fetchRelationLabelSuggestions()
    }

    /// Ctrl+D with no selection toggles one-off for the typed label.
    /// Ctrl+D is always consumed; key auto-repeat is ignored by the router.
    func toggleRelationLabelOneOff() {
        clearEqualsGestureArm()
        guard var prompt = relationLabelPrompt, !prompt.isSaving, prompt.rename == nil else {
            return
        }
        if prompt.selectedKey != nil {
            return
        }
        if prompt.authoredLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt.noticeMessage = "Type a label to make it one-off"
            relationLabelPrompt = prompt
            return
        }
        prompt.oneOff.toggle()
        prompt.noticeMessage = nil
        relationLabelPrompt = prompt
    }

    /// Ctrl+D on a row hides what Return would insert, or unhides a
    /// hidden row. The row stays as a ghost and Ctrl+D on the ghost flips
    /// it back. The write runs in the background: it is optimistic, a
    /// failure restores the row with bob's message, and a pending write
    /// survives dismissal. With no selection, Ctrl+D toggles one-off.
    func toggleRelationLabelVisibility() {
        clearEqualsGestureArm()
        guard let prompt = relationLabelPrompt, !prompt.isSaving, prompt.rename == nil else {
            return
        }
        guard let selected = relationLabelSelectedCandidate else {
            toggleRelationLabelOneOff()
            return
        }
        guard prompt.hiddenCountKnown else {
            var notice = prompt
            notice.noticeMessage = "Update bob to hide relation labels"
            relationLabelPrompt = notice
            return
        }
        let key = relationLabelKey(selected)
        let label = selected.label ?? key
        let actualHidden = prompt.hiddenRows.contains { $0.key == key }
        let effectiveHidden = prompt.ghosts[key] ?? actualHidden
        let targetHidden = !effectiveHidden
        guard let processClient else {
            var waiting = prompt
            waiting.ghosts.removeValue(forKey: key)
            waiting.errorMessage = "Bob is not resolved. Check Settings and Recheck Bob."
            relationLabelPrompt = waiting
            return
        }
        var optimistic = prompt
        optimistic.ghosts[key] = targetHidden
        optimistic.errorMessage = nil
        optimistic.noticeMessage = nil
        let requestID = UUID()
        optimistic.visibilityWriteID = requestID
        relationLabelPrompt = optimistic
        statusText = targetHidden ? "Hiding \(label)…" : "Restoring \(label)…"
        Task { [weak self, processClient] in
            do {
                try await processClient.setRelationLabelHidden(label, hidden: targetHidden)
                await MainActor.run {
                    guard let self,
                          self.relationLabelPrompt?.visibilityWriteID == requestID
                    else {
                        return
                    }
                    self.relationLabelPrompt?.visibilityWriteID = nil
                    self.statusText =
                        targetHidden
                        ? "Hid “\(label)” from relation suggestions"
                        : "Restored “\(label)” to relation suggestions"
                    // The ghost stays until the query changes; the refetch
                    // moves the row to its new section underneath it.
                    // The hidden-rows prefetch runs once per open, so reset
                    // its gate to pick up the new hidden state now.
                    self.relationLabelPrompt?.hiddenRowsLoaded = false
                    self.fetchRelationLabelCatalog()
                    self.fetchRelationLabelHiddenRows()
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          self.relationLabelPrompt?.visibilityWriteID == requestID
                    else {
                        return
                    }
                    self.relationLabelPrompt?.visibilityWriteID = nil
                    self.relationLabelPrompt?.ghosts.removeValue(forKey: key)
                    if let clientError = error as? BobClientError,
                       case .processFailed(_, _, let stderr) = clientError,
                       stderr.localizedCaseInsensitiveContains("unrecognized subcommand")
                    {
                        self.relationLabelPrompt?.errorMessage =
                            "Update bob to hide relation labels"
                    } else {
                        self.relationLabelPrompt?.errorMessage =
                            "Could not update “\(label)”: \(error.localizedDescription)"
                    }
                    self.statusText = "Relation label update failed"
                }
            }
        }
    }

    /// Ctrl+H shows or hides the Hidden section. The query and the
    /// selection are kept. An older bob gets the update hint.
    func toggleRelationLabelHiddenSection() {
        clearEqualsGestureArm()
        guard var prompt = relationLabelPrompt, !prompt.isSaving, prompt.rename == nil else {
            return
        }
        guard prompt.hiddenCountKnown else {
            prompt.noticeMessage = "Update bob to hide relation labels"
            relationLabelPrompt = prompt
            return
        }
        prompt.showHidden.toggle()
        prompt.noticeMessage = nil
        relationLabelPrompt = prompt
        if prompt.showHidden {
            fetchRelationLabelHiddenRows()
        }
    }

    /// Prefetch the hidden rows once the probe reports `hidden_count` > 0.
    /// A failure stays silent: the card simply shows no Hidden pill.
    private func fetchRelationLabelHiddenRows() {
        guard let prompt = relationLabelPrompt,
              let processClient,
              prompt.draftSnapshot == plainDraft,
              prompt.hiddenCount > 0,
              !prompt.hiddenRowsLoaded
        else {
            return
        }
        let draftSnapshot = prompt.draftSnapshot
        Task { [weak self, processClient] in
            do {
                let response = try await processClient.relationLabels(hiddenOnly: true)
                await MainActor.run {
                    guard let self,
                          var current = self.relationLabelPrompt,
                          current.draftSnapshot == draftSnapshot,
                          current.draftSnapshot == self.plainDraft
                    else {
                        return
                    }
                    current.hiddenRows = response.labels
                    current.hiddenRowsLoaded = true
                    self.relationLabelPrompt = current
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          var current = self.relationLabelPrompt,
                          current.draftSnapshot == draftSnapshot
                    else {
                        return
                    }
                    // An older bob has no `relations` group; the card keeps
                    // working without a Hidden section.
                    current.hiddenRowsLoaded = true
                    self.relationLabelPrompt = current
                }
            }
        }
    }

    /// Backspace on an empty field turns one-off off. Returns true when it
    /// consumed the key; otherwise the field edits normally.
    @discardableResult
    func relationLabelPromptBackspace() -> Bool {
        guard var prompt = relationLabelPrompt, !prompt.isSaving, prompt.rename == nil else {
            return false
        }
        guard prompt.authoredLabel.isEmpty, prompt.oneOff else {
            return false
        }
        prompt.oneOff = false
        prompt.noticeMessage = nil
        relationLabelPrompt = prompt
        return true
    }

    /// Whether the card is in Ctrl+R rename mode (the choose query,
    /// selection, and Hidden section wait underneath).
    var relationLabelRenameIsActive: Bool {
        relationLabelPrompt?.rename != nil
    }

    /// The rename field text in rename mode, else the choose query.
    /// The view binds the card field to this.
    var relationLabelFieldText: String {
        relationLabelPrompt?.rename?.newName ?? relationLabelPrompt?.authoredLabel ?? ""
    }

    /// Consume the one-shot select-all request the rename field raises when
    /// rename mode opens with OLD prefilled. The view calls this from
    /// `updateNSView` so a late focus claim cannot reselect after typing.
    func consumeRelationLabelRenameSelectAll() -> Bool {
        guard var prompt = relationLabelPrompt,
              var rename = prompt.rename,
              rename.selectAllOnFocus
        else {
            return false
        }
        rename.selectAllOnFocus = false
        prompt.rename = rename
        relationLabelPrompt = prompt
        return true
    }

    /// Ctrl+R opens rename mode for the selected row, or for the typed
    /// label when it names an existing key. Otherwise hint and stay in
    /// choose mode. The preview doubles as the capability probe: an older
    /// bob gets the update hint instead of a preview.
    func openRelationLabelRename() {
        clearEqualsGestureArm()
        guard var prompt = relationLabelPrompt, !prompt.isSaving, prompt.rename == nil else {
            return
        }
        guard processClient != nil else {
            prompt.errorMessage = "Bob is not resolved. Check Settings and Recheck Bob."
            relationLabelPrompt = prompt
            return
        }
        let oldKey: String
        let oldName: String
        if let selected = relationLabelSelectedCandidate {
            oldKey = relationLabelKey(selected)
            oldName = selected.label ?? oldKey
        } else {
            let query = relationLabelKey(prompt.authoredLabel)
            guard !query.isEmpty else {
                prompt.noticeMessage = "Select a label to rename"
                relationLabelPrompt = prompt
                return
            }
            if let match = prompt.catalog.first(where: { relationLabelKey($0) == query }) {
                oldKey = relationLabelKey(match)
                oldName = match.label ?? oldKey
            } else if let typed = relationLabelFreshTypedRow,
                      relationLabelKey(typed) == query,
                      typed.existing == true,
                      let label = typed.label
            {
                oldKey = query
                oldName = label
            } else {
                prompt.noticeMessage = "Select a label to rename"
                relationLabelPrompt = prompt
                return
            }
        }
        prompt.rename = CaptureRelationRenameState(
            oldKey: oldKey,
            oldName: oldName,
            newName: oldName,
            preview: nil,
            previewNewName: nil,
            previewMerge: false,
            refusalCode: nil,
            refusalMessage: nil,
            mergeArmed: false,
            pendingApply: false,
            isApplying: false,
            selectAllOnFocus: true
        )
        prompt.errorMessage = nil
        prompt.noticeMessage = nil
        relationLabelPrompt = prompt
        statusText = "Rename a relation label everywhere"
        requestFocus(.relationLabelPromptField)
        scheduleRelationLabelRenamePreview()
    }

    /// Rename field edit: disarm any merge confirm, drop the stale
    /// preview, and re-debounce the dry run.
    func updateRelationLabelRenameName(_ name: String) {
        guard var prompt = relationLabelPrompt, !prompt.isSaving, var rename = prompt.rename else {
            return
        }
        rename.newName = name
        rename.mergeArmed = false
        rename.pendingApply = false
        rename.preview = nil
        rename.previewNewName = nil
        rename.refusalCode = nil
        rename.refusalMessage = nil
        prompt.rename = rename
        prompt.errorMessage = nil
        relationLabelPrompt = prompt
        scheduleRelationLabelRenamePreview()
    }

    /// Escape in rename mode returns to choose mode; the query, selection,
    /// and Hidden section are kept. Returns true when it exited rename mode.
    @discardableResult
    func cancelRelationLabelRename() -> Bool {
        guard var prompt = relationLabelPrompt, prompt.rename != nil, !prompt.isSaving else {
            return false
        }
        prompt.rename = nil
        prompt.errorMessage = nil
        prompt.noticeMessage = nil
        relationLabelPrompt = prompt
        relationLabelRenameGeneration &+= 1
        relationLabelRenameInFlight = nil
        statusText = "Link with a relation"
        requestFocus(.relationLabelPromptField)
        return true
    }

    /// Debounced live dry run (150 ms): a cancellable preview per rename
    /// field value on the `relation-rename-preview` lane. A generation bump
    /// from typing, arming, or exiting drops the stale reply.
    private func scheduleRelationLabelRenamePreview() {
        guard let prompt = relationLabelPrompt,
              let rename = prompt.rename,
              !rename.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        relationLabelRenameGeneration &+= 1
        let generation = relationLabelRenameGeneration
        let draftSnapshot = prompt.draftSnapshot
        let oldName = rename.oldName
        let newName = rename.newName
        let merge = rename.mergeArmed
        relationLabelRenameInFlight = (
            generation: generation, draft: draftSnapshot, oldKey: rename.oldKey,
            newName: newName, merge: merge
        )
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await self?.fetchRelationLabelRenamePreview(
                generation: generation,
                draftSnapshot: draftSnapshot,
                oldName: oldName,
                oldKey: rename.oldKey,
                newName: newName,
                merge: merge
            )
        }
    }

    private func fetchRelationLabelRenamePreview(
        generation: UInt64,
        draftSnapshot: String,
        oldName: String,
        oldKey: String,
        newName: String,
        merge: Bool
    ) async {
        guard let processClient else {
            await MainActor.run {
                guard var current = self.relationLabelPrompt,
                      var rename = current.rename,
                      self.relationLabelRenameGeneration == generation,
                      current.draftSnapshot == draftSnapshot,
                      rename.oldKey == oldKey,
                      rename.newName == newName,
                      rename.mergeArmed == merge
                else {
                    return
                }
                rename.pendingApply = false
                current.rename = rename
                current.errorMessage = "Bob is not resolved. Check Settings and Recheck Bob."
                self.relationLabelPrompt = current
            }
            return
        }
        do {
            let result = try await processClient.renameRelationLabel(
                oldName: oldName,
                newName: newName,
                dryRun: true,
                merge: merge
            )
            await MainActor.run {
                self.applyRelationLabelRenamePreview(
                    result,
                    generation: generation,
                    draftSnapshot: draftSnapshot,
                    oldKey: oldKey,
                    newName: newName,
                    merge: merge
                )
            }
        } catch {
            await MainActor.run {
                guard var current = self.relationLabelPrompt,
                      var rename = current.rename,
                      self.relationLabelRenameGeneration == generation,
                      current.draftSnapshot == draftSnapshot,
                      rename.oldKey == oldKey,
                      rename.newName == newName,
                      rename.mergeArmed == merge
                else {
                    return
                }
                self.clearRelationLabelRenameInFlight(generation: generation)
                rename.pendingApply = false
                if let clientError = error as? BobClientError,
                   case .unsupportedCommand = clientError
                {
                    rename.preview = nil
                    rename.previewNewName = nil
                    current.errorMessage = nil
                    current.noticeMessage = "Update bob to rename relation labels"
                } else if error is CancellationError {
                    current.rename = rename
                    self.relationLabelPrompt = current
                    return
                } else {
                    current.errorMessage = "Could not preview the rename: \(error.localizedDescription)"
                }
                current.rename = rename
                self.relationLabelPrompt = current
            }
        }
    }

    private func clearRelationLabelRenameInFlight(generation: UInt64) {
        if relationLabelRenameInFlight?.generation == generation {
            relationLabelRenameInFlight = nil
        }
    }

    /// Store one dry-run answer when it still covers the current rename
    /// field value, then replay a Return that arrived before it.
    private func applyRelationLabelRenamePreview(
        _ result: RelationRenameResult,
        generation: UInt64,
        draftSnapshot: String,
        oldKey: String,
        newName: String,
        merge: Bool
    ) {
        guard relationLabelRenameGeneration == generation,
              var current = relationLabelPrompt,
              var rename = current.rename,
              current.draftSnapshot == draftSnapshot,
              rename.oldKey == oldKey,
              rename.newName == newName,
              rename.mergeArmed == merge
        else {
            return
        }
        clearRelationLabelRenameInFlight(generation: generation)
        switch result {
        case .renamed(let preview):
            rename.preview = preview
            rename.previewNewName = newName
            rename.previewMerge = merge
            rename.refusalCode = nil
            rename.refusalMessage = nil
            current.errorMessage = nil
        case .refused(let code, let message):
            rename.preview = nil
            rename.previewNewName = nil
            rename.refusalCode = code
            rename.refusalMessage = message
            current.errorMessage = message
        }
        current.rename = rename
        relationLabelPrompt = current
        // Replay a Return that arrived before this preview — but only on
        // a success preview. Replaying on a refusal would refetch forever;
        // the inline refusal is the answer there.
        if rename.pendingApply, case .renamed = result {
            if var pending = relationLabelPrompt, var pendingRename = pending.rename {
                pendingRename.pendingApply = false
                pending.rename = pendingRename
                relationLabelPrompt = pending
            }
            submitRelationLabelRename()
        }
    }

    /// Return in rename mode: apply on a fresh preview, arm the merge
    /// confirm on a `label_exists` refusal, or wait for the fresh preview
    /// and replay.
    func submitRelationLabelRename() {
        guard var prompt = relationLabelPrompt,
              var rename = prompt.rename,
              !prompt.isSaving,
              !rename.isApplying
        else {
            return
        }
        guard prompt.draftSnapshot == plainDraft else {
            prompt.errorMessage = "Draft changed. Reopen the relation card and try again."
            relationLabelPrompt = prompt
            return
        }
        let trimmed = rename.newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            prompt.noticeMessage = "Type a new name for “\(rename.oldName)”"
            relationLabelPrompt = prompt
            return
        }
        if rename.previewNewName == rename.newName,
           rename.previewMerge == rename.mergeArmed,
           rename.preview != nil
        {
            applyRelationLabelRename(merge: rename.mergeArmed)
            return
        }
        if rename.refusalCode == "label_exists", !rename.mergeArmed {
            rename.mergeArmed = true
            rename.refusalCode = nil
            rename.refusalMessage = nil
            prompt.errorMessage = nil
            prompt.rename = rename
            relationLabelPrompt = prompt
            statusText = "Confirm the merge into “\(trimmed)”"
            scheduleRelationLabelRenamePreview()
            return
        }
        rename.pendingApply = true
        prompt.rename = rename
        relationLabelPrompt = prompt
        scheduleRelationLabelRenamePreview()
    }

    /// Apply the rename on the serial `relation-label-pref` lane (a hide
    /// survives dismissal, and so does a rename) with a 60 s timeout
    /// behind the `Renaming… syncing vault` progress state.
    private func applyRelationLabelRename(merge: Bool) {
        guard var prompt = relationLabelPrompt,
              var rename = prompt.rename,
              let processClient,
              !prompt.isSaving,
              !rename.isApplying,
              prompt.draftSnapshot == plainDraft
        else {
            return
        }
        rename.isApplying = true
        rename.pendingApply = false
        prompt.rename = rename
        prompt.isSaving = true
        prompt.errorMessage = nil
        relationLabelPrompt = prompt
        statusText = "Renaming… syncing vault"
        let draftSnapshot = prompt.draftSnapshot
        let oldName = rename.oldName
        let oldKey = rename.oldKey
        let newName = rename.newName
        Task { [weak self, processClient] in
            do {
                let result = try await processClient.renameRelationLabel(
                    oldName: oldName,
                    newName: newName,
                    dryRun: false,
                    merge: merge,
                    lane: "relation-label-pref",
                    cancelsPreviousInLane: false,
                    timeout: 60
                )
                await MainActor.run {
                    self?.finishRelationLabelRename(
                        result,
                        draftSnapshot: draftSnapshot,
                        oldKey: oldKey,
                        newName: newName
                    )
                }
            } catch {
                await MainActor.run {
                    self?.failRelationLabelRename(error, draftSnapshot: draftSnapshot)
                }
            }
        }
    }

    private func failRelationLabelRename(_ error: Error, draftSnapshot: String) {
        guard var current = relationLabelPrompt,
              var rename = current.rename,
              current.draftSnapshot == draftSnapshot
        else {
            return
        }
        rename.isApplying = false
        current.rename = rename
        current.isSaving = false
        if let clientError = error as? BobClientError,
           case .unsupportedCommand = clientError
        {
            current.errorMessage = nil
            current.noticeMessage = "Update bob to rename relation labels"
        } else {
            current.errorMessage = "Could not rename: \(error.localizedDescription)"
        }
        statusText = "Relation label rename failed"
        relationLabelPrompt = current
        requestFocus(.relationLabelPromptField)
    }

    /// Apply success: fix up the draft from bob's ranges and replacements,
    /// leave rename mode with NEW selected, refetch the catalog, and report
    /// the one commit (plus `· sync pending` when the post-sync failed).
    private func finishRelationLabelRename(
        _ result: RelationRenameResult,
        draftSnapshot: String,
        oldKey: String,
        newName: String
    ) {
        guard var current = relationLabelPrompt,
              let rename = current.rename,
              current.draftSnapshot == draftSnapshot,
              current.draftSnapshot == plainDraft
        else {
            return
        }
        switch result {
        case .refused(let code, let message):
            var failed = current
            var failedRename = rename
            failedRename.isApplying = false
            failedRename.mergeArmed = false
            failedRename.refusalCode = code
            failedRename.refusalMessage = message
            failed.rename = failedRename
            failed.isSaving = false
            failed.errorMessage = message
            statusText = "Relation label rename failed"
            relationLabelPrompt = failed
            requestFocus(.relationLabelPromptField)
            return
        case .renamed(let preview):
            guard preview.mode == "write" else {
                var failed = current
                var failedRename = rename
                failedRename.isApplying = false
                failed.rename = failedRename
                failed.isSaving = false
                failed.errorMessage = "Bob answered the rename without writing. Try again."
                statusText = "Relation label rename failed"
                relationLabelPrompt = failed
                requestFocus(.relationLabelPromptField)
                return
            }
            // The draft fix-up needs bob's own `label_range`s, so parse
            // the unchanged draft before leaving rename mode. A parse
            // failure still reports the successful rename; the draft
            // simply keeps its OLD labels with a notice.
            guard let processClient else {
                var failed = current
                var failedRename = rename
                failedRename.isApplying = false
                failed.rename = failedRename
                failed.isSaving = false
                failed.errorMessage = "Bob is not resolved. Check Settings and Recheck Bob."
                statusText = "Relation label rename failed"
                relationLabelPrompt = failed
                return
            }
            statusText = "Renaming… updating draft"
            let oldName = rename.oldName
            Task { [weak self, processClient] in
                let markers: [CaptureParseRelationshipMarker]?
                do {
                    let parse = try await processClient.captureParse(draftSnapshot)
                    markers = parse.relations
                } catch {
                    markers = nil
                }
                await MainActor.run {
                    self?.completeRelationLabelRename(
                        preview: preview,
                        draftSnapshot: draftSnapshot,
                        oldKey: oldKey,
                        oldName: oldName,
                        newName: newName,
                        markers: markers
                    )
                }
            }
        }
    }

    /// Apply-success landing: splice bob's replacements into the draft,
    /// leave rename mode with NEW selected, refetch the catalog, and
    /// report the one commit (plus `· sync pending` when post-sync failed).
    private func completeRelationLabelRename(
        preview: CaptureRelationRenameResponse,
        draftSnapshot: String,
        oldKey: String,
        oldName: String,
        newName: String,
        markers: [CaptureParseRelationshipMarker]?
    ) {
        guard var finished = relationLabelPrompt,
              finished.draftSnapshot == draftSnapshot,
              finished.draftSnapshot == plainDraft
        else {
            return
        }
        let newKey = preview.toKey.isEmpty ? relationLabelKey(newName) : preview.toKey
        let newDisplayName = preview.toName.isEmpty ? newName : preview.toName
        let fixed = relationLabelRenameDraftFixUp(
            oldKey: oldKey,
            replacement: preview.replacement,
            hideReplacement: preview.hideReplacement,
            markers: markers ?? [],
            draft: draftSnapshot,
            ownLabelRange: finished.labelRange
        )
        let parseFailed = markers == nil
        finished.rename = nil
        finished.isSaving = false
        finished.errorMessage = nil
        finished.noticeMessage =
            parseFailed
            ? "Renamed everywhere, but the draft kept “\(oldName)” (parse failed)"
            : nil
        finished.selectedKey = newKey
        finished.authoredLabel = newDisplayName
        finished.hiddenRowsLoaded = false
        if let fixed, fixed.text != draftSnapshot {
            finished.draftSnapshot = fixed.text
            finished.labelRange = fixed.labelRange
            if stringRange(in: fixed.text, start: finished.restoreCursor, end: finished.restoreCursor)
                == nil
            {
                finished.restoreCursor = fixed.text.utf8.count
            }
            suppressedCompletionAcceptanceDraft = fixed.text
            setPlainDraft(
                fixed.text,
                cursorUTF8Offset: finished.restoreCursor,
                suppressSelectionCallbacks: true
            )
            scheduleAnalysis(
                cursorUTF8Offset: finished.restoreCursor,
                requestCompletion: false,
                trigger: .edit
            )
        }
        relationLabelPrompt = finished
        statusText =
            "Renamed “\(oldName)” → “\(newDisplayName)” · \(preview.links) links in \(preview.notes) notes · 1 commit"
            + (preview.syncPost == "failed" ? " · sync pending" : "")
        fetchRelationLabelCatalog()
        fetchRelationLabelHiddenRows()
        requestFocus(.relationLabelPromptField)
    }

    /// Rewrite every draft relation whose label key was OLD, splicing
    /// bob's label text (the `replacement` / `hide_replacement` with the
    /// leading pipes stripped, so quoting stays bob's) into each
    /// `label_range`. Splices run from the end so earlier byte offsets stay
    /// valid, and the card's own suffix range is carried along by the same
    /// shifts. Returns nil when nothing matched.
    private func relationLabelRenameDraftFixUp(
        oldKey: String,
        replacement: String,
        hideReplacement: String,
        markers: [CaptureParseRelationshipMarker],
        draft: String,
        ownLabelRange: CaptureRange
    ) -> (text: String, labelRange: CaptureRange)? {
        let plain = String(replacement.drop(while: { $0 == "|" }))
        let oneOff = String(hideReplacement.drop(while: { $0 == "|" }))
        guard !plain.isEmpty, !oneOff.isEmpty else {
            return nil
        }
        let matches: [(range: CaptureRange, text: String)] = markers.compactMap { marker in
            guard let label = marker.label,
                  let range = marker.labelRange,
                  relationLabelKey(label) == oldKey
            else {
                return nil
            }
            return (range, marker.hidden ? oneOff : plain)
        }
        guard !matches.isEmpty else {
            return nil
        }
        let ascending = matches.sorted { $0.range.start < $1.range.start }
        var startShift = 0
        var endShift = 0
        for (range, labelText) in ascending {
            let shift = labelText.utf8.count - (range.end - range.start)
            if range.end <= ownLabelRange.start {
                startShift += shift
            }
            if range.start < ownLabelRange.end {
                endShift += shift
            }
        }
        var text = draft
        for (range, labelText) in ascending.sorted(by: { $0.range.start > $1.range.start }) {
            guard let swiftRange = stringRange(in: text, byteRange: range) else {
                continue
            }
            text.replaceSubrange(swiftRange, with: labelText)
        }
        return (
            text,
            CaptureRange(
                start: ownLabelRange.start + startShift,
                end: ownLabelRange.end + endShift
            )
        )
    }

    func cycleRelationLabelSuggestionForward() {
        clearEqualsGestureArm()
        moveRelationLabelSelection(by: 1)
    }

    func cycleRelationLabelSuggestionBackward() {
        clearEqualsGestureArm()
        moveRelationLabelSelection(by: -1)
    }

    /// Every row the highlight can land on: visible rows first, then the
    /// open Hidden section. Hidden rows accept like any row.
    private var relationLabelNavigableRows: [CaptureCompletionCandidate] {
        relationLabelPromptRows + relationLabelHiddenPromptRows
    }

    private func moveRelationLabelSelection(by offset: Int) {
        guard var prompt = relationLabelPrompt, !prompt.isSaving, prompt.rename == nil else {
            return
        }
        let rows = relationLabelNavigableRows
        guard !rows.isEmpty else { return }
        let selectedIndex = prompt.selectedKey.flatMap { key in
            rows.firstIndex { relationLabelKey($0) == key }
        }
        if offset > 0 {
            if let selectedIndex, selectedIndex + 1 < rows.count {
                prompt.selectedKey = relationLabelKey(rows[selectedIndex + 1])
            } else if selectedIndex == nil {
                prompt.selectedKey = relationLabelKey(rows[0])
            } else {
                prompt.selectedKey = nil
            }
        } else if let selectedIndex, selectedIndex > 0 {
            prompt.selectedKey = relationLabelKey(rows[selectedIndex - 1])
        } else if selectedIndex == nil {
            prompt.selectedKey = relationLabelKey(rows[rows.count - 1])
        } else {
            prompt.selectedKey = nil
        }
        prompt.noticeMessage = nil
        relationLabelPrompt = prompt
    }

    func selectRelationLabelSuggestion(key: String) {
        clearEqualsGestureArm()
        guard var prompt = relationLabelPrompt, !prompt.isSaving, prompt.rename == nil,
              relationLabelNavigableRows.contains(where: { relationLabelKey($0) == key })
        else {
            return
        }
        prompt.selectedKey = key
        prompt.noticeMessage = nil
        relationLabelPrompt = prompt
    }

    /// Tab accepts the highlighted row, or the first local match when the
    /// field has no selection. It never changes the query or calls Bob.
    func acceptRelationLabelSuggestion() {
        clearEqualsGestureArm()
        guard !relationLabelPromptIsSaving, relationLabelPrompt?.rename == nil else { return }
        // Stale catalog rows after a direction flip must never commit.
        guard relationLabelPrompt?.catalogLoaded == true else { return }
        guard let candidate = relationLabelSelectedCandidate ?? relationLabelPromptRows.first else {
            guard var prompt = relationLabelPrompt else { return }
            prompt.errorMessage = relationLabelPromptHint ?? "No matching labels · type a relation name"
            relationLabelPrompt = prompt
            return
        }
        insertRelationLabelSuggestion(candidate: candidate)
    }

    func insertRelationLabelSuggestion(id: String) {
        clearEqualsGestureArm()
        guard relationLabelPrompt?.rename == nil,
              let candidate = relationLabelNavigableRows.first(where: {
            $0.replacement == id || $0.label == id || $0.key == id
                || relationLabelKey($0) == id
        }) else {
            return
        }
        insertRelationLabelSuggestion(candidate: candidate)
    }

    /// Rename-mode footer: `↩` renames (or arms/applies the merge),
    /// `esc` returns to choose mode. At most three pairs.
    var relationLabelRenameFooterItems: [(keycap: String, label: String)] {
        guard let rename = relationLabelPrompt?.rename else { return [] }
        if rename.isApplying {
            return [("esc", "cancel")]
        }
        if rename.mergeArmed,
           let preview = rename.preview,
           rename.previewNewName == rename.newName,
           rename.previewMerge
        {
            return [
                ("↩", "again to merge \(preview.links) links"),
                ("esc", "cancel"),
            ]
        }
        if rename.refusalCode == "label_exists", !rename.mergeArmed {
            let target = rename.newName.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetCount = relationLabelCatalogCount(for: relationLabelKey(target))
            let sourceCount = relationLabelCatalogCount(for: rename.oldKey)
            return [
                ("↩", "merge into “\(target)” (\(targetCount)) → \(targetCount + sourceCount) links"),
                ("esc", "cancel"),
            ]
        }
        return [
            ("↩", "rename everywhere"),
            ("esc", "cancel"),
        ]
    }

    /// Current catalog link count for a key (0 when the key is unknown).
    /// Feeds the merge-confirm footer before the merge preview lands.
    private func relationLabelCatalogCount(for key: String) -> Int {
        guard let prompt = relationLabelPrompt else { return 0 }
        if let row = prompt.catalog.first(where: { relationLabelKey($0) == key }) {
            return row.count ?? 0
        }
        return prompt.hiddenRows.first(where: { $0.key == key })?.count ?? 0
    }

    /// Bob's counts line for the rename preview, e.g.
    /// `3 links in 3 notes · 2 mirrors · 1 in done/ · 1 commit`.
    /// Nil while no fresh preview covers the rename field.
    var relationLabelRenamePreviewLines: [String]? {
        guard let rename = relationLabelPrompt?.rename,
              let preview = rename.preview,
              rename.previewNewName == rename.newName,
              rename.previewMerge == rename.mergeArmed
        else {
            return nil
        }
        var counts =
            "\(preview.links) links in \(preview.notes) notes · \(preview.mirrors) mirrors"
        if preview.doneLinks > 0 {
            counts += " · \(preview.doneLinks) in done/"
        }
        counts += " · 1 commit"
        var lines = [counts]
        if !preview.hiddenNote.isEmpty {
            lines.append(preview.hiddenNote)
        }
        if !preview.inverseNote.isEmpty {
            lines.append(preview.inverseNote)
        }
        return lines
    }

    /// Context-sensitive footer keycaps (at most five pairs) that teach the
    /// grammar, including `||`, without repeating the full key table.
    var relationLabelFooterItems: [(keycap: String, label: String)] {
        guard let prompt = relationLabelPrompt else { return [] }
        if prompt.rename != nil {
            return relationLabelRenameFooterItems
        }
        if let selected = relationLabelSelectedCandidate,
           selected.disabledReason?.isEmpty == false
        {
            let key = relationLabelKey(selected)
            let hidden =
                selected.hidden || relationLabelIsHiddenKey(key, in: prompt)
                || prompt.ghosts[key] == true
            var items: [(keycap: String, label: String)] = [
                (
                    "⌃D",
                    prompt.ghosts[key] != nil ? "undo" : (hidden ? "unhide" : "hide")
                ),
            ]
            if prompt.hiddenCountKnown, prompt.hiddenCount > 0 {
                items.append(("⌃H", prompt.showHidden ? "hide list" : "hidden"))
            }
            if relationLabelTeachesFlip {
                items.append(("~", "flips"))
            }
            items.append(("esc", "back"))
            return items
        }
        let selectedInsertion = relationLabelSelectedCandidate.map {
            relationLabelInsertion(for: $0, oneOff: prompt.oneOff)
        }
        if prompt.oneOff {
            if relationLabelOneOffWarning != nil {
                return [
                    ("↩", "inserts \(selectedInsertion ?? "||…")"),
                    ("⌃D", "keep visible"),
                    ("esc", "back"),
                ]
            }
            if let insertion = selectedInsertion, !insertion.isEmpty {
                return [
                    ("↩", "inserts \(insertion) · won't be suggested again"),
                    ("⌃D", "visible"),
                    ("esc", "back"),
                ]
            }
            if let typed = relationLabelFreshTypedRow,
               !relationLabelInsertion(for: typed, oneOff: true).isEmpty,
               typed.disabledReason?.isEmpty != false
            {
                return [
                    ("↩", "inserts \(relationLabelInsertion(for: typed, oneOff: true)) · won't be suggested again"),
                    ("⌃D", "visible"),
                    ("esc", "back"),
                ]
            }
            if relationLabelTeachesFlip {
                return [("↩", "inserts plain link"), ("~", "flips"), ("esc", "back")]
            }
            return [("↩", "inserts plain link"), ("esc", "back")]
        }
        var items: [(keycap: String, label: String)] = []
        if let selected = relationLabelSelectedCandidate {
            let key = relationLabelKey(selected)
            let hidden =
                selected.hidden || relationLabelIsHiddenKey(key, in: prompt)
                || prompt.ghosts[key] == true
            let replacement = relationLabelInsertion(for: selected, oneOff: false)
            if hidden {
                items.append(("↩", "inserts \(replacement) (stays hidden)"))
            } else {
                items.append(("↩", "inserts \(replacement)"))
            }
            if prompt.ghosts[key] != nil {
                items.append(("⌃D", "undo"))
            } else {
                items.append(("⌃D", hidden ? "unhide" : "hide"))
            }
        } else if relationLabelNavigableRows.first != nil {
            items.append(("⇥", "accepts top match"))
            if let typed = relationLabelFreshTypedRow,
               !typed.replacement.isEmpty,
               typed.disabledReason?.isEmpty != false
            {
                items.append(("↩", "inserts \(typed.replacement)"))
            }
            items.append(("⌃D", "one-off"))
        } else {
            items.append(("↩", "inserts plain link"))
        }
        if prompt.hiddenCountKnown, prompt.hiddenCount > 0 {
            items.append(("⌃H", prompt.showHidden ? "hide list" : "hidden"))
        }
        if relationLabelTeachesFlip {
            items.append(("~", "flips"))
        }
        items.append(("esc", "back"))
        return Array(items.prefix(relationLabelTeachesFlip ? 6 : 5))
    }

    /// Footer/header teaching: a selected row disabled for `new_task`, or
    /// Bob sent an inverse hint. Decided from structured fields, never copy.
    var relationLabelTeachesFlip: Bool {
        guard let prompt = relationLabelPrompt, prompt.rename == nil else {
            return false
        }
        if relationLabelHasInverseHint {
            return true
        }
        guard let selected = relationLabelSelectedCandidate,
              selected.disabledReason?.isEmpty == false
        else {
            return false
        }
        return prompt.relationCancel?.verdict == "new_task"
            || prompt.relationComplete?.verdict == "new_task"
    }

    private var relationLabelHasInverseHint: Bool {
        guard let prompt = relationLabelPrompt else {
            return false
        }
        if let hint = prompt.relationSuccessor?.hint, !hint.isEmpty {
            return true
        }
        if let hint = prompt.relationCancel?.hint, !hint.isEmpty {
            return true
        }
        if let hint = prompt.relationComplete?.hint, !hint.isEmpty {
            return true
        }
        return false
    }

    private var relationLabelPromptIsSaving: Bool {
        relationLabelPrompt?.isSaving ?? true
    }

    /// What Return inserts for a row: the `||` form when one-off is on,
    /// else bob's plain replacement. The app never builds either token.
    private func relationLabelInsertion(for candidate: CaptureCompletionCandidate, oneOff: Bool) -> String {
        if oneOff {
            return candidate.hideReplacement ?? candidate.replacement
        }
        return candidate.replacement
    }

    private func insertRelationLabelSuggestion(candidate: CaptureCompletionCandidate) {
        guard var prompt = relationLabelPrompt, !prompt.isSaving, prompt.rename == nil,
              prompt.catalogLoaded
        else { return }
        if let reason = candidate.disabledReason, !reason.isEmpty {
            prompt.errorMessage = reason
            relationLabelPrompt = prompt
            return
        }
        let replacement = relationLabelInsertion(for: candidate, oneOff: prompt.oneOff)
        guard !replacement.isEmpty else {
            prompt.errorMessage = "This label cannot be inserted."
            relationLabelPrompt = prompt
            return
        }
        prompt.pendingSubmit = false
        insertRelationLabelReplacement(replacement, prompt: &prompt)
    }

    func submitRelationLabelPrompt() {
        clearEqualsGestureArm()
        if relationLabelPrompt?.rename != nil {
            submitRelationLabelRename()
            return
        }
        guard let prompt = relationLabelPrompt, !prompt.isSaving else {
            return
        }
        if let selected = relationLabelSelectedCandidate {
            // A flip invalidates catalog verdicts. Return on a highlighted
            // row waits for the new catalog so it never commits a stale
            // replacement. Empty Return and a typed label do not read the
            // catalog: they drop the pipe or wait on the typed-row probe.
            if !prompt.catalogLoaded {
                var waiting = prompt
                waiting.pendingSubmit = true
                relationLabelPrompt = waiting
                return
            }
            insertRelationLabelSuggestion(candidate: selected)
            return
        }
        submitAuthoredRelationLabel()
    }

    /// Choose-mode `~` / `=` flip. A fast second `=` undoes the flip and
    /// types one `=` into the label field. Guards consume the key with no
    /// effect; the flip writes no preference and runs no effect.
    func flipRelationLabelDirection(
        key: String,
        timestamp: TimeInterval = 0,
        isRepeat: Bool = false
    ) {
        guard let prompt = relationLabelPrompt, !prompt.isSaving, prompt.rename == nil else {
            equalsGestureArm = nil
            return
        }
        guard prompt.draftSnapshot == plainDraft else {
            equalsGestureArm = nil
            return
        }
        if key == "=",
           let arm = equalsGestureArm,
           arm.surface == .relationLabelCard,
           CaptureEqualsGesture.isFastSecond(
               first: arm.firstTimestamp,
               second: timestamp,
               isRepeat: isRepeat
           )
        {
            equalsGestureArm = nil
            let query = prompt.authoredLabel
            if applyRelationLabelDirectionFlip() {
                updateRelationLabelPromptLabel(query + "=")
            }
            return
        }
        if key != "=" {
            equalsGestureArm = nil
        }
        let flipped = applyRelationLabelDirectionFlip()
        if key == "=", flipped, let prompt = relationLabelPrompt {
            equalsGestureArm = CaptureEqualsGestureArm(
                surface: .relationLabelCard,
                firstTimestamp: timestamp,
                isOpener: false,
                preDraft: prompt.draftSnapshot,
                preCaretUTF8: prompt.restoreCursor,
                postDraft: prompt.draftSnapshot,
                postCaretUTF8: prompt.restoreCursor,
                pickerSnapshot: nil
            )
        }
    }

    func cancelRelationLabelPrompt() {
        // Escape leaves rename mode first and never drops the card: the
        // choose query, selection, and Hidden section wait underneath. A
        // rename apply in flight (`isSaving`) blocks cancellation.
        if cancelRelationLabelRename() {
            return
        }
        guard let prompt = relationLabelPrompt, !prompt.isSaving else {
            return
        }
        equalsGestureArm = nil
        let returnPicker = prompt.returnPicker
        let restoreCursor = prompt.restoreCursor
        clearRelationLabelPrompt()
        if let returnPicker {
            restoreDraftUndoably(
                returnPicker.draftSnapshot,
                cursor: returnPicker.restoreCursor
            )
            let direction: DependencyPickerDirection =
                returnPicker.source == .linkedFrom ? .linkedFrom : .linksTo
            let index: CapturePickerIndex =
                direction == .linkedFrom
                ? .linkedFrom(
                    DependencyPickerIndex(
                        candidates: returnPicker.candidates,
                        direction: .linkedFrom
                    )
                )
                : .linksTo(
                    DependencyPickerIndex(
                        candidates: returnPicker.candidates,
                        direction: .linksTo
                    )
                )
            let presentation = index.presentation(filter: returnPicker.filterText)
            pickerIndex = index
            pickerPresentation = presentation
            picker = returnPicker
            pickerMarkerHighlight = Self.pickerMarkerHighlightRange(
                source: returnPicker.source,
                replacementRange: returnPicker.replacementRange,
                markerRange: nil
            )
            applyPickerMarkerHighlight()
            dismissCompletion()
            pickerChip = nil
            editorInputLocked = true
            requestFocus(.pickerFilter)
            statusText = CapturePickerNeed.relationTarget.statusText
        } else {
            if stringRange(in: plainDraft, start: restoreCursor, end: restoreCursor) != nil {
                setPlainDraft(plainDraft, cursorUTF8Offset: restoreCursor, suppressSelectionCallbacks: true)
            }
            statusText = "Ready"
            requestFocus(.editor)
        }
    }

    private func clearEqualsGestureArm() {
        equalsGestureArm = nil
    }

    /// Clears a live `.` / `;` arm for any key that is neither its fast
    /// second key nor a Space/Escape restore. The arm must not survive
    /// navigation, a modifier, or a non-restoring Escape.
    func clearModifierAliasArmForInterveningKey() {
        let aliasKeys: Set<String> = [".", ";"]
        let hasAliasArm = equalsGestureArm.map { aliasKeys.contains($0.key) } == true
        let pendingAlias = pendingEqualsFirstKey.map { aliasKeys.contains($0.key) } == true
        guard hasAliasArm || pendingAlias else {
            return
        }
        if pendingAlias, let pending = pendingEqualsFirstKey {
            interruptedModifierAliasReply = (pending.draft, pending.timestamp)
        }
        if hasAliasArm {
            equalsGestureArm = nil
        }
        pendingEqualsFirstKey = nil
        equalsProbe = nil
    }

    @discardableResult
    private func applyRelationLabelDirectionFlip() -> Bool {
        guard var prompt = relationLabelPrompt else {
            return false
        }
        let token = prompt.tokenRange
        guard let flipped = toggleRelationTilde(
            in: prompt.draftSnapshot,
            tokenStart: token.start,
            tokenEnd: token.end
        ) else {
            return false
        }
        let editPoint = token.start + 1
        prompt.draftSnapshot = flipped.text
        prompt.tokenRange = CaptureRange(start: token.start, end: token.end + flipped.delta)
        prompt.labelRange = CaptureRange(
            start: prompt.labelRange.start + flipped.delta,
            end: prompt.labelRange.end + flipped.delta
        )
        if prompt.restoreCursor >= editPoint {
            prompt.restoreCursor += flipped.delta
        }
        prompt.direction = flipped.linkedFrom ? .linkedFrom : .linksTo
        if var returnPicker = prompt.returnPicker {
            let range = returnPicker.replacementRange
            if let pickerFlip = toggleRelationTilde(
                in: returnPicker.draftSnapshot,
                tokenStart: range.start,
                tokenEnd: range.end
            ) {
                let pickerEdit = range.start + 1
                returnPicker.draftSnapshot = pickerFlip.text
                returnPicker.replacementRange = CaptureRange(
                    start: range.start,
                    end: range.end + pickerFlip.delta
                )
                if returnPicker.restoreCursor >= pickerEdit {
                    returnPicker.restoreCursor += pickerFlip.delta
                }
                returnPicker.source = pickerFlip.linkedFrom ? .linkedFrom : .linksTo
                prompt.returnPicker = returnPicker
            }
        }
        prompt.relationCancel = nil
        prompt.relationComplete = nil
        prompt.relationSuccessor = nil
        prompt.suggestions = []
        prompt.suggestionAuthoredLabel = nil
        prompt.errorMessage = nil
        prompt.pendingSubmit = false
        prompt.catalogLoaded = processClient != nil ? false : true
        relationLabelCatalogGeneration &+= 1
        relationLabelSuggestionGeneration &+= 1
        relationLabelCatalogInFlight = nil
        relationLabelInFlight = nil
        relationLabelPrompt = prompt
        applyFocusPreservingRelationFlip(
            at: editPoint,
            inserting: flipped.delta > 0,
            resultingDraft: flipped.text,
            cursor: prompt.restoreCursor
        )
        announceStatus(prompt.direction == .linkedFrom ? "Linked From" : "Links To")
        requestFocus(.relationLabelPromptField)
        if processClient != nil {
            fetchRelationLabelCatalog()
            if !prompt.authoredLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fetchRelationLabelSuggestions()
            }
        }
        return true
    }

    private func toggleRelationTilde(
        in text: String,
        tokenStart: Int,
        tokenEnd: Int
    ) -> (text: String, delta: Int, linkedFrom: Bool)? {
        let bytes = Array(text.utf8)
        guard tokenStart < bytes.count, bytes[tokenStart] == 126 else {
            return nil
        }
        let editPoint = tokenStart + 1
        let isLinkedFrom =
            editPoint < tokenEnd && editPoint < bytes.count && bytes[editPoint] == 126
        if !isLinkedFrom {
            guard let insertRange = stringRange(in: text, start: editPoint, end: editPoint) else {
                return nil
            }
            var next = text
            next.replaceSubrange(insertRange, with: "~")
            return (next, 1, true)
        }
        guard editPoint <= tokenEnd,
              let deleteRange = stringRange(in: text, start: editPoint, end: editPoint + 1)
        else {
            return nil
        }
        var next = text
        next.removeSubrange(deleteRange)
        return (next, -1, false)
    }

    private func applyFocusPreservingRelationFlip(
        at editPoint: Int,
        inserting: Bool,
        resultingDraft: String,
        cursor: Int
    ) {
        let end = inserting ? editPoint : editPoint + 1
        guard let replacementRange = utf16Range(in: plainDraft, start: editPoint, end: end),
              let cursorUTF16 = utf16Range(in: resultingDraft, start: cursor, end: cursor)?.location
        else {
            setPlainDraft(
                resultingDraft,
                cursorUTF8Offset: cursor,
                suppressSelectionCallbacks: true
            )
            return
        }
        let edit = CaptureNativeRewriteEdit(
            replacementRange: replacementRange,
            replacementText: inserting ? "~" : "",
            resultingSelection: NSRange(location: cursorUTF16, length: 0),
            expectedDraft: plainDraft,
            resultingDraft: resultingDraft
        )
        suppressedCompletionAcceptanceDraft = resultingDraft
        if applyNativeRewriteEdit?(edit) == true {
            if plainDraft != resultingDraft {
                isApplyingProgrammaticDraft = true
                attributedDraft = AttributedString(resultingDraft)
                isApplyingProgrammaticDraft = false
            }
            restoreSelection(cursorUTF8Offset: cursor, suppressEditorCallbacks: true)
            return
        }
        setPlainDraft(
            resultingDraft,
            cursorUTF8Offset: cursor,
            suppressSelectionCallbacks: true
        )
    }

    private func restoreDraftUndoably(_ text: String, cursor: Int) {
        guard text != plainDraft else {
            if stringRange(in: plainDraft, start: cursor, end: cursor) != nil {
                setPlainDraft(plainDraft, cursorUTF8Offset: cursor, suppressSelectionCallbacks: true)
            }
            return
        }
        guard let replacementRange = utf16Range(
            in: plainDraft,
            start: 0,
            end: plainDraft.utf8.count
        ),
            let cursorUTF16 = utf16Range(in: text, start: cursor, end: cursor)?.location
        else {
            setPlainDraft(text, cursorUTF8Offset: cursor, suppressSelectionCallbacks: true)
            return
        }
        let edit = CaptureNativeRewriteEdit(
            replacementRange: replacementRange,
            replacementText: text,
            resultingSelection: NSRange(location: cursorUTF16, length: 0),
            expectedDraft: plainDraft,
            resultingDraft: text
        )
        if applyNativeRewriteEdit?(edit) == true {
            if plainDraft != text {
                isApplyingProgrammaticDraft = true
                attributedDraft = AttributedString(text)
                isApplyingProgrammaticDraft = false
            }
            restoreSelection(cursorUTF8Offset: cursor, suppressEditorCallbacks: true)
            return
        }
        setPlainDraft(text, cursorUTF8Offset: cursor, suppressSelectionCallbacks: true)
    }

    private func submitAuthoredRelationLabel() {
        guard var prompt = relationLabelPrompt, !prompt.isSaving else {
            return
        }
        guard prompt.draftSnapshot == plainDraft else {
            prompt.errorMessage = "Draft changed. Reopen the relation card and try again."
            prompt.pendingSubmit = false
            relationLabelPrompt = prompt
            requestFocus(.relationLabelPromptField)
            return
        }
        let trimmed = prompt.authoredLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            prompt.pendingSubmit = false
            relationLabelPrompt = prompt
            let returnPicker = prompt.returnPicker
            if returnPicker == nil {
                guard let replacementRange = stringRange(
                    in: prompt.draftSnapshot,
                    byteRange: prompt.labelRange
                ) else {
                    prompt.errorMessage = "Completion range is stale. Reopen the relation card and try again."
                    relationLabelPrompt = prompt
                    return
                }
                var text = prompt.draftSnapshot
                text.replaceSubrange(replacementRange, with: "")
                let caret = prompt.labelRange.start
                guard stringRange(in: text, start: caret, end: caret) != nil else {
                    prompt.errorMessage = "Completion cursor is stale. Reopen the relation card and try again."
                    relationLabelPrompt = prompt
                    return
                }
                clearRelationLabelPrompt()
                suppressedCompletionAcceptanceDraft = text
                setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
                scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: false, trigger: .edit)
                statusText = "Inserted relation without a label"
                requestFocus(.editor)
                return
            }
            clearRelationLabelPrompt()
            statusText = "Inserted relation without a label"
            requestFocus(.editor)
            return
        }
        if commitFreshRelationLabel() {
            return
        }
        prompt.pendingSubmit = true
        prompt.errorMessage = nil
        relationLabelPrompt = prompt
        requestFocus(.relationLabelPromptField)
        guard processClient != nil else {
            var waiting = prompt
            waiting.pendingSubmit = false
            waiting.errorMessage = "Bob is not resolved. Check Settings and Recheck Bob."
            relationLabelPrompt = waiting
            return
        }
        fetchRelationLabelSuggestions()
    }

    /// Insert or refuse from bob's fresh typed row. Returns false when no
    /// fresh typed row covers the current authored input yet.
    @discardableResult
    private func commitFreshRelationLabel() -> Bool {
        guard var prompt = relationLabelPrompt, !prompt.isSaving else {
            return false
        }
        guard prompt.suggestionAuthoredLabel == prompt.authoredLabel else {
            return false
        }
        let trimmed = prompt.authoredLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        guard let typed = prompt.suggestions.first(where: { $0.typed }) else {
            prompt.pendingSubmit = false
            prompt.errorMessage =
                "This bob cannot validate relation labels. Update bob, or leave the label empty."
            relationLabelPrompt = prompt
            requestFocus(.relationLabelPromptField)
            return true
        }
        if let reason = typed.disabledReason, !reason.isEmpty {
            prompt.pendingSubmit = false
            prompt.errorMessage = reason
            relationLabelPrompt = prompt
            requestFocus(.relationLabelPromptField)
            return true
        }
        let replacement = relationLabelInsertion(for: typed, oneOff: prompt.oneOff)
        if replacement.isEmpty {
            prompt.pendingSubmit = false
            prompt.errorMessage = "This label cannot be inserted."
            relationLabelPrompt = prompt
            requestFocus(.relationLabelPromptField)
            return true
        }
        prompt.pendingSubmit = false
        insertRelationLabelReplacement(replacement, prompt: &prompt)
        return true
    }

    private func insertRelationLabelReplacement(
        _ replacement: String,
        prompt: inout CaptureRelationLabelPromptState
    ) {
        guard let suffixRange = stringRange(in: prompt.draftSnapshot, byteRange: prompt.labelRange) else {
            prompt.errorMessage = "Completion range is stale. Reopen the relation card and try again."
            relationLabelPrompt = prompt
            return
        }
        var text = prompt.draftSnapshot
        text.replaceSubrange(suffixRange, with: replacement)
        let caret = prompt.labelRange.start + replacement.utf8.count
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            prompt.errorMessage = "Completion cursor is stale. Reopen the relation card and try again."
            relationLabelPrompt = prompt
            return
        }
        let returnPicker = prompt.returnPicker
        clearRelationLabelPrompt()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: false, trigger: .edit)
        if returnPicker != nil {
            statusText = "Inserted \(replacement)"
        } else {
            statusText = "Inserted \(replacement)"
        }
        requestFocus(.editor)
    }

    private func clearRelationLabelPrompt() {
        relationLabelPrompt = nil
        equalsGestureArm = nil
        relationLabelSuggestionGeneration &+= 1
        relationLabelCatalogGeneration &+= 1
        relationLabelRenameGeneration &+= 1
        relationLabelInFlight = nil
        relationLabelCatalogInFlight = nil
        relationLabelRenameInFlight = nil
        clearEditorInputLockIfFree()
    }

    private func clearRelationLabelInFlight(generation: UInt64) {
        if relationLabelInFlight?.generation == generation {
            relationLabelInFlight = nil
        }
    }

    private func relationLabelProbe(
        prompt: CaptureRelationLabelPromptState,
        authoredLabel: String
    ) -> (draft: String, cursor: Int)? {
        guard let labelRange = stringRange(in: prompt.draftSnapshot, byteRange: prompt.labelRange),
              let labelStartIndex = stringRange(
                in: prompt.draftSnapshot,
                start: prompt.labelRange.start,
                end: prompt.labelRange.start
              )?.lowerBound
        else {
            return nil
        }
        let head = String(prompt.draftSnapshot[..<labelStartIndex])
        let tail = String(prompt.draftSnapshot[labelRange.upperBound...])
        let escaped = authoredLabel.replacingOccurrences(of: "\"", with: "")
        let probe = head + "|\"\(escaped)" + tail
        let cursor = prompt.labelRange.start + 2 + escaped.utf8.count
        guard stringRange(in: probe, start: cursor, end: cursor) != nil else {
            return nil
        }
        return (probe, cursor)
    }

    /// Fetch the empty-label catalog once when the card opens. This request
    /// has its own generation so typing cannot discard a late catalog reply.
    private func fetchRelationLabelCatalog() {
        guard let prompt = relationLabelPrompt,
              let processClient,
              prompt.draftSnapshot == plainDraft
        else {
            return
        }
        if let inFlight = relationLabelCatalogInFlight, inFlight.draft == prompt.draftSnapshot {
            return
        }
        guard let probe = relationLabelProbe(prompt: prompt, authoredLabel: "") else {
            return
        }
        relationLabelCatalogGeneration &+= 1
        let generation = relationLabelCatalogGeneration
        let draftSnapshot = prompt.draftSnapshot
        relationLabelCatalogInFlight = (generation, draftSnapshot)
        Task { [weak self, processClient] in
            do {
                let response = try await processClient.captureComplete(probe.draft, cursor: probe.cursor)
                await MainActor.run {
                    guard let self else { return }
                    self.clearRelationLabelCatalogInFlight(generation: generation)
                    self.applyRelationLabelCatalog(
                        response,
                        generation: generation,
                        draftSnapshot: draftSnapshot
                    )
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          self.relationLabelCatalogGeneration == generation,
                          var current = self.relationLabelPrompt,
                          current.draftSnapshot == draftSnapshot
                    else {
                        return
                    }
                    self.clearRelationLabelCatalogInFlight(generation: generation)
                    current.catalogLoaded = true
                    current.catalogErrorMessage = "Could not load relation labels. Type a label to continue."
                    self.relationLabelPrompt = current
                }
            }
        }
    }

    private func clearRelationLabelCatalogInFlight(generation: UInt64) {
        if relationLabelCatalogInFlight?.generation == generation {
            relationLabelCatalogInFlight = nil
        }
    }

    @discardableResult
    func applyRelationLabelCatalog(
        _ response: CaptureCompletionResponse,
        generation: UInt64,
        draftSnapshot: String
    ) -> Bool {
        guard relationLabelCatalogGeneration == generation,
              var current = relationLabelPrompt,
              current.draftSnapshot == draftSnapshot,
              current.draftSnapshot == plainDraft
        else {
            return false
        }
        current.catalogLoaded = true
        guard response.context == "relation_label" else {
            current.catalogErrorMessage = "This bob cannot suggest relation labels. Type a label to continue."
            relationLabelPrompt = current
            return true
        }
        current.catalog = response.candidates.filter { !$0.typed }
        current.catalogErrorMessage = nil
        current.relationCancel = response.relationCancel
        current.relationComplete = response.relationComplete
        current.relationSuccessor = response.relationSuccessor
        if let hiddenCount = response.hiddenCount {
            current.hiddenCount = hiddenCount
            current.hiddenCountKnown = true
        }
        if let selectedKey = current.selectedKey,
           !current.catalog.contains(where: {
               !$0.hidden && relationLabelKey($0) == selectedKey
           }),
           current.ghosts[selectedKey] == nil
        {
            current.selectedKey = nil
        }
        relationLabelPrompt = current
        if current.hiddenCount > 0 {
            fetchRelationLabelHiddenRows()
        }
        if current.pendingSubmit {
            let trimmed = current.authoredLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.selectedKey != nil || trimmed.isEmpty {
                submitRelationLabelPrompt()
            }
        }
        return true
    }

    /// Probe Bob for the typed row only. Existing rows stay in the locally
    /// filtered catalog; Bob still owns validation and canonical replacement
    /// for newly authored text (bob-cli-al).
    private func fetchRelationLabelSuggestions() {
        guard let prompt = relationLabelPrompt,
              let processClient,
              !prompt.authoredLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        guard prompt.draftSnapshot == plainDraft else {
            return
        }
        if let inFlight = relationLabelInFlight,
           inFlight.draft == prompt.draftSnapshot,
           inFlight.authored == prompt.authoredLabel
        {
            return
        }
        let typed = prompt.authoredLabel
        guard let probe = relationLabelProbe(prompt: prompt, authoredLabel: typed) else { return }
        relationLabelSuggestionGeneration &+= 1
        let generation = relationLabelSuggestionGeneration
        relationLabelInFlight = (
            generation: generation,
            draft: prompt.draftSnapshot,
            authored: prompt.authoredLabel
        )
        let draftSnapshot = prompt.draftSnapshot
        let requestedLabel = prompt.authoredLabel
        Task { [weak self, processClient] in
            do {
                let response = try await processClient.captureComplete(probe.draft, cursor: probe.cursor)
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.clearRelationLabelInFlight(generation: generation)
                    self.applyRelationLabelSuggestions(
                        response,
                        generation: generation,
                        draftSnapshot: draftSnapshot,
                        authoredLabel: requestedLabel
                    )
                }
            } catch {
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.clearRelationLabelInFlight(generation: generation)
                    guard self.relationLabelSuggestionGeneration == generation,
                          var current = self.relationLabelPrompt,
                          current.draftSnapshot == draftSnapshot,
                          current.authoredLabel == requestedLabel
                    else {
                        return
                    }
                    if current.pendingSubmit {
                        current.pendingSubmit = false
                        current.errorMessage = "Could not load label suggestions. Try again."
                    } else {
                        current.errorMessage = nil
                    }
                    self.relationLabelPrompt = current
                }
            }
        }
    }

    /// Applies one `relation_label` probe response to the current card.
    /// Each fetch is tied to the request generation plus the prompt and
    /// authored label it was issued for; a response that no longer matches
    /// — delayed, or an older one arriving after a newer one — is dropped so
    /// stale suggestions can never overwrite the current prompt's rows or
    /// validation (bob-cli-al). Returns whether the response was applied.
    @discardableResult
    func applyRelationLabelSuggestions(
        _ response: CaptureCompletionResponse,
        generation: UInt64,
        draftSnapshot: String,
        authoredLabel: String
    ) -> Bool {
        guard relationLabelSuggestionGeneration == generation,
              var current = relationLabelPrompt,
              current.draftSnapshot == draftSnapshot,
              current.draftSnapshot == plainDraft,
              current.authoredLabel == authoredLabel
        else {
            return false
        }
        guard response.context == "relation_label" else {
            return false
        }
        current.suggestions = response.candidates
        current.suggestionAuthoredLabel = authoredLabel
        current.relationCancel = response.relationCancel
        current.relationComplete = response.relationComplete
        current.relationSuccessor = response.relationSuccessor
        if let hiddenCount = response.hiddenCount {
            current.hiddenCount = hiddenCount
            current.hiddenCountKnown = true
        }
        if let typed = current.suggestions.first(where: { $0.typed }),
           let reason = typed.disabledReason, !reason.isEmpty
        {
            current.errorMessage = reason
        } else {
            current.errorMessage = nil
        }
        relationLabelPrompt = current
        if current.hiddenCount > 0 {
            fetchRelationLabelHiddenRows()
        }
        if current.pendingSubmit {
            commitFreshRelationLabel()
        }
        return true
    }

    /// `|` flow: a `relation_label` completion means Bob found a relation
    /// token ending where the label suffix starts. Open the card for that
    /// token with Bob's candidates, instead of showing an inline list.
    private func handleRelationLabelCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        trigger: CompletionTrigger
    ) async {
        guard isCurrentAnalysis(generation), plainDraft == draft else {
            return
        }
        guard trigger == .edit else {
            dismissCompletion()
            return
        }
        let tokenRange: CaptureRange
        let direction: DependencyPickerDirection
        if let relation = completion.relation {
            guard relation.range.start < relation.range.end,
                  relation.range.end == completion.replacement.start,
                  stringRange(in: draft, byteRange: relation.range) != nil
            else {
                dismissCompletion()
                return
            }
            switch relation.direction {
            case "to": direction = .linksTo
            case "from": direction = .linkedFrom
            default:
                dismissCompletion()
                return
            }
            tokenRange = relation.range
        } else {
            // Older-bob path: retain the legacy byte scan until `relation`
            // has shipped to every supported installation.
            let tokenEnd = completion.replacement.start
            guard tokenEnd <= draft.utf8.count,
                  tokenEnd > 0,
                  let tokenEndIndex = stringRange(in: draft, start: tokenEnd, end: tokenEnd)?.lowerBound
            else {
                dismissCompletion()
                return
            }
            let bytes = Array(draft.utf8)
            var tokenStart = tokenEnd - 1
            while tokenStart > 0,
                  bytes[tokenStart] != 0x7E,
                  bytes[tokenStart] != 0x20,
                  bytes[tokenStart] != 0x0A
            {
                tokenStart -= 1
            }
            guard tokenStart < tokenEnd,
                  bytes[tokenStart] == 0x7E,
                  let tokenStartIndex = stringRange(in: draft, start: tokenStart, end: tokenStart)?.lowerBound
            else {
                dismissCompletion()
                return
            }
            let token = String(draft[tokenStartIndex..<tokenEndIndex])
            guard token.hasPrefix("~"), !token.contains(" "), !token.contains("\n") else {
                dismissCompletion()
                return
            }
            direction = token.hasPrefix("~~") ? .linkedFrom : .linksTo
            tokenRange = CaptureRange(start: tokenStart, end: tokenEnd)
        }
        guard let tokenStartIndex = stringRange(
            in: draft,
            start: tokenRange.start,
            end: tokenRange.start
        )?.lowerBound,
              let tokenStringRange = stringRange(in: draft, byteRange: tokenRange),
              stringRange(in: draft, byteRange: completion.replacement) != nil
        else {
            dismissCompletion()
            return
        }
        let token = String(draft[tokenStringRange])
        let labelRange = completion.replacement
        if var existing = relationLabelPrompt,
           existing.draftSnapshot == draft,
           existing.tokenRange == tokenRange,
           existing.labelRange == labelRange
        {
            // A late completion for a previous label must not replace the
            // current validation and suggestions (bob-cli-al). Bob echoes the
            // probe's query, so adopt only what was computed for the current
            // input — and never clobber rows a newer fetch already tagged.
            // Without a query (older bob) there is nothing to verify, so keep
            // whatever the card already holds unless it has no fresh rows.
            let verified = completion.query == existing.authoredLabel
            let hasFreshRows = existing.suggestionAuthoredLabel == existing.authoredLabel
            if verified, !hasFreshRows {
                existing.suggestions = completion.candidates
                existing.suggestionAuthoredLabel = existing.authoredLabel
                existing.relationCancel = completion.relationCancel
                existing.relationComplete = completion.relationComplete
                existing.relationSuccessor = completion.relationSuccessor
                if let typed = completion.candidates.first(where: { $0.typed }),
                   let reason = typed.disabledReason, !reason.isEmpty
                {
                    existing.errorMessage = reason
                } else {
                    existing.errorMessage = nil
                }
                relationLabelPrompt = existing
                if existing.pendingSubmit {
                    commitFreshRelationLabel()
                }
            }
            dismissCompletion()
            return
        }
        dismissCompletion()
        let ownerPrefix = String(draft[..<tokenStartIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerText = completion.owner?.text ?? ownerPrefix
        let targetText = relationshipDisplayNames[token]
            ?? relationshipDisplayNames[token.trimmingCharacters(in: .whitespaces)]
            ?? ""
        openRelationLabelPrompt(
            draftSnapshot: draft,
            tokenRange: tokenRange,
            labelRange: labelRange,
            direction: direction,
            ownerText: ownerText,
            targetText: targetText,
            restoreCursor: cursor,
            returnPicker: nil
        )
        if var opened = relationLabelPrompt {
            opened.suggestions = completion.candidates
            opened.authoredLabel = completion.query ?? ""
            opened.suggestionAuthoredLabel = completion.query == nil ? nil : opened.authoredLabel
            // The card opens in one-off mode when it opens on a `||` token:
            // the replacement starts at the first pipe, so two pipes mean
            // the author already asked to hide the label on capture.
            let bytes = Array(draft.utf8)
            let pipe = completion.replacement.start
            if pipe + 1 < bytes.count, bytes[pipe] == 0x7C, bytes[pipe + 1] == 0x7C {
                opened.oneOff = true
            }
            if let typed = completion.candidates.first(where: { $0.typed }),
               let reason = typed.disabledReason, !reason.isEmpty
            {
                opened.errorMessage = reason
            }
            if let hiddenCount = completion.hiddenCount {
                opened.hiddenCount = hiddenCount
                opened.hiddenCountKnown = true
            }
            opened.relationCancel = completion.relationCancel
            opened.relationComplete = completion.relationComplete
            opened.relationSuccessor = completion.relationSuccessor
            relationLabelPrompt = opened
            if opened.hiddenCount > 0 {
                fetchRelationLabelHiddenRows()
            }
        }
    }

    /// Preview hook: mount the relation-label card production presents for a
    /// Control-Return relation pick, so design tests render the card production
    /// mounts.
    func installRelationLabelPromptForPreviews(
        draft: String = "New task ~tasks:target",
        tokenRange: CaptureRange = CaptureRange(start: 9, end: 22),
        labelRange: CaptureRange? = nil,
        direction: DependencyPickerDirection = .linksTo,
        ownerText: String = "New task",
        targetText: String = "Target",
        authoredLabel: String = "",
        suggestions: [CaptureCompletionCandidate] = [],
        suggestionAuthoredLabel: String? = nil,
        pendingSubmit: Bool = false,
        returnPicker: CapturePickerState? = nil,
        relationCancel: CaptureCompletionRelationCancel? = nil,
        relationComplete: CaptureCompletionRelationComplete? = nil,
        relationSuccessor: CaptureCompletionRelationSuccessor? = nil
    ) {
        plainDraft = draft
        relationLabelPrompt = CaptureRelationLabelPromptState(
            draftSnapshot: draft,
            tokenRange: tokenRange,
            labelRange: labelRange ?? CaptureRange(start: tokenRange.end, end: tokenRange.end),
            direction: direction,
            ownerText: ownerText,
            targetText: targetText,
            restoreCursor: draft.utf8.count,
            returnPicker: returnPicker,
            authoredLabel: authoredLabel,
            suggestions: suggestions,
            catalog: suggestions.filter { !$0.typed },
            catalogLoaded: processClient == nil,
            catalogErrorMessage: nil,
            suggestionAuthoredLabel: suggestionAuthoredLabel,
            pendingSubmit: pendingSubmit,
            selectedKey: nil,
            showHidden: false,
            oneOff: false,
            hiddenRows: [],
            hiddenCount: 0,
            hiddenCountKnown: false,
            hiddenRowsLoaded: false,
            ghosts: [:],
            noticeMessage: nil,
            visibilityWriteID: nil,
            rename: nil,
            isSaving: false,
            errorMessage: nil,
            relationCancel: relationCancel,
            relationComplete: relationComplete,
            relationSuccessor: relationSuccessor
        )
        editorInputLocked = true
        fetchRelationLabelCatalog()
    }

    /// Preview hook: stage the old-Bob capability gate for a `~` draft whose
    /// latest parse lacks `relation_grammar`, so design tests render the calm
    /// warning production shows.
    func installRelationCapabilityForPreviews(draft: String, hasGrammar: Bool) {
        plainDraft = draft
        lastAppliedParseDraft = draft
        lastAppliedParseGeneration = analysisGeneration
        lastAppliedParseGrammar = CaptureGrammarGate.minimumRevision
        lastAppliedParseClientIdentity = processClient?.identityToken
        lastRelationGrammar = hasGrammar ? 1 : nil
        if draft.contains("~") && !hasGrammar {
            relationCapabilityWarning =
                "This bob predates ~ links; ~ text would be captured literally · update bob"
        } else {
            relationCapabilityWarning = nil
        }
        relationCapabilityAcknowledgedDraft = nil
    }

    /// Test seam: pretends the current draft already parsed at the minimum grammar
    /// for this process client so submit tests that skip analysis can run.
    func installCompatibleCaptureGrammarForTests() {
        installCaptureGrammarForTests(CaptureGrammarGate.minimumRevision)
    }

    /// Test seam for missing (`nil`) and numeric grammar cases.
    func installCaptureGrammarForTests(_ grammar: Int?) {
        lastAppliedParseDraft = plainDraft
        lastAppliedParseGeneration = analysisGeneration
        lastAppliedParseGrammar = grammar
        lastAppliedParseClientIdentity = processClient?.identityToken
        refreshCaptureGrammarGate()
    }

    func submitTaskIDPrompt() {
        guard var prompt = taskIDPrompt, !prompt.isSaving else {
            return
        }
        guard let processClient else {
            prompt.errorMessage = "Bob is not resolved. Check Settings and Recheck Bob."
            taskIDPrompt = prompt
            requestFocus(.taskIDPromptBlockID)
            return
        }
        if let validationMessage = Self.blockIDValidationMessage(for: prompt.authoredID) {
            prompt.errorMessage = validationMessage
            taskIDPrompt = prompt
            requestFocus(.taskIDPromptBlockID)
            return
        }
        guard prompt.draftSnapshot == plainDraft else {
            prompt.errorMessage = "Draft changed. Return to the task list and choose again."
            taskIDPrompt = prompt
            requestFocus(.taskIDPromptBlockID)
            return
        }
        guard stringRange(in: prompt.draftSnapshot, byteRange: prompt.replacementRange) != nil else {
            prompt.errorMessage = "Completion range is stale. Return to the task list and choose again."
            taskIDPrompt = prompt
            requestFocus(.taskIDPromptBlockID)
            return
        }
        let route: String
        let taskRef: String
        // Exact-path dependency assignments never touch the lowercasing
        // route parser: the pending `route` already carries Bob's exact
        // `note_path`.
        let dependencyNotePath: String?
        var dependencyAllowClosed = false
        if case .taskLink(let linkRoute, let linkRef, _, _, _) = prompt.purpose {
            route = linkRoute
            taskRef = linkRef
            dependencyNotePath = nil
        } else if case .parentTaskPicker(let parentRoute, let parentRef, _, _, _, _) = prompt.purpose {
            route = parentRoute
            taskRef = parentRef
            dependencyNotePath = nil
        } else if case .projectTaskMove(let moveRoute, let moveRef, _, _, _) = prompt.purpose {
            route = moveRoute
            taskRef = moveRef
            dependencyNotePath = nil
        } else if case .dependency(let notePath, let depRef, _, _, _, let depAllowClosed) = prompt.purpose {
            route = notePath
            taskRef = depRef
            dependencyNotePath = notePath
            dependencyAllowClosed = depAllowClosed
        } else if case .blockedTask(let notePath, let blockedRef, _, _, _) = prompt.purpose {
            route = notePath
            taskRef = blockedRef
            dependencyNotePath = notePath
            dependencyAllowClosed = false
        } else if case .relation(let notePath, let relationRef, _, _, _, _) = prompt.purpose {
            route = notePath
            taskRef = relationRef
            dependencyNotePath = notePath
            dependencyAllowClosed = false
        } else if case .taskComplete(let notePath, let completeRef, _, _, _) = prompt.purpose {
            route = notePath
            taskRef = completeRef
            dependencyNotePath = notePath
            dependencyAllowClosed = false
        } else if case .wikilinkTask(let notePath, let wikiRef, _, _, _, let wikiAllowClosed, _) = prompt.purpose {
            route = notePath
            taskRef = wikiRef
            dependencyNotePath = notePath
            dependencyAllowClosed = wikiAllowClosed
        } else if case .similarTask(let similarRoute, let similarRef, _, _, _) = prompt.purpose {
            // Similar-tasks rows assign by route so Bob returns every
            // replacement string, including `parent_replacement`.
            route = similarRoute
            taskRef = similarRef
            dependencyNotePath = nil
        } else if let candidateRoute = prompt.candidate.route,
                  let candidateRef = prompt.candidate.taskRef
        {
            route = candidateRoute
            taskRef = candidateRef
            dependencyNotePath = nil
        } else {
            prompt.errorMessage = "Task candidate is missing route metadata. Refresh the task list and choose again."
            taskIDPrompt = prompt
            requestFocus(.taskIDPromptBlockID)
            return
        }

        let requestID = UUID()
        activeTaskIDRequestID = requestID
        prompt.isSaving = true
        prompt.errorMessage = nil
        taskIDPrompt = prompt
        // `route` is a bare route for `@route+` and `:` flows but Bob's
        // exact `note_path` (extension included) for `&` and `*` flows.
        statusText = dependencyNotePath == nil ? "Adding to \(route).md\u{2026}" : "Adding to \(route)\u{2026}"
        let blockID = prompt.authoredID

        Task { [dependencyNotePath, dependencyAllowClosed] in
            do {
                let response = try await CaptureSignpost.measure("capture-task-id") {
                    if let notePath = dependencyNotePath {
                        try await processClient.assignDependencyTaskID(
                            notePath: notePath,
                            taskRef: taskRef,
                            blockID: blockID,
                            allowClosed: dependencyAllowClosed
                        )
                    } else {
                        try await processClient.assignCaptureTaskID(
                            route: route,
                            taskRef: taskRef,
                            blockID: blockID
                        )
                    }
                }
                await MainActor.run {
                    self.completeTaskIDAssignment(requestID: requestID, response: response)
                }
            } catch {
                await MainActor.run {
                    self.failTaskIDAssignment(requestID: requestID, error: error)
                }
            }
        }
    }

    /// Presentation content for one completion row: icon, context label, primary/secondary
    /// text with match emphasis, and badges. Computed here (rather than in the view) because
    /// it needs the in-progress query text, which only the model can derive from the draft,
    /// the server-reported replacement range, and the cursor.
    func rowContent(for candidate: CaptureCompletionCandidate) -> CompletionRowContent {
        completionRowContent(
            for: candidate,
            context: completionResponse?.context,
            query: completionQueryText(),
            override: completionResponse?.overrideInfo,
            temporarilyHiddenThemeKey: temporarilyHiddenThemeKey,
            themeSuggestion: completionResponse?.themeSuggestion
        )
    }

    /// Bob-authored place menus plus the legacy drawer fallback. A generic
    /// non-notebook `section` response without chrome stays in the completion list.
    func placeMenuPresentation() -> CapturePlaceMenuPresentation? {
        guard let completionResponse,
              completionResponse.placeMenu != nil || completionResponse.context == "drawer"
        else {
            return nil
        }
        return CapturePlaceMenuPresentation(
            response: completionResponse,
            selectedIndex: selectedCompletionIndex,
            query: completionQueryText()
        )
    }

    private static func placeMenuScope(
        _ response: CaptureCompletionResponse
    ) -> PlaceMenuScope? {
        guard response.placeMenu != nil || response.context == "drawer" else {
            return nil
        }
        let destination: String
        if let menu = response.placeMenu {
            destination = [menu.caption, menu.title, response.target?.route ?? ""]
                .joined(separator: "\u{1f}")
        } else {
            destination = [
                response.target?.route ?? "",
                response.target?.blockID ?? "",
            ].joined(separator: "\u{1f}")
        }
        return PlaceMenuScope(
            context: response.context,
            kind: response.placeMenu?.kind ?? "drawer",
            destination: destination,
            fieldStart: response.replacement.start
        )
    }

    private static func placeMenuCandidateKey(
        _ candidate: CaptureCompletionCandidate
    ) -> PlaceMenuCandidateKey {
        PlaceMenuCandidateKey(
            group: candidate.group,
            title: candidate.title ?? candidate.replacement,
            kind: candidate.kind
        )
    }

    private static func notebookPlaceMenuInitialIndex(
        _ response: CaptureCompletionResponse
    ) -> Int? {
        guard !response.opensWithoutSelection else {
            return nil
        }
        let enabled = response.candidates.enumerated().filter {
            !CaptureCompletionMenu.isDisabled($0.element)
        }
        if let ordinary = enabled.first(where: {
            $0.element.group != "new" && $0.element.kind != "create" && !$0.element.creates
        }) {
            return ordinary.offset
        }
        return enabled.first(where: {
            $0.element.group == "new" || $0.element.kind == "create" || $0.element.creates
        })?.offset
    }

    func taskTypeMenuPresentation() -> CaptureTaskTypeMenuPresentation? {
        guard let completionResponse, completionResponse.context == "task_type" else {
            return nil
        }
        return CaptureTaskTypeMenuPresentation(
            response: completionResponse,
            selectedIndex: selectedCompletionIndex,
            temporarilyHiddenThemeKey: temporarilyHiddenThemeKey,
            today: CaptureTaskTypeMenuPresentation.todayISODate()
        )
    }

    func toggleSelectedCompletionThemeVisibility() {
        guard let candidate = selectedHistoryThemeCandidate,
              !isWritingThemeVisibility,
              let name = candidate.name,
              !name.isEmpty,
              let theme = candidate.themes.first
        else {
            return
        }
        guard let processClient else {
            statusText = "Bob is not resolved. Check Settings and Recheck Bob."
            return
        }

        let currentlyHidden = captureThemeCurrentlyHidden(
            candidate: candidate,
            temporarilyHiddenThemeKey: temporarilyHiddenThemeKey
        )
        let hidden = !currentlyHidden
        let draftSnapshot = plainDraft
        let requestID = UUID()
        activeThemeVisibilityRequestID = requestID
        isWritingThemeVisibility = true
        statusText = hidden ? "Hiding \(name)…" : "Restoring \(name)…"

        Task {
            do {
                try await processClient.setPomodoroThemeHidden(name, hidden: hidden)
                await MainActor.run {
                    guard self.activeThemeVisibilityRequestID == requestID else {
                        return
                    }
                    self.activeThemeVisibilityRequestID = nil
                    self.isWritingThemeVisibility = false
                    let draftIsUnchanged = self.plainDraft == draftSnapshot
                    let overrideActive = hidden != candidate.hidden && draftIsUnchanged
                    self.temporarilyHiddenThemeKey = overrideActive ? theme.key : nil
                    self.hiddenThemeDraftSnapshot = overrideActive ? draftSnapshot : nil
                    self.statusText = hidden
                        ? "\(name) hidden from Recent suggestions"
                        : "\(name) restored to Recent suggestions"
                    // The journal write recolors agenda rows; refresh now
                    // instead of waiting for the vault watcher echo.
                    self.agendaStore?.refresh(reason: .themes)
                }
            } catch {
                await MainActor.run {
                    guard self.activeThemeVisibilityRequestID == requestID else {
                        return
                    }
                    self.activeThemeVisibilityRequestID = nil
                    self.isWritingThemeVisibility = false
                    self.statusText = "Could not update \(name): \(error.localizedDescription)"
                }
            }
        }
    }

    private var selectedHistoryThemeCandidate: CaptureCompletionCandidate? {
        guard let completionResponse,
              let index = selectedCompletionIndex,
              completionResponse.candidates.indices.contains(index)
        else {
            return nil
        }
        let candidate = completionResponse.candidates[index]
        let hideableOrigin: Bool
        switch completionResponse.context {
        case "pomodoro_name", "pomodoro_start_name", "pomodoro_past_name":
            hideableOrigin = candidate.origin == "history"
        case "task_type":
            hideableOrigin = candidate.origin == "history" || candidate.origin == "configured"
        default:
            return nil
        }
        guard hideableOrigin,
              candidate.origin != "typed",
              candidate.name?.isEmpty == false,
              !candidate.themes.isEmpty
        else {
            return nil
        }
        return candidate
    }

    private func completionQueryText() -> String {
        guard let completionResponse else {
            return ""
        }
        if completionResponse.placeMenu?.kind == "notebook_section",
           let query = completionResponse.query
        {
            return query
        }
        if completionResponse.context == "task_type" {
            return completionResponse.query ?? ""
        }
        guard let range = stringRange(
            in: plainDraft,
            start: completionResponse.replacement.start,
            end: min(completionResponse.cursor, completionResponse.replacement.end)
        )
        else {
            return ""
        }
        let typed = String(plainDraft[range])
        if completionResponse.context == "drawer" || completionResponse.placeMenu != nil {
            // A drawer replacement may cover the glued `#` (and a literal's
            // opening quote); neither is part of the name being matched.
            return CapturePlaceMenuPresentation.queryText(fromTyped: typed)
        }
        return typed
    }

    private func presentTaskIDPrompt(
        candidate: CaptureCompletionCandidate,
        draftSnapshot: String,
        replacementRange: CaptureRange
    ) {
        clearPomodoroNamePrompt()
        invalidateAnalysis()
        activeTaskIDRequestID = nil
        taskIDPrompt = CaptureTaskIDPromptState(
            candidate: candidate,
            draftSnapshot: draftSnapshot,
            replacementRange: replacementRange,
            selectedCompletionIndex: selectedCompletionIndex,
            authoredID: "",
            isSaving: false,
            errorMessage: nil
        )
        statusText = "Add block ID"
        requestFocus(.taskIDPromptBlockID)
        editorInputLocked = true
    }

    /// Card-mode Add block ID prompt for an ID-less parent-task row: prefill
    /// with the first suggestion, keep the picker snapshot for Escape, and
    /// remember whether to submit after naming. Vault splices Bob's
    /// `parent_replacement`; scoped splices the returned ID.
    private func presentParentTaskIDPrompt(
        pending: CapturePickerPendingBlockID,
        pickerSnapshot: CapturePickerState,
        followUp: CaptureTaskLinkFollowUp
    ) {
        clearPomodoroNamePrompt()
        invalidateAnalysis()
        activeTaskIDRequestID = nil
        let candidate = pickerSnapshot.candidates.first {
            ($0.route ?? "") == pending.route && ($0.taskRef ?? "") == pending.taskRef
        } ?? CaptureCompletionCandidate(
            replacement: "",
            route: pending.route,
            taskRef: pending.taskRef,
            requiresBlockID: true,
            blockIDSuggestions: pending.suggestions
        )
        let prefill = pending.suggestions.first ?? ""
        let scope: ParentTaskPickerScope
        if case .parentTask(let context) = pickerSnapshot.source {
            scope = context.scope
        } else {
            scope = .note
        }
        let returnPicker = pickerSnapshot
        clearPickerMarkerHighlight(draftSnapshot: pickerSnapshot.draftSnapshot)
        picker = nil
        pickerPresentation = nil
        pickerIndex = nil
        taskIDPrompt = CaptureTaskIDPromptState(
            candidate: candidate,
            draftSnapshot: pickerSnapshot.draftSnapshot,
            replacementRange: pickerSnapshot.replacementRange,
            selectedCompletionIndex: selectedCompletionIndex,
            authoredID: prefill,
            isSaving: false,
            errorMessage: nil,
            purpose: .parentTaskPicker(
                route: pending.route,
                taskRef: pending.taskRef,
                suggestions: pending.suggestions,
                followUp: followUp,
                returnPicker: returnPicker,
                scope: scope
            )
        )
        statusText = "Add block ID"
        requestFocus(.taskIDPromptBlockID)
        editorInputLocked = true
    }

    /// Move-picker Add block ID prompt for an ID-less move row: prefill with
    /// the first suggestion, keep the picker snapshot for Escape, and splice
    /// the bare block ID into the picker's replacement range after the
    /// draft-snapshot check. Shift-Return chains via the picker's continuation.
    private func presentProjectTaskMoveIDPrompt(
        pending: CapturePickerPendingBlockID,
        pickerSnapshot: CapturePickerState,
        followUp: CaptureTaskLinkFollowUp
    ) {
        clearPomodoroNamePrompt()
        invalidateAnalysis()
        activeTaskIDRequestID = nil
        let candidate = pickerSnapshot.candidates.first {
            ($0.route ?? "") == pending.route && ($0.taskRef ?? "") == pending.taskRef
        } ?? CaptureCompletionCandidate(
            replacement: "",
            route: pending.route,
            taskRef: pending.taskRef,
            requiresBlockID: true,
            blockIDSuggestions: pending.suggestions
        )
        let prefill = pending.suggestions.first ?? ""
        let returnPicker = pickerSnapshot
        clearPickerMarkerHighlight(draftSnapshot: pickerSnapshot.draftSnapshot)
        picker = nil
        pickerPresentation = nil
        pickerIndex = nil
        taskIDPrompt = CaptureTaskIDPromptState(
            candidate: candidate,
            draftSnapshot: pickerSnapshot.draftSnapshot,
            replacementRange: pickerSnapshot.replacementRange,
            selectedCompletionIndex: selectedCompletionIndex,
            authoredID: prefill,
            isSaving: false,
            errorMessage: nil,
            purpose: .projectTaskMove(
                route: pending.route,
                taskRef: pending.taskRef,
                suggestions: pending.suggestions,
                followUp: followUp,
                returnPicker: returnPicker
            )
        )
        statusText = "Add block ID"
        requestFocus(.taskIDPromptBlockID)
        editorInputLocked = true
    }

    /// Shift-Return on a move row: insert the ID plus Bob's continuation,
    /// put the caret at the end, and re-analyse with completion requested so
    /// the fresh `- ^` reopens the picker. On an ID-less row it runs after
    /// the Add block ID prompt names the task.
    private func acceptProjectTaskMoveRowAndContinue(id: String) {
        guard let picker = picker,
              case .projectTaskMove(let context) = picker.source,
              plainDraft == picker.draftSnapshot,
              let range = stringRange(in: plainDraft, byteRange: picker.replacementRange)
        else {
            closePickerAfterStaleDraft()
            return
        }
        guard let row = pickerPresentation?.row(id: id) else {
            return
        }
        if row.insertion == nil, let pending = row.pendingBlockID {
            presentProjectTaskMoveIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: .start
            )
            return
        }
        guard let insertion = row.insertion else {
            announceStatus(row.badgeText ?? "That task cannot be used yet")
            return
        }
        let continued = insertion + (context.continuation ?? "\n- \(context.scopeToken)")
        var text = plainDraft
        text.replaceSubrange(range, with: continued)
        let caret = picker.replacementRange.start + continued.utf8.count
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            closePickerAfterStaleDraft()
            return
        }
        closePickerForAccept()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
        announceStatus("Inserted \(insertion) — pick the next task to move")
    }

    /// Link-mode Add block ID prompt for an ID-less `:` row: prefill with the
    /// first suggestion (fully selected in the view), keep the picker snapshot
    /// for Escape, and remember whether to append `=` or submit after naming.
    private func presentTaskLinkIDPrompt(
        pending: CapturePickerPendingBlockID,
        pickerSnapshot: CapturePickerState,
        followUp: CaptureTaskLinkFollowUp
    ) {
        clearPomodoroNamePrompt()
        invalidateAnalysis()
        activeTaskIDRequestID = nil
        let candidate = pickerSnapshot.candidates.first {
            ($0.route ?? "") == pending.route && ($0.taskRef ?? "") == pending.taskRef
        } ?? CaptureCompletionCandidate(
            replacement: "",
            route: pending.route,
            taskRef: pending.taskRef,
            requiresBlockID: true,
            blockIDSuggestions: pending.suggestions
        )
        let prefill = pending.suggestions.first ?? ""
        // Stash the open picker; Escape restores it without a refetch.
        let returnPicker = pickerSnapshot
        clearPickerMarkerHighlight(draftSnapshot: pickerSnapshot.draftSnapshot)
        picker = nil
        pickerPresentation = nil
        pickerIndex = nil
        taskIDPrompt = CaptureTaskIDPromptState(
            candidate: candidate,
            draftSnapshot: pickerSnapshot.draftSnapshot,
            replacementRange: pickerSnapshot.replacementRange,
            selectedCompletionIndex: selectedCompletionIndex,
            authoredID: prefill,
            isSaving: false,
            errorMessage: nil,
            purpose: .taskLink(
                route: pending.route,
                taskRef: pending.taskRef,
                suggestions: pending.suggestions,
                followUp: followUp,
                returnPicker: returnPicker
            )
        )
        statusText = "Add block ID"
        requestFocus(.taskIDPromptBlockID)
        editorInputLocked = true
    }

    /// Dependency-mode Add block ID prompt for an ID-less `&` row: prefill
    /// with the first suggestion (fully selected in the view), keep the
    /// picker snapshot for Escape, and remember whether to submit after
    /// naming. The prompt says **Add ID and use task** and explains it edits
    /// that note now; cancelling the later capture can leave an unused block
    /// ID, as with the `:` flow. The match is by exact note path, never by
    /// lowercased route, so nested and quoted notes round-trip.
    private func presentDependencyIDPrompt(
        pending: CapturePickerPendingBlockID,
        pickerSnapshot: CapturePickerState,
        followUp: CaptureTaskLinkFollowUp
    ) {
        clearPomodoroNamePrompt()
        invalidateAnalysis()
        activeTaskIDRequestID = nil
        let candidate = pickerSnapshot.candidates.first {
            ($0.notePath ?? $0.route ?? "") == pending.route && ($0.taskRef ?? "") == pending.taskRef
        } ?? CaptureCompletionCandidate(
            replacement: "",
            taskRef: pending.taskRef,
            requiresBlockID: true,
            blockIDSuggestions: pending.suggestions,
            notePath: pending.route
        )
        let prefill = pending.suggestions.first ?? ""
        // Done/Cancelled history rows name IDs without reopening: the
        // opt-in rides along so the assignment can land there.
        let allowClosed = candidate.statusType == "DONE" || candidate.statusType == "CANCELLED"
        // Stash the open picker; Escape restores it without a refetch.
        let returnPicker = pickerSnapshot
        clearPickerMarkerHighlight(draftSnapshot: pickerSnapshot.draftSnapshot)
        picker = nil
        pickerPresentation = nil
        pickerIndex = nil
        taskIDPrompt = CaptureTaskIDPromptState(
            candidate: candidate,
            draftSnapshot: pickerSnapshot.draftSnapshot,
            replacementRange: pickerSnapshot.replacementRange,
            selectedCompletionIndex: selectedCompletionIndex,
            authoredID: prefill,
            isSaving: false,
            errorMessage: nil,
            purpose: .dependency(
                notePath: pending.route,
                taskRef: pending.taskRef,
                suggestions: pending.suggestions,
                followUp: followUp,
                returnPicker: returnPicker,
                allowClosed: allowClosed
            )
        )
        statusText = "Add block ID and use task"
        requestFocus(.taskIDPromptBlockID)
        editorInputLocked = true
    }

    /// Blocks-mode Add block ID prompt for an ID-less `*` row. It keeps the
    /// exact note path and picker snapshot so Escape restores the same query.
    private func presentBlockedTaskIDPrompt(
        pending: CapturePickerPendingBlockID,
        pickerSnapshot: CapturePickerState,
        followUp: CaptureTaskLinkFollowUp
    ) {
        clearPomodoroNamePrompt()
        invalidateAnalysis()
        activeTaskIDRequestID = nil
        let candidate = pickerSnapshot.candidates.first {
            ($0.notePath ?? $0.route ?? "") == pending.route && ($0.taskRef ?? "") == pending.taskRef
        } ?? CaptureCompletionCandidate(
            replacement: "",
            taskRef: pending.taskRef,
            requiresBlockID: true,
            blockIDSuggestions: pending.suggestions,
            notePath: pending.route
        )
        let returnPicker = pickerSnapshot
        clearPickerMarkerHighlight(draftSnapshot: pickerSnapshot.draftSnapshot)
        picker = nil
        pickerPresentation = nil
        pickerIndex = nil
        taskIDPrompt = CaptureTaskIDPromptState(
            candidate: candidate,
            draftSnapshot: pickerSnapshot.draftSnapshot,
            replacementRange: pickerSnapshot.replacementRange,
            selectedCompletionIndex: selectedCompletionIndex,
            authoredID: pending.suggestions.first ?? "",
            isSaving: false,
            errorMessage: nil,
            purpose: .blockedTask(
                notePath: pending.route,
                taskRef: pending.taskRef,
                suggestions: pending.suggestions,
                followUp: followUp,
                returnPicker: returnPicker
            )
        )
        statusText = "Add block ID and use task"
        requestFocus(.taskIDPromptBlockID)
        editorInputLocked = true
    }

    /// Relation-mode Add block ID prompt for an ID-less `~` / `~~` row.
    private func presentRelationIDPrompt(
        pending: CapturePickerPendingBlockID,
        pickerSnapshot: CapturePickerState,
        followUp: CaptureTaskLinkFollowUp
    ) {
        clearPomodoroNamePrompt()
        invalidateAnalysis()
        activeTaskIDRequestID = nil
        let candidate = pickerSnapshot.candidates.first {
            ($0.notePath ?? $0.route ?? "") == pending.route && ($0.taskRef ?? "") == pending.taskRef
        } ?? CaptureCompletionCandidate(
            replacement: "",
            taskRef: pending.taskRef,
            requiresBlockID: true,
            blockIDSuggestions: pending.suggestions,
            notePath: pending.route
        )
        let direction = pickerSnapshot.source.dependencyDirection ?? .linksTo
        let returnPicker = pickerSnapshot
        clearPickerMarkerHighlight(draftSnapshot: pickerSnapshot.draftSnapshot)
        picker = nil
        pickerPresentation = nil
        pickerIndex = nil
        taskIDPrompt = CaptureTaskIDPromptState(
            candidate: candidate,
            draftSnapshot: pickerSnapshot.draftSnapshot,
            replacementRange: pickerSnapshot.replacementRange,
            selectedCompletionIndex: selectedCompletionIndex,
            authoredID: pending.suggestions.first ?? "",
            isSaving: false,
            errorMessage: nil,
            purpose: .relation(
                notePath: pending.route,
                taskRef: pending.taskRef,
                suggestions: pending.suggestions,
                followUp: followUp,
                returnPicker: returnPicker,
                direction: direction
            )
        )
        statusText = "Add block ID and use task"
        requestFocus(.taskIDPromptBlockID)
        editorInputLocked = true
    }

    /// Complete-mode Add block ID prompt for an ID-less `!` row: prefill
    /// with the first suggestion, keep the picker snapshot for Escape, and
    /// remember whether to submit after naming. The prompt says **Add ID &
    /// Insert** / **Add ID & Complete** and splices Bob's
    /// `complete_replacement`; it never builds the token in Swift.
    private func presentTaskCompleteIDPrompt(
        pending: CapturePickerPendingBlockID,
        pickerSnapshot: CapturePickerState,
        followUp: CaptureTaskLinkFollowUp
    ) {
        clearPomodoroNamePrompt()
        invalidateAnalysis()
        activeTaskIDRequestID = nil
        let candidate = pickerSnapshot.candidates.first {
            ($0.notePath ?? $0.locator ?? $0.route ?? "") == pending.route && ($0.taskRef ?? "") == pending.taskRef
        } ?? CaptureCompletionCandidate(
            replacement: "",
            taskRef: pending.taskRef,
            requiresBlockID: true,
            blockIDSuggestions: pending.suggestions,
            notePath: pending.route
        )
        let prefill = pending.suggestions.first ?? ""
        let returnPicker = pickerSnapshot
        clearPickerMarkerHighlight(draftSnapshot: pickerSnapshot.draftSnapshot)
        picker = nil
        pickerPresentation = nil
        pickerIndex = nil
        taskIDPrompt = CaptureTaskIDPromptState(
            candidate: candidate,
            draftSnapshot: pickerSnapshot.draftSnapshot,
            replacementRange: pickerSnapshot.replacementRange,
            selectedCompletionIndex: selectedCompletionIndex,
            authoredID: prefill,
            isSaving: false,
            errorMessage: nil,
            purpose: .taskComplete(
                notePath: pending.route,
                taskRef: pending.taskRef,
                suggestions: pending.suggestions,
                followUp: followUp,
                returnPicker: returnPicker
            )
        )
        statusText = "Add block ID and complete task"
        requestFocus(.taskIDPromptBlockID)
        editorInputLocked = true
    }

    /// Wikilink-mode Add block ID prompt for an ID-less `((` row: prefill
    /// with the first suggestion, keep the picker snapshot for Escape, and
    /// remember whether to submit after naming. The prompt says **Add ID &
    /// Link** / **Add ID & Capture** and splices Bob's
    /// `wikilink_replacement`; it never builds the link in Swift. History
    /// rows pass `--allow-closed` through `allowClosed`.
    private func presentWikilinkTaskIDPrompt(
        pending: CapturePickerPendingBlockID,
        pickerSnapshot: CapturePickerState,
        followUp: CaptureTaskLinkFollowUp
    ) {
        clearPomodoroNamePrompt()
        invalidateAnalysis()
        activeTaskIDRequestID = nil
        let candidate = pickerSnapshot.candidates.first {
            ($0.notePath ?? $0.locator ?? $0.route ?? "") == pending.route && ($0.taskRef ?? "") == pending.taskRef
        } ?? CaptureCompletionCandidate(
            replacement: "",
            taskRef: pending.taskRef,
            requiresBlockID: true,
            blockIDSuggestions: pending.suggestions,
            notePath: pending.route
        )
        let prefill = pending.suggestions.first ?? ""
        let returnPicker = pickerSnapshot
        let allowClosed = candidate.statusType == "DONE" || candidate.statusType == "CANCELLED"
        let linkTarget = candidate.linkTarget ?? candidate.locator ?? candidate.route
        clearPickerMarkerHighlight(draftSnapshot: pickerSnapshot.draftSnapshot)
        picker = nil
        pickerPresentation = nil
        pickerIndex = nil
        taskIDPrompt = CaptureTaskIDPromptState(
            candidate: candidate,
            draftSnapshot: pickerSnapshot.draftSnapshot,
            replacementRange: pickerSnapshot.replacementRange,
            selectedCompletionIndex: selectedCompletionIndex,
            authoredID: prefill,
            isSaving: false,
            errorMessage: nil,
            purpose: .wikilinkTask(
                notePath: pending.route,
                taskRef: pending.taskRef,
                suggestions: pending.suggestions,
                followUp: followUp,
                returnPicker: returnPicker,
                allowClosed: allowClosed,
                linkTarget: linkTarget
            )
        )
        statusText = "Add a block ID to link this task"
        requestFocus(.taskIDPromptBlockID)
        editorInputLocked = true
    }

    /// Similar-tasks Add block ID prompt for an ID-less row: prefill with
    /// the first block-ID suggestion, keep the band focus for Escape, and
    /// remember which strip action to splice after naming. The ID is
    /// written now, before Return, as the pickers already do.
    private func presentSimilarTaskIDPrompt(
        row: SimilarTasksBandRow,
        item: CaptureRelatedItem,
        action: CaptureRelatedAction
    ) {
        clearPomodoroNamePrompt()
        invalidateAnalysis()
        activeTaskIDRequestID = nil
        let candidate = CaptureCompletionCandidate(
            replacement: "",
            route: row.match.route,
            taskRef: row.match.taskRef,
            requiresBlockID: true,
            statusSymbol: row.match.statusSymbol,
            statusName: row.match.statusName,
            text: row.match.title,
            section: row.match.locator,
            blockIDSuggestions: row.match.blockIDSuggestions,
            notePath: row.match.notePath
        )
        // The prompt splices at the item's marker; a zero-length range there
        // keeps the draft-snapshot stale check meaningful while typing is
        // locked by the prompt.
        let at = item.markerAt ?? plainDraft.utf8.count
        taskIDPrompt = CaptureTaskIDPromptState(
            candidate: candidate,
            draftSnapshot: plainDraft,
            replacementRange: CaptureRange(start: at, end: at),
            selectedCompletionIndex: selectedCompletionIndex,
            authoredID: row.match.blockIDSuggestions.first ?? "",
            isSaving: false,
            errorMessage: nil,
            purpose: .similarTask(
                route: row.match.route,
                taskRef: row.match.taskRef,
                suggestions: row.match.blockIDSuggestions,
                action: action,
                itemIndex: row.itemIndex
            )
        )
        statusText = "Add block ID and use task"
        requestFocus(.taskIDPromptBlockID)
        editorInputLocked = true
    }

    /// Cycle the link-mode suggestion chips with Tab / Shift-Tab. Both link
    /// purposes use this; the parent-task flow keeps Tab consumed.
    func cycleTaskLinkSuggestion(forward: Bool) {
        guard var prompt = taskIDPrompt,
              !prompt.isSaving
        else {
            return
        }
        let suggestions: [String]
        switch prompt.purpose {
        case .taskLink(_, _, let linkSuggestions, _, _):
            suggestions = linkSuggestions
        case .dependency(_, _, let dependencySuggestions, _, _, _):
            suggestions = dependencySuggestions
        case .blockedTask(_, _, let blockedTaskSuggestions, _, _):
            suggestions = blockedTaskSuggestions
        case .relation(_, _, let relationSuggestions, _, _, _):
            suggestions = relationSuggestions
        case .taskComplete(_, _, let completeSuggestions, _, _):
            suggestions = completeSuggestions
        case .wikilinkTask(_, _, let wikilinkSuggestions, _, _, _, _):
            suggestions = wikilinkSuggestions
        case .parentTaskPicker(_, _, let parentSuggestions, _, _, _):
            suggestions = parentSuggestions
        case .projectTaskMove(_, _, let moveSuggestions, _, _):
            suggestions = moveSuggestions
        case .similarTask(_, _, let similarSuggestions, _, _):
            suggestions = similarSuggestions
        case .parentTask:
            return
        }
        guard !suggestions.isEmpty else {
            return
        }
        let current = suggestions.firstIndex(of: prompt.authoredID) ?? (forward ? -1 : 0)
        let next: Int
        if forward {
            next = (current + 1) % suggestions.count
        } else {
            next = (current - 1 + suggestions.count) % suggestions.count
        }
        prompt.authoredID = suggestions[next]
        prompt.errorMessage = nil
        taskIDPrompt = prompt
        requestFocus(.taskIDPromptBlockID)
    }

    private func presentPomodoroNamePrompt(
        candidate: CaptureCompletionCandidate,
        draftSnapshot: String,
        replacementRange: CaptureRange
    ) {
        clearTaskIDPrompt()
        invalidateAnalysis()
        activePomodoroNameRequestID = nil
        pomodoroNamePrompt = CapturePomodoroNamePromptState(
            candidate: candidate,
            draftSnapshot: draftSnapshot,
            replacementRange: replacementRange,
            selectedCompletionIndex: selectedCompletionIndex,
            authoredName: Self.prefilledPomodoroName(from: completionQueryText()),
            suggestions: [],
            suggestionQuery: nil,
            suggestionsLoading: false,
            suggestionsUnavailable: false,
            configuredThemes: nil,
            isSaving: false,
            errorMessage: nil
        )
        statusText = "Name Pomodoro"
        refreshPomodoroThemeSuggestions(query: pomodoroNamePrompt?.authoredName ?? "")
        requestFocus(.pomodoroNamePromptName)
        editorInputLocked = true
    }

    private func completePomodoroNameAssignment(
        requestID: UUID,
        response: CapturePomodoroNameResponse
    ) {
        guard activePomodoroNameRequestID == requestID,
              var prompt = pomodoroNamePrompt
        else {
            return
        }
        activePomodoroNameRequestID = nil

        switch response {
        case .success(let success):
            guard let range = stringRange(in: prompt.draftSnapshot, byteRange: prompt.replacementRange) else {
                prompt.isSaving = false
                prompt.errorMessage = "Completion range is stale. Return to the Pomodoro list and choose again."
                pomodoroNamePrompt = prompt
                statusText = "Name Pomodoro failed"
                requestFocus(.pomodoroNamePromptName)
                return
            }

            var text = prompt.draftSnapshot
            text.replaceSubrange(range, with: success.slug)
            let cursor = prompt.replacementRange.start + success.slug.utf8.count
            guard stringRange(in: text, start: cursor, end: cursor) != nil else {
                prompt.isSaving = false
                prompt.errorMessage = "Completion cursor is stale. Return to the Pomodoro list and choose again."
                pomodoroNamePrompt = prompt
                statusText = "Name Pomodoro failed"
                requestFocus(.pomodoroNamePromptName)
                return
            }

            clearPomodoroNamePrompt()
            dismissCompletion()
            suppressedCompletionAcceptanceDraft = text
            setPlainDraft(
                text,
                cursorUTF8Offset: cursor,
                suppressSelectionCallbacks: true
            )
            scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
            statusText = "Named \(success.name) in \(success.relativeDayFile)"
            requestFocus(.editor)
        case .failure(let failure):
            prompt.isSaving = false
            prompt.errorMessage = failure.error
            pomodoroNamePrompt = prompt
            statusText = "Name Pomodoro failed"
            requestFocus(.pomodoroNamePromptName)
        }
    }

    private func failPomodoroNameAssignment(requestID: UUID, error: Error) {
        guard activePomodoroNameRequestID == requestID,
              var prompt = pomodoroNamePrompt
        else {
            return
        }
        activePomodoroNameRequestID = nil
        prompt.isSaving = false
        prompt.errorMessage = String(describing: error)
        pomodoroNamePrompt = prompt
        statusText = "Name Pomodoro failed"
        requestFocus(.pomodoroNamePromptName)
    }

    private func completeTaskIDAssignment(
        requestID: UUID,
        response: CaptureTaskIDResponse
    ) {
        guard activeTaskIDRequestID == requestID,
              var prompt = taskIDPrompt
        else {
            return
        }
        activeTaskIDRequestID = nil

        switch response {
        case .success(let success):
            if case .similarTask(_, _, _, let action, let itemIndex) = prompt.purpose {
                completeSimilarTaskIDAssignment(
                    prompt: &prompt,
                    success: success,
                    action: action,
                    itemIndex: itemIndex
                )
                return
            }
            if case .parentTaskPicker(_, _, _, let followUp, _, let scope) = prompt.purpose {
                completeParentTaskIDAssignment(
                    prompt: &prompt,
                    success: success,
                    followUp: followUp,
                    scope: scope
                )
                return
            }
            if case .projectTaskMove(_, _, _, let followUp, let returnPicker) = prompt.purpose {
                let insertion = success.blockID
                guard let range = stringRange(in: prompt.draftSnapshot, byteRange: prompt.replacementRange) else {
                    prompt.isSaving = false
                    prompt.errorMessage = "Completion range is stale. Return to the task list and choose again."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                var text = prompt.draftSnapshot
                text.replaceSubrange(range, with: insertion)
                var cursor = prompt.replacementRange.start + insertion.utf8.count
                if followUp == .start,
                   case .projectTaskMove(let context) = returnPicker.source,
                   let continuation = context.continuation
                {
                    text.replaceSubrange(
                        stringRange(in: text, start: cursor, end: cursor)!,
                        with: continuation
                    )
                    cursor += continuation.utf8.count
                }
                guard stringRange(in: text, start: cursor, end: cursor) != nil else {
                    prompt.isSaving = false
                    prompt.errorMessage = "Completion cursor is stale. Return to the task list and choose again."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                clearTaskIDPrompt()
                dismissCompletion()
                suppressedCompletionAcceptanceDraft = text
                setPlainDraft(
                    text,
                    cursorUTF8Offset: cursor,
                    suppressSelectionCallbacks: true
                )
                scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: true, trigger: .edit)
                statusText = "Added ^\(success.blockID) to \(success.relativeTarget)"
                announceStatus("Added ^\(success.blockID) to \(success.route).md and inserted \(insertion)")
                requestFocus(.editor)
                if followUp == .submit || followUp == .submitAndOpen {
                    submitAfterCurrentAnalysis(openAfterCapture: followUp == .submitAndOpen)
                }
                return
            }
            if case .taskLink(_, _, _, let followUp, _) = prompt.purpose {
                let link = "@\(success.route):\(success.blockID)" + (followUp == .start ? "=" : "")
                guard let range = stringRange(in: prompt.draftSnapshot, byteRange: prompt.replacementRange) else {
                    prompt.isSaving = false
                    prompt.errorMessage = "Completion range is stale. Return to the task list and choose again."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                var text = prompt.draftSnapshot
                text.replaceSubrange(range, with: link)
                let cursor = prompt.replacementRange.start + link.utf8.count
                guard stringRange(in: text, start: cursor, end: cursor) != nil else {
                    prompt.isSaving = false
                    prompt.errorMessage = "Completion cursor is stale. Return to the task list and choose again."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                clearTaskIDPrompt()
                dismissCompletion()
                suppressedCompletionAcceptanceDraft = text
                setPlainDraft(
                    text,
                    cursorUTF8Offset: cursor,
                    suppressSelectionCallbacks: true
                )
                scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
                statusText = "Added ^\(success.blockID) to \(success.relativeTarget)"
                announceStatus("Added ^\(success.blockID) to \(success.route).md and inserted \(link)")
                requestFocus(.editor)
                if followUp == .submit || followUp == .submitAndOpen {
                    submitAfterCurrentAnalysis(openAfterCapture: followUp == .submitAndOpen)
                }
                return
            }
            if case .dependency(_, _, _, let followUp, _, _) = prompt.purpose {
                // Splice Bob's backend-formatted replacement verbatim: it
                // carries the quoting and case the app must never rebuild.
                guard let replacement = success.dependencyReplacement else {
                    prompt.isSaving = false
                    prompt.errorMessage = "This Bob is too old for dependency picks. Update Bob first."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                guard let range = stringRange(in: prompt.draftSnapshot, byteRange: prompt.replacementRange) else {
                    prompt.isSaving = false
                    prompt.errorMessage = "Completion range is stale. Return to the task list and choose again."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                var text = prompt.draftSnapshot
                text.replaceSubrange(range, with: replacement)
                let cursor = prompt.replacementRange.start + replacement.utf8.count
                guard stringRange(in: text, start: cursor, end: cursor) != nil else {
                    prompt.isSaving = false
                    prompt.errorMessage = "Completion cursor is stale. Return to the task list and choose again."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                clearTaskIDPrompt()
                dismissCompletion()
                suppressedCompletionAcceptanceDraft = text
                setPlainDraft(
                    text,
                    cursorUTF8Offset: cursor,
                    suppressSelectionCallbacks: true
                )
                scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
                statusText = "Added ^\(success.blockID) to \(success.relativeTarget)"
                announceStatus("Added ^\(success.blockID) to \(success.relativeTarget) and inserted \(replacement)")
                requestFocus(.editor)
                if followUp == .submit || followUp == .submitAndOpen {
                    submitAfterCurrentAnalysis(openAfterCapture: followUp == .submitAndOpen)
                }
                return
            }
            if case .blockedTask(_, _, _, let followUp, _) = prompt.purpose {
                completeBlockedTaskIDAssignment(
                    prompt: &prompt,
                    success: success,
                    followUp: followUp
                )
                return
            }
            if case .relation(_, _, _, let followUp, _, let direction) = prompt.purpose {
                completeRelationIDAssignment(
                    prompt: &prompt,
                    success: success,
                    followUp: followUp,
                    direction: direction
                )
                return
            }
            if case .taskComplete(_, _, _, let followUp, _) = prompt.purpose {
                // Splice Bob's backend-formatted Complete replacement
                // verbatim: it carries the quoting and case the app must
                // never rebuild.
                guard let replacement = success.completeReplacement, !replacement.isEmpty else {
                    prompt.isSaving = false
                    prompt.errorMessage = "This Bob is too old for Complete picks. Update Bob first."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                guard let range = stringRange(in: prompt.draftSnapshot, byteRange: prompt.replacementRange) else {
                    prompt.isSaving = false
                    prompt.errorMessage = "Completion range is stale. Return to the task list and choose again."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                var text = prompt.draftSnapshot
                text.replaceSubrange(range, with: replacement)
                let cursor = prompt.replacementRange.start + replacement.utf8.count
                guard stringRange(in: text, start: cursor, end: cursor) != nil else {
                    prompt.isSaving = false
                    prompt.errorMessage = "Completion cursor is stale. Return to the task list and choose again."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                clearTaskIDPrompt()
                dismissCompletion()
                suppressedCompletionAcceptanceDraft = text
                setPlainDraft(
                    text,
                    cursorUTF8Offset: cursor,
                    suppressSelectionCallbacks: true
                )
                scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
                statusText = "Added ^\(success.blockID) to \(success.relativeTarget)"
                announceStatus("Added ^\(success.blockID) to \(success.relativeTarget) and inserted \(replacement)")
                requestFocus(.editor)
                if followUp == .submit || followUp == .submitAndOpen {
                    submitAfterCurrentAnalysis(openAfterCapture: followUp == .submitAndOpen)
                }
                return
            }
            if case .wikilinkTask(_, _, _, let followUp, _, _, _) = prompt.purpose {
                // Splice Bob's backend-formatted Task Wikilink replacement
                // verbatim: it carries the quoting and case the app must
                // never rebuild.
                guard let replacement = success.wikilinkReplacement, !replacement.isEmpty else {
                    prompt.isSaving = false
                    prompt.errorMessage = "This Bob is too old for (( links. Update Bob first."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                guard let range = stringRange(in: prompt.draftSnapshot, byteRange: prompt.replacementRange) else {
                    prompt.isSaving = false
                    prompt.errorMessage = "Completion range is stale. Return to the task list and choose again."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                var text = prompt.draftSnapshot
                text.replaceSubrange(range, with: replacement)
                let cursor = prompt.replacementRange.start + replacement.utf8.count
                guard stringRange(in: text, start: cursor, end: cursor) != nil else {
                    prompt.isSaving = false
                    prompt.errorMessage = "Completion cursor is stale. Return to the task list and choose again."
                    taskIDPrompt = prompt
                    statusText = "Add block ID failed"
                    requestFocus(.taskIDPromptBlockID)
                    return
                }
                clearTaskIDPrompt()
                dismissCompletion()
                suppressedCompletionAcceptanceDraft = text
                setPlainDraft(
                    text,
                    cursorUTF8Offset: cursor,
                    suppressSelectionCallbacks: true
                )
                scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
                statusText = "Added ^\(success.blockID) to \(success.relativeTarget)"
                announceStatus("Added ^\(success.blockID) to \(success.relativeTarget) and inserted \(replacement)")
                requestFocus(.editor)
                if followUp == .submit || followUp == .submitAndOpen {
                    submitAfterCurrentAnalysis(openAfterCapture: followUp == .submitAndOpen)
                }
                return
            }
            guard let range = stringRange(in: prompt.draftSnapshot, byteRange: prompt.replacementRange) else {
                prompt.isSaving = false
                prompt.errorMessage = "Completion range is stale. Return to the task list and choose again."
                taskIDPrompt = prompt
                statusText = "Add block ID failed"
                requestFocus(.taskIDPromptBlockID)
                return
            }

            var text = prompt.draftSnapshot
            text.replaceSubrange(range, with: success.blockID)
            let cursor = prompt.replacementRange.start + success.blockID.utf8.count
            guard stringRange(in: text, start: cursor, end: cursor) != nil else {
                prompt.isSaving = false
                prompt.errorMessage = "Completion cursor is stale. Return to the task list and choose again."
                taskIDPrompt = prompt
                statusText = "Add block ID failed"
                requestFocus(.taskIDPromptBlockID)
                return
            }

            clearTaskIDPrompt()
            dismissCompletion()
            suppressedCompletionAcceptanceDraft = text
            setPlainDraft(
                text,
                cursorUTF8Offset: cursor,
                suppressSelectionCallbacks: true
            )
            scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
            statusText = "Added ^\(success.blockID) to \(success.relativeTarget)"
            requestFocus(.editor)
        case .failure(let failure):
            prompt.isSaving = false
            prompt.errorMessage = failure.error
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
        }
    }

    /// Splices a successful similar-tasks ID assignment. `capture-task-id
    /// --route` returns the same replacements Bob's `capture-related`
    /// contract carries, so this splices through the shared strip helper and
    /// then runs the live preview again, exactly like a direct strip action.
    private func completeSimilarTaskIDAssignment(
        prompt: inout CaptureTaskIDPromptState,
        success: CaptureTaskIDSuccess,
        action: CaptureRelatedAction,
        itemIndex: Int
    ) {
        let replacement: String?
        switch action {
        case .relate:
            replacement = success.relationToReplacement
        case .note:
            replacement = success.parentReplacement
        case .needs:
            replacement = success.dependencyReplacement
        case .blocks:
            replacement = success.blockedTaskReplacement
        case .addTo, .open, .discard, .unknown:
            replacement = nil
        }
        guard let replacement, !replacement.isEmpty else {
            prompt.isSaving = false
            prompt.errorMessage = "This Bob is too old for similar-tasks links. Update Bob first."
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
            return
        }
        guard prompt.draftSnapshot == plainDraft,
              let item = similarItemAnchors[itemIndex],
              similarAnchorsDraft == plainDraft,
              let focused = focusedSimilarRow(),
              focused.itemIndex == itemIndex,
              let edited = SimilarTasksBandEdits.editedDraftWithReplacement(
                  plainDraft,
                  item: item,
                  replacement: replacement,
                  action: action
              )
        else {
            prompt.isSaving = false
            prompt.errorMessage = "Similar tasks changed. Return to the band and choose again."
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
            return
        }
        // The shared helper already rejected stale anchors; only the cursor
        // offset still needs a validity check before it becomes selection.
        let text = edited.text
        let cursor = edited.cursorUTF8
        guard stringRange(in: text, start: cursor, end: cursor) != nil else {
            prompt.isSaving = false
            prompt.errorMessage = "Similar tasks changed. Return to the band and choose again."
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
            return
        }
        let announcement = SimilarTasksBandEdits.announcement(for: action, title: focused.match.title)
        clearTaskIDPrompt()
        dismissCompletion()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: cursor, suppressSelectionCallbacks: true)
        // The ID assignment already wrote the vault; unfocus collapses any
        // revealed rows back to the capped band.
        unfocusSimilarRow(applyPending: false)
        scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
        statusText = "Added ^\(success.blockID) to \(success.relativeTarget)"
        announceStatus(announcement)
        requestFocus(.editor)
    }

    private func completeBlockedTaskIDAssignment(
        prompt: inout CaptureTaskIDPromptState,
        success: CaptureTaskIDSuccess,
        followUp: CaptureTaskLinkFollowUp
    ) {
        guard let replacement = success.blockedTaskReplacement, !replacement.isEmpty else {
            prompt.isSaving = false
            prompt.errorMessage = "This Bob is too old for blocked-task picks. Update Bob first."
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
            return
        }
        guard prompt.draftSnapshot == plainDraft,
              let range = stringRange(in: prompt.draftSnapshot, byteRange: prompt.replacementRange)
        else {
            prompt.isSaving = false
            prompt.errorMessage = "Completion range is stale. Return to the task list and choose again."
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
            return
        }
        var text = prompt.draftSnapshot
        text.replaceSubrange(range, with: replacement)
        let cursor = prompt.replacementRange.start + replacement.utf8.count
        guard stringRange(in: text, start: cursor, end: cursor) != nil else {
            prompt.isSaving = false
            prompt.errorMessage = "Completion cursor is stale. Return to the task list and choose again."
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
            return
        }
        clearTaskIDPrompt()
        dismissCompletion()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: cursor, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
        statusText = "Added ^\(success.blockID) to \(success.relativeTarget)"
        announceStatus("Added ^\(success.blockID) to \(success.relativeTarget) and inserted \(replacement)")
        requestFocus(.editor)
        if followUp == .submit || followUp == .submitAndOpen {
            submitAfterCurrentAnalysis(openAfterCapture: followUp == .submitAndOpen)
        }
    }

    private func completeRelationIDAssignment(
        prompt: inout CaptureTaskIDPromptState,
        success: CaptureTaskIDSuccess,
        followUp: CaptureTaskLinkFollowUp,
        direction: DependencyPickerDirection
    ) {
        let replacement: String?
        switch direction {
        case .linkedFrom:
            replacement = success.relationFromReplacement
        default:
            replacement = success.relationToReplacement
        }
        guard let replacement, !replacement.isEmpty else {
            prompt.isSaving = false
            prompt.errorMessage = "This Bob is too old for ~ links. Update Bob first."
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
            return
        }
        guard prompt.draftSnapshot == plainDraft,
              let range = stringRange(in: prompt.draftSnapshot, byteRange: prompt.replacementRange)
        else {
            prompt.isSaving = false
            prompt.errorMessage = "Completion range is stale. Return to the task list and choose again."
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
            return
        }
        var text = prompt.draftSnapshot
        text.replaceSubrange(range, with: replacement)
        let cursor = prompt.replacementRange.start + replacement.utf8.count
        guard stringRange(in: text, start: cursor, end: cursor) != nil else {
            prompt.isSaving = false
            prompt.errorMessage = "Completion cursor is stale. Return to the task list and choose again."
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
            return
        }
        clearTaskIDPrompt()
        dismissCompletion()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: cursor, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
        statusText = "Added ^\(success.blockID) to \(success.relativeTarget)"
        announceStatus("Added ^\(success.blockID) to \(success.relativeTarget) and inserted \(replacement)")
        requestFocus(.editor)
        if followUp == .submit || followUp == .submitAndOpen {
            submitAfterCurrentAnalysis(openAfterCapture: followUp == .submitAndOpen)
        }
    }

    /// Splices a successful parent-task ID assignment. Vault requires Bob's
    /// `parent_replacement`; scoped inserts the returned ID into the ID-only
    /// range. A missing vault field asks the user to update Bob and keeps
    /// the draft. Rechecks draft identity after the async assignment.
    private func completeParentTaskIDAssignment(
        prompt: inout CaptureTaskIDPromptState,
        success: CaptureTaskIDSuccess,
        followUp: CaptureTaskLinkFollowUp,
        scope: ParentTaskPickerScope
    ) {
        guard prompt.draftSnapshot == plainDraft else {
            prompt.isSaving = false
            prompt.errorMessage = "Draft changed. Return to the task list and choose again."
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
            return
        }
        let insertion: String
        if scope == .vault {
            guard let parentReplacement = success.parentReplacement, !parentReplacement.isEmpty else {
                prompt.isSaving = false
                prompt.errorMessage = "This Bob is too old for parent-task picks. Update Bob first."
                taskIDPrompt = prompt
                statusText = "Add block ID failed"
                requestFocus(.taskIDPromptBlockID)
                return
            }
            insertion = parentReplacement
        } else {
            insertion = success.blockID
        }
        guard let range = stringRange(in: prompt.draftSnapshot, byteRange: prompt.replacementRange) else {
            prompt.isSaving = false
            prompt.errorMessage = "Completion range is stale. Return to the task list and choose again."
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
            return
        }
        var text = prompt.draftSnapshot
        text.replaceSubrange(range, with: insertion)
        let cursor = prompt.replacementRange.start + insertion.utf8.count
        guard stringRange(in: text, start: cursor, end: cursor) != nil else {
            prompt.isSaving = false
            prompt.errorMessage = "Completion cursor is stale. Return to the task list and choose again."
            taskIDPrompt = prompt
            statusText = "Add block ID failed"
            requestFocus(.taskIDPromptBlockID)
            return
        }
        clearTaskIDPrompt()
        dismissCompletion()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(
            text,
            cursorUTF8Offset: cursor,
            suppressSelectionCallbacks: true
        )
        scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
        statusText = "Added ^\(success.blockID) to \(success.relativeTarget)"
        announceStatus("Added ^\(success.blockID) to \(success.relativeTarget) and inserted \(insertion)")
        requestFocus(.editor)
        if followUp == .submit || followUp == .submitAndOpen {
            submitAfterCurrentAnalysis(openAfterCapture: followUp == .submitAndOpen)
        }
    }

    private func failTaskIDAssignment(requestID: UUID, error: Error) {
        guard activeTaskIDRequestID == requestID,
              var prompt = taskIDPrompt
        else {
            return
        }
        activeTaskIDRequestID = nil
        prompt.isSaving = false
        prompt.errorMessage = String(describing: error)
        taskIDPrompt = prompt
        statusText = "Add block ID failed"
        requestFocus(.taskIDPromptBlockID)
    }

    private func completeSubmit(
        requestID: UUID,
        response: CaptureCommandResponse,
        openAfterCapture: Bool,
        draft: String,
        choiceSeed: String,
        processClientIdentity: String
    ) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        isSubmitting = false
        let routeContext = activeInboxRouteSubmitContext
        activeInboxRouteSubmitContext = nil

        switch response {
        case .success(let success):
            let captures = success.normalizedCaptures
            let openPlan = CaptureOpenPlan(openNotes: success.openNotes, captures: captures)
            invalidateAnalysis()
            rememberRefParent(captures: captures)
            lastSuccess = captures.first
            lastSuccessResults = captures
            lastSuccessGlobalDestination = success.globalDestination
            previewPullInSnapshot = nil
            clearPreviewOutputs()
            lastPreviewTransferVerb = nil
            transferOwnedStatusText = nil
            errorMessage = nil
            errorCode = nil
            setPlainDraft("")
            suppressedCompletionAcceptanceDraft = nil
            priorityRollSeed = nil
            parseDiagnostics = []
            parsedTemplate = nil
            lastAppliedParseDraft = nil
            lastAppliedParseGeneration = nil
            similarTasksParseItems = []
            similarTasksFolded = false
            completionResponse = nil
            completionDraftSnapshot = nil
            fileUnderActive = false
            clearPickerState()
            previewState = .idle
            if let presentation = Self.soleTogglePresentation(for: captures) {
                statusText = presentation.voiceOverAnnouncement
            } else if let presentation = Self.soleTaskCompletePresentation(for: captures) {
                statusText = presentation.statusText
            } else if let presentation = Self.soleResetPresentation(for: captures) {
                statusText = presentation.statusText
            } else if let presentation = Self.soleClosePresentation(for: captures) {
                statusText = presentation.statusText
            } else if let presentation = Self.soleSessionStartPresentation(for: captures) {
                statusText = presentation.statusText
            } else if let presentation = Self.soleRefPresentation(for: captures) {
                statusText = presentation.statusText
            } else if let summary = Self.soleRecordNoteSummary(for: captures) {
                let headline = CaptureRecordPreviewPresentation.headline(for: summary)
                let detail = CaptureRecordPreviewPresentation.detail(for: summary)
                statusText = "\(headline) · \(detail)"
            } else if captures.count == 1,
                      let notebook = captures.first,
                      CaptureNotebookPresentation.isNotebook(notebook)
            {
                statusText = "Captured → \(CaptureNotebookPresentation.headline(for: notebook))"
            } else {
                statusText = captureStatus(
                    prefix: "Captured",
                    captures: captures,
                    globalDestination: success.globalDestination
                )
            }
            if let templateStatus = Self.templateCaptureStatus(success.template) {
                statusText += templateStatus
            }
            if let routeStatus = CaptureInboxRoutePresentation.successNoticeSuffix(
                route: success.inboxRoute
            ) {
                statusText += " \(routeStatus)"
            }
            templateOrigin = nil
            successAnnouncementTick += 1
            savedTemplateShelf.refresh(reason: .submit)
            postCaptureSuccess(
                captures: captures,
                globalDestination: success.globalDestination,
                openPlan: openPlan
            )
            if openAfterCapture,
               let url = ObsidianOpenURL.openNotesURL(for: openPlan)
            {
                noteOpener(url) { [weak self] error in
                    guard let self, let error else { return }
                    self.postCaptureOpenFailure(message: error.localizedDescription)
                }
            }
            panelDismisser()
        case .failure(let failure):
            if showRecordRefusal(failure) {
                return
            }
            if showBareAlbumRefusal(failure) {
                return
            }
            if showEmptyNotePull(failure) {
                return
            }
            if failure.code == "pomodoro_past_windows_changed" {
                guard plainDraft == draft,
                      processClient?.identityToken == processClientIdentity
                else {
                    return
                }
                scheduleAnalysis(
                    cursorUTF8Offset: nil,
                    requestCompletion: false,
                    trigger: .selection
                )
                errorMessage = failure.error
                errorCode = failure.code
                statusText = failure.error
                announceStatus(failure.error)
                return
            }
            if failure.code == "pomodoro_override_refused" {
                errorMessage = nil
                errorCode = nil
                overrideRefusalDraft = draft
                scheduleAnalysis(
                    cursorUTF8Offset: nil,
                    requestCompletion: false,
                    trigger: .selection
                )
                statusText = "A Pomodoro is running — review the override, then press Return again"
                return
            }
            if let code = failure.code, code.hasPrefix("move_choice_") {
                guard plainDraft == draft,
                    processClient?.identityToken == processClientIdentity
                else { return }
                if let report = failure.moveChoice, report.supported,
                    let slot = report.slots.first
                {
                    let snapshot = CapturePullInPreviewSnapshot(
                        draft: draft, clientIdentity: processClientIdentity,
                        seed: choiceSeed, generation: analysisGeneration, requestID: requestID,
                        pullIn: failure.pullIn, inboxRoute: failure.inboxRoute,
                        planBudget: nil, offers: failure.offers, stillBlocked: [],
                        hasOverride: routeContext?.hasOverride == true, moveChoice: report
                    )
                    openMoveChoice(
                        slot: slot, preview: snapshot, openAfterCapture: openAfterCapture,
                        stale: code == "move_choice_stale", needsPreview: true
                    )
                    if code != "move_choice_required", code != "move_choice_stale" {
                        moveChoiceMessage = failure.error
                        announceStatus(failure.error)
                    }
                } else {
                    errorMessage = failure.error
                    errorCode = failure.code
                    announceStatus(failure.error)
                }
                return
            }
            if failure.code == "pull_in_choice_required" {
                guard let processClient,
                    plainDraft == draft,
                    processClient.identityToken == processClientIdentity,
                    let pullIn = failure.pullIn,
                    pullIn.supported
                else {
                    errorMessage =
                        "Bob's successor offer response was incomplete or stale. Preview again before submitting."
                    errorCode = nil
                    statusText = "Successor offers need refresh"
                    return
                }
                let opened = openPullInChoice(
                    offers: failure.offers,
                    stillBlocked: [],
                    pullIn: pullIn,
                    planBudget: nil,
                    draft: draft,
                    processClientIdentity: processClientIdentity,
                    openAfterCapture: openAfterCapture,
                    seed: choiceSeed,
                    generation: analysisGeneration,
                    requestID: requestID,
                    moveInSelection: routeContext?.moveInSelection
                )
                if !opened {
                    errorMessage = "Bob requested a successor choice but returned no usable offer keys. Preview again before submitting."
                    errorCode = nil
                    statusText = "Successor offers need refresh"
                }
                return
            }
            if failure.code == "inbox_route_choice_required" {
                guard let processClient,
                      plainDraft == draft,
                      processClient.identityToken == processClientIdentity,
                      let route = failure.inboxRoute,
                      route.supported,
                      let routeContext,
                      inboxRouteContextIsCurrent(routeContext)
                else {
                    errorMessage = "Bob's inbox route response was incomplete or stale. Preview again before submitting."
                    errorCode = nil
                    statusText = "Inbox routes need refresh"
                    return
                }
                if openInboxRouteChoice(route, context: routeContext) {
                    return
                }
                errorMessage = "Bob requested an inbox route choice but returned no usable candidates. Preview again before submitting."
                errorCode = nil
                statusText = "Inbox routes need refresh"
                return
            }
            if failure.code == "inbox_route_refused" {
                guard let processClient,
                      plainDraft == draft,
                      processClient.identityToken == processClientIdentity,
                      let route = failure.inboxRoute,
                      route.supported,
                      let routeContext,
                      inboxRouteContextIsCurrent(routeContext)
                else {
                    errorMessage = failure.error
                    errorCode = failure.code
                    refuseStatus("Capture failed")
                    notificationService?.notifyCaptureFailure(message: failure.error)
                    return
                }
                if openInboxRouteChoice(
                    route,
                    context: routeContext,
                    refused: failure.refused,
                    refusalMessage: failure.refused == nil ? failure.error : nil
                ) {
                    return
                }
            }
            if failure.code == "inbox_route_stale" {
                inboxRouteChoice = nil
                inboxRouteChoiceContext = nil
                clearEditorInputLockIfFree()
                previewPullInSnapshot = nil
                errorMessage = nil
                errorCode = nil
                announceStatus("Inbox tasks changed since the preview; press Return to choose again")
                return
            }
            if let code = failure.code,
                ["offer_close_stale", "offer_close_refused", "offer_verdict_conflict"]
                    .contains(code)
            {
                if reopenPullInChoiceAfterOfferRefusal(
                    failure: failure,
                    draft: draft,
                    processClientIdentity: processClientIdentity,
                    openAfterCapture: openAfterCapture,
                    choiceSeed: choiceSeed,
                    remembered: routeContext?.pullInChoiceForBack
                ) {
                    return
                }
            }
            if failure.code == nil,
                failure.error.hasPrefix("stale, unknown, or out-of-range --pull-in pick:")
            {
                if reopenPullInChoiceAfterStalePick(
                    failure: failure,
                    draft: draft,
                    processClientIdentity: processClientIdentity,
                    openAfterCapture: openAfterCapture,
                    choiceSeed: choiceSeed,
                    remembered: routeContext?.pullInChoiceForBack
                ) {
                    return
                }
            }
            previewPullInSnapshot = nil
            errorMessage = failure.error
            errorCode = failure.code
            refuseStatus("Capture failed")
            notificationService?.notifyCaptureFailure(message: failure.error)
        }
    }

    private func postCaptureSuccess(
        captures: [CaptureCommandSuccess],
        globalDestination: CaptureGlobalDestination?,
        openPlan: CaptureOpenPlan
    ) {
        if let captureSuccessNotifier {
            captureSuccessNotifier(captures, globalDestination, openPlan)
        } else {
            notificationService?.notifyCaptureSuccess(
                captures: captures,
                globalDestination: globalDestination,
                openPlan: openPlan
            )
        }
    }

    private func postCaptureOpenFailure(message: String) {
        if let captureOpenFailureNotifier {
            captureOpenFailureNotifier(message)
        } else {
            notificationService?.notifyCaptureOpenFailure(message: message)
        }
    }

    private func failSubmit(requestID: UUID, error: Error) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        isSubmitting = false
        activeInboxRouteSubmitContext = nil
        previewPullInSnapshot = nil

        let message = String(describing: error)
        errorMessage = message
        errorCode = nil
        refuseStatus("Capture failed")
        notificationService?.notifyCaptureFailure(message: message)
    }

    private func completePreview(
        requestID: UUID,
        response: CaptureCommandResponse,
        draft: String,
        seed: String,
        generation: UInt64,
        processClient: BobProcessClient,
        processClientIdentity: String
    ) {
        guard activeRequestID == requestID else {
            return
        }
        guard generation == analysisGeneration,
              plainDraft == draft,
              self.processClient === processClient,
              processClient.identityToken == processClientIdentity
        else {
            activeRequestID = nil
            isPreviewing = false
            return
        }
        activeRequestID = nil
        isPreviewing = false

        switch response {
        case .success(let success):
            let captures = success.normalizedCaptures
            previewPullInSnapshot = makePullInPreviewSnapshot(
                success: success,
                captures: captures,
                draft: draft,
                processClientIdentity: processClientIdentity,
                seed: seed,
                generation: generation,
                requestID: requestID
            )
            assignPreviewOutputs(
                captures: captures,
                openNotes: success.openNotes,
                globalDestination: success.globalDestination,
                previewDraft: draft
            )
            errorMessage = nil
            errorCode = nil
            if let presentation = Self.soleResetPresentation(for: captures) {
                statusText = presentation.statusText
            } else if let presentation = Self.soleClosePresentation(for: captures) {
                statusText = presentation.statusText
            } else if let presentation = Self.soleSessionStartPresentation(for: captures) {
                statusText = presentation.statusText
            } else if let presentation = Self.soleTogglePresentation(for: captures) {
                statusText = presentation.statusText
            } else if let presentation = Self.soleTaskCompletePresentation(for: captures) {
                statusText = presentation.statusText
            } else if let presentation = Self.soleRefPresentation(for: captures) {
                statusText = presentation.statusText
            } else {
                statusText = captureStatus(
                    prefix: "Preview",
                    captures: captures,
                    globalDestination: success.globalDestination
                )
            }
            consumeTransferOwnedStatus()
        case .failure(let failure):
            if showTransferFailure(failure, parseMode: latestParse?.mode) {
                return
            }
            if showRecordRefusal(failure) {
                return
            }
            if showBareAlbumRefusal(failure) {
                return
            }
            if showEmptyNotePull(failure) {
                return
            }
            // A failed explicit dry run drops the preview result for the same
            // reason `failPreview` does: no stale card beside the red error.
            clearPreviewOutputs()
            previewPullInSnapshot = nil
            errorMessage = failure.error
            errorCode = failure.code
            refuseStatus("Preview failed")
        }
    }

    private func makePullInPreviewSnapshot(
        success: CaptureCommandSuccess,
        captures: [CaptureCommandSuccess],
        draft: String,
        processClientIdentity: String,
        seed: String,
        generation: UInt64,
        requestID: UUID?
    ) -> CapturePullInPreviewSnapshot {
        var offers: [TaskCompleteUnblocked] = []
        var stillBlocked: [TaskCompleteStillBlocked] = []
        for capture in captures {
            if let complete = capture.taskComplete {
                offers.append(contentsOf: complete.unblocked)
                offers.append(contentsOf: complete.keepMoving)
                stillBlocked.append(contentsOf: complete.stillBlocked)
            }
            if let close = capture.pomodoroClose {
                offers.append(contentsOf: close.unblocked)
                offers.append(contentsOf: close.keepMoving)
                stillBlocked.append(contentsOf: close.stillBlocked)
            }
            if let past = capture.pomodoroPast {
                offers.append(contentsOf: past.close.unblocked)
                offers.append(contentsOf: past.close.keepMoving)
                stillBlocked.append(contentsOf: past.close.stillBlocked)
            }
            if let projectNote = capture.projectNote, projectNote.form == "offer" {
                offers.append(contentsOf: projectNote.successors)
            }
            offers.append(contentsOf: capture.allNotePullRows)
            // Complete-label commits offer successors exactly like `!`:
            // the close carries the same `task_complete` offers.
            for relationComplete in capture.relationCompletes {
                guard let complete = relationComplete.taskComplete else {
                    continue
                }
                offers.append(contentsOf: complete.unblocked)
                offers.append(contentsOf: complete.keepMoving)
                stillBlocked.append(contentsOf: complete.stillBlocked)
            }
            // Relation offers via the shared helpers, including item-level
            // toggle offers and nested complete-label closes. Deduped below
            // by Bob's opaque key, preserving canonical numbering.
            offers.append(contentsOf: capture.allRelationSuccessors)
        }
        offers.append(contentsOf: success.allRelationSuccessors)
        if let parent = success.moveChoice?.slots.first?.parent,
            rememberedMoveChoice?.slot.parent != parent
        {
            rememberedMoveChoice = nil
        }
        return CapturePullInPreviewSnapshot(
            draft: draft,
            clientIdentity: processClientIdentity,
            seed: seed,
            generation: generation,
            requestID: requestID,
            pullIn: success.pullIn,
            inboxRoute: success.inboxRoute,
            planBudget: success.planBudget,
            offers: Self.uniquePullInRows(offers),
            stillBlocked: stillBlocked,
            hasOverride: captures.contains { capture in
                CapturePomodoroStartPresentation(capture: capture)?.isOverride == true
            },
            moveChoice: success.moveChoice
        )
    }

    /// A batch's toggle presentation, only when it is exactly one `task_toggle` item —
    /// the same single-item gate `captureStatus`/`captureSummary` use before falling
    /// back to their generic per-kind wording.
    private static func soleTogglePresentation(
        for captures: [CaptureCommandSuccess]
    ) -> CaptureTogglePresentation? {
        guard captures.count == 1 else {
            return nil
        }
        return CaptureTogglePresentation(capture: captures[0])
    }

    private static func templateCaptureStatus(_ template: CaptureTemplateSummary?) -> String? {
        guard let template else {
            return nil
        }
        if let reason = template.notSaved {
            return " · Template not saved: \(reason)"
        }
        guard let saved = template.saved else {
            return nil
        }
        switch saved.status {
        case .new:
            return " · Template saved — ⌃T to reuse"
        case .replaced:
            return " · Template updated"
        case .updated:
            return nil
        case .unknown:
            return " · Template saved"
        }
    }

    /// A batch's task-complete presentation, only when it is exactly one
    /// `task_complete` item — the same single-item gate as the toggle
    /// presentation.
    private static func soleTaskCompletePresentation(
        for captures: [CaptureCommandSuccess]
    ) -> CaptureTaskCompletePresentation? {
        guard captures.count == 1 else {
            return nil
        }
        return CaptureTaskCompletePresentation(capture: captures[0])
    }

    /// A batch's link presentation, only when it is exactly one `pomodoro_link`
    /// item — the same single-item gate as the toggle presentation.
    private static func soleLinkPresentation(
        for captures: [CaptureCommandSuccess]
    ) -> CapturePomodoroLinkPresentation? {
        guard captures.count == 1 else {
            return nil
        }
        return CapturePomodoroLinkPresentation(capture: captures[0])
    }

    /// A batch's reference presentation, only when it is exactly one `ref`
    /// item — the same single-item gate as the toggle presentation.
    private static func soleRefPresentation(
        for captures: [CaptureCommandSuccess]
    ) -> CaptureRefPresentation? {
        guard captures.count == 1 else {
            return nil
        }
        return CaptureRefPresentation(capture: captures[0])
    }

    /// The committed per-item `record_note` summary for a lone record
    /// capture, built from Bob's metadata rather than the cleared editor.
    /// Older Bob falls back to the generic capture status.
    private static func soleRecordNoteSummary(
        for captures: [CaptureCommandSuccess]
    ) -> CaptureRecordNoteSummary? {
        guard captures.count == 1,
              captures[0].kind == "record_note" || captures[0].kind == "record_update"
        else {
            return nil
        }
        return captures[0].recordNote
    }

    private static func soleClosePresentation(
        for captures: [CaptureCommandSuccess]
    ) -> CapturePomodoroClosePresentation? {
        guard captures.count == 1 else {
            return nil
        }
        return CapturePomodoroClosePresentation(capture: captures[0])
    }

    private static func soleResetPresentation(
        for captures: [CaptureCommandSuccess]
    ) -> CapturePomodoroResetPresentation? {
        guard captures.count == 1 else {
            return nil
        }
        return CapturePomodoroResetPresentation(capture: captures[0])
    }

    /// A batch's session-start presentation, only when it is exactly one
    /// whole-item `=`/`=<X>` start — the same single-item gate as the close
    /// presentation.
    private static func soleSessionStartPresentation(
        for captures: [CaptureCommandSuccess]
    ) -> CapturePomodoroStartPresentation? {
        guard captures.count == 1,
              CapturePomodoroStartPresentation.isSessionStart(captures[0])
        else {
            return nil
        }
        return CapturePomodoroStartPresentation(capture: captures[0])
    }

    private func failPreview(
        requestID: UUID,
        error: Error,
        draft: String,
        generation: UInt64,
        processClient: BobProcessClient,
        processClientIdentity: String
    ) {
        guard activeRequestID == requestID else {
            return
        }
        guard generation == analysisGeneration,
              plainDraft == draft,
              self.processClient === processClient,
              processClient.identityToken == processClientIdentity
        else {
            activeRequestID = nil
            isPreviewing = false
            return
        }
        activeRequestID = nil
        isPreviewing = false
        // A failed live dry run must never leave a stale card beside the red
        // error: a close preview's `closed_at` and timing describe a moment
        // that has already passed, so drop the whole preview result.
        clearPreviewOutputs()
        previewPullInSnapshot = nil
        errorMessage = String(describing: error)
        errorCode = nil
        refuseStatus("Preview failed")
    }

    /// Turns Bob's decided empty-pull refusal into the calm preview card.
    /// The CLI payload supplies both the note name and fold counts.
    @discardableResult
    private func showEmptyNotePull(_ failure: CaptureCommandFailure) -> Bool {
        guard failure.code == "nothing_to_pull_in",
              let notePull = failure.notePull,
              let presentation = CaptureNotePullEmptyPresentation(notePull: notePull)
        else {
            return false
        }
        clearPreviewOutputs()
        previewPullInSnapshot = nil
        closePendingText = nil
        closePendingAction = "Close"
        emptyNotePullPresentation = presentation
        previewState = .failed(failure.error)
        errorMessage = nil
        errorCode = nil
        statusText = presentation.title
        return true
    }

    /// Incomplete record drafts that Bob refuses get an inline card with
    /// the message, missing/invalid field details, and the ready-to-copy
    /// draft. The draft is never applied, and the user keeps the entire
    /// original draft, including the other items in a mixed capture. An
    /// obsolete successful note preview is cleared beside the card.
    @discardableResult
    private func showRecordRefusal(_ failure: CaptureCommandFailure) -> Bool {
        let labels = (latestParse?.record?.fields ?? []).reduce(
            into: [String: String]()
        ) { partial, field in
            partial[field.key] = field.label
        }
        guard
            let presentation = CaptureRecordRefusalPresentation(
                failure: failure,
                fieldLabels: labels
            )
        else {
            return false
        }
        clearPreviewOutputs()
        previewPullInSnapshot = nil
        closePendingText = nil
        closePendingAction = "Close"
        recordRefusalPresentation = presentation
        previewState = .failed(failure.error)
        errorMessage = nil
        errorCode = nil
        refuseStatus(failure.error)
        return true
    }

    /// A bare album route (`Blaze @eat`) is an expected teaching state,
    /// not a failure: the footer keeps Bob's teach text beside the
    /// one-key `@eat/` rewrite button, with no red callout, no
    /// Retry-that-submits, and no duplicated preview-pane message. Like
    /// the older-Bob transfer path, the preview itself stays quiet.
    @discardableResult
    private func showBareAlbumRefusal(_ failure: CaptureCommandFailure) -> Bool {
        guard failure.code == CaptureBareAlbumRefusal.code else {
            return false
        }
        clearPreviewOutputs()
        previewPullInSnapshot = nil
        closePendingText = nil
        closePendingAction = "Close"
        errorMessage = nil
        errorCode = nil
        previewState = .idle
        refuseStatus(failure.error)
        return true
    }

    /// Transfer destination needs are preview states. Bob's additive payload
    /// gives the calm card; older Bob keeps the diagnostic in the muted footer.
    /// Complete transfer drafts that Bob refuses get a designed card instead
    /// of the generic red preview callout.
    @discardableResult
    private func showTransferFailure(
        _ failure: CaptureCommandFailure,
        parseMode: String?
    ) -> Bool {
        if failure.code?.hasPrefix("incomplete_transfer") == true {
            clearPreviewOutputs()
            previewPullInSnapshot = nil
            closePendingText = nil
            closePendingAction = "Close"
            errorMessage = nil
            errorCode = nil
            if let presentation = failure.transferPending.flatMap(
                CaptureTransferPendingPresentation.init(pending:)
            ) {
                transferPendingPresentation = presentation
                previewState = .failed(failure.error)
                statusText = presentation.title
                transferOwnedStatusText = presentation.title
            } else {
                // Prior Bob versions have the diagnostic, but not the additive
                // pending payload. Keep the preview itself quiet in that case.
                previewState = .idle
                statusText = failure.error
                transferOwnedStatusText = failure.error
            }
            return true
        }

        if let code = failure.code, code.contains("merge_in") {
            let rewrites = latestParse?.diagnostics.compactMap(\.rewrite) ?? []
            if let presentation = CaptureMergeInRefusalPresentation(
                failure: failure,
                rewrites: rewrites
            ) {
                clearPreviewOutputs()
                previewPullInSnapshot = nil
                closePendingText = nil
                closePendingAction = "Close"
                mergeInRefusalPresentation = presentation
                previewState = .failed(failure.error)
                errorMessage = nil
                errorCode = nil
                statusText = failure.error
                transferOwnedStatusText = failure.error
                return true
            }
        }

        guard
            let presentation = CaptureTransferRefusalPresentation(
                failure: failure,
                parseMode: parseMode
            )
        else {
            return false
        }
        clearPreviewOutputs()
        previewPullInSnapshot = nil
        closePendingText = nil
        closePendingAction = "Close"
        transferRefusalPresentation = presentation
        previewState = .failed(failure.error)
        errorMessage = nil
        errorCode = nil
        statusText = presentation.verb.title
        transferOwnedStatusText = presentation.verb.title
        return true
    }

    private func setPlainDraft(
        _ text: String,
        cursorUTF8Offset: Int? = nil,
        suppressSelectionCallbacks: Bool = false
    ) {
        let previousDraft = plainDraft
        if previousDraft != text { invalidateMoveChoiceForEdit(text) }
        if text.isEmpty {
            templateOrigin = nil
        }
        if previousDraft != text {
            emptyNotePullPresentation = nil
            transferPendingPresentation = nil
            transferRefusalPresentation = nil
            mergeInRefusalPresentation = nil
            if let pullInChoice, pullInChoice.draftSnapshot != text {
                self.pullInChoice = nil
                clearEditorInputLockIfFree()
                requestFocus(.editor)
            }
            if let context = inboxRouteChoiceContext, context.draft != text {
                discardInboxRouteChoiceForInvalidation()
            }
            if let context = activeInboxRouteSubmitContext, context.draft != text {
                activeInboxRouteSubmitContext = nil
            }
            if previewPullInSnapshot?.draft != text {
                previewPullInSnapshot = nil
            }
        }
        closeListParseSnapshot = nil
        closeListAssistParsePending = false
        stopClipboardPolling()
        closeCommaProvenance.clear()
        lastProvenanceDraft = text
        isApplyingProgrammaticDraft = true
        attributedDraft = AttributedString(text)
        restoreSelection(
            cursorUTF8Offset: cursorUTF8Offset ?? text.utf8.count,
            suppressEditorCallbacks: suppressSelectionCallbacks
        )
        isApplyingProgrammaticDraft = false
        refreshCaptureGrammarGate()
    }

    private func refreshCaptureGrammarGate() {
        guard hasDraft else {
            captureGrammarWarning = nil
            return
        }
        let identityMatches =
            processClient.map { $0.identityToken == lastAppliedParseClientIdentity } ?? false
        let parseMatchesCurrentDraft =
            lastAppliedParseDraft == plainDraft && identityMatches
        if parseMatchesCurrentDraft, !CaptureGrammarGate.isCompatible(lastAppliedParseGrammar) {
            captureGrammarWarning = CaptureGrammarGate.blockedMessage
        } else {
            captureGrammarWarning = nil
        }
    }

    /// `completionGate` holds this analysis's completion request until that task
    /// settles. An accepted correction reschedules the analysis meanwhile, which
    /// supersedes this one; any other outcome completes as if ungated.
    /// `writtenRange` overrides the baseline-to-draft edit window; sigil-alias
    /// rewrites pass Bob's input→text range so auto-open still sees the typed
    /// separator when a superseded parse already advanced the baseline.
    private func scheduleAnalysis(
        cursorUTF8Offset: Int?,
        requestCompletion: Bool,
        trigger: CompletionTrigger,
        completionGate: Task<Void, Never>? = nil,
        writtenRange rewriteWrittenRange: CaptureRange? = nil,
        recordField: String? = nil,
        nextMissingRecordField: Bool = false,
        recordItemIndex: Int? = nil
    ) {
        if pullInChoice != nil {
            cancelPullInChoiceFromKeyboard()
        }
        if inboxRouteChoice != nil {
            discardInboxRouteChoiceForInvalidation()
        }
        guard let processClient else {
            statusText = "Bob is not resolved"
            return
        }

        cancelPendingExplicitSubmit()
        cancelLivePreviewRequest()

        let draft = plainDraft
        if overrideRefusalDraft != draft {
            overrideRefusalDraft = nil
        }
        let writtenRange = rewriteWrittenRange ?? (trigger == .edit
            ? captureWrittenByteRange(from: editAnalysisBaseline, to: draft)
            : nil)
        if let cursorUTF8Offset {
            guard cursorUTF8Offset >= 0,
                  cursorUTF8Offset <= draft.utf8.count,
                  stringRange(in: draft, start: cursorUTF8Offset, end: cursorUTF8Offset) != nil
            else {
                statusText = "Cursor is not on a UTF-8 boundary"
                return
            }
        }

        scheduleSimilarTasks(draft: draft)

        analysisGeneration &+= 1
        let generation = analysisGeneration
        recordReturnTask?.cancel()
        recordReturnTask = nil
        recordRequestSequence &+= 1
        let recordSequence = recordRequestSequence
        recordAnalysisRequest = CaptureRecordAnalysisRequest(
            draft: draft,
            generation: generation,
            sequence: recordSequence,
            processClientIdentity: processClient.identityToken,
            cursor: cursorUTF8Offset,
            itemIndex: recordItemIndex,
            fieldKey: recordField,
            nextMissingField: nextMissingRecordField
        )
        recordCompletionSnapshot = nil
        recordInteractionPending = recordInteractionPending
            || recordPresentation != nil
            || recordField != nil
            || nextMissingRecordField
        recordPresentation = nil
        let debounceNanoseconds = self.debounceNanoseconds
        analysisTask?.cancel()
        mergeInPendingRevision = nil
        previewState = .loading
        previewPullInSnapshot = nil
        // A changed draft can still have the prior response in these caches while
        // the debounce is running. Clear it before calculating the next preview so
        // the footer and preview card always describe the same draft.
        clearPreviewOutputs()
        closePendingText = nil
        closePendingAction = "Close"

        analysisTask = Task { [weak self, processClient] in
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                try Task.checkCancellation()

                let parse = try await CaptureSignpost.measure("parse") {
                    try await processClient.captureParse(draft)
                }
                try Task.checkCancellation()

                let pickerNeeded = Self.pickerNeed(in: parse)
                // A dangling `,`/`!` is an editing state, not a mistake: the
                // picker needs keep precedence, otherwise the live preview
                // runs on the trimmed draft instead of the doomed real one.
                let closePending = pickerNeeded == nil
                    ? Self.closePendingTrim(in: parse, draft: draft) : nil

                await MainActor.run {
                    guard self?.isCurrentAnalysis(generation) == true else {
                        return
                    }
                    self?.applyParse(
                        parse,
                        draft: draft,
                        generation: generation,
                        cursorUTF8: cursorUTF8Offset
                    )
                    if let need = pickerNeeded {
                        // An incomplete `^` is a state, not an error: skip the
                        // doomed live dry run and stay calm instead of flashing
                        // red "incomplete Pomodoro link" errors while picking.
                        self?.applyQuietIncompletePicker(need, parse: parse)
                    }
                }

                guard await self?.isCurrentAnalysis(generation) == true else {
                    return
                }

                var previewTask: Task<Void, Never>?
                if pickerNeeded == nil || pickerNeeded == .mergeInSource {
                    // A live clipboard read needs this same draft's accepted
                    // parse: a `%c` directive span on a compatible grammar. A
                    // bare `%`, escaped or literal `%c`, an older draft's
                    // span, or a missing/lower grammar keeps `--no-clip`.
                    let clipAuthorized =
                        CaptureGrammarGate.isCompatible(parse.grammar)
                        && parse.reportsClipDirective
                    previewTask = await self?.startLivePreview(
                        draft: draft,
                        previewDraft: closePending?.trimmed ?? draft,
                        pendingSeparator: closePending?.separator,
                        pendingAction: closePending?.action,
                        generation: generation,
                        processClient: processClient,
                        trigger: trigger,
                        clipAuthorized: clipAuthorized
                    )
                }

                if requestCompletion, let completionGate {
                    await completionGate.value
                    try Task.checkCancellation()
                    guard await self?.isCurrentAnalysis(generation) == true else {
                        return
                    }
                }

                let explicitRecordRequest = recordField != nil || nextMissingRecordField
                let shouldRequestCompletion: Bool
                if explicitRecordRequest {
                    shouldRequestCompletion = true
                } else if let cursorUTF8Offset, requestCompletion {
                    shouldRequestCompletion = await self?.shouldRequestCompletion(
                        parse: parse,
                        cursor: cursorUTF8Offset,
                        draft: draft
                    ) == true
                } else {
                    shouldRequestCompletion = false
                }
                if let cursorUTF8Offset, requestCompletion, shouldRequestCompletion
                {
                    if explicitRecordRequest,
                       CaptureRecordPresentation.make(parse: parse, cursor: cursorUTF8Offset)?
                           .record.assistVersion != 1
                    {
                        await MainActor.run {
                            guard self?.isCurrentAnalysis(generation) == true else {
                                return
                            }
                            self?.handleMissingCompletion(trigger: trigger)
                            self?.editAnalysisBaseline = draft
                        }
                        await previewTask?.value
                        return
                    }
                    if let cached = await self?.cachedRouteCompletion(
                        parse: parse,
                        cursor: cursorUTF8Offset,
                        draft: draft
                    ) {
                        await MainActor.run {
                            guard self?.isCurrentAnalysis(generation) == true else {
                                return
                            }
                            guard self?.recordCompletionDidArrive(
                                cached,
                                parse: parse,
                                draft: draft,
                                cursor: cursorUTF8Offset,
                                generation: generation,
                                processClient: processClient
                            ) == true else {
                                return
                            }
                            self?.applyNonActiveTaskCompletion(
                                cached,
                                draft: draft,
                                trigger: trigger
                            )
                            self?.editAnalysisBaseline = draft
                        }
                    } else {
                        do {
                            let completion = try await CaptureSignpost.measure("completion") {
                                try await processClient.captureComplete(
                                    draft,
                                    cursor: cursorUTF8Offset,
                                    nextMissingField: nextMissingRecordField,
                                    recordField: recordField
                                )
                            }
                            await self?.handleCompletionResponse(
                                completion,
                                parse: parse,
                                draft: draft,
                                cursor: cursorUTF8Offset,
                                trigger: trigger,
                                writtenRange: writtenRange,
                                generation: generation,
                                processClient: processClient
                            )
                            await MainActor.run {
                                guard self?.isCurrentAnalysis(generation) == true else {
                                    return
                                }
                                self?.editAnalysisBaseline = draft
                            }
                        } catch {
                            await MainActor.run {
                                guard self?.isCurrentAnalysis(generation) == true else {
                                    return
                                }
                                self?.statusText = String(describing: error)
                                self?.editAnalysisBaseline = draft
                            }
                        }
                    }
                } else {
                    await MainActor.run {
                        guard self?.isCurrentAnalysis(generation) == true else {
                            return
                        }
                        self?.handleMissingCompletion(trigger: trigger)
                        self?.editAnalysisBaseline = draft
                    }
                }

                await previewTask?.value
                try Task.checkCancellation()
                await MainActor.run {
                    self?.submitDeferredRewriteAfterAnalysis(
                        draft: draft,
                        generation: generation,
                        processClient: processClient
                    )
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    guard self?.isCurrentAnalysis(generation) == true else {
                        return
                    }
                    self?.previewState = .failed(String(describing: error))
                }
            }
        }
    }

    @discardableResult
    private func startCaptureRewrite(
        draft: String,
        cursorUTF8Offset: Int,
        triggeredCharacter: String = "",
        triggerTimestamp: TimeInterval = 0,
        expectsRelationDirectionToggle: Bool = false,
        deferSubmitForMeaningChangingAlias: Bool = false
    ) -> Task<Void, Never>? {
        guard let processClient else {
            return nil
        }

        finishMeaningChangingRewriteHold(didReceiveReply: false)
        rewriteGeneration &+= 1
        let generation = rewriteGeneration
        cancelPendingRewriteSubmit()
        deferredRewriteInputDraft = deferSubmitForMeaningChangingAlias ? draft : nil
        completedDeferredRewriteDraft = nil
        deferredRewriteEchoDraft = nil
        deferredRewriteEchoCursorUTF8 = nil
        rewriteExpectedCursorUTF8 = cursorUTF8Offset
        rewriteSawMatchingSelection = collapsedSelectionUTF8Offset() == cursorUTF8Offset
        rewriteTask?.cancel()
        let task = Task { [weak self, processClient] in
            do {
                let response = try await CaptureSignpost.measure("rewrite") {
                    try await processClient.captureRewrite(draft, cursor: cursorUTF8Offset)
                }
                try Task.checkCancellation()

                await MainActor.run {
                    self?.applyCaptureRewrite(
                        response,
                        draft: draft,
                        cursorUTF8Offset: cursorUTF8Offset,
                        triggeredCharacter: triggeredCharacter,
                        triggerTimestamp: triggerTimestamp,
                        expectsRelationDirectionToggle: expectsRelationDirectionToggle,
                        generation: generation,
                        processClient: processClient
                    )
                    if self?.rewriteGeneration == generation {
                        self?.rewriteTask = nil
                        if self?.deferredRewriteInputDraft == draft {
                            self?.deferredRewriteInputDraft = nil
                            if self?.plainDraft == response.text, response.changed {
                                self?.completedDeferredRewriteDraft = response.text
                            }
                        }
                        if self?.pendingRewriteSubmitIntent?.rewriteGeneration == generation,
                           self?.pendingRewriteSubmitIntent?.inputDraft == draft
                        {
                            if self?.completedDeferredRewriteDraft != self?.plainDraft {
                                self?.cancelPendingRewriteSubmit()
                            }
                        }
                    }
                    self?.finishMeaningChangingRewriteHold(
                        generation: generation,
                        didReceiveReply: true
                    )
                }
            } catch is CancellationError {
            } catch {
                // Rewriting is a typing assist. Parse, completion, and preview still run
                // on the original draft, so transport failures should not disturb the UI.
                await MainActor.run {
                    guard self?.rewriteGeneration == generation else {
                        return
                    }
                    self?.rewriteTask = nil
                    self?.cancelPendingRewriteSubmit()
                    self?.deferredRewriteInputDraft = nil
                    self?.completedDeferredRewriteDraft = nil
                    self?.deferredRewriteEchoDraft = nil
                    self?.deferredRewriteEchoCursorUTF8 = nil
                    self?.rewriteExpectedCursorUTF8 = nil
                    self?.rewriteSawMatchingSelection = false
                    self?.pendingHashAlias = nil
                    self?.finishMeaningChangingRewriteHold(
                        generation: generation,
                        didReceiveReply: false
                    )
                }
            }
        }
        rewriteTask = task
        if deferSubmitForMeaningChangingAlias {
            meaningChangingRewriteHoldGeneration = generation
            if meaningChangingRewriteHoldDidStart?(generation) != true {
                meaningChangingRewriteHoldGeneration = nil
            }
        }
        return task
    }

    private static func isMeaningChangingAlias(trigger: String, draft: String) -> Bool {
        if trigger == "x" || trigger == "s" {
            return true
        }
        return trigger == "-" && draft.contains("x=")
    }

    private static func meaningChangingAliasReplacement(for trigger: String) -> String? {
        switch trigger {
        case "-": "~"
        case "x": "!"
        case "s": "*"
        default: nil
        }
    }

    /// Re-asks Bob about the first alias key for a fast double-tap. Reuses
    /// the rewrite generation and task so any later edit, caret move, or
    /// dismissal cancels the probe through the existing paths. The live
    /// caret, not the request cursor, is the expected cursor.
    @discardableResult
    private func startHashAliasProbeRewrite(
        probe: HashAliasProbe
    ) -> Task<Void, Never>? {
        guard let processClient else {
            return nil
        }

        rewriteGeneration &+= 1
        let generation = rewriteGeneration
        deferredRewriteInputDraft = nil
        completedDeferredRewriteDraft = nil
        rewriteExpectedCursorUTF8 = probe.secondCaretUTF8
        rewriteSawMatchingSelection = collapsedSelectionUTF8Offset() == probe.secondCaretUTF8
        rewriteTask?.cancel()
        let task = Task { [weak self, processClient] in
            do {
                let response = try await CaptureSignpost.measure("rewrite") {
                    try await processClient.captureRewrite(
                        probe.firstDraft,
                        cursor: probe.firstCaretUTF8
                    )
                }
                try Task.checkCancellation()

                await MainActor.run {
                    self?.applyHashAliasProbeRewrite(
                        response,
                        probe: probe,
                        generation: generation,
                        processClient: processClient
                    )
                    if self?.rewriteGeneration == generation {
                        self?.rewriteTask = nil
                    }
                }
            } catch is CancellationError {
            } catch {
                // Like `startCaptureRewrite`: a failed assist never disturbs
                // the typed draft.
                await MainActor.run {
                    guard self?.rewriteGeneration == generation else {
                        return
                    }
                    self?.rewriteTask = nil
                    self?.deferredRewriteInputDraft = nil
                    self?.rewriteExpectedCursorUTF8 = nil
                    self?.rewriteSawMatchingSelection = false
                    self?.pendingHashAlias = nil
                    self?.hashAliasProbe = nil
                }
            }
        }
        rewriteTask = task
        return task
    }

    /// Applies a fast double-tap probe reply without running it through
    /// `applyCaptureRewrite`, whose guards compare against the request
    /// draft. On a matching alias reply deletes the second key natively, so
    /// aliased sigil is never shown and no arm is set; any other reply leaves
    /// the typed doubled key alone. Always clears the probe and the
    /// expected-cursor state.
    private func applyHashAliasProbeRewrite(
        _ response: CaptureRewriteResponse,
        probe: HashAliasProbe,
        generation: UInt64,
        processClient: BobProcessClient
    ) {
        guard rewriteGeneration == generation,
              self.processClient === processClient,
              response.input == probe.firstDraft
        else {
            return
        }
        defer {
            if rewriteGeneration == generation {
                rewriteExpectedCursorUTF8 = nil
                rewriteSawMatchingSelection = false
                pendingHashAlias = nil
                hashAliasProbe = nil
            }
        }
        guard response.rule == "expand_sigil_alias",
              response.edits.count == 1,
              let edit = response.edits.first,
              (edit.replacement == "#" || edit.replacement == "%"),
              edit.range.start == probe.firstCaretUTF8 - 1,
              edit.range.end == probe.firstCaretUTF8,
              let inputRange = stringRange(
                  in: response.input,
                  start: edit.range.start,
                  end: edit.range.end
              ),
              String(response.input[inputRange]) == probe.key,
              let secondBackslashRange = utf16Range(
                  in: probe.secondDraft,
                  start: probe.secondCaretUTF8 - 1,
                  end: probe.secondCaretUTF8
              ),
              let secondRange = stringRange(
                  in: probe.secondDraft,
                  start: probe.secondCaretUTF8 - 1,
                  end: probe.secondCaretUTF8
              ),
              String(probe.secondDraft[secondRange]) == probe.key,
              let secondCaretUTF16 = utf16Range(
                  in: probe.secondDraft,
                  start: probe.secondCaretUTF8,
                  end: probe.secondCaretUTF8
              )?.location,
              let firstCaretUTF16 = utf16Range(
                  in: probe.firstDraft,
                  start: probe.firstCaretUTF8,
                  end: probe.firstCaretUTF8
              )?.location
        else {
            if let notice = response.notices.first {
                announceStatus(notice)
            }
            return
        }
        let nativeEdit = CaptureNativeRewriteEdit(
            replacementRange: secondBackslashRange,
            replacementText: "",
            resultingSelection: NSRange(location: firstCaretUTF16, length: 0),
            expectedDraft: probe.secondDraft,
            resultingDraft: probe.firstDraft,
            expectedSelection: NSRange(location: secondCaretUTF16, length: 0)
        )
        suppressedCompletionAcceptanceDraft = probe.firstDraft
        guard applyNativeRewriteEdit?(nativeEdit) == true else {
            suppressedCompletionAcceptanceDraft = nil
            return
        }
        hashAliasLiteralArm = nil
        equalsGestureArm = nil
        pendingEqualsFirstKey = nil
        equalsProbe = nil
        relationFlipAliasOpen = nil
        if plainDraft != probe.firstDraft {
            isApplyingProgrammaticDraft = true
            attributedDraft = AttributedString(probe.firstDraft)
            isApplyingProgrammaticDraft = false
        }
        restoreSelection(
            cursorUTF8Offset: probe.firstCaretUTF8,
            suppressEditorCallbacks: true
        )
        dismissCompletion()
        suppressedCompletionAcceptanceDraft = probe.firstDraft
        scheduleAnalysis(
            cursorUTF8Offset: probe.firstCaretUTF8,
            requestCompletion: false,
            trigger: .edit
        )
    }

    /// Whether the observed caret fits a fast double-tap equals-probe
    /// delivery: unknown, exact, or one behind (SwiftUI can report the
    /// pre-insert caret one callback behind).
    private static func equalsProbeCursorMatches(
        _ cursorUTF8Offset: Int?,
        probe: CaptureEqualsProbe
    ) -> Bool {
        guard let cursorUTF8Offset else {
            return true
        }
        return cursorUTF8Offset == probe.secondCaretUTF8
            || cursorUTF8Offset + 1 == probe.secondCaretUTF8
    }

    /// Re-asks Bob about the first `=` for a fast double-tap. Reuses the
    /// rewrite generation and task so any later edit, caret move, or
    /// dismissal cancels the probe through the existing paths.
    private func startEqualsProbeRewrite(
        probe: CaptureEqualsProbe
    ) -> Task<Void, Never>? {
        guard let processClient else {
            return nil
        }

        rewriteGeneration &+= 1
        let generation = rewriteGeneration
        deferredRewriteInputDraft = nil
        completedDeferredRewriteDraft = nil
        rewriteExpectedCursorUTF8 = probe.secondCaretUTF8
        rewriteSawMatchingSelection = collapsedSelectionUTF8Offset() == probe.secondCaretUTF8
        rewriteTask?.cancel()
        let task = Task { [weak self, processClient] in
            do {
                let response = try await CaptureSignpost.measure("rewrite") {
                    try await processClient.captureRewrite(
                        probe.firstDraft,
                        cursor: probe.firstCaretUTF8
                    )
                }
                try Task.checkCancellation()

                await MainActor.run {
                    self?.applyEqualsProbeRewrite(
                        response,
                        probe: probe,
                        generation: generation,
                        processClient: processClient
                    )
                    if self?.rewriteGeneration == generation {
                        self?.rewriteTask = nil
                    }
                }
            } catch is CancellationError {
            } catch {
                // Like `startCaptureRewrite`: a failed assist never disturbs
                // the typed draft.
                await MainActor.run {
                    guard self?.rewriteGeneration == generation else {
                        return
                    }
                    self?.rewriteTask = nil
                    self?.deferredRewriteInputDraft = nil
                    self?.rewriteExpectedCursorUTF8 = nil
                    self?.rewriteSawMatchingSelection = false
                    self?.pendingEqualsFirstKey = nil
                    self?.equalsProbe = nil
                }
            }
        }
        rewriteTask = task
        return task
    }

    /// Applies a fast double-tap probe reply for `==` / `=~` / `..` without
    /// running it through `applyCaptureRewrite`, whose guards compare
    /// against the request draft. On an alias reply for the first key, `==`
    /// collapses to one `=` (no arm: no rewrite produced output), `=~`
    /// becomes `~~` (armed like the slow flip path), and `..` collapses to
    /// one `.` (no arm); any other reply leaves the typed pair alone.
    /// Always clears the probe and the first-key state.
    private func applyEqualsProbeRewrite(
        _ response: CaptureRewriteResponse,
        probe: CaptureEqualsProbe,
        generation: UInt64,
        processClient: BobProcessClient
    ) {
        guard rewriteGeneration == generation,
              self.processClient === processClient,
              response.input == probe.firstDraft
        else {
            return
        }
        defer {
            if rewriteGeneration == generation {
                rewriteExpectedCursorUTF8 = nil
                rewriteSawMatchingSelection = false
                pendingEqualsFirstKey = nil
                equalsProbe = nil
            }
        }
        let expectedSigils: Set<String>
        switch probe.firstKey {
        case "=":
            expectedSigils = ["~"]
        case ".":
            expectedSigils = ["@", "&"]
        case ";":
            expectedSigils = ["*"]
        default:
            expectedSigils = []
        }
        guard response.rule == "expand_sigil_alias",
              response.edits.count == 1,
              let edit = response.edits.first,
              expectedSigils.contains(edit.replacement),
              edit.range.start == probe.firstCaretUTF8 - 1,
              edit.range.end == probe.firstCaretUTF8,
              let inputRange = stringRange(
                  in: response.input,
                  start: edit.range.start,
                  end: edit.range.end
              ),
              String(response.input[inputRange]) == probe.firstKey,
              let secondRange = stringRange(
                  in: probe.secondDraft,
                  start: probe.secondCaretUTF8 - 1,
                  end: probe.secondCaretUTF8
              ),
              String(probe.secondDraft[secondRange]) == probe.secondKey,
              (probe.firstKey == "=" && (probe.secondKey == "=" || probe.secondKey == "~"))
                  || ((probe.firstKey == "." || probe.firstKey == ";")
                      && probe.secondKey == probe.firstKey),
              let secondCaretUTF16 = utf16Range(
                  in: probe.secondDraft,
                  start: probe.secondCaretUTF8,
                  end: probe.secondCaretUTF8
              )?.location
        else {
            if let notice = response.notices.first {
                announceStatus(notice)
            }
            return
        }
        // `==` and `..` delete the second key; `=~` swaps the pair for `~~`.
        let collapseStart = probe.secondKey == "~"
            ? probe.firstCaretUTF8 - 1
            : probe.secondCaretUTF8 - 1
        let collapseReplacement = probe.secondKey == "~" ? "~~" : ""
        let resultingDraft: String
        let resultingCaretUTF8: Int
        if probe.secondKey == "=" || probe.secondKey == "." || probe.secondKey == ";" {
            resultingDraft = probe.firstDraft
            resultingCaretUTF8 = probe.firstCaretUTF8
        } else {
            var collapsed = probe.secondDraft
            guard let pairRange = stringRange(
                in: collapsed,
                start: collapseStart,
                end: probe.secondCaretUTF8
            ) else {
                return
            }
            collapsed.replaceSubrange(pairRange, with: collapseReplacement)
            resultingDraft = collapsed
            resultingCaretUTF8 = probe.secondCaretUTF8
        }
        guard let collapseUTF16Range = utf16Range(
                  in: probe.secondDraft,
                  start: collapseStart,
                  end: probe.secondCaretUTF8
              ),
              let resultingCaretUTF16 = utf16Range(
                  in: resultingDraft,
                  start: resultingCaretUTF8,
                  end: resultingCaretUTF8
              )?.location
        else {
            return
        }
        let nativeEdit = CaptureNativeRewriteEdit(
            replacementRange: collapseUTF16Range,
            replacementText: collapseReplacement,
            resultingSelection: NSRange(location: resultingCaretUTF16, length: 0),
            expectedDraft: probe.secondDraft,
            resultingDraft: resultingDraft,
            expectedSelection: NSRange(location: secondCaretUTF16, length: 0)
        )
        suppressedCompletionAcceptanceDraft = resultingDraft
        guard applyNativeRewriteEdit?(nativeEdit) == true else {
            suppressedCompletionAcceptanceDraft = nil
            return
        }
        if plainDraft != resultingDraft {
            isApplyingProgrammaticDraft = true
            attributedDraft = AttributedString(resultingDraft)
            isApplyingProgrammaticDraft = false
        }
        restoreSelection(
            cursorUTF8Offset: resultingCaretUTF8,
            suppressEditorCallbacks: true
        )
        if probe.secondKey == "~" {
            // The first `=` was the last typed byte (guarded above), so the
            // pre-gesture draft drops it.
            var preDraft = probe.firstDraft
            preDraft.removeLast()
            equalsGestureArm = CaptureEqualsGestureArm(
                surface: .editor,
                firstTimestamp: probe.secondTimestamp,
                isOpener: false,
                preDraft: preDraft,
                preCaretUTF8: probe.firstCaretUTF8 - 1,
                postDraft: resultingDraft,
                postCaretUTF8: resultingCaretUTF8,
                pickerSnapshot: nil
            )
        }
        dismissCompletion()
        suppressedCompletionAcceptanceDraft = resultingDraft
        scheduleAnalysis(
            cursorUTF8Offset: resultingCaretUTF8,
            requestCompletion: probe.secondKey == "~",
            trigger: .edit
        )
    }

    private func applyCaptureRewrite(
        _ response: CaptureRewriteResponse,
        draft: String,
        cursorUTF8Offset: Int,
        triggeredCharacter: String,
        triggerTimestamp: TimeInterval,
        expectsRelationDirectionToggle: Bool,
        generation: UInt64,
        processClient: BobProcessClient
    ) {
        guard rewriteGeneration == generation,
              self.processClient === processClient,
            plainDraft == draft,
            response.input == draft
        else {
            return
        }
        let suppressInterruptedAliasArm = (triggeredCharacter == "." || triggeredCharacter == ";")
            && interruptedModifierAliasReply?.draft == draft
            && interruptedModifierAliasReply?.timestamp == triggerTimestamp
        defer {
            if rewriteGeneration == generation {
                rewriteExpectedCursorUTF8 = nil
                rewriteSawMatchingSelection = false
                pendingHashAlias = nil
                pendingEqualsFirstKey = nil
                equalsProbe = nil
                if suppressInterruptedAliasArm {
                    interruptedModifierAliasReply = nil
                }
            }
        }
        if let current = collapsedSelectionUTF8Offset(), current != cursorUTF8Offset {
            return
        }

        if response.changed {
            if expectsRelationDirectionToggle,
               response.rule != "toggle_relation_direction"
            {
                announceStatus("This bob does not support relation direction toggles · update bob")
                return
            }
            if let cursor = response.cursor,
               stringRange(in: response.text, start: cursor, end: cursor) == nil
            {
                return
            }

            if deferredRewriteInputDraft == draft,
                response.rule == "expand_sigil_alias",
                response.edits.count == 1,
                let replacement = Self.meaningChangingAliasReplacement(
                    for: triggeredCharacter
                ),
                let edit = response.edits.first,
                edit.replacement == replacement,
                let triggerRange = stringRange(
                    in: draft,
                    start: edit.range.start,
                    end: edit.range.end
                ),
                String(draft[triggerRange]) == triggeredCharacter
            {
                deferredRewriteEchoDraft = response.text
                deferredRewriteEchoCursorUTF8 = response.cursor ?? response.text.utf8.count
            }

            if response.rule == "switch_block_id_separator"
                || response.rule == "attach_relation_label"
                || response.rule == "expand_sigil_alias"
                || response.rule == "toggle_relation_direction"
            {
                applyNativeSingleEditRewrite(
                    response,
                    draft: draft,
                    triggeredCharacter: triggeredCharacter,
                    triggerPositionUTF8: cursorUTF8Offset - triggeredCharacter.utf8.count,
                    triggerTimestamp: triggerTimestamp,
                armRelationEqualsOpener: deferredRewriteInputDraft != draft
                        && !suppressInterruptedAliasArm
                )
                return
            }

            let cursor = response.cursor ?? response.text.utf8.count
            suppressedCompletionAcceptanceDraft = response.text
            setPlainDraft(
                response.text,
                cursorUTF8Offset: cursor,
                suppressSelectionCallbacks: true
            )
            if let summary = response.summary, !summary.isEmpty {
                announceStatus(summary)
            }
            scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
        } else if let notice = response.notices.first {
            announceStatus(notice)
        }
    }

    private func applyNativeSingleEditRewrite(
        _ response: CaptureRewriteResponse,
        draft: String,
        triggeredCharacter: String,
        triggerPositionUTF8: Int,
        triggerTimestamp: TimeInterval,
        armRelationEqualsOpener: Bool
    ) {
        guard let edit = response.coveringEdit(in: draft) else {
            return
        }
        let cursor = response.cursor ?? response.text.utf8.count
        guard let replacementRange = utf16Range(in: draft, byteRange: edit.range),
              let cursorUTF16 = utf16Range(
                in: response.text,
                start: cursor,
                end: cursor
              )?.location
        else {
            return
        }
        applyNativeRewrite(
            CaptureNativeRewriteEdit(
                replacementRange: replacementRange,
                replacementText: edit.replacement,
                resultingSelection: NSRange(location: cursorUTF16, length: 0),
                expectedDraft: draft,
                resultingDraft: response.text
            ),
            response: response,
            cursorUTF8Offset: cursor,
            triggeredCharacter: triggeredCharacter,
            triggerPositionUTF8: triggerPositionUTF8,
            triggerTimestamp: triggerTimestamp,
            armRelationEqualsOpener: armRelationEqualsOpener
        )
    }

    private func applyNativeRewrite(
        _ nativeEdit: CaptureNativeRewriteEdit,
        response: CaptureRewriteResponse,
        cursorUTF8Offset: Int,
        triggeredCharacter: String,
        triggerPositionUTF8: Int,
        triggerTimestamp: TimeInterval,
        armRelationEqualsOpener: Bool
    ) {
        relationFlipAliasOpen = nil
        suppressedCompletionAcceptanceDraft = response.text
        guard applyNativeRewriteEdit?(nativeEdit) == true else {
            suppressedCompletionAcceptanceDraft = nil
            hashAliasLiteralArm = nil
            equalsGestureArm = nil
            relationFlipAliasOpen = nil
            return
        }
        recordAliasTipHit(
            from: response,
            preDraft: nativeEdit.expectedDraft,
            postDraft: response.text
        )
        if plainDraft != response.text {
            isApplyingProgrammaticDraft = true
            attributedDraft = AttributedString(response.text)
            isApplyingProgrammaticDraft = false
        }
        restoreSelection(cursorUTF8Offset: cursorUTF8Offset, suppressEditorCallbacks: true)
        if let summary = response.summary, !summary.isEmpty {
            announceStatus(summary)
        }
        hashAliasLiteralArm = nil
        equalsGestureArm = nil
        relationFlipAliasOpen = nil
        // Pre-gesture draft for the shared equals record: the reply input
        // minus the trigger byte the user typed.
        let equalsGesturePreDraft: String? = {
            guard !triggeredCharacter.isEmpty,
                  let triggerRange = stringRange(
                      in: response.input,
                      start: triggerPositionUTF8,
                      end: triggerPositionUTF8 + triggeredCharacter.utf8.count
                  ),
                  String(response.input[triggerRange]) == triggeredCharacter
            else {
                return nil
            }
            var pre = response.input
            pre.removeSubrange(triggerRange)
            return pre
        }()
        let inputBytes = Array(response.input.utf8)
        if response.rule == "expand_sigil_alias",
           triggeredCharacter == "=",
           triggerPositionUTF8 > 0,
           triggerPositionUTF8 <= inputBytes.count,
           inputBytes[triggerPositionUTF8 - 1] == 0x7E,
           let flipCursor = response.cursor,
           let preDraft = equalsGesturePreDraft
        {
            relationFlipAliasOpen = CaptureRelationFlipAliasOpen(
                draft: response.text,
                caretUTF8: flipCursor
            )
            equalsGestureArm = CaptureEqualsGestureArm(
                surface: .editor,
                firstTimestamp: triggerTimestamp,
                isOpener: false,
                preDraft: preDraft,
                preCaretUTF8: triggerPositionUTF8,
                postDraft: response.text,
                postCaretUTF8: flipCursor,
                pickerSnapshot: nil
            )
        }
        if response.rule == "toggle_relation_direction",
           triggeredCharacter == "=",
           let preDraft = equalsGesturePreDraft,
           let postCursor = response.cursor
        {
            equalsGestureArm = CaptureEqualsGestureArm(
                surface: .editor,
                firstTimestamp: triggerTimestamp,
                isOpener: false,
                preDraft: preDraft,
                preCaretUTF8: triggerPositionUTF8,
                postDraft: response.text,
                postCaretUTF8: postCursor,
                pickerSnapshot: nil
            )
        }
        let modifierAliasOpeners: [(key: String, sigil: String)] = [
            ("=", "~"),
            (".", "@"),
            (".", "&"),
            (";", "*"),
        ]
        if response.rule == "expand_sigil_alias",
           response.edits.count == 1,
           let edit = response.edits.first,
           edit.range.end == edit.range.start + 1,
           edit.range.start == triggerPositionUTF8,
           edit.range.start > 0,
           inputBytes[edit.range.start - 1] != 0x7E,
           let inputRange = stringRange(
               in: response.input,
               start: edit.range.start,
               end: edit.range.end
           ),
           let cursor = response.cursor,
           let caretUTF16 = utf16Range(
               in: response.text,
               start: cursor,
               end: cursor
           )?.location
        {
            let trigger = String(response.input[inputRange])
            if (edit.replacement == "#" || edit.replacement == "%"),
               trigger == "\\" || trigger == "/",
               let hashUTF16Range = utf16Range(
                   in: response.text,
                   byteRange: edit.range
               )
            {
                hashAliasLiteralArm = CaptureHashAliasArm(
                    key: trigger,
                    sigil: edit.replacement,
                    draft: response.text,
                    hashUTF8: edit.range.start,
                    caretUTF8: cursor,
                    caretUTF16: caretUTF16,
                    hashUTF16Range: hashUTF16Range
                )
            } else if armRelationEqualsOpener,
                      let opener = modifierAliasOpeners.first(where: {
                          $0.key == triggeredCharacter && $0.sigil == edit.replacement
                      }),
                      trigger == opener.key,
                      utf16Range(in: response.text, byteRange: edit.range) != nil,
                      let preDraft = equalsGesturePreDraft
            {
                equalsGestureArm = CaptureEqualsGestureArm(
                    surface: .editor,
                    firstTimestamp: triggerTimestamp,
                    isOpener: true,
                    preDraft: preDraft,
                    preCaretUTF8: triggerPositionUTF8,
                    postDraft: response.text,
                    postCaretUTF8: cursor,
                    pickerSnapshot: nil,
                    key: opener.key,
                    sigil: opener.sigil
                )
            }
        }
        let aliasWrittenRange = response.rule == "expand_sigil_alias"
            ? captureWrittenByteRange(from: response.input, to: response.text)
            : nil
        scheduleAnalysis(
            cursorUTF8Offset: cursorUTF8Offset,
            requestCompletion: response.rule == "attach_relation_label"
                || response.rule == "expand_sigil_alias",
            trigger: .edit,
            writtenRange: aliasWrittenRange
        )
        rewriteExpectedCursorUTF8 = nil
        rewriteSawMatchingSelection = false
    }

    /// Second alias key right after an alias: replaces Bob's sigil with the
    /// arm's literal key through the native text view so Undo stays native,
    /// then closes the menu without reopening a picker. The caller passes
    /// the arm it took at key-down time; the live editor decides through
    /// `expectedDraft`/`expectedSelection`. Returns false without changing
    /// state when the arm no longer matches, so the key falls through.
    func replaceHashAliasWithLiteralKey(_ arm: CaptureHashAliasArm) -> Bool {
        guard !isSubmitting,
              !editorInputLocked,
              let hashRange = stringRange(
                  in: arm.draft,
                  start: arm.hashUTF8,
                  end: arm.hashUTF8 + 1
              ),
              String(arm.draft[hashRange]) == arm.sigil
        else {
            return false
        }
        var newDraft = arm.draft
        newDraft.replaceSubrange(hashRange, with: arm.key)
        let newCaretUTF8 = arm.hashUTF8 + arm.key.utf8.count
        guard let caretUTF16 = utf16Range(
            in: newDraft,
            start: newCaretUTF8,
            end: newCaretUTF8
        )?.location
        else {
            return false
        }
        let edit = CaptureNativeRewriteEdit(
            replacementRange: arm.hashUTF16Range,
            replacementText: arm.key,
            resultingSelection: NSRange(location: caretUTF16, length: 0),
            expectedDraft: arm.draft,
            resultingDraft: newDraft,
            expectedSelection: NSRange(location: arm.caretUTF16, length: 0)
        )
        suppressedCompletionAcceptanceDraft = newDraft
        guard applyNativeRewriteEdit?(edit) == true else {
            suppressedCompletionAcceptanceDraft = nil
            return false
        }
        withdrawLastAliasHit()
        if plainDraft != newDraft {
            isApplyingProgrammaticDraft = true
            attributedDraft = AttributedString(newDraft)
            isApplyingProgrammaticDraft = false
        }
        restoreSelection(
            cursorUTF8Offset: newCaretUTF8,
            suppressEditorCallbacks: true
        )
        dismissCompletion()
        suppressedCompletionAcceptanceDraft = newDraft
        scheduleAnalysis(
            cursorUTF8Offset: newCaretUTF8,
            requestCompletion: false,
            trigger: .edit
        )
        return true
    }

    /// True when an opener record is live against the current editor:
    /// Bob's returned sigil sits where the trigger was typed and any open
    /// picker is that sigil's own picker with an empty filter.
    var relationEqualsOpenerRestorable: Bool {
        guard let arm = equalsGestureArm,
              arm.isOpener,
              arm.surface == .editor,
              plainDraft == arm.postDraft,
              arm.postCaretUTF8 == arm.preCaretUTF8 + 1,
              let tildeRange = stringRange(
                  in: arm.postDraft,
                  start: arm.preCaretUTF8,
                  end: arm.preCaretUTF8 + 1
              ),
              String(arm.postDraft[tildeRange]) == arm.sigil
        else {
            return false
        }
        if let openPicker = picker {
            return modifierAliasArm(arm, owns: openPicker) && openPicker.filterText.isEmpty
        }
        // Race window before Bob's picker or completion list appears: the
        // opener arm alone is enough, including picker-backed sigils.
        return !editorInputLocked
    }

    /// Restores a live opener through the native editor so Undo returns
    /// to Bob's rewrite. `key` is a space or empty for Escape.
    func restoreRelationEqualsOpener(key: String) -> Bool {
        guard let arm = equalsGestureArm, relationEqualsOpenerRestorable else {
            return false
        }
        equalsGestureArm = nil
        pendingEqualsFirstKey = nil
        equalsProbe = nil
        let inserted = arm.key + key
        guard !isSubmitting,
              let tildeRange = stringRange(
                  in: arm.postDraft,
                  start: arm.preCaretUTF8,
                  end: arm.preCaretUTF8 + 1
              )
        else {
            return false
        }
        var newDraft = arm.postDraft
        newDraft.replaceSubrange(tildeRange, with: inserted)
        let newCaretUTF8 = arm.preCaretUTF8 + inserted.utf8.count
        guard let tildeUTF16Range = utf16Range(
                  in: arm.postDraft,
                  start: arm.preCaretUTF8,
                  end: arm.preCaretUTF8 + 1
              ),
              let caretUTF16 = utf16Range(
                  in: newDraft,
                  start: newCaretUTF8,
                  end: newCaretUTF8
              )?.location,
              let expectedCaretUTF16 = utf16Range(
                  in: arm.postDraft,
                  start: arm.postCaretUTF8,
                  end: arm.postCaretUTF8
              )?.location
        else {
            return false
        }
        let edit = CaptureNativeRewriteEdit(
            replacementRange: tildeUTF16Range,
            replacementText: inserted,
            resultingSelection: NSRange(location: caretUTF16, length: 0),
            expectedDraft: arm.postDraft,
            resultingDraft: newDraft,
            expectedSelection: NSRange(location: expectedCaretUTF16, length: 0)
        )
        if picker != nil {
            closePickerForAccept()
        }
        suppressedCompletionAcceptanceDraft = newDraft
        guard applyNativeRewriteEdit?(edit) == true else {
            suppressedCompletionAcceptanceDraft = nil
            return false
        }
        withdrawLastAliasHit()
        if plainDraft != newDraft {
            isApplyingProgrammaticDraft = true
            attributedDraft = AttributedString(newDraft)
            isApplyingProgrammaticDraft = false
        }
        restoreSelection(
            cursorUTF8Offset: newCaretUTF8,
            suppressEditorCallbacks: true
        )
        requestFocus(.editor)
        dismissCompletion()
        suppressedCompletionAcceptanceDraft = newDraft
        scheduleAnalysis(
            cursorUTF8Offset: newCaretUTF8,
            requestCompletion: false,
            trigger: .edit
        )
        return true
    }

    /// Shared non-timing precondition for a fast-second undo. Returns the
    /// surface the undo would take, or nil when the key must take its
    /// ordinary path. Both routing (`equalsGestureSecondEqualsSurface`) and
    /// the undo itself use this, so the router never claims an undo the
    /// undo would refuse. Never mutates state.
    private func equalsGestureUndoEligibility(
        for arm: CaptureEqualsGestureArm
    ) -> CaptureEqualsGestureArm.Surface? {
        guard !isSubmitting else {
            return nil
        }
        // The editor stays locked while a picker is open; that lock is
        // expected for both editor and picker undos. Without a picker a
        // lock means a modal owns the editor, so refuse.
        if picker == nil, editorInputLocked {
            return nil
        }
        switch arm.surface {
        case .editor:
            guard relationLabelPrompt == nil,
                plainDraft == arm.postDraft,
                stringRange(
                    in: arm.preDraft,
                    start: arm.preCaretUTF8,
                    end: arm.preCaretUTF8
                ) != nil
            else {
                return nil
            }
            if let openPicker = picker {
                if arm.isOpener {
                    guard modifierAliasArm(arm, owns: openPicker) else {
                        return nil
                    }
                } else {
                    guard openPicker.source.isRelation,
                          openPicker.draftSnapshot == arm.postDraft
                    else {
                        return nil
                    }
                }
            }
            var probeDraft = arm.preDraft
            guard let probeInsert = stringRange(
                in: arm.preDraft,
                start: arm.preCaretUTF8,
                end: arm.preCaretUTF8
            ) else {
                return nil
            }
            probeDraft.replaceSubrange(probeInsert, with: arm.key)
            let probeCaret = arm.preCaretUTF8 + arm.key.utf8.count
            guard utf16Range(
                in: arm.postDraft,
                start: 0,
                end: arm.postDraft.utf8.count
            ) != nil,
                utf16Range(in: probeDraft, start: probeCaret, end: probeCaret) != nil,
                utf16Range(
                    in: arm.postDraft,
                    start: arm.postCaretUTF8,
                    end: arm.postCaretUTF8
                ) != nil
            else {
                return nil
            }
            return .editor
        case .picker:
            guard let snapshot = arm.pickerSnapshot,
                let openPicker = picker,
                openPicker.source.isRelation,
                openPicker.draftSnapshot == arm.postDraft,
                plainDraft == arm.postDraft,
                stringRange(
                    in: arm.preDraft,
                    start: arm.preCaretUTF8,
                    end: arm.preCaretUTF8
                ) != nil
            else {
                return nil
            }
            _ = snapshot
            return .picker
        case .relationLabelCard:
            return nil
        }
    }

    /// Which live surface a fast second key undoes, or nil when the key
    /// should take its ordinary path. Never consumes synthesized
    /// (`timestamp == 0`) or repeat keys.
    func equalsGestureSecondEqualsSurface(
        timestamp: TimeInterval,
        isRepeat: Bool,
        markedText: Bool
    ) -> CaptureEqualsGestureArm.Surface? {
        guard !isRepeat,
            !markedText,
            let arm = equalsGestureArm,
            CaptureEqualsGesture.isFastSecond(
                first: arm.firstTimestamp,
                second: timestamp,
                isRepeat: isRepeat
            )
        else {
            return nil
        }
        return equalsGestureUndoEligibility(for: arm)
    }

    /// Undoes whatever the first key did and types one literal key at the
    /// original caret (editor), into the filter (picker), or into the label
    /// field (card callers use `flipRelationLabelDirection` instead).
    /// Returns false without changing state when the record no longer
    /// matches, so the key falls through to its ordinary path.
    func undoEqualsGestureAndTypeLiteral() -> Bool {
        guard let arm = equalsGestureArm,
            let surface = equalsGestureUndoEligibility(for: arm)
        else {
            return false
        }
        switch surface {
        case .editor:
            return undoEditorEqualsGesture(arm)
        case .picker:
            return undoPickerEqualsGesture(arm)
        case .relationLabelCard:
            return false
        }
    }

    /// Editor undo: restore the pre-gesture draft, type one literal key at
    /// the original caret, and dismiss the picker Bob's reply may have
    /// opened. Never mutates state when the native edit refuses, so a
    /// refused claim leaves the key to its ordinary path with the record
    /// intact.
    private func undoEditorEqualsGesture(_ arm: CaptureEqualsGestureArm) -> Bool {
        guard relationLabelPrompt == nil,
            plainDraft == arm.postDraft,
            let insertRange = stringRange(
                in: arm.preDraft,
                start: arm.preCaretUTF8,
                end: arm.preCaretUTF8
            )
        else {
            return false
        }
        if let openPicker = picker {
            if arm.isOpener {
                guard modifierAliasArm(arm, owns: openPicker) else {
                    return false
                }
            } else {
                guard openPicker.source.isRelation,
                      openPicker.draftSnapshot == arm.postDraft
                else {
                    return false
                }
            }
            if !openPicker.filterText.isEmpty {
                // The opener armed, then the filter gained text: nothing
                // flippable happened, so keep the direction and type the
                // literal into the filter.
                equalsGestureArm = nil
                pendingEqualsFirstKey = nil
                equalsProbe = nil
                updatePickerFilter(openPicker.filterText + arm.key)
                scheduleAnalysis(
                    cursorUTF8Offset: arm.postCaretUTF8,
                    requestCompletion: true,
                    trigger: .edit
                )
                return true
            }
        }
        var newDraft = arm.preDraft
        newDraft.replaceSubrange(insertRange, with: arm.key)
        let newCaretUTF8 = arm.preCaretUTF8 + arm.key.utf8.count
        guard let fullRange = utf16Range(
            in: arm.postDraft,
            start: 0,
            end: arm.postDraft.utf8.count
        ),
            let caretUTF16 = utf16Range(
                in: newDraft,
                start: newCaretUTF8,
                end: newCaretUTF8
            )?.location,
            let expectedCaretUTF16 = utf16Range(
                in: arm.postDraft,
                start: arm.postCaretUTF8,
                end: arm.postCaretUTF8
            )?.location
        else {
            return false
        }
        let edit = CaptureNativeRewriteEdit(
            replacementRange: fullRange,
            replacementText: newDraft,
            resultingSelection: NSRange(location: caretUTF16, length: 0),
            expectedDraft: arm.postDraft,
            resultingDraft: newDraft,
            expectedSelection: NSRange(location: expectedCaretUTF16, length: 0)
        )
        suppressedCompletionAcceptanceDraft = newDraft
        guard applyNativeRewriteEdit?(edit) == true else {
            suppressedCompletionAcceptanceDraft = nil
            return false
        }
        withdrawLastAliasHit()
        equalsGestureArm = nil
        pendingEqualsFirstKey = nil
        equalsProbe = nil
        if picker != nil {
            closePickerForAccept()
        }
        if plainDraft != newDraft {
            isApplyingProgrammaticDraft = true
            attributedDraft = AttributedString(newDraft)
            isApplyingProgrammaticDraft = false
        }
        restoreSelection(
            cursorUTF8Offset: newCaretUTF8,
            suppressEditorCallbacks: true
        )
        requestFocus(.editor)
        dismissCompletion()
        suppressedCompletionAcceptanceDraft = newDraft
        scheduleAnalysis(
            cursorUTF8Offset: newCaretUTF8,
            requestCompletion: false,
            trigger: .edit
        )
        return true
    }

    /// Picker undo: restore the pre-flip session and insert one literal key
    /// into the filter. The direction follows the restored draft through the
    /// re-analysis, as it did after the flip.
    private func undoPickerEqualsGesture(_ arm: CaptureEqualsGestureArm) -> Bool {
        guard let snapshot = arm.pickerSnapshot,
              let openPicker = picker,
              openPicker.source.isRelation,
              openPicker.draftSnapshot == arm.postDraft,
              plainDraft == arm.postDraft,
              stringRange(
                  in: arm.preDraft,
                  start: arm.preCaretUTF8,
                  end: arm.preCaretUTF8
              ) != nil
        else {
            return false
        }
        equalsGestureArm = nil
        pendingEqualsFirstKey = nil
        equalsProbe = nil
        picker = snapshot
        setPlainDraft(
            arm.preDraft,
            cursorUTF8Offset: arm.preCaretUTF8,
            suppressSelectionCallbacks: true
        )
        pickerMarkerHighlight = Self.pickerMarkerHighlightRange(
            source: snapshot.source,
            replacementRange: snapshot.replacementRange,
            markerRange: nil
        )
        applyPickerMarkerHighlight()
        updatePickerFilter(snapshot.filterText + arm.key)
        scheduleAnalysis(
            cursorUTF8Offset: arm.preCaretUTF8,
            requestCompletion: true,
            trigger: .edit
        )
        return true
    }

    @discardableResult
    private func startLivePreview(
        draft: String,
        previewDraft: String,
        pendingSeparator: String?,
        pendingAction: String?,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger,
        clipAuthorized: Bool
    ) -> Task<Void, Never> {
        livePreviewGeneration &+= 1
        let previewRequestGeneration = livePreviewGeneration
        livePreviewTask?.cancel()
        let task = Task { [weak self, processClient] in
            defer {
                if self?.livePreviewGeneration == previewRequestGeneration {
                    self?.livePreviewTask = nil
                }
            }
            do {
                guard self?.isCurrentLivePreviewRequest(
                          previewRequestGeneration: previewRequestGeneration,
                          analysisGeneration: generation,
                          draft: draft,
                          processClient: processClient,
                          clipAuthorized: clipAuthorized
                      ) == true else {
                    return
                }
                let seed = self?.activePriorityRollSeed() ?? UUID().uuidString
                let processClientIdentity = processClient.identityToken
                guard self?.isCurrentLivePreviewRequest(
                    previewRequestGeneration: previewRequestGeneration,
                    analysisGeneration: generation,
                    draft: draft,
                    processClient: processClient,
                    clipAuthorized: clipAuthorized
                ) == true else {
                    return
                }
                let preview = try await CaptureSignpost.measure("preview") {
                    try await processClient.captureLivePreview(
                        previewDraft,
                        priorityRollSeed: seed,
                        readClipboard: clipAuthorized
                    )
                }
                await MainActor.run {
                    guard self?.isCurrentLivePreviewRequest(
                        previewRequestGeneration: previewRequestGeneration,
                        analysisGeneration: generation,
                        draft: draft,
                        processClient: processClient,
                        clipAuthorized: clipAuthorized
                    ) == true else {
                        return
                    }
                    switch preview {
                    case .success(let success):
                        self?.mergeInPendingRevision = nil
                        let captures = success.normalizedCaptures
                        self?.previewPullInSnapshot = self?.makePullInPreviewSnapshot(
                            success: success,
                            captures: captures,
                            draft: previewDraft,
                            processClientIdentity: processClientIdentity,
                            seed: seed,
                            generation: generation,
                            requestID: nil
                        )
                        self?.previewState = .ready(success)
                        self?.assignPreviewOutputs(
                            captures: captures,
                            openNotes: success.openNotes,
                            globalDestination: success.globalDestination,
                            previewDraft: previewDraft
                        )
                        self?.errorMessage = nil
                        self?.errorCode = nil
                        // A bare URL that will queue under the default parent
                        // opens File under on its own; library hits never do.
                        self?.maybeAutoOpenFileUnder(
                            captures: captures,
                            draft: draft,
                            trigger: trigger
                        )
                        if let presentation = Self.soleTogglePresentation(for: captures) {
                            self?.statusText = presentation.statusText
                        } else if let link = Self.soleLinkPresentation(for: captures) {
                            self?.statusText = link.statusText
                        } else if let complete = Self.soleTaskCompletePresentation(for: captures) {
                            self?.statusText = complete.statusText
                        } else if let reset = Self.soleResetPresentation(for: captures) {
                            self?.statusText = reset.statusText
                        } else if let close = Self.soleClosePresentation(for: captures) {
                            self?.statusText = close.statusText
                        } else if let start = Self.soleSessionStartPresentation(for: captures) {
                            self?.statusText = start.statusText
                        } else if let ref = Self.soleRefPresentation(for: captures) {
                            self?.statusText = ref.statusText
                        } else if captures.count == 1,
                                  let transfer = CaptureTransferPresentation(capture: captures[0])
                        {
                            self?.statusText = transfer.statusLineText
                        } else if captures.count == 1,
                                  let mergeIn = CaptureMergeInPresentation(capture: captures[0])
                        {
                            self?.statusText = mergeIn.statusLineText
                        } else if self?.statusText == "Preview failed" {
                            // A successful live preview that sets no
                            // kind-specific status clears a stale failure
                            // footer; empty reads as Ready. Any other text,
                            // such as rewrite notices, is left untouched.
                            self?.statusText = ""
                        }
                        self?.consumeTransferOwnedStatus()
                        if let separator = pendingSeparator {
                            // The card previews the trimmed draft: mark it
                            // pending, dim it in the view, and disable the
                            // pending action so Return cannot submit the real
                            // draft. A numeric separator is a dangling Work
                            // Log bullet, which teaches the entry text.
                            let pending: String
                            if !separator.isEmpty, separator.allSatisfy({ $0.isASCII && $0.isNumber }),
                               let index = Int(separator)
                            {
                                pending = CapturePomodoroClosePresentation.pendingLogText(index: index)
                            } else {
                                pending = CapturePomodoroClosePresentation.pendingText(
                                    separator: separator
                                )
                            }
                            let action = pendingAction ?? "Close"
                            self?.closePendingText = pending
                            self?.closePendingAction = action
                            self?.statusText = "\(pending) — \(action) is disabled"
                        } else {
                            // A valid draft restores the normal card.
                            self?.closePendingText = nil
                            self?.closePendingAction = "Close"
                        }
                        if self?.overrideRefusalDraft == previewDraft {
                            self?.overrideRefusalDraft = nil
                            self?.statusText = "A Pomodoro is running — review the override, then press Return again"
                        }
                    case .failure(let failure):
                        if failure.code == "incomplete_merge_in",
                           let pending = failure.mergeInPending,
                           pending.need == "merge_in_source",
                           let parse = self?.latestParse,
                           Self.pickerNeed(in: parse) == .mergeInSource
                        {
                            self?.mergeInPendingRevision = CaptureMergeInPendingRevision(
                                pending: pending,
                                draft: draft,
                                generation: generation,
                                processClientIdentity: processClientIdentity
                            )
                            self?.previewState = .idle
                            self?.clearPreviewOutputs()
                            self?.previewPullInSnapshot = nil
                            self?.errorMessage = nil
                            self?.errorCode = nil
                            self?.statusText = CapturePickerNeed.mergeInSource.statusText
                            return
                        }
                        if self?.showTransferFailure(
                            failure,
                            parseMode: self?.latestParse?.mode
                        ) != true, self?.showRecordRefusal(failure) != true,
                            self?.showBareAlbumRefusal(failure) != true,
                            self?.showEmptyNotePull(failure) != true
                        {
                            self?.previewState = .failed(failure.error)
                            // Like `failPreview`: a failed live dry run must never
                            // leave a stale card beside the red error.
                            self?.clearPreviewOutputs()
                            self?.previewPullInSnapshot = nil
                            self?.closePendingText = nil
                            self?.closePendingAction = "Close"
                            self?.errorMessage = failure.error
                            self?.errorCode = failure.code
                            self?.refuseStatus("Preview failed")
                        }
                    }
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    guard self?.isCurrentLivePreviewRequest(
                        previewRequestGeneration: previewRequestGeneration,
                        analysisGeneration: generation,
                        draft: draft,
                        processClient: processClient,
                        clipAuthorized: clipAuthorized
                    ) == true else {
                        return
                    }
                    self?.previewState = .failed(String(describing: error))
                }
            }
        }
        livePreviewTask = task
        return task
    }

    private func isCurrentLivePreviewRequest(
        previewRequestGeneration: UInt64,
        analysisGeneration: UInt64,
        draft: String,
        processClient: BobProcessClient,
        clipAuthorized: Bool
    ) -> Bool {
        guard livePreviewGeneration == previewRequestGeneration,
              self.analysisGeneration == analysisGeneration,
              plainDraft == draft,
              self.processClient === processClient,
              lastAppliedParseDraft == draft,
              lastAppliedParseGeneration == analysisGeneration,
              lastAppliedParseClientIdentity == processClient.identityToken,
              let parse = latestParse,
              (Self.pickerNeed(in: parse) == nil
                  || Self.pickerNeed(in: parse) == .mergeInSource)
        else {
            return false
        }
        guard clipAuthorized else {
            return true
        }
        return CaptureGrammarGate.isCompatible(lastAppliedParseGrammar)
            && parse.reportsClipDirective
    }

    private func cancelLivePreviewRequest() {
        livePreviewGeneration &+= 1
        livePreviewTask?.cancel()
        livePreviewTask = nil
    }

    private func isCurrentAnalysis(_ generation: UInt64) -> Bool {
        generation == analysisGeneration
    }

    /// Arms or disarms the pasteboard-counter poll from the accepted parse.
    /// Polling needs the panel visible and key, the parse's own draft still
    /// current, this client's identity on the parse, a compatible grammar,
    /// and a `%c` directive span. Anything else stops the ticker; the next
    /// accepted parse re-arms it.
    private func updateClipboardPolling(parse: CaptureParseResponse, draft: String) {
        guard panelVisible, panelIsKey,
              plainDraft == draft,
              lastAppliedParseDraft == draft,
              lastAppliedParseGeneration == analysisGeneration,
              let processClient,
              lastAppliedParseClientIdentity == processClient.identityToken,
              CaptureGrammarGate.isCompatible(lastAppliedParseGrammar),
              parse.reportsClipDirective
        else {
            stopClipboardPolling()
            return
        }
        startClipboardPolling()
    }

    private func startClipboardPolling() {
        guard clipboardPollTask == nil else { return }
        // Baseline without triggering: activation already refreshed.
        lastSeenClipboardChangeCount = clipboardChangeCounter()
        clipboardPollTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: Self.clipboardPollIntervalNanoseconds
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else {
                    return
                }
                self.clipboardPollTick()
            }
        }
    }

    private func stopClipboardPolling() {
        clipboardPollTask?.cancel()
        clipboardPollTask = nil
        lastSeenClipboardChangeCount = nil
        cancelLivePreviewRequest()
    }

    /// Arms one five-minute boundary refresh while the panel shows a valid
    /// current past preview. Re-arms after each boundary; never overlaps
    /// tickers and never fires on every view render.
    private func schedulePastBoundaryRefresh() {
        cancelPastBoundaryRefresh()
        guard CapturePastBoundary.shouldArm(
            panelVisible: panelVisible,
            hasPastGroups: pastPresentation != nil
        ) else {
            return
        }
        let delay = CapturePastBoundary.sleepNanoseconds(now: pastNow())
        pastRefreshTask = Task { [weak self] in
            do {
                try await self?.pastSleep(delay) ?? ()
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self?.refreshPastPreviewForBoundary()
            }
        }
    }

    private func cancelPastBoundaryRefresh() {
        pastRefreshTask?.cancel()
        pastRefreshTask = nil
    }

    /// Re-runs the live preview at a five-minute boundary without touching
    /// the draft, selection, completion, chosen offers, or submission. Uses
    /// `startLivePreview` and its generation/draft/client/clipboard checks,
    /// so stale responses cannot resurrect retired offers and failures show
    /// the normal refusal instead of restoring the old success.
    private func refreshPastPreviewForBoundary() {
        guard let processClient,
            let parse = latestParse,
            let appliedDraft = lastAppliedParseDraft,
            appliedDraft == plainDraft,
            lastAppliedParseGeneration == analysisGeneration,
            lastAppliedParseClientIdentity == processClient.identityToken,
            Self.pickerNeed(in: parse) == nil,
            pastPresentation != nil,
            panelVisible
        else {
            cancelPastBoundaryRefresh()
            return
        }
        let draft = plainDraft
        let closePending = Self.closePendingTrim(in: parse, draft: draft)
        let clipAuthorized = CaptureGrammarGate.isCompatible(parse.grammar)
            && parse.reportsClipDirective
        startLivePreview(
            draft: draft,
            previewDraft: closePending?.trimmed ?? draft,
            pendingSeparator: closePending?.separator,
            pendingAction: closePending?.action,
            generation: analysisGeneration,
            processClient: processClient,
            trigger: .edit,
            clipAuthorized: clipAuthorized
        )
        // Re-arm for the next boundary only when the refreshed preview is
        // still a past preview; `assignPreviewOutputs` re-arms on success,
        // and failures clear outputs (no stale card) via the normal path.
    }

    /// Hosted-test hook: whether a boundary refresh is armed.
    var pastRefreshArmedForTests: Bool {
        pastRefreshTask != nil
    }

    /// Hosted-test hook: fire the boundary refresh synchronously.
    func firePastBoundaryRefreshForTests() {
        refreshPastPreviewForBoundary()
    }

    /// One pasteboard-counter check. A moved counter re-runs the debounced
    /// preview for the unchanged draft; lapsed evidence stops the ticker.
    private func clipboardPollTick() {
        guard clipboardPollTask != nil else { return }
        let current = clipboardChangeCounter()
        guard current != lastSeenClipboardChangeCount else { return }
        lastSeenClipboardChangeCount = current
        refreshPreviewForClipboardChange()
    }

    /// Synchronous single poll check for hosted lifecycle tests.
    func fireClipboardPollForTests() {
        clipboardPollTick()
    }

    var clipboardPollingForTests: Bool {
        clipboardPollTask != nil
    }

    /// Reports panel key-focus changes from the controller. Activation
    /// refreshes the preview; focus loss stops counter polling.
    func notePanelKeyActive(_ active: Bool) {
        panelIsKey = active
        if active {
            if hasDraft {
                editorTextDidChange()
            }
        } else {
            stopClipboardPolling()
        }
    }

    /// Re-runs the live preview after the pasteboard counter moved while the
    /// draft stayed put. The accepted parse still describes this draft, so
    /// re-validate its evidence and re-issue the preview without touching
    /// completion, similar tasks, or the analysis generation: the response
    /// keeps the current generation check, so a newer analysis still wins
    /// and a delayed tick cannot restore stale content.
    private func refreshPreviewForClipboardChange() {
        guard let processClient,
              let parse = latestParse,
              let appliedDraft = lastAppliedParseDraft,
              appliedDraft == plainDraft,
              lastAppliedParseGeneration == analysisGeneration,
              lastAppliedParseClientIdentity == processClient.identityToken,
              CaptureGrammarGate.isCompatible(lastAppliedParseGrammar),
              parse.reportsClipDirective,
              Self.pickerNeed(in: parse) == nil
        else {
            stopClipboardPolling()
            return
        }
        let draft = plainDraft
        let closePending = Self.closePendingTrim(in: parse, draft: draft)
        startLivePreview(
            draft: draft,
            previewDraft: closePending?.trimmed ?? draft,
            pendingSeparator: closePending?.separator,
            pendingAction: closePending?.action,
            generation: analysisGeneration,
            processClient: processClient,
            trigger: .edit,
            clipAuthorized: true
        )
    }

    private func scheduleSimilarTasks(draft: String, immediate: Bool = false) {
        similarTasksGeneration &+= 1
        let generation = similarTasksGeneration
        similarTasksTask?.cancel()
        similarTasksTask = nil

        guard similarTasksEnabled,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let processClient,
              !processClient.captureRelatedKnownUnsupported
        else {
            similarTasks = .empty
            similarChosenAction = nil
            similarPendingAction = nil
            similarPendingResponse = nil
            return
        }

        let processClientIdentity = processClient.identityToken
        let settleNanoseconds = similarTasksSettleNanoseconds
        similarTasks = SimilarTasksBandPolicy.markPending(similarTasks)
        similarTasksTask = Task { [weak self, processClient] in
            do {
                if !immediate {
                    try await Task.sleep(nanoseconds: settleNanoseconds)
                    try Task.checkCancellation()
                }
                guard let self,
                      self.isCurrentSimilarTasksRequest(
                        generation: generation,
                        draft: draft,
                        processClient: processClient,
                        identity: processClientIdentity
                      )
                else {
                    return
                }
                let mayRequest: Bool
                if immediate {
                    mayRequest = self.panelVisible && self.similarTasksEnabled
                } else {
                    mayRequest = self.similarTasksMayRequest
                }
                if !mayRequest {
                    await MainActor.run {
                        self.clearSimilarTasksPendingKeepingRows()
                    }
                    return
                }

                let response = try await CaptureSignpost.measure(CaptureSignpost.related) {
                    try await processClient.captureRelated(draft)
                }
                try Task.checkCancellation()
                guard self.isCurrentSimilarTasksRequest(
                  generation: generation,
                  draft: draft,
                  processClient: processClient,
                  identity: processClientIdentity
                ) else {
                    return
                }

                await MainActor.run {
                    self.handleSettledSimilarResponse(
                      response,
                      draft: draft,
                      generation: generation,
                      processClient: processClient,
                      identity: processClientIdentity
                    )
                }
            } catch is CancellationError {
            } catch let error as BobClientError {
                guard let self,
                      self.isCurrentSimilarTasksRequest(
                        generation: generation,
                        draft: draft,
                        processClient: processClient,
                        identity: processClientIdentity
                      )
                else {
                    return
                }
                if case .unsupportedCommand("capture-related") = error {
                    CaptureSignpost.event(CaptureSignpost.relatedUnsupported)
                }
                await MainActor.run {
                    self.similarTasks = .empty
                    self.similarChosenAction = nil
                    self.similarPendingAction = nil
                    self.similarPendingResponse = nil
                    self.similarTasksTask = nil
                }
            } catch {
                guard let self,
                      self.isCurrentSimilarTasksRequest(
                        generation: generation,
                        draft: draft,
                        processClient: processClient,
                        identity: processClientIdentity
                      )
                else {
                    return
                }
                CaptureSignpost.event(CaptureSignpost.relatedFailed)
                await MainActor.run {
                    self.similarTasks = .empty
                    self.similarChosenAction = nil
                    self.similarPendingAction = nil
                    self.similarPendingResponse = nil
                    self.similarTasksTask = nil
                }
            }
        }
    }

    private func requestSimilarTasksNow() {
        scheduleSimilarTasks(draft: plainDraft, immediate: true)
    }

    private func emitSimilarTasksSettledSignposts(
        previous: SimilarTasksBandState,
        next: SimilarTasksBandState,
        response: CaptureRelatedResponse
    ) {
        let hasMatches = response.items.contains { !$0.matches.isEmpty }
        if !hasMatches {
            CaptureSignpost.event(CaptureSignpost.relatedEmpty)
            return
        }
        if previous.rows != next.rows {
            CaptureSignpost.event(CaptureSignpost.relatedPublish)
        }
    }

    private func handleSettledSimilarResponse(
        _ response: CaptureRelatedResponse,
        draft: String,
        generation: UInt64,
        processClient: BobProcessClient,
        identity: String
    ) {
        guard isCurrentSimilarTasksRequest(
            generation: generation,
            draft: draft,
            processClient: processClient,
            identity: identity
        ) else { return }
        guard response.ok else {
            if similarTasks.focusedRowID != nil {
                unfocusSimilarRow(applyPending: false)
                announceStatus("Similar tasks changed")
            } else {
                similarTasks = .empty
            }
            similarChosenAction = nil
            similarPendingAction = nil
            similarPendingResponse = nil
            similarTasksTask = nil
            return
        }
        let itemCount = lastAppliedParseDraft == draft ? lastAppliedParseItemCount : nil
        let anchors = Dictionary(uniqueKeysWithValues: response.items.map { ($0.index, $0) })
        if similarTasks.focusedRowID != nil {
            let frozenPrevious = similarTasks
            let fresh = SimilarTasksBandPolicy.reduce(
                response,
                previous: frozenPrevious,
                draft: draft,
                draftItemCount: itemCount
            )
            // Re-key the focus by key. A missing row means the task is gone.
            if fresh.focusedRowID == nil {
                let previous = similarTasks
                similarItemAnchors = anchors
                similarAnchorsDraft = draft
                similarTasks = fresh
                similarChosenAction = nil
                similarPendingAction = nil
                similarPendingResponse = nil
                similarTasksTask = nil
                emitSimilarTasksSettledSignposts(previous: previous, next: fresh, response: response)
                announceStatus("Similar tasks changed")
                return
            }
            if let pending = similarPendingAction {
                similarPendingAction = nil
                similarItemAnchors = anchors
                similarAnchorsDraft = draft
                similarTasks = fresh
                emitSimilarTasksSettledSignposts(previous: frozenPrevious, next: fresh, response: response)
                if let row = focusedSimilarRow() {
                    let defaultAction = row.match.defaultAction
                    if let def = defaultAction,
                       SimilarTasksBandEdits.orderedAvailableActions(for: row.match).contains(def)
                    {
                        similarChosenAction = def
                    }
                }
                similarTasksTask = nil
                // A pending link action on an ID-less row names the task
                // first instead of splicing stale (empty) replacements.
                if let row = focusedSimilarRow(),
                   row.match.requiresBlockID, pending != .open, pending != .discard,
                   SimilarTasksBandEdits.orderedAvailableActions(for: row.match).contains(pending),
                   let item = similarItemAnchors[row.itemIndex],
                   !row.match.route.isEmpty,
                   !row.match.taskRef.isEmpty
                {
                    presentSimilarTaskIDPrompt(row: row, item: item, action: pending)
                    return
                }
                applySimilarActionFresh(pending, draft: draft)
                return
            }
            // Frozen: keep painting the held rows, remember the fresh result.
            similarItemAnchors = anchors
            similarAnchorsDraft = draft
            similarPendingResponse = (response, draft, itemCount)
            similarTasksTask = nil
            return
        }
        let previous = similarTasks
        similarItemAnchors = anchors
        similarAnchorsDraft = draft
        similarPendingResponse = nil
        let next = SimilarTasksBandPolicy.reduce(
            response,
            previous: previous,
            draft: draft,
            draftItemCount: itemCount
        )
        similarTasks = next
        emitSimilarTasksSettledSignposts(previous: previous, next: next, response: response)
        similarTasksTask = nil
    }

    private func isCurrentSimilarTasksRequest(
        generation: UInt64,
        draft: String,
        processClient: BobProcessClient,
        identity: String
    ) -> Bool {
        similarTasksGeneration == generation
          && similarTasksEnabled
          && plainDraft == draft
          && self.processClient === processClient
          && processClient.identityToken == identity
    }

    private func cancelSimilarTasks(clear: Bool) {
        similarTasksGeneration &+= 1
        similarTasksTask?.cancel()
        similarTasksTask = nil
        if clear {
            similarTasks = .empty
            similarTasksFolded = false
            similarChosenAction = nil
            similarPendingAction = nil
            similarPendingResponse = nil
        } else {
            similarTasks = SimilarTasksBandPolicy.markPending(similarTasks)
        }
    }

    // MARK: - Gmail peek lane

    /// Peek line for one Gmail URL from the settled `bob gmail peek`,
    /// or nil while the peek for the current draft has not landed, the
    /// peek failed, or Bob predates `gmail peek`. The item preview shows
    /// this in place of the dry-run offline line.
    func gmailPeekMessage(for url: String) -> String? {
        guard gmailPeekDraft == plainDraft else { return nil }
        return gmailPeekMessages[url]
    }

    /// Schedules one settled `bob gmail peek` per Gmail URL Bob's parse
    /// reported. It copies the Similar-tasks settle: a 350 ms pause, a
    /// generation counter, cancel-previous, and `isCurrent…Request`
    /// checks, on its own `gmail-peek` process lane. A draft without
    /// `gmail_url` spans settles to no peek. Bob stays authoritative:
    /// the app only slices the span bytes Bob reported and renders the
    /// `message` lines Bob returns.
    private func scheduleGmailPeek(parse: CaptureParseResponse, draft: String) {
        gmailPeekGeneration &+= 1
        let generation = gmailPeekGeneration
        gmailPeekTask?.cancel()
        gmailPeekTask = nil

        var seen: Set<String> = []
        let urls = parse.spans
            .filter { $0.kind == "gmail_url" }
            .compactMap { span -> String? in
                guard let range = stringRange(in: draft, start: span.start, end: span.end) else {
                    return nil
                }
                return String(draft[range])
            }
            .filter { seen.insert($0).inserted }

        guard !urls.isEmpty,
              let processClient,
              !processClient.gmailPeekKnownUnsupported
        else {
            return
        }

        let processClientIdentity = processClient.identityToken
        let settleNanoseconds = gmailPeekSettleNanoseconds
        gmailPeekTask = Task { [weak self, processClient] in
            do {
                try await Task.sleep(nanoseconds: settleNanoseconds)
                try Task.checkCancellation()
                guard let self,
                      self.isCurrentGmailPeekRequest(
                        generation: generation,
                        draft: draft,
                        processClient: processClient,
                        identity: processClientIdentity
                      )
                else {
                    return
                }
                var landed: [String: String] = [:]
                for url in urls {
                    try Task.checkCancellation()
                    do {
                        let response = try await processClient.gmailPeek(url)
                        try Task.checkCancellation()
                        guard self.isCurrentGmailPeekRequest(
                          generation: generation,
                          draft: draft,
                          processClient: processClient,
                          identity: processClientIdentity
                        ) else {
                            return
                        }
                        guard response.ok, response.verdict == "resolved" else { continue }
                        landed[url] = response.message
                    } catch is CancellationError {
                        return
                    } catch let error as BobClientError {
                        if case .unsupportedCommand("gmail peek") = error {
                            await MainActor.run {
                                self.gmailPeekTask = nil
                            }
                            return
                        }
                        continue
                    } catch {
                        continue
                    }
                }
                guard self.isCurrentGmailPeekRequest(
                  generation: generation,
                  draft: draft,
                  processClient: processClient,
                  identity: processClientIdentity
                ) else {
                    return
                }
                await MainActor.run {
                    self.gmailPeekMessages = landed
                    self.gmailPeekDraft = draft
                    self.gmailPeekTask = nil
                }
            } catch is CancellationError {
                // Cancelled while settling or peeking: the newer schedule
                // owns the lane, so there is nothing to publish.
            } catch {
                // Unreachable: the settle only fails by cancellation and
                // each peek handles its own errors above.
            }
        }
    }

    private func isCurrentGmailPeekRequest(
        generation: UInt64,
        draft: String,
        processClient: BobProcessClient,
        identity: String
    ) -> Bool {
        gmailPeekGeneration == generation
          && plainDraft == draft
          && self.processClient === processClient
          && processClient.identityToken == identity
    }

    private func cancelGmailPeek(clear: Bool) {
        gmailPeekGeneration &+= 1
        gmailPeekTask?.cancel()
        gmailPeekTask = nil
        if clear {
            gmailPeekMessages = [:]
            gmailPeekDraft = nil
        }
    }

    // MARK: - Similar-tasks focus and strip actions

    /// Visible rows in ⌘-number order for key routing and the strip.
    func similarVisibleRows() -> [SimilarTasksBandRow] {
        SimilarTasksBandPolicy.visibleItems(
            in: similarTasks,
            parseItems: similarTasksParseItems
        ).flatMap(\.rows).sorted { $0.rowNumber < $1.rowNumber }
    }

    var similarRowsVisibleForKeys: Bool { !similarVisibleRows().isEmpty }

    var isSimilarRowFocused: Bool { similarTasks.focusedRowID != nil }

    func focusedSimilarRow() -> SimilarTasksBandRow? {
        guard let id = similarTasks.focusedRowID else { return nil }
        return similarVisibleRows().first { $0.id == id }
            ?? similarTasks.rows.first { $0.id == id }
    }

    func focusedSimilarDefaultAction() -> CaptureRelatedAction? {
        guard let row = focusedSimilarRow() else { return nil }
        if let chosen = similarChosenAction,
           SimilarTasksBandEdits.orderedAvailableActions(for: row.match).contains(chosen)
        {
            return chosen
        }
        return row.match.defaultAction
    }

    /// Focus ⌘N, or unfocus when it is already focused. A stale focus fires
    /// the related lane at once, skipping the settle; the row stays focused
    /// while the fresh anchors load.
    func focusSimilarRow(number: Int) {
        let rows = similarVisibleRows()
        guard let row = rows.first(where: { $0.rowNumber == number }) else { return }
        if similarTasks.focusedRowID == row.id {
            unfocusSimilarRow()
            return
        }
        similarTasks = SimilarTasksBandState(
            draft: similarTasks.draft,
            items: similarTasks.items,
            pending: similarTasks.pending,
            focusedRowID: row.id,
            parseItemCount: similarTasks.parseItemCount,
            revealed: similarTasks.revealed
        )
        let available = SimilarTasksBandEdits.orderedAvailableActions(for: row.match)
        if let def = row.match.defaultAction, available.contains(def) {
            similarChosenAction = def
        } else {
            similarChosenAction = available.first
        }
        similarPendingAction = nil
        if similarTasks.draft != plainDraft {
            requestSimilarTasksNow()
        }
    }

    func focusSimilarRow(id: String) {
        let rows = similarVisibleRows()
        guard let row = rows.first(where: { $0.id == id }) else { return }
        focusSimilarRow(number: row.rowNumber)
    }

    /// Esc or a toggle: clear the focus and paint any frozen result.
    func unfocusSimilarRow(applyPending: Bool = true) {
        guard similarTasks.focusedRowID != nil else { return }
        let pending = applyPending ? similarPendingResponse : nil
        similarPendingResponse = nil
        similarPendingAction = nil
        similarChosenAction = nil
        if let pending {
            let base = SimilarTasksBandState(
                draft: similarTasks.draft,
                items: similarTasks.items,
                pending: false,
                focusedRowID: nil,
                parseItemCount: similarTasks.parseItemCount
            )
            similarTasks = SimilarTasksBandPolicy.reduce(
                pending.response,
                previous: base,
                draft: pending.draft,
                draftItemCount: pending.itemCount
            )
            similarItemAnchors = Dictionary(
                uniqueKeysWithValues: pending.response.items.map { ($0.index, $0) }
            )
            similarAnchorsDraft = pending.draft
        } else {
            // Unfocusing collapses the +N reveal back to the capped rows.
            similarTasks = collapsedSimilarTasks()
        }
    }

    /// Rebuilds the band from the settled anchors with zero revealed rows.
    /// Unfocusing collapses the +N reveal; the next settle re-applies only
    /// the capped rows.
    private func collapsedSimilarTasks() -> SimilarTasksBandState {
        guard !similarItemAnchors.isEmpty else {
            return SimilarTasksBandState(
                draft: similarTasks.draft,
                items: similarTasks.items,
                pending: false,
                focusedRowID: nil,
                parseItemCount: similarTasks.parseItemCount,
                revealed: [:]
            )
        }
        let response = CaptureRelatedResponse(
            ok: true,
            schemaVersion: 1,
            items: similarItemAnchors.values.sorted { $0.index < $1.index }
        )
        let base = SimilarTasksBandState(
            draft: similarTasks.draft,
            items: similarTasks.items,
            pending: false,
            focusedRowID: nil,
            parseItemCount: similarTasks.parseItemCount,
            revealed: [:]
        )
        return SimilarTasksBandPolicy.reduce(
            response,
            previous: base,
            draft: similarTasks.draft ?? plainDraft,
            draftItemCount: similarTasks.parseItemCount
        )
    }

    func similarSelectNextRow() {
        let rows = similarVisibleRows()
        guard let id = similarTasks.focusedRowID,
              let current = rows.firstIndex(where: { $0.id == id })
        else { return }
        // ↓ on the last visible row of an item reveals that item's next
        // hidden match, up to Bob's limit. The focus stays put; a further ↓
        // moves onto the revealed row.
        let focusedItem = rows[current].itemIndex
        if rows[current].id == rows.last(where: { $0.itemIndex == focusedItem })?.id,
           revealNextHiddenSimilarRow(forItem: focusedItem)
        {
            return
        }
        guard current + 1 < rows.count else { return }
        focusSimilarRow(number: rows[current + 1].rowNumber)
    }

    /// Reveals one more hidden match for one band item. Returns true when
    /// another row painted.
    @discardableResult
    func revealNextHiddenSimilarRow(forItem itemIndex: Int) -> Bool {
        guard !similarItemAnchors.isEmpty else { return false }
        var revealed = similarTasks.revealed
        revealed[itemIndex, default: 0] += 1
        let response = CaptureRelatedResponse(
            ok: true,
            schemaVersion: 1,
            items: similarItemAnchors.values.sorted { $0.index < $1.index }
        )
        let before = similarTasks.items.first(where: { $0.index == itemIndex })?.rows.count ?? 0
        let base = SimilarTasksBandState(
            draft: similarTasks.draft,
            items: similarTasks.items,
            pending: similarTasks.pending,
            focusedRowID: similarTasks.focusedRowID,
            parseItemCount: similarTasks.parseItemCount,
            revealed: revealed
        )
        let next = SimilarTasksBandPolicy.reduce(
            response,
            previous: base,
            draft: similarTasks.draft ?? plainDraft,
            draftItemCount: similarTasks.parseItemCount
        )
        let after = next.items.first(where: { $0.index == itemIndex })?.rows.count ?? 0
        guard after > before else { return false }
        // Re-reducing clears the in-flight flag; the lane is still running,
        // so keep painting it until its response settles.
        similarTasks = SimilarTasksBandState(
            draft: next.draft,
            items: next.items,
            pending: similarTasks.pending,
            focusedRowID: next.focusedRowID,
            parseItemCount: next.parseItemCount,
            revealed: next.revealed
        )
        return true
    }

    func similarSelectPreviousRow() {
        let rows = similarVisibleRows()
        guard let id = similarTasks.focusedRowID,
              let current = rows.firstIndex(where: { $0.id == id }),
              current > 0
        else { return }
        focusSimilarRow(number: rows[current - 1].rowNumber)
    }

    func similarSelectNextAction() {
        guard let row = focusedSimilarRow() else { return }
        let available = SimilarTasksBandEdits.orderedAvailableActions(for: row.match)
        guard !available.isEmpty else { return }
        let current = similarChosenAction.flatMap { available.firstIndex(of: $0) } ?? 0
        similarChosenAction = available[(current + 1) % available.count]
    }

    func similarSelectPreviousAction() {
        guard let row = focusedSimilarRow() else { return }
        let available = SimilarTasksBandEdits.orderedAvailableActions(for: row.match)
        guard !available.isEmpty else { return }
        let current = similarChosenAction.flatMap { available.firstIndex(of: $0) } ?? 0
        similarChosenAction = available[(current - 1 + available.count) % available.count]
    }

    func similarApplyDefault() {
        guard let row = focusedSimilarRow() else { return }
        let action: CaptureRelatedAction
        if let chosen = similarChosenAction,
           SimilarTasksBandEdits.orderedAvailableActions(for: row.match).contains(chosen)
        {
            action = chosen
        } else if let def = row.match.defaultAction {
            action = def
        } else {
            return
        }
        similarApply(action)
    }

    /// Apply one strip action. A stale focus waits for fresh anchors first.
    func similarApply(_ action: CaptureRelatedAction) {
        guard let row = focusedSimilarRow() else { return }
        let available = SimilarTasksBandEdits.orderedAvailableActions(for: row.match)
        guard available.contains(action) else {
            if action == .discard {
                announceStatus("Discard is not available for this task")
            }
            return
        }
        // Stale anchors: focus now, apply against the fresh response.
        if similarAnchorsDraft != plainDraft || similarTasks.draft != plainDraft {
            similarPendingAction = action
            requestSimilarTasksNow()
            return
        }
        // ID-less rows name the task first: the Add block ID prompt writes
        // the ID now (before Return) and splices the matching replacement.
        if row.match.requiresBlockID, action != .open, action != .discard {
            guard let item = similarItemAnchors[row.itemIndex],
                  !row.match.route.isEmpty,
                  !row.match.taskRef.isEmpty
            else {
                announceStatus("Similar tasks changed")
                return
            }
            presentSimilarTaskIDPrompt(row: row, item: item, action: action)
            return
        }
        applySimilarActionFresh(action, draft: plainDraft)
    }

    private func applySimilarActionFresh(_ action: CaptureRelatedAction, draft: String) {
        guard let row = focusedSimilarRow() else {
            similarPendingAction = nil
            return
        }
        if action == .open {
            openFocusedSimilarRow(row)
            return
        }
        guard plainDraft == draft,
              draft == similarAnchorsDraft,
              let item = similarItemAnchors[row.itemIndex]
        else {
            similarPendingAction = nil
            unfocusSimilarRow(applyPending: false)
            announceStatus("Similar tasks changed")
            return
        }
        guard let edited = SimilarTasksBandEdits.editedDraft(
            plainDraft,
            item: item,
            match: row.match,
            action: action
        ) else {
            unfocusSimilarRow(applyPending: false)
            announceStatus("Similar tasks changed")
            return
        }
        guard let replacementRange = utf16Range(
            in: plainDraft,
            start: editReplacementStart(item: item, match: row.match, action: action, draft: plainDraft),
            end: editReplacementEnd(item: item, match: row.match, action: action, draft: plainDraft)
        ),
            let cursorSelection = utf16Range(
                in: edited.text,
                start: edited.cursorUTF8,
                end: edited.cursorUTF8
            )
        else {
            unfocusSimilarRow(applyPending: false)
            announceStatus("Similar tasks changed")
            return
        }
        // The native bridge receives exactly the inserted or replaced slice.
        let nativeReplacement = nativeReplacementText(
            old: plainDraft,
            new: edited.text,
            item: item,
            action: action
        )
        let nativeEdit = CaptureNativeRewriteEdit(
            replacementRange: replacementRange,
            replacementText: nativeReplacement,
            resultingSelection: NSRange(location: cursorSelection.location, length: 0),
            expectedDraft: plainDraft,
            resultingDraft: edited.text
        )
        let announcement = SimilarTasksBandEdits.announcement(for: action, title: row.match.title)
        if applyNativeRewriteEdit?(nativeEdit) == true {
            if plainDraft != edited.text {
                isApplyingProgrammaticDraft = true
                attributedDraft = AttributedString(edited.text)
                isApplyingProgrammaticDraft = false
            }
            restoreSelection(cursorUTF8Offset: edited.cursorUTF8, suppressEditorCallbacks: true)
        } else {
            setPlainDraft(edited.text, cursorUTF8Offset: edited.cursorUTF8, suppressSelectionCallbacks: true)
        }
        unfocusSimilarRow(applyPending: false)
        announceStatus(announcement)
        scheduleAnalysis(
            cursorUTF8Offset: edited.cursorUTF8,
            requestCompletion: false,
            trigger: .edit
        )
    }

    private func editReplacementStart(
        item: CaptureRelatedItem,
        match: CaptureRelatedMatch,
        action: CaptureRelatedAction,
        draft: String
    ) -> Int {
        switch action {
        case .note where item.routeRange != nil:
            return item.routeRange?.start ?? 0
        case .discard:
            return item.discardRange?.start ?? 0
        default:
            return item.markerAt ?? draft.utf8.count
        }
    }

    private func editReplacementEnd(
        item: CaptureRelatedItem,
        match: CaptureRelatedMatch,
        action: CaptureRelatedAction,
        draft: String
    ) -> Int {
        switch action {
        case .note where item.routeRange != nil:
            return item.routeRange?.end ?? 0
        case .discard:
            return item.discardRange?.end ?? 0
        default:
            return item.markerAt ?? draft.utf8.count
        }
    }

    private func nativeReplacementText(
        old: String,
        new: String,
        item: CaptureRelatedItem,
        action: CaptureRelatedAction
    ) -> String {
        switch action {
        case .discard:
            return ""
        case .note where item.routeRange != nil:
            guard let range = item.routeRange,
                  stringRange(in: old, byteRange: range) != nil
            else { return "" }
            let prefix = Array(old.utf8.prefix(range.start))
            let suffixDrop = old.utf8.count - range.end
            let newBytes = Array(new.utf8)
            guard newBytes.count >= prefix.count + suffixDrop else { return "" }
            let slice = newBytes[prefix.count..<(newBytes.count - suffixDrop)]
            return String(decoding: slice, as: UTF8.self)
        default:
            guard let at = item.markerAt else { return "" }
            let insertedCount = new.utf8.count - old.utf8.count
            guard insertedCount > 0 else { return "" }
            let newBytes = Array(new.utf8)
            guard at + insertedCount <= newBytes.count else { return "" }
            return String(decoding: newBytes[at..<(at + insertedCount)], as: UTF8.self)
        }
    }

    private func openFocusedSimilarRow(_ row: SimilarTasksBandRow) {
        if taskGotoDispatchInFlight { return }
        guard let url = ObsidianOpenURL.taskGotoURL(
            path: row.match.target,
            line: row.match.line,
            ref: row.match.taskRef.isEmpty ? nil : row.match.taskRef,
            blockID: row.match.blockID
        ) else {
            announceStatus("bob sent no location for this task — update bob")
            return
        }
        taskGotoDispatchInFlight = true
        announceStatus("Opening in Obsidian…")
        taskGotoOpener(url) { [weak self] success in
            guard let self else { return }
            self.taskGotoDispatchInFlight = false
            if success {
                let announcement = SimilarTasksBandEdits.announcement(
                    for: .open,
                    title: row.match.title
                )
                self.unfocusSimilarRow(applyPending: false)
                self.announceStatus(announcement)
                self.panelDismisser()
            } else {
                self.announceStatus("Couldn't open Obsidian")
            }
        }
    }

    private func invalidateAnalysis() {
        analysisGeneration &+= 1
        analysisTask?.cancel()
        analysisTask = nil
        cancelPendingExplicitSubmit()
        cancelLivePreviewRequest()
        cancelSimilarTasks(clear: false)
    }

    private func invalidateRewrite() {
        cancelInFlightRewrite()
        pendingSeparatorToggleIntent = nil
        pendingHashAlias = nil
        hashAliasProbe = nil
        equalsGestureArm = nil
        pendingEqualsFirstKey = nil
        equalsProbe = nil
        interruptedModifierAliasReply = nil
        relationFlipAliasOpen = nil
    }

    private func cancelInFlightRewrite() {
        cancelPendingRewriteSubmit()
        rewriteTask?.cancel()
        rewriteTask = nil
        deferredRewriteInputDraft = nil
        completedDeferredRewriteDraft = nil
        deferredRewriteEchoDraft = nil
        deferredRewriteEchoCursorUTF8 = nil
        rewriteGeneration &+= 1
        rewriteExpectedCursorUTF8 = nil
        rewriteSawMatchingSelection = false
        finishMeaningChangingRewriteHold(didReceiveReply: false)
    }

    private func finishMeaningChangingRewriteHold(didReceiveReply: Bool) {
        guard let generation = meaningChangingRewriteHoldGeneration else {
            return
        }
        finishMeaningChangingRewriteHold(
            generation: generation,
            didReceiveReply: didReceiveReply
        )
    }

    private func finishMeaningChangingRewriteHold(
        generation: UInt64,
        didReceiveReply: Bool
    ) {
        guard meaningChangingRewriteHoldGeneration == generation else {
            return
        }
        meaningChangingRewriteHoldGeneration = nil
        meaningChangingRewriteHoldDidEnd?(generation, didReceiveReply)
    }

    private func cancelPendingRewriteSubmit() {
        pendingRewriteSubmitIntent = nil
    }

    /// Whether the observed caret fits a fast double-tap probe delivery:
    /// unknown, exact, or one behind (SwiftUI can report the pre-insert
    /// caret one callback behind).
    private static func hashAliasProbeCursorMatches(
        _ cursorUTF8Offset: Int?,
        probe: HashAliasProbe
    ) -> Bool {
        guard let cursorUTF8Offset else {
            return true
        }
        return cursorUTF8Offset == probe.secondCaretUTF8
            || cursorUTF8Offset + 1 == probe.secondCaretUTF8
    }

    private func consumeSeparatorToggleIntent(
        draft: String,
        cursorUTF8Offset: Int?
    ) -> SeparatorToggleIntent? {
        guard let intent = pendingSeparatorToggleIntent else {
            return nil
        }
        pendingSeparatorToggleIntent = nil
        guard draft == intent.expectedDraft else {
            return nil
        }
        if let cursorUTF8Offset {
            if cursorUTF8Offset == intent.expectedCursorUTF8 {
                return intent
            }
            // SwiftUI can report the pre-insert caret one callback behind.
            if cursorUTF8Offset + 1 == intent.expectedCursorUTF8 {
                return intent
            }
            return nil
        }
        return intent
    }

    private func activePriorityRollSeed() -> String {
        if let priorityRollSeed {
            return priorityRollSeed
        }

        let seed = UUID().uuidString
        priorityRollSeed = seed
        return seed
    }

    private var recordCompletionSnapshotIsCurrent: Bool {
        guard let snapshot = recordCompletionSnapshot,
              let response = completionResponse,
              let parse = latestParse,
              let processClient,
              snapshot.draft == plainDraft,
              completionDraftSnapshot == plainDraft,
              snapshot.generation == analysisGeneration,
              snapshot.sequence == recordRequestSequence,
              snapshot.processClientIdentity == processClient.identityToken,
              recordAnalysisRequest?.sequence == snapshot.sequence,
              response.cursor == snapshot.cursor,
              parse.input == plainDraft,
              lastAppliedParseDraft == plainDraft,
              lastAppliedParseGeneration == analysisGeneration,
              lastAppliedParseClientIdentity == processClient.identityToken
        else {
            return false
        }

        let itemIndex = Self.recordItemIndex(in: parse, cursor: snapshot.cursor)
        guard itemIndex == snapshot.itemIndex else {
            return false
        }
        if let presentation = CaptureRecordPresentation.make(
            parse: parse,
            cursor: snapshot.cursor
        ) {
            return presentation.record.recordType == snapshot.recordType
        }
        return response.candidates.contains { candidate in
            candidate.recordType == snapshot.recordType
                || candidate.recordContinuation != nil
                || candidate.kind == "record_create"
                || candidate.kind == "record"
        }
    }

    private func updateRecordPresentation(
        parse: CaptureParseResponse,
        draft: String,
        generation: UInt64,
        cursor: Int?,
        clientIdentity: String
    ) {
        recordInteractionPending = false
        guard recordCardDismissedDraft != draft,
              parse.input == draft,
              let cursor,
              let base = CaptureRecordPresentation.make(
                  parse: parse,
                  cursor: cursor,
                  showsMore: false
              )
        else {
            recordPresentation = nil
            recordFocusState = nil
            recordAssistVersion = nil
            return
        }

        recordAssistVersion = base.record.assistVersion
        let focus = recordFocusState?.refreshed(
            with: base,
            draft: draft,
            generation: generation,
            sequence: recordRequestSequence,
            clientIdentity: clientIdentity
        ) ?? CaptureRecordFocusState(
            draft: draft,
            generation: generation,
            sequence: recordRequestSequence,
            clientIdentity: clientIdentity,
            itemIndex: base.itemIndex,
            fieldKey: base.activeFieldKey,
            showsMore: base.showsMore,
            selectedRowKey: base.selectedRowKey
        )
        recordFocusState = focus
        recordPresentation = CaptureRecordPresentation(
            record: base.record,
            itemIndex: base.itemIndex,
            rows: base.rows,
            activeFieldKey: focus.fieldKey,
            selectedRowKey: focus.selectedRowKey,
            showsMore: focus.showsMore
        )
    }

    private static func recordItemIndex(in parse: CaptureParseResponse, cursor: Int) -> Int? {
        guard !parse.items.isEmpty else {
            return nil
        }
        return parse.items.firstIndex { cursor >= $0.range.start && cursor <= $0.range.end }
    }

    private func applyParse(
        _ parse: CaptureParseResponse,
        draft: String,
        generation: UInt64,
        cursorUTF8: Int? = nil
    ) {
        if plainDraft == draft, parse.template == nil {
            templateOrigin = nil
        }
        lastAnalysisNeedsTaskGoto = Self.pickerNeed(in: parse) == .taskGoto
        parseDiagnostics = parse.diagnostics
        latestParse = parse
        parsedTemplate = parse.template
        lastAppliedParseDraft = draft
        lastAppliedParseGeneration = generation
        lastAppliedParseGrammar = parse.grammar
        lastAppliedParseClientIdentity = processClient?.identityToken
        updateRecordPresentation(
            parse: parse,
            draft: draft,
            generation: generation,
            cursor: cursorUTF8 ?? collapsedSelectionUTF8Offset(),
            clientIdentity: processClient?.identityToken ?? ""
        )
        lastAppliedParseItemCount = parse.items.isEmpty
          ? (draft.isEmpty ? 0 : 1)
          : parse.items.count
        if parse.items.isEmpty {
            similarTasksParseItems = draft.isEmpty
                ? []
                : [SimilarTasksParseItem(index: 0, mode: parse.mode)]
        } else {
            similarTasksParseItems = parse.items.map {
                SimilarTasksParseItem(index: $0.index, mode: $0.mode)
            }
        }
        lastRelationGrammar = parse.relationGrammar
        refreshCaptureGrammarGate()
        if draft.contains("~") && parse.relationGrammar == nil {
            relationCapabilityWarning =
                "This bob predates ~ links; ~ text would be captured literally · update bob"
            if relationCapabilityAcknowledgedDraft != draft {
                // A new draft needing acknowledgement stays unacknowledged.
            }
        } else {
            relationCapabilityWarning = nil
            if lastAppliedParseDraft != relationCapabilityAcknowledgedDraft {
                // Keep the acknowledgement only for its own draft; a draft
                // without the warning never needs one.
            }
        }
        if plainDraft == draft {
            closeListParseSnapshot = CaptureParseSnapshot(
                draft: draft,
                parse: parse
            )
        }
        updateClipboardPolling(parse: parse, draft: draft)
        applyHighlighting(parse: parse, draft: draft, cursorUTF8: cursorUTF8)
        scheduleGmailPeek(parse: parse, draft: draft)

        if let diagnostic = parse.diagnostics.first(where: { $0.severity != "info" }) {
            if diagnostic.severity == "error" {
                refuseStatus(diagnostic.message)
            } else {
                statusText = diagnostic.message
            }
        } else if CaptureRecordFooterMessage.isSupersedable(statusText) {
            statusText = "Ready"
        } else {
            consumeTransferOwnedStatus()
        }
    }

    /// Applies one Bob-authored diagnostic rewrite as a single explicit,
    /// undoable editor edit. The diagnostic must still belong to the current
    /// parse revision and its byte range must remain valid in that draft.
    @discardableResult
    func applyDiagnosticRewrite(_ rewrite: CaptureDiagnosticRewrite) -> Bool {
        guard !isSubmitting,
              !inlinePromptVisible,
              let processClient,
              let parse = latestParse,
              parse.input == plainDraft,
              lastAppliedParseDraft == plainDraft,
              lastAppliedParseGeneration == analysisGeneration,
              lastAppliedParseClientIdentity == processClient.identityToken,
              parse.diagnostics.contains(where: { $0.rewrite == rewrite }),
              let edit = Self.nativeEditForOrdinaryInsertion(
                  insertion: rewrite.replacement,
                  draft: plainDraft,
                  range: CaptureRange(start: rewrite.start, end: rewrite.end)
              )
        else {
            return false
        }
        let cursor = rewrite.start + rewrite.replacement.utf8.count
        guard stringRange(in: edit.resultingDraft, start: cursor, end: cursor) != nil else {
            return false
        }
        if picker != nil {
            closePickerForAccept()
        }
        if applyNativeRewriteEdit != nil {
            guard applyBlockIDSpliceNatively(edit: edit, caretUTF8: cursor) else {
                return false
            }
        } else {
            setPlainDraft(
                edit.resultingDraft,
                cursorUTF8Offset: cursor,
                suppressSelectionCallbacks: true
            )
        }
        mergeInPendingRevision = nil
        scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
        announceStatus("Applied \(rewrite.label)")
        requestFocus(.editor)
        return true
    }

    private func applyHighlighting(
        parse: CaptureParseResponse,
        draft: String,
        cursorUTF8: Int? = nil
    ) {
        let ranges = validatedSpanRanges(in: draft, spans: parse.spans)
        if ranges == nil {
            statusText = "Ignored malformed parse spans"
        }
        guard plainDraft == draft else {
            return
        }
        if let ranges {
            paintedSpanRanges = (draft: draft, ranges: ranges)
        } else {
            paintedSpanRanges = nil
        }
        var ignoredMalformedSpan = false
        isApplyingProgrammaticDraft = true
        attributedDraft.transform(updating: &editorSelection) { text in
            ignoredMalformedSpan = Self.applyEditorHighlighting(
                &text,
                parse: parse,
                draft: draft,
                ranges: ranges,
                cursorUTF8: cursorUTF8 ?? collapsedSelectionUTF8Offset(),
                concealRouteStartGlyphs: showsRecordRouteEmoji
            )
        }
        isApplyingProgrammaticDraft = false
        if ignoredMalformedSpan {
            statusText = "Ignored malformed parse spans"
        }
        // Repainting clears every editor-owned background, so restore the
        // marker wash in the same parse application while the picker is open.
        applyPickerMarkerHighlight()
    }

    /// Paints validated spans, or clears inherited highlight attributes when
    /// the span list is unusable so stale route concealment cannot hide text.
    @discardableResult
    static func applyEditorHighlighting(
        _ text: inout AttributedString,
        parse: CaptureParseResponse,
        draft: String,
        ranges: [ValidatedCaptureSpan]?,
        cursorUTF8: Int? = nil,
        concealRouteStartGlyphs: Bool = false
    ) -> Bool {
        guard let ranges else {
            clearEditorHighlightAttributes(&text)
            return true
        }
        return paintHighlighting(
            &text,
            parse: parse,
            draft: draft,
            ranges: ranges,
            cursorUTF8: cursorUTF8,
            concealRouteStartGlyphs: concealRouteStartGlyphs
        )
    }

    /// Re-paints the current parse so route-start concealment stays in
    /// lockstep with the overlay gate.
    private func refreshRecordRouteConcealmentIfNeeded() {
        guard let parse = latestParse, parse.input == plainDraft else {
            return
        }
        applyHighlighting(parse: parse, draft: plainDraft)
    }

    /// Typed text inherits the previous character's attributes, so clear every
    /// attribute owned by an editor painter before painting current spans.
    static func clearEditorHighlightAttributes(_ text: inout AttributedString) {
        text.foregroundColor = nil
        text.backgroundColor = nil
        // An empty style clears the run where assigning nil leaves the prior
        // paint in place (same AttributedString quirk as unconfigured themes).
        text.underlineStyle = NSUnderlineStyle([])
        text.underlineColor = nil
        text.inlinePresentationIntent = nil
    }

    @discardableResult
    static func paintHighlighting(
        _ text: inout AttributedString,
        parse: CaptureParseResponse,
        draft: String,
        ranges: [ValidatedCaptureSpan],
        cursorUTF8: Int? = nil,
        concealRouteStartGlyphs: Bool = false
    ) -> Bool {
        clearEditorHighlightAttributes(&text)
        let concealedRouteStarts: Set<Int> =
            concealRouteStartGlyphs
            ? Set(CaptureRecordRouteAdornment.all(in: parse).map(\.start))
            : []
        for item in ranges {
            guard let lower = AttributedString.Index(item.range.lowerBound, within: text),
                  let upper = AttributedString.Index(item.range.upperBound, within: text)
            else {
                return true
            }

            let category = captureSemanticCategory(forSpan: item.span, mode: parse.mode)
            let increaseContrast =
                NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            var color = CaptureEditorPalette.color(for: category)
            if item.span.kind == "record_field_value",
               let record = CaptureRecordPresentation.record(matching: item.span, in: parse),
               let field = CaptureRecordPresentation.field(matching: item.span, in: record)
            {
                color = CaptureEditorPalette.recordFieldValueColor(
                    state: field.state,
                    increaseContrast: increaseContrast
                )
            }
            text[lower..<upper].foregroundColor = color
            if item.span.kind == "section",
               item.span.notebook == true
            {
                if item.span.sectionAction == "create" {
                    text[lower..<upper].underlineStyle = NSUnderlineStyle([
                        .single, .patternDot,
                    ])
                    text[lower..<upper].underlineColor =
                        NSColor.systemPurple.withAlphaComponent(0.5)
                } else {
                    text[lower..<upper].underlineStyle = NSUnderlineStyle([])
                    text[lower..<upper].underlineColor = nil
                }
            }
            if item.span.kind == "record_route" {
                // Chip wash only: the type emoji is a presentation overlay
                // at the route-start glyph and must never enter the draft or
                // shift copy/selection offsets. When the overlay is drawn,
                // conceal that `@` grapheme so the emoji replaces it in place.
                text[lower..<upper].backgroundColor = CaptureEditorPalette.recordRouteWash(
                    increaseContrast: increaseContrast
                )
                if concealedRouteStarts.contains(item.span.start),
                    item.range.lowerBound < item.range.upperBound
                {
                    let glyphEnd = draft.index(after: item.range.lowerBound)
                    if let glyphLower = AttributedString.Index(
                        item.range.lowerBound,
                        within: text
                    ),
                        let glyphUpper = AttributedString.Index(glyphEnd, within: text)
                    {
                        text[glyphLower..<glyphUpper].foregroundColor = .clear
                    }
                }
            }
            if item.span.projectNote != nil {
                // Every span of a sealed project-note marker, whatever the
                // modifier says, carries the manila wash. Spans are
                // contiguous, so the per-span washes read as one chip; the
                // `#name` pill after the seal is a separate span.
                text[lower..<upper].backgroundColor = CaptureEditorPalette.projectNoteWash(
                    increaseContrast: increaseContrast
                )
            }
            if category.isUnderlined {
                text[lower..<upper].underlineStyle = .single
            }
            if category.isItalic {
                text[lower..<upper].inlinePresentationIntent = .emphasized
            }
            // Theme tints wash Bob's hue behind each known component of a
            // name, including `task_type` markers. Unconfigured names take
            // a dashed orange underline once the caret leaves the
            // component, matching the Typing rule for unknown names.
            if !item.span.themes.isEmpty {
                for theme in item.span.themes {
                    guard let start = theme.start,
                          let end = theme.end,
                          start < end,
                          let themeRange = stringRange(in: draft, start: start, end: end),
                          let themeLower = AttributedString.Index(
                              themeRange.lowerBound,
                              within: text
                          ),
                          let themeUpper = AttributedString.Index(
                              themeRange.upperBound,
                              within: text
                          )
                    else {
                        continue
                    }
                    if theme.configured == false {
                        if CaptureUnconfiguredThemePresentation.caretIsInName(
                            start: start,
                            end: end,
                            caretUTF8: cursorUTF8
                        ) {
                            // Caret is inside the name: overwrite any
                            // dashed underline on this range. An empty
                            // style clears the run where nil removal
                            // leaves the prior paint in place.
                            text[themeLower..<themeUpper].underlineStyle = NSUnderlineStyle([])
                            text[themeLower..<themeUpper].underlineColor = nil
                            continue
                        }
                        text[themeLower..<themeUpper].underlineStyle = NSUnderlineStyle([
                            .single, .patternDash,
                        ])
                        text[themeLower..<themeUpper].underlineColor =
                            NSColor.systemOrange.withAlphaComponent(0.7)
                        continue
                    }
                    guard theme.known,
                          let tint = PomodoroThemeTint.background(for: theme.hue)
                    else {
                        continue
                    }
                    text[themeLower..<themeUpper].backgroundColor = tint
                    if item.span.kind == "task_type"
                        || item.span.kind == "task_type_marker"
                    {
                        text[themeLower..<themeUpper].foregroundColor =
                            CaptureEditorPalette.color(for: .neutral)
                    }
                }
            }
        }
        paintRecordValueRanges(&text, parse: parse, draft: draft)
        if parse.template != nil {
            for diagnostic in parse.diagnostics where diagnostic.severity != "info" && diagnostic.code != "template_missing_rows" {
                guard let range = diagnostic.range,
                      let typedRange = stringRange(in: draft, byteRange: range),
                      let lower = AttributedString.Index(typedRange.lowerBound, within: text),
                      let upper = AttributedString.Index(typedRange.upperBound, within: text),
                      lower < upper
                else {
                    continue
                }
                text[lower..<upper].underlineStyle = .single
                text[lower..<upper].underlineColor = .red
            }
        }
        return false
    }

    /// Tints each field's `value_ranges` from the record that owns the
    /// span, so list members and Unicode/multiline values follow Bob's
    /// state. Items keep their own record; the first record is never used
    /// globally when item data exists.
    private static func paintRecordValueRanges(
        _ text: inout AttributedString,
        parse: CaptureParseResponse,
        draft: String
    ) {
        let records: [CaptureRecord]
        if parse.items.isEmpty {
            records = parse.record.map { [$0] } ?? []
        } else {
            records = parse.items.compactMap(\.record)
        }
        let increaseContrast =
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        for record in records {
            for field in record.fields {
                for valueRange in field.valueRanges {
                    guard let typedRange = stringRange(in: draft, byteRange: valueRange),
                          let lower = AttributedString.Index(typedRange.lowerBound, within: text),
                          let upper = AttributedString.Index(typedRange.upperBound, within: text),
                          lower < upper
                    else {
                        continue
                    }
                    text[lower..<upper].foregroundColor =
                        CaptureEditorPalette.recordFieldValueColor(
                            state: field.state,
                            increaseContrast: increaseContrast
                        )
                }
            }
        }
    }

    private func shouldRequestCompletion(
        parse: CaptureParseResponse,
        cursor: Int,
        draft: String
    ) -> Bool {
        if Self.leadingSingleAtRouteReplacementRange(in: draft, cursor: cursor) != nil {
            return true
        }

        let completionNeeds = Set([
            "route", "section", "pomodoro_id", "pomodoro_name", "task", "drawer",
            "active_task", "task_link", "task_goto", "task_parent", "task_dependency", "blocked_task",
            "relation_target", "relation_to", "relation_from", "relation_label",
            "dependency_target", "task_complete", "wikilink_task", "block_id", "project_task_move",
            "transfer_destination", "task_type",
            "directive", "record_field", "record_value", "record_create",
        ])
        if !completionNeeds.isDisjoint(with: Set(parse.needs)) {
            return true
        }

        // The additive `pomodoro_start` (`=<X>`) and `pomodoro_close` (`x`)
        // spans are deliberately absent: a cursor inside either suffix offers no
        // completion, while a cursor on its leading edge
        // still matches `pomodoro_name`/`pomodoro_block_id` so accepting a candidate
        // replaces only the name and leaves the typed suffix in place (Bob's
        // replacement range already ends before `=`).
        // `active_task_route`/`active_task_block_id` request `^` completion from Bob.
        // They stay out of `routeSpanKinds` below so cached route completion never
        // intercepts `^` and `routeReplacementRange` never overwrites it; Bob's
        // `needs` covers the lone-`^` case, so there is no Swift-side `^` sniffing.
        // `task_block_id` (the right-hand side of `@route^`) requests block-ID
        // completion the same way `pomodoro_block_id` already does, and the
        // `project_task_*` spans (a trailing ` :id` / ` ^id` token on a
        // project-note bullet) request `project_task_block_id` the same way.
        // A lone whole-item + is dual-use: Swift asks Bob for completion and Bob
        // decides whether to open the picker. Other adjustments return a null
        // context with no candidates.
        let completionSpanKinds = Set([
            "route",
            "record_route",
            "section",
            "task_block_id_route",
            "task_block_id",
            "pomodoro_route",
            "pomodoro_block_id",
            "project_task_link_marker",
            "project_task_block_id",
            "project_task_move_marker",
            "project_task_move_link_marker",
            "project_task_move_block_id",
            "pomodoro_name",
            "sub_bullet_route",
            "sub_bullet_block_id",
            "drawer",
            "task_toggle_route",
            "task_toggle_block_id",
            "task_toggle_pomodoro_name",
            "active_task_route",
            "active_task_block_id",
            "dependency_sigil",
            "dependency_note",
            "dependency_block_id",
            "blocked_task_sigil",
            "blocked_task_note",
            "blocked_task_block_id",
            "relation_sigil",
            "relation_note",
            "relation_block_id",
            "relation_label_separator",
            "relation_label",
            "task_complete_sigil",
            "task_complete_note",
            "task_complete_block_id",
            "global_route",
            "interactive_placeholder",
            "pomodoro_adjust",
            "wikilink_delimiter",
            "wikilink_target",
            "wikilink_heading",
            "wikilink_block_id",
            "wikilink_alias",
            // Bob's `((` spans request `wikilink_task` completion; Swift never sniffs `((`.
            "wikilink_task_delimiter",
            "wikilink_task_query",
            "pomodoro_close_drop",
            "pomodoro_close_park",
            "pomodoro_past_segment",
            "pomodoro_start_drop",
            "task_type",
            "task_type_marker",
            "directive",
        ])

        return parse.spans.contains { span in
            completionSpanKinds.contains(span.kind) && cursor >= span.start && cursor <= span.end
        }
    }

    private func cachedRouteCompletion(
        parse: CaptureParseResponse,
        cursor: Int,
        draft: String
    ) -> CaptureCompletionResponse? {
        // `@@` route completion always goes through bob so the `template:`
        // header candidate appears. This filters on span kinds bob reported,
        // not on local grammar.
        if parse.spans.contains(where: { $0.kind == "global_route" && cursor >= $0.start && cursor <= $0.end }) {
            return nil
        }
        guard let targets = targetCacheSnapshot.targets?.targets, !targets.isEmpty else {
            return nil
        }
        guard let replacement = routeReplacementRange(parse: parse, cursor: cursor, draft: draft)
        else {
            return nil
        }

        let queryEnd = min(cursor, replacement.end)
        guard let queryRange = stringRange(in: draft, start: replacement.start, end: queryEnd)
        else {
            return nil
        }

        let query = String(draft[queryRange]).lowercased()
        let matching = rankedTargets(targets, query: query)
        guard !matching.isEmpty else {
            return nil
        }

        return CaptureCompletionResponse(
            ok: true,
            cursor: cursor,
            replacement: replacement,
            context: "route",
            candidates: matching.map { target in
                CaptureCompletionCandidate(
                    replacement: CaptureRecordRouteCache.insertion(for: target),
                    summary: target.summary,
                    route: target.route,
                    label: CaptureRecordRouteCache.label(for: target),
                    kind: target.kind,
                    status: target.status,
                    title: target.title,
                    owner: target.owner,
                    breadcrumb: target.breadcrumb,
                    alias: aliasHint(for: target, query: query),
                    recordType: target.recordType,
                    emoji: target.emoji,
                    recordContinuation: CaptureRecordRouteCache.continuation(
                        for: target,
                        replacementStart: replacement.start
                    )
                )
            }
        )
    }

    // MARK: - File under (bare-URL reference parent picker)

    /// UserDefaults key for the last-used File-under parent route.
    private static let lastUsedRefParentKey = "refFileUnderLastUsedParent"

    /// The last-used File-under parent route, remembered after a successful
    /// submit so the next list opens with it first.
    private static var lastUsedRefParent: String? {
        get { UserDefaults.standard.string(forKey: lastUsedRefParentKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastUsedRefParentKey) }
    }

    /// Synthesize the File-under route list for a bare-URL draft: cached
    /// inbox, area, and project targets with the last-used parent first,
    /// each accepting as ` @<route>` at the end of the draft through the
    /// existing completion-accept path. Nil when the target cache is empty.
    private func fileUnderCompletion(draft: String) -> CaptureCompletionResponse? {
        guard let cached = targetCacheSnapshot.targets?.targets, !cached.isEmpty else {
            return nil
        }
        let targets = CaptureRefFileUnder.eligibleTargets(cached)
        guard !targets.isEmpty else {
            return nil
        }
        let end = draft.utf8.count
        guard stringRange(in: draft, start: end, end: end) != nil else {
            return nil
        }
        let ordered = CaptureRefFileUnder.orderedTargets(
            targets,
            lastUsedParent: Self.lastUsedRefParent
        )
        return CaptureCompletionResponse(
            ok: true,
            cursor: end,
            replacement: CaptureRange(start: end, end: end),
            context: "route",
            candidates: ordered.map { target in
                CaptureCompletionCandidate(
                    replacement: CaptureRefFileUnder.insertionText(route: target.route),
                    summary: target.summary,
                    route: target.route,
                    label: target.label,
                    kind: target.kind,
                    status: target.status,
                    title: target.title,
                    owner: target.owner,
                    breadcrumb: target.breadcrumb,
                    alias: target.projectNameAliases.first
                )
            }
        )
    }

    /// Open the File-under list on its own when the finished live preview
    /// shows a single bare-URL reference that will queue under the default
    /// parent. Library hits never open it; Esc records the URL so it does
    /// not reopen until the URL changes. Only `.edit` analyses open it: a
    /// caret-only move never does.
    private func maybeAutoOpenFileUnder(
        captures: [CaptureCommandSuccess],
        draft: String,
        trigger: CompletionTrigger
    ) {
        guard trigger == .edit,
              picker == nil,
              completionResponse == nil,
              taskIDPrompt == nil,
              pomodoroNamePrompt == nil,
              captures.count == 1,
              let capture = captures.first,
              capture.kind.lowercased() == "ref",
              capture.placement == "queued",
              let ref = capture.ref,
              let parent = ref.parent,
              parent.source == "default",
              CaptureRefFileUnder.queueableVerdicts.contains(ref.library.verdict)
        else {
            return
        }
        let url = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url != fileUnderDismissedURL,
              plainDraft == draft,
              let fileUnder = fileUnderCompletion(draft: draft),
              !fileUnder.candidates.isEmpty
        else {
            return
        }
        completionResponse = fileUnder
        completionDraftSnapshot = draft
        selectedCompletionIndex = 0
        fileUnderActive = true
    }

    /// Remember the queued reference's parent after a successful submit so
    /// the next File-under list opens with it first.
    private func rememberRefParent(captures: [CaptureCommandSuccess]) {
        guard captures.count == 1,
              let capture = captures.first,
              capture.kind.lowercased() == "ref",
              capture.placement == "queued",
              let route = capture.ref?.parent?.route,
              !route.isEmpty
        else {
            return
        }
        Self.lastUsedRefParent = route
        fileUnderDismissedURL = nil
    }

    private func routeReplacementRange(
        parse: CaptureParseResponse,
        cursor: Int,
        draft: String
    ) -> CaptureRange? {
        let routeSpanKinds = Set([
            "route",
            "record_route",
            "task_block_id_route",
            "pomodoro_route",
            "sub_bullet_route",
            "global_route",
        ])

        for span in parse.spans where cursor >= span.start && cursor <= span.end {
            if routeSpanKinds.contains(span.kind) {
                var start = span.start
                if let sigilRange = stringRange(
                    in: draft,
                    start: span.start,
                    end: min(span.start + 2, span.end)
                ) {
                    let sigil = String(draft[sigilRange])
                    if sigil == "@@" {
                        start += 2
                    } else if sigil.hasPrefix("@") {
                        start += 1
                    }
                }
                return CaptureRange(start: min(start, span.end), end: span.end)
            }
        }

        return Self.leadingSingleAtRouteReplacementRange(in: draft, cursor: cursor)
    }

    private static func leadingSingleAtRouteReplacementRange(in draft: String, cursor: Int) -> CaptureRange? {
        guard draft.utf8.first == 64,
              !draft.hasPrefix("@@"),
              cursor >= 1,
              cursor <= draft.utf8.count,
              stringRange(in: draft, start: cursor, end: cursor) != nil
        else {
            return nil
        }

        var offset = 0
        for character in draft {
            let nextOffset = offset + String(character).utf8.count
            if offset == 0 {
                offset = nextOffset
                continue
            }
            if character.isWhitespace || Self.isRouteBoundary(character) {
                return nil
            }
            offset = nextOffset
        }

        return CaptureRange(start: 1, end: draft.utf8.count)
    }

    private static func isRouteBoundary(_ character: Character) -> Bool {
        character == "#"
            || character == "^"
            || character == ":"
            || character == "+"
    }

    /// Typed `@` route completion ranking over Bob's targets, including
    /// record rows. File under keeps its restricted `rankedTargets`
    /// wrapper so bare-URL parents still exclude records, notebooks, and
    /// unknown kinds. Both share the same bucket order.
    private func rankedTargets(_ targets: [CaptureTarget], query: String) -> [CaptureTarget] {
        CaptureRefFileUnder.rankedSuppliedTargets(targets, query: query)
    }

    /// The alias to show beside a route row for this query (`bob-cli` for
    /// `bob`): the prefix-matching alias when one exists, else the first
    /// substring-matching alias, else nil so ordinary rows read as today.
    private func aliasHint(for target: CaptureTarget, query: String) -> String? {
        guard !query.isEmpty else {
            return nil
        }
        if let prefix = target.projectNameAliases.first(where: { $0.lowercased().hasPrefix(query) }) {
            return prefix
        }
        return target.projectNameAliases.first(where: { $0.lowercased().contains(query) })
    }

    private func restoreSelection(cursorUTF8Offset: Int, suppressEditorCallbacks: Bool = false) {
        guard let insertionPoint = attributedStringIndex(in: attributedDraft, utf8Offset: cursorUTF8Offset) else {
            statusText = "Cursor is not on a UTF-8 boundary"
            return
        }

        if suppressEditorCallbacks {
            programmaticSelectionOffsetToIgnore = cursorUTF8Offset
        }
        editorSelection = AttributedTextSelection(insertionPoint: insertionPoint)
    }

    private func applyCompletionWarnings(_ warnings: [String]) {
        guard let warning = warnings.first else {
            return
        }
        statusText = "Link completion warning: \(warning)"
    }

    private func captureSummary(
        prefix: String,
        captures: [CaptureCommandSuccess],
        globalDestination: CaptureGlobalDestination?
    ) -> String {
        if let globalDestination {
            let sample = captures
                .prefix(2)
                .map(\.text)
                .joined(separator: "; ")
            let overrideCount = captures.filter {
                !captureUsesGlobalDestination($0, globalDestination)
            }.count
            let overrides = overrideCount == 0
                ? ""
                : ", \(overrideCount) local override\(overrideCount == 1 ? "" : "s")"
            return "\(prefix) \u{2192} All items \u{2192} \(globalDestination.destinationLabel)\(overrides): \(sample)"
        }

        if captures.count == 1,
           let transfer = CaptureTransferPresentation(capture: captures[0])
        {
            return transfer.statusLineText
        }
        if captures.count == 1,
           let mergeIn = CaptureMergeInPresentation(capture: captures[0])
        {
            return mergeIn.statusLineText
        }

        guard captures.count != 1 else {
            let capture = captures[0]
            let label = displayLabel(for: capture)
            // A single sub-bullet capture names its parent task: the card
            // below shows where the bullet landed.
            if let subBullet = CaptureSubBulletPresentation(capture: capture) {
                if label == capture.relativeTarget {
                    return "\(prefix) \u{2192} \(label) \u{203A} \(subBullet.parentLabel): \(capture.taskLine)"
                }
                return "\(prefix) \u{2192} \(label) (\(capture.relativeTarget)) \u{203A} \(subBullet.parentLabel): \(capture.taskLine)"
            }
            // The display label already is the path for unrouted captures,
            // so the parenthetical would repeat it verbatim.
            if label == capture.relativeTarget {
                return "\(prefix) \u{2192} \(label): \(capture.taskLine)"
            }
            return "\(prefix) \u{2192} \(label) (\(capture.relativeTarget)): \(capture.taskLine)"
        }

        let destinationCount = Set(captures.map(\.target)).count
        let noun = captures.count == 1 ? "capture" : "captures"
        let destinationNoun = destinationCount == 1 ? "destination" : "destinations"
        let sample = captures
            .prefix(2)
            .map(\.text)
            .joined(separator: "; ")
        return "\(prefix) \u{2192} \(captures.count) \(noun), \(destinationCount) \(destinationNoun): \(sample)"
    }

    private func captureStatus(
        prefix: String,
        captures: [CaptureCommandSuccess],
        globalDestination: CaptureGlobalDestination?
    ) -> String {
        if let globalDestination {
            let overrideCount = captures.filter {
                !captureUsesGlobalDestination($0, globalDestination)
            }.count
            let overrides = overrideCount == 0
                ? ""
                : ", \(overrideCount) local override\(overrideCount == 1 ? "" : "s")"
            return "\(prefix) \(captures.count) items \u{00b7} All items \u{2192} \(globalDestination.destinationLabel)\(overrides)"
        }

        if captures.count == 1,
           let transfer = CaptureTransferPresentation(capture: captures[0])
        {
            return transfer.statusLineText
        }
        if captures.count == 1,
           let mergeIn = CaptureMergeInPresentation(capture: captures[0])
        {
            return mergeIn.statusLineText
        }

        guard captures.count != 1 else {
            let capture = captures[0]
            // A single sub-bullet capture names its parent task.
            if let subBullet = CaptureSubBulletPresentation(capture: capture) {
                return "\(prefix) \u{2192} \(displayLabel(for: capture)) \u{203A} \(subBullet.parentLabel)"
            }
            return "\(prefix) \u{2192} \(displayLabel(for: capture))"
        }
        return "\(prefix) \(captures.count) items"
    }

    private func displayLabel(for capture: CaptureCommandSuccess) -> String {
        capture.routeLabel.isEmpty ? capture.relativeTarget : capture.routeLabel
    }

    private static func blockIDValidationMessage(for blockID: String) -> String? {
        if blockID.isEmpty {
            return "Enter a block ID."
        }
        return isValidBlockID(blockID) ? nil : "Use only letters, numbers, and hyphens."
    }

    private static func isValidBlockID(_ blockID: String) -> Bool {
        !blockID.isEmpty
            && blockID.unicodeScalars.allSatisfy { scalar in
                let value = scalar.value
                return (value >= 48 && value <= 57)
                    || (value >= 65 && value <= 90)
                    || (value >= 97 && value <= 122)
                    || value == 45
            }
    }

    private static func prefilledPomodoroName(from query: String) -> String {
        canonicalPomodoroName(query.replacingOccurrences(of: "-", with: " "))
    }

    private static func canonicalPomodoroName(_ raw: String) -> String {
        raw.split { $0.isWhitespace }.joined(separator: " ").uppercased()
    }

    private static func pomodoroNameValidationMessage(for name: String) -> String? {
        if canonicalPomodoroName(name).isEmpty {
            return "Enter a Pomodoro name."
        }
        return isValidPomodoroName(name)
            ? nil
            : "Use only letters, numbers, spaces, and & ' ( ) , . / -."
    }

    private static func isValidPomodoroName(_ name: String) -> Bool {
        isValidCanonicalPomodoroName(canonicalPomodoroName(name))
    }

    private static func isValidCanonicalPomodoroName(_ name: String) -> Bool {
        guard let first = name.first else {
            return false
        }
        guard isPomodoroNameFirst(first) else {
            return false
        }
        var hasLetter = first.isASCII && first.isLetter
        for character in name.dropFirst() {
            guard isPomodoroNameRest(character) else {
                return false
            }
            hasLetter = hasLetter || (character.isASCII && character.isLetter)
        }
        return hasLetter
    }

    private static func isPomodoroNameFirst(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    private static func isPomodoroNameRest(_ character: Character) -> Bool {
        if isPomodoroNameFirst(character) {
            return true
        }
        return character == " "
            || character == "&"
            || character == "'"
            || character == "("
            || character == ")"
            || character == ","
            || character == "."
            || character == "/"
            || character == "-"
    }

    private static func isBareAtAtTrigger(in draft: String, cursorUTF8Offset: Int) -> Bool {
        let bytes = Array(draft.utf8)
        guard cursorUTF8Offset >= 2,
              cursorUTF8Offset <= bytes.count,
              bytes[cursorUTF8Offset - 2] == 64,
              bytes[cursorUTF8Offset - 1] == 64
        else {
            return false
        }

        return cursorUTF8Offset < 3 || bytes[cursorUTF8Offset - 3] != 64
    }
}

extension CapturePanelModel {
    static let typedSigilTriggers: Set<String> = [
        "@", "#", "%", "^", ":", "+", "~", "&", "*",
    ]

    /// Records the expected post-key draft for a physically Shift- or
    /// Option-typed capture sigil. `editorTextDidChange` consumes it only
    /// when the resulting buffer matches.
    func noteTypedSigilIntent(
        sigil: String,
        text: String,
        selectedRange: NSRange
    ) {
        guard Self.typedSigilTriggers.contains(sigil),
            typingTipsEnabled,
            selectedRange.length == 0,
            selectedRange.location >= 0
        else {
            pendingTypedSigilIntent = nil
            return
        }
        let nsText = text as NSString
        guard selectedRange.location <= nsText.length else {
            pendingTypedSigilIntent = nil
            return
        }
        let expectedDraft = nsText.replacingCharacters(in: selectedRange, with: sigil)
        let expectedUTF16 = selectedRange.location + (sigil as NSString).length
        guard let expectedCaretUTF8 = utf8Offset(in: expectedDraft, utf16Offset: expectedUTF16)
        else {
            pendingTypedSigilIntent = nil
            return
        }
        pendingTypedSigilIntent = TypedSigilIntent(
            sigil: sigil,
            expectedDraft: expectedDraft,
            expectedCaretUTF8: expectedCaretUTF8
        )
    }

    func resetTypingTips() {
        aliasTipLedgerStore.reset()
        aliasTipSession = AliasTipSession()
    }

    func installPresentedAliasTipForPreviews(_ tip: CaptureSigilAliasTip?) {
        presentedAliasTip = tip
    }

    /// Test support: installs a reply waiting for its first surface.
    func installPendingAliasTipForPreviews(
        _ tip: CaptureSigilAliasTip?,
        draft: String? = nil
    ) {
        guard let tip else {
            pendingAliasTip = nil
            aliasTipRequest = nil
            return
        }
        let snapshot = draft ?? plainDraft
        let anchor = AliasTipAnchor(
            draft: snapshot,
            sigilRange: tip.range,
            sigil: tip.sigil
        )
        aliasTipRequest = AliasTipRequest(
            generation: aliasTipGeneration,
            cursorUTF8Offset: snapshot.utf8.count,
            anchor: anchor
        )
        pendingAliasTip = PendingAliasTip(
            tip: tip,
            anchor: anchor,
            generation: aliasTipGeneration
        )
    }

    func aliasTipSigilColor(for tip: CaptureSigilAliasTip) -> Color {
        guard let parse = latestParse else {
            return .primary
        }
        let start = tip.range.start
        if let span = parse.spans.first(where: { start >= $0.start && start < $0.end })
            ?? parse.spans.first(where: { start >= $0.start && start <= $0.end })
        {
            return CaptureEditorPalette.color(
                for: captureSemanticCategory(forSpanKind: span.kind)
            )
        }
        return .primary
    }

    var aliasTipFitsPanelBudget: Bool {
        let screenLimit: CGFloat
        if let available = availableScreenHeight {
            screenLimit = max(1, available - 2 * CapturePanelLayout.panelScreenMargin)
        } else {
            return true
        }
        let listHeight =
            CapturePanelLayout.completionViewportHeight
            + CapturePanelLayout.aliasTipHostHeight
        let chrome =
            titlebarSafeAreaInset
            + CapturePanelLayout.rootPadding * 2
            + CapturePanelLayout.sectionSpacing
            + (footerHeight > 0 ? footerHeight : 28)
            + 44
        return chrome + listHeight <= screenLimit
    }

    func aliasTipFitsPickerPanelBudget(visibleRowBudget: Int) -> Bool {
        guard let available = availableScreenHeight else {
            return true
        }
        let screenLimit = max(1, available - 2 * CapturePanelLayout.panelScreenMargin)
        let pickerHeight = CapturePickerHeightPolicy(
            visibleRowBudget: visibleRowBudget,
            tipRowHeight: CapturePanelLayout.aliasTipRowHeight
        ).idealHeight
        let chrome =
            titlebarSafeAreaInset
            + CapturePanelLayout.rootPadding * 2
            + CapturePanelLayout.sectionSpacing
            + (footerHeight > 0 ? footerHeight : 28)
            + 44
        return chrome + pickerHeight <= screenLimit
    }

    fileprivate func consumeTypedSigilIntent(
        draft: String,
        cursorUTF8Offset: Int?
    ) -> TypedSigilIntent? {
        guard let intent = pendingTypedSigilIntent else {
            return nil
        }
        pendingTypedSigilIntent = nil
        guard draft == intent.expectedDraft else {
            return nil
        }
        if let cursorUTF8Offset {
            if cursorUTF8Offset == intent.expectedCaretUTF8 {
                return intent
            }
            if cursorUTF8Offset + 1 == intent.expectedCaretUTF8 {
                return intent
            }
            return nil
        }
        return intent
    }

    fileprivate func startAliasTipLane(
        draft: String,
        cursorUTF8Offset: Int,
        sigil: String
    ) {
        guard typingTipsEnabled, let processClient else {
            return
        }
        if let identity = aliasTipIncapableIdentity,
            identity == processClient.identityToken
        {
            return
        }
        dropPendingAliasTip(reason: .superseded)
        cancelAliasTipLane()
        let anchor = AliasTipAnchor(
            draft: draft,
            sigilRange: CaptureRange(
                start: cursorUTF8Offset - sigil.utf8.count,
                end: cursorUTF8Offset
            ),
            sigil: sigil
        )
        aliasTipRequest = AliasTipRequest(
            generation: aliasTipGeneration,
            cursorUTF8Offset: cursorUTF8Offset,
            anchor: anchor
        )
        let generation = aliasTipGeneration
        let timeout = aliasTipTimeout
        aliasTipTask = Task { [weak self, processClient] in
            do {
                let response = try await processClient.captureRewrite(
                    draft,
                    cursor: cursorUTF8Offset,
                    lane: "alias-tip",
                    timeout: timeout
                )
                try Task.checkCancellation()
                await MainActor.run {
                    self?.applyAliasTipRewrite(
                        response,
                        draft: draft,
                        sigil: sigil,
                        generation: generation,
                        processClient: processClient
                    )
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    if self?.aliasTipGeneration == generation {
                        self?.aliasTipTask = nil
                        self?.finishAliasTipRequest(generation: generation)
                    }
                }
            }
        }
    }

    func applyAliasTipRewrite(
        _ response: CaptureRewriteResponse,
        draft: String,
        sigil: String,
        generation: UInt64,
        processClient: BobProcessClient
    ) {
        guard aliasTipGeneration == generation else {
            return
        }
        aliasTipTask = nil
        if aliasTipRequest == nil {
            let cursor = response.cursor ?? draft.utf8.count
            let anchor = AliasTipAnchor(
                draft: draft,
                sigilRange: CaptureRange(
                    start: max(0, cursor - sigil.utf8.count),
                    end: cursor
                ),
                sigil: sigil
            )
            let openedSurface = currentAliasTipSurface()
                .flatMap { surface in
                    currentAliasTipSurfaceIsAnchored(surface, to: anchor) ? surface.kind : nil
                }
            aliasTipRequest = AliasTipRequest(
                generation: generation,
                cursorUTF8Offset: cursor,
                anchor: anchor,
                openedSurface: openedSurface
            )
        }
        guard var request = aliasTipRequest,
            request.generation == generation,
            request.anchor.draft == draft
        else {
            return
        }
        // A changed reply belongs to the independent main rewrite lane. It
        // carries no capability evidence and must not affect learning state.
        guard !response.changed else {
            finishAliasTipRequest(generation: generation)
            return
        }
        guard response.ok,
            response.input == draft,
            response.text == draft,
            response.cursor == request.cursorUTF8Offset,
            response.edits.isEmpty,
            response.rule == nil
        else {
            finishAliasTipRequest(generation: generation)
            return
        }
        if !response.reportsSigilAliasTips {
            aliasTipIncapableIdentity = processClient.identityToken
            finishAliasTipRequest(generation: generation)
            return
        }
        aliasTipIncapableIdentity = nil
        guard let tip = response.sigilAliasTip else {
            aliasTipLedgerStore.recordIneligible(sigil: sigil)
            finishAliasTipRequest(generation: generation)
            return
        }
        guard CaptureAliasLesson.isKnown(id: tip.id) else {
            finishAliasTipRequest(generation: generation)
            return
        }
        if let reason = request.dropReason {
            recordAliasTipMiss(id: tip.id, generation: generation, reason: reason)
            return
        }
        guard aliasTipIsIntact(request.anchor) else {
            recordAliasTipMiss(id: tip.id, generation: generation, reason: .sigilEdited)
            return
        }
        guard request.openedSurface == nil else {
            recordAliasTipMiss(id: tip.id, generation: generation, reason: .lateReply)
            return
        }
        guard aliasTipLedgerStore.isDue(id: tip.id) else {
            recordAliasTipMiss(id: tip.id, generation: generation, reason: .notDue)
            return
        }
        guard aliasTipSession.canShow(lessonId: tip.id) else {
            recordAliasTipMiss(id: tip.id, generation: generation, reason: .session)
            return
        }
        pendingAliasTip = PendingAliasTip(
            tip: tip,
            anchor: request.anchor,
            generation: generation
        )
        aliasTipRequest = request
    }

    fileprivate func consumePendingAliasTipOnListUpdate(draft: String) {
        let surface =
            completionVisible && !recordShowsGenericCompletionFallback
            ? currentAliasTipSurface()
            : nil
        resolveAliasTipOpeningOpportunity(
            surface: surface,
            draft: draft,
            fallbackReason: .unanchored
        )
    }

    func consumePendingAliasTipOnPickerOpen(
        draft: String,
        range: CaptureRange,
        visibleRowBudget: Int
    ) {
        resolveAliasTipOpeningOpportunity(
            surface: AliasTipSurfaceSnapshot(
                kind: .picker,
                draft: draft,
                replacementRange: range
            ),
            draft: draft,
            fallbackReason: .unanchored,
            pickerVisibleRowBudget: visibleRowBudget
        )
    }

    private func resolveAliasTipOpeningOpportunity(
        surface: AliasTipSurfaceSnapshot?,
        draft: String,
        fallbackReason: AliasTipDropReason,
        pickerVisibleRowBudget: Int? = nil
    ) {
        if let presentedAliasTipAnchor {
            let staysAnchored =
                surface.map {
                    aliasTipIsIntact(presentedAliasTipAnchor, in: $0.draft)
                        && Self.isAliasTipSurfaceAnchored($0, to: presentedAliasTipAnchor)
                } ?? false
            if !staysAnchored {
                presentedAliasTip = nil
            }
        }
        guard var request = aliasTipRequest,
            request.openedSurface == nil,
            request.dropReason == nil
        else {
            return
        }
        guard aliasTipIsIntact(request.anchor, in: draft) else {
            request.dropReason = .sigilEdited
            aliasTipRequest = request
            dropPendingAliasTip(reason: .sigilEdited)
            return
        }
        guard let surface,
            aliasTipIsIntact(request.anchor, in: surface.draft),
            Self.isAliasTipSurfaceAnchored(surface, to: request.anchor)
        else {
            request.dropReason = fallbackReason
            aliasTipRequest = request
            dropPendingAliasTip(reason: fallbackReason)
            return
        }
        request.openedSurface = surface.kind
        aliasTipRequest = request
        guard let pending = pendingAliasTip,
            pending.generation == request.generation
        else {
            return
        }
        pendingAliasTip = nil
        let reason: AliasTipDropReason?
        if CaptureAliasLesson.host(for: pending.tip.id) != surface.kind.lessonHost {
            reason = .host
        } else if !aliasTipSession.canShow(lessonId: pending.tip.id) {
            reason = .session
        } else if surface.kind == .completionList {
            reason = aliasTipFitsPanelBudget ? nil : .budget
        } else if let pickerVisibleRowBudget {
            reason =
                aliasTipFitsPickerPanelBudget(visibleRowBudget: pickerVisibleRowBudget)
                ? nil
                : .budget
        } else {
            reason = .budget
        }
        if let reason {
            recordAliasTipMiss(id: pending.tip.id, generation: pending.generation, reason: reason)
        } else {
            presentedAliasTipAnchor = pending.anchor
            presentedAliasTip = pending.tip
            aliasTipSession.markShown()
            aliasTipLedgerStore.recordMiss(id: pending.tip.id, shown: true)
            finishAliasTipRequest(generation: pending.generation)
        }
    }

    fileprivate func dropPendingAliasTip(reason: AliasTipDropReason = .closed) {
        guard let pending = pendingAliasTip else {
            return
        }
        pendingAliasTip = nil
        aliasTipLedgerStore.recordMiss(
            id: pending.tip.id,
            shown: false,
            dropReason: reason
        )
        finishAliasTipRequest(generation: pending.generation)
    }

    private func deferAliasTipOpportunity(reason: AliasTipDropReason) {
        if pendingAliasTip != nil {
            dropPendingAliasTip(reason: reason)
        } else if var request = aliasTipRequest,
            request.openedSurface == nil,
            request.dropReason == nil
        {
            request.dropReason = reason
            aliasTipRequest = request
        }
    }

    fileprivate func cancelAliasTipLane() {
        aliasTipGeneration &+= 1
        aliasTipTask?.cancel()
        aliasTipTask = nil
        aliasTipRequest = nil
    }

    fileprivate func retireAliasTipDisplayEligibility(
        reason: AliasTipDropReason = .closed
    ) {
        presentedAliasTip = nil
        guard let pending = pendingAliasTip else {
            if var request = aliasTipRequest, request.openedSurface == nil {
                request.dropReason = reason
                aliasTipRequest = request
            }
            return
        }
        dropPendingAliasTip(reason: reason)
    }

    private func finishAliasTipRequest(generation: UInt64) {
        guard aliasTipRequest?.generation == generation else {
            return
        }
        aliasTipRequest = nil
        if pendingAliasTip?.generation == generation {
            pendingAliasTip = nil
        }
    }

    private func recordAliasTipMiss(
        id: String,
        generation: UInt64,
        reason: AliasTipDropReason
    ) {
        guard aliasTipRequest?.generation == generation else {
            return
        }
        aliasTipLedgerStore.recordMiss(id: id, shown: false, dropReason: reason)
        finishAliasTipRequest(generation: generation)
    }

    private func aliasTipIsIntact(_ anchor: AliasTipAnchor) -> Bool {
        aliasTipIsIntact(anchor, in: plainDraft)
    }

    private func aliasTipIsIntact(_ anchor: AliasTipAnchor, in draft: String) -> Bool {
        guard
            aliasTipPrefix(of: draft, through: anchor.sigilRange.end)
                == aliasTipPrefix(of: anchor.draft, through: anchor.sigilRange.end)
        else {
            return false
        }
        guard
            let range = stringRange(
                in: draft,
                start: anchor.sigilRange.start,
                end: anchor.sigilRange.end)
        else {
            return false
        }
        return String(draft[range]) == anchor.sigil
    }

    private func currentAliasTipSurface() -> AliasTipSurfaceSnapshot? {
        if pickerVisible, let picker {
            return AliasTipSurfaceSnapshot(
                kind: .picker,
                draft: picker.draftSnapshot,
                replacementRange: picker.replacementRange
            )
        }
        guard completionVisible,
            let completionResponse,
            let completionDraftSnapshot
        else {
            return nil
        }
        return AliasTipSurfaceSnapshot(
            kind: .completionList,
            draft: completionDraftSnapshot,
            replacementRange: completionResponse.replacement
        )
    }

    private func currentAliasTipSurfaceIsAnchored(
        _ surface: AliasTipSurfaceSnapshot,
        to anchor: AliasTipAnchor
    ) -> Bool {
        aliasTipIsIntact(anchor, in: surface.draft)
            && Self.isAliasTipSurfaceAnchored(surface, to: anchor)
    }

    private static func isAliasTipSurfaceAnchored(
        _ surface: AliasTipSurfaceSnapshot,
        to anchor: AliasTipAnchor
    ) -> Bool {
        surface.replacementRange.start == anchor.sigilRange.start
            || surface.replacementRange.start == anchor.sigilRange.end
    }

    private func aliasTipPrefix(of draft: String, through end: Int) -> String? {
        guard let range = stringRange(in: draft, start: 0, end: end) else {
            return nil
        }
        return String(draft[range])
    }

    fileprivate func recordAliasTipHit(
        from response: CaptureRewriteResponse,
        preDraft: String,
        postDraft: String
    ) {
        guard response.rule == "expand_sigil_alias",
            let alias = response.alias,
            CaptureAliasLesson.isKnown(id: alias.id)
        else {
            return
        }
        let credit = aliasTipLedgerStore.recordHit(id: alias.id)
        aliasTipHitRecords.append(AliasTipHitRecord(
            id: alias.id,
            credit: credit,
            preDraft: preDraft,
            postDraft: postDraft
        ))
        if aliasTipHitRecords.count > 32 {
            aliasTipHitRecords.removeFirst(aliasTipHitRecords.count - 32)
        }
    }

    fileprivate func withdrawLastAliasHit() {
        guard let hit = aliasTipHitRecords.popLast() else {
            return
        }
        aliasTipLedgerStore.withdrawHit(hit.credit)
        aliasTipSession.escape(lessonId: hit.id)
    }

    fileprivate func reconcileAliasTipHit(with draft: String) {
        for index in aliasTipHitRecords.indices.reversed() {
            let hit = aliasTipHitRecords[index]
            if draft == hit.postDraft {
                return
            }
            if draft == hit.preDraft {
                aliasTipHitRecords.remove(at: index)
                aliasTipLedgerStore.withdrawHit(hit.credit)
                aliasTipSession.escape(lessonId: hit.id)
                return
            }
        }
    }
}
