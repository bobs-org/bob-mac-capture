import CaptureCore
import SwiftUI

/// One designed transfer preview. Every sentence and task fact comes from
/// Bob's response; this view only styles and arranges those values.
@available(macOS 26.0, *)
struct CaptureTransferCardView: View {
    let presentation: CaptureTransferPresentation
    let planBudget: CapturePlanBudget?
    let offerContent: AnyView?

    private var tint: Color {
        presentation.verb == .merge ? .purple : .accentColor
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint)
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                header
                if presentation.state == .alreadyMerged {
                    Text("Nothing to write")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(presentation.sourceRows.enumerated()), id: \.offset) { _, row in
                        sourceRow(row)
                    }
                    destinationConnector
                    destinationRow
                    ForEach(Array(presentation.consequences.enumerated()), id: \.offset) { _, row in
                        consequenceRow(row)
                    }
                    if let repairText = presentation.repairText {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(repairText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let planBudget {
                        HStack(spacing: 6) {
                            Image(systemName: "sun.max")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            TodayBadge(
                                presentation: TodayBadgePresentation(
                                    count: planBudget.links.count,
                                    cap: planBudget.links.cap
                                )
                            )
                        }
                    }
                    if let offerContent {
                        offerContent
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 10)
            .padding(.trailing, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        }
        .opacity(presentation.state == .alreadyMerged ? 0.62 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.previewAccessibilitySummary)
        .transaction { $0.animation = nil }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: presentation.verb.glyph)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(presentation.state == .alreadyMerged
                ? (presentation.alreadyMergedText ?? "Already merged")
                : "\(presentation.verb.actionText) \(presentation.sourceRows.count) "
                    + "task\(presentation.sourceRows.count == 1 ? "" : "s")")
                .font(.callout.weight(.semibold))
            Spacer(minLength: 0)
        }
    }

    private func sourceRow(_ row: CaptureTransferPresentation.SourceRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                statusGlyph(row.status)
                Text(CapturePickerRichText.displayText(
                    row.title.text,
                    segments: row.title.segments,
                    matches: []
                ))
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                statusTransition(
                    from: row.status,
                    fromName: row.statusName,
                    to: row.targetStatus,
                    toName: row.targetStatusName
                )
                Spacer(minLength: 0)
                if !row.locator.isEmpty {
                    Text(row.locator)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(0)
                }
            }
            if let detailText = row.detailText {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(row.detailIsRename ? .orange : .secondary)
                    .padding(.leading, 20)
            }
        }
    }

    private var destinationConnector: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(tint.opacity(0.25))
                .frame(width: 1, height: 12)
                .padding(.leading, 9)
            Text("↓ into")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }

    private var destinationRow: some View {
        HStack(spacing: 6) {
            statusGlyph(presentation.destination.status)
            Text(CapturePickerRichText.displayText(
                presentation.destination.title.text,
                segments: presentation.destination.title.segments,
                matches: []
            ))
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(1)
            if let status = presentation.destination.status,
               let statusName = presentation.destination.statusName
            {
                statusChip(statusName, status: status)
            }
            if let container = presentation.destination.containerLabel {
                Text(container)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 0.8))
                    .foregroundStyle(tint)
            }
            if presentation.destination.isNew {
                Text("new")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        Capsule().strokeBorder(
                            tint.opacity(0.7),
                            style: StrokeStyle(lineWidth: 0.8, dash: [3, 2])
                        )
                    )
            }
            Spacer(minLength: 0)
            if !presentation.destination.locator.isEmpty {
                Text(presentation.destination.locator)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func consequenceRow(
        _ row: CaptureTransferPresentation.ConsequenceRow
    ) -> some View {
        let color: Color = row.tone == "warning" ? .orange : .secondary
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: row.symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(CapturePickerRichText.displayText(
                row.text,
                segments: TaskDisplayText(parsing: row.text).segments,
                matches: []
            ))
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 20)
    }

    private func statusGlyph(_ status: CapturePickerTaskStatus?) -> some View {
        let style = status.map(CaptureEditorPalette.taskStatus)
            ?? (symbol: "circle.dashed", color: Color.secondary)
        return Image(systemName: style.symbol)
            .foregroundStyle(style.color)
            .frame(width: 14)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func statusTransition(
        from sourceStatus: CapturePickerTaskStatus?,
        fromName source: String?,
        to targetStatus: CapturePickerTaskStatus?,
        toName target: String?
    ) -> some View {
        if let source, !source.isEmpty, let target, !target.isEmpty,
           let sourceStatus, let targetStatus,
           !(source == target && sourceStatus == targetStatus)
        {
            HStack(spacing: 3) {
                statusChip(source, status: sourceStatus)
                Text("→")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                statusChip(target, status: targetStatus)
            }
            .fixedSize()
            .layoutPriority(2)
            .accessibilityLabel("\(source) to \(target)")
        }
    }

    private func statusChip(_ title: String, status: CapturePickerTaskStatus) -> some View {
        let color = CaptureEditorPalette.taskStatus(status).color
        return Text(title)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.11), in: Capsule())
            .foregroundStyle(color)
    }
}
