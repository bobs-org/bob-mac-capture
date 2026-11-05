import CaptureCore
import SwiftUI

@available(macOS 26.0, *)
struct CaptureTransferPendingCardView: View {
    let presentation: CaptureTransferPendingPresentation

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.secondary.opacity(0.65))
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(presentation.title)
                    .font(.callout.weight(.semibold))
                ForEach(Array(presentation.sourceRows.enumerated()), id: \.offset) { _, row in
                    sourceRow(row)
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(presentation.forms.enumerated()), id: \.offset) { _, row in
                        formRow(row)
                    }
                }
                .padding(.top, 2)
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
        .accessibilityLabel("Transfer destination pending")
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private func sourceRow(_ row: CaptureTransferPendingPresentation.SourceRow) -> some View {
        if let message = row.errorMessage {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "xmark.octagon")
                    .foregroundStyle(.red)
                    .frame(width: 14)
                    .accessibilityHidden(true)
                Text(
                    CapturePickerRichText.displayText(
                        message.text,
                        segments: message.segments,
                        matches: []
                    )
                )
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            }
        } else if let title = row.title {
            HStack(spacing: 6) {
                statusGlyph(row.status)
                Text(
                    CapturePickerRichText.displayText(
                        title.text,
                        segments: title.segments,
                        matches: []
                    )
                )
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                if let status = row.status, let statusName = row.statusName {
                    statusChip(statusName, status: status)
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
        }
    }

    private func formRow(_ row: CaptureTransferPendingPresentation.FormRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            coloredForm(row)
                .font(.system(.caption, design: .monospaced))
                .fixedSize()
            Image(systemName: row.glyph)
                .font(.caption.weight(.semibold))
                .foregroundStyle(verbColor(row.verb))
                .accessibilityHidden(true)
            Text(row.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if row.active {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.10))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func coloredForm(_ row: CaptureTransferPendingPresentation.FormRow) -> Text {
        let characters = Array(row.form)
        guard !row.segments.isEmpty else {
            return Text(row.form)
        }
        var result = Text("")
        for segment in row.segments {
            let lower = max(0, segment.range.lowerBound)
            let upper = min(characters.count, segment.range.upperBound)
            guard lower < upper else { continue }
            result =
                result
                + Text(String(characters[lower..<upper]))
                .foregroundColor(formColor(segment.part))
        }
        return result
    }

    private func formColor(_ part: CaptureTransferPendingPresentation.FormPart) -> Color {
        switch part {
        case .route:
            CaptureEditorPalette.color(for: .route)
        case .blockID:
            CaptureEditorPalette.color(for: .blockID)
        case .section:
            CaptureEditorPalette.color(for: .section)
        case .plain:
            .secondary
        }
    }

    private func verbColor(_ verb: String) -> Color {
        verb == "merge" ? .purple : .accentColor
    }

    private func statusGlyph(_ status: CapturePickerTaskStatus?) -> some View {
        let style =
            status.map(CaptureEditorPalette.taskStatus)
            ?? (symbol: "circle.dashed", color: Color.secondary)
        return Image(systemName: style.symbol)
            .foregroundStyle(style.color)
            .frame(width: 14)
            .accessibilityHidden(true)
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

@available(macOS 26.0, *)
struct CaptureTransferRefusalCardView: View {
    let presentation: CaptureTransferRefusalPresentation

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.red.opacity(0.75))
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: presentation.verb.glyph)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(width: 26, height: 26)
                        .background(Color.red.opacity(0.10), in: Circle())
                        .accessibilityHidden(true)
                    Text(presentation.verb.title)
                        .font(.callout.weight(.semibold))
                }
                Text(
                    CapturePickerRichText.displayText(
                        presentation.message.text,
                        segments: presentation.message.segments,
                        matches: []
                    )
                )
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                if let code = presentation.code {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 10)
            .padding(.trailing, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.red.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.red.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilitySummary)
        .transaction { $0.animation = nil }
    }
}
