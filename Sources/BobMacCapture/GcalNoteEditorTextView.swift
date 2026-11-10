import AppKit
import CaptureCore
import SwiftUI

/// Lets hosted tests and the panel controller find the event-note editor
/// without confusing it for the covered capture `NSTextView`.
let gcalNoteEditorAccessibilityIdentifier = "org.bobs.bob-mac-capture.gcal-note-editor"

@available(macOS 26.0, *)
final class GcalNoteNSTextView: NSTextView {
    let noteUndoManager = UndoManager()
    var onTextChange: ((String) -> Void)?
    private var wantsFirstResponder = false

    func requestFirstResponder() {
        wantsFirstResponder = true
        claimFirstResponderIfPending()
    }

    func claimFirstResponderIfPending() {
        guard wantsFirstResponder, let window else {
            return
        }
        wantsFirstResponder = false
        _ = window.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        claimFirstResponderIfPending()
    }

    override var undoManager: UndoManager? {
        noteUndoManager
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }
}

@available(macOS 26.0, *)
struct GcalNoteEditorTextView: NSViewRepresentable {
    var text: String
    var isEditable: Bool
    var matchingSpans: [GcalNoteSpan]
    var matchingErrors: [GcalNoteIssue]
    var rootHue: String?
    var identityKey: String
    var onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let textView = GcalNoteNSTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.monospacedSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.identifier = NSUserInterfaceItemIdentifier(
            gcalNoteEditorAccessibilityIdentifier
        )
        textView.setAccessibilityIdentifier(gcalNoteEditorAccessibilityIdentifier)
        textView.setAccessibilityLabel("Private event note")
        textView.delegate = context.coordinator
        textView.onTextChange = onTextChange
        scroll.documentView = textView
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? GcalNoteNSTextView else {
            return
        }
        context.coordinator.parent = self
        textView.onTextChange = onTextChange
        textView.isEditable = isEditable
        if context.coordinator.identityKey != identityKey {
            context.coordinator.identityKey = identityKey
            context.coordinator.shouldFocus = true
            textView.noteUndoManager.removeAllActions()
        }
        if textView.string != text, !textView.hasMarkedText() {
            context.coordinator.applyingProgrammaticText = true
            defer { context.coordinator.applyingProgrammaticText = false }
            replaceText(textView, with: text)
        }
        if !textView.hasMarkedText() {
            GcalNoteHighlightPainter.paint(
                in: textView,
                text: textView.string,
                spans: matchingSpans,
                errors: matchingErrors,
                rootHue: rootHue
            )
        }
        if isEditable, context.coordinator.shouldFocus {
            context.coordinator.shouldFocus = false
            textView.requestFirstResponder()
        }
    }

    private func replaceText(_ textView: GcalNoteNSTextView, with text: String) {
        guard let storage = textView.textStorage else {
            textView.string = text
            return
        }
        textView.noteUndoManager.disableUndoRegistration()
        storage.beginEditing()
        storage.replaceCharacters(
            in: NSRange(location: 0, length: storage.length),
            with: text
        )
        storage.endEditing()
        textView.noteUndoManager.enableUndoRegistration()
        let end = (text as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
    }

    @available(macOS 26.0, *)
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GcalNoteEditorTextView?
        var identityKey = ""
        var shouldFocus = true
        var applyingProgrammaticText = false
        weak var textView: GcalNoteNSTextView?

        func textDidChange(_ notification: Notification) {
            guard !applyingProgrammaticText else { return }
            guard let textView = notification.object as? NSTextView else {
                return
            }
            parent?.onTextChange(textView.string)
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            (view as? GcalNoteNSTextView)?.noteUndoManager
        }
    }
}

@available(macOS 26.0, *)
enum GcalNoteHighlightPainter {
    static func paint(
        in textView: NSTextView,
        text: String,
        spans: [GcalNoteSpan],
        errors: [GcalNoteIssue],
        rootHue: String?
    ) {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        let undo = textView.undoManager
        undo?.disableUndoRegistration()
        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: full)
        storage.removeAttribute(.underlineStyle, range: full)
        storage.removeAttribute(.underlineColor, range: full)
        storage.removeAttribute(.toolTip, range: full)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)

        let validated = GcalNoteSpanAdapter.validatedRanges(in: text, spans: spans)
        for item in validated {
            guard
                let range = utf16Range(
                    in: text,
                    start: item.span.start,
                    end: item.span.end
                )
            else {
                continue
            }
            let role = GcalNotePresentation.highlightRole(forKind: item.span.kind)
            if let color = color(for: role, rootHue: rootHue) {
                storage.addAttribute(.foregroundColor, value: color, range: range)
            }
        }

        let issues = GcalNoteSpanAdapter.validatedIssueRanges(in: text, errors: errors)
        for item in issues {
            guard
                let range = utf16Range(
                    in: text,
                    start: item.span.span.start,
                    end: item.span.span.end
                )
            else {
                continue
            }
            storage.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: range
            )
            storage.addAttribute(.underlineColor, value: NSColor.systemRed, range: range)
            if let message = item.issue.message, !message.isEmpty {
                storage.addAttribute(.toolTip, value: message, range: range)
            }
        }
        storage.endEditing()
        undo?.enableUndoRegistration()
    }

    static func color(for role: GcalNoteHighlightRole, rootHue: String?) -> NSColor? {
        switch role {
        case .route:
            return .controlAccentColor
        case .root:
            return hueColor(rootHue) ?? .controlAccentColor
        case .clock:
            return .systemTeal
        case .buffer:
            return .systemOrange
        case .reasonSign:
            return .systemOrange
        case .reason:
            return .secondaryLabelColor
        case .prose:
            return .labelColor
        case .unknown:
            return nil
        }
    }

    private static func hueColor(_ raw: String?) -> NSColor? {
        let hue: PomodoroHomeHue?
        switch raw {
        case "blue": hue = .blue
        case "orange": hue = .orange
        case "aqua": hue = .aqua
        case "yellow": hue = .yellow
        case "magenta": hue = .magenta
        case "green": hue = .green
        case "violet": hue = .violet
        case "red": hue = .red
        default: hue = nil
        }
        let scheme: ColorScheme =
            NSApp.effectiveAppearance.bestMatch(
                from: [.darkAqua, .aqua]
            ) == .darkAqua ? .dark : .light
        return NSColor(PomodoroHomeColor.color(for: hue, scheme: scheme))
    }
}
