import AppKit
import SwiftUI

/// Lets `CapturePanelController` find this field in the window's view tree without a
/// reference back into SwiftUI.
let pickerFilterFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.picker-filter"
let moveChoiceFilterFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.move-choice-filter"
let pullInFilterFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.pull-in-filter"
let pullInReasonFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.pull-in-reason"
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
    var fontSize: CGFloat = 15
    var onFocusChange: (Bool) -> Void = { _ in }
    /// Caret-aware text change: when set, the coordinator calls this with
    /// the post-edit caret (UTF-16, nil for a ranged selection) instead of
    /// `onTextChange`.
    var onTextChangeWithCaret: ((String, Int?) -> Void)? = nil
    /// Raw selection change (location, length) from the field editor, for
    /// caret-only moves that never send a text change. Observed only while
    /// the field is editing.
    var onSelectionChange: ((Int, Int) -> Void)? = nil

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
        field.font = NSFont.systemFont(ofSize: fontSize)
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
        var selectionObserver: Any?

        init(parent: CapturePickerFilterField) {
            self.parent = parent
        }

        deinit {
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            let text = field.stringValue
            if let onTextChangeWithCaret = parent.onTextChangeWithCaret {
                onTextChangeWithCaret(text, Self.caret(of: field))
            } else {
                parent.onTextChange(text)
            }
        }

        /// Post-edit caret (UTF-16), or nil for a ranged selection or a
        /// missing editor.
        private static func caret(of field: NSTextField) -> Int? {
            guard let editor = field.currentEditor() as? NSTextView else {
                return nil
            }
            let selection = editor.selectedRange
            guard selection.length == 0 else { return nil }
            return selection.location
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
                observeSelectionChanges(of: editor)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            stopObservingSelectionChanges()
            parent.onFocusChange(false)
        }

        /// Caret-only moves (arrows, clicks) never send a text change, so
        /// the LINK band tracks them through the field editor's selection
        /// notification, bound to the edit session.
        private func observeSelectionChanges(of editor: NSTextView) {
            guard parent.onSelectionChange != nil, selectionObserver == nil else {
                return
            }
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: editor,
                queue: .main
            ) { [weak self] _ in
                guard let self,
                    let onSelectionChange = self.parent.onSelectionChange
                else {
                    return
                }
                let selection = editor.selectedRange
                onSelectionChange(selection.location, selection.length)
            }
        }

        private func stopObservingSelectionChanges() {
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
                self.selectionObserver = nil
            }
        }
    }
}
