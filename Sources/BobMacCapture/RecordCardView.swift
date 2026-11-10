import CaptureCore
import SwiftUI

extension CapturePanelLayout {
    static let recordCardHeaderHeight: CGFloat = 36
    static let recordCardRowHeight: CGFloat = 32
    static let recordCardMoreHeight: CGFloat = 26
    static let recordCardFooterHeight: CGFloat = 34
    static let recordCardPadding: CGFloat = 10
    static let recordCardMaxRows = 8
    static let recordCardMinRows = 3
}

/// Fixed-height sizing for the Record Card in the picker slot. Filtering
/// and More disclosure change the row count; the short-screen floor keeps
/// the header, a few rows, and the footer readable.
struct RecordCardHeightPolicy: Equatable {
    var rowCount: Int
    var showsMoreControl: Bool
    var displayScale: CGFloat = 1

    init(
        rowCount: Int,
        showsMoreControl: Bool,
        displayScale: CGFloat = 1
    ) {
        self.rowCount = rowCount
        self.showsMoreControl = showsMoreControl
        self.displayScale = displayScale
    }

    init(presentation: CaptureRecordPresentation, displayScale: CGFloat = 1) {
        self.init(
            rowCount: presentation.displayedRows.count,
            showsMoreControl: !presentation.hiddenOptionalRows.isEmpty
                || presentation.showsMore,
            displayScale: displayScale
        )
    }

    var clampedRows: Int {
        min(max(rowCount, 1), CapturePanelLayout.recordCardMaxRows)
    }

    var minimumRowCount: Int {
        min(CapturePanelLayout.recordCardMinRows, clampedRows)
    }

    private func listHeight(forRowCount rows: Int) -> CGFloat {
        roundedToPixel(CapturePanelLayout.recordCardRowHeight * CGFloat(rows))
    }

    var listViewportHeight: CGFloat {
        listHeight(forRowCount: clampedRows)
    }

    var moreHeight: CGFloat {
        showsMoreControl ? CapturePanelLayout.recordCardMoreHeight : 0
    }

    var chromeHeight: CGFloat {
        CapturePanelLayout.recordCardPadding * 2
            + CapturePanelLayout.recordCardHeaderHeight
            + 1
            + moreHeight
            + 1
            + CapturePanelLayout.recordCardFooterHeight
    }

    var idealHeight: CGFloat {
        roundedToPixel(chromeHeight + listViewportHeight)
    }

    var minimumVisibleHeight: CGFloat {
        roundedToPixel(chromeHeight + listHeight(forRowCount: minimumRowCount))
    }

    var auxiliaryHeight: CapturePanelAuxiliaryHeight {
        CapturePanelAuxiliaryHeight(
            idealHeight: idealHeight,
            minimumVisibleHeight: minimumVisibleHeight
        )
    }

    private func roundedToPixel(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (value * scale).rounded(.up) / scale
    }
}

/// Record Card in the picker-card slot. Every control accepts a Bob
/// completion row or requests a named field; the view never invents
/// replacement text (`decisions:mac-capture-is-a-thin-client`).
@available(macOS 26.0, *)
struct RecordCardView: View {
    @ObservedObject var model: CapturePanelModel
    let presentation: CaptureRecordPresentation
    var previewMode = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var policy: RecordCardHeightPolicy {
        let fields = fieldCandidates
        if !fields.isEmpty {
            return RecordCardHeightPolicy(
                rowCount: fields.count,
                showsMoreControl: false,
                displayScale: displayScale
            )
        }
        return RecordCardHeightPolicy(presentation: presentation, displayScale: displayScale)
    }

    private var increaseContrast: Bool {
        colorSchemeContrast == .increased
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: CapturePanelLayout.recordCardHeaderHeight)
            Divider()
            rowList
            if policy.showsMoreControl {
                moreControl
                    .frame(height: CapturePanelLayout.recordCardMoreHeight)
            }
            Divider()
            footer
                .frame(height: CapturePanelLayout.recordCardFooterHeight)
        }
        .padding(.horizontal, CapturePanelLayout.recordCardPadding)
        .padding(.vertical, 2)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CapturePanelLayout.pickerCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CapturePanelLayout.pickerCornerRadius)
                .strokeBorder(Color.primary.opacity(increaseContrast ? 0.28 : 0.08), lineWidth: 0.5)
        )
        .shadow(radius: reduceMotion ? 0 : 18, y: reduceMotion ? 0 : 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("record-card")
        .accessibilityLabel(cardAccessibilityLabel)
        .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: presentation.showsMore)
    }

    private var cardAccessibilityLabel: String {
        var parts = [presentation.headerTitle]
        if let path = presentation.headerPath {
            parts.append(path)
        }
        parts.append(presentation.notesLabel)
        return parts.joined(separator: ", ")
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let emoji = presentation.record.emoji, !emoji.isEmpty {
                Text(emoji)
                    .accessibilityHidden(true)
            }
            Text(presentation.headerTitle)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let path = presentation.headerPath {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel("Path \(path)")
            }
            Text(presentation.notesLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardAccessibilityLabel)
    }

    @ViewBuilder
    private var rowList: some View {
        let fields = fieldCandidates
        if !fields.isEmpty {
            candidateList(fields)
        } else if previewMode {
            VStack(spacing: 0) {
                ForEach(presentation.displayedRows, id: \.key) { row in
                    schemaRow(row)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: CapturePanelLayout.recordCardRowHeight,
                            alignment: .leading
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: policy.listViewportHeight, alignment: .top)
            .clipped()
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(presentation.displayedRows, id: \.key) { row in
                        schemaRow(row)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: CapturePanelLayout.recordCardRowHeight,
                                alignment: .leading
                            )
                            .id(row.key)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: policy.listViewportHeight)
        }
    }

    private func schemaRow(_ row: CaptureRecordRow) -> some View {
        RecordCardRowView(
            row: row,
            isActive: row.key == presentation.activeFieldKey
                || row.key == presentation.selectedRowKey,
            candidates: candidates(for: row),
            selectedCandidateIndex: model.selectedCompletionIndex,
            editAvailable: editAvailable(for: row),
            diagnostic: diagnostic(for: row),
            increaseContrast: increaseContrast,
            onSelectField: { selectField(row) },
            onAccept: acceptCandidate,
            onEdit: { _ = model.editRecordField() }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func candidateList(_ candidates: [CaptureCompletionCandidate]) -> some View {
        let selected = model.selectedCompletionIndex
        if previewMode {
            VStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    RecordCardFieldCandidateRow(
                        candidate: candidate,
                        isSelected: index == selected,
                        increaseContrast: increaseContrast,
                        onAccept: { acceptCandidate(candidate) }
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: CapturePanelLayout.recordCardRowHeight,
                        alignment: .leading
                    )
                    .id(index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: policy.listViewportHeight, alignment: .top)
            .clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) {
                            index,
                            candidate in
                            RecordCardFieldCandidateRow(
                                candidate: candidate,
                                isSelected: index == selected,
                                increaseContrast: increaseContrast,
                                onAccept: { acceptCandidate(candidate) }
                            )
                            .frame(
                                maxWidth: .infinity,
                                minHeight: CapturePanelLayout.recordCardRowHeight,
                                alignment: .leading
                            )
                            .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                .frame(height: policy.listViewportHeight)
                .onAppear {
                    if let selected {
                        proxy.scrollTo(selected, anchor: .center)
                    }
                }
                .onChange(of: selected) { _, index in
                    if let index {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private var moreControl: some View {
        Button {
            model.setRecordMoreExpanded(!presentation.showsMore)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: presentation.showsMore ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(presentation.moreLabel)
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("record-more")
        .accessibilityLabel(presentation.moreLabel)
        .accessibilityHint(
            presentation.showsMore
                ? "Hides optional fields"
                : "Shows optional fields"
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(footerCopy)
                .font(.caption.monospaced())
                .foregroundStyle(footerIsRefusal ? Color(nsColor: .systemRed) : .secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(footerCopy)
    }

    private var footerResolved: (text: String, isRefusal: Bool) {
        CaptureRecordFooterMessage.copy(
            statusText: model.statusText,
            statusIsRefusal: model.statusIsRefusal,
            errorDiagnostic: model.latestParse?.diagnostics.first {
                $0.severity == "error"
            }?.message,
            footerHint: presentation.footerHint
        )
    }

    private var footerIsRefusal: Bool {
        footerResolved.isRefusal
    }

    private var footerCopy: String {
        footerResolved.text
    }

    private var fieldCandidates: [CaptureCompletionCandidate] {
        let live = previewMode || model.recordCompletionListVisible
        guard live,
            let response = model.completionResponse,
            response.context == "record_field",
            !response.candidates.isEmpty
        else {
            return []
        }
        return response.candidates
    }

    private func candidates(for row: CaptureRecordRow) -> [CaptureCompletionCandidate] {
        let live = previewMode || model.recordCompletionListVisible
        guard live, let response = model.completionResponse else {
            return []
        }
        let field = response.record?.field ?? presentation.activeFieldKey
        guard response.context == "record_value", field == row.key else {
            return []
        }
        return response.candidates
    }

    private func editAvailable(for row: CaptureRecordRow) -> Bool {
        let field = model.completionResponse?.record?.field ?? presentation.activeFieldKey
        let live = previewMode || model.recordEditAvailable
        return live && field == row.key && model.completionResponse?.record?.edit != nil
    }

    private func diagnostic(for row: CaptureRecordRow) -> String? {
        guard let parse = model.latestParse else {
            return nil
        }
        let field = presentation.record.fields.first { $0.key == row.key }
        return parse.diagnostics.first { diagnostic in
            guard diagnostic.severity == "error", let range = diagnostic.range else {
                return false
            }
            if let fieldRange = field?.range,
                range.start <= fieldRange.end && range.end >= fieldRange.start
            {
                return true
            }
            return field?.valueRanges.contains {
                range.start <= $0.end && range.end >= $0.start
            } == true
        }?.message
    }

    private func selectField(_ row: CaptureRecordRow) {
        _ = model.requestRecordField(row.key)
    }

    private func acceptCandidate(_ candidate: CaptureCompletionCandidate) {
        _ = model.acceptRecordCandidate(candidate)
    }
}

@available(macOS 26.0, *)
private struct RecordCardRowView: View {
    let row: CaptureRecordRow
    let isActive: Bool
    let candidates: [CaptureCompletionCandidate]
    let selectedCandidateIndex: Int?
    let editAvailable: Bool
    let diagnostic: String?
    let increaseContrast: Bool
    let onSelectField: () -> Void
    let onAccept: (CaptureCompletionCandidate) -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: row.stateSymbolName)
                .foregroundStyle(stateColor)
                .frame(width: 14)
                .accessibilityHidden(true)
            Button(action: onSelectField) {
                Text(row.label)
                    .font(.callout.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 92, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("record-field-\(row.key)")
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityAddTraits(isActive ? .isSelected : [])

            valueContent
                .frame(maxWidth: .infinity, alignment: .leading)

            if row.source == "default" {
                Text("default")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Default")
            }
            if editAvailable {
                Button("Edit", action: onEdit)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("record-edit")
                    .accessibilityLabel("Edit \(row.label)")
                    .accessibilityHint("Edits the value in the draft")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .background(isActive ? Color.primary.opacity(increaseContrast ? 0.12 : 0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelectField)
    }

    @ViewBuilder
    private var valueContent: some View {
        switch row.valueMode(
            hasCandidates: !candidates.isEmpty,
            hasDiagnostic: diagnostic != nil
        ) {
        case .candidates:
            if row.kind == "choices" {
                choiceCapsules(candidates)
            } else {
                inlineValues(candidates)
            }
        case .changed:
            HStack(spacing: 6) {
                Text(row.beforeDisplay ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .strikethrough()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityHidden(true)
                Text("→")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(row.display ?? "")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
        case .display:
            HStack(spacing: 6) {
                Text(row.display ?? "")
                    .font(.callout)
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if row.state == "missing" {
                    fillHint
                }
                Spacer(minLength: 0)
            }
        case .choices:
            schemaChoiceCapsules
        case .diagnostic:
            HStack(spacing: 6) {
                Text(diagnostic ?? "")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
        case .fillHint:
            HStack(spacing: 6) {
                fillHint
                Spacer(minLength: 0)
            }
        case .empty:
            Spacer(minLength: 0)
        }
    }

    private var fillHint: some View {
        Text("⇥ fill")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .accessibilityLabel("Fill \(row.label)")
    }

    private var schemaChoiceCapsules: some View {
        HStack(spacing: 6) {
            ForEach(row.choices, id: \.value) { choice in
                Button(choice.label.isEmpty ? choice.value : choice.label, action: onSelectField)
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("record-choice-\(choice.value)")
                    .accessibilityLabel(choice.label.isEmpty ? choice.value : choice.label)
                    .accessibilityHint("Requests \(row.label)")
            }
        }
        .lineLimit(1)
    }

    private func choiceCapsules(_ candidates: [CaptureCompletionCandidate]) -> some View {
        valueScroller(candidates, capsule: true)
    }

    private func inlineValues(_ candidates: [CaptureCompletionCandidate]) -> some View {
        valueScroller(candidates, capsule: false)
    }

    private func valueScroller(
        _ candidates: [CaptureCompletionCandidate],
        capsule: Bool
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(
                        Array(candidates.enumerated()),
                        id: \.element.id
                    ) { index, candidate in
                        let title =
                            candidate.display ?? candidate.label ?? candidate.recordValue
                            ?? candidate.replacement
                        let selected = index == selectedCandidateIndex
                        Button(title) { onAccept(candidate) }
                            .font(capsule ? .caption.weight(.semibold) : .caption)
                            .padding(.horizontal, capsule ? 7 : 4)
                            .padding(.vertical, capsule ? 3 : 1)
                            .background(
                                selected
                                    ? Color.primary.opacity(increaseContrast ? 0.18 : 0.10)
                                    : (capsule ? Color.primary.opacity(0.06) : Color.clear),
                                in: Capsule()
                            )
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                "record-choice-\(candidate.recordValue ?? candidate.replacement)"
                            )
                            .accessibilityLabel(title)
                            .accessibilityHint("Accepts this \(row.label) value")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .id(index)
                    }
                }
                .lineLimit(1)
            }
            .onAppear {
                if let selectedCandidateIndex {
                    proxy.scrollTo(selectedCandidateIndex, anchor: .center)
                }
            }
            .onChange(of: selectedCandidateIndex) { _, index in
                if let index {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    private var stateColor: Color {
        CaptureEditorPalette.recordFieldValueColor(
            state: row.state,
            increaseContrast: increaseContrast
        )
    }
}

@available(macOS 26.0, *)
private struct RecordCardFieldCandidateRow: View {
    let candidate: CaptureCompletionCandidate
    let isSelected: Bool
    let increaseContrast: Bool
    let onAccept: () -> Void

    var body: some View {
        Button(action: onAccept) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "list.bullet")
                    .frame(width: 14)
                    .accessibilityHidden(true)
                Text(candidate.label ?? candidate.key ?? candidate.replacement)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(width: 92, alignment: .leading)
                Text(candidate.replacement)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .background(
            isSelected ? Color.primary.opacity(increaseContrast ? 0.12 : 0.06) : Color.clear
        )
        .accessibilityIdentifier("record-field-candidate-\(candidate.key ?? candidate.replacement)")
        .accessibilityLabel(candidate.label ?? candidate.key ?? candidate.replacement)
        .accessibilityHint("Inserts this field")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
