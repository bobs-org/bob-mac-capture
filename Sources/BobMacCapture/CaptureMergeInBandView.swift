import CaptureCore
import SwiftUI

/// Complete merge-in band inside the new-task card. Every sentence comes
/// from Bob's `merges[]`; Swift only arranges rows, disclosure, and the
/// existing Pull-In content. Similar-tasks rendering stays untouched below.
@available(macOS 26.0, *)
struct CaptureMergeInBandView: View {
    let presentation: CaptureMergeInPresentation
    let offerContent: AnyView?
    @State private var expanded = false

    private var tint: Color { .purple }

    private var visibleRows: [CaptureMergeInPresentation.SourceRow] {
        guard !expanded, presentation.sourceRows.count > 3 else {
            return presentation.sourceRows
        }
        return Array(presentation.sourceRows.prefix(3))
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint)
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                header
                ForEach(Array(visibleRows.enumerated()), id: \.offset) { _, row in
                    sourceRow(row)
                }
                if !expanded, let label = presentation.disclosureLabel {
                    Button(label) { expanded = true }
                        .buttonStyle(.link)
                        .font(.caption)
                        .accessibilityHint("Shows all \(presentation.count) merged tasks")
                }
                ForEach(Array(presentation.consequences.enumerated()), id: \.offset) {
                    _, row in
                    consequenceRow(row)
                }
                if let offerContent {
                    offerContent
                        .padding(.top, 2)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.previewAccessibilitySummary)
        .transaction { $0.animation = nil }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.merge")
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(presentation.headerText)
                .font(.callout.weight(.semibold))
            Spacer(minLength: 0)
        }
    }

    private func sourceRow(_ row: CaptureMergeInPresentation.SourceRow) -> some View {
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
            }
            HStack(spacing: 6) {
                if let detailText = row.detailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Spacer(minLength: 0)
                if !row.locator.isEmpty {
                    Text(row.locator)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.leading, 20)
        }
    }

    private func consequenceRow(_ row: CaptureMergeInPresentation.ConsequenceRow) -> some View {
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

/// Calm pending card for a merge-in whose sources are still being typed.
/// A source-less draft never flashes red; source errors stay visible inline.
@available(macOS 26.0, *)
struct CaptureMergeInPendingCardView: View {
    let presentation: CaptureMergeInPendingPresentation

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.secondary.opacity(0.65))
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(CaptureMergeInPendingPresentation.prompt)
                    .font(.callout.weight(.semibold))
                ForEach(Array(presentation.sourceRows.enumerated()), id: \.offset) { _, row in
                    if let message = row.errorMessage {
                        Text(message.text)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let title = row.title {
                        HStack(spacing: 6) {
                            Text(title.text)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            Spacer(minLength: 0)
                            if !row.locator.isEmpty {
                                Text(row.locator)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        if let mergeable = row.mergeableMessage, !mergeable.isEmpty {
                            Text(mergeable)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 0)
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 10)
            .padding(.trailing, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilitySummary)
        .transaction { $0.animation = nil }
    }
}

/// Refusal card for a merge-in the dry run rejected. Shows Bob's message and
/// one button per available explicit rewrite; Return never rewrites.
@available(macOS 26.0, *)
struct CaptureMergeInRefusalCardView: View {
    let presentation: CaptureMergeInRefusalPresentation
    let onApplyRewrite: (CaptureDiagnosticRewrite) -> Void

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.red.opacity(0.8))
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(presentation.message.text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                ForEach(Array(presentation.rewrites.enumerated()), id: \.offset) { _, rewrite in
                    Button(rewrite.label) { onApplyRewrite(rewrite) }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 10)
            .padding(.trailing, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.red.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilitySummary)
        .transaction { $0.animation = nil }
    }
}
