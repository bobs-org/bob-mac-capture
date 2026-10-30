import Foundation

/// Shared task-type preview copy for Bob Mac Capture. Bob owns the rule;
/// Swift only renders the additive `task_theme` change Bob reports using the
/// D10 phrases.
public enum CaptureTaskThemePresentation {
    /// The inherited half of the task-type line, mirroring
    /// `format_task_theme_row` in `src/native/capture/output.rs`:
    /// `this task suggests X`, `reading tasks suggest X`,
    /// `<stem> suggests X`, `default type suggests X`, else `no default here`.
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
        case "default":
            return "default type suggests \(shown.theme.name)"
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

    /// One optional task-type preview line, e.g.
    /// `type → FIX · sase_blog suggests WRITE` or
    /// `type cleared · sase_blog suggests WRITE`. Dry runs read as
    /// `would set type …` / `would clear type …`, mirroring Bob's human output.
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
                return "would set type → \(theme.name) · \(inherited)"
            }
            return "type → \(theme.name) · \(inherited)"
        case "cleared":
            if isDryRun {
                return "would clear type · \(inherited)"
            }
            return "type cleared · \(inherited)"
        case "kept":
            guard let theme = change.theme else {
                return nil
            }
            let label = keptSourceLabel(for: change)
            if isDryRun {
                return "would keep type \(theme.name) · \(label)"
            }
            return "type \(theme.name) · \(label)"
        default:
            return nil
        }
    }

    /// Short source label for a `kept` change: `this task`, `from <stem>`,
    /// `default type`, `reading task`, or `no default here`.
    public static func keptSourceLabel(for change: CaptureTaskThemeChange) -> String {
        if let previous = change.previous, let theme = change.theme, previous.key == theme.key {
            return "this task"
        }
        guard let suggestion = change.inherited else {
            return "no default here"
        }
        switch suggestion.source {
        case "task":
            return "this task"
        case "reading":
            return "reading task"
        case "default":
            return "default type"
        case "note":
            return suggestion.label.isEmpty ? "from note" : suggestion.label
        default:
            return suggestion.label.isEmpty ? "no default here" : suggestion.label
        }
    }

    /// Ledger relocation copy from Bob's `type_relocation` outcome. Unknown
    /// outcomes return nil so rendering stays on the type line.
    public static func relocationLine(for relocation: CaptureTypeRelocation?) -> String? {
        guard let relocation, !relocation.to.isEmpty else {
            return nil
        }
        let from = relocation.from.flatMap { $0.isEmpty ? nil : $0 } ?? "entry"
        switch relocation.outcome {
        case "rename_entry":
            return "\(from) → \(relocation.to) · running entry renamed"
        case "append_component":
            return "\(from) → \(relocation.to) · running entry shared"
        case "move_to":
            return "moved under \(relocation.to)"
        case "rename_placeholder":
            return "\(from) → \(relocation.to) · planned entry renamed"
        case "create_below":
            return "moved under new \(relocation.to)"
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
