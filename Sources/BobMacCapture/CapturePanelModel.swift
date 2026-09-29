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

struct CaptureTaskIDPromptState: Equatable {
    let candidate: CaptureCompletionCandidate
    let draftSnapshot: String
    let replacementRange: CaptureRange
    let selectedCompletionIndex: Int
    var authoredID: String
    var isSaving: Bool
    var errorMessage: String?
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
    @Published var errorMessage: String?
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

    /// The live preview's close presentation for a single plain, linked-task, or
    /// new-task close. Bob's additive summary is the sole source of close effects.
    var closePresentation: CapturePomodoroClosePresentation? {
        guard previewResults.count == 1, let previewResult else {
            return nil
        }
        return CapturePomodoroClosePresentation(capture: previewResult)
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
    /// clear. It never varies with `dryRun` — it always names what Return will
    /// do next.
    var primaryActionTitle: String {
        closePresentation.map { _ in "Close" }
            ?? sessionStartPresentation.map { _ in "Start" }
            ?? togglePresentation?.primaryActionTitle
            ?? linkPresentation?.primaryActionTitle
            ?? shiftPresentation.map { _ in "Shift" }
            ?? adjustPresentation.map { _ in "Adjust" } ?? "Capture"
    }

    func setProcessClient(_ processClient: BobProcessClient?) {
        self.processClient = processClient
        if processClient == nil {
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
        } else if hasDraft {
            editorTextDidChange()
        }
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
        scheduleAnalysis(
            cursorUTF8Offset: insertionOffset,
            requestCompletion: insertionOffset != nil,
            trigger: .edit
        )
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

    func submit(openAfterCapture: Bool) {
        guard !inlinePromptVisible, !isSubmitting, !isPreviewing, hasDraft else {
            return
        }
        guard let processClient else {
            errorMessage = "Bob is not resolved. Check Settings and Recheck Bob."
            return
        }

        let draft = plainDraft
        let requestID = UUID()
        activeRequestID = requestID
        isSubmitting = true
        errorMessage = nil
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
            return
        }

        let draft = plainDraft
        let requestID = UUID()
        activeRequestID = requestID
        isPreviewing = true
        errorMessage = nil
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
        clearPickerState()
        clearInlinePrompts()
        previewState = .idle
        statusText = ""
        errorMessage = nil
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
        let presentation = index.presentation(filter: filter)
        pickerIndex = index
        pickerPresentation = presentation
        picker = CapturePickerState(
            source: .activeTask,
            draftSnapshot: "^",
            replacementRange: CaptureRange(start: 0, end: 1),
            restoreCursor: 1,
            candidates: candidates,
            warnings: warnings,
            filterText: filter,
            selectedRowID: CapturePickerNavigation.first(in: presentation.orderedRowIDs),
            visibleRowBudget: presentation.visibleRowBudget,
            snapshotIsPartial: false
        )
    }

    /// Routes one completion result: `active_task` and block-ID responses
    /// feed the picker or the reopen chip and never populate the inline
    /// list; every other context keeps the inline list and clears the chip.
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
        guard completion.context == "active_task" else {
            if completion.context == "pomodoro_block_id" || completion.context == "task_block_id" {
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
    /// picker without New ID rows) or `task_block_id` with a `block_id`
    /// object. A `task_block_id` response without one is treated as no
    /// completion: older Bob never sends `task_block_id` at all, so there is
    /// no picker and no inline list.
    private static func isUsableBlockIDCompletion(_ completion: CaptureCompletionResponse) -> Bool {
        completion.context == "pomodoro_block_id" || completion.blockID != nil
    }

    /// Builds the picker source for a usable block-ID response: the decoded
    /// field (nil for older Bob), the route, the marker, the intent (older
    /// Bob means Link), and Bob's ID rules.
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
        return .blockID(
            BlockIDPickerContext(field: field, route: route, marker: marker, intent: intent, rules: rules)
        )
    }

    /// Routes `pomodoro_block_id`/`task_block_id` responses into the generic
    /// picker with intent-aware opening rules. Link intent mirrors `^`: an
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
            BlockIDPickerIndex(field: completion.blockID, candidates: completion.candidates, route: context.route)
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

    /// The filter seed: the draft text typed after `^` so far, by UTF-8 byte
    /// range. Text typed before the picker appears seeds the filter.
    private static func pickerQuery(in draft: String, range: CaptureRange, cursor: Int) -> String {
        guard let queryRange = stringRange(in: draft, start: range.start, end: min(cursor, range.end)) else {
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
        snapshotIsPartial: Bool
    ) {
        let presentation = index.presentation(filter: query)
        pickerIndex = index
        pickerPresentation = presentation
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
            snapshotIsPartial: snapshotIsPartial
        )
        dismissCompletion()
        pickerChip = nil
        editorInputLocked = true
        requestFocus(.pickerFilter)
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
        picker = updated
        pickerPresentation = presentation
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

    func acceptPickerRow(id: String, submitAfterInsert: Bool) {
        guard let picker = picker,
              plainDraft == picker.draftSnapshot,
              let range = stringRange(in: plainDraft, byteRange: picker.replacementRange)
        else {
            // The draft moved under the picker: never edit a stale draft.
            closePickerAfterStaleDraft()
            return
        }
        guard let row = pickerPresentation?.row(id: id),
              let insertion = row.insertion
        else {
            // No selectable row: a no-op that announces why, leaving the
            // picker open. `^` keeps its silent no-op.
            if case .blockID = picker.source {
                announceStatus(
                    Self.blockIDNoAcceptReason(filter: picker.filterText, presentation: pickerPresentation)
                )
            }
            return
        }

        var text = plainDraft
        text.replaceSubrange(range, with: insertion)
        let caret = picker.replacementRange.start + insertion.utf8.count
        guard stringRange(in: text, start: caret, end: caret) != nil else {
            closePickerAfterStaleDraft()
            return
        }

        let source = picker.source
        closePickerForAccept()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(text, cursorUTF8Offset: caret, suppressSelectionCallbacks: true)
        scheduleAnalysis(cursorUTF8Offset: caret, requestCompletion: false, trigger: .edit)
        // Block-ID insertions are bare IDs; name the marker they landed on.
        if case .blockID(let context) = source {
            announceStatus("Inserted @\(context.route)\(context.marker)\(insertion)")
        } else {
            announceStatus("Inserted \(insertion)")
        }
        if submitAfterInsert {
            submit(openAfterCapture: false)
        }
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

    /// Cancel leaves the draft unchanged, restores the caret, suppresses
    /// auto-open for this token, and shows the reopen chip.
    func cancelPicker() {
        guard let openPicker = picker else {
            return
        }
        let range = openPicker.replacementRange
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
    /// with any fragment it opened on (`^` for active tasks). Otherwise
    /// behaves like cancel.
    func removePickerTrigger() {
        guard let picker = picker, picker.filterText.isEmpty else {
            return
        }
        let r = picker.replacementRange
        let caretBytes = Array(plainDraft.utf8)
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
        // whole part.
        let query: String
        if case .blockID(let context) = chip.source,
           context.isNewIDMode,
           let partRange = stringRange(in: draft, byteRange: r)
        {
            query = String(draft[partRange])
        } else {
            query = Self.pickerQuery(in: draft, range: r, cursor: chip.cursor)
        }
        if chip.cursor != r.start, let processClient {
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
        case .blockID(let context):
            // The chip's source already carries the opening snapshot's
            // field, route, marker, intent, and rules.
            presentPicker(
                source: chip.source,
                index: .blockID(
                    BlockIDPickerIndex(field: context.field, candidates: chip.candidates, route: context.route)
                ),
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
    /// Precedence is `active_task`, then `pomodoro_id`, then `block_id`,
    /// checked top-level or in any item. Suffix-only states such as
    /// `@sase:x#` (`pomodoro_name`) keep today's behavior.
    private static func pickerNeed(in parse: CaptureParseResponse) -> CapturePickerNeed? {
        let itemNeeds = parse.items.flatMap { $0.needs }
        func needs(_ need: String) -> Bool {
            parse.needs.contains(need) || itemNeeds.contains(need)
        }
        if needs("active_task") {
            return .activeTask
        }
        if needs("pomodoro_id") {
            return .pomodoroID
        }
        if needs("block_id") {
            return .blockID
        }
        return nil
    }

    private func applyQuietIncompletePicker(_ need: CapturePickerNeed) {
        previewState = .idle
        previewResult = nil
        previewResults = []
        previewGlobalDestination = nil
        errorMessage = nil
        statusText = need.statusText
    }

    private func closePickerForAccept() {
        picker = nil
        pickerPresentation = nil
        pickerIndex = nil
        pickerChip = nil
        clearEditorInputLockIfFree()
        requestFocus(.editor)
    }

    private func closePickerAfterStaleDraft() {
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
            pickerChip = nil
            pickerAutoOpenSuppressedStart = nil
            return
        }
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

        if completionResponse.context == "pomodoro_name", candidate.requiresName {
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
        guard let route = prompt.candidate.route,
              let taskRef = prompt.candidate.taskRef
        else {
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
        statusText = "Adding to \(route).md\u{2026}"
        let blockID = prompt.authoredID

        Task {
            do {
                let response = try await CaptureSignpost.measure("capture-task-id") {
                    try await processClient.assignCaptureTaskID(
                        route: route,
                        taskRef: taskRef,
                        blockID: blockID
                    )
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
            query: completionQueryText()
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
            } else if let presentation = Self.soleClosePresentation(for: captures) {
                statusText = presentation.statusText
            } else if let presentation = Self.soleSessionStartPresentation(for: captures) {
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
            if let presentation = Self.soleClosePresentation(for: captures) {
                statusText = presentation.statusText
            } else if let presentation = Self.soleSessionStartPresentation(for: captures) {
                statusText = presentation.statusText
            } else if let presentation = Self.soleTogglePresentation(for: captures) {
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

    private static func soleClosePresentation(
        for captures: [CaptureCommandSuccess]
    ) -> CapturePomodoroClosePresentation? {
        guard captures.count == 1 else {
            return nil
        }
        return CapturePomodoroClosePresentation(capture: captures[0])
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
        statusText = "Preview failed"
    }

    private func setPlainDraft(
        _ text: String,
        cursorUTF8Offset: Int? = nil,
        suppressSelectionCallbacks: Bool = false
    ) {
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

        analysisTask = Task { [weak self, processClient] in
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                try Task.checkCancellation()

                let parse = try await CaptureSignpost.measure("parse") {
                    try await processClient.captureParse(draft)
                }
                try Task.checkCancellation()

                await MainActor.run {
                    guard self?.isCurrentAnalysis(generation) == true else {
                        return
                    }
                    self?.applyParse(parse, draft: draft)
                    if let need = Self.pickerNeed(in: parse) {
                        // An incomplete `^` is a state, not an error: skip the
                        // doomed live dry run and stay calm instead of flashing
                        // red "incomplete Pomodoro link" errors while picking.
                        self?.applyQuietIncompletePicker(need)
                    }
                }

                guard await self?.isCurrentAnalysis(generation) == true else {
                    return
                }

                if Self.pickerNeed(in: parse) == nil {
                    await self?.startLivePreview(
                        draft: draft,
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
        generation: UInt64,
        processClient: BobProcessClient
    ) {
        Task { [weak self, processClient] in
            do {
                let seed = await self?.activePriorityRollSeed() ?? UUID().uuidString
                let preview = try await CaptureSignpost.measure("preview") {
                    try await processClient.captureLivePreview(
                        draft,
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
                        if let presentation = Self.soleTogglePresentation(for: captures) {
                            self?.statusText = presentation.statusText
                        } else if let link = Self.soleLinkPresentation(for: captures) {
                            self?.statusText = link.statusText
                        } else if let close = Self.soleClosePresentation(for: captures) {
                            self?.statusText = close.statusText
                        } else if let start = Self.soleSessionStartPresentation(for: captures) {
                            self?.statusText = start.statusText
                        }
                    case .failure(let failure):
                        self?.previewState = .failed(failure.error)
                        // Like `failPreview`: a failed live dry run must never
                        // leave a stale card beside the red error.
                        self?.previewResult = nil
                        self?.previewResults = []
                        self?.previewGlobalDestination = nil
                        self?.errorMessage = failure.error
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
            for item in ranges {
                guard let lower = AttributedString.Index(item.range.lowerBound, within: text),
                      let upper = AttributedString.Index(item.range.upperBound, within: text)
                else {
                    ignoredMalformedSpan = true
                    return
                }

                let category = captureSemanticCategory(forSpanKind: item.span.kind)
                text[lower..<upper].foregroundColor = CaptureEditorPalette.color(for: category)
            }
        }
        isApplyingProgrammaticDraft = false
        if ignoredMalformedSpan {
            statusText = "Ignored malformed parse spans"
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
            "route", "section", "pomodoro_id", "pomodoro_name", "task", "task_section",
            "active_task", "block_id",
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
        // completion the same way `pomodoro_block_id` already does.
        let completionSpanKinds = Set([
            "route",
            "section",
            "task_block_id_route",
            "task_block_id",
            "pomodoro_route",
            "pomodoro_block_id",
            "pomodoro_name",
            "sub_bullet_route",
            "sub_bullet_block_id",
            "sub_bullet_section",
            "task_toggle_route",
            "task_toggle_block_id",
            "task_toggle_pomodoro_name",
            "active_task_route",
            "active_task_block_id",
            "global_route",
            "global_sub_bullet_route",
            "global_sub_bullet_block_id",
            "interactive_placeholder",
            "wikilink_delimiter",
            "wikilink_target",
            "wikilink_heading",
            "wikilink_block_id",
            "wikilink_alias",
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
            return "\(prefix) \u{2192} \(displayLabel(for: capture)) (\(capture.relativeTarget)): \(capture.taskLine)"
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
            return "\(prefix) \u{2192} \(displayLabel(for: captures[0]))"
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
        if CapturePomodoroClosePresentation(capture: capture) != nil {
            return true
        }
        if CapturePomodoroStartPresentation.isSessionStart(capture) {
            return true
        }
        if let toggle = CaptureTogglePresentation(capture: capture) {
            return toggle.dayFileChanged
        }
        if let link = CapturePomodoroLinkPresentation(capture: capture) {
            return link.dayFileChanged
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
