import Foundation

/// Lexical gate for when the editor should ask bob about starting a template.
/// Like `isBareAtAtTrigger`, this helper does not implement capture grammar;
/// bob alone decides whether and how the draft is rewritten.
public enum CaptureTemplateStart {
    public static let rewriteRule = "start_template"

    /// True when typing `@` at the end of the exact first-line marker `@@`
    /// would produce the `@@@` template-start gesture.
    public static func isRewriteKeystroke(
        typed: String,
        text: String,
        selectedRange: NSRange
    ) -> Bool {
        typed == "@"
            && selectedRange.length == 0
            && selectedRange.location == 2
            && firstPhysicalLineIsBareAtAt(in: text)
    }

    /// True while the caret is immediately after a first physical line that is
    /// exactly `@@`, where another `@` would start a template.
    public static func hintApplies(draft: String, cursorUTF8Offset: Int?) -> Bool {
        cursorUTF8Offset == 2 && firstPhysicalLineIsBareAtAt(in: draft)
    }

    private static func firstPhysicalLineIsBareAtAt(in text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count >= 2, bytes[0] == 64, bytes[1] == 64 else {
            return false
        }
        guard bytes.count > 2 else {
            return true
        }
        if bytes[2] == 10 {
            return true
        }
        return bytes[2] == 13 && bytes.count > 3 && bytes[3] == 10
    }
}
