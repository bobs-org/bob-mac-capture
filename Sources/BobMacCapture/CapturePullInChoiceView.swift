import AppKit
import CaptureCore
import SwiftUI

/// Layout constants for the successor pull-in choice card. They live on
/// `CapturePanelLayout` so the card, the height policy, and the panel metrics
/// share one source of truth.
extension CapturePanelLayout {
    static let pullInBarHeight: CGFloat = 46
    static let pullInContextHeight: CGFloat = 26
    static let pullInSectionHeaderHeight: CGFloat = 28
    static let pullInFoldRowHeight: CGFloat = 22
    static let pullInRowHeight: CGFloat = 44
    static let pullInListPadding: CGFloat = 6
    static let pullInMaxVisibleRows = 6
    static let pullInMinVisibleRows = 2
}

/// Fixed-height sizing policy for the pull-in choice card. The budget is
/// fixed at open from the full choice state, so filtering or collapsing
/// never resizes the panel, matching the picker's contract.
struct CapturePullInChoiceHeightPolicy: Equatable {
    var sectionCount: Int
    var foldRowCount: Int
    var rowCount: Int
    var hasContextLine: Bool
    var displayScale: CGFloat = 1

    init(
        sectionCount: Int,
        foldRowCount: Int,
        rowCount: Int,
        hasContextLine: Bool,
        displayScale: CGFloat = 1
    ) {
        self.sectionCount = sectionCount
        self.foldRowCount = foldRowCount
        self.rowCount = rowCount
        self.hasContextLine = hasContextLine
        self.displayScale = displayScale
    }

    init(choice: CapturePullInChoiceState, displayScale: CGFloat = 1) {
        let sections = choice.sections
        let folds = sections.filter { section in
            guard let folded = section.folded else {
                return false
            }
            return folded.hidden > 0 || folded.alreadyPlanned > 0 || folded.subProjects > 0
        }.count
        let hasContext = choice.contextText != nil || choice.planBudget != nil
        self.init(
            sectionCount: sections.count,
            foldRowCount: folds,
            rowCount: choice.rows.count,
            hasContextLine: hasContext,
            displayScale: displayScale
        )
    }

    var listContentHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.pullInListPadding * 2
                + CGFloat(sectionCount) * CapturePanelLayout.pullInSectionHeaderHeight
                + CGFloat(foldRowCount) * CapturePanelLayout.pullInFoldRowHeight
                + CGFloat(rowCount) * CapturePanelLayout.pullInRowHeight
        )
    }

    var maxListHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.pullInListPadding * 2
                + CapturePanelLayout.pullInSectionHeaderHeight
                + CGFloat(CapturePanelLayout.pullInMaxVisibleRows) * CapturePanelLayout.pullInRowHeight
        )
    }

    var minListHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.pullInListPadding * 2
                + CapturePanelLayout.pullInSectionHeaderHeight
                + CGFloat(CapturePanelLayout.pullInMinVisibleRows) * CapturePanelLayout.pullInRowHeight
        )
    }

    var listViewportHeight: CGFloat {
        min(listContentHeight, maxListHeight)
    }

    var idealHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.pullInBarHeight
                + (hasContextLine ? CapturePanelLayout.pullInContextHeight : 0)
                + 1
                + listViewportHeight
        )
    }

    var minimumVisibleHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.pullInBarHeight
                + (hasContextLine ? CapturePanelLayout.pullInContextHeight : 0)
                + 1
                + min(listContentHeight, minListHeight)
        )
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

/// The successor pull-in choice card: a full-width sibling of the capture
/// picker with a filter bar, a context line, a fixed-height list of two-line
/// rows under pinned group headers, and a footer with keycap hints plus
/// action buttons. You can see what Return will do: the rows Return will
/// pull in light up in the same green they wear in the preview after
/// linking.
@available(macOS 26.0, *)
struct CapturePullInChoiceCard: View {
    @ObservedObject var model: CapturePanelModel
    let choice: CapturePullInChoiceState
    /// Design fixtures lay the same rows out in a static stack:
    /// `ImageRenderer` snapshots `ScrollView` content blank, so the live
    /// scroll view never appears in a fixture (the Refs panel precedent:
    /// `RefsListView`, `RefsSearchBar`, `RefsPanelView`).
    var previewMode = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var policy: CapturePullInChoiceHeightPolicy {
        CapturePullInChoiceHeightPolicy(choice: choice, displayScale: displayScale)
    }

    var body: some View {
        VStack(spacing: 0) {
            pullInFilterBar
                .frame(height: CapturePanelLayout.pullInBarHeight)
            if showsContextLine {
                pullInContextLine
                    .frame(height: CapturePanelLayout.pullInContextHeight)
            }
            Divider()
            if previewMode {
                previewList
                    .frame(height: policy.listViewportHeight, alignment: .top)
                    .clipped()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            choiceSections
                            if choice.visibleSelectableKeys.isEmpty && !choice.filterText.isEmpty {
                                pullInEmptyState
                            }
                        }
                        .padding(CapturePanelLayout.pullInListPadding)
                    }
                    .frame(height: policy.listViewportHeight)
                    .onChange(of: choice.highlightedKey) { _, key in
                        guard let key else {
                            return
                        }
                        proxy.scrollTo(key, anchor: nil)
                    }
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CapturePanelLayout.pickerCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CapturePanelLayout.pickerCornerRadius)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Successor offer choices")
        .focusable()
        .focusEffectDisabled()
        .onAppear {
            postAnnouncement("Choose successor offers, \(choice.countText)")
        }
        .onChange(of: choice.highlightedKey) { _, key in
            guard let key,
                let row = choice.rows.first(where: { $0.offerKey == key })
            else {
                return
            }
            postAnnouncement(row.accessibilityLabel)
        }
        .onChange(of: choice.markedKeys) { oldMarks, newMarks in
            if let added = newMarks.subtracting(oldMarks).first,
                let row = choice.rows.first(where: { $0.offerKey == added })
            {
                postAnnouncement("Marked \(row.text)")
            } else if let removed = oldMarks.subtracting(newMarks).first,
                let row = choice.rows.first(where: { $0.offerKey == removed })
            {
                postAnnouncement("Unmarked \(row.text)")
            } else if newMarks.count != oldMarks.count {
                let count = newMarks.count
                postAnnouncement(count == 1 ? "1 marked" : "\(count) marked")
            }
        }
        .onChange(of: choice.visibleSelectableKeys.count) { _, count in
            guard !choice.filterText.isEmpty else {
                return
            }
            postAnnouncement(count == 1 ? "1 match" : "\(count) matches")
        }
    }

    private var showsContextLine: Bool {
        choice.contextText != nil || choice.planBudget != nil
    }

    private func postAnnouncement(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    private var pullInFilterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "lock.open.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Successors")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.background.opacity(0.45), in: Capsule())
            if previewMode {
                Text(choice.filterText.isEmpty ? "Filter offers" : choice.filterText)
                    .font(.system(size: 15))
                    .foregroundStyle(choice.filterText.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                CapturePickerFilterField(
                    text: choice.filterText,
                    placeholder: "Filter offers",
                    accessibilityLabel: "Filter successor offers",
                    focusRequest: model.focusRequest,
                    onTextChange: { model.updatePullInChoiceFilter($0) },
                    fieldIdentifier: pullInFilterFieldAccessibilityIdentifier,
                    focusTarget: .pullInFilter,
                    onFocusChange: { focused in
                        if focused {
                            model.focusPullInChoiceFilter()
                        }
                    }
                )
                .frame(maxWidth: .infinity)
            }
            Text(choice.countText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter successor offers")
    }

    private var pullInContextLine: some View {
        HStack(spacing: 6) {
            if let context = choice.contextText {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(context)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            Spacer(minLength: 8)
            if choice.planBudget != nil,
                let capsule = choice.projectedLinksCapsuleText
            {
                Text(capsule)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (choice.projectedLinksOverCap ? Color.red : Color.green).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(choice.projectedLinksOverCap ? Color.red : Color.green)
                    .contentTransition(.numericText())
                    .animation(snappy(0.15), value: capsule)
                    .accessibilityLabel(projectedLinksAccessibilityLabel)
                if let delta = choice.projectedLinksDeltaText {
                    Text(delta)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(snappy(0.15), value: delta)
                }
            }
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(contextAccessibilityLabel)
    }

    private var projectedLinksAccessibilityLabel: String {
        guard let capsule = choice.projectedLinksCapsuleText,
            let budget = choice.planBudget,
            let projected = choice.projectedLinkCount
        else {
            return choice.projectedLinksCapsuleText ?? ""
        }
        let base = "Projected links \(projected) of \(budget.links.cap)"
        return choice.projectedLinksOverCap ? "Warning: \(base)" : base
    }

    private var contextAccessibilityLabel: String {
        var parts: [String] = []
        if let context = choice.contextText {
            parts.append(context)
        }
        if choice.planBudget != nil {
            parts.append(projectedLinksAccessibilityLabel)
        }
        return parts.joined(separator: ", ")
    }

    private func snappy(_ duration: Double) -> Animation? {
        reduceMotion ? nil : .snappy(duration: duration)
    }

    private var choiceSections: some View {
        ForEach(choice.sections) { section in
            Section {
                if let foldText = foldText(for: section) {
                    Text(foldText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: CapturePanelLayout.pullInFoldRowHeight)
                        .padding(.horizontal, 8)
                        .padding(.leading, 22)
                        .help(foldText)
                }
                ForEach(choice.visibleRows(in: section)) { row in
                    if let key = row.offerKey {
                        Button {
                            model.togglePullInOffer(key)
                        } label: {
                            CapturePullInOfferRow(
                                choice: choice,
                                row: row,
                                isHighlighted: choice.highlightedKey == key,
                                isMarked: choice.markedKeys.contains(key)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(key)
                    } else {
                        CapturePullInMutedRow(row: row)
                    }
                }
                if previewMode && choice.visibleRows(in: section).isEmpty && choice.filterText.isEmpty {
                    EmptyView()
                }
            } header: {
                CapturePullInSectionHeader(
                    choice: choice,
                    section: section,
                    isCollapsed: choice.collapsedGroups.contains(section.id) && choice.filterText.isEmpty,
                    marked: choice.markedCount(in: section),
                    onToggle: { model.togglePullInChoiceGroup(section.id) },
                    reduceMotion: reduceMotion
                )
            }
        }
    }

    private var previewList: some View {
        VStack(spacing: 0) {
            ForEach(choice.sections) { section in
                CapturePullInSectionHeader(
                    choice: choice,
                    section: section,
                    isCollapsed: choice.collapsedGroups.contains(section.id) && choice.filterText.isEmpty,
                    marked: choice.markedCount(in: section),
                    onToggle: { model.togglePullInChoiceGroup(section.id) },
                    reduceMotion: reduceMotion
                )
                if let foldText = foldText(for: section) {
                    Text(foldText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: CapturePanelLayout.pullInFoldRowHeight)
                        .padding(.horizontal, 8)
                        .padding(.leading, 22)
                }
                ForEach(choice.visibleRows(in: section)) { row in
                    if row.offerKey != nil {
                        CapturePullInOfferRow(
                            choice: choice,
                            row: row,
                            isHighlighted: choice.highlightedKey == row.offerKey,
                            isMarked: row.offerKey.map { choice.markedKeys.contains($0) } ?? false
                        )
                    } else {
                        CapturePullInMutedRow(row: row)
                    }
                }
            }
            if choice.visibleSelectableKeys.isEmpty && !choice.filterText.isEmpty {
                pullInEmptyState
            }
        }
        .padding(CapturePanelLayout.pullInListPadding)
    }

    private func foldText(for section: CapturePullInChoiceSection) -> String? {
        guard let folded = section.folded else {
            return nil
        }
        var parts: [String] = []
        if folded.hidden > 0 {
            parts.append("\(folded.hidden) hidden")
        }
        if folded.alreadyPlanned > 0 {
            parts.append("\(folded.alreadyPlanned) already planned")
        }
        if folded.subProjects > 0 {
            parts.append("\(folded.subProjects) sub-projects stay blocked until the next reconcile")
        }
        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: " · ")
    }

    private var pullInEmptyState: some View {
        VStack(spacing: 4) {
            Text("No matching offers")
                .font(.headline)
            Text("Clear the filter to see all \(choice.selectableKeys.count) offers.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "No matching offers. Clear the filter to see all \(choice.selectableKeys.count) offers."
        )
    }
}

/// One pinned section header (28pt). Kept as its own view so both the live
/// list and the `previewMode` fixture share it.
@available(macOS 26.0, *)
struct CapturePullInSectionHeader: View {
    let choice: CapturePullInChoiceState
    let section: CapturePullInChoiceSection
    let isCollapsed: Bool
    let marked: Int
    let onToggle: () -> Void
    var reduceMotion = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isCollapsed)
                    .accessibilityHidden(true)
                Image(systemName: glyph)
                    .foregroundStyle(glyphColor)
                    .accessibilityHidden(true)
                Text(section.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(section.rows.filter(\.isSelectable).count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 8)
                if marked > 0 {
                    Text("\(marked) marked")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .monospacedDigit()
                }
            }
            .frame(height: CapturePanelLayout.pullInSectionHeaderHeight)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(section.title), \(section.rows.filter(\.isSelectable).count) offers")
    }

    private var glyph: String {
        switch section.group {
        case "hand_off":
            return "arrow.turn.down.right"
        case "project":
            return "folder"
        case "project_finished":
            return "checkmark.circle"
        default:
            return "lock.open"
        }
    }

    private var glyphColor: Color {
        section.group == "project_finished" ? .green : .secondary
    }
}

/// The 16pt checkbox in the leading column. Kept as its own view so the
/// offer row stays readable.
@available(macOS 26.0, *)
struct CapturePullInCheckbox: View {
    var isMarked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isMarked {
                RoundedRectangle(cornerRadius: 4.5)
                    .fill(Color.accentColor)
                    .frame(width: 16, height: 16)
            } else {
                RoundedRectangle(cornerRadius: 4.5)
                    .fill(.background.opacity(0.5))
                    .frame(width: 16, height: 16)
                RoundedRectangle(cornerRadius: 4.5)
                    .strokeBorder(Color.secondary, lineWidth: 1.25)
                    .frame(width: 16, height: 16)
            }
            if isMarked {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 22, height: 22)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isMarked)
        .accessibilityHidden(true)
    }
}

/// The trailing destination capsule. Kept as its own small view so the
/// per-row destination retarget (bob-cli-7j) can show `→ NAME` overrides
/// here.
@available(macOS 26.0, *)
struct CapturePullInDestinationCapsule: View {
    var text: String
    var isEffective: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(isEffective ? .green : .secondary)
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isEffective)
    }
}

/// One 44pt two-line offer row, after the Refs rows.
@available(macOS 26.0, *)
struct CapturePullInOfferRow: View {
    let choice: CapturePullInChoiceState
    let row: CapturePullInChoiceRow
    var isHighlighted = false
    var isMarked = false
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    private var isEffective: Bool {
        guard let key = row.offerKey else {
            return false
        }
        return choice.isEffectivelySelected(key)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            CapturePullInCheckbox(isMarked: isMarked)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(titleRichText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Spacer(minLength: 6)
                    if let destination = row.destinationText {
                        CapturePullInDestinationCapsule(
                            text: destination,
                            isEffective: isEffective
                        )
                    }
                }
                metaLine
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CapturePanelLayout.pullInRowHeight)
        .padding(.horizontal, 8)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }

    private var titleRichText: AttributedString {
        let display = TaskDisplayText(parsing: row.text)
        let matches: [Range<Int>]
        if let match = choice.filterMatchRange(in: display.text) {
            matches = [match]
        } else {
            matches = []
        }
        return CapturePickerRichText.displayText(
            display.text,
            segments: display.segments,
            matches: matches
        )
    }

    private var metaParts: [(text: String, tint: Color?)] {
        var parts: [(text: String, tint: Color?)] = []
        if let number = row.offerNumber {
            parts.append(("Offer \(number)", nil))
        }
        let locator = row.notePath + (row.blockID.isEmpty ? "" : " ^\(row.blockID)")
        if !locator.isEmpty {
            parts.append((locator, nil))
        }
        if row.needsBlockID {
            parts.append(("adds ^id", CaptureEditorPalette.color(for: .blockID)))
        }
        for detail in row.metaDetails {
            parts.append((detail, nil))
        }
        if choice.showsRowCauses,
            let cause = row.offerRow?.unblockedBy.first,
            !cause.text.isEmpty
        {
            parts.append(("from \(SuccessorRows.truncate(cause.text))", nil))
        }
        return parts
    }

    private var metaLine: Text {
        metaParts.enumerated().reduce(Text("")) { result, entry in
            let separator = entry.offset == 0 ? "" : " · "
            let chunk = Text("\(separator)\(entry.element.text)")
                .foregroundStyle(entry.element.tint ?? .secondary)
            return result + chunk
        }
    }

    private var rowBackground: Color {
        if isHighlighted {
            return Color.accentColor.opacity(contrast == .increased ? 0.30 : 0.16)
        }
        if isHovered {
            return Color.primary.opacity(contrast == .increased ? 0.12 : 0.06)
        }
        return .clear
    }

    private var accessibilityLabel: String {
        var label = row.accessibilityLabel
        if let key = row.offerKey {
            if choice.markedKeys.contains(key) {
                label += ", marked"
            } else if choice.isEffectivelySelected(key) {
                label += ", will be pulled in"
            }
        }
        return label
    }
}

/// One 44pt muted resident row: it stays blocked, so it has no capsule,
/// no hover, and no button.
@available(macOS 26.0, *)
struct CapturePullInMutedRow: View {
    let row: CapturePullInChoiceRow

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(mutedMeta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CapturePanelLayout.pullInRowHeight)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var mutedMeta: String {
        var parts: [String] = []
        if let detail = row.detailText, !detail.isEmpty {
            parts.append(detail)
        }
        let locator = row.notePath + (row.blockID.isEmpty ? "" : " ^\(row.blockID)")
        if !locator.isEmpty {
            parts.append(locator)
        }
        return parts.joined(separator: " · ")
    }
}

/// Button style for the footer's Skip / Pull In actions.
@available(macOS 26.0, *)
struct CapturePullInActionButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.label
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(prominent ? .white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            prominent ? Color.accentColor : Color.primary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : 0.45))
    }
}

/// Footer shown while the choice card is open. It replaces
/// `CapturePanelFooter` so the panel's buttons do not sit dead under the
/// card: the left holds keycap hints, the right holds Skip / Pull In.
@available(macOS 26.0, *)
struct CapturePullInChoiceFooter: View {
    @ObservedObject var model: CapturePanelModel

    /// Keycap plus action pairs, in display order. Kept static so tests can
    /// assert the documented keyboard contract without rendering.
    static let hintItems: [(keys: String, action: String)] = [
        ("⌃N ⌃P", "Move"),
        ("space", "Mark"),
        ("⌘A", "All"),
        ("esc", "Back"),
    ]

    static let accessibilityText =
        "Up, Down, Control-N, or Control-P moves the highlight. Space marks the highlighted offer. Command-A marks every offer. Return pulls in the marked offers, or the highlighted offer when none are marked. Shift-Return skips pulling in any offer. Escape goes back to the draft without writing."

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                hintRow(items: Self.hintItems)
                hintRow(items: Array(Self.hintItems.dropLast()))
                hintRow(items: Array(Self.hintItems.prefix(2)))
            }
            Spacer(minLength: 12)
            Button {
                model.chooseNoPullInOffers()
            } label: {
                HStack(spacing: 4) {
                    Text("Skip")
                    Text("⇧↩")
                        .opacity(0.7)
                }
            }
            .buttonStyle(CapturePullInActionButtonStyle(prominent: false))
            .disabled(model.isSubmitting)
            Button {
                model.confirmPullInChoice()
            } label: {
                HStack(spacing: 4) {
                    Text(pullInTitle)
                        .contentTransition(.numericText())
                    Text("↩")
                        .opacity(0.7)
                }
            }
            .buttonStyle(CapturePullInActionButtonStyle(prominent: true))
            .disabled(model.isSubmitting || pullInCount == 0)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.accessibilityText)
        .onChange(of: model.statusAnnouncementTick) { _, _ in
            guard !model.statusText.isEmpty else {
                return
            }
            AccessibilityNotification.Announcement(model.statusText).post()
        }
    }

    private var pullInCount: Int {
        model.pullInChoice?.effectivePickCount ?? 0
    }

    private var pullInTitle: String {
        model.pullInChoice?.pullInActionTitle ?? "Pull In"
    }

    private func hintRow(items: [(keys: String, action: String)]) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<items.count, id: \.self) { index in
                HStack(spacing: 4) {
                    Text(items[index].keys)
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
                    Text(items[index].action)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
