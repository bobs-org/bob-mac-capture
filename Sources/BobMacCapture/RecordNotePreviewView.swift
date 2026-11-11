import AppKit
import CaptureCore
import SwiftUI

/// Record preview for a committed-plan `note_files` entry paired with its
/// record item. Heading and property sheet come from Bob's metadata; the
/// exact Markdown rides a collapsed disclosure. Creates show the planned
/// note body. Updates show only changed properties and changed lines
/// (falling back to today's body when older Bob omitted `lines`). When
/// record metadata is absent the caller keeps the generic fallback.
@available(macOS 26.0, *)
struct RecordNotePreviewView: View {
    let item: CaptureCommandSuccess
    let file: CaptureNoteFile
    private let startsExpanded: Bool
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(item: CaptureCommandSuccess, file: CaptureNoteFile, expanded: Bool = false) {
        self.item = item
        self.file = file
        startsExpanded = expanded
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

    /// Album destination ("Restaurants · Body") when Bob named the
    /// album, else the file path. The path stays in the accessibility
    /// label either way so nothing precise is lost.
    private var locationCaption: String {
        if let summary,
            let destination = CaptureRecordPreviewPresentation.albumDestination(
                for: summary)
        {
            return destination
        }
        return file.path
    }

    private var locationAccessibilityLabel: String {
        if let summary,
            let destination = CaptureRecordPreviewPresentation.albumDestination(
                for: summary)
        {
            return "\(destination). Path \(file.path)"
        }
        return "Path \(file.path)"
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
            Text(locationCaption)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(locationAccessibilityLabel)
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
        let rows =
            file.action == "update" ? properties.filter(\.displayChanged) : properties
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, property in
                    if file.action == "update"
                        || property.resolvedDisplay != nil
                        || property.isDefault
                    {
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
        if file.action == "update", let lines = file.lines {
            let changed = lines.filter { $0.change != "unchanged" }
            if changed.isEmpty {
                Text("No changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("No changes")
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(changed.enumerated()), id: \.offset) { _, line in
                        RecordChangeLineView(line: line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(changed.map(\.text).joined(separator: "\n"))
            }
        } else {
            plannedBody
        }
    }

    @ViewBuilder
    private var plannedBody: some View {
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
        CaptureNoteMarkdownDisclosure(
            markdown: file.markdown,
            identifierPrefix: "record-note",
            expanded: startsExpanded
        )
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

    private var isChanged: Bool {
        property.displayChanged
            && !(property.resolvedBeforeDisplay ?? "").isEmpty
            && !(property.resolvedDisplay ?? "").isEmpty
    }

    private var rowAccessibilityLabel: String {
        var parts = [property.label]
        if isChanged {
            parts.append(
                "\(property.resolvedBeforeDisplay ?? "") to \(property.resolvedDisplay ?? "")"
            )
        } else if let display = property.resolvedDisplay {
            parts.append(display)
        }
        if property.isDefault {
            parts.append("default")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var valueContent: some View {
        if isChanged {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(property.resolvedBeforeDisplay ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .strikethrough()
                    .accessibilityHidden(true)
                Text("→")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if let display = property.resolvedDisplay {
                    let parsed = TaskDisplayText(parsing: display)
                    Text(
                        CapturePickerRichText.displayText(
                            parsed.text,
                            segments: parsed.segments,
                            matches: []
                        )
                    )
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowAccessibilityLabel)
        } else if let values = linkValues, !values.isEmpty {
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

/// Diff gutter, wash, and glyph for one planned record-note line. Glyphs
/// follow the Record Card contract (`+` added, `~` changed, `−` removed);
/// washes match `BlockDiffCard`.
enum RecordNoteChangeChrome {
    static func glyph(for change: String?) -> String {
        switch change {
        case "added":
            return "+"
        case "changed":
            return "~"
        case "removed":
            return "−"
        default:
            return " "
        }
    }

    static func color(for change: String?) -> Color {
        switch change {
        case "added":
            return .green
        case "changed":
            return .accentColor
        case "removed":
            return .red
        default:
            return .secondary
        }
    }

    static func wash(for change: String?, increaseContrast: Bool) -> Color {
        let opacity: Double
        if increaseContrast {
            opacity = change == nil || change == "unchanged" ? 0 : 0.22
        } else {
            switch change {
            case "added":
                opacity = 0.10
            case "changed":
                opacity = 0.12
            case "removed":
                opacity = 0.08
            default:
                opacity = 0
            }
        }
        return color(for: change).opacity(opacity)
    }
}

/// One planned record-note change line: gutter glyph, wash, verbatim text.
@available(macOS 26.0, *)
struct RecordChangeLineView: View {
    let line: CaptureNoteFileLine
    var compact: Bool = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        let increaseContrast = colorSchemeContrast == .increased
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(RecordNoteChangeChrome.glyph(for: line.change))
                .font(.caption.weight(.bold))
                .foregroundStyle(RecordNoteChangeChrome.color(for: line.change))
                .frame(width: 12, alignment: .center)
                .accessibilityHidden(true)
            Text(line.text)
                .font(compact ? .caption : .callout)
                .lineLimit(compact ? 1 : nil)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: !compact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, compact ? 1 : 2)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    RecordNoteChangeChrome.wash(
                        for: line.change,
                        increaseContrast: increaseContrast
                    )
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(RecordNoteChangeChrome.glyph(for: line.change)) \(line.text)"
        )
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
