import AppKit
import CaptureCore
import SwiftUI

/// Similar-tasks band at the foot of a task-creating preview card.
/// Rows come from Bob; the strip focuses a row and applies draft edits.
@available(macOS 26.0, *)
struct SimilarTasksBandView: View {
    let item: SimilarTasksBandItem
    var folded: Bool = false
    var focusedRowID: String? = nil
    var chosenAction: CaptureRelatedAction? = nil
    var onFocusRow: ((SimilarTasksBandRow) -> Void)? = nil
    var onApplyAction: ((SimilarTasksBandRow, CaptureRelatedAction) -> Void)? = nil

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var identity: String {
        item.rows.map(\.match.key).joined(separator: "\u{1e}")
    }

    private var focusedRowInItem: SimilarTasksBandRow? {
        guard let focusedRowID else { return nil }
        return item.rows.first { $0.id == focusedRowID }
    }

    var body: some View {
        Group {
            if item.isVisible {
                bandBody
                    .contentTransition(reduceMotion ? .identity : .opacity)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(
                                duration: SimilarTasksBandMetrics.crossFadeSeconds
                            ),
                        value: identity
                    )
            }
        }
    }

    @ViewBuilder
    private var bandBody: some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: CGFloat(SimilarTasksBandMetrics.hairlineSpacing))
                .accessibilityHidden(true)
            Rectangle()
                .fill(BlockDiffCard.hairlineColor(contrast: contrast))
                .frame(height: CGFloat(SimilarTasksBandMetrics.hairlineHeight))
                .accessibilityHidden(true)
            if folded, focusedRowInItem == nil {
                foldedLine
            } else if folded, let focused = focusedRowInItem {
                focusedBlock(row: focused)
            } else {
                if item.showsHeader {
                    header
                }
                ForEach(item.rows) { row in
                    if row.id == focusedRowID {
                        focusedBlock(row: row)
                    } else {
                        SimilarTasksBandRowView(
                            row: row,
                            bulkLeadIn: !item.showsHeader,
                            contrast: contrast,
                            isFocused: false,
                            onFocus: onFocusRow,
                            onApply: onApplyAction
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if folded, focusedRowInItem == nil {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    SimilarTasksBandPresentation.foldedAccessibilityLabel(item: item)
                )
        } else {
            content
                .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func focusedBlock(row: SimilarTasksBandRow) -> some View {
        SimilarTasksBandRowView(
            row: row,
            bulkLeadIn: !item.showsHeader,
            contrast: contrast,
            isFocused: true,
            onFocus: onFocusRow,
            onApply: onApplyAction
        )
        SimilarTasksActionStrip(
            row: row,
            chosenAction: chosenAction ?? row.match.defaultAction,
            contrast: contrast,
            onApply: { action in onApplyAction?(row, action) }
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.on.square")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("SIMILAR TASKS")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            if let overflow = SimilarTasksBandPresentation.overflowCapsule(
                count: item.overflowCount
            ) {
                SimilarTasksCapsule(
                    text: overflow,
                    style: .overflow,
                    contrast: contrast
                )
            }
            Spacer(minLength: 8)
            if focusedRowID == nil {
                Text(SimilarTasksBandPresentation.commandHint(rows: item.rows))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: CGFloat(SimilarTasksBandMetrics.headerHeight))
        .accessibilityHidden(true)
    }

    private var foldedLine: some View {
        Text(SimilarTasksBandPresentation.foldedLine(item: item))
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: CGFloat(SimilarTasksBandMetrics.foldedHeight))
    }
}

@available(macOS 26.0, *)
struct SimilarTasksActionStrip: View {
    let row: SimilarTasksBandRow
    var chosenAction: CaptureRelatedAction? = nil
    let contrast: ColorSchemeContrast
    var onApply: ((CaptureRelatedAction) -> Void)? = nil

    private var actions: [CaptureRelatedAction] {
        SimilarTasksBandEdits.orderedAvailableActions(for: row.match)
    }

    var body: some View {
        HStack(spacing: 6) {
            // Align the strip with the title's leading edge: keycap plus
            // status glyph widths, matching the row's leading spacing.
            Color.clear
                .frame(width: 44, height: 1)
                .accessibilityHidden(true)
            ForEach(actions, id: \.wireValue) { action in
                stripChip(for: action)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 20)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            SimilarTasksBandPresentation.stripAccessibilityLabel(
                row: row,
                defaultAction: chosenAction
            )
        )
    }

    private func stripChip(for action: CaptureRelatedAction) -> some View {
        let chosen = action == chosenAction
        return Button {
            onApply?(action)
        } label: {
            HStack(spacing: 4) {
                Text(SimilarTasksBandEdits.sigil(for: action))
                    .font(.caption.monospaced())
                Text(SimilarTasksBandEdits.label(for: action))
                    .font(.caption)
            }
            .foregroundStyle(chosen ? Color.white : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                chosen ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        chosen ? Color.accentColor : Color.primary.opacity(0.18),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(SimilarTasksBandEdits.label(for: action)) \(SimilarTasksBandEdits.sigil(for: action))"
        )
    }
}

@available(macOS 26.0, *)
private struct SimilarTasksBandRowView: View {
    let row: SimilarTasksBandRow
    let bulkLeadIn: Bool
    let contrast: ColorSchemeContrast
    var isFocused: Bool = false
    var onFocus: ((SimilarTasksBandRow) -> Void)? = nil
    var onApply: ((SimilarTasksBandRow, CaptureRelatedAction) -> Void)? = nil

    @State private var hovering = false

    private var closed: Bool { row.match.closed != nil }
    private var status: CapturePickerTaskStatus {
        if let closed = row.match.closed {
            return closed.status == "canceled" ? .canceled : .done
        }
        return CapturePickerTaskStatus(
            symbol: row.match.statusSymbol,
            name: row.match.statusName
        )
    }

    private var statusStyle: (symbol: String, color: Color) {
        CaptureEditorPalette.taskStatus(status)
    }

    private var availableActions: [CaptureRelatedAction] {
        SimilarTasksBandEdits.orderedAvailableActions(for: row.match)
    }

    var body: some View {
        HStack(spacing: 6) {
            if bulkLeadIn {
                Image(systemName: "square.on.square")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            SimilarTasksKeycap(text: "⌘\(row.rowNumber)")
            Image(systemName: statusStyle.symbol)
                .foregroundStyle(statusStyle.color)
                .accessibilityHidden(true)
            titleText
                .foregroundStyle(closed ? Color.secondary : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let symbol = SimilarTasksBandPresentation.kindSymbolName(row.match.kind) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(
                        SimilarTasksBandPresentation.kindAccessibilityLabel(row.match.kind)
                            ?? "Kind"
                    )
            }
            if let capsule = SimilarTasksBandPresentation.capsuleLabel(for: row) {
                SimilarTasksCapsule(
                    text: capsule,
                    style: capsuleStyle(for: row),
                    contrast: contrast
                )
                .layoutPriority(2)
            }
            Spacer(minLength: 8)
            Text(SimilarTasksBandPresentation.locatorText(for: row))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CGFloat(SimilarTasksBandMetrics.rowHeight))
        .padding(.horizontal, 4)
        .background {
            if isFocused {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor.opacity(contrast == .increased ? 0.30 : 0.16))
            } else if hovering {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.quaternary)
            }
        }
        .onHover { hovering = $0 }
        .help(SimilarTasksBandPresentation.rowHelp(row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SimilarTasksBandPresentation.rowAccessibilityLabel(row))
        .onTapGesture {
            onFocus?(row)
        }
        .accessibilityActions {
            ForEach(availableActions, id: \.wireValue) { action in
                Button(SimilarTasksBandEdits.label(for: action)) {
                    onApply?(row, action)
                }
            }
        }
    }

    private var titleText: Text {
        let runs = SimilarTasksBandPresentation.titleRuns(
            title: row.match.title,
            ranges: row.match.matchedRanges
        )
        return runs.reduce(Text("")) { soFar, run in
            var part = Text(run.text)
            if run.emphasized {
                part = part.fontWeight(.semibold)
            }
            return soFar + part
        }
    }

    private func capsuleStyle(for row: SimilarTasksBandRow) -> SimilarTasksCapsule.Style {
        if let link = row.linkedBy {
            switch link {
            case .relation:
                return .related
            case .dependency:
                return .prerequisite
            case .blockedTask:
                return .blockedByThis
            case .parent, .unknown:
                break
            }
        }
        if row.match.closed != nil {
            return .closed
        }
        switch row.match.band {
        case .sameTitle, .possibleDuplicate:
            return .warning
        default:
            return .overflow
        }
    }
}

@available(macOS 26.0, *)
private struct SimilarTasksKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                .background.opacity(0.6),
                in: RoundedRectangle(cornerRadius: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}

@available(macOS 26.0, *)
struct SimilarTasksCapsule: View {
    enum Style {
        case warning
        case closed
        case related
        case prerequisite
        case blockedByThis
        case overflow
    }

    let text: String
    let style: Style
    let contrast: ColorSchemeContrast

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(backgroundFill, in: Capsule())
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var foreground: Color {
        switch style {
        case .warning:
            return .orange
        case .related:
            return CaptureEditorPalette.color(for: .relationSigil)
        case .prerequisite:
            return CaptureEditorPalette.color(for: .route)
        case .blockedByThis:
            return CaptureEditorPalette.color(for: .blockedTaskSigil)
        case .closed:
            return .secondary
        case .overflow:
            return Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var backgroundFill: Color {
        switch style {
        case .warning:
            return Color.orange.opacity(contrast == .increased ? 0.25 : 0.15)
        case .related:
            return CaptureEditorPalette.color(for: .relationSigil).opacity(0.18)
        case .prerequisite:
            return CaptureEditorPalette.color(for: .route).opacity(0.18)
        case .blockedByThis:
            return CaptureEditorPalette.color(for: .blockedTaskSigil).opacity(0.18)
        case .closed, .overflow:
            return Color(nsColor: .quaternaryLabelColor).opacity(0.4)
        }
    }
}
