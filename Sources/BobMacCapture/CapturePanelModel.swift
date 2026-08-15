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
    // Incremented on every successful capture so the view can drive a VoiceOver
    // announcement without needing `CaptureCommandSuccess` to be diffed for equality.
    @Published var successAnnouncementTick = 0
    @Published var statusAnnouncementTick = 0
    @Published var isStashPickerPresented = false
    @Published var selectedStashIndex = 0

    var processClient: BobProcessClient?
    var notificationService: NotificationService?
    var targetOpener: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var panelDismisser: () -> Void = {}
    let canceledDraftStash: CanceledDraftStash

    private let debounceNanoseconds: UInt64
    private var analysisTask: Task<Void, Never>?
    private var stashCancellable: AnyCancellable?
    private var analysisGeneration: UInt64 = 0
    private var isApplyingProgrammaticDraft = false
    // SwiftUI can deliver the text-change callback after a programmatic binding update.
    // Remember the accepted value so that callback cannot start completion analysis again.
    private var suppressedCompletionAcceptanceDraft: String?
    private var programmaticSelectionOffsetToIgnore: Int?
    private var priorityRollSeed: String?

    // Shared by submit and preview so a late callback from either one can never mutate
    // state on behalf of a request that is no longer the active one.
    private var activeRequestID: UUID?

    init(
        processClient: BobProcessClient? = nil,
        debounceNanoseconds: UInt64 = 50_000_000,
        canceledDraftStash: CanceledDraftStash = CanceledDraftStash()
    ) {
        self.processClient = processClient
        self.debounceNanoseconds = debounceNanoseconds
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
    }

    var plainDraft: String {
        get { String(attributedDraft.characters) }
        set { setPlainDraft(newValue) }
    }

    var hasDraft: Bool {
        !plainDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var completionVisible: Bool {
        !isStashPickerPresented && completionResponse?.candidates.isEmpty == false
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
        if let previewResult {
            return "Preview \u{2192} \(previewResult.routeLabel) (\(previewResult.relativeTarget)): \(previewResult.taskLine)"
        }
        if let lastSuccess {
            return "Captured \u{2192} \(lastSuccess.routeLabel) (\(lastSuccess.relativeTarget)): \(lastSuccess.taskLine)"
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

    func setProcessClient(_ processClient: BobProcessClient?) {
        self.processClient = processClient
        if processClient == nil {
            statusText = "Bob is not resolved"
            previewState = .idle
            completionResponse = nil
            invalidateAnalysis()
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
            previewState = .idle
            statusText = ""
            invalidateAnalysis()
            return
        }

        let insertionOffset = cursorUTF8Offset ?? collapsedSelectionUTF8Offset()
        scheduleAnalysis(cursorUTF8Offset: insertionOffset, requestCompletion: insertionOffset != nil)
    }

    func editorSelectionDidChange() {
        editorSelectionDidChange(cursorUTF8Offset: collapsedSelectionUTF8Offset())
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

        scheduleAnalysis(cursorUTF8Offset: insertionOffset, requestCompletion: insertionOffset != nil)
    }

    func collapsedSelectionUTF8Offset() -> Int? {
        switch editorSelection.indices(in: attributedDraft) {
        case .insertionPoint(let index):
            return utf8Offset(in: attributedDraft, at: index)
        case .ranges(_):
            return nil
        }
    }

    func submit(openAfterCapture: Bool) {
        guard !isSubmitting, !isPreviewing, hasDraft else {
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
        guard !isSubmitting, !isPreviewing, hasDraft else {
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
        if isStashPickerPresented {
            dismissStashPicker()
        } else {
            presentStashPicker()
        }
    }

    func presentStashPicker() {
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
        scheduleAnalysis(cursorUTF8Offset: text.utf8.count, requestCompletion: false)
        canceledDraftStash.remove(id: entry.id)
        announceStatus("Restored canceled draft")
    }

    // Called before the panel is (re)shown. A retained draft (from Escape or a failed
    // capture) must reopen exactly as the user left it, error and all; only a panel with
    // no draft — i.e. one that just dismissed after a success — needs its leftover
    // success summary and status cleared so the next capture starts clean.
    func prepareForPresentation() {
        dismissStashPicker()
        guard !hasDraft else {
            return
        }
        resetAnalysisState()
        lastSuccess = nil
        selectedCompletionIndex = 0
    }

    func prepareForDismissal() {
        dismissStashPicker()
    }

    private func resetAnalysisState() {
        invalidateAnalysis()
        parseDiagnostics = []
        completionResponse = nil
        previewState = .idle
        statusText = ""
        errorMessage = nil
        previewResult = nil
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
        selectedCompletionIndex = 0
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

        var text = plainDraft
        text.replaceSubrange(range, with: candidate.replacement)
        let cursor = candidate.cursorAfter ?? completionResponse.replacement.start + candidate.replacement.utf8.count
        guard stringRange(in: text, start: cursor, end: cursor) != nil else {
            statusText = "Completion cursor is stale"
            dismissCompletion()
            return
        }

        dismissCompletion()
        suppressedCompletionAcceptanceDraft = text
        setPlainDraft(
            text,
            cursorUTF8Offset: cursor,
            suppressSelectionCallbacks: true
        )
        scheduleAnalysis(cursorUTF8Offset: cursor, requestCompletion: false)
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
            invalidateAnalysis()
            lastSuccess = success
            previewResult = nil
            errorMessage = nil
            setPlainDraft("")
            suppressedCompletionAcceptanceDraft = nil
            priorityRollSeed = nil
            parseDiagnostics = []
            completionResponse = nil
            previewState = .idle
            statusText = "Captured \u{2192} \(success.routeLabel)"
            successAnnouncementTick += 1
            notificationService?.notifyCaptureSuccess(routeLabel: success.routeLabel, targetPath: success.target)
            if openAfterCapture, let url = ObsidianOpenURL.url(forAbsolutePath: success.target) {
                targetOpener(url)
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
            previewResult = success
            errorMessage = nil
            statusText = "Preview \u{2192} \(success.routeLabel)"
        case .failure(let failure):
            errorMessage = failure.error
            statusText = "Preview failed"
        }
    }

    private func failPreview(requestID: UUID, error: Error) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        isPreviewing = false
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

    private func scheduleAnalysis(cursorUTF8Offset: Int?, requestCompletion: Bool) {
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
                }

                guard await self?.isCurrentAnalysis(generation) == true else {
                    return
                }

                await self?.startLivePreview(
                    draft: draft,
                    generation: generation,
                    processClient: processClient
                )

                if let cursorUTF8Offset,
                   requestCompletion,
                   await self?.shouldRequestCompletion(parse: parse, cursor: cursorUTF8Offset) == true
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
                            self?.completionResponse = cached
                            self?.selectedCompletionIndex = 0
                        }
                    }

                    do {
                        let completion = try await CaptureSignpost.measure("completion") {
                            try await processClient.captureComplete(
                                draft,
                                cursor: cursorUTF8Offset
                            )
                        }
                        await MainActor.run {
                            guard self?.isCurrentAnalysis(generation) == true else {
                                return
                            }
                            self?.completionResponse = completion.candidates.isEmpty ? nil : completion
                            self?.selectedCompletionIndex = 0
                            self?.applyCompletionWarnings(completion.warnings)
                        }
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
                        self?.dismissCompletion()
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
                        self?.previewState = .ready(success)
                    case .failure(let failure):
                        self?.previewState = .failed(failure.error)
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

    private func shouldRequestCompletion(parse: CaptureParseResponse, cursor: Int) -> Bool {
        let completionNeeds = Set(["route", "section", "pomodoro_id", "task"])
        if !completionNeeds.isDisjoint(with: Set(parse.needs)) {
            return true
        }

        let completionSpanKinds = Set([
            "route",
            "section",
            "task_block_id_route",
            "pomodoro_route",
            "pomodoro_block_id",
            "sub_bullet_route",
            "sub_bullet_block_id",
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
        let routeSpanKinds = Set(["route", "task_block_id_route", "pomodoro_route", "sub_bullet_route"])

        for span in parse.spans where cursor >= span.start && cursor <= span.end {
            if routeSpanKinds.contains(span.kind) {
                var start = span.start
                if let markerRange = stringRange(in: draft, start: span.start, end: min(span.start + 1, span.end)),
                   draft[markerRange] == "@"
                {
                    start += 1
                }
                return CaptureRange(start: min(start, span.end), end: span.end)
            }

            if span.kind == "interactive_placeholder", parse.needs.contains("route") {
                return CaptureRange(start: cursor, end: cursor)
            }
        }

        if parse.needs.contains("route") {
            return CaptureRange(start: cursor, end: cursor)
        }

        return nil
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
}
