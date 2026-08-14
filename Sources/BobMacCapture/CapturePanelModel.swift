import Foundation

@MainActor
final class CapturePanelModel: ObservableObject {
    @Published var attributedDraft = AttributedString()
    @Published var statusText = ""
    @Published var pendingDiscardConfirmation = false

    var plainDraft: String {
        get { String(attributedDraft.characters) }
        set { attributedDraft = AttributedString(newValue) }
    }

    var hasDraft: Bool {
        !plainDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit(openAfterCapture: Bool) {
        statusText = openAfterCapture ? "Submit and open requested" : "Submit requested"
    }

    func insertNewline() {
        attributedDraft.append(AttributedString("\n"))
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
        attributedDraft = AttributedString()
        pendingDiscardConfirmation = false
        statusText = ""
    }
}
