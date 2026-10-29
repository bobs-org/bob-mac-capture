import Foundation

/// Shared task-theme preview copy for Bob Mac Capture. Bob owns the rule;
/// Swift only renders the additive `task_theme` change Bob reports using the
/// PT12 shared-contract phrases.
public enum CaptureTaskThemePresentation {
    /// The inherited half of the task-theme line, mirroring
    /// `format_task_theme_row` in `src/native/capture/output.rs`:
    /// `this task suggests X`, `reading tasks suggest X`,
    /// `daily review suggests X`, `<stem> suggests X`, else `no default here`.
    public static func inheritedPhrase(_ suggestion: CaptureThemeSuggestion?) -> String {
        guard let suggestion else {
            return "no default here"
        }
        // `inherited` on a `set`/`cleared` change is the suggestion that was
        // shown; on a bare suggestion it is the suggestion itself. Unwrap one
        // box level: an explicit null decodes as nil and reads as no default.
        let shown = suggestion.inherited?.value ?? suggestion
        switch shown.source {
        case "task":
            return "this task suggests \(shown.theme.name)"
        case "reading":
            return "reading tasks suggest \(shown.theme.name)"
        case "review":
            return "daily review suggests \(shown.theme.name)"
        case "note":
            let stem: String = {
                if let from = shown.from, !from.stem.isEmpty {
                    return from.stem
                }
                let label = shown.label
                if label.hasPrefix("from "), !label.dropFirst(5).isEmpty {
                    return String(label.dropFirst(5))
                }
                return label.isEmpty ? "note" : label
            }()
            return "\(stem) suggests \(shown.theme.name)"
        default:
            return "no default here"
        }
    }

    /// One optional task-theme preview line, e.g.
    /// `task theme → FIX · sase_blog suggests WRITE` or
    /// `task theme cleared · sase_blog suggests WRITE`. Dry runs read as
    /// `would set …` / `would clear …`, mirroring Bob's human output.
    /// Returns nil for unknown actions or when Bob reported no change.
    public static func line(
        for change: CaptureTaskThemeChange?,
        isDryRun: Bool
    ) -> String? {
        guard let change else {
            return nil
        }
        let inherited = inheritedPhrase(change.inherited)
        switch change.action {
        case "set":
            guard let theme = change.theme else {
                return nil
            }
            if isDryRun {
                return "would set task theme → \(theme.name) · \(inherited)"
            }
            return "task theme → \(theme.name) · \(inherited)"
        case "cleared":
            if isDryRun {
                return "would clear task theme · \(inherited)"
            }
            return "task theme cleared · \(inherited)"
        default:
            return nil
        }
    }

    /// Accessible label for a suggested menu row, e.g.
    /// `Pomodoro WRITE, suggested, from sase_blog`.
    public static func suggestedAccessibilityLabel(
        themeName: String,
        label: String
    ) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Pomodoro \(themeName), suggested"
        }
        return "Pomodoro \(themeName), suggested, \(trimmed)"
    }

    /// Secondary text for a suggested `pomodoro_name` row, e.g.
    /// `Suggested · from sase_blog`. The `●` dot is inserted before the
    /// declaring stem so the view can tint it with `from.hue`.
    public static func suggestedSecondaryText(label: String?, themeName: String?) -> String? {
        guard let label, !label.isEmpty else {
            if let themeName, !themeName.isEmpty {
                return "Suggested · \(themeName)"
            }
            return "Suggested"
        }
        // Bob's label is already `from <stem>`, `reading task`, etc.
        // Insert the hue dot before the stem for note suggestions.
        if label.hasPrefix("from "), label.count > 5 {
            let stem = String(label.dropFirst(5))
            return "Suggested · from ● \(stem)"
        }
        return "Suggested · \(label)"
    }
}
