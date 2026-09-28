import AppKit

/// Centralizes the capture draft editor's AppKit text-substitution policy so
/// `--3` / `-2` operator drafts can never be rewritten by macOS smart-dash
/// substitution. Disables only automatic dash substitution on the draft's
/// backing `NSTextView`; automatic quote substitution and the app's own
/// Tab `--` → `—` snippet are intentionally untouched.
enum CaptureEditorTextConfiguration {
    /// Disables smart dashes on one text view, preserving every other
    /// substitution setting (notably smart quotes).
    static func configure(_ textView: NSTextView) {
        textView.isAutomaticDashSubstitutionEnabled = false
    }

    /// Walks a view hierarchy and disables smart dashes on every editable
    /// `NSTextView` it finds. The capture panel's SwiftUI `TextEditor` owns
    /// its backing view, so callers pass the panel's `contentView` after
    /// layout and let this find the editor without holding a direct outlet.
    static func configureEditorTextViews(in view: NSView?) {
        guard let view else {
            return
        }
        if let textView = view as? NSTextView, textView.isEditable {
            configure(textView)
        }
        for subview in view.subviews {
            configureEditorTextViews(in: subview)
        }
    }
}
