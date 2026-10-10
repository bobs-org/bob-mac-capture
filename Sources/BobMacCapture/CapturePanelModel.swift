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

/// What follows a successful Add block ID assignment.
enum CaptureTaskLinkFollowUp: Equatable, Sendable {
    case none
    case start
    case submit
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
    /// this source: only `.none` and `.submit` occur. `allowClosed` permits
    /// Done/Cancelled history rows without reopening them.
    case dependency(
        notePath: String,
        taskRef: String,
        suggestions: [String],
        followUp: CaptureTaskLinkFollowUp,
        returnPicker: CapturePickerState,
        allowClosed: Bool = false
    )
    /// Complete mode for an ID-less `!` row: name the task with the exact
    /// vault-relative note path (never the lowercased route), then splice
    /// Bob's `complete_replacement`. Only `.none` and `.submit` occur:
    /// Shift-Return chains via the picker, never via the prompt.
    case taskComplete(
        notePath: String,
        taskRef: String,
        suggestions: [String],
        followUp: CaptureTaskLinkFollowUp,
        returnPicker: CapturePickerState
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
        if case .taskComplete(_, _, let suggestions, _, _) = purpose {
            return suggestions
        }
        if case .parentTaskPicker(_, _, let suggestions, _, _, _) = purpose {
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
        if case .taskComplete(_, _, _, let followUp, _) = purpose {
            return followUp
        }
        if case .parentTaskPicker(_, _, _, let followUp, _, _) = purpose {
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
    var isSaving: Bool
    var errorMessage: String?
}

enum CapturePanelFocusTarget: Hashable {
    case editor
    /// Model-level focus intent owned by `BlockIDField` / AppKit, not `@FocusState`.
    case taskIDPromptBlockID
    /// Model-level focus intent owned by `PomodoroNameField` / AppKit, not `@FocusState`.
    case pomodoroNamePromptName
    /// Model-level focus intent owned by `CapturePickerFilterField` / AppKit,
    /// not `@FocusState`.
    case pickerFilter
}

struct CapturePanelFocusRequest: Equatable {
    let sequence: UInt64
    let target: CapturePanelFocusTarget
}

@MainActor
final class CapturePanelModel: ObservableObject {
    @Published var attributedDraft = AttributedString()
    @Published var editorSelection = AttributedTextSelection()
    @Published var statusText = ""
    @Published var previewState: CapturePreviewState = .idle
    @Published var parseDiagnostics: [CaptureDiagnostic] = []
    @Published var completionResponse: CaptureCompletionResponse?
    @Published var selectedCompletionIndex = 0
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
    @Published var lastSuccess: CaptureCommandSuccess?
    @Published var previewResult: CaptureCommandSuccess?
    @Published var lastSuccessResults: [CaptureCommandSuccess] = []
    @Published var previewResults: [CaptureCommandSuccess] = []
    @Published var lastSuccessGlobalDestination: CaptureGlobalDestination?
    @Published var previewGlobalDestination: CaptureGlobalDestination?
    // Incremented on every successful capture so the view can drive a VoiceOver
    // announcement without needing `CaptureCommandSuccess` to be diffed for equality.
    @Published var successAnnouncementTick = 0
    @Published var statusAnnouncementTick = 0
    @Published var isStashPickerPresented = false
    @Published var selectedStashIndex = 0
    @Published var taskIDPrompt: CaptureTaskIDPromptState?
    @Published var pomodoroNamePrompt: CapturePomodoroNamePromptState?
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

    var processClient: BobProcessClient?
    var notificationService: NotificationService?
    var targetOpener: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var panelDismisser: () -> Void = {}
    let canceledDraftStash: CanceledDraftStash

    private let debounceNanoseconds: UInt64
    private var analysisTask: Task<Void, Never>?
    private var rewriteTask: Task<Void, Never>?
    private var stashCancellable: AnyCancellable?
    private var analysisGeneration: UInt64 = 0
    private var isApplyingProgrammaticDraft = false
    // SwiftUI can deliver the text-change callback after a programmatic binding update.
    // Remember the accepted value so that callback cannot start completion analysis again.
    private var suppressedCompletionAcceptanceDraft: String?
    // The draft that produced the visible `completionResponse`, so a `+` commit can
    // locate the route text by byte range instead of trusting the view-supplied caret.
    private var completionDraftSnapshot: String?
    private var programmaticSelectionOffsetToIgnore: Int?
    private var priorityRollSeed: String?
    private var focusSequence: UInt64 = 0

    // Shared by submit and preview so a late callback from either one can never mutate
    // state on behalf of a request that is no longer the active one.
    private var activeRequestID: UUID?
    private var activeTaskIDRequestID: UUID?
    private var activePomodoroNameRequestID: UUID?
    /// Local fuzzy index for the picker's snapshot. Kept private; the view only
    /// sees the derived `pickerPresentation`.
    private var pickerIndex: CapturePickerIndex?
    /// Replacement-range start of the `^` token auto-open is suppressed for
    /// (set by the two-stage Escape cancel). Cleared when an `.edit` analysis
    /// leaves the token.
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

    /// Measured footer height, reported by the panel view. The
    /// controller derives the compact panel's top from it.
    @Published var footerHeight: CGFloat = 0

    /// Fires when a new plan publishes, so the controller can settle
    /// the layout while the panel is hidden.
    var agendaPlanDidChange: (() -> Void)?

    private let agendaMeasurer = CaptureAgendaRowMeasurer()
    private var agendaSnapshotCancellable: AnyCancellable?

    /// Whether the agenda paints: the setting is on, the draft is
    /// blank, nothing else owns the auxiliary region, no live preview
    /// is showing, and a plan is ready.
    var agendaVisible: Bool {
        CaptureAgendaVisibility.isVisible(
            settingOn: agendaEnabled,
            draftBlank: !hasDraft,
            regionFree: !auxiliaryOwnedByOther,
            previewIdle: previewState == .idle,
            hasPlan: agendaPlan != nil
        )
    }

    private var auxiliaryOwnedByOther: Bool {
        isStashPickerPresented || inlinePromptVisible || pickerVisible
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

    /// Measures what is missing, plans, and publishes. Runs on snapshot
    /// publish, width change, screen change (via the budget), and
    /// expansion. Planning iterates to a fixpoint: a freshly folded
    /// plan can surface new row variants (chips, strips) that need
    /// measuring before the final plan.
    func refreshAgendaPlan(today: String = CaptureAgendaStore.localToday()) {
        guard agendaEnabled, let snapshot = agendaStore?.snapshot else {
            agendaPresentation = nil
            agendaPlan = nil
            return
        }
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: Date()
        )
        agendaPresentation = presentation
        let plan = CaptureAgendaHeightResolver.resolve(
            presentation: presentation,
            budget: agendaBudget,
            expanded: agendaExpanded,
            width: max(1, agendaContentWidth),
            measurer: agendaMeasurer
        )
        let changed = agendaPlan != plan
        agendaPlan = plan
        if changed {
            agendaPlanDidChange?()
        }
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
        canceledDraftStash: CanceledDraftStash? = nil
    ) {
        self.processClient = processClient
        self.debounceNanoseconds = debounceNanoseconds
        let canceledDraftStash = canceledDraftStash ?? CanceledDraftStash()
        self.canceledDraftStash = canceledDraftStash
        stashCancellable = canceledDraftStash.$entries.sink { [weak self] entries in
            guard let self else {
                return
            }
            self.objectWillChange.send()
            self.clampStashSelection(afterEntriesChange: entries)
        }
    }

    deinit {
        analysisTask?.cancel()
        rewriteTask?.cancel()
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
            && !inlinePromptVisible
            && completionResponse?.candidates.isEmpty == false
    }

    var inlinePromptVisible: Bool {
        taskIDPrompt != nil || pomodoroNamePrompt != nil
    }

    var pickerVisible: Bool {
        picker != nil
    }

    /// False while any modal, prompt, or completion list is visible.
    var pickerChipVisible: Bool {
        pickerChip != nil
            && !isStashPickerPresented
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
        return false
    }

    /// True when Tab / Shift-Tab cycle ID suggestions (link, dependency,
    /// Complete, and parent-task card). The old inline `.parentTask` path
    /// keeps Tab consumed.
    var taskIDPromptCyclesSuggestions: Bool {
        taskIDPromptIsTaskLink || taskIDPromptIsDependency || taskIDPromptIsTaskComplete || taskIDPromptIsParentTaskPicker
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

    /// True when the open picker belongs to the `&` source.
    var pickerSourceIsDependency: Bool {
        picker?.source == .dependency
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

    var stashEntries: [CanceledDraftEntry] {
        canceledDraftStash.entries
    }

    var stashCount: Int {
        canceledDraftStash.count
    }

    var selectedStashEntry: CanceledDraftEntry? {
        canceledDraftStash.entry(at: selectedStashIndex)
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
        plainDraft.contains("%")
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
    /// or new-task note-free `=x0` reset. Bob's additive summary is the sole
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

    /// The footer's primary action verb. Single close, start, toggle, link,
    /// adjust, and shift previews name their action so Return's meaning is
    /// clear. A `==` override start names its own verb (`Restart` / `Swap`)
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
        return "Capture"
    }

    /// Follows the agenda store's count publisher. The store nils the
    /// count on failure, a non-today snapshot, and client replacement,
    /// so the model only forwards it.
    private func subscribeToAgendaStore() {
        agendaCancellable = nil
        agendaSnapshotCancellable = nil
        guard let agendaStore else {
            return
        }
        agendaCancellable = agendaStore.$currentTaskLinkCount.sink { [weak self] count in
            guard let self else {
                return
            }
            self.currentPomodoroTaskLinkCount = count
        }
        // A new snapshot resets expansions and re-plans. The store
        // only publishes on change, so byte-identical output stays a
        // no-op here too.
        agendaSnapshotCancellable = agendaStore.$snapshot.sink { [weak self] _ in
            guard let self else {
                return
            }
            self.agendaExpanded = []
            self.agendaMeasurer.noteSnapshotChange()
            self.refreshAgendaPlan()
        }
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
        }
        if processClient == nil {
            if changed {
                statusText = "Bob is not resolved"
                previewState = .idle
                previewResult = nil
                previewResults = []
                previewGlobalDestination = nil
                completionResponse = nil
                completionDraftSnapshot = nil
                clearPickerState()
                invalidateAnalysis()
                invalidateRewrite()
            }
        } else {
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

    func updateTargetCacheSnapshot(_ snapshot: CaptureTargetsSnapshot) {
        targetCacheSnapshot = snapshot
        if let error = snapshot.errorDescription {
            statusText = snapshot.stale ? "Target cache stale" : error
        }
    }

    func editorTextDidChange(cursorUTF8Offset: Int? = nil) {
        guard !isApplyingProgrammaticDraft else {
            return
        }

        let draft = plainDraft
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
            parseDiagnostics = []
            completionResponse = nil
            completionDraftSnapshot = nil
            clearInlinePrompts()
            previewState = .idle
            statusText = ""
            invalidateAnalysis()
            invalidateRewrite()
            return
        }

        if commitRouteCompletionOnPlus(draft: draft) {
            return
        }

        let insertionOffset = cursorUTF8Offset ?? collapsedSelectionUTF8Offset()
        if let insertionOffset,
           Self.isBareAtAtTrigger(in: draft, cursorUTF8Offset: insertionOffset)
        {
            startCaptureRewrite(draft: draft, cursorUTF8Offset: insertionOffset)
        }
        if closeListAssistParsePending {
            closeListAssistParsePending = false
            if closeTaskCommaArmed {
                startCloseListAssistParse(draft: draft)
            }
        }
        scheduleAnalysis(
            cursorUTF8Offset: insertionOffset,
            requestCompletion: insertionOffset != nil,
            trigger: .edit
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
        guard !isApplyingProgrammaticDraft, hasDraft else {
            return
        }

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
        let requestID = UUID()
        activeRequestID = requestID
        isSubmitting = true
        errorMessage = nil
        errorCode = nil
        statusText = openAfterCapture ? "Capturing and opening\u{2026}" : "Capturing\u{2026}"
        let seed = activePriorityRollSeed()

        Task {
            do {
                let response = try await CaptureSignpost.measure("submit") {
                    try await processClient.capture(
                        draft,
                        dryRun: false,
                        readClipboard: true,
                        priorityRollSeed: seed
                    )
                }
                await MainActor.run {
                    self.completeSubmit(requestID: requestID, response: response, openAfterCapture: openAfterCapture)
                }
            } catch {
                await MainActor.run {
                    self.failSubmit(requestID: requestID, error: error)
                }
            }
        }
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
        activeRequestID = requestID
        isPreviewing = true
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
                        priorityRollSeed: activePriorityRollSeed()
                    )
                }
                await MainActor.run {
                    self.completePreview(requestID: requestID, response: response)
                }
            } catch {
                await MainActor.run {
                    self.failPreview(requestID: requestID, error: error)
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
        dismissStashPicker()
        clearInlinePrompts()
        agendaExpanded = []
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
        clearInlinePrompts()
        setPlainDraft("")
        suppressedCompletionAcceptanceDraft = nil
        priorityRollSeed = nil
        resetAnalysisState()
    }

    func stashDraftAndClose() {
        if hasDraft {
            let draft = plainDraft
            let stashed = canceledDraftStash.push(draft) != nil
            discardDraft()
            announceStatus(stashed ? "Canceled draft stashed" : "Canceled draft discarded")
        } else {
            discardDraft()
        }
        panelDismisser()
    }

    func toggleStashPicker() {
        if picker != nil {
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

    // Called before the panel is (re)shown. A retained draft (from Escape or a failed
    // capture) must reopen exactly as the user left it, error and all; only a panel with
    // no draft — i.e. one that just dismissed after a success — needs its leftover
    // success summary and status cleared so the next capture starts clean. A retained
    // non-empty draft still re-runs analysis: a close preview's `closed_at` and timing
    // go stale while the panel is hidden, so the card must resolve them fresh.
    func prepareForPresentation() {
        dismissStashPicker()
        guard !hasDraft else {
            editorTextDidChange()
            return
        }
        resetAnalysisState()
        lastSuccess = nil
        lastSuccessResults = []
        lastSuccessGlobalDestination = nil
        selectedCompletionIndex = 0
    }

    func prepareForDismissal() {
        dismissStashPicker()
        closePickerForDismissal()
        clearInlinePrompts()
        agendaExpanded = []
    }

    func requestFocus(_ target: CapturePanelFocusTarget) {
        focusSequence &+= 1
        focusRequest = CapturePanelFocusRequest(sequence: focusSequence, target: target)
    }

    private func resetAnalysisState() {
        invalidateAnalysis()
        invalidateRewrite()
        parseDiagnostics = []
        completionResponse = nil
        completionDraftSnapshot = nil
        closeListParseSnapshot = nil
        closeListAssistParsePending = false
        closeCommaProvenance.clear()
        lastProvenanceDraft = plainDraft
        clearPickerState()
        clearInlinePrompts()
        previewState = .idle
        statusText = ""
        errorMessage = nil
        errorCode = nil
        previewResult = nil
        previewResults = []
        previewGlobalDestination = nil
    }

    private func clearInlinePrompts() {
        clearTaskIDPrompt()
        clearPomodoroNamePrompt()
    }

    private func clearTaskIDPrompt() {
        taskIDPrompt = nil
        activeTaskIDRequestID = nil
        clearEditorInputLockIfFree()
    }

    private func clearPomodoroNamePrompt() {
        pomodoroNamePrompt = nil
        activePomodoroNameRequestID = nil
        clearEditorInputLockIfFree()
    }

    private func clearEditorInputLock() {
        if editorInputLocked {
            editorInputLocked = false
        }
    }

    /// The editor stays locked while the picker or either prompt is open.
    private func clearEditorInputLockIfFree() {
        if taskIDPrompt == nil, pomodoroNamePrompt == nil, picker == nil {
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
        completionResponse = nil
        completionDraftSnapshot = nil
        selectedCompletionIndex = 0
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
    }

    /// Routes one completion result: `active_task`, `task_link`,
    /// `task_dependency`, and block-ID responses feed the picker or the
    /// reopen chip and never populate the inline list; every other context
    /// keeps the inline list and clears the chip.
    private func handleCompletionResponse(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        trigger: CompletionTrigger,
        generation: UInt64,
        processClient: BobProcessClient
    ) async {
        guard isCurrentAnalysis(generation) else {
            return
        }
        // While the picker is open, analysis results never modify picker or
        // chip state and never populate the inline list. A selection callback
        // fired when the editor loses focus must not reset the picker.
        if picker != nil {
            dismissCompletion()
            return
        }
        if completion.context == "task_link" {
            await handleTaskLinkCompletion(
                completion,
                draft: draft,
                cursor: cursor,
                generation: generation,
                processClient: processClient,
                trigger: trigger
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
        if completion.context == "task_dependency" {
            await handleDependencyCompletion(
                completion,
                draft: draft,
                cursor: cursor,
                generation: generation,
                processClient: processClient,
                trigger: trigger
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
                    trigger: trigger
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
            trigger: trigger
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
    /// New ID rules below with the project-task scope. Link intent mirrors
    /// `^`: an
    /// exact part opens nothing, an `.edit` opens the picker (refetching the
    /// full snapshot at the range start when the caret is past it), and a
    /// caret-only move or suppression shows the chip. New ID intent opens
    /// only when the part is empty or the caret is at the part's end (typing
    /// forward); any other edit shows the chip.
    private func handleBlockIDCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger
    ) async {
        // Block-ID responses never populate the inline list, even when empty.
        dismissCompletion()
        guard Self.isUsableBlockIDCompletion(completion) else {
            clearPickerInterruption(trigger: trigger)
            return
        }
        let r = completion.replacement
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
        // A `pomodoro_start_name` list that opened on the quiet incomplete
        // picker (`==#`, `==3#`, `=#`) still shows that calm status line:
        // refresh it from Bob's override object once completion arrives, so
        // a `==` pick names the running session it displaces. Any other
        // status (a live preview, a prompt) is left alone.
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

    private func handleActiveTaskCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger
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
        guard trigger == .edit, pickerAutoOpenSuppressedStart != r.start else {
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

    /// Routes a `task_link` completion response into the picker card, mirroring
    /// `handleActiveTaskCompletion`: dismiss the inline list, auto-open only on
    /// `.edit` when not suppressed, show the chip on `.selection`, and refetch
    /// the full list at `r.start` when the caret is past it.
    private func handleTaskLinkCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger
    ) async {
        // A `task_link` response never sets `completionResponse`, even when
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
                source: .taskLink,
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
               snapshot.context == "task_link",
               snapshot.replacement == r
            {
                presentPicker(
                    source: .taskLink,
                    index: .taskLink(TaskLinkPickerIndex(candidates: snapshot.candidates)),
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
                source: .taskLink,
                index: .taskLink(TaskLinkPickerIndex(candidates: completion.candidates)),
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
            source: .taskLink,
            index: .taskLink(TaskLinkPickerIndex(candidates: completion.candidates)),
            candidates: completion.candidates,
            warnings: completion.warnings,
            draft: draft,
            range: r,
            restoreCursor: cursor,
            query: query,
            snapshotIsPartial: false
        )
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
    /// dependent exists: the owner rides along for the header and the
    /// Command-Return gate, never to block the pick itself.
    private func handleDependencyCompletion(
        _ completion: CaptureCompletionResponse,
        draft: String,
        cursor: Int,
        generation: UInt64,
        processClient: BobProcessClient,
        trigger: CompletionTrigger
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
        guard trigger == .edit, pickerAutoOpenSuppressedStart != r.start else {
            var chip = CapturePickerChipState(
                source: .dependency,
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
        let query = Self.dependencyPickerQuery(in: draft, range: r, cursor: cursor)
        if cursor > r.start + 1 {
            if let snapshot = try? await processClient.captureComplete(draft, cursor: r.start),
               isCurrentAnalysis(generation),
               plainDraft == draft,
               snapshot.context == "task_dependency",
               snapshot.replacement == r
            {
                presentPicker(
                    source: .dependency,
                    index: .dependency(DependencyPickerIndex(candidates: snapshot.candidates)),
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
                source: .dependency,
                index: .dependency(DependencyPickerIndex(candidates: completion.candidates)),
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
            source: .dependency,
            index: .dependency(DependencyPickerIndex(candidates: completion.candidates)),
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

    /// The `&` filter seed: draft bytes `(r.start + 1)..<caret`, so the sigil
    /// itself never filters. The index also strips a leading `&`
    /// defensively. Quoted locators stay raw here; Bob's decoded `query`
    /// remains authoritative for anything but the seed.
    private static func dependencyPickerQuery(in draft: String, range: CaptureRange, cursor: Int) -> String {
        let start = range.start + 1
        guard start <= range.end,
              let queryRange = stringRange(in: draft, start: start, end: min(cursor, range.end))
        else {
            return ""
        }
        return String(draft[queryRange])
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
        requestFocus(.pickerFilter)
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
        case .dependency:
            // Bob's `task_dependency` replacement already includes the `&`
            // sigil, quoted note included.
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
        guard let selectedRowID = picker?.selectedRowID else {
            // An empty-list accept is a no-op.
            return
        }
        acceptPickerRow(id: selectedRowID, submitAfterInsert: submitAfterInsert)
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
                followUp: submitAfterInsert ? .submit : .none
            )
            return
        }
        if case .parentTask = picker.source, row.insertion == nil, let pending = row.pendingBlockID {
            presentParentTaskIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: submitAfterInsert ? .submit : .none
            )
            return
        }
        if picker.source == .dependency, row.insertion == nil, let pending = row.pendingBlockID {
            presentDependencyIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: submitAfterInsert ? .submit : .none
            )
            return
        }
        if picker.source == .taskComplete, row.insertion == nil, let pending = row.pendingBlockID {
            presentTaskCompleteIDPrompt(
                pending: pending,
                pickerSnapshot: picker,
                followUp: submitAfterInsert ? .submit : .none
            )
            return
        }
        guard let insertion = row.insertion else {
            if case .blockID = picker.source {
                announceStatus(
                    Self.blockIDNoAcceptReason(filter: picker.filterText, presentation: pickerPresentation)
                )
            } else if picker.source == .dependency || picker.source == .taskComplete {
                // Already-added and guarded rows keep the draft unchanged and
                // say why, leaving the picker open.
                announceStatus(row.badgeText ?? "That task cannot be used yet")
            }
            return
        }

        // At a terminal `&` token, leave one separating space for typing
        // another `&`; preserve existing suffix whitespace when editing a
        // token in place.
        let insertionText: String
        if picker.source == .dependency,
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
        closePickerForAccept()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: false, trigger: .edit)
        // Block-ID insertions are bare IDs; name the marker they landed on.
        // Active-task insertions are bare locators; prefix the `^` so the
        // announcement matches the pre-epic "Inserted ^route:block-id".
        // Task-link and dependency insertions already include `@` and `&`.
        if case .blockID(let context) = source {
            if context.scope == .projectTask {
                announceStatus("Inserted \(context.marker)\(insertionText)")
            } else {
                announceStatus("Inserted @\(context.route)\(context.marker)\(insertionText)")
            }
        } else if source == .taskLink || source == .dependency || source == .taskComplete {
            announceStatus("Inserted \(insertionText)")
        } else if case .parentTask = source {
            announceStatus("Inserted \(insertionText)")
        } else {
            announceStatus("Inserted \(row.detail.insertionPrefix)\(insertionText)")
        }
        if submitAfterInsert {
            if source == .dependency, owner == nil {
                // No dependent yet: keep the draft open and teach the next
                // step instead of submitting an ownerless pick.
                announceStatus("Add task text or @note+id, then capture")
                return
            }
            submit(openAfterCapture: false)
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

    /// Backspace on an empty filter removes the source's trigger byte together
    /// with any fragment it opened on (`^` for active tasks, `:` for task
    /// links and `&` for dependencies, whose replacements already include the
    /// sigil). Parent-task uses Bob's `trigger_removal_range` and never hunts
    /// for the marker. Otherwise behaves like cancel.
    func removePickerTrigger() {
        guard let picker = picker, picker.filterText.isEmpty else {
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
        if picker.source == .taskLink || picker.source == .dependency || picker.source == .taskComplete {
            let sigil: UInt8
            if picker.source == .taskLink {
                sigil = 58 // `:`
            } else if picker.source == .dependency {
                sigil = 38 // `&`
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
        } else if chip.source == .taskLink {
            query = Self.taskLinkPickerQuery(in: draft, range: r, cursor: chip.cursor)
        } else if chip.source == .dependency {
            query = Self.dependencyPickerQuery(in: draft, range: r, cursor: chip.cursor)
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
        if chip.source == .taskLink || chip.source == .dependency || chip.source == .taskComplete {
            needsRefetch = chip.cursor > r.start + 1
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
                    case .dependency:
                        guard snapshot.context == "task_dependency" else {
                            return
                        }
                        self.presentPicker(
                            source: chip.source,
                            index: .dependency(DependencyPickerIndex(candidates: snapshot.candidates)),
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
        case .dependency:
            presentPicker(
                source: chip.source,
                index: .dependency(DependencyPickerIndex(candidates: chip.candidates)),
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
    /// Precedence is `active_task`, then `task_link`, then `task_parent`,
    /// then `task_dependency`, then `pomodoro_id`, then `block_id`, then the
    /// `=<X>#` named-start incomplete, checked top-level or in any item.
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
        if needs("task_parent") {
            return .taskParent
        }
        if needs("task_dependency") {
            return .dependency
        }
        if needs("task_complete") {
            return .taskComplete
        }
        if needs("pomodoro_id") {
            return .pomodoroID
        }
        if needs("block_id") {
            return .blockID
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

    private func applyQuietIncompletePicker(_ need: CapturePickerNeed) {
        previewState = .idle
        previewResult = nil
        previewResults = []
        previewGlobalDestination = nil
        closePendingText = nil
        closePendingAction = "Close"
        errorMessage = nil
        errorCode = nil
        statusText = need.statusText
    }

    /// The pending close/start-list trim for a draft that dangles on a list
    /// separator or a Work Log entry: for every item whose `needs` contains
    /// `pomodoro_close_task` (`,`/`!`/`~`/`*`), `pomodoro_start_task` (`~`/`,`),
    /// or `pomodoro_close_log_text` (a `- <n>` bullet or an inline `=x 2`
    /// number with no entry text yet), the one `interactive_placeholder`
    /// span Bob reported inside that item's range is removed, so the live
    /// preview runs on the trimmed draft — exactly what has been typed so
    /// far. For a dangling bullet the removal leaves a `- ` placeholder row
    /// (or `-` after the trailing-space strip), which bob treats as a
    /// harmless placeholder, so the card previews the rest. For a dangling
    /// inline number the removal leaves `=x` (or `=x =` from `=x 2 =`),
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
        // A dangling bullet leaves a trailing space (`=x\n- 1` trims to
        // `=x\n- `): strip it so the preview runs on the placeholder row
        // (`=x\n-`, still a harmless placeholder).
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

    func acceptSelectedCompletion() {
        guard let completionResponse,
              let candidate = selectedCompletion,
              let range = stringRange(in: plainDraft, byteRange: completionResponse.replacement)
        else {
            statusText = "Completion range is stale"
            dismissCompletion()
            return
        }

        if completionResponse.context == "task", candidate.requiresBlockID {
            presentTaskIDPrompt(
                candidate: candidate,
                draftSnapshot: plainDraft,
                replacementRange: completionResponse.replacement
            )
            return
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
                return
            }
            let name = candidate.name.flatMap { $0.isEmpty ? nil : $0 } ?? candidate.replacement
            if candidate.state == "completed" {
                announceStatus("Starts a new \(name) session when captured")
            } else {
                announceStatus("\(name) will be created and started when captured")
            }
            requestFocus(.editor)
            return
        }

        if completionResponse.context == "pomodoro_name", candidate.createsPomodoro {
            guard applySelectedCompletionReplacement(
                candidate: candidate,
                range: range,
                completionResponse: completionResponse
            ) else {
                return
            }
            let name = candidate.name.flatMap { $0.isEmpty ? nil : $0 } ?? candidate.replacement
            announceStatus("\(name) will be created when captured")
            requestFocus(.editor)
            return
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
            return
        }

        _ = applySelectedCompletionReplacement(
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

        dismissCompletion()
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
        case .taskComplete(_, _, _, _, let pickerSnapshot):
            returnPicker = pickerSnapshot
        case .parentTaskPicker(_, _, _, _, let pickerSnapshot, _):
            returnPicker = pickerSnapshot
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
            case .taskLink:
                index = .taskLink(TaskLinkPickerIndex(candidates: returnPicker.candidates))
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
            if case .parentTask = returnPicker.source {
                statusText = CapturePickerNeed.taskParent.statusText
            } else if returnPicker.source == .dependency {
                statusText = CapturePickerNeed.dependency.statusText
            } else if returnPicker.source == .taskComplete {
                statusText = CapturePickerNeed.taskComplete.statusText
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
        } else if case .taskComplete(let notePath, let completeRef, _, _, _) = prompt.purpose {
            route = notePath
            taskRef = completeRef
            dependencyNotePath = notePath
            dependencyAllowClosed = false
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
        // exact `note_path` (extension included) for `&` flows.
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
            override: completionResponse?.overrideInfo
        )
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
        case .taskComplete(_, _, let completeSuggestions, _, _):
            suggestions = completeSuggestions
        case .parentTaskPicker(_, _, let parentSuggestions, _, _, _):
            suggestions = parentSuggestions
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
            isSaving: false,
            errorMessage: nil
        )
        statusText = "Name Pomodoro"
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
                if followUp == .submit {
                    submit(openAfterCapture: false)
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
                if followUp == .submit {
                    submit(openAfterCapture: false)
                }
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
                if followUp == .submit {
                    submit(openAfterCapture: false)
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
        if followUp == .submit {
            submit(openAfterCapture: false)
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
        openAfterCapture: Bool
    ) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        isSubmitting = false

        switch response {
        case .success(let success):
            let captures = success.normalizedCaptures
            invalidateAnalysis()
            lastSuccess = captures.first
            lastSuccessResults = captures
            lastSuccessGlobalDestination = success.globalDestination
            previewResult = nil
            previewResults = []
            previewGlobalDestination = nil
            errorMessage = nil
            errorCode = nil
            setPlainDraft("")
            suppressedCompletionAcceptanceDraft = nil
            priorityRollSeed = nil
            parseDiagnostics = []
            completionResponse = nil
            completionDraftSnapshot = nil
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
            successAnnouncementTick += 1
            notificationService?.notifyCaptureSuccess(
                captures: captures,
                globalDestination: success.globalDestination
            )
            if openAfterCapture {
                for url in uniqueTargetURLs(from: captures) {
                    targetOpener(url)
                }
            }
            panelDismisser()
        case .failure(let failure):
            errorMessage = failure.error
            errorCode = failure.code
            statusText = "Capture failed"
            notificationService?.notifyCaptureFailure(message: failure.error)
        }
    }

    private func failSubmit(requestID: UUID, error: Error) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        isSubmitting = false

        let message = String(describing: error)
        errorMessage = message
        errorCode = nil
        statusText = "Capture failed"
        notificationService?.notifyCaptureFailure(message: message)
    }

    private func completePreview(requestID: UUID, response: CaptureCommandResponse) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        isPreviewing = false

        switch response {
        case .success(let success):
            let captures = success.normalizedCaptures
            previewResult = captures.first
            previewResults = captures
            previewGlobalDestination = success.globalDestination
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
            previewResult = nil
            previewResults = []
            previewGlobalDestination = nil
            errorMessage = failure.error
            errorCode = failure.code
            statusText = "Preview failed"
        }
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

    private func failPreview(requestID: UUID, error: Error) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        isPreviewing = false
        // A failed live dry run must never leave a stale card beside the red
        // error: a close preview's `closed_at` and timing describe a moment
        // that has already passed, so drop the whole preview result.
        previewResult = nil
        previewResults = []
        previewGlobalDestination = nil
        errorMessage = String(describing: error)
        errorCode = nil
        statusText = "Preview failed"
    }

    private func setPlainDraft(
        _ text: String,
        cursorUTF8Offset: Int? = nil,
        suppressSelectionCallbacks: Bool = false
    ) {
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

    private func scheduleAnalysis(
        cursorUTF8Offset: Int?,
        requestCompletion: Bool,
        trigger: CompletionTrigger
    ) {
        guard let processClient else {
            statusText = "Bob is not resolved"
            return
        }

        let draft = plainDraft
        if let cursorUTF8Offset {
            guard cursorUTF8Offset >= 0,
                  cursorUTF8Offset <= draft.utf8.count,
                  stringRange(in: draft, start: cursorUTF8Offset, end: cursorUTF8Offset) != nil
            else {
                statusText = "Cursor is not on a UTF-8 boundary"
                return
            }
        }

        analysisGeneration &+= 1
        let generation = analysisGeneration
        let debounceNanoseconds = self.debounceNanoseconds
        analysisTask?.cancel()
        previewState = .loading
        // A changed draft can still have the prior response in these caches while
        // the debounce is running. Clear it before calculating the next preview so
        // the footer and preview card always describe the same draft.
        previewResult = nil
        previewResults = []
        previewGlobalDestination = nil
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
                    self?.applyParse(parse, draft: draft)
                    if let need = pickerNeeded {
                        // An incomplete `^` is a state, not an error: skip the
                        // doomed live dry run and stay calm instead of flashing
                        // red "incomplete Pomodoro link" errors while picking.
                        self?.applyQuietIncompletePicker(need)
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
                        processClient: processClient
                    )
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
                            generation: generation,
                            processClient: processClient
                        )
                    } catch {
                        await MainActor.run {
                            guard self?.isCurrentAnalysis(generation) == true else {
                                return
                            }
                            self?.statusText = String(describing: error)
                        }
                    }
                } else {
                    await MainActor.run {
                        guard self?.isCurrentAnalysis(generation) == true else {
                            return
                        }
                        self?.handleMissingCompletion(trigger: trigger)
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

    private func startCaptureRewrite(draft: String, cursorUTF8Offset: Int) {
        guard let processClient else {
            return
        }

        rewriteTask?.cancel()
        rewriteTask = Task { [weak self, processClient] in
            do {
                let response = try await CaptureSignpost.measure("rewrite") {
                    try await processClient.captureRewrite(draft, cursor: cursorUTF8Offset)
                }
                try Task.checkCancellation()

                await MainActor.run {
                    self?.applyCaptureRewrite(response, draft: draft)
                }
            } catch is CancellationError {
            } catch {
                // Rewriting is a typing assist. Parse, completion, and preview still run
                // on the original draft, so transport failures should not disturb the UI.
            }
        }
    }

    private func applyCaptureRewrite(
        _ response: CaptureRewriteResponse,
        draft: String
    ) {
        guard plainDraft == draft else {
            return
        }

        if response.changed {
            if let cursor = response.cursor,
               stringRange(in: response.text, start: cursor, end: cursor) == nil
            {
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

    private func startLivePreview(
        draft: String,
        previewDraft: String,
        pendingSeparator: String?,
        pendingAction: String?,
        generation: UInt64,
        processClient: BobProcessClient
    ) {
        Task { [weak self, processClient] in
            do {
                let seed = await self?.activePriorityRollSeed() ?? UUID().uuidString
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
                        self?.previewState = .ready(success)
                        self?.previewResult = captures.first
                        self?.previewResults = captures
                        self?.previewGlobalDestination = success.globalDestination
                        self?.errorMessage = nil
                        self?.errorCode = nil
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
                    case .failure(let failure):
                        self?.previewState = .failed(failure.error)
                        // Like `failPreview`: a failed live dry run must never
                        // leave a stale card beside the red error.
                        self?.previewResult = nil
                        self?.previewResults = []
                        self?.previewGlobalDestination = nil
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

    private func invalidateAnalysis() {
        analysisGeneration &+= 1
        analysisTask?.cancel()
        analysisTask = nil
    }

    private func invalidateRewrite() {
        rewriteTask?.cancel()
        rewriteTask = nil
    }

    private func activePriorityRollSeed() -> String {
        if let priorityRollSeed {
            return priorityRollSeed
        }

        let seed = UUID().uuidString
        priorityRollSeed = seed
        return seed
    }

    private func applyParse(_ parse: CaptureParseResponse, draft: String) {
        parseDiagnostics = parse.diagnostics
        if plainDraft == draft {
            closeListParseSnapshot = CaptureParseSnapshot(
                draft: draft,
                spans: parse.spans
            )
        }
        applyHighlighting(parse: parse, draft: draft)

        if let diagnostic = parse.diagnostics.first(where: { $0.severity != "info" }) {
            statusText = diagnostic.message
        } else if statusText == "Ready" || statusText.isEmpty || statusText == "Target cache stale" {
            statusText = "Ready"
        }
    }

    private func applyHighlighting(parse: CaptureParseResponse, draft: String) {
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
            text.foregroundColor = nil
            text.underlineStyle = nil
            for item in ranges {
                guard let lower = AttributedString.Index(item.range.lowerBound, within: text),
                      let upper = AttributedString.Index(item.range.upperBound, within: text)
                else {
                    ignoredMalformedSpan = true
                    return
                }

                let category = captureSemanticCategory(forSpanKind: item.span.kind)
                text[lower..<upper].foregroundColor = CaptureEditorPalette.color(for: category)
                if category.isUnderlined {
                    text[lower..<upper].underlineStyle = .single
                }
            }
        }
        isApplyingProgrammaticDraft = false
        if ignoredMalformedSpan {
            statusText = "Ignored malformed parse spans"
        }
        // A parse that lands while the picker is open repaints spans; restore
        // the marker wash it may have covered.
        applyPickerMarkerHighlight()
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
            "active_task", "task_link", "task_parent", "task_dependency", "dependency_target",
            "task_complete", "block_id",
        ])
        if !completionNeeds.isDisjoint(with: Set(parse.needs)) {
            return true
        }

        // The additive `pomodoro_start` (`=<X>`) and `pomodoro_close` (`=x`)
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
                    status: target.status
                )
            }
        )
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

    private func rankedTargets(_ targets: [CaptureTarget], query: String) -> [CaptureTarget] {
        guard !query.isEmpty else {
            return targets
        }

        let prefix = targets.filter { target in
            target.route.lowercased().hasPrefix(query)
                || target.label.lowercased().hasPrefix(query)
                || target.name.lowercased().hasPrefix(query)
        }
        let contains = targets.filter { target in
            !prefix.contains(target)
                && (
                    target.route.lowercased().contains(query)
                        || target.label.lowercased().contains(query)
                        || target.name.lowercased().contains(query)
                )
        }
        return prefix + contains
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

    // A toggle's or link's route note and Bob's daily note may be the same file, or
    // the daily note may be untouched (nothing was linked, moved, or started) — both
    // are handled by `seen` deduplication plus gating the day file on
    // `dayFileChanged`, so Command-Return never opens a note the capture didn't
    // actually write to.
    private func uniqueTargetURLs(from captures: [CaptureCommandSuccess]) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        func appendURL(forAbsolutePath path: String) {
            guard seen.insert(path).inserted,
                  let url = ObsidianOpenURL.url(forAbsolutePath: path)
            else {
                return
            }
            urls.append(url)
        }
        for capture in captures {
            appendURL(forAbsolutePath: capture.target)
            if let dayFile = capture.dayFile, Self.captureWroteDayFile(capture) {
                appendURL(forAbsolutePath: dayFile)
            }
        }
        return urls
    }

    private static func captureWroteDayFile(_ capture: CaptureCommandSuccess) -> Bool {
        if CapturePomodoroResetPresentation(capture: capture) != nil {
            return true
        }
        if CapturePomodoroClosePresentation(capture: capture) != nil {
            return true
        }
        if CapturePomodoroStartPresentation.isSessionStart(capture) {
            return true
        }
        if let toggle = CaptureTogglePresentation(capture: capture) {
            return toggle.dayFileChanged
        }
        if CaptureTaskCompletePresentation(capture: capture) != nil {
            // Bob sets the top-level `day_file` whenever the gesture
            // changed the day file, and a linked successor always changes
            // it — even when the predecessor had no ledger entry of its own.
            guard let complete = capture.taskComplete else { return false }
            return complete.ledger != nil || complete.unblocked.contains { $0.link != nil }
        }
        if let link = CapturePomodoroLinkPresentation(capture: capture) {
            return link.dayFileChanged
        }
        if let note = capture.projectNote, !note.taskLinks.isEmpty {
            return true
        }
        return false
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
