import Foundation

/// Portable coordinator for `bob ref meet`. It owns request freshness and the
/// one-write lifecycle; Bob remains the authority for clipboard parsing,
/// meeting/parent resolution, and filing.
@MainActor
public final class MeetingNotesSession {
    public enum State: Equatable, Sendable {
        case inactive
        case loading
        case choosingMeeting
        case choosingParent
        case confirmingReplace
        case previewReady
        case writing
        case filed
        case queued
        case empty
        case unsupported
        case recoverableError(code: String, message: String, hint: String?)
    }

    public enum ListState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var state: State = .inactive { didSet { notifyChange() } }
    public private(set) var listState: ListState = .idle { didSet { notifyChange() } }
    public private(set) var meetings: [MeetingNotesMeeting] = [] { didSet { notifyChange() } }
    public private(set) var meetingChoices: [MeetingNotesMeeting] = [] { didSet { notifyChange() } }
    public private(set) var parentChoices: [MeetingNotesParentChoice] = [] {
        didSet { notifyChange() }
    }
    public private(set) var listWarnings: [String] = [] { didSet { notifyChange() } }
    public private(set) var response: MeetingNotesResponse? { didSet { notifyChange() } }
    public private(set) var previewOptions: MeetingNotesOptions? { didSet { notifyChange() } }
    public private(set) var eventToken: String? { didSet { notifyChange() } }
    public private(set) var parent: String? { didSet { notifyChange() } }
    public private(set) var statusOverride: MeetingNotesStatus? { didSet { notifyChange() } }
    public private(set) var overwrite = false { didSet { notifyChange() } }
    public private(set) var notice: String? { didSet { notifyChange() } }

    /// Called when visible state changes, after a batch of related updates.
    public var onChange: (() -> Void)?
    /// Filed and queued receipts both change agenda/library state.
    public var onRefresh: (() -> Void)?
    /// Receipts remain visible in `response`; this callback also observes a
    /// write that the user asked to leave while it was still in flight.
    public var onReceipt: ((MeetingNotesResponse) -> Void)?

    public var isActive: Bool { state != .inactive }
    public var canOpenExisting: Bool { state == .confirmingReplace && response?.existing != nil }
    public var existingNotePath: String? {
        if state == .confirmingReplace, let existing = response?.existing?.note, !existing.isEmpty {
            return existing
        }
        if state == .filed, let note = response?.filing?.note, !note.isEmpty {
            return note
        }
        return nil
    }
    public var canOpenFiledNote: Bool {
        state == .filed && response?.outcome == .filed && response?.filing?.note != nil
    }
    public var queuedNextStep: String? {
        state == .queued && response?.queued != nil
            ? "Run bob ref scan to file the queued notes." : nil
    }
    public var existing: MeetingNotesExisting? { response?.existing }
    public var effectiveStatus: String? { response?.filing?.task.status }
    public var isWriting: Bool { state == .writing }
    public var canFile: Bool {
        guard state == .previewReady,
            let response,
            response.ok,
            response.outcome == .wouldFile,
            let previewOptions,
            previewOptions == currentOptions,
            let eventRef = response.meeting?.eventRef,
            !eventRef.isEmpty,
            let sha256 = response.notes?.sha256
        else {
            return false
        }
        return sha256.utf8.count == 64
            && sha256.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
            }
    }

    private let process: MeetingNotesProcess
    private var sessionGeneration: UInt64 = 0
    private var previewGeneration: UInt64 = 0
    private var listGeneration: UInt64 = 0
    private var listTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var writeTask: Task<Void, Never>?
    private var pendingLeave = false
    private var receiptNotified = false
    private var chooserUsesRecentList = false
    private var chooserReturnPreview: PreviewSnapshot?

    private struct PreviewSnapshot {
        var response: MeetingNotesResponse
        var previewOptions: MeetingNotesOptions
        var eventToken: String?
        var parent: String?
        var statusOverride: MeetingNotesStatus?
        var overwrite: Bool
        var notice: String?
    }

    private var currentOptions: MeetingNotesOptions {
        MeetingNotesOptions(
            eventToken: eventToken,
            parent: parent,
            status: statusOverride,
            overwrite: overwrite
        )
    }

    private var canChangeOptions: Bool {
        switch state {
        case .inactive, .writing, .filed, .queued, .unsupported:
            false
        default:
            true
        }
    }

    public init(process: MeetingNotesProcess) {
        self.process = process
    }

    /// Start list and clipboard preview independently. An agenda caller passes
    /// Bob's event token; a general entry point lets Bob auto-match.
    public func enter(eventToken: String? = nil) {
        guard !isWriting else { return }
        cancelReads()
        sessionGeneration &+= 1
        previewGeneration &+= 1
        pendingLeave = false
        receiptNotified = false
        self.eventToken = eventToken
        parent = nil
        statusOverride = nil
        overwrite = false
        response = nil
        previewOptions = nil
        meetingChoices = []
        parentChoices = []
        listWarnings = []
        meetings = []
        notice = nil
        chooserUsesRecentList = false
        chooserReturnPreview = nil
        listState = .loading
        state = .loading
        listGeneration &+= 1
        loadList(session: sessionGeneration, list: listGeneration)
        requestPreview()
    }

    /// Explicitly recheck capability after Bob is installed or replaced.
    public func recheckBob() {
        process.recheckMeetingNotesCapability()
        guard isActive, state != .writing else { return }
        sessionGeneration &+= 1
        previewGeneration &+= 1
        cancelReads()
        state = .loading
        listState = .loading
        chooserUsesRecentList = false
        chooserReturnPreview = nil
        listGeneration &+= 1
        loadList(session: sessionGeneration, list: listGeneration)
        requestPreview()
    }

    /// Open the recent-meeting chooser from a preview. The current list stays
    /// visible while a fresh list loads; Escape restores the previous preview
    /// without filing or keeping a changed selection.
    public func showChooser() {
        guard canChangeOptions else { return }
        if state == .previewReady, let response, let previewOptions {
            chooserReturnPreview = PreviewSnapshot(
                response: response,
                previewOptions: previewOptions,
                eventToken: eventToken,
                parent: parent,
                statusOverride: statusOverride,
                overwrite: overwrite,
                notice: notice
            )
        } else {
            chooserReturnPreview = nil
        }
        chooserUsesRecentList = true
        if meetingChoices.isEmpty {
            meetingChoices = meetings
        }
        state = .choosingMeeting
        retryList()
    }

    /// Restore the preview that **Change meeting** left, or report that there
    /// is no valid preview to return to so the sheet can close.
    @discardableResult
    public func cancelChooser() -> Bool {
        guard state == .choosingMeeting else { return false }
        guard let snapshot = chooserReturnPreview else { return false }
        previewGeneration &+= 1
        previewTask?.cancel()
        chooserReturnPreview = nil
        chooserUsesRecentList = false
        response = snapshot.response
        previewOptions = snapshot.previewOptions
        eventToken = snapshot.eventToken
        parent = snapshot.parent
        statusOverride = snapshot.statusOverride
        overwrite = snapshot.overwrite
        notice = snapshot.notice
        meetingChoices = []
        parentChoices = []
        state = .previewReady
        return true
    }

    public func selectMeeting(_ meeting: MeetingNotesMeeting) {
        guard canChangeOptions, canSelect(meeting) else { return }
        chooserReturnPreview = nil
        chooserUsesRecentList = false
        eventToken = meeting.eventRef
        parent = nil
        overwrite = false
        requestPreview()
    }

    public func selectMeeting(eventToken: String) {
        guard !eventToken.isEmpty, canChangeOptions else { return }
        chooserReturnPreview = nil
        chooserUsesRecentList = false
        self.eventToken = eventToken
        parent = nil
        overwrite = false
        requestPreview()
    }

    public func chooseParent(_ choice: MeetingNotesParentChoice) {
        guard state == .choosingParent, parentChoices.contains(choice)
        else {
            return
        }
        parent = choice.route
        requestPreview()
    }

    public func chooseParent(route: String) {
        guard state == .choosingParent, parentChoices.contains(where: { $0.route == route })
        else {
            return
        }
        parent = route
        requestPreview()
    }

    public func chooseStatus(_ status: MeetingNotesStatus?) {
        guard canChangeOptions, statusOverride != status else { return }
        statusOverride = status
        requestPreview()
    }

    public func chooseNext() { chooseStatus(.next) }
    public func chooseRead() { chooseStatus(.read) }

    /// Replacement is an explicit answer to Bob's already-filed refusal. The
    /// overwrite preview is a fresh clipboard read and must be approved again.
    public func confirmReplace() {
        guard state == .confirmingReplace, !overwrite else { return }
        overwrite = true
        notice = "Review the replacement preview before filing."
        requestPreview(preservingNotice: true)
    }

    public func declineReplace() {
        guard state == .confirmingReplace else { return }
        previewGeneration &+= 1
        previewTask?.cancel()
        response = nil
        previewOptions = nil
        state = .empty
        notice = "The existing meeting note was left unchanged."
    }

    public func retryPreview() {
        guard canChangeOptions else { return }
        requestPreview()
    }

    public func retryList() {
        guard state != .inactive else { return }
        listState = .loading
        listGeneration &+= 1
        loadList(session: sessionGeneration, list: listGeneration)
    }

    /// Return is accepted only for the current would-file preview. The write
    /// pins Bob's returned event reference even when the preview auto-matched.
    public func file() {
        guard canFile, writeTask == nil,
            let preview = response,
            let eventRef = preview.meeting?.eventRef,
            let sha256 = preview.notes?.sha256,
            let previewOptions
        else {
            return
        }
        let pinnedOptions = MeetingNotesOptions(
            eventToken: eventRef,
            parent: previewOptions.parent,
            status: previewOptions.status,
            overwrite: previewOptions.overwrite
        )
        let request = MeetingNotesFileRequest(options: pinnedOptions, sha256: sha256)
        state = .writing
        notice = nil
        let token = sessionGeneration
        writeTask = Task { [weak self, process] in
            do {
                let result = try await process.meetingNotesFile(request)
                await self?.receiveWrite(result, session: token)
            } catch {
                await self?.receiveWriteError(error, session: token)
            }
        }
    }

    /// Reads are cancelled on leave. An in-flight write is allowed to settle;
    /// its terminal receipt remains onscreen so the mutation is observable.
    public func leave() {
        guard state != .inactive else { return }
        if state == .writing {
            pendingLeave = true
            cancelReads()
            return
        }
        sessionGeneration &+= 1
        previewGeneration &+= 1
        cancelReads()
        response = nil
        previewOptions = nil
        eventToken = nil
        parent = nil
        statusOverride = nil
        overwrite = false
        notice = nil
        meetings = []
        meetingChoices = []
        parentChoices = []
        listWarnings = []
        chooserUsesRecentList = false
        chooserReturnPreview = nil
        listState = .idle
        state = .inactive
    }

    private func loadList(session token: UInt64, list listToken: UInt64) {
        listTask?.cancel()
        listTask = Task { [weak self, process] in
            do {
                let result = try await process.meetingNotesList()
                await self?.receiveList(result, session: token, list: listToken)
            } catch {
                await self?.receiveListError(error, session: token, list: listToken)
            }
        }
    }

    private func requestPreview(preservingNotice: Bool = false) {
        guard state != .inactive, state != .writing else { return }
        previewGeneration &+= 1
        let token = previewGeneration
        let options = currentOptions
        previewTask?.cancel()
        response = nil
        previewOptions = nil
        meetingChoices = []
        parentChoices = []
        if !preservingNotice {
            notice = nil
        }
        state = .loading
        previewTask = Task { [weak self, process] in
            do {
                let result = try await process.meetingNotesPreview(options)
                await self?.receivePreview(result, options: options, generation: token)
            } catch {
                await self?.receivePreviewError(error, generation: token)
            }
        }
    }

    private func receiveList(
        _ result: MeetingNotesListResponse,
        session token: UInt64,
        list listToken: UInt64
    ) {
        guard token == sessionGeneration, listToken == listGeneration, state != .inactive else {
            return
        }
        guard result.ok else {
            listState = .failed("Bob could not load the recent meeting list.")
            if state == .choosingMeeting && meetingChoices.isEmpty {
                state = .empty
                notice = "Recent meetings could not be loaded. Retry the list or preview."
            }
            return
        }
        meetings = result.meetings
        listWarnings = result.warnings
        listState = .loaded
        if state == .choosingMeeting, meetingChoices.isEmpty || chooserUsesRecentList {
            meetingChoices = result.meetings
            if meetingChoices.isEmpty {
                state = .empty
                notice = "No recent meetings are available to choose."
            }
        }
    }

    private func receiveListError(_ error: Error, session token: UInt64, list listToken: UInt64) {
        guard token == sessionGeneration, listToken == listGeneration, state != .inactive else {
            return
        }
        if isUnsupported(error) {
            state = .unsupported
            listState = .failed("Meeting notes require an updated Bob command.")
        } else {
            listState = .failed(error.localizedDescription)
            if state == .choosingMeeting && meetingChoices.isEmpty {
                state = .empty
                notice = "Recent meetings could not be loaded. Retry the list or preview."
            }
        }
    }

    private func receivePreview(
        _ result: MeetingNotesResponse,
        options: MeetingNotesOptions,
        generation token: UInt64
    ) {
        guard token == previewGeneration, state != .inactive else { return }
        response = result
        if result.ok {
            guard result.outcome == .wouldFile else {
                setRecoverable(
                    code: "unexpected_outcome",
                    message: "Bob returned a filing receipt during preview.",
                    hint: nil
                )
                return
            }
            if result.meeting?.eventRef == nil || result.notes?.sha256 == nil {
                previewOptions = options
                setRecoverable(
                    code: "incomplete_preview",
                    message:
                        "Bob's preview did not include the event identity and notes hash needed to file.",
                    hint: "Retry the preview after updating Bob."
                )
                return
            }
            if let matched = result.meeting?.eventRef, !matched.isEmpty {
                eventToken = matched
            }
            previewOptions = MeetingNotesOptions(
                eventToken: eventToken,
                parent: options.parent,
                status: options.status,
                overwrite: options.overwrite
            )
            state = .previewReady
            return
        }

        previewOptions = nil
        guard let error = result.error else {
            setRecoverable(
                code: "invalid_response",
                message: "Bob refused the meeting notes request without a structured error.",
                hint: nil
            )
            return
        }
        switch error.code {
        case "ambiguous_meeting", "no_meeting":
            chooserReturnPreview = nil
            meetingChoices = result.candidates.map(\.meeting)
            chooserUsesRecentList = meetingChoices.isEmpty
            if meetingChoices.isEmpty {
                meetingChoices = meetings
            }
            if meetingChoices.isEmpty && listState != .loading {
                state = .empty
                notice = error.hint ?? error.message
            } else {
                state = .choosingMeeting
            }
        case "needs_parent":
            parentChoices = result.parentCandidates
            if parentChoices.isEmpty {
                setRecoverable(code: error.code, message: error.message, hint: error.hint)
            } else {
                state = .choosingParent
            }
        case "already_filed":
            state = .confirmingReplace
        case "no_notes", "notes_unreadable":
            state = .empty
            notice = [error.message, error.hint].compactMap { $0 }.joined(separator: " ")
        case "notes_changed":
            notice = "The clipboard changed. Review the new preview before filing."
            requestPreview(preservingNotice: true)
        default:
            setRecoverable(code: error.code, message: error.message, hint: error.hint)
        }
    }

    private func receivePreviewError(_ error: Error, generation token: UInt64) {
        guard token == previewGeneration, state != .inactive else { return }
        if isUnsupported(error) {
            state = .unsupported
            response = nil
            previewOptions = nil
        } else {
            setRecoverable(code: "process_error", message: error.localizedDescription, hint: nil)
        }
    }

    private func receiveWrite(_ result: MeetingNotesResponse, session token: UInt64) {
        guard token == sessionGeneration, state == .writing else { return }
        writeTask = nil
        response = result
        if result.ok, result.outcome == .filed || result.outcome == .queued {
            previewOptions = nil
            state = result.outcome == .filed ? .filed : .queued
            if pendingLeave {
                notice = "Filing finished. Review the receipt before closing."
            }
            notifyReceipt(result)
            pendingLeave = false
            return
        }
        guard let error = result.error else {
            setRecoverable(
                code: "invalid_receipt",
                message: "Bob did not confirm whether the meeting notes were filed.",
                hint: "Check the meeting list before retrying."
            )
            return
        }
        previewOptions = nil
        switch error.code {
        case "notes_changed":
            notice =
                "The clipboard changed. Bob did not file those notes. Review a fresh preview before filing."
            state = .loading
            requestPreview(preservingNotice: true)
        case "already_filed":
            state = .confirmingReplace
        case "needs_parent":
            parentChoices = result.parentCandidates
            state =
                parentChoices.isEmpty
                ? .recoverableError(
                    code: error.code, message: error.message, hint: error.hint
                ) : .choosingParent
        case "ambiguous_meeting", "no_meeting":
            chooserReturnPreview = nil
            meetingChoices = result.candidates.map(\.meeting)
            chooserUsesRecentList = meetingChoices.isEmpty
            if meetingChoices.isEmpty { meetingChoices = meetings }
            state = meetingChoices.isEmpty ? .empty : .choosingMeeting
        case "no_notes", "notes_unreadable":
            state = .empty
            notice = [error.message, error.hint].compactMap { $0 }.joined(separator: " ")
        default:
            setRecoverable(code: error.code, message: error.message, hint: error.hint)
        }
    }

    private func receiveWriteError(_ error: Error, session token: UInt64) {
        guard token == sessionGeneration, state == .writing else { return }
        writeTask = nil
        if isUnsupported(error) {
            state = .unsupported
        } else {
            setRecoverable(
                code: "write_error",
                message: error.localizedDescription,
                hint: "Check the meeting list before retrying."
            )
        }
        if pendingLeave {
            notice = "The filing finished with an error. Review it before closing."
        }
        pendingLeave = false
    }

    private func notifyReceipt(_ receipt: MeetingNotesResponse) {
        guard !receiptNotified else { return }
        receiptNotified = true
        onRefresh?()
        onReceipt?(receipt)
    }

    private func setRecoverable(code: String, message: String, hint: String?) {
        state = .recoverableError(code: code, message: message, hint: hint)
    }

    private func canSelect(_ meeting: MeetingNotesMeeting) -> Bool {
        guard let token = meeting.eventRef, !token.isEmpty else { return false }
        return meetingChoices.contains { $0.eventRef == token }
            || meetings.contains { $0.eventRef == token }
    }

    private func isUnsupported(_ error: Error) -> Bool {
        if let clientError = error as? BobClientError,
            case .unsupportedCommand = clientError
        {
            return true
        }
        return process.meetingNotesKnownUnsupported
    }

    private func cancelReads() {
        listTask?.cancel()
        previewTask?.cancel()
        listTask = nil
        previewTask = nil
        process.cancelMeetingNotesReads()
    }

    private func notifyChange() { onChange?() }
}

extension BobProcessClient: MeetingNotesProcess {}
