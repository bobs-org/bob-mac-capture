import AppKit
import SwiftUI

/// Lets `CapturePanelController` find this field in the window's view tree without a
/// reference back into SwiftUI.
let activeTaskFilterFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.active-task-filter"

@available(macOS 26.0, *)
final class ActiveTaskFilterNSTextField: NSTextField {
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
            CaptureSignpost.event("active-task-filter-focus-claimed")
        } else {
            CaptureSignpost.event("active-task-filter-focus-claim-failed")
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
struct ActiveTaskFilterField: NSViewRepresentable {
    var text: String
    let focusRequest: CapturePanelFocusRequest
    let onTextChange: (String) -> Void

    func makeNSView(context: Context) -> ActiveTaskFilterNSTextField {
        let field = ActiveTaskFilterNSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.placeholderString = "Filter by task, note, ^id, or Pomodoro"
        field.font = NSFont.systemFont(ofSize: 15)
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier(activeTaskFilterFieldAccessibilityIdentifier)
        field.setAccessibilityLabel("Filter active tasks")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: ActiveTaskFilterNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }

        guard focusRequest.target == .activeTaskFilter,
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
        var parent: ActiveTaskFilterField
        var appliedFocusSequence: UInt64?

        init(parent: ActiveTaskFilterField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            parent.onTextChange(field.stringValue)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            // The filter is seeded from the draft at open; land the caret at
            // the end so typing appends to the seed.
            guard let editor = (notification.object as? NSTextField)?.currentEditor() else {
                return
            }
            let end = (editor.string as NSString).length
            editor.selectedRange = NSRange(location: end, length: 0)
        }
    }
}
