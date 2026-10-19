import RefsCore
import SwiftUI

/// Shared quote-text builder for the inspector and the Copy card
/// picker: paired `**` runs render as bold instead of raw markup,
/// so both views agree. Payloads, tooltips, and the clipboard keep
/// the raw `**` Markdown.
@available(macOS 26.0, *)
enum RefsQuoteText {
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        for run in RefsQuoteEmphasis.runs(text) {
            var part = AttributedString(run.text)
            if run.isStrong {
                part.inlinePresentationIntent = .stronglyEmphasized
            }
            result += part
        }
        return result
    }
}
