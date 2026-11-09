import AppKit
import CaptureCore
import SwiftUI

/// New-record preview for a committed-plan `note_files` entry paired with
/// its record item. Heading and property sheet come from Bob's metadata;
/// the exact Markdown rides a collapsed disclosure. Update items keep
/// their existing presentation; when record metadata is absent the caller
/// keeps the generic fallback.
@available(macOS 26.0, *)
struct RecordNotePreviewView: View {
    let item: CaptureCommandSuccess
    let file: CaptureNoteFile
    @State private var showsMarkdown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(item: CaptureCommandSuccess, file: CaptureNoteFile, expanded: Bool = false) {
        self.item = item
        self.file = file
        _showsMarkdown = State(initialValue: expanded)
    }

    private var summary: CaptureRecordNoteSummary? {
        item.recordNote
    }

    private var heading: String {
        if let summary {
            return CaptureRecordPreviewPresentation.headline(for: summary)
        }
        let verb = file.action == "update" ? "Updated" : "New"
        let label = file.recordType.isEmpty ? "record" : file.recordType
        return "\(verb) \(label)  \(file.path)"
    }

    private var properties: [CaptureNoteFileProperty] {
        if let summary, !summary.properties.isEmpty {
            return summary.properties
        }
        return file.properties
    }

    private var increaseContrast: Bool {
        colorSchemeContrast == .increased
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headingRow
            propertySheet
            noteBody
            markdownDisclosure
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [heading]
        if let summary {
            parts.append(CaptureRecordPreviewPresentation.detail(for: summary))
        }
        return parts.joined(separator: ". ")
    }

    private var headingRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let emoji = summary?.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .accessibilityHidden(true)
                }
                Text(headingTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(heading)
            Text(file.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel("Path \(file.path)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headingTitle: String {
        if let summary {
            let kind = summary.label.lowercased()
            let verb = summary.action == "update" ? "Updated" : "New"
            if let emoji = summary.emoji, !emoji.isEmpty {
                return "\(emoji) \(verb) \(kind)"
            }
            return "\(verb) \(kind)"
        }
        return heading
    }

    @ViewBuilder
    private var propertySheet: some View {
        let rows = properties
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, property in
                    if property.resolvedDisplay != nil || property.isDefault {
                        RecordNotePropertyRow(property: property)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Properties")
        }
    }

    @ViewBuilder
    private var noteBody: some View {
        let lines = file.body.components(separatedBy: "\n")
        let visible = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
                    RecordNoteBodyLine(line: line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(file.body)
        }
    }

    private var markdownDisclosure: some View {
        DisclosureGroup("View Markdown", isExpanded: $showsMarkdown) {
            VStack(alignment: .leading, spacing: 6) {
                Text(file.markdown)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Exact note Markdown")
                Button("Copy Markdown") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(file.markdown, forType: .string)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("record-note-copy-markdown")
                .accessibilityLabel("Copy exact note Markdown")
                .accessibilityHint("Copies the exact Markdown Bob will write")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("record-note-view-markdown")
        .accessibilityLabel("View Markdown")
        .accessibilityHint(
            showsMarkdown ? "Hides the exact note Markdown" : "Shows the exact note Markdown"
        )
        .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: showsMarkdown)
    }
}

/// One property row: human label, display value (wikilinks as chips),
/// and a visible `default` badge with provenance for accessibility.
@available(macOS 26.0, *)
private struct RecordNotePropertyRow: View {
    let property: CaptureNoteFileProperty

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(property.label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)
                .accessibilityLabel(property.label)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                valueContent
                if property.isDefault {
                    Text("default")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Default value")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        var parts = [property.label]
        if let display = property.resolvedDisplay {
            parts.append(display)
        }
        if property.isDefault {
            parts.append("default")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var valueContent: some View {
        if let values = linkValues, !values.isEmpty {
            FlowChips(values: values)
        } else if let display = property.resolvedDisplay {
            let parsed = TaskDisplayText(parsing: display)
            Text(
                CapturePickerRichText.displayText(
                    parsed.text,
                    segments: parsed.segments,
                    matches: []
                )
            )
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Raw wikilink values become one chip each, using the alias-aware
    /// display text Bob's conventions produce.
    private var linkValues: [String]? {
        guard let value = property.value else {
            return nil
        }
        switch value {
        case .string(let text):
            guard text.contains("[[") else {
                return nil
            }
            return [TaskDisplayText(parsing: text).text]
        case .list(let items):
            let chips = items.compactMap { element -> String? in
                guard case .string(let text) = element, text.contains("[[") else {
                    return nil
                }
                return TaskDisplayText(parsing: text).text
            }
            return chips.isEmpty ? nil : chips
        case .number, .bool, .null:
            return nil
        }
    }
}

/// Wrapping chips for wikilink values.
@available(macOS 26.0, *)
private struct FlowChips: View {
    let values: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel("Link \(value)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Wrapping layout for link chips. Lines wrap; plain values stay inline.
@available(macOS 26.0, *)
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        layout(proposal: proposal, subviews: subviews, bounds: bounds)
    }

    @discardableResult
    private func layout(
        proposal: ProposedViewSize,
        subviews: Subviews,
        bounds: CGRect? = nil
    ) -> (size: CGSize, rows: Int) {
        let maxWidth = proposal.width ?? bounds?.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rows = 1
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
                rows += 1
            }
            if let bounds {
                subview.place(
                    at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                    proposal: .unspecified
                )
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return ((CGSize(width: x, height: y + rowHeight)), rows)
    }
}

/// One body line as note content: headings wear heading fonts, every
/// other line reuses inline link/code rendering with nesting preserved.
@available(macOS 26.0, *)
private struct RecordNoteBodyLine: View {
    let line: String

    var body: some View {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        let indent = line.prefix(while: { $0 == " " }).count
        Group {
            if stripped.hasPrefix("# ") {
                Text(String(stripped.dropFirst(2)))
                    .font(.headline)
            } else if stripped.hasPrefix("## ") {
                Text(String(stripped.dropFirst(3)))
                    .font(.subheadline.weight(.semibold))
            } else {
                let bullet = stripped.hasPrefix("- ") ? String(stripped.dropFirst(2)) : stripped
                let parsed = TaskDisplayText(parsing: bullet)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if stripped.hasPrefix("- ") {
                        Text("•")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(
                        CapturePickerRichText.displayText(
                            parsed.text,
                            segments: parsed.segments,
                            matches: []
                        )
                    )
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, CGFloat(indent / 2) * 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Inline record refusal: Bob's message, the missing/invalid field
/// details, and the selectable ready-to-copy draft. The draft is never
/// applied: it can hold ellipses and choice hints, and the user keeps
/// the entire original draft.
@available(macOS 26.0, *)
struct RecordRefusalCardView: View {
    let presentation: CaptureRecordRefusalPresentation
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.message.text)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(nsColor: .systemRed))
                .fixedSize(horizontal: false, vertical: true)
            if !presentation.missing.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(presentation.missing, id: \.self) { key in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text("\(presentation.displayLabel(for: key)) — required")
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(presentation.displayLabel(for: key)), missing required field"
                        )
                    }
                }
            }
            ForEach(Array(presentation.invalid.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("\(presentation.displayLabel(for: row.field)): \(row.message)")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(presentation.displayLabel(for: row.field)): \(row.message)"
                )
            }
            if let draft = presentation.draft {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ready-to-copy draft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(draft)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Ready-to-copy draft")
                    Button("Copy Draft") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(draft, forType: .string)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("record-refusal-copy-draft")
                    .accessibilityLabel("Copy ready-to-copy draft")
                    .accessibilityHint("Copies Bob's suggested draft without applying it")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("record-refusal")
        .accessibilityLabel(presentation.accessibilitySummary)
    }
}
