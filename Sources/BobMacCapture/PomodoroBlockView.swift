import CaptureCore
import SwiftUI

/// One batch-level Pomodoro block in the preview pane: a status caption row
/// above the shared diff card. Every line is exactly what Bob will write —
/// tinting never adds, drops, or reorders characters — and rows wrap instead
/// of truncating. No animation; the pane updates on every keystroke.
struct PomodoroBlockView: View {
    let presentation: CapturePomodoroBlockPresentation

    init(block: CapturePomodoroBlock, dryRun: Bool) {
        presentation = CapturePomodoroBlockPresentation(block: block, dryRun: dryRun)
    }

    private var statusTint: Color {
        switch presentation.status {
        case .running:
            return CaptureEditorPalette.color(for: .pomodoroStart)
        case .completed:
            return .green
        case .queued, .other:
            return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            captionRow
            BlockDiffCard(
                railTint: statusTint,
                rows: presentation.rows,
                headlineEmphasis: false
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilitySummary)
    }

    private var captionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: presentation.statusSymbolName)
                .foregroundStyle(statusTint)
                .accessibilityHidden(true)
            Text(presentation.captionText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            // A created block carries the start card's pink New/Created
            // capsule so the fresh entry reads at a glance.
            if let badge = presentation.badgeText {
                Text(badge)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.pink.opacity(0.15), in: Capsule())
                    .accessibilityHidden(true)
            }
        }
    }
}
