import AppKit
import CaptureCore
import SwiftUI

/// Editor tint for a known theme (PT6): the hue washed behind
/// normal-colored text — 16 % in light mode, 24 % in dark — while the
/// syntax color stays exactly as `CaptureEditorPalette` paints it.
/// Unknown and exempt themes return nil and stay neutral.
enum PomodoroThemeTint {
    static func background(for hue: PomodoroHomeHue?) -> Color? {
        guard let hue else {
            return nil
        }
        let base = PomodoroHomeColor.color(for: hue, scheme: currentScheme)
        return base.opacity(currentScheme == .dark ? 0.24 : 0.16)
    }

    private static var currentScheme: ColorScheme {
        guard let appearance = NSApp?.effectiveAppearance,
              appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        else {
            return .light
        }
        return .dark
    }
}

/// The shared 8 pt theme swatch (PT6): a rounded square in the theme's
/// light/dark hex before a name. Area homes keep their ● circle, so a
/// theme never looks like a home. Unknown names draw a neutral outline
/// and stay quiet while typing.
@available(macOS 26.0, *)
struct PomodoroThemeSwatchView: View {
    let hue: PomodoroHomeHue?
    let known: Bool
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if known, let hue {
                RoundedRectangle(cornerRadius: 2)
                    .fill(PomodoroHomeColor.color(for: hue, scheme: colorScheme))
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.secondary.opacity(0.72), lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A single-component theme pill (PT6): the theme's tint behind
/// normal-colored text. The tint is 16 % in light mode and 24 % in dark
/// mode, rising on hover; the hue is never the text color. An exempt
/// theme (known, no hue) renders muted. Unknown names render neutral.
@available(macOS 26.0, *)
struct PomodoroThemePillView: View {
    let name: String
    let swatch: CaptureThemeSwatch
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private var isExempt: Bool {
        swatch.known && swatch.hue == nil
    }

    private var tint: Color {
        if isExempt {
            return Color(nsColor: .quaternaryLabelColor)
        }
        guard let hue = swatch.hue else {
            return Color(nsColor: .quaternaryLabelColor)
        }
        let base = PomodoroHomeColor.color(for: hue, scheme: colorScheme)
        let resting = colorScheme == .dark ? 0.24 : 0.16
        return base.opacity(hovering ? min(resting + 0.08, 1) : resting)
    }

    private var spokenHue: String {
        if isExempt {
            return "muted"
        }
        return swatch.hue?.slotName ?? "no color"
    }

    var body: some View {
        Text(name)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(isExempt ? .secondary : .primary)
            .onHover { hovering = $0 }
            .help("\(name) · \(spokenHue)")
            .accessibilityLabel("\(name), \(spokenHue) theme")
    }
}

/// One pill per theme component of a Pomodoro name, with a neutral `+`
/// between them (PT6 composites). Renders nothing when `names` is empty.
@available(macOS 26.0, *)
struct PomodoroThemeNamePillsView: View {
    let names: [String]
    let swatches: [CaptureThemeSwatch]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                if index > 0 {
                    Text("+")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                PomodoroThemePillView(
                    name: name,
                    swatch: index < swatches.count
                        ? swatches[index]
                        : CaptureThemeSwatch(hue: nil, known: false)
                )
            }
        }
    }
}

/// The component display names for a pill row, split on `+` and trimmed.
/// Order matches `PomodoroThemeSwatches.swatches(forName:refs:)`.
enum PomodoroThemePillNames {
    static func components(of name: String?) -> [String] {
        guard let name else {
            return []
        }
        return name.split(separator: "+").map { part in
            String(part).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }
}

/// Theme pills for a preview Pomodoro name, resolved against the
/// capture's budget `added_theme_refs` (PT6). Renders nothing when the
/// name is blank or the capture carries no budget.
@available(macOS 26.0, *)
struct PomodoroPreviewThemePillsView: View {
    let name: String?
    let budget: CapturePlanBudget?

    var body: some View {
        let names = PomodoroThemePillNames.components(of: name)
        let swatches = CapturePlanBudgetPresentation.swatches(forName: name, budget: budget)
        if !names.isEmpty, !swatches.isEmpty {
            PomodoroThemeNamePillsView(names: names, swatches: swatches)
        }
    }
}
