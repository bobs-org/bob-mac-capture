import AppKit
import CaptureCore
import SwiftUI

/// The shared theme and Task Link capsules used by idle agendas and
/// proposed capture previews.
@available(macOS 26.0, *)
struct CapturePlanBudgetMeterRow: View {
    let budget: CapturePlanBudgetPresentation
    @Environment(\.colorScheme) private var colorScheme

    /// Tint for the `+1 BOB` delta chip: the first added theme's hue
    /// washed to the PT6 pill strength, or neutral on an older Bob.
    private var deltaTint: Color {
        guard let hue = budget.deltaThemeSwatches.first(where: { $0.known })?.hue else {
            return Color(nsColor: .quaternaryLabelColor)
        }
        let base = PomodoroHomeColor.color(for: hue, scheme: colorScheme)
        return base.opacity(colorScheme == .dark ? 0.24 : 0.16)
    }

    private var deltaSpokenHue: String {
        guard let first = budget.deltaThemeSwatches.first(where: { $0.known }) else {
            return "no color"
        }
        return first.hue?.slotName ?? "muted"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                capsule(
                    budget.themesCapsuleText,
                    overCap: budget.themesOverCap
                )
                capsule(
                    budget.linksCapsuleText,
                    overCap: budget.linksOverCap
                )
                if let delta = budget.deltaChipText {
                    Text(delta)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(deltaTint, in: Capsule())
                        .foregroundStyle(.secondary)
                        .help("\(delta) · \(deltaSpokenHue)")
                        .accessibilityLabel("\(delta), \(deltaSpokenHue) theme")
                }
            }
            ForEach(Array(budget.warningTexts.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan budget: \(budget.accessibilitySummary)")
    }

    private func capsule(_ text: String, overCap: Bool) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                (overCap ? Color.red : Color.green).opacity(0.15),
                in: Capsule()
            )
            .foregroundStyle(overCap ? Color.red : Color.green)
    }
}
