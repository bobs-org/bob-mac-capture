import AppKit
import SwiftUI

/// Lets `CapturePanelController` find this field in the window's view tree without a
/// reference back into SwiftUI.
let pickerFilterFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.picker-filter"
let pullInFilterFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.pull-in-filter"
let inboxRouteFilterFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.inbox-route-filter"

@available(macOS 26.0, *)
final class CapturePickerFilterNSTextField: NSTextField {
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
            CaptureSignpost.event("picker-filter-focus-claimed")
        } else {
            CaptureSignpost.event("picker-filter-focus-claim-failed")
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
struct CapturePickerFilterField: NSViewRepresentable {
    var text: String
    var placeholder: String
    var accessibilityLabel: String
    let focusRequest: CapturePanelFocusRequest
    let onTextChange: (String) -> Void
    var fieldIdentifier = pickerFilterFieldAccessibilityIdentifier
    var focusTarget: CapturePanelFocusTarget = .pickerFilter
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> CapturePickerFilterNSTextField {
        let field = CapturePickerFilterNSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: 15)
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier(fieldIdentifier)
        field.setAccessibilityLabel(accessibilityLabel)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: CapturePickerFilterNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
        field.setAccessibilityLabel(accessibilityLabel)

        guard focusRequest.target == focusTarget,
              context.coordinator.appliedFocusSequence != focusRequest.sequence
        else {
            if focusRequest.target != focusTarget, field.holdsFirstResponder {
                _ = field.window?.makeFirstResponder(nil)
            }
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
        var parent: CapturePickerFilterField
        var appliedFocusSequence: UInt64?

        init(parent: CapturePickerFilterField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            parent.onTextChange(field.stringValue)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
            // Automatic text substitutions must not change filter input.
            if let editor = (notification.object as? NSTextField)?.currentEditor() as? NSTextView {
                editor.isAutomaticDashSubstitutionEnabled = false
                editor.isAutomaticQuoteSubstitutionEnabled = false
                editor.isAutomaticTextReplacementEnabled = false
                editor.isContinuousSpellCheckingEnabled = false
                editor.isAutomaticSpellingCorrectionEnabled = false
                let end = (editor.string as NSString).length
                editor.selectedRange = NSRange(location: end, length: 0)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }
    }
}
