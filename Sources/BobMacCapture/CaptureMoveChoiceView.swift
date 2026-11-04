import AppKit
import CaptureCore
import SwiftUI

extension CapturePanelLayout {
    static let moveChoiceBarHeight: CGFloat = 48
    static let moveChoiceSectionHeight: CGFloat = 25
    static let moveChoiceRowHeight: CGFloat = 44
    static let moveChoiceListPadding: CGFloat = 6
    static let moveChoiceMaxVisibleRows = 7
    static let moveChoiceMinVisibleRows = 2
    static let moveChoiceDetailHeight: CGFloat = 62
}

/// The Move card is a presentation of one Bob-reported `move_choice` slot.
/// Its binding contains only local marks and focus; callers own the capture
/// flow and decide what the footer actions do.
@available(macOS 26.0, *)
struct CaptureMoveChoiceCard: View {
    @Binding var choice: CaptureMoveChoiceState
    let todayBadge: TodayBadgePresentation?
    let previewMode: Bool
    let onConfirm: () -> Void
    let onNone: () -> Void
    let onBack: () -> Void

    init(
        choice: Binding<CaptureMoveChoiceState>,
        todayBadge: TodayBadgePresentation? = nil,
        previewMode: Bool = false,
        onConfirm: @escaping () -> Void = {},
        onNone: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) {
        _choice = choice
        self.todayBadge = todayBadge
        self.previewMode = previewMode
        self.onConfirm = onConfirm
        self.onNone = onNone
        self.onBack = onBack
    }

    @Environment(\.displayScale) private var displayScale

    private var listContentHeight: CGFloat {
        let sections = choice.sections.count
        let rows = choice.rows.count
        return CapturePanelLayout.moveChoiceListPadding * 2
            + CGFloat(sections) * CapturePanelLayout.moveChoiceSectionHeight
            + CGFloat(rows) * CapturePanelLayout.moveChoiceRowHeight
    }

    private var listViewportHeight: CGFloat {
        let scale = max(displayScale, 1)
        let rowHeight = CapturePanelLayout.moveChoiceRowHeight
        let sectionHeight =
            CGFloat(max(choice.sections.count, 1))
            * CapturePanelLayout.moveChoiceSectionHeight
        let minimum =
            CapturePanelLayout.moveChoiceListPadding * 2
            + sectionHeight
            + CGFloat(CapturePanelLayout.moveChoiceMinVisibleRows) * rowHeight
        let maximum =
            CapturePanelLayout.moveChoiceListPadding * 2
            + sectionHeight
            + CGFloat(CapturePanelLayout.moveChoiceMaxVisibleRows) * rowHeight
        let bounded = min(max(listContentHeight, minimum), maximum)
        return (bounded * scale).rounded(.up) / scale
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: CapturePanelLayout.moveChoiceBarHeight)
            Divider()
            if previewMode {
                staticRows
                    .frame(height: listViewportHeight, alignment: .top)
                    .clipped()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        rows
                    }
                    .frame(height: listViewportHeight)
                    .onChange(of: choice.currentRow?.key) { _, key in
                        guard let key else { return }
                        proxy.scrollTo(key, anchor: nil)
                    }
                }
            }
            Divider()
            detailStrip
                .frame(height: CapturePanelLayout.moveChoiceDetailHeight)
            footer
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CapturePanelLayout.pickerCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CapturePanelLayout.pickerCornerRadius)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Move tasks from \(choice.slot.parent)")
        .focusable()
        .focusEffectDisabled()
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("↪")
                        .foregroundStyle(CaptureEditorPalette.color(for: .route))
                    Text(CaptureMoveChoicePresentation.title(for: choice.slot))
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                }
                Text(CaptureMoveChoicePresentation.subtitle(for: choice.slot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            Text(choice.counterText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            if let todayBadge {
                TodayBadge(presentation: todayBadge)
            }
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(choice.sections) { section in
                Section {
                    ForEach(section.rows, id: \.key) { row in
                        taskRow(row)
                            .id(row.key)
                    }
                } header: {
                    sectionHeader(section)
                }
            }
            if choice.rows.isEmpty {
                Text("No open tasks in \(choice.slot.parent)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            }
        }
        .padding(CapturePanelLayout.moveChoiceListPadding)
    }

    private var staticRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(choice.sections) { section in
                sectionHeader(section)
                ForEach(section.rows, id: \.key) { row in
                    taskRow(row)
                        .id(row.key)
                }
            }
            if choice.rows.isEmpty {
                Text("No open tasks in \(choice.slot.parent)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            }
        }
        .padding(CapturePanelLayout.moveChoiceListPadding)
    }

    private func sectionHeader(_ section: CaptureMoveChoiceSection) -> some View {
        HStack {
            Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            Text("\(choice.markedCount(in: section)) marked")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .frame(height: CapturePanelLayout.moveChoiceSectionHeight)
        .background(.regularMaterial)
    }

    private func taskRow(_ row: CaptureMoveChoiceRow) -> some View {
        let answer = choice.answer(for: row)
        let highlighted = choice.currentRow?.key == row.key
        let selectable = row.choices.contains(where: { $0.sigil == "^" })
        return HStack(spacing: 8) {
            sigilWell(row, answer: answer, highlighted: highlighted, selectable: selectable)
                .frame(width: 54, alignment: .leading)

            Button {
                choice.highlight(rowKey: row.key)
            } label: {
                HStack(spacing: 7) {
                    Text(CaptureMoveChoicePresentation.statusGlyph(for: row))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(statusColor(for: row.statusSymbol))
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(row.text)
                        .font(.callout.weight(highlighted ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let pomodoro = row.pomodoro {
                        smallChip(pomodoro.name ?? "TODAY", symbol: "timer")
                    }
                    if let scheduled = row.scheduled, !scheduled.isEmpty {
                        smallChip(scheduled, symbol: "calendar")
                    }
                    if row.hidden {
                        smallChip("HIDDEN", symbol: "eye.slash")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.statusName), \(row.text)")
            .accessibilityAddTraits(highlighted ? .isSelected : [])

            if let identity = CaptureMoveChoicePresentation.rowIdentity(for: row) {
                Text(identity)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 130, alignment: .trailing)
            } else if let disabledReason = row.disabledReason {
                Text(disabledReason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: CapturePanelLayout.moveChoiceRowHeight)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.13))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func sigilWell(
        _ row: CaptureMoveChoiceRow,
        answer: CaptureMoveChoiceAnswer?,
        highlighted: Bool,
        selectable: Bool
    ) -> some View {
        if let locked = row.locked {
            HStack(spacing: 4) {
                Text(locked.sigil)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color(for: locked.sigil))
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Already moving on line \(locked.itemLine)")
        } else if selectable && highlighted {
            HStack(spacing: 1) {
                stateButton("·", row: row, answer: nil, selected: answer == nil)
                stateButton("^", row: row, answer: .move, selected: answer == .move)
                stateButton(":", row: row, answer: .moveAndLink, selected: answer == .moveAndLink)
            }
            .padding(2)
            .background(.background.opacity(0.72), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Move state for \(row.text)")
        } else {
            let sigil = answer?.sigil ?? "·"
            Text(sigil)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color(for: sigil))
                .frame(width: 42, height: 28)
                .background(color(for: sigil).opacity(answer == nil ? 0.05 : 0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(color(for: sigil).opacity(0.3), lineWidth: 0.7))
                .accessibilityLabel(
                    answer.map { $0 == .move ? "Move" : "Move and link" } ?? "Leave")
        }
    }

    private func stateButton(
        _ label: String,
        row: CaptureMoveChoiceRow,
        answer: CaptureMoveChoiceAnswer?,
        selected: Bool
    ) -> some View {
        let enabled = answer == nil || row.choices.contains(where: { $0.sigil == answer?.sigil })
        return Button {
            _ = choice.setAnswer(answer, for: row.key)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color(for: label))
                .frame(width: 16, height: 22)
                .background {
                    if selected {
                        Capsule().fill(color(for: label).opacity(0.18))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(previewMode || !enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label == "·" ? "Leave" : label == "^" ? "Move" : "Move and link")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func smallChip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.background.opacity(0.62), in: Capsule())
    }

    private var detailStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let row = choice.currentRow {
                HStack(spacing: 5) {
                    Text(row.text)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(detailText(for: row))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .accessibilityElement(children: .combine)
            }
            Text(choice.slot.copy?.slot ?? "In \(choice.slot.parent) order")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detailAccessibilityText)
    }

    private var detailAccessibilityText: String {
        guard let row = choice.currentRow else {
            return choice.slot.copy?.slot ?? "In \(choice.slot.parent) order"
        }
        return
            "\(row.text). \(detailText(for: row)). \(choice.slot.copy?.slot ?? "In \(choice.slot.parent) order")"
    }

    private func detailText(for row: CaptureMoveChoiceRow) -> String {
        if let lockText = CaptureMoveChoicePresentation.lockText(for: row) {
            return lockText
        }
        if let disabled = row.disabledReason {
            return disabled
        }
        return choice.consequence(for: row)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("^ move  : move & link  Space toggle  ⌘A all")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button("Back  esc", action: onBack)
                .buttonStyle(CapturePullInActionButtonStyle(prominent: false))
                .disabled(previewMode)
            Button("None  ⇧↩", action: onNone)
                .buttonStyle(CapturePullInActionButtonStyle(prominent: false))
                .disabled(previewMode)
            Button(action: onConfirm) {
                HStack(spacing: 4) {
                    Text(choice.primaryLabel)
                    Text("↩").opacity(0.7)
                }
            }
            .buttonStyle(CapturePullInActionButtonStyle(prominent: true))
            .disabled(previewMode || !choice.canConfirm)
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Caret moves the task, colon moves and links it, Space toggles, Command-A selects all, Shift-Return moves none, Return moves the marked tasks"
        )
    }

    private func color(for sigil: String) -> Color {
        switch sigil {
        case "^": CaptureEditorPalette.color(for: .route)
        case ":": CaptureEditorPalette.color(for: .explicitToggle)
        default: CaptureEditorPalette.color(for: .interactivePlaceholder)
        }
    }

    private func statusColor(for symbol: String) -> Color {
        switch symbol {
        case "/": .orange
        case "*": .blue
        case "x", "X": .green
        default: .secondary
        }
    }
}
