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

/// Source draft and cursor for a recovered template-start gesture after bob
/// already absorbed the second `@`.
private struct CaptureRewriteSource: Equatable {
    let draft: String
    let cursorUTF8Offset: Int
}

/// Provenance for an absorbed `@@` rewrite that may have consumed the second
/// `@` before the third one was typed.
private struct CaptureRewriteProvenance: Equatable {
    let inputDraft: String
    let inputCursorUTF8Offset: Int
    let outputDraft: String
    let outputCursorUTF8Offset: Int
}

/// One-shot expected buffer after a native `:`/`^`, `|`, or template-start `@` insertion.
/// Cleared on consume, mismatch, or lifecycle invalidation; never used to parse grammar.
/// The keystroke's completion waits on the eager rewrite (the completion gate):
/// an accepted toggle supersedes that analysis, while any other outcome completes
/// like an ordinary keystroke.
private struct SeparatorToggleIntent: Equatable {
    let expectedDraft: String
    let expectedCursorUTF8: Int
    let rewriteSource: CaptureRewriteSource?
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
    let selectedCompletionIndex: Int
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
        if case .parentTaskPicker(_, _, let suggestions, _, _, _) = purpose {
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
        if case .parentTaskPicker(_, _, _, let followUp, _, _) = purpose {
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
    let selectedCompletionIndex: Int
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
    let tokenRange: CaptureRange
    /// UTF-8 byte range replaced when committing the `|label` suffix. The
    /// rename draft fix-up rebases this along with the draft text.
    var labelRange: CaptureRange
    /// Relation direction for the live sentence.
    let direction: DependencyPickerDirection
    /// Draft task text (source side for `~`, target side for `~~`).
    let ownerText: String
    /// Picked task text.
    let targetText: String
    /// Caret to restore on cancel. The rename draft fix-up rebases this
    /// when the rewritten draft is shorter than the restore offset.
    var restoreCursor: Int
    /// Picker snapshot to return to on Escape (nil for the `|` flow).
    let returnPicker: CapturePickerState?
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
    case pullInFilter
    case pullInOfferList
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
    let inboxRouteCapabilityAdvertised: Bool
    let hasOverride: Bool
    let vaultDirectoryIdentity: String
}

@MainActor
final class CapturePanelModel: ObservableObject {
    @Published var attributedDraft = AttributedString()
    @Published var editorSelection = AttributedTextSelection()
    @Published var statusText = ""
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
    @Published var selectedCompletionIndex = 0
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
    @Published var isSubmitting = false
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
    /// reported one. Today only the strict plan-budget refusal carries a
    /// code (`plan_theme_cap_exceeded`); nil for every other error and when
    /// there is no error. Cleared together with `errorMessage`.
    @Published var errorCode: String?
    /// Calm capability warning when the draft contains `~` but the latest
    /// parse for this draft lacks `relation_grammar` (an older Bob would
    /// capture the sigil literally). Nil when the draft has no `~` or Bob
    /// understands relations. Rendered as secondary text, never red.
    @Published var relationCapabilityWarning: String?
    @Published var lastSuccess: CaptureCommandSuccess?
    @Published var previewResult: CaptureCommandSuccess?
    @Published var lastSuccessResults: [CaptureCommandSuccess] = []
    @Published var previewResults: [CaptureCommandSuccess] = []
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
    @Published var pullInChoice: CapturePullInChoiceState?
    @Published var inboxRouteChoice: CaptureInboxRouteChoiceState?
    @Published var picker: CapturePickerState?
    /// Recomputed only when the picker snapshot or the filter text changes.
    @Published var pickerPresentation: CapturePickerPresentation?
    @Published var pickerChip: CapturePickerChipState?
    @Published private(set) var focusRequest = CapturePanelFocusRequest(sequence: 0, target: .editor)
    @Published private(set) var editorInputLocked = false
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
                return
            }
            invalidateAnalysis()
            cancelSimilarTasks(clear: true)
            previewPullInSnapshot = nil
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
    /// Narrow controller bridge: insert a saved template through the
    /// focused `NSTextView` so Undo stays native. Nil in tests that do
    /// not wire a text view; those apply `setPlainDraft` as a fallback.
    var applyTemplateInsert: ((CaptureTemplateInsertEdit) -> Bool)?
    let canceledDraftStash: CanceledDraftStash
    let savedTemplateShelf: SavedTemplateShelf

    private let debounceNanoseconds: UInt64
    private let similarTasksSettleNanoseconds: UInt64
    private var analysisTask: Task<Void, Never>?
    private var similarTasksTask: Task<Void, Never>?
    private var rewriteTask: Task<Void, Never>?
    private var stashCancellable: AnyCancellable?
    private var templateShelfCancellable: AnyCancellable?
    private var rememberedSelectedTemplateID: String?
    private var lastAppliedParseDraft: String?
    private var lastAppliedParseItemCount: Int?
    /// Latest parse's `relation_grammar` for `lastAppliedParseDraft` (nil
    /// when the Bob predates relations or no parse has landed yet).
    private var lastRelationGrammar: Int?
    /// Draft the capability warning was already shown for (first ⌘↩). A
    /// second ⌘↩ on the same draft submits. Cleared when the draft changes.
    private var relationCapabilityAcknowledgedDraft: String?
    private var analysisGeneration: UInt64 = 0
    private var similarTasksGeneration: UInt64 = 0
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
    private var rewriteExpectedCursorUTF8: Int?
    private var rewriteSawMatchingSelection = false
    private var pendingSeparatorToggleIntent: SeparatorToggleIntent?
    private var captureRewriteProvenance: CaptureRewriteProvenance?
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

    /// Numbered Task Link count of the running Pomodoro, derived from
    /// the agenda store's snapshot (or its plain-lane fallback on an old
    /// bob). Nil while unknown, when no session runs, when the snapshot
    /// is not today's, or when the latest refresh failed. The close-comma
    /// assist turns off while nil.
    private(set) var currentPomodoroTaskLinkCount: Int?

    /// The agenda store that owns this count. The model subscribes to its
    /// count publisher; the store refreshes on launch, show, submit, and
    /// filtered vault events instead of the old per-show spawn.
    var agendaStore: CaptureAgendaStore? {
        didSet {
            subscribeToAgendaStore()
        }
    }

    private var agendaCancellable: AnyCancellable?

    // MARK: - Idle agenda view state

    /// The Settings toggle, observed live from AppDelegate. While off,
    /// the store keeps refreshing for the close-comma count, but
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
    @Published private(set) var panelVisible = false

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

    /// True while the close-comma assist may fire: the running Pomodoro
    /// has a known count below the single-digit limit.
    var closeTaskCommaArmed: Bool {
        CaptureCloseTaskCommaAssist.isArmed(
            taskLinkCount: currentPomodoroTaskLinkCount
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
        canceledDraftStash: CanceledDraftStash? = nil,
        savedTemplateShelf: SavedTemplateShelf? = nil
    ) {
        self.processClient = processClient
        self.debounceNanoseconds = debounceNanoseconds
        self.similarTasksSettleNanoseconds = similarTasksSettleNanoseconds
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
    }

    deinit {
        analysisTask?.cancel()
        similarTasksTask?.cancel()
        rewriteTask?.cancel()
        todayPomodoroGotoTask?.cancel()
        pomodoroThemeSuggestionsTask?.cancel()
    }

    var plainDraft: String {
        get { String(attributedDraft.characters) }
        set { setPlainDraft(newValue) }
    }

    var hasDraft: Bool {
        !plainDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var completionVisible: Bool {
        !isStashPickerPresented
            && !isTemplateShelfPresented
            && !inlinePromptVisible
            && completionResponse?.candidates.isEmpty == false
    }

    var templateStartHintVisible: Bool {
        guard completionVisible,
              !fileUnderActive,
              let completionResponse,
              completionResponse.context == "route",
              completionResponse.candidates.contains(where: { $0.kind == "template" })
        else {
            return false
        }
        return CaptureTemplateStart.hintApplies(
            draft: plainDraft,
            cursorUTF8Offset: collapsedSelectionUTF8Offset()
        )
    }

    var inlinePromptVisible: Bool {
        taskIDPrompt != nil || pomodoroNamePrompt != nil || relationLabelPrompt != nil
            || pullInChoice != nil || inboxRouteChoice != nil
    }

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
    /// Complete, parent-task card, and similar-tasks band). The old inline
    /// `.parentTask` path keeps Tab consumed.
    var taskIDPromptCyclesSuggestions: Bool {
        taskIDPromptIsTaskLink || taskIDPromptIsDependency || taskIDPromptIsTaskComplete || taskIDPromptIsParentTaskPicker || taskIDPromptIsSimilarTask
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

    /// True when the open picker belongs to the `:` source.
    var pickerSourceIsTaskLink: Bool {
        picker?.source == .taskLink
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

    func pickerActionLine(for row: CapturePickerRow) -> String? {
        pickerIndex?.actionLine(for: row)
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
    /// or prose-terminal plus pickers (Bob omits the keys there).
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
        return []
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
            $0.kind == "pomodoro_name" || $0.kind == "task_toggle_pomodoro_name"
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
              candidates.indices.contains(selectedCompletionIndex)
        else {
            return nil
        }
        return candidates[selectedCompletionIndex]
    }

    var livePreviewUsesLiteralClipboard: Bool {
        guard let snapshot = closeListParseSnapshot,
              snapshot.draft == plainDraft
        else {
            return false
        }
        return snapshot.spans.contains { $0.kind == "clipboard" }
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
        if resetPresentation != nil {
            return "Reset"
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

    var openHintChipVisible: Bool {
        primaryActionEnabled && openHintPresentation.isAvailable
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
        globalDestination: CaptureGlobalDestination?
    ) {
        previewResult = captures.first
        previewResults = captures
        previewGlobalDestination = globalDestination
        previewOpenPlan = CaptureOpenPlan(openNotes: openNotes, captures: captures)
    }

    private func clearPreviewOutputs() {
        previewResult = nil
        previewResults = []
        previewGlobalDestination = nil
        previewOpenPlan = nil
    }

    /// Follows the agenda store's count publisher. The store nils the
    /// count on failure, a non-today snapshot, and client replacement,
    /// so the model only forwards it.
    private func subscribeToAgendaStore() {
        agendaCancellable = nil
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
        agendaPlanningDay = nil
        publishAgendaLoading(today: CaptureAgendaStore.localToday())
    }

    func setProcessClient(_ processClient: BobProcessClient?) {
        let changed = self.processClient !== processClient
        self.processClient = processClient
        if changed {
            // An old count or assist parse must never re-arm the assist
            // after Bob becomes unavailable or the executable/vault changes.
            // The agenda store owns recounting; it clears and repopulates
            // the count through the subscription above.
            closeAssistParseGeneration &+= 1
            currentPomodoroTaskLinkCount = nil
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

    /// Forwards one typed digit to the pure close-comma helper with the
    /// latest snapshot and count. Nil means type the digit natively.
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
            taskLinkCount: currentPomodoroTaskLinkCount
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
    /// separator gesture (`:`, `^`, or `|`) or the template-start `@`. The character still
    /// inserts natively; `editorTextDidChange` consumes this only when the
    /// resulting buffer matches.
    func noteSeparatorToggleIntent(typed: String, text: String, selectedRange: NSRange) {
        var rewriteSource: CaptureRewriteSource?
        if typed == "@" {
            let normalTemplateTrigger = CaptureTemplateStart.isRewriteKeystroke(
                typed: typed,
                text: text,
                selectedRange: selectedRange
            )
            if !normalTemplateTrigger {
                guard selectedRange.length == 0,
                    selectedRange.location >= 0,
                    let provenance = captureRewriteProvenance,
                    provenance.outputDraft == text,
                    utf8Offset(in: text, utf16Offset: selectedRange.location)
                        == provenance.outputCursorUTF8Offset,
                    let inputSelection = utf16Range(
                        in: provenance.inputDraft,
                        start: provenance.inputCursorUTF8Offset,
                        end: provenance.inputCursorUTF8Offset
                    )?.location,
                    CaptureTemplateStart.isRewriteKeystroke(
                        typed: typed,
                        text: provenance.inputDraft,
                        selectedRange: NSRange(location: inputSelection, length: 0)
                    )
                else {
                    pendingSeparatorToggleIntent = nil
                    return
                }
                var sourceDraft = provenance.inputDraft
                guard
                    let sourceInsertion = stringRange(
                        in: sourceDraft,
                        start: provenance.inputCursorUTF8Offset,
                        end: provenance.inputCursorUTF8Offset
                    )
                else {
                    pendingSeparatorToggleIntent = nil
                    return
                }
                sourceDraft.replaceSubrange(sourceInsertion, with: typed)
                rewriteSource = CaptureRewriteSource(
                    draft: sourceDraft,
                    cursorUTF8Offset: provenance.inputCursorUTF8Offset + typed.utf8.count
                )
            }
        } else {
            guard typed == ":" || typed == "^" || typed == "|",
                  selectedRange.length == 0,
                  selectedRange.location >= 0
            else {
                pendingSeparatorToggleIntent = nil
                return
            }
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
            expectedDraft: expectedDraft,
            expectedCursorUTF8: expectedCursorUTF8,
            rewriteSource: rewriteSource
        )
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
        if captureRewriteProvenance?.outputDraft != draft {
            captureRewriteProvenance = nil
        }
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

        if commitRouteCompletionOnPlus(draft: draft) {
            return
        }

        let insertionOffset = cursorUTF8Offset ?? collapsedSelectionUTF8Offset()
        var analysisCursor = insertionOffset
        let requestCompletion = insertionOffset != nil
        var completionGate: Task<Void, Never>?
        if let intent = consumeSeparatorToggleIntent(
            draft: draft,
            cursorUTF8Offset: insertionOffset
        ) {
            if let source = intent.rewriteSource {
                if insertionOffset == intent.expectedCursorUTF8 {
                    completionGate = startCaptureRewrite(
                        draft: source.draft,
                        cursorUTF8Offset: source.cursorUTF8Offset,
                        visibleDraft: draft,
                        visibleCursorUTF8Offset: intent.expectedCursorUTF8
                    )
                } else {
                    invalidateRewrite()
                }
                analysisCursor = intent.expectedCursorUTF8
            } else {
                completionGate = startCaptureRewrite(
                    draft: draft,
                    cursorUTF8Offset: intent.expectedCursorUTF8
                )
                analysisCursor = intent.expectedCursorUTF8
            }
        } else if let insertionOffset,
                  // A lone declaration has nothing to absorb. This also keeps
                  // the second Undo of a template-start gesture from issuing a
                  // no-op rewrite request when it restores the original `@@`.
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
        Task { [weak self, processClient] in
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
                        spans: parse.spans
                    )
                }
            } catch {
            }
        }
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
        if let expected = rewriteExpectedCursorUTF8 {
            if insertionOffset == expected {
                rewriteSawMatchingSelection = true
            } else {
                let laggedPreInsertCaret =
                    !rewriteSawMatchingSelection
                    && insertionOffset == expected - 1
                if !laggedPreInsertCaret {
                    invalidateRewrite()
                }
            }
        }
        guard !isApplyingProgrammaticDraft, hasDraft else {
            return
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
    // so the user never has to accept the route before opening the task picker.
    // Decides purely from the draft diff against `completionDraftSnapshot` — never
    // from the view-supplied caret, which SwiftUI can report one edit behind.
    private func commitRouteCompletionOnPlus(draft: String) -> Bool {
        guard completionVisible, completionResponse?.context == "route",
              let completionResponse, let snapshot = completionDraftSnapshot
        else {
            return false
        }
        guard selectedCompletion?.kind != "template" else {
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
        let expectedDraft = String(snapshot[prefixRange]) + "+" + String(snapshot[suffixRange])
        guard draft == expectedDraft else {
            return false
        }

        let hasExactTypedMatch = completionResponse.candidates.contains { candidate in
            guard let route = candidate.route else {
                return false
            }
            return route.caseInsensitiveCompare(typed) == .orderedSame
        }

        if hasExactTypedMatch {
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
        let caret = r.start + candidate.replacement.utf8.count + 1
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            return false
        }

        dismissCompletion()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
        return true
    }

    /// True while a close/start draft dangles on a list separator: the visible
    /// card previews the trimmed draft, so Return must not submit it.
    var isClosePending: Bool {
        closePendingText != nil
    }

    func submit(openAfterCapture: Bool) {
        clearOpenHintReveal()
        guard !inlinePromptVisible, !isSubmitting, !isPreviewing, hasDraft else {
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
                requestID: preview.requestID
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
                inboxRouteCapabilityAdvertised: true,
                hasOverride: preview.hasOverride,
                vaultDirectoryIdentity: processClient.vaultDirectoryIdentity
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
            inboxRouteCapabilityAdvertised: preview?.inboxRoute?.supported == true
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
        pullInChoiceForBack: CapturePullInChoiceState? = nil
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
            inboxRouteCapabilityAdvertised: inboxRouteCapabilityAdvertised
                || matchingPreview?.inboxRoute?.supported == true,
            hasOverride: allowsOverride,
            vaultDirectoryIdentity: processClient.vaultDirectoryIdentity
        )
        activeInboxRouteSubmitContext = submitContext
        invalidateRewrite()
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
                        pullInSelection: selection,
                        requirePullInChoice: selection == nil && inboxRouteAnswers == nil,
                        refuseOverride: !allowsOverride,
                        pullInCapabilityAdvertised: capabilityAdvertised,
                        inboxRouteAnswers: inboxRouteAnswers,
                        requireInboxRouteChoice: true,
                        inboxRouteCapabilityAdvertised: submitContext.inboxRouteCapabilityAdvertised,
                        templateOrigin: currentDraftHasTemplate ? templateOrigin : nil
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
        requestID: UUID?
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
        statusText = "Choose successor offers"
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
            announceStatus("Choose successor offers")
        } else {
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
        let keys = choice.effectiveSelectionKeys
        guard !keys.isEmpty else {
            announceStatus("No visible successor offer is selected")
            return
        }
        if openAfterCapture {
            choice.openAfterCapture = true
            pullInChoice = choice
        }
        commitPullInChoice(choice, selection: .keys(keys))
    }

    func chooseNoPullInOffers() {
        guard let choice = pullInChoice, !isSubmitting else {
            return
        }
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
            cancelPullInChoiceFromKeyboard()
            return
        }
        pullInChoice = nil
        clearEditorInputLockIfFree()
        dispatchCapture(
            draft: choice.draftSnapshot,
            openAfterCapture: choice.openAfterCapture,
            selection: selection,
            capabilityAdvertised: choice.pullIn.supported,
            seed: choice.priorityRollSeed,
            inboxRouteCapabilityAdvertised: processClient?.inboxRouteCapabilityKnown == true,
            pullInChoiceForBack: choice
        )
    }

    func cancelPullInChoiceFromKeyboard() {
        guard pullInChoice != nil else {
            return
        }
        pullInChoice = nil
        errorMessage = nil
        errorCode = nil
        clearEditorInputLockIfFree()
        requestFocus(.editor)
        statusText = "Successor choice canceled"
    }

    func movePullInChoiceHighlight(by delta: Int) {
        guard var choice = pullInChoice else {
            return
        }
        choice.moveHighlight(by: delta)
        pullInChoice = choice
        requestFocus(.pullInOfferList)
    }

    func toggleHighlightedPullInOffer() {
        guard var choice = pullInChoice else {
            return
        }
        choice.toggleHighlighted()
        pullInChoice = choice
    }

    func togglePullInOffer(_ key: String) {
        guard var choice = pullInChoice else {
            return
        }
        choice.highlightedKey = key
        choice.toggleHighlighted()
        pullInChoice = choice
        requestFocus(.pullInOfferList)
    }

    func markAllPullInOffers() {
        guard var choice = pullInChoice else {
            return
        }
        choice.markAll()
        pullInChoice = choice
    }

    func updatePullInChoiceFilter(_ text: String) {
        guard var choice = pullInChoice else {
            return
        }
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
            announceStatus(
                "No saved templates yet — type @@@ to start one; capturing it saves it here"
            )
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
            announceStatus("No saved templates yet — type @@@ to start one; capturing it saves it here")
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
        guard currentDraftHasTemplate else {
            announceStatus("Only @@template: drafts can be saved as templates")
            return
        }
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
        selectedCompletionIndex = 0
    }

    func prepareForDismissal() {
        panelVisible = false
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
    }

    func requestFocus(_ target: CapturePanelFocusTarget) {
        focusSequence &+= 1
        focusRequest = CapturePanelFocusRequest(sequence: focusSequence, target: target)
    }

    private func resetAnalysisState() {
        invalidateAnalysis()
        cancelSimilarTasks(clear: true)
        editAnalysisBaseline = plainDraft
        invalidateRewrite()
        cancelInFlightExplicitPreview()
        parseDiagnostics = []
        parsedTemplate = nil
        lastAppliedParseDraft = nil
        lastAppliedParseItemCount = nil
        similarTasksParseItems = []
        similarTasksFolded = false
        completionResponse = nil
        completionDraftSnapshot = nil
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
           inboxRouteChoice == nil, picker == nil
        {
            clearEditorInputLock()
        }
    }

    private func announceStatus(_ message: String) {
        statusText = message
        statusAnnouncementTick += 1
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

    func dismissCompletion() {
        // Esc on the File-under list keeps the default inbox parent: remember
        // the URL so the list does not reopen until the URL changes. Accept
        // paths clear the record after splicing (see
        // `applySelectedCompletionReplacement`).
        if fileUnderActive {
            fileUnderDismissedURL = plainDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        completionResponse = nil
        completionDraftSnapshot = nil
        selectedCompletionIndex = 0
        fileUnderActive = false
    }

    // MARK: - Capture picker

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
                scope: source.blockIDScope
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
    private func handleCompletionResponse(
        _ completion: CaptureCompletionResponse,
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
            dismissCompletion()
            return
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
            await handleParentTaskCompletion(
                completion,
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
            await handleParentTaskCompletion(
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
        dismissCompletion()
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
                scope: context.scope
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
            snapshotIsPartial: snapshotIsPartial
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
        completionResponse = completion.candidates.isEmpty ? nil : completion
        completionDraftSnapshot = completion.candidates.isEmpty ? nil : draft
        selectedCompletionIndex = 0
        // Task-theme suggestion: in `pomodoro_name` with an empty query the
        // initial selection is the first `suggested` row Bob preselected;
        // otherwise it stays 0 and PT7 ranking wins.
        if completion.context == "pomodoro_name",
           completionQueryText().isEmpty,
           let suggested = completion.candidates.firstIndex(where: \.suggested)
        {
            selectedCompletionIndex = suggested
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
    }

    /// An analysis that ends with no completion at all (nothing requested, or
    /// nothing offered) still retires the `^` affordances per trigger.
    private func handleMissingCompletion(trigger: CompletionTrigger) {
        if picker != nil {
            dismissCompletion()
            return
        }
        clearPickerInterruption(trigger: trigger)
        dismissCompletion()
    }

    /// An `.edit` analysis without an `active_task` result leaves the token:
    /// it clears the suppression and the chip. A `.selection` analysis only
    /// ever clears the chip.
    private func clearPickerInterruption(trigger: CompletionTrigger) {
        if trigger == .edit {
            pickerAutoOpenSuppressedStart = nil
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
        dismissCompletion()
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
                    snapshotIsPartial: false
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
                snapshotIsPartial: true
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
            snapshotIsPartial: false
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
        dismissCompletion()
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
                    snapshotIsPartial: false
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
                snapshotIsPartial: true
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
            snapshotIsPartial: false
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
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger
    ) async {
        dismissCompletion()
        guard let context = completion.picker?.parentTaskContext else {
            clearPickerInterruption(trigger: trigger)
            return
        }
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
            snapshotIsPartial: snapshotIsPartial
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
        dismissCompletion()
        let r = completion.replacement
        guard stringRange(in: draft, byteRange: r) != nil,
              stringRange(in: draft, start: r.start, end: min(cursor, r.end)) != nil
        else {
            return
        }
        let source = Self.pickerSource(for: direction)
        guard trigger == .edit, pickerAutoOpenSuppressedStart != r.start else {
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
                    dependencyOwner: snapshot.owner
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
                dependencyOwner: completion.owner
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
            dependencyOwner: completion.owner
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
        dismissCompletion()
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
                    dependencyOwner: snapshot.owner
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
            dependencyOwner: completion.owner
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
        dismissCompletion()
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
                    taskCompleteContinuationKeys: snapshot.picker?.actionContinuationKeys ?? []
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
                taskCompleteContinuationKeys: continuationKeys
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
            taskCompleteContinuationKeys: continuationKeys
        )
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

    private func presentPicker(
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
        taskCompleteContinuationKeys: [String] = []
    ) {
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
            selectedRowID: CapturePickerNavigation.first(in: presentation.orderedRowIDs),
            visibleRowBudget: presentation.visibleRowBudget,
            snapshotIsPartial: snapshotIsPartial,
            scopeLineNumber: scopeLine,
            dependencyOwner: dependencyOwner,
            taskCompleteContinuationKeys: taskCompleteContinuationKeys
        )
        pickerMarkerHighlight = markerRange
        applyPickerMarkerHighlight()
        dismissCompletion()
        pickerChip = nil
        editorInputLocked = true
        applyOwnerModeParentStatus(source: source)
        requestFocus(.pickerFilter)
    }

    private func applyOwnerModeParentStatus(source: CapturePickerSource) {
        if case .parentTask(let context) = source, context.isOwnerMode {
            statusText = CaptureRelationshipCopy.relateStatusText
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
        case .blockID:
            return markerRange ?? replacementRange
        case .parentTask(let context):
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
        isApplyingProgrammaticDraft = true
        attributedDraft.transform(updating: &editorSelection) { text in
            guard let lower = AttributedString.Index(stringRange.lowerBound, within: text),
                  let upper = AttributedString.Index(stringRange.upperBound, within: text)
            else {
                return
            }
            text[lower..<upper].backgroundColor = nil
        }
        isApplyingProgrammaticDraft = false
    }

    func updatePickerFilter(_ text: String) {
        guard var updated = picker,
              let index = pickerIndex
        else {
            return
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
    /// `#` opens Pomodoro-name completion; the caret sits past the committed
    /// token, so the ID picker cannot reopen for it.
    private func commitBlockIDTypeThrough(id: String, remainder: String) {
        guard let openPicker = picker,
              plainDraft == openPicker.draftSnapshot,
              let idRange = stringRange(in: plainDraft, byteRange: openPicker.replacementRange)
        else {
            // The draft moved under the picker: never edit a stale draft.
            closePickerAfterStaleDraft()
            return
        }
        var text = plainDraft
        text.replaceSubrange(idRange, with: id + remainder)
        let caret = openPicker.replacementRange.start + (id + remainder).utf8.count
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            closePickerAfterStaleDraft()
            return
        }
        closePickerForAccept()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: true, trigger: .edit)
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
        movePickerSelection { CapturePickerNavigation.next(after: $0, in: $1) }
    }

    func selectPreviousPickerRow() {
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
        guard let selectedRowID = picker?.selectedRowID else {
            // An empty-list accept is a no-op.
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
        guard let insertion = row.insertion else {
            if case .blockID = picker.source {
                announceStatus(
                    Self.blockIDNoAcceptReason(filter: picker.filterText, presentation: pickerPresentation)
                )
            } else if picker.source.isRelationshipModifier
                || picker.source == .taskComplete
            {
                // Already-added and guarded rows keep the draft unchanged and
                // say why, leaving the picker open.
                announceStatus(row.badgeText ?? "That task cannot be used yet")
            } else if case .parentTask = picker.source {
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
        var text = plainDraft
        text.replaceSubrange(range, with: insertionText)
        let caret = picker.replacementRange.start + insertionText.utf8.count
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
            if context.scope == .projectTask {
                announceStatus("Inserted \(context.marker)\(insertionText)")
            } else {
                announceStatus("Inserted @\(context.route)\(context.marker)\(insertionText)")
            }
        } else if source == .taskLink || source.isRelationshipModifier || source == .taskComplete {
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
            submit(openAfterCapture: followUp == .submitAndOpen)
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
    /// "Already in this draft". Only the Complete source maps here.
    func acceptPickerRowAndContinue(id: String) {
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
        let range = openPicker.replacementRange
        clearPickerMarkerHighlight(draftSnapshot: openPicker.draftSnapshot)
        picker = nil
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
            candidates: openPicker.candidates,
            warnings: openPicker.warnings
        )
    }

    /// `~` anywhere in a relation picker filter flips the direction in
    /// place: it inserts or removes one tilde at the sigil, keeps the picker
    /// open with the filter untouched, and never suppresses auto-open.
    /// Analysis then live-flips `relation_to` ↔ `relation_from`.
    func flipRelationDirection() {
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
    /// for the marker. Otherwise behaves like cancel.
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
        } else if case .parentTask(let context) = chip.source {
            query = Self.parentTaskPickerQuery(in: draft, range: r, cursor: chip.cursor, context: context)
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
        } else if let direction = chip.source.dependencyDirection {
            needsRefetch = chip.cursor > r.start + direction.leadingSigil.utf8.count
        } else if case .parentTask(let context) = chip.source {
            needsRefetch = context.isVault ? chip.cursor > r.start + 1 : chip.cursor != r.start
        } else {
            needsRefetch = chip.cursor != r.start
        }
        if needsRefetch, let processClient {
            // The chip came from a caret snapshot; refetch the full list at
            // the token start. A keystroke in the meantime abandons the open.
            Task { [weak self, processClient] in
                guard let snapshot = try? await processClient.captureComplete(draft, cursor: r.start) else {
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.pickerChip?.draftSnapshot == draft,
                          self.plainDraft == draft,
                          snapshot.replacement == r
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
                        guard snapshot.context == "task_goto" else {
                            return
                        }
                        self.presentPicker(
                            source: chip.source,
                            index: Self.taskCatalogIndex(
                                source: chip.source,
                                candidates: snapshot.candidates
                            ),
                            candidates: snapshot.candidates,
                            warnings: snapshot.warnings,
                            draft: draft,
                            range: r,
                            restoreCursor: chip.cursor,
                            query: query,
                            snapshotIsPartial: false
                        )
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
                snapshotIsPartial: false
            )
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
                        scope: context.scope
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
    /// `block_id`, then `template_row`, then the `=<X>#` named-start
    /// incomplete, checked top-level or in any item.
    /// Suffix-only states such as `@sase:x#` (`pomodoro_name` without a
    /// `pomodoro_start` object) keep today's behavior.
    private static func pickerNeed(in parse: CaptureParseResponse) -> CapturePickerNeed? {
        let itemNeeds = parse.items.flatMap { $0.needs }
        func needs(_ need: String) -> Bool {
            parse.needs.contains(need) || itemNeeds.contains(need)
        }
        if needs("active_task") {
            return .activeTask
        }
        if needs("task_link") {
            return .taskLink
        }
        if needs("task_goto") {
            return .taskGoto
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
        if needs("dependency_target") {
            return .dependencyTarget
        }
        if needs("pomodoro_id") {
            return .pomodoroID
        }
        if needs("block_id") {
            return .blockID
        }
        if needs("template_row") {
            return .templateRow
        }
        // A `=<X>#` draft (or chain token) is `incomplete` with a
        // `pomodoro_name` need and a partial `pomodoro_start` spec. It keeps
        // the completion list open while the preview stays calm.
        let scopes: [(mode: String, needs: [String], hasStart: Bool)] =
            if parse.items.isEmpty {
                [(parse.mode, parse.needs, parse.pomodoroStart != nil)]
            } else {
                parse.items.map { ($0.mode, $0.needs, $0.pomodoroStart != nil) }
            }
        if scopes.contains(where: {
            $0.mode == "incomplete" && $0.needs.contains("pomodoro_name") && $0.hasStart
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
        if let openPicker = picker {
            clearPickerMarkerHighlight(draftSnapshot: openPicker.draftSnapshot)
        }
        picker = nil
        pickerPresentation = nil
        pickerIndex = nil
        pickerChip = nil
        clearEditorInputLockIfFree()
        requestFocus(.editor)
    }

    private func closePickerAfterStaleDraft() {
        if let openPicker = picker {
            clearPickerMarkerHighlight(draftSnapshot: openPicker.draftSnapshot)
        }
        picker = nil
        pickerPresentation = nil
        pickerIndex = nil
        clearEditorInputLockIfFree()
        requestFocus(.editor)
        announceStatus("Draft changed — reopen the task picker")
    }

    /// Hide path: close the picker without suppression, restore the caret,
    /// and clear the chip. Re-show reopens via the retained-draft analysis.
    private func closePickerForDismissal() {
        guard let openPicker = picker else {
            pickerMarkerHighlight = nil
            pickerChip = nil
            pickerAutoOpenSuppressedStart = nil
            return
        }
        clearPickerMarkerHighlight(draftSnapshot: openPicker.draftSnapshot)
        editAnalysisBaseline = ""
        picker = nil
        pickerPresentation = nil
        pickerIndex = nil
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
        pickerPresentation = nil
        pickerIndex = nil
        pickerChip = nil
        pickerAutoOpenSuppressedStart = nil
    }

    func selectNextCompletion() {
        guard let count = completionResponse?.candidates.count, count > 0 else {
            return
        }
        selectedCompletionIndex = (selectedCompletionIndex + 1) % count
    }

    func selectPreviousCompletion() {
        guard let count = completionResponse?.candidates.count, count > 0 else {
            return
        }
        selectedCompletionIndex = (selectedCompletionIndex + count - 1) % count
    }

    func acceptSelectedCompletionThenSubmitAndOpen() {
        let isTemplateHeader = selectedCompletion?.kind == "template"
        guard acceptSelectedCompletion(),
              !isTemplateHeader,
              !completionVisible,
              !pickerVisible,
              !inlinePromptVisible,
              hasDraft
        else {
            return
        }
        submit(openAfterCapture: true)
    }

    @discardableResult
    func acceptSelectedCompletion() -> Bool {
        guard let completionResponse,
              let candidate = selectedCompletion,
              let range = stringRange(in: plainDraft, byteRange: completionResponse.replacement)
        else {
            statusText = "Completion range is stale"
            dismissCompletion()
            return false
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

        if completionResponse.context == "pomodoro_name", candidate.createsPomodoro {
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
        // for the pending named start.
        if completionResponse.context == "pomodoro_name"
            || completionResponse.context == "pomodoro_start_name",
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
        let cursor = candidate.cursorAfter ?? completionResponse.replacement.start + candidate.replacement.utf8.count
        guard stringRange(in: text, start: cursor, end: cursor) != nil else {
            statusText = "Completion cursor is stale"
            dismissCompletion()
            return false
        }

        // A File-under accept files the link under the chosen route, so the
        // Esc record for the bare URL must not survive the splice (the
        // dismiss below runs while the draft is still bare).
        let wasFileUnder = fileUnderActive
        dismissCompletion()
        if wasFileUnder {
            fileUnderDismissedURL = nil
        }
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(
            text,
            cursorUTF8Offset: cursor,
            suppressSelectionCallbacks: true
        )
        scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false, trigger: .edit)
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
        case .parentTaskPicker(_, _, _, _, let pickerSnapshot, _):
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
            case .activeTask:
                index = .activeTask(ActiveTaskPickerIndex(candidates: returnPicker.candidates))
            case .blockID:
                index = .taskLink(TaskLinkPickerIndex(candidates: returnPicker.candidates))
            case .parentTask(let context):
                index = .parentTask(
                    ParentTaskPickerIndex(candidates: returnPicker.candidates, context: context)
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
                statusText = context.isOwnerMode
                    ? CaptureRelationshipCopy.relateStatusText
                    : CapturePickerNeed.taskParent.statusText
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

    /// Palette role for the live-sentence label pill: the close-effect
    /// tint when the active row carries one, else the mint relation sigil.
    var relationLabelCloseEffectCategory: CaptureSemanticCategory {
        let candidate = relationLabelSelectedCandidate ?? relationLabelFreshTypedRow
        if candidate?.completesSource == true {
            return .relationCompleteLabel
        }
        if candidate?.cancelsSource == true {
            return .relationCancelLabel
        }
        return .relationSigil
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

    /// The close-effect slot: the complete slot when it applies, else the
    /// cancel slot.
    var relationLabelCloseSlot: (text: String, isClosing: Bool, effect: RelationSourceEffect)? {
        if let complete = relationLabelCompleteSlot {
            return (
                text: complete.text,
                isClosing: complete.style == .completes,
                effect: .complete
            )
        }
        if let cancel = relationLabelCancelSlot {
            return (
                text: cancel.text,
                isClosing: cancel.style == .cancels,
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

    /// Shift-Return on a relation picker row: insert the token like Return,
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
            relationComplete: nil
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
        prompt.pendingSubmit = false
        prompt.errorMessage = nil
        prompt.noticeMessage = nil
        relationLabelPrompt = prompt
        fetchRelationLabelSuggestions()
    }

    /// Ctrl+D with no selection toggles one-off for the typed label.
    /// Ctrl+D is always consumed; key auto-repeat is ignored by the router.
    func toggleRelationLabelOneOff() {
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
        moveRelationLabelSelection(by: 1)
    }

    func cycleRelationLabelSuggestionBackward() {
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
        guard !relationLabelPromptIsSaving, relationLabelPrompt?.rename == nil else { return }
        guard let candidate = relationLabelSelectedCandidate ?? relationLabelPromptRows.first else {
            guard var prompt = relationLabelPrompt else { return }
            prompt.errorMessage = relationLabelPromptHint ?? "No matching labels · type a relation name"
            relationLabelPrompt = prompt
            return
        }
        insertRelationLabelSuggestion(candidate: candidate)
    }

    func insertRelationLabelSuggestion(id: String) {
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
        items.append(("esc", "back"))
        return Array(items.prefix(5))
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
        guard var prompt = relationLabelPrompt, !prompt.isSaving, prompt.rename == nil else { return }
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
        if relationLabelPrompt?.rename != nil {
            submitRelationLabelRename()
            return
        }
        if let selected = relationLabelSelectedCandidate {
            insertRelationLabelSuggestion(candidate: selected)
            return
        }
        submitAuthoredRelationLabel()
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
        let returnPicker = prompt.returnPicker
        let restoreCursor = prompt.restoreCursor
        clearRelationLabelPrompt()
        if let returnPicker {
            picker = returnPicker
            pickerPresentation = pickerIndex?.presentation(filter: returnPicker.filterText)
            editorInputLocked = true
            requestFocus(.pickerFilter)
            statusText = "Pick a task to link"
        } else {
            if stringRange(in: plainDraft, start: restoreCursor, end: restoreCursor) != nil {
                setPlainDraft(plainDraft, cursorUTF8Offset: restoreCursor, suppressSelectionCallbacks: true)
            }
            statusText = "Ready"
            requestFocus(.editor)
        }
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
            relationLabelPrompt = opened
            if opened.hiddenCount > 0 {
                fetchRelationLabelHiddenRows()
            }
        }
    }

    /// Preview hook: mount the relation-label card production presents for a
    /// Shift-Return relation pick, so design tests render the card production
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
        relationComplete: CaptureCompletionRelationComplete? = nil
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
            relationComplete: relationComplete
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
        lastRelationGrammar = hasGrammar ? 1 : nil
        if draft.contains("~") && !hasGrammar {
            relationCapabilityWarning =
                "This bob predates ~ links; ~ text would be captured literally · update bob"
        } else {
            relationCapabilityWarning = nil
        }
        relationCapabilityAcknowledgedDraft = nil
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

        let hidden = temporarilyHiddenThemeKey != theme.key
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
                    self.temporarilyHiddenThemeKey = hidden && draftIsUnchanged ? theme.key : nil
                    self.hiddenThemeDraftSnapshot = hidden && draftIsUnchanged ? draftSnapshot : nil
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
              completionResponse.context == "pomodoro_name"
                || completionResponse.context == "pomodoro_start_name",
              completionResponse.candidates.indices.contains(selectedCompletionIndex)
        else {
            return nil
        }
        let candidate = completionResponse.candidates[selectedCompletionIndex]
        guard candidate.origin == "history",
              candidate.name?.isEmpty == false,
              !candidate.themes.isEmpty
        else {
            return nil
        }
        return candidate
    }

    private func completionQueryText() -> String {
        guard let completionResponse,
              let range = stringRange(
                  in: plainDraft,
                  start: completionResponse.replacement.start,
                  end: min(completionResponse.cursor, completionResponse.replacement.end)
              )
        else {
            return ""
        }
        return String(plainDraft[range])
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
        case .parentTaskPicker(_, _, let parentSuggestions, _, _, _):
            suggestions = parentSuggestions
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
                    submit(openAfterCapture: followUp == .submitAndOpen)
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
                    submit(openAfterCapture: followUp == .submitAndOpen)
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
                    submit(openAfterCapture: followUp == .submitAndOpen)
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
        case .open, .discard, .unknown:
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
            submit(openAfterCapture: followUp == .submitAndOpen)
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
            submit(openAfterCapture: followUp == .submitAndOpen)
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
            submit(openAfterCapture: followUp == .submitAndOpen)
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
            errorMessage = nil
            errorCode = nil
            setPlainDraft("")
            suppressedCompletionAcceptanceDraft = nil
            priorityRollSeed = nil
            parseDiagnostics = []
            parsedTemplate = nil
            lastAppliedParseDraft = nil
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
            if failure.code == "pull_in_choice_required" {
                guard let processClient,
                      plainDraft == draft,
                      processClient.identityToken == processClientIdentity,
                      let pullIn = failure.pullIn,
                      pullIn.supported
                else {
                    errorMessage = "Bob's successor offer response was incomplete or stale. Preview again before submitting."
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
                    requestID: requestID
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
                    statusText = "Capture failed"
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
            previewPullInSnapshot = nil
            errorMessage = failure.error
            errorCode = failure.code
            statusText = "Capture failed"
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
        statusText = "Capture failed"
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
                globalDestination: success.globalDestination
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
        case .failure(let failure):
            // A failed explicit dry run drops the preview result for the same
            // reason `failPreview` does: no stale card beside the red error.
            clearPreviewOutputs()
            previewPullInSnapshot = nil
            errorMessage = failure.error
            errorCode = failure.code
            statusText = "Preview failed"
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
                stillBlocked.append(contentsOf: complete.stillBlocked)
            }
            if let close = capture.pomodoroClose {
                offers.append(contentsOf: close.unblocked)
                stillBlocked.append(contentsOf: close.stillBlocked)
            }
            // Complete-label commits offer successors exactly like `!`:
            // the close carries the same `task_complete` offers.
            for relationComplete in capture.relationCompletes {
                guard let complete = relationComplete.taskComplete else {
                    continue
                }
                offers.append(contentsOf: complete.unblocked)
                stillBlocked.append(contentsOf: complete.stillBlocked)
            }
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
            }
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
        statusText = "Preview failed"
    }

    private func setPlainDraft(
        _ text: String,
        cursorUTF8Offset: Int? = nil,
        suppressSelectionCallbacks: Bool = false
    ) {
        let previousDraft = plainDraft
        if captureRewriteProvenance?.outputDraft != text {
            captureRewriteProvenance = nil
        }
        if text.isEmpty {
            templateOrigin = nil
        }
        if previousDraft != text {
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
        closeCommaProvenance.clear()
        lastProvenanceDraft = text
        isApplyingProgrammaticDraft = true
        attributedDraft = AttributedString(text)
        restoreSelection(
            cursorUTF8Offset: cursorUTF8Offset ?? text.utf8.count,
            suppressEditorCallbacks: suppressSelectionCallbacks
        )
        isApplyingProgrammaticDraft = false
    }

    /// `completionGate` holds this analysis's completion request until that task
    /// settles. An accepted correction reschedules the analysis meanwhile, which
    /// supersedes this one; any other outcome completes as if ungated.
    private func scheduleAnalysis(
        cursorUTF8Offset: Int?,
        requestCompletion: Bool,
        trigger: CompletionTrigger,
        completionGate: Task<Void, Never>? = nil
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

        let draft = plainDraft
        if overrideRefusalDraft != draft {
            overrideRefusalDraft = nil
        }
        let writtenRange = trigger == .edit
            ? captureWrittenByteRange(from: editAnalysisBaseline, to: draft)
            : nil
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
        let debounceNanoseconds = self.debounceNanoseconds
        analysisTask?.cancel()
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
                    self?.applyParse(parse, draft: draft, cursorUTF8: cursorUTF8Offset)
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

                if pickerNeeded == nil {
                    await self?.startLivePreview(
                        draft: draft,
                        previewDraft: closePending?.trimmed ?? draft,
                        pendingSeparator: closePending?.separator,
                        pendingAction: closePending?.action,
                        generation: generation,
                        processClient: processClient,
                        trigger: trigger
                    )
                }

                if requestCompletion, let completionGate {
                    await completionGate.value
                    try Task.checkCancellation()
                    guard await self?.isCurrentAnalysis(generation) == true else {
                        return
                    }
                }

                if let cursorUTF8Offset,
                   requestCompletion,
                   await self?.shouldRequestCompletion(
                       parse: parse,
                       cursor: cursorUTF8Offset,
                       draft: draft
                   ) == true
                {
                    if let cached = await self?.cachedRouteCompletion(
                        parse: parse,
                        cursor: cursorUTF8Offset,
                        draft: draft
                    ) {
                        await MainActor.run {
                            guard self?.isCurrentAnalysis(generation) == true else {
                                return
                            }
                            self?.applyNonActiveTaskCompletion(
                                cached,
                                draft: draft,
                                trigger: trigger
                            )
                            self?.editAnalysisBaseline = draft
                        }
                        return
                    }

                    do {
                        let completion = try await CaptureSignpost.measure("completion") {
                            try await processClient.captureComplete(
                                draft,
                                cursor: cursorUTF8Offset
                            )
                        }
                        await self?.handleCompletionResponse(
                            completion,
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
                } else {
                    await MainActor.run {
                        guard self?.isCurrentAnalysis(generation) == true else {
                            return
                        }
                        self?.handleMissingCompletion(trigger: trigger)
                        self?.editAnalysisBaseline = draft
                    }
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
        visibleDraft: String? = nil,
        visibleCursorUTF8Offset: Int? = nil
    ) -> Task<Void, Never>? {
        guard let processClient else {
            return nil
        }

        let expectedVisibleDraft = visibleDraft ?? draft
        let expectedVisibleCursor = visibleCursorUTF8Offset ?? cursorUTF8Offset
        rewriteGeneration &+= 1
        let generation = rewriteGeneration
        rewriteExpectedCursorUTF8 = expectedVisibleCursor
        rewriteSawMatchingSelection = collapsedSelectionUTF8Offset() == expectedVisibleCursor
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
                        visibleDraft: expectedVisibleDraft,
                        visibleCursorUTF8Offset: expectedVisibleCursor,
                        generation: generation,
                        processClient: processClient
                    )
                }
            } catch is CancellationError {
            } catch {
                // Rewriting is a typing assist. Parse, completion, and preview still run
                // on the original draft, so transport failures should not disturb the UI.
            }
        }
        rewriteTask = task
        return task
    }

    private func applyCaptureRewrite(
        _ response: CaptureRewriteResponse,
        draft: String,
        cursorUTF8Offset: Int,
        visibleDraft: String,
        visibleCursorUTF8Offset: Int,
        generation: UInt64,
        processClient: BobProcessClient
    ) {
        guard rewriteGeneration == generation,
              self.processClient === processClient,
            plainDraft == visibleDraft,
            response.input == draft
        else {
            return
        }
        if draft != visibleDraft {
            guard collapsedSelectionUTF8Offset() == visibleCursorUTF8Offset,
                response.changed,
                response.rule == CaptureTemplateStart.rewriteRule,
                let cursor = response.cursor,
                stringRange(in: response.text, start: cursor, end: cursor) != nil
            else {
                return
            }
            applyNativeWholeDraftRewrite(
                response,
                expectedDraft: visibleDraft,
                cursorUTF8Offset: cursor
            )
            return
        }
        if let current = collapsedSelectionUTF8Offset(), current != visibleCursorUTF8Offset {
            return
        }

        if response.changed {
            if let cursor = response.cursor,
               stringRange(in: response.text, start: cursor, end: cursor) == nil
            {
                return
            }

            if response.rule == "switch_block_id_separator"
                || response.rule == "attach_relation_label"
                || response.rule == CaptureTemplateStart.rewriteRule
            {
                applyNativeSingleEditRewrite(response, draft: draft)
                return
            }

            let cursor = response.cursor ?? response.text.utf8.count
            suppressedCompletionAcceptanceDraft = response.text
            setPlainDraft(
                response.text,
                cursorUTF8Offset: cursor,
                suppressSelectionCallbacks: true
            )
            if response.rule == "absorb_local_marker"
                || response.rule == "absorb_declaration"
            {
                captureRewriteProvenance = CaptureRewriteProvenance(
                    inputDraft: draft,
                    inputCursorUTF8Offset: cursorUTF8Offset,
                    outputDraft: response.text,
                    outputCursorUTF8Offset: cursor
                )
            }
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
        draft: String
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
            cursorUTF8Offset: cursor
        )
    }

    private func applyNativeWholeDraftRewrite(
        _ response: CaptureRewriteResponse,
        expectedDraft: String,
        cursorUTF8Offset: Int
    ) {
        guard
            let cursorUTF16 = utf16Range(
                in: response.text,
                start: cursorUTF8Offset,
                end: cursorUTF8Offset
            )?.location
        else {
            return
        }
        applyNativeRewrite(
            CaptureNativeRewriteEdit(
                replacementRange: NSRange(
                    location: 0,
                    length: (expectedDraft as NSString).length
                ),
                replacementText: response.text,
                resultingSelection: NSRange(location: cursorUTF16, length: 0),
                expectedDraft: expectedDraft,
                resultingDraft: response.text
            ),
            response: response,
            cursorUTF8Offset: cursorUTF8Offset
        )
    }

    private func applyNativeRewrite(
        _ nativeEdit: CaptureNativeRewriteEdit,
        response: CaptureRewriteResponse,
        cursorUTF8Offset: Int
    ) {
        suppressedCompletionAcceptanceDraft = response.text
        guard applyNativeRewriteEdit?(nativeEdit) == true else {
            suppressedCompletionAcceptanceDraft = nil
            return
        }
        if plainDraft != response.text {
            isApplyingProgrammaticDraft = true
            attributedDraft = AttributedString(response.text)
            isApplyingProgrammaticDraft = false
        }
        restoreSelection(cursorUTF8Offset: cursorUTF8Offset, suppressEditorCallbacks: true)
        if response.rule == CaptureTemplateStart.rewriteRule,
            completionVisible,
            completionResponse?.context == "route"
        {
            dismissCompletion()
        }
        if let summary = response.summary, !summary.isEmpty {
            announceStatus(summary)
        }
        scheduleAnalysis(
            cursorUTF8Offset: cursorUTF8Offset,
            requestCompletion: response.rule == "attach_relation_label",
            trigger: .edit
        )
        rewriteExpectedCursorUTF8 = nil
        rewriteSawMatchingSelection = false
    }

    private func startLivePreview(
        draft: String,
        previewDraft: String,
        pendingSeparator: String?,
        pendingAction: String?,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger
    ) {
        Task { [weak self, processClient] in
            do {
                let seed = await self?.activePriorityRollSeed() ?? UUID().uuidString
                let processClientIdentity = processClient.identityToken
                let preview = try await CaptureSignpost.measure("preview") {
                    try await processClient.captureLivePreview(
                        previewDraft,
                        priorityRollSeed: seed
                    )
                }
                await MainActor.run {
                    guard self?.isCurrentAnalysis(generation) == true else {
                        return
                    }
                    switch preview {
                    case .success(let success):
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
                            globalDestination: success.globalDestination
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
                        } else if self?.statusText == "Preview failed" {
                            // A successful live preview that sets no
                            // kind-specific status clears a stale failure
                            // footer; empty reads as Ready. Any other text,
                            // such as rewrite notices, is left untouched.
                            self?.statusText = ""
                        }
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
                        self?.previewState = .failed(failure.error)
                        // Like `failPreview`: a failed live dry run must never
                        // leave a stale card beside the red error.
                        self?.clearPreviewOutputs()
                        self?.previewPullInSnapshot = nil
                        self?.closePendingText = nil
                        self?.closePendingAction = "Close"
                        self?.errorMessage = failure.error
                        self?.errorCode = failure.code
                        self?.statusText = "Preview failed"
                    }
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

    private func isCurrentAnalysis(_ generation: UInt64) -> Bool {
        generation == analysisGeneration
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
        cancelSimilarTasks(clear: false)
    }

    private func invalidateRewrite() {
        rewriteTask?.cancel()
        rewriteTask = nil
        rewriteGeneration &+= 1
        rewriteExpectedCursorUTF8 = nil
        rewriteSawMatchingSelection = false
        pendingSeparatorToggleIntent = nil
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

    private func applyParse(
        _ parse: CaptureParseResponse,
        draft: String,
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
                spans: parse.spans
            )
        }
        applyHighlighting(parse: parse, draft: draft, cursorUTF8: cursorUTF8)

        if let diagnostic = parse.diagnostics.first(where: { $0.severity != "info" }) {
            statusText = diagnostic.message
        } else if statusText == "Ready" || statusText.isEmpty || statusText == "Target cache stale" {
            statusText = "Ready"
        }
    }

    private func applyHighlighting(
        parse: CaptureParseResponse,
        draft: String,
        cursorUTF8: Int? = nil
    ) {
        guard let ranges = validatedSpanRanges(in: draft, spans: parse.spans) else {
            statusText = "Ignored malformed parse spans"
            return
        }

        guard plainDraft == draft else {
            return
        }
        var ignoredMalformedSpan = false
        isApplyingProgrammaticDraft = true
        attributedDraft.transform(updating: &editorSelection) { text in
            ignoredMalformedSpan = Self.paintHighlighting(
                &text,
                parse: parse,
                draft: draft,
                ranges: ranges,
                cursorUTF8: cursorUTF8 ?? collapsedSelectionUTF8Offset()
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

    /// Typed text inherits the previous character's attributes, so clear every
    /// attribute owned by an editor painter before painting current spans.
    static func clearEditorHighlightAttributes(_ text: inout AttributedString) {
        text.foregroundColor = nil
        text.backgroundColor = nil
        text.underlineStyle = nil
        text.underlineColor = nil
        text.inlinePresentationIntent = nil
    }

    @discardableResult
    static func paintHighlighting(
        _ text: inout AttributedString,
        parse: CaptureParseResponse,
        draft: String,
        ranges: [ValidatedCaptureSpan],
        cursorUTF8: Int? = nil
    ) -> Bool {
        clearEditorHighlightAttributes(&text)
        for item in ranges {
            guard let lower = AttributedString.Index(item.range.lowerBound, within: text),
                  let upper = AttributedString.Index(item.range.upperBound, within: text)
            else {
                return true
            }

            let category = captureSemanticCategory(forSpan: item.span)
            text[lower..<upper].foregroundColor = CaptureEditorPalette.color(for: category)
            if category.isUnderlined {
                text[lower..<upper].underlineStyle = .single
            }
            if category.isItalic {
                text[lower..<upper].inlinePresentationIntent = .emphasized
            }
            // Theme tints wash Bob's hue behind each known component of a name.
            // Unconfigured names take a dashed orange underline once the caret
            // leaves the component, matching the Typing rule for unknown names.
            if item.span.kind == "pomodoro_name"
                || item.span.kind == "task_toggle_pomodoro_name"
            {
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
                }
            }
        }
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

    private func shouldRequestCompletion(
        parse: CaptureParseResponse,
        cursor: Int,
        draft: String
    ) -> Bool {
        if Self.leadingSingleAtRouteReplacementRange(in: draft, cursor: cursor) != nil {
            return true
        }

        let completionNeeds = Set([
            "route", "section", "pomodoro_id", "pomodoro_name", "task", "task_section",
            "active_task", "task_link", "task_goto", "task_parent", "task_dependency", "blocked_task",
            "relation_target", "relation_to", "relation_from", "relation_label",
            "dependency_target", "task_complete", "block_id",
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
            "section",
            "task_block_id_route",
            "task_block_id",
            "pomodoro_route",
            "pomodoro_block_id",
            "project_task_link_marker",
            "project_task_block_id",
            "pomodoro_name",
            "sub_bullet_route",
            "sub_bullet_block_id",
            "sub_bullet_section",
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
            "global_sub_bullet_route",
            "global_sub_bullet_block_id",
            "interactive_placeholder",
            "pomodoro_adjust",
            "wikilink_delimiter",
            "wikilink_target",
            "wikilink_heading",
            "wikilink_block_id",
            "wikilink_alias",
            "pomodoro_close_drop",
            "pomodoro_close_park",
            "pomodoro_start_drop",
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
                    replacement: target.route,
                    route: target.route,
                    label: target.label,
                    kind: target.kind,
                    status: target.status,
                    alias: aliasHint(for: target, query: query)
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
        guard let targets = targetCacheSnapshot.targets?.targets, !targets.isEmpty else {
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
                    route: target.route,
                    label: target.label,
                    kind: target.kind,
                    status: target.status,
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
            "task_block_id_route",
            "pomodoro_route",
            "sub_bullet_route",
            "global_route",
            "global_sub_bullet_route",
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

    /// Route completion ranking, owned by `CaptureRefFileUnder` so the
    /// `@`-typed list filters exactly like File under: canonical prefix
    /// matches first, then alias-prefix matches, then every other
    /// substring match (aliases included).
    private func rankedTargets(_ targets: [CaptureTarget], query: String) -> [CaptureTarget] {
        CaptureRefFileUnder.rankedTargets(targets, query: query)
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
            return "\(prefix) \u{2192} All items \u{2192} \(globalDestination.scopeSummary)\(overrides): \(sample)"
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
            return "\(prefix) \(captures.count) items \u{00b7} All items \u{2192} \(globalDestination.scopeSummary)\(overrides)"
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
