import Foundation

/// One local typing snippet: a trigger sequence typed immediately before the caret, and
/// the replacement text that should take its place.
struct CaptureSnippet: Equatable {
    let trigger: String
    let replacement: String
}

/// The single source of supported capture-editor snippets. Adding an entry here is
/// enough to make it available to `CaptureSnippetResolver`.
enum CaptureSnippetCatalog {
    static let all: [CaptureSnippet] = [
        CaptureSnippet(trigger: "--", replacement: "\u{2014}")
    ]
}

/// A deterministic single-point source edit that replaces a caret-adjacent snippet
/// trigger with its replacement text, plus the resulting collapsed caret position.
struct CaptureSnippetEdit: Equatable {
    let replacementRange: NSRange
    let replacementText: String
    let resultingSelection: NSRange
}

/// Resolves a caret-adjacent snippet trigger to a deterministic edit. Pure and
/// side-effect free: callers are responsible for applying the returned edit.
enum CaptureSnippetResolver {
    /// Requires a collapsed caret and inspects only the characters immediately
    /// preceding it. Returns `nil` without inspecting anything else whenever the
    /// selection is non-collapsed, out of bounds, or no catalog trigger immediately
    /// precedes the caret.
    nonisolated static func resolve(
        in text: NSString,
        selectedRange: NSRange
    ) -> CaptureSnippetEdit? {
        guard selectedRange.length == 0,
              selectedRange.location >= 0,
              selectedRange.location <= text.length
        else {
            return nil
        }

        for snippet in CaptureSnippetCatalog.all {
            let triggerLength = (snippet.trigger as NSString).length
            guard selectedRange.location >= triggerLength else {
                continue
            }

            let triggerRange = NSRange(
                location: selectedRange.location - triggerLength,
                length: triggerLength
            )
            guard text.substring(with: triggerRange) == snippet.trigger else {
                continue
            }

            let replacementLength = (snippet.replacement as NSString).length
            return CaptureSnippetEdit(
                replacementRange: triggerRange,
                replacementText: snippet.replacement,
                resultingSelection: NSRange(
                    location: triggerRange.location + replacementLength,
                    length: 0
                )
            )
        }

        return nil
    }
}
