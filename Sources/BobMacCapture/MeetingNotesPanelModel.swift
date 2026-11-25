import CaptureCore
import Combine
import Foundation

@MainActor
final class MeetingNotesPanelModel: ObservableObject {
    @Published private(set) var isPresented = false {
        didSet {
            guard isPresented != oldValue else { return }
            onPresentationChange?(isPresented)
        }
    }
    @Published private(set) var revision = 0
    @Published private(set) var session: MeetingNotesSession?
    @Published private(set) var missingBob = false
    @Published private(set) var selectedMeetingRef: String?
    @Published private(set) var meetingActionIsFocused = false
    @Published private(set) var focusedMeetingRef: String?
    @Published var filterText = ""

    var onPresentationChange: ((Bool) -> Void)?
    var onReceipt: ((MeetingNotesResponse) -> Void)?

    private var processClient: BobProcessClient?
    private let onAgendaRefresh: (() -> Void)?

    init(
        processClient: BobProcessClient? = nil,
        onAgendaRefresh: (() -> Void)? = nil
    ) {
        missingBob = processClient == nil
        self.onAgendaRefresh = onAgendaRefresh
        setProcessClient(processClient)
    }

    var menuItemShouldBeHidden: Bool {
        processClient?.meetingNotesKnownUnsupported == true
    }

    var isWriting: Bool {
        session?.isWriting == true
    }

    var pickerMeetings: [MeetingNotesMeeting] {
        guard let session else { return [] }
        let base: [MeetingNotesMeeting]
        if session.state == .choosingMeeting, !session.meetingChoices.isEmpty {
            base = session.meetingChoices
        } else {
            base = session.meetings
        }
        let needle = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(needle)
                || $0.date.lowercased().contains(needle)
        }
    }

    var selectedMeeting: MeetingNotesMeeting? {
        guard let ref = selectedMeetingRef else { return nil }
        return pickerMeetings.first { $0.eventRef == ref }
    }

    func setProcessClient(_ client: BobProcessClient?) {
        guard processClient !== client else { return }
        session?.leave()
        processClient = client
        missingBob = client == nil
        session = client.map { client in
            let next = MeetingNotesSession(process: client)
            next.onChange = { [weak self, weak next] in
                guard let self, let next else { return }
                self.synchronizeSelection(from: next)
                self.revision &+= 1
                self.objectWillChange.send()
            }
            next.onRefresh = { [weak self] in
                self?.onAgendaRefresh?()
            }
            next.onReceipt = { [weak self] receipt in
                self?.onReceipt?(receipt)
            }
            return next
        }
        selectedMeetingRef = nil
        revision &+= 1
    }

    func recheckBob() {
        session?.recheckBob()
    }

    func present(eventRef: String? = nil) {
        guard !isPresented else {
            // Re-entry with a new agenda token restarts the session.
            session?.enter(eventToken: eventRef)
            return
        }
        meetingActionIsFocused = false
        focusedMeetingRef = nil
        selectedMeetingRef = nil
        filterText = ""
        isPresented = true
        guard let session else {
            missingBob = true
            return
        }
        missingBob = false
        session.enter(eventToken: eventRef)
    }

    func leave() {
        guard isPresented else { return }
        isPresented = false
        session?.leave()
        selectedMeetingRef = nil
        filterText = ""
        clearMeetingFocus()
    }

    func file() {
        session?.file()
    }

    func retryPreview() {
        session?.retryPreview()
    }

    func retryList() {
        session?.retryList()
    }

    func selectMeeting(_ meeting: MeetingNotesMeeting) {
        guard let token = meeting.eventRef, !token.isEmpty else { return }
        selectedMeetingRef = token
        session?.selectMeeting(meeting)
    }

    func selectMeeting(eventRef: String) {
        guard !eventRef.isEmpty else { return }
        selectedMeetingRef = eventRef
        session?.selectMeeting(eventToken: eventRef)
    }

    func moveSelection(_ direction: Int) {
        let meetings = pickerMeetings
        guard !meetings.isEmpty else { return }
        let current = selectedMeetingRef.flatMap { ref in
            meetings.firstIndex { $0.eventRef == ref }
        } ?? (direction < 0 ? meetings.count : -1)
        let next = min(max(current + direction, 0), meetings.count - 1)
        selectedMeetingRef = meetings[next].eventRef
    }

    func openSelectedMeeting() {
        guard let meeting = selectedMeeting else { return }
        // Return on a candidate selects and previews it; it never files.
        session?.selectMeeting(meeting)
    }

    func chooseParent(_ choice: MeetingNotesParentChoice) {
        session?.chooseParent(choice)
    }

    func chooseParent(route: String) {
        session?.chooseParent(route: route)
    }

    func chooseNext() {
        session?.chooseNext()
    }

    func chooseRead() {
        session?.chooseRead()
    }

    func clearStatusOverride() {
        session?.chooseStatus(nil)
    }

    func confirmReplace() {
        session?.confirmReplace()
    }

    func declineReplace() {
        session?.declineReplace()
    }

    func handleEscape() {
        guard let session else {
            leave()
            return
        }
        switch session.state {
        case .choosingMeeting, .choosingParent, .confirmingReplace:
            // One level back: return to the preview/loading state.
            session.retryPreview()
        case .filed, .queued, .empty, .unsupported:
            leave()
        case .recoverableError:
            leave()
        case .inactive:
            leave()
        case .loading, .previewReady, .writing:
            leave()
        }
    }

    func setMeetingActionFocused(_ focused: Bool, eventRef: String?) {
        meetingActionIsFocused = focused
        focusedMeetingRef = focused ? eventRef : nil
    }

    func clearMeetingFocus() {
        meetingActionIsFocused = false
        focusedMeetingRef = nil
    }

    private func synchronizeSelection(from session: MeetingNotesSession?) {
        guard let session else {
            selectedMeetingRef = nil
            return
        }
        if let token = session.eventToken, !token.isEmpty {
            selectedMeetingRef = token
            return
        }
        let meetings = session.state == .choosingMeeting
            && !session.meetingChoices.isEmpty
            ? session.meetingChoices : session.meetings
        if let selectedMeetingRef,
            meetings.contains(where: { $0.eventRef == selectedMeetingRef })
        {
            return
        }
        selectedMeetingRef = meetings.first?.eventRef
    }
}

struct MeetingNotesPanelMetrics: Equatable {
    let contentHeight: CGFloat

    static func resolved(
        availableScreenHeight: CGFloat?,
        writing: Bool = false
    ) -> Self {
        let preferred: CGFloat = writing ? 520 : 480
        let fallbackLimit: CGFloat = 680
        let screenLimit = availableScreenHeight.map { max(280, $0 - 88) } ?? fallbackLimit
        return Self(contentHeight: min(preferred, screenLimit))
    }
}
