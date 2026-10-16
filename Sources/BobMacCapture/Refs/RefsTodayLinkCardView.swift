import AppKit
import CaptureCore
import RefsCore
import SwiftUI

let refsTodayLinkFieldAccessibilityIdentifier = "org.bobs.bob-mac-capture.refs-today-link-filter"

/// The Bob-backed Pomodoro picker shown in the Rename card's inspector slot.
@available(macOS 26.0, *)
struct RefsTodayLinkCardView: View {
    let card: RefsTodayLinkCard
    let focusSequence: UInt64
    var previewMode = false
    var fixedNow: Date? = nil
    let onQueryChange: (String) -> Void
    let onRowTap: (Int) -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var now = Date()
    private let minute = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var displayNow: Date { fixedNow ?? now }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            filter
            if case .refused(let message, let hint) = card.phase {
                refused(message: message, hint: hint)
            } else {
                defaultNotice
                rows
                previewStrip
                footerState
            }
        }
        .padding(RefsVisualTokens.inspectorPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Link reference to Today")
        .onReceive(minute) { if fixedNow == nil { now = $0 } }
    }

    private var header: some View {
        HStack(spacing: 9) {
            RefsKindTile(kind: card.kind, size: RefsVisualTokens.kindTileSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(RefsTodayLinkPresentation.header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(card.title)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(card.taskCaption.isEmpty ? card.notePath : card.taskCaption)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 3)
            if let lane = RefsTodayLinkPresentation.laneChip(capture: card.preview?.capture) {
                Text(lane)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isGuarded ? Color.orange : Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        (isGuarded ? Color.orange : Color.accentColor).opacity(0.12),
                        in: Capsule()
                    )
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var filter: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if previewMode {
                Text(card.query.isEmpty ? placeholder : card.query)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(card.query.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                RefsTodayLinkFilterField(
                    text: card.query,
                    placeholder: placeholder,
                    isEnabled: card.phase != .running,
                    focusSequence: focusSequence,
                    onTextChange: onQueryChange
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.primary.opacity(contrast == .increased ? 0.28 : 0.12))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RefsTodayLinkPresentation.filterAccessibilityLabel)
    }

    private var placeholder: String {
        RefsTodayLinkPresentation.placeholder(pomodoros: card.pomodoros)
    }

    @ViewBuilder
    private var defaultNotice: some View {
        if let message = RefsTodayLinkPresentation.defaultProblem(
            card.defaultProblem, pomodoros: card.pomodoros
        ) {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var rows: some View {
        switch card.phase {
        case .loading, .reloading:
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 9) {
                        Circle().fill(.secondary.opacity(0.16)).frame(width: 17, height: 17)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.secondary.opacity(0.16))
                            .frame(width: 126, height: 11)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 38)
                }
            }
            .accessibilityLabel(
                card.phase == .reloading
                    ? RefsTodayLinkPresentation.reloading
                    : RefsTodayLinkPresentation.loading
            )
        case .ready, .running, .failed:
            if card.visiblePomodoros.isEmpty, !card.offersCreate, card.query.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(RefsTodayLinkPresentation.emptyTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(RefsTodayLinkPresentation.emptyHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityElement(children: .combine)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(card.visiblePomodoros.enumerated()), id: \.offset) { index, row in
                            pomodoroRow(row, index: index)
                        }
                        if card.offersCreate {
                            createRow(index: card.visiblePomodoros.count)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        case .refused:
            EmptyView()
        }
    }

    private func pomodoroRow(_ row: RefsTodayLinkPomodoro, index: Int) -> some View {
        let selected = card.selectedIndex == index
        let label = RefsTodayLinkPresentation.rowAccessibilityLabel(
            row, selected: selected, now: displayNow
        )
        return HStack(spacing: 8) {
            progressGlyph(row)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(RefsTodayLinkPresentation.rowTitle(row))
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    pillLabels(row)
                    Spacer(minLength: 0)
                    if selected { RefsReturnKeycap() }
                }
                Text(RefsTodayLinkPresentation.rowMeta(row, now: displayNow))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 42)
        .background(rowBackground(selected: selected))
        .contentShape(Rectangle())
        .onTapGesture { onRowTap(index) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onRowTap(index) }
    }

    private func createRow(index: Int) -> some View {
        let selected = card.selectsCreate
        return HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(RefsTodayLinkPresentation.createTitle(query: card.query))
                .font(.callout.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(RefsTodayLinkPresentation.newPill)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            Spacer(minLength: 0)
            if selected { RefsReturnKeycap() }
        }
        .padding(.horizontal, 7)
        .frame(height: 38)
        .background(rowBackground(selected: selected))
        .contentShape(Rectangle())
        .onTapGesture { onRowTap(index) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(RefsTodayLinkPresentation.createTitle(query: card.query)), New")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onRowTap(index) }
    }

    private func progressGlyph(_ row: RefsTodayLinkPomodoro) -> some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.24), lineWidth: 2)
            if row.running, let fraction = RefsTodayLinkPresentation.progress(row, now: displayNow) {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.pink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else if row.isDefault {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func pillLabels(_ row: RefsTodayLinkPomodoro) -> some View {
        ForEach(RefsTodayLinkPresentation.pills(row), id: \.self) { label in
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(pillColor(label))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(pillColor(label).opacity(0.12), in: Capsule())
        }
    }

    private func pillColor(_ label: String) -> Color {
        switch label {
        case "Running": return .pink
        case "Next up": return .accentColor
        default: return .secondary
        }
    }

    private func rowBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(selected ? Color.accentColor.opacity(0.12) : .clear)
    }

    private var previewStrip: some View {
        Group {
            if let line = RefsTodayLinkPresentation.previewLine(card.preview) {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(isGuarded ? Color.orange : Color.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(card.previewPending ? 0.48 : 1)
                    .accessibilityLabel(line)
            } else if card.phase == .loading {
                Text(RefsTodayLinkPresentation.loading)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .padding(.top, 3)
        .overlay(alignment: .top) {
            Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var footerState: some View {
        switch card.phase {
        case .running:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text(RefsTodayLinkPresentation.linking)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Linking reference")
        case .failed(let message, let hint):
            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint, !hint.isEmpty {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        case .reloading:
            Text(RefsTodayLinkPresentation.reloading)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loading, .ready, .refused:
            EmptyView()
        }
    }

    private func refused(message: String, hint: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.circle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(card.failure.map(RefsTodayLinkPresentation.refusalTitle) ?? "Couldn't link reference")
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("Esc closes")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var isGuarded: Bool {
        card.preview?.capture.map { CaptureLinkGuardPresentation(capture: $0) != nil } ?? false
    }
}

@available(macOS 26.0, *)
private struct RefsTodayLinkFilterField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let isEnabled: Bool
    let focusSequence: UInt64
    let onTextChange: (String) -> Void

    func makeNSView(context: Context) -> CapturePickerFilterNSTextField {
        let field = CapturePickerFilterNSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier(refsTodayLinkFieldAccessibilityIdentifier)
        field.setAccessibilityLabel(RefsTodayLinkPresentation.filterAccessibilityLabel)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: CapturePickerFilterNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        field.isEnabled = isEnabled
        guard context.coordinator.appliedFocusSequence != focusSequence else { return }
        context.coordinator.appliedFocusSequence = focusSequence
        field.requestFirstResponder()
        DispatchQueue.main.async { [weak field] in
            guard let field, !field.holdsFirstResponder else { return }
            field.requestFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RefsTodayLinkFilterField
        var appliedFocusSequence: UInt64?

        init(parent: RefsTodayLinkFilterField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.onTextChange(field.stringValue)
        }
    }
}

@available(macOS 26.0, *)
private struct RefsReturnKeycap: View {
    var body: some View {
        Text("↵")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
    }
}
