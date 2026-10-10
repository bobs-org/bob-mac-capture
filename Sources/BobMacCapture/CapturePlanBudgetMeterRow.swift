import CaptureCore
import SwiftUI

/// The shared theme and Task Link capsules used by idle agendas and
/// proposed capture previews.
@available(macOS 26.0, *)
struct CapturePlanBudgetMeterRow: View {
    let budget: CapturePlanBudgetPresentation

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
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
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
