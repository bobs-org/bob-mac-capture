import AppKit
import CaptureCore
import SwiftUI

/// The shared TODAY badge used by idle agendas and
/// proposed capture previews.
@available(macOS 26.0, *)
struct CapturePlanBudgetMeterRow: View {
    let budget: CapturePlanBudgetPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                TodayBadge(presentation: budget.today)
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

}
