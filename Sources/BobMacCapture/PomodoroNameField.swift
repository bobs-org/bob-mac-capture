import AppKit
import SwiftUI

/// Lets `CapturePanelController` find this field in the window's view tree without a
/// reference back into SwiftUI.
let pomodoroNameFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.pomodoro-name-field"

@available(macOS 26.0, *)
final class PomodoroNameNSTextField: NSTextField {
    private var wantsFirstResponder = false

    /// Claims first responder now if the field is already in a window, and otherwise
    /// arms the claim so `viewDidMoveToWindow` performs it.
    func requestFirstResponder() {
        wantsFirstResponder = true
        claimFirstResponderIfPending()
    }

    func claimFirstResponderIfPending() {
        guard wantsFirstResponder, let window else {
            return
        }
        wantsFirstResponder = false
        if window.makeFirstResponder(self) {
            CaptureSignpost.event("pomodoro-name-focus-claimed")
        } else {
            CaptureSignpost.event("pomodoro-name-focus-claim-failed")
        }
    }

    /// True when this field or its field editor currently holds first responder.
    var holdsFirstResponder: Bool {
        guard let responder = window?.firstResponder else {
            return false
        }
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
struct PomodoroNameField: NSViewRepresentable {
    @Binding var text: String
    let isEnabled: Bool
    let focusRequest: CapturePanelFocusRequest
    let focusDidChange: (Bool) -> Void

    func makeNSView(context: Context) -> PomodoroNameNSTextField {
        let field = PomodoroNameNSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.placeholderString = "DEEP WORK"
        field.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier(pomodoroNameFieldAccessibilityIdentifier)
        field.setAccessibilityLabel("Pomodoro name")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: PomodoroNameNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.isEnabled = isEnabled

        guard focusRequest.target == .pomodoroNamePromptName,
              context.coordinator.appliedFocusSequence != focusRequest.sequence
        else {
            return
        }
        context.coordinator.appliedFocusSequence = focusRequest.sequence
        field.requestFirstResponder()
        DispatchQueue.main.async { [weak field] in
            guard let field, !field.holdsFirstResponder else {
                return
            }
            field.requestFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PomodoroNameField
        var appliedFocusSequence: UInt64?

        init(parent: PomodoroNameField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
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
