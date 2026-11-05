import CaptureCore
import SwiftUI

/// Batch-level section target for a transfer merge. The card shows Bob's
/// exact section diff, with the heading emphasized and a created capsule
/// when the merge appended the section.
struct SectionBlockView: View {
    let presentation: CaptureSectionBlockPresentation
    let onExpandFold: () -> Void

    @State private var expandedFolds: Set<Int> = []

    init(
        block: CaptureSectionBlock,
        dryRun: Bool,
        onExpandFold: @escaping () -> Void = {}
    ) {
        presentation = CaptureSectionBlockPresentation(block: block, dryRun: dryRun)
        self.onExpandFold = onExpandFold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            captionRow
            BlockDiffCard(
                railTint: .purple,
                items: presentation.items(expandedFolds: expandedFolds),
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
            Image(systemName: "text.alignleft")
                .foregroundStyle(.purple)
                .accessibilityHidden(true)
            Text(presentation.captionText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
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
