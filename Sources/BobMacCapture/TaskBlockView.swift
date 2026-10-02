import CaptureCore
import SwiftUI

/// One batch-level parent-task block in the preview pane: a picker-status
/// caption row above the shared diff card. Every line is the exact bytes Bob
/// will write, in the after-state — tinting never adds, drops, or reorders
/// characters — and rows wrap instead of truncating. Long quiet runs fold
/// into one expandable row; expansions reset when the card's identity
/// changes. No animation; the pane updates on every keystroke.
struct TaskBlockView: View {
    let presentation: CaptureTaskBlockPresentation
    /// Focus intent back to the editor after a fold expands, owned by the
    /// caller (the preview pane's model).
    let onExpandFold: () -> Void

    @State private var expandedFolds: Set<Int> = []
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        block: CaptureTaskBlock,
        dryRun: Bool,
        onExpandFold: @escaping () -> Void = {}
    ) {
        presentation = CaptureTaskBlockPresentation(block: block, dryRun: dryRun)
        self.onExpandFold = onExpandFold
    }

    init(
        presentation: CaptureTaskBlockPresentation,
        onExpandFold: @escaping () -> Void = {}
    ) {
        self.presentation = presentation
        self.onExpandFold = onExpandFold
    }

    private var statusTint: Color {
        CaptureEditorPalette.taskStatus(presentation.status).color
    }

    private var statusSymbolName: String {
        CaptureEditorPalette.taskStatus(presentation.status).symbol
    }

    private var items: [CaptureTaskBlockPresentation.Item] {
        presentation.items(expandedFolds: expandedFolds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            captionRow
            BlockDiffCard(
                railTint: statusTint,
                items: items,
                headlineEmphasis: true,
                onExpandFold: { id in
                    expandedFolds.insert(id)
                    onExpandFold()
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilitySummary)
        .accessibilityAction(named: "Show all lines") {
            expandedFolds = Set(
                presentation.items(expandedFolds: []).compactMap { item in
                    if case .fold(let fold) = item {
                        return fold.id
                    }
                    return nil
                }
            )
        }
        .onChange(of: presentation.identity) { _, _ in
            expandedFolds = []
        }
    }

    private var captionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: statusSymbolName)
                .foregroundStyle(statusTint)
                .accessibilityHidden(true)
            Text(presentation.captionText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            // A created parent carries the Pomodoro view's pink New/Created
            // capsule so the fresh task reads at a glance.
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
