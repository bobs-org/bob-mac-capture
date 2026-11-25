import CaptureCore
import Combine
import Foundation

enum MeetingNotesReplaceAction: Equatable, Hashable, CaseIterable {
    case openExisting
    case reviewReplacement
    case keepExisting
}

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
    @Published private(set) var selectedParentRoute: String?
    @Published private(set) var selectedReplaceAction: MeetingNotesReplaceAction =
        .reviewReplacement
    @Published private(set) var meetingActionIsFocused = false
    @Published private(set) var focusedMeetingRef: String?
    @Published var filterText = "" {
        didSet { ensureMeetingSelectionVisible() }
    }

    var onPresentationChange: ((Bool) -> Void)?
    var onReceipt: ((MeetingNotesResponse) -> Void)?
    var onOpenNote: ((String) -> Void)?
    /// Extra native entry gates (capture submit, Event Note mutation).
    var entryGate: () -> Bool = { true }

    var hasMeetingActionFocus: Bool { meetingActionIsFocused }

    var keySurface: MeetingNotesKeySurface {
        guard isPresented else { return .inactive }
        switch session?.state {
        case .choosingMeeting: return .choosingMeeting
        case .choosingParent: return .choosingParent
        case .confirmingReplace: return .confirmingReplace
        case .previewReady: return .preview
        case .writing: return .writing
        default: return .other
        }
    }

    private var processClient: BobProcessClient?
    private var deferredProcessClient: BobProcessClient?
    private var hasDeferredProcessClient = false
    private let onAgendaRefresh: (() -> Void)?

    init(
        processClient: BobProcessClient? = nil,
        onAgendaRefresh: (() -> Void)? = nil
    ) {
        missingBob = processClient == nil
        self.onAgendaRefresh = onAgendaRefresh
        setProcessClient(processClient)
    }

    var menuItemShouldBeHidden: Bool { entryShouldBeHidden }
    var entryShouldBeHidden: Bool {
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

    var pickerRows: [(id: String, meeting: MeetingNotesMeeting)] {
        pickerMeetings.enumerated().map { index, meeting in
            (meeting.presentationIdentity(at: index), meeting)
        }
    }

    var selectablePickerMeetings: [MeetingNotesMeeting] {
        pickerMeetings.filter(\.canSelect)
    }

    var selectedMeeting: MeetingNotesMeeting? {
        guard let ref = selectedMeetingRef else { return nil }
        return pickerMeetings.first { $0.eventRef == ref }
    }

    var replaceActions: [MeetingNotesReplaceAction] {
        var actions: [MeetingNotesReplaceAction] = []
        if session?.canOpenExisting == true {
            actions.append(.openExisting)
        }
        actions.append(.reviewReplacement)
        actions.append(.keepExisting)
        return actions
    }

    func setProcessClient(_ client: BobProcessClient?) {
        guard processClient !== client else { return }
        // Keep the writing session and its later receipt onscreen. Apply the
        // replacement only after this sheet is no longer presented.
        if session?.isWriting == true || isPresented {
            deferredProcessClient = client
            hasDeferredProcessClient = true
            return
        }
        applyProcessClient(client)
    }

    func recheckBob() {
        session?.recheckBob()
    }

    func present(eventRef: String? = nil) {
        guard entryGate() else { return }
        if session?.isWriting == true { return }
        guard !entryShouldBeHidden else { return }
        guard !isPresented else {
            session?.enter(eventToken: eventRef)
            return
        }
        meetingActionIsFocused = false
        focusedMeetingRef = nil
        selectedMeetingRef = nil
        selectedParentRoute = nil
        selectedReplaceAction = .reviewReplacement
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
        if session?.isWriting == true {
            session?.leave()
            return
        }
        isPresented = false
        session?.leave()
        selectedMeetingRef = nil
        selectedParentRoute = nil
        filterText = ""
        clearMeetingFocus()
        applyDeferredProcessClientIfSettled()
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

    func showChooser() {
        session?.showChooser()
    }

    func selectMeeting(_ meeting: MeetingNotesMeeting) {
        guard meeting.canSelect, let token = meeting.eventRef else { return }
        selectedMeetingRef = token
        session?.selectMeeting(meeting)
    }

    func selectMeeting(eventRef: String) {
        guard !eventRef.isEmpty else { return }
        selectedMeetingRef = eventRef
        session?.selectMeeting(eventToken: eventRef)
    }

    func moveSelection(_ direction: Int) {
        switch session?.state {
        case .choosingMeeting:
            moveMeetingSelection(direction)
        case .choosingParent:
            moveParentSelection(direction)
        case .confirmingReplace:
            moveReplaceSelection(direction)
        default:
            break
        }
    }

    func openSelectedMeeting() {
        switch session?.state {
        case .choosingMeeting:
            guard let meeting = selectedMeeting, meeting.canSelect else { return }
            session?.selectMeeting(meeting)
        case .choosingParent:
            activateSelectedParent()
        case .confirmingReplace:
            activateReplaceAction()
        default:
            break
        }
    }

    func chooseParent(_ choice: MeetingNotesParentChoice) {
        selectedParentRoute = choice.route
        session?.chooseParent(choice)
    }

    func chooseParent(route: String) {
        selectedParentRoute = route
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
        if session.isWriting {
            session.leave()
            return
        }
        switch session.state {
        case .choosingMeeting:
            if session.cancelChooser() {
                synchronizeSelection(from: session)
                return
            }
            leave()
        case .choosingParent, .confirmingReplace:
            leave()
        case .filed, .queued, .empty, .unsupported, .recoverableError, .inactive, .loading,
            .previewReady:
            leave()
        case .writing:
            session.leave()
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

    func activateReplaceAction(_ action: MeetingNotesReplaceAction? = nil) {
        let action = action ?? selectedReplaceAction
        selectedReplaceAction = action
        switch action {
        case .openExisting:
            openExistingOrFiledNote()
        case .reviewReplacement:
            session?.confirmReplace()
        case .keepExisting:
            session?.declineReplace()
        }
    }

    func openExistingOrFiledNote() {
        guard let path = session?.existingNotePath, !path.isEmpty else { return }
        onOpenNote?(path)
    }

    private func applyProcessClient(_ client: BobProcessClient?) {
        session?.leave()
        processClient = client
        missingBob = client == nil
        session = client.map { client in
            let next = MeetingNotesSession(process: client)
            next.onChange = { [weak self, weak next] in
                guard let self, let next else { return }
                self.synchronizeSelection(from: next)
                self.applyDeferredProcessClientIfSettled()
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
        selectedParentRoute = nil
        revision &+= 1
    }

    private func applyDeferredProcessClientIfSettled() {
        guard hasDeferredProcessClient else { return }
        guard session?.isWriting != true else { return }
        guard !isPresented else { return }
        hasDeferredProcessClient = false
        let next = deferredProcessClient
        deferredProcessClient = nil
        applyProcessClient(next)
    }

    private func moveMeetingSelection(_ direction: Int) {
        let meetings = selectablePickerMeetings
        guard !meetings.isEmpty else { return }
        let current = selectedMeetingRef.flatMap { ref in
            meetings.firstIndex { $0.eventRef == ref }
        } ?? (direction < 0 ? meetings.count : -1)
        let next = min(max(current + direction, 0), meetings.count - 1)
        selectedMeetingRef = meetings[next].eventRef
    }

    private func moveParentSelection(_ direction: Int) {
        let choices = session?.parentChoices ?? []
        guard !choices.isEmpty else { return }
        let current = selectedParentRoute.flatMap { route in
            choices.firstIndex { $0.route == route }
        } ?? (direction < 0 ? choices.count : -1)
        let next = min(max(current + direction, 0), choices.count - 1)
        selectedParentRoute = choices[next].route
    }

    private func moveReplaceSelection(_ direction: Int) {
        let actions = replaceActions
        guard !actions.isEmpty else { return }
        let current = actions.firstIndex(of: selectedReplaceAction)
            ?? (direction < 0 ? actions.count : -1)
        let next = min(max(current + direction, 0), actions.count - 1)
        selectedReplaceAction = actions[next]
    }

    private func activateSelectedParent() {
        let choices = session?.parentChoices ?? []
        let route = selectedParentRoute ?? choices.first?.route
        guard let route, choices.contains(where: { $0.route == route }) else { return }
        session?.chooseParent(route: route)
    }

    private func ensureMeetingSelectionVisible() {
        let visible = selectablePickerMeetings
        if let selectedMeetingRef, visible.contains(where: { $0.eventRef == selectedMeetingRef }) {
            return
        }
        selectedMeetingRef = visible.first?.eventRef
    }

    private func synchronizeSelection(from session: MeetingNotesSession?) {
        guard let session else {
            selectedMeetingRef = nil
            selectedParentRoute = nil
            return
        }
        if let token = session.eventToken, !token.isEmpty {
            selectedMeetingRef = token
        } else {
            let meetings = session.state == .choosingMeeting
                && !session.meetingChoices.isEmpty
                ? session.meetingChoices : session.meetings
            let selectable = meetings.filter(\.canSelect)
            if let selectedMeetingRef,
                selectable.contains(where: { $0.eventRef == selectedMeetingRef })
            {
                // Keep the keyboard selection.
            } else {
                selectedMeetingRef = selectable.first?.eventRef
            }
        }
        if session.state == .choosingParent {
            let routes = session.parentChoices.map(\.route)
            if let selectedParentRoute, routes.contains(selectedParentRoute) {
                // Keep the keyboard selection.
            } else {
                selectedParentRoute = routes.first
            }
        }
        if session.state == .confirmingReplace {
            let actions = replaceActions
            if !actions.contains(selectedReplaceAction) {
                selectedReplaceAction = actions.first ?? .reviewReplacement
            }
        }
        ensureMeetingSelectionVisible()
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

extension MeetingNotesReplaceAction {
    var title: String {
        switch self {
        case .openExisting: "Open existing"
        case .reviewReplacement: "Review replacement preview"
        case .keepExisting: "Keep existing"
        }
    }
}
