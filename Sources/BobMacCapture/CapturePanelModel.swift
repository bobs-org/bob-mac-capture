import AppKit
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
    @Published var statusText = ""
    @Published var pendingDiscardConfirmation = false
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

    var processClient: BobProcessClient?
    var notificationService: NotificationService?
    var targetOpener: (URL) -> Void = { NSWorkspace.shared.open($0) }

    private let debounceNanoseconds: UInt64
    private var analysisTask: Task<Void, Never>?
    private var analysisGeneration: UInt64 = 0
    private var isApplyingProgrammaticDraft = false
    private var priorityRollSeed: String?

    // Shared by submit and preview so a late callback from either one can never mutate
    // state on behalf of a request that is no longer the active one.
    private var activeRequestID: UUID?

    init(
        processClient: BobProcessClient? = nil,
        debounceNanoseconds: UInt64 = 50_000_000
    ) {
        self.processClient = processClient
        self.debounceNanoseconds = debounceNanoseconds
    }

    deinit {
        analysisTask?.cancel()
    }

    var plainDraft: String {
        get { String(attributedDraft.characters) }
        set { setPlainDraft(newValue, scheduleAnalysis: false) }
    }

    var hasDraft: Bool {
        !plainDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var completionVisible: Bool {
        completionResponse?.candidates.isEmpty == false
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

        pendingDiscardConfirmation = false
        let draft = plainDraft
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            priorityRollSeed = nil
            parseDiagnostics = []
            completionResponse = nil
            previewState = .idle
            statusText = ""
            analysisTask?.cancel()
            return
        }

        scheduleAnalysis(cursorUTF8Offset: cursorUTF8Offset ?? draft.utf8.count)
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

    func requestClose() -> Bool {
        guard hasDraft else {
            pendingDiscardConfirmation = false
            return true
        }
        pendingDiscardConfirmation = true
        statusText = "Draft retained"
        return false
    }

    func discardDraft() {
        setPlainDraft("", scheduleAnalysis: false)
        priorityRollSeed = nil
        pendingDiscardConfirmation = false
        parseDiagnostics = []
        completionResponse = nil
        previewState = .idle
        statusText = ""
        errorMessage = nil
        previewResult = nil
        analysisTask?.cancel()
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
        let cursor = completionResponse.replacement.start + candidate.replacement.utf8.count
        dismissCompletion()
        setPlainDraft(text, scheduleAnalysis: true, cursorUTF8Offset: cursor)
    }

    func detailText(for candidate: CaptureCompletionCandidate, context: String?) -> String {
        switch context {
        case "route":
            return [
                candidate.kind,
                candidate.status,
                candidate.label,
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        case "section":
            if let level = candidate.level {
                return "Heading \(level)"
            }
            return "Heading"
        case "pomodoro_block_id", "task":
            return [
                candidate.statusSymbol,
                candidate.statusName,
                candidate.section,
                candidate.blockID,
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        default:
            return candidate.label ?? candidate.text ?? ""
        }
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
            lastSuccess = success
            previewResult = nil
            errorMessage = nil
            attributedDraft = AttributedString()
            pendingDiscardConfirmation = false
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
        scheduleAnalysis: Bool,
        cursorUTF8Offset: Int? = nil
    ) {
        isApplyingProgrammaticDraft = true
        attributedDraft = AttributedString(text)
        isApplyingProgrammaticDraft = false

        if scheduleAnalysis {
            editorTextDidChange(cursorUTF8Offset: cursorUTF8Offset)
        }
    }

    private func scheduleAnalysis(cursorUTF8Offset: Int) {
        guard let processClient else {
            statusText = "Bob is not resolved"
            return
        }

        let draft = plainDraft
        guard cursorUTF8Offset >= 0,
              cursorUTF8Offset <= draft.utf8.count,
              stringRange(in: draft, start: cursorUTF8Offset, end: cursorUTF8Offset) != nil
        else {
            statusText = "Cursor is not on a UTF-8 boundary"
            return
        }

        analysisGeneration += 1
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

                if await self?.shouldRequestCompletion(parse: parse, cursor: cursorUTF8Offset) == true {
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

        var highlighted = AttributedString(draft)
        for item in ranges {
            guard let lower = AttributedString.Index(item.range.lowerBound, within: highlighted),
                  let upper = AttributedString.Index(item.range.upperBound, within: highlighted)
            else {
                statusText = "Ignored malformed parse spans"
                return
            }

            highlighted[lower..<upper].foregroundColor = color(forSpanKind: item.span.kind)
        }

        isApplyingProgrammaticDraft = true
        attributedDraft = highlighted
        isApplyingProgrammaticDraft = false
    }

    private func color(forSpanKind kind: String) -> Color {
        switch kind {
        case "route", "pomodoro_route", "sub_bullet_route":
            return .accentColor
        case "section":
            return .purple
        case "pomodoro_block_id", "sub_bullet_block_id":
            return .indigo
        case "schedule":
            return .green
        case "priority":
            return .orange
        case "clipboard":
            return .teal
        case "interactive_placeholder":
            return .secondary
        default:
            return .primary
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
            "pomodoro_route",
            "pomodoro_block_id",
            "sub_bullet_route",
            "sub_bullet_block_id",
            "interactive_placeholder",
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
        let routeSpanKinds = Set(["route", "pomodoro_route", "sub_bullet_route"])

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
}
