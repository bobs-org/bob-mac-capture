import AppKit
import SwiftUI

/// Lets `CapturePanelController` find and repair focus for the relation card.
let relationLabelFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.relation-label-field"

@available(macOS 26.0, *)
final class RelationLabelNSTextField: NSTextField {
    private var wantsFirstResponder = false

    func requestFirstResponder() {
        wantsFirstResponder = true
        claimFirstResponderIfPending()
    }

    private func claimFirstResponderIfPending() {
        guard wantsFirstResponder, let window else { return }
        wantsFirstResponder = false
        if window.makeFirstResponder(self) {
            CaptureSignpost.event("relation-label-focus-claimed")
        } else {
            CaptureSignpost.event("relation-label-focus-claim-failed")
        }
    }

    var holdsFirstResponder: Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder === self || (currentEditor().map { $0 === responder } ?? false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        claimFirstResponderIfPending()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, holdsFirstResponder {
            _ = window?.makeFirstResponder(nil)
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

@available(macOS 26.0, *)
struct RelationLabelField: NSViewRepresentable {
    @Binding var text: String
    let isEnabled: Bool
    let focusRequest: CapturePanelFocusRequest
    let focusDidChange: (Bool) -> Void

    func makeNSView(context: Context) -> RelationLabelNSTextField {
        let field = RelationLabelNSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.placeholderString = "Search or name a relation"
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier(relationLabelFieldAccessibilityIdentifier)
        field.setAccessibilityLabel("Search or name a relation")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: RelationLabelNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.isEnabled = isEnabled

        guard focusRequest.target == .relationLabelPromptField,
              context.coordinator.appliedFocusSequence != focusRequest.sequence
        else {
            return
        }
        context.coordinator.appliedFocusSequence = focusRequest.sequence
        field.requestFirstResponder()
        DispatchQueue.main.async { [weak field] in
            guard let field, !field.holdsFirstResponder else { return }
            field.requestFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RelationLabelField
        var appliedFocusSequence: UInt64?

        init(parent: RelationLabelField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.focusDidChange(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.focusDidChange(false)
        }
    }
}
