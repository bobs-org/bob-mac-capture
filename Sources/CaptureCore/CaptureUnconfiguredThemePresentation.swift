import Foundation

/// Shared presentation for `theme_not_configured`: preview captions, Name-it
/// warnings, and the create-row badge. Bob owns membership and the message;
/// this type only filters and words what Bob already returned.
public enum CaptureUnconfiguredThemePresentation {
    public static let warningCode = "theme_not_configured"
    public static let createBadge = "Not in your types"
    public static let accessibilitySuffix = "not in your types"

    public static func structuredWarnings(
        in warnings: [CaptureWarning]
    ) -> [StructuredCaptureWarning] {
        warnings.compactMap { warning in
            guard case .structured(let structured) = warning,
                structured.code == warningCode
            else {
                return nil
            }
            return structured
        }
    }

    /// Warnings to show in a settled capture preview. A warning whose label
    /// is a prefix of a visible configured theme is held back while the caret
    /// sits at the end of that name, so typing `BUILD` never flickers.
    public static func visibleWarnings(
        from warnings: [CaptureWarning],
        draft: String,
        caretUTF8: Int?,
        themeSpans: [CapturePomodoroThemeRef],
        configuredNames: [String]
    ) -> [StructuredCaptureWarning] {
        structuredWarnings(in: warnings).filter { warning in
            let label = warning.label ?? ""
            guard !label.isEmpty else {
                return true
            }
            return !shouldSuppress(
                label: label,
                draft: draft,
                caretUTF8: caretUTF8,
                themeSpans: themeSpans,
                configuredNames: configuredNames
            )
        }
    }

    public static func shouldSuppress(
        label: String,
        draft: String,
        caretUTF8: Int?,
        themeSpans: [CapturePomodoroThemeRef],
        configuredNames: [String]
    ) -> Bool {
        guard
            caretIsAtEndOfName(
                label: label,
                draft: draft,
                caretUTF8: caretUTF8,
                themeSpans: themeSpans
            )
        else {
            return false
        }
        return isPrefixOfConfigured(name: label, configuredNames: configuredNames)
    }

    public static func isPrefixOfConfigured(
        name: String,
        configuredNames: [String]
    ) -> Bool {
        let needle = PomodoroThemeSwatches.normalizeThemeKey(name)
        guard !needle.isEmpty else {
            return false
        }
        return configuredNames.contains { candidate in
            PomodoroThemeSwatches.normalizeThemeKey(candidate).hasPrefix(needle)
        }
    }

    /// Name-it warnings from Bob's `configured_themes` catalog. Prefixes of a
    /// configured name stay quiet while typing, matching the preview rule.
    /// The copy mirrors Bob's unconfigured-type warning (D10); labels read
    /// the same here because the completion payload carries no inventory list.
    public static func nameItWarnings(
        authoredName: String,
        configuredThemes: [CaptureConfiguredTheme]
    ) -> [StructuredCaptureWarning] {
        guard !configuredThemes.isEmpty else {
            return []
        }
        let configuredNames = configuredThemes.flatMap { [$0.name, $0.key] }
        var seen = Set<String>()
        var warnings: [StructuredCaptureWarning] = []
        for component in nameComponents(authoredName) {
            let key = PomodoroThemeSwatches.normalizeThemeKey(component)
            guard seen.insert(key).inserted else {
                continue
            }
            if isPrefixOfConfigured(name: component, configuredNames: configuredNames) {
                continue
            }
            warnings.append(
                StructuredCaptureWarning(
                    code: warningCode,
                    label: component,
                    message: "\(component) isn't one of your types; tasks here keep their own types"
                )
            )
        }
        return warnings
    }

    /// Recent-type chips when `configured_themes` is present: visible
    /// configured rows, in config order.
    public static func nameItSuggestions(
        configuredThemes: [CaptureConfiguredTheme],
        list: [CapturePomodoroTheme]
    ) -> [CapturePomodoroTheme] {
        let byKey = Dictionary(
            list.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return configuredThemes.compactMap { entry in
            guard let row = byKey[entry.key], !row.hidden else {
                return nil
            }
            return row
        }
    }

    public static func spokenColor(for ref: CapturePomodoroThemeRef) -> String {
        spokenColor(
            name: ref.name,
            hue: ref.hue,
            hueSource: ref.hueSource,
            known: ref.known,
            configured: ref.configured
        )
    }

    public static func spokenColor(
        name: String,
        hue: PomodoroHomeHue?,
        hueSource: String?,
        known: Bool,
        configured: Bool?
    ) -> String {
        guard known else {
            return "\(name), unknown type"
        }
        if configured == false || hueSource == "unconfigured" {
            return "\(name), muted, \(accessibilitySuffix)"
        }
        if let hueName = hue?.slotName {
            return "\(name), \(hueName)"
        }
        if hueSource == "exempt" {
            return "\(name), muted"
        }
        return "\(name), no color"
    }

    public static func caretIsInName(
        start: Int,
        end: Int,
        caretUTF8: Int?
    ) -> Bool {
        guard let caret = caretUTF8 else {
            return false
        }
        return caret >= start && caret <= end
    }

    public static func nameComponents(_ name: String) -> [String] {
        name.split(separator: "+").map { part in
            String(part).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    private static func caretIsAtEndOfName(
        label: String,
        draft: String,
        caretUTF8: Int?,
        themeSpans: [CapturePomodoroThemeRef]
    ) -> Bool {
        guard let caret = caretUTF8 else {
            return false
        }
        let needle = PomodoroThemeSwatches.normalizeThemeKey(label)
        if themeSpans.contains(where: { ref in
            let matches =
                PomodoroThemeSwatches.normalizeThemeKey(ref.name) == needle
                || ref.key == needle
            return matches && ref.end == caret
        }) {
            return true
        }
        guard let range = utf8RangeOfComponent(label, in: draft, endingAt: caret) else {
            return false
        }
        return range.upperBound == caret
    }

    private static func utf8RangeOfComponent(
        _ label: String,
        in draft: String,
        endingAt caret: Int
    ) -> Range<Int>? {
        let bytes = Array(draft.utf8)
        let needle = Array(label.utf8)
        guard !needle.isEmpty, caret >= needle.count, caret <= bytes.count else {
            return nil
        }
        let start = caret - needle.count
        if bytes[start..<caret].elementsEqual(needle) {
            return start..<caret
        }
        return nil
    }
}
