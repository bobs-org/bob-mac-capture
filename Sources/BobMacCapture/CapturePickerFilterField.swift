import AppKit
import SwiftUI

/// Lets `CapturePanelController` find this field in the window's view tree without a
/// reference back into SwiftUI.
let pickerFilterFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.picker-filter"

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
        field.setAccessibilityIdentifier(pickerFilterFieldAccessibilityIdentifier)
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

        guard focusRequest.target == .pickerFilter,
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
            // The picker filter only ever holds ID characters, so automatic
            // dash, quote, and text replacement plus spelling correction are
            // disabled: `--` must never become an em dash.
            if let editor = (notification.object as? NSTextField)?.currentEditor() as? NSTextView {
                editor.isAutomaticDashSubstitutionEnabled = false
                editor.isAutomaticQuoteSubstitutionEnabled = false
                editor.isAutomaticTextReplacementEnabled = false
                editor.isContinuousSpellCheckingEnabled = false
                editor.isAutomaticSpellingCorrectionEnabled = false
            }
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
