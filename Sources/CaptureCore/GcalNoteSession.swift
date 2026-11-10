import Foundation

/// One last successful event-note mutation that Command-Z can reverse.
/// `previousText` is nil when the prior canonical state was absence.
public struct GcalNoteMutationUndo: Equatable, Sendable {
    public let identity: GcalNoteIdentity
    public let scope: GcalNoteScope
    public let previousText: String?
}

/// Dedicated event-note lifecycle. It owns list/filter/select, per-scope drafts,
/// debounced preview, serialized save/clear/undo, capability state, and stale
/// response rejection, and it can be exercised without the capture panel.
@MainActor
public final class GcalNoteSession {
    public enum Phase: Equatable, Sendable {
        case inactive
        case loadingList
        case listing
        case resolving
        case editing
        case previewPending
        case writing
        case unsupported
        case recoverableError(message: String, retry: RetryKind, uncertain: Bool)
    }

    public enum RetryKind: Equatable, Sendable {
        case list
        case show
        case preview
        case reloadThenWrite
    }

    public struct DayGroup: Equatable, Sendable {
        public let day: String
        public let events: [GcalNoteEvent]
    }

    public nonisolated static let defaultPreviewDebounceNanoseconds: UInt64 = 150_000_000

    public private(set) var phase: Phase = .inactive { didSet { notifyChange() } }
    public private(set) var events: [GcalNoteEvent] = [] { didSet { notifyChange() } }
    public private(set) var filterText = "" { didSet { notifyChange() } }
    public private(set) var selectedIdentity: GcalNoteIdentity? { didSet { notifyChange() } }
    public private(set) var selectedEvent: GcalNoteEvent? { didSet { notifyChange() } }
    public private(set) var scope: GcalNoteScope = .event { didSet { notifyChange() } }
    public private(set) var editorText = "" { didSet { notifyChange() } }
    public private(set) var isEditorDirty = false { didSet { notifyChange() } }
    public private(set) var showResponse: GcalNoteShowResponse? { didSet { notifyChange() } }
    public private(set) var previewResponse: GcalNoteWriteResponse? { didSet { notifyChange() } }
    public private(set) var lastValidPreview: GcalNoteWriteResponse? { didSet { notifyChange() } }
    public private(set) var writeResponse: GcalNoteWriteResponse? { didSet { notifyChange() } }
    public private(set) var previewError: String? { didSet { notifyChange() } }
    public private(set) var statusBanner: GcalNoteStatus? { didSet { notifyChange() } }
    public private(set) var warnings: [String] = [] { didSet { notifyChange() } }
    public private(set) var ambiguousCandidates: [GcalNoteEvent] = [] { didSet { notifyChange() } }
    public private(set) var mutationUndo: GcalNoteMutationUndo? { didSet { notifyChange() } }
    public private(set) var listWarnings: [String] = [] { didSet { notifyChange() } }
    /// UI clients may observe state changes without making the portable session depend on
    /// Combine or SwiftUI.
    public var onChange: (() -> Void)?

    public var canUndoMutation: Bool { mutationUndo != nil }
    /// True when the selected scope has a saved note of its own. An empty
    /// occurrence must not clear an inherited series note.
    public var canClearSavedScope: Bool {
        guard selectedIdentity != nil else { return false }
        let canonical = (currentCanonicalText() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !canonical.isEmpty
    }
    public var navigationDeferred: Bool { phase == .writing }
    public var isListEmpty: Bool { events.isEmpty }
    public var hasNoFilterMatches: Bool { !events.isEmpty && filteredEvents.isEmpty }
    public var isEditorKeySurface: Bool {
        switch phase {
        case .editing, .previewPending, .writing:
            return selectedEvent != nil
        default:
            return false
        }
    }
    public var showsEditor: Bool {
        switch phase {
        case .editing, .previewPending, .writing, .resolving:
            return selectedEvent != nil
        default:
            return false
        }
    }
    public var livePreview: GcalNotePresentation.LivePreview {
        GcalNotePresentation.livePreview(
            editorText: editorText,
            isDirty: isEditorDirty,
            phase: phase,
            show: showResponse,
            preview: previewResponse,
            lastValid: lastValidPreview,
            previewError: previewError
        )
    }

    public var availableScopes: [GcalNoteScope] {
        selectedEvent?.isRecurring == true ? [.event, .series] : [.event]
    }

    public var filteredEvents: [GcalNoteEvent] {
        Self.filtered(events: events, query: filterText)
    }

    public var groupedEvents: [DayGroup] {
        Self.grouped(events: filteredEvents)
    }

    private let process: BobProcessClient
    private let previewDebounceNanoseconds: UInt64
    private let onAgendaRefresh: (() -> Void)?
    private var generation: UInt64 = 0
    private var drafts: [GcalNoteDraftKey: String] = [:]
    private var canonicalText: [GcalNoteDraftKey: String] = [:]
    private var listTask: Task<Void, Never>?
    private var showTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var writeTask: Task<Void, Never>?
    private var pendingLeave = false
    private var pendingWrite: PendingWrite?
    private var lastURLQuery: String?
    private var suppressedChangeNotifications = 0

    private func notifyChange() {
        guard suppressedChangeNotifications == 0 else { return }
        onChange?()
    }

    private func publish(_ body: () -> Void) {
        suppressedChangeNotifications += 1
        body()
        suppressedChangeNotifications -= 1
        notifyChange()
    }

    private struct GcalNoteDraftKey: Hashable {
        let identity: GcalNoteIdentity
        let scope: GcalNoteScope
    }

    private struct ReadToken: Equatable {
        let generation: UInt64
        let identity: GcalNoteIdentity?
        let scope: GcalNoteScope?
        let text: String
    }

    private struct PendingWrite {
        enum Kind {
            case save
            case clear
        }

        let kind: Kind
        let identity: GcalNoteIdentity
        let scope: GcalNoteScope
        let text: String
        let previousCanonical: String?
        let isUndo: Bool
    }

    public init(
        process: BobProcessClient,
        previewDebounceNanoseconds: UInt64 = GcalNoteSession.defaultPreviewDebounceNanoseconds,
        onAgendaRefresh: (() -> Void)? = nil
    ) {
        self.process = process
        self.previewDebounceNanoseconds = previewDebounceNanoseconds
        self.onAgendaRefresh = onAgendaRefresh
    }

    public func enterPicker() {
        guard phase != .writing else { return }
        beginSession(resetDrafts: phase == .inactive)
        lastURLQuery = nil
        loadList()
    }

    public func enter(url: String) {
        guard phase != .writing else { return }
        beginSession(resetDrafts: phase == .inactive)
        lastURLQuery = url
        ambiguousCandidates = []
        bumpGeneration()
        phase = .resolving
        let token = currentToken
        showTask?.cancel()
        showTask = Task { [weak self] in
            await self?.performShow(query: url, token: token)
        }
    }

    public func setFilter(_ text: String) {
        filterText = text
    }

    public func select(_ event: GcalNoteEvent) {
        select(identity: event.identity, fallbackEvent: event)
    }

    public func select(identity: GcalNoteIdentity, fallbackEvent: GcalNoteEvent? = nil) {
        guard phase != .writing else { return }
        if phase == .inactive {
            return
        }
        stashCurrentDraft()
        selectedIdentity = identity
        selectedEvent = fallbackEvent ?? events.first { $0.identity == identity }
        scope = selectedEvent?.isRecurring == true ? scopeIfRecurring() : .event
        editorText = ""
        isEditorDirty = false
        showResponse = nil
        previewResponse = nil
        lastValidPreview = nil
        previewError = nil
        ambiguousCandidates = []
        bumpGeneration()
        loadShow()
    }

    public func toggleScope() {
        let next: GcalNoteScope = scope == .series ? .event : .series
        setScope(next)
    }

    public func requestPreview() {
        guard isEditingSurface, selectedIdentity != nil else { return }
        schedulePreview()
    }

    public func setScope(_ next: GcalNoteScope) {
        guard phase != .writing, phase != .inactive else { return }
        guard availableScopes.contains(next), next != scope else { return }
        stashCurrentDraft()
        scope = next
        bumpGeneration()
        let key = draftKey()
        if let draft = key.flatMap({ drafts[$0] }) {
            applyRestoredDraft(draft)
            return
        }
        loadShow()
    }

    public func setEditorText(_ text: String) {
        guard isEditingSurface else { return }
        editorText = text
        isEditorDirty = true
        stashCurrentDraft()
        schedulePreview()
    }

    public func save() {
        guard phase == .editing || phase == .previewPending else { return }
        guard let identity = selectedIdentity else { return }
        if !isEditorDirty && editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        startWrite(
            PendingWrite(
                kind: .save,
                identity: identity,
                scope: writableScope,
                text: editorText,
                previousCanonical: currentCanonicalText(),
                isUndo: false
            )
        )
    }

    public func clear() {
        guard phase == .editing || phase == .previewPending else { return }
        guard let identity = selectedIdentity else { return }
        guard canClearSavedScope else { return }
        startWrite(
            PendingWrite(
                kind: .clear,
                identity: identity,
                scope: writableScope,
                text: editorText,
                previousCanonical: currentCanonicalText(),
                isUndo: false
            )
        )
    }

    public func undoLastMutation() {
        guard !navigationDeferred, let record = mutationUndo else { return }
        if let previous = record.previousText, !previous.isEmpty {
            startWrite(
                PendingWrite(
                    kind: .save,
                    identity: record.identity,
                    scope: record.scope,
                    text: previous,
                    previousCanonical: nil,
                    isUndo: true
                )
            )
        } else {
            startWrite(
                PendingWrite(
                    kind: .clear,
                    identity: record.identity,
                    scope: record.scope,
                    text: "",
                    previousCanonical: nil,
                    isUndo: true
                )
            )
        }
    }

    public func retry() {
        guard case .recoverableError(_, let retry, _) = phase else { return }
        switch retry {
        case .list:
            loadList()
        case .show:
            if let url = lastURLQuery, selectedIdentity == nil {
                enter(url: url)
            } else {
                loadShow()
            }
        case .preview:
            schedulePreview()
        case .reloadThenWrite:
            reloadThenRetryWrite()
        }
    }

    public func returnToPicker() {
        guard phase != .writing, phase != .inactive else { return }
        stashCurrentDraft()
        cancelReads()
        selectedIdentity = nil
        selectedEvent = nil
        showResponse = nil
        previewResponse = nil
        lastValidPreview = nil
        previewError = nil
        editorText = ""
        isEditorDirty = false
        lastURLQuery = nil
        bumpGeneration()
        loadList()
    }

    public func leave() {
        if phase == .writing {
            pendingLeave = true
            return
        }
        finishLeave()
    }

    public var isActive: Bool {
        phase != .inactive
    }

    public var isEditingSurface: Bool {
        switch phase {
        case .editing, .previewPending, .resolving:
            return true
        default:
            return false
        }
    }

    private var writableScope: GcalNoteScope {
        switch scope {
        case .series: return .series
        default: return .event
        }
    }

    private var currentToken: ReadToken {
        ReadToken(
            generation: generation,
            identity: selectedIdentity,
            scope: selectedIdentity == nil ? nil : scope,
            text: editorText
        )
    }

    private func beginSession(resetDrafts: Bool) {
        pendingLeave = false
        if resetDrafts {
            drafts.removeAll()
            canonicalText.removeAll()
            mutationUndo = nil
            statusBanner = nil
            warnings = []
            writeResponse = nil
        }
        cancelReads()
        selectedIdentity = nil
        selectedEvent = nil
        showResponse = nil
        previewResponse = nil
        lastValidPreview = nil
        previewError = nil
        editorText = ""
        isEditorDirty = false
        filterText = ""
        ambiguousCandidates = []
        bumpGeneration()
    }

    private func finishLeave() {
        pendingLeave = false
        pendingWrite = nil
        bumpGeneration()
        cancelReads()
        writeTask = nil
        process.cancelLanes(["gcal-note-list", "gcal-note-show", "gcal-note-preview"])
        drafts.removeAll()
        canonicalText.removeAll()
        mutationUndo = nil
        events = []
        filterText = ""
        selectedIdentity = nil
        selectedEvent = nil
        scope = .event
        editorText = ""
        isEditorDirty = false
        showResponse = nil
        previewResponse = nil
        lastValidPreview = nil
        writeResponse = nil
        previewError = nil
        statusBanner = nil
        warnings = []
        ambiguousCandidates = []
        listWarnings = []
        lastURLQuery = nil
        phase = .inactive
    }

    private func bumpGeneration() {
        generation &+= 1
    }

    private func cancelReads() {
        listTask?.cancel()
        showTask?.cancel()
        previewTask?.cancel()
        listTask = nil
        showTask = nil
        previewTask = nil
        process.cancelLanes(["gcal-note-list", "gcal-note-show", "gcal-note-preview"])
    }

    private func draftKey(
        identity: GcalNoteIdentity? = nil,
        scope: GcalNoteScope? = nil
    ) -> GcalNoteDraftKey? {
        guard let identity = identity ?? selectedIdentity else { return nil }
        return GcalNoteDraftKey(identity: identity, scope: scope ?? self.scope)
    }

    private func stashCurrentDraft() {
        guard let key = draftKey() else { return }
        drafts[key] = editorText
    }

    private func currentCanonicalText() -> String? {
        guard let key = draftKey() else { return nil }
        return canonicalText[key]
    }

    private func scopeIfRecurring() -> GcalNoteScope {
        switch scope {
        case .series: return .series
        default: return .event
        }
    }

    private func loadList() {
        if process.gcalNoteKnownUnsupported {
            phase = .unsupported
            return
        }
        phase = .loadingList
        let token = currentToken
        listTask?.cancel()
        listTask = Task { [weak self] in
            await self?.performList(token: token)
        }
    }

    private func loadShow() {
        guard let identity = selectedIdentity else { return }
        if process.gcalNoteKnownUnsupported {
            phase = .unsupported
            return
        }
        phase = .resolving
        previewResponse = nil
        lastValidPreview = nil
        previewError = nil
        let token = currentToken
        showTask?.cancel()
        showTask = Task { [weak self] in
            await self?.performShow(
                eventID: identity.eventID,
                calendarID: identity.calendarID,
                token: token
            )
        }
    }

    private func schedulePreview() {
        guard selectedIdentity != nil else { return }
        previewError = nil
        phase = .previewPending
        let token = currentToken
        previewTask?.cancel()
        let delay = previewDebounceNanoseconds
        previewTask = Task { [weak self] in
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await self?.performPreview(token: token)
        }
    }

    private func startWrite(_ request: PendingWrite) {
        pendingWrite = request
        phase = .writing
        previewTask?.cancel()
        let token = ReadToken(
            generation: generation,
            identity: request.identity,
            scope: request.scope,
            text: request.text
        )
        writeTask = Task { [weak self] in
            await self?.performWrite(request, token: token)
        }
    }

    private func reloadThenRetryWrite() {
        guard let pending = pendingWrite else {
            loadShow()
            return
        }
        phase = .resolving
        let token = currentToken
        showTask?.cancel()
        showTask = Task { [weak self] in
            await self?.performShow(
                eventID: pending.identity.eventID,
                calendarID: pending.identity.calendarID,
                token: token,
                thenRetryWrite: true
            )
        }
    }

    private func performList(token: ReadToken) async {
        do {
            let response = try await process.gcalNoteList()
            guard publishable(token, kind: .list) else { return }
            events = response.events
            listWarnings = response.warnings
            phase = .listing
        } catch let error as BobClientError {
            guard publishable(token, kind: .list) else { return }
            applyClientError(error, retry: .list, uncertain: false)
        } catch {
            guard publishable(token, kind: .list) else { return }
            applyClientError(
                BobClientError.processFailed(command: [], exitStatus: 1, stderr: "\(error)"),
                retry: .list,
                uncertain: false
            )
        }
    }

    private func performShow(
        query: String? = nil,
        eventID: String? = nil,
        calendarID: String? = nil,
        token: ReadToken,
        thenRetryWrite: Bool = false
    ) async {
        do {
            let response = try await process.gcalNoteShow(
                query: query,
                eventID: eventID,
                calendarID: calendarID,
                scope: eventID == nil ? nil : writableScope
            )
            guard publishable(token, kind: .show) else { return }
            applyShow(response, thenRetryWrite: thenRetryWrite)
        } catch let error as BobClientError {
            guard publishable(token, kind: .show) else { return }
            applyClientError(error, retry: .show, uncertain: false)
        } catch {
            guard publishable(token, kind: .show) else { return }
            applyClientError(
                BobClientError.processFailed(command: [], exitStatus: 1, stderr: "\(error)"),
                retry: .show,
                uncertain: false
            )
        }
    }

    private func performPreview(token: ReadToken) async {
        guard let identity = token.identity else { return }
        do {
            let response = try await process.gcalNotePreview(
                text: token.text,
                eventID: identity.eventID,
                calendarID: identity.calendarID,
                scope: token.scope ?? .event
            )
            guard publishable(token, kind: .preview) else { return }
            publish {
                previewResponse = response
                if response.ok {
                    lastValidPreview = response
                    previewError = nil
                } else {
                    previewError = response.error?.message ?? response.errors.first?.message
                }
                warnings = response.warnings
                phase = .editing
            }
        } catch is CancellationError {
            return
        } catch let error as BobClientError {
            guard publishable(token, kind: .preview) else { return }
            if case .unsupportedCommand = error {
                phase = .unsupported
                return
            }
            previewError = error.description
            phase = .editing
        } catch {
            guard publishable(token, kind: .preview) else { return }
            previewError = "\(error)"
            phase = .editing
        }
    }

    private func performWrite(_ request: PendingWrite, token: ReadToken) async {
        do {
            let response: GcalNoteWriteResponse
            switch request.kind {
            case .save:
                response = try await process.gcalNoteSave(
                    text: request.text,
                    eventID: request.identity.eventID,
                    calendarID: request.identity.calendarID,
                    scope: request.scope
                )
            case .clear:
                response = try await process.gcalNoteClear(
                    eventID: request.identity.eventID,
                    calendarID: request.identity.calendarID,
                    scope: request.scope
                )
            }
            guard stillOwnsWrite(token) else { return }
            applyWrite(response, request: request)
        } catch is CancellationError {
            guard stillOwnsWrite(token) else { return }
            if pendingLeave {
                finishLeave()
            }
        } catch let error as BobClientError {
            guard stillOwnsWrite(token) else { return }
            applyClientError(error, retry: .reloadThenWrite, uncertain: true)
            if pendingLeave {
                finishLeave()
            }
        } catch {
            guard stillOwnsWrite(token) else { return }
            applyClientError(
                BobClientError.processFailed(command: [], exitStatus: 1, stderr: "\(error)"),
                retry: .reloadThenWrite,
                uncertain: true
            )
            if pendingLeave {
                finishLeave()
            }
        }
    }

    private func applyShow(_ response: GcalNoteShowResponse, thenRetryWrite: Bool) {
        if !response.candidates.isEmpty, response.event == nil {
            publish {
                ambiguousCandidates = response.candidates
                warnings = response.warnings
                phase = .listing
            }
            return
        }
        guard let event = response.event else {
            let message = response.error?.message ?? "Could not open that event note."
            phase = .recoverableError(message: message, retry: .show, uncertain: false)
            return
        }
        publish {
            showResponse = response
            selectedEvent = event
            selectedIdentity = event.identity
            if let returnedScope = response.scope, availableScopes.contains(returnedScope) {
                scope = returnedScope
            }
            let loaded = event.note?.text ?? ""
            let key = GcalNoteDraftKey(identity: event.identity, scope: writableScope)
            canonicalText[key] = loaded
            if let draft = drafts[key] {
                editorText = draft
                isEditorDirty = draft != loaded
            } else {
                editorText = loaded
                isEditorDirty = false
                drafts[key] = loaded
            }
            lastValidPreview = nil
            previewResponse = nil
            previewError = nil
            warnings = response.warnings
            statusBanner = nil
            if thenRetryWrite, let pending = pendingWrite {
                startWrite(pending)
                return
            }
            if !editorText.isEmpty {
                schedulePreview()
            } else {
                phase = .editing
            }
        }
    }

    private func applyRestoredDraft(_ draft: String) {
        editorText = draft
        let loaded = currentCanonicalText() ?? ""
        isEditorDirty = draft != loaded
        showResponse = nil
        previewResponse = nil
        lastValidPreview = nil
        previewError = nil
        if !editorText.isEmpty {
            schedulePreview()
        } else {
            phase = .editing
        }
    }

    private func applyWrite(_ response: GcalNoteWriteResponse, request: PendingWrite) {
        writeResponse = response
        warnings = response.warnings
        if response.ok, isSuccessfulMutation(response) {
            statusBanner = response.status
            rememberCanonical(from: response, request: request)
            if request.isUndo {
                mutationUndo = nil
            } else if shouldRecordUndo(response) {
                mutationUndo = GcalNoteMutationUndo(
                    identity: request.identity,
                    scope: request.scope,
                    previousText: emptyToNil(request.previousCanonical)
                )
            }
            onAgendaRefresh?()
            if pendingLeave {
                finishLeave()
                return
            }
            pendingWrite = nil
            returnToPickerAfterMutation()
            return
        }
        if pendingLeave {
            finishLeave()
            return
        }
        previewResponse = response
        previewError = response.error?.message ?? response.errors.first?.message
        if let event = response.event {
            selectedEvent = event
        }
        phase = .editing
    }

    private func returnToPickerAfterMutation() {
        stashCurrentDraft()
        selectedIdentity = nil
        selectedEvent = nil
        showResponse = nil
        previewResponse = nil
        lastValidPreview = nil
        previewError = nil
        editorText = ""
        isEditorDirty = false
        bumpGeneration()
        loadList()
    }

    private func rememberCanonical(from response: GcalNoteWriteResponse, request: PendingWrite) {
        let key = GcalNoteDraftKey(identity: request.identity, scope: request.scope)
        if request.kind == .clear || response.action == "cleared" {
            canonicalText[key] = ""
            drafts[key] = ""
        } else if let text = response.note?.text ?? response.input?.text {
            canonicalText[key] = text
            drafts[key] = text
        }
    }

    private func isSuccessfulMutation(_ response: GcalNoteWriteResponse) -> Bool {
        guard response.ok else { return false }
        if response.status?.state == "sync_failed" {
            return true
        }
        switch response.action {
        case "saved", "cleared", "unchanged":
            return true
        default:
            return response.status?.state == "saved"
                || response.status?.state == "cleared"
                || response.status?.state == "unchanged"
                || response.status?.state == "waiting_note"
                || response.status?.state == "applied"
        }
    }

    private func shouldRecordUndo(_ response: GcalNoteWriteResponse) -> Bool {
        if response.action == "unchanged" || response.status?.state == "unchanged" {
            return false
        }
        return true
    }

    private func applyClientError(
        _ error: BobClientError,
        retry: RetryKind,
        uncertain: Bool
    ) {
        if case .unsupportedCommand = error {
            phase = .unsupported
            return
        }
        phase = .recoverableError(
            message: error.description,
            retry: retry,
            uncertain: uncertain
        )
    }

    private enum ReadKind {
        case list
        case show
        case preview
    }

    private func publishable(_ token: ReadToken, kind: ReadKind) -> Bool {
        if pendingLeave || phase == .inactive {
            return false
        }
        if token.generation != generation {
            return false
        }
        switch kind {
        case .list:
            return selectedIdentity == nil
        case .show:
            if token.identity == nil {
                return selectedIdentity == nil
            }
            return token.identity == selectedIdentity && token.scope == scope
        case .preview:
            return token == currentToken
        }
    }

    private func stillOwnsWrite(_ token: ReadToken) -> Bool {
        if phase == .inactive {
            return false
        }
        guard let pending = pendingWrite else { return false }
        return pending.identity == token.identity
            && pending.scope == token.scope
            && pending.text == token.text
    }

    private func emptyToNil(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    static func filtered(events: [GcalNoteEvent], query: String) -> [GcalNoteEvent] {
        let fuzzy = FuzzyQuery(query, leadingSigil: "")
        let ordered = events.sorted(by: startOrder)
        guard !fuzzy.isEmpty else { return ordered }
        return ordered.filter { event in
            fuzzy.tokens.allSatisfy { token in
                fields(for: event).contains { field in
                    FuzzyMatcher.match(token: token, in: field) != nil
                }
            }
        }
    }

    static func grouped(events: [GcalNoteEvent]) -> [DayGroup] {
        var order: [String] = []
        var buckets: [String: [GcalNoteEvent]] = [:]
        for event in events {
            let day = event.day ?? ""
            if buckets[day] == nil {
                order.append(day)
                buckets[day] = []
            }
            buckets[day, default: []].append(event)
        }
        return order.map { day in
            DayGroup(day: day, events: buckets[day] ?? [])
        }
    }

    private static func fields(for event: GcalNoteEvent) -> [FuzzyField] {
        [
            FuzzyField(event.title ?? ""),
            FuzzyField(event.organizer?.name ?? ""),
            FuzzyField(event.calendarName ?? ""),
            FuzzyField(event.time ?? ""),
        ]
    }

    private static func startOrder(_ lhs: GcalNoteEvent, _ rhs: GcalNoteEvent) -> Bool {
        switch (lhs.start, rhs.start) {
        case (let left?, let right?):
            if left != right { return left < right }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }
        if lhs.eventID != rhs.eventID {
            return lhs.eventID < rhs.eventID
        }
        return lhs.calendarID < rhs.calendarID
    }
}
