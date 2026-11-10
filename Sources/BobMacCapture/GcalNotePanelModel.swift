import CaptureCore
import Combine
import Foundation

@MainActor
final class GcalNotePanelModel: ObservableObject {
    @Published private(set) var isPresented = false {
        didSet {
            guard isPresented != oldValue else { return }
            onPresentationChange?(isPresented)
        }
    }
    @Published private(set) var revision = 0
    @Published private(set) var session: GcalNoteSession?
    @Published private(set) var missingBob = false
    @Published private(set) var selectedPickerIdentity: GcalNoteIdentity?
    @Published private(set) var calendarNoteActionIsFocused = false
    @Published private(set) var focusedCalendarURL: String?

    var onPresentationChange: ((Bool) -> Void)?

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
        processClient?.gcalNoteKnownUnsupported == true
    }

    var pickerEvents: [GcalNoteEvent] {
        guard let session else { return [] }
        return session.ambiguousCandidates.isEmpty
            ? session.filteredEvents
            : session.ambiguousCandidates
    }

    var selectedPickerEvent: GcalNoteEvent? {
        guard let selectedPickerIdentity else { return nil }
        return pickerEvents.first { $0.identity == selectedPickerIdentity }
    }

    func setProcessClient(_ client: BobProcessClient?) {
        guard processClient !== client else { return }
        session?.leave()
        processClient = client
        missingBob = client == nil
        session = client.map { client in
            let next = GcalNoteSession(process: client, onAgendaRefresh: onAgendaRefresh)
            next.onChange = { [weak self, weak next] in
                guard let self, let next else { return }
                self.synchronizeSelection(from: next)
                self.revision &+= 1
                self.objectWillChange.send()
            }
            return next
        }
        selectedPickerIdentity = nil
        revision &+= 1
    }

    func present(url: String? = nil) {
        guard !isPresented else { return }
        calendarNoteActionIsFocused = false
        focusedCalendarURL = nil
        selectedPickerIdentity = nil
        isPresented = true
        guard let session else {
            missingBob = true
            return
        }
        missingBob = false
        if let url, !url.isEmpty {
            session.enter(url: url)
        } else {
            session.enterPicker()
        }
    }

    func leave() {
        guard isPresented else { return }
        isPresented = false
        session?.leave()
        selectedPickerIdentity = nil
        clearCalendarFocus()
    }

    func setFilter(_ text: String) {
        session?.setFilter(text)
        synchronizeSelection(from: session)
    }

    func moveSelection(_ direction: Int) {
        let events = pickerEvents
        guard !events.isEmpty else { return }
        let current = selectedPickerIdentity.flatMap { identity in
            events.firstIndex { $0.identity == identity }
        } ?? (direction < 0 ? events.count : -1)
        let next = min(max(current + direction, 0), events.count - 1)
        selectedPickerIdentity = events[next].identity
    }

    func openSelectedEvent() {
        guard let event = selectedPickerEvent else { return }
        session?.select(event)
    }

    func open(_ event: GcalNoteEvent) {
        selectedPickerIdentity = event.identity
        session?.select(event)
    }

    func retry() {
        session?.retry()
    }

    @discardableResult
    func undoLastMutation() -> Bool {
        guard session?.canUndoMutation == true else { return false }
        session?.undoLastMutation()
        return true
    }

    func setCalendarNoteActionFocused(_ focused: Bool, url: String?) {
        calendarNoteActionIsFocused = focused
        focusedCalendarURL = focused ? url : nil
    }

    func clearCalendarFocus() {
        calendarNoteActionIsFocused = false
        focusedCalendarURL = nil
    }

    private func synchronizeSelection(from session: GcalNoteSession?) {
        guard let session else {
            selectedPickerIdentity = nil
            return
        }
        if let identity = session.selectedIdentity {
            selectedPickerIdentity = identity
            return
        }
        let events = session.ambiguousCandidates.isEmpty
            ? session.filteredEvents
            : session.ambiguousCandidates
        if let selectedPickerIdentity,
            events.contains(where: { $0.identity == selectedPickerIdentity })
        {
            return
        }
        selectedPickerIdentity = events.first?.identity
    }
}

struct GcalNotePanelMetrics: Equatable {
    let contentHeight: CGFloat

    static func resolved(availableScreenHeight: CGFloat?) -> Self {
        let preferred: CGFloat = 420
        let fallbackLimit: CGFloat = 680
        let screenLimit = availableScreenHeight.map { max(280, $0 - 88) } ?? fallbackLimit
        return Self(contentHeight: min(preferred, screenLimit))
    }
}
