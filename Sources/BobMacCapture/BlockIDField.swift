import AppKit
import SwiftUI

/// Lets `CapturePanelController` find this field in the window's view tree without a
/// reference back into SwiftUI.
let blockIDFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.block-id-field"

@available(macOS 26.0, *)
final class BlockIDNSTextField: NSTextField {
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
            CaptureSignpost.event("block-id-focus-claimed")
        } else {
            CaptureSignpost.event("block-id-focus-claim-failed")
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
struct BlockIDField: NSViewRepresentable {
    @Binding var text: String
    let isEnabled: Bool
    let focusRequest: CapturePanelFocusRequest
    let focusDidChange: (Bool) -> Void

    func makeNSView(context: Context) -> BlockIDNSTextField {
        let field = BlockIDNSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.placeholderString = "block-id"
        field.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier(blockIDFieldAccessibilityIdentifier)
        field.setAccessibilityLabel("Block ID")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: BlockIDNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.isEnabled = isEnabled

        guard focusRequest.target == .taskIDPromptBlockID,
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
        var parent: BlockIDField
        var appliedFocusSequence: UInt64?

        init(parent: BlockIDField) {
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
