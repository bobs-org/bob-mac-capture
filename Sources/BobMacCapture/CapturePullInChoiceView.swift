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
    static let pullInKeepMovingHeaderHeight: CGFloat = 48
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
    var captionSectionCount: Int
    var foldRowCount: Int
    var rowCount: Int
    var hasContextLine: Bool
    var displayScale: CGFloat = 1

    init(
        sectionCount: Int,
        foldRowCount: Int,
        rowCount: Int,
        hasContextLine: Bool,
        captionSectionCount: Int = 0,
        displayScale: CGFloat = 1
    ) {
        self.sectionCount = sectionCount
        self.captionSectionCount = captionSectionCount
        self.foldRowCount = foldRowCount
        self.rowCount = rowCount
        self.hasContextLine = hasContextLine
        self.displayScale = displayScale
    }

    init(choice: CapturePullInChoiceState, displayScale: CGFloat = 1) {
        let sections = choice.sections
        let folds = sections.filter { $0.foldText != nil }.count
        let hasContext = choice.contextText != nil || choice.planBudget != nil
        self.init(
            sectionCount: sections.count,
            foldRowCount: folds,
            rowCount: choice.rows.count,
            hasContextLine: hasContext,
            captionSectionCount: sections.filter { $0.caption != nil }.count,
            displayScale: displayScale
        )
    }

    var listContentHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.pullInListPadding * 2
                + CGFloat(sectionCount) * CapturePanelLayout.pullInSectionHeaderHeight
                + CGFloat(captionSectionCount)
                * (CapturePanelLayout.pullInKeepMovingHeaderHeight
                    - CapturePanelLayout.pullInSectionHeaderHeight)
                + CGFloat(foldRowCount) * CapturePanelLayout.pullInFoldRowHeight
                + CGFloat(rowCount) * CapturePanelLayout.pullInRowHeight
        )
    }

    var maxListHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.pullInListPadding * 2
                + CapturePanelLayout.pullInSectionHeaderHeight
                + (captionSectionCount > 0
                    ? CapturePanelLayout.pullInKeepMovingHeaderHeight
                        - CapturePanelLayout.pullInSectionHeaderHeight
                    : 0)
                + CGFloat(CapturePanelLayout.pullInMaxVisibleRows)
                * CapturePanelLayout.pullInRowHeight
        )
    }

    var minListHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.pullInListPadding * 2
                + CapturePanelLayout.pullInSectionHeaderHeight
                + (captionSectionCount > 0
                    ? CapturePanelLayout.pullInKeepMovingHeaderHeight
                        - CapturePanelLayout.pullInSectionHeaderHeight
                    : 0)
                + CGFloat(CapturePanelLayout.pullInMinVisibleRows)
                * CapturePanelLayout.pullInRowHeight
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
            postAnnouncement("\(choice.promptStatusText), \(choice.countText)")
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
                Image(systemName: filterCapsuleGlyph)
                    .foregroundStyle(filterCapsuleColor)
                    .accessibilityHidden(true)
                Text(filterCapsuleTitle)
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

    private var filterCapsuleGlyph: String {
        if let key = choice.authoredCopy?.glyph, !key.isEmpty {
            return CapturePullInGlyph.systemImageName(for: key)
        }
        if choice.isNewProjectPrompt {
            return CapturePullInGlyph.systemImageName(for: "project_created")
        }
        if choice.isOnlyKeepMoving {
            return CapturePullInGlyph.systemImageName(for: "keep_moving")
        }
        if choice.isOnlyNotePull {
            return CapturePullInGlyph.systemImageName(for: "note_pull")
        }
        if choice.isOnlyRelation {
            return CapturePullInGlyph.systemImageName(for: "relation")
        }
        return "lock.open.fill"
    }

    private var filterCapsuleColor: Color {
        if choice.isOnlyRelation
            || choice.authoredCopy?.glyph == "relation"
        {
            return .secondary
        }
        if choice.isNewProjectPrompt {
            return .brown
        }
        return choice.isOnlyKeepMoving || choice.isOnlyNotePull
            ? CaptureEditorPalette.checkboxSymbolColor("*")
            : .green
    }

    private var filterCapsuleTitle: String {
        if let capsule = choice.authoredCopy?.capsule, !capsule.isEmpty {
            return capsule
        }
        if choice.isNewProjectPrompt {
            return "New project"
        }
        if choice.isOnlyKeepMoving {
            return "Keep moving"
        }
        if choice.isOnlyNotePull {
            return "Pull In"
        }
        if choice.isOnlyRelation {
            return "Starts after"
        }
        return "Successors"
    }

    private var pullInContextLine: some View {
        HStack(spacing: 6) {
            if let context = choice.contextText {
                if !choice.isNewProjectPrompt {
                    Image(
                        systemName: choice.isOnlyKeepMoving
                            ? "forward.end.fill"
                            : "checkmark.circle.fill"
                    )
                    .foregroundStyle(
                        choice.isOnlyKeepMoving
                            ? CaptureEditorPalette.checkboxSymbolColor("*")
                            : .green
                    )
                    .accessibilityHidden(true)
                }
                Text(context)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            Spacer(minLength: 8)
            if let today = choice.projectedTodayBadge {
                TodayBadge(
                    presentation: today,
                    accessibilityLabel: projectedLinksAccessibilityLabel
                )
                if let delta = choice.projectedLinksDeltaText {
                    TodayBadgeDeltaChip(text: delta)
                }
            }
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(contextAccessibilityLabel)
    }

    private var projectedLinksAccessibilityLabel: String {
        guard let budget = choice.planBudget,
            let projected = choice.projectedLinkCount
        else {
            return ""
        }
        let base = "Projected links \(projected) of \(budget.links.cap)"
        let warning = choice.projectedLinksOverCap ? "Warning: " : ""
        let atCap = choice.projectedTodayBadge?.tone == .magenta ? ", at cap" : ""
        return "\(warning)\(base)\(atCap)"
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

    private var choiceSections: some View {
        ForEach(choice.sections) { section in
            Section {
                if let foldText = section.foldText {
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
                        VStack(alignment: .leading, spacing: 2) {
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
                            .contextMenu {
                                if choice.closeSupported,
                                    choice.outcomes.isEligible(.done, for: key)
                                {
                                    Button("Mark Done") {
                                        model.stagePullInDoneForRow(key)
                                    }
                                    Button("Mark Cancelled…") {
                                        model.beginPullInCancelForRow(key)
                                    }
                                }
                                Button("Pull In") {
                                    model.togglePullInOffer(key)
                                }
                                if choice.verdicts[key] != nil {
                                    Button("Leave") {
                                        model.clearPullInVerdictForRow(key)
                                    }
                                }
                            }
                            .accessibilityAction(named: "Mark Done") {
                                model.stagePullInDoneForRow(key)
                            }
                            .accessibilityAction(named: "Mark Cancelled…") {
                                model.beginPullInCancelForRow(key)
                            }
                            .accessibilityAction(named: "Pull In") {
                                model.togglePullInOffer(key)
                            }
                            .accessibilityAction(named: "Leave") {
                                model.clearPullInVerdictForRow(key)
                            }
                            if choice.activeReasonKey == key {
                                CapturePullInReasonField(
                                    model: model,
                                    choice: choice,
                                    rowKey: key)
                            }
                        }
                    } else {
                        CapturePullInMutedRow(row: row)
                    }
                }
                if previewMode && choice.visibleRows(in: section).isEmpty
                    && choice.filterText.isEmpty
                {
                    EmptyView()
                }
            } header: {
                CapturePullInSectionHeader(
                    choice: choice,
                    section: section,
                    isCollapsed: choice.collapsedGroups.contains(section.id)
                        && choice.filterText.isEmpty,
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
                    isCollapsed: choice.collapsedGroups.contains(section.id)
                        && choice.filterText.isEmpty,
                    marked: choice.markedCount(in: section),
                    onToggle: { model.togglePullInChoiceGroup(section.id) },
                    reduceMotion: reduceMotion
                )
                if let foldText = section.foldText {
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
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isCollapsed)
                        .accessibilityHidden(true)
                    Image(systemName: section.glyph)
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
                    if let tag = section.contrastTag {
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(glyphColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if let caption = section.caption {
                    HStack(spacing: 6) {
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                    }
                    .padding(.leading, 42)
                }
            }
        }
        .frame(
            height: section.caption == nil
                ? CapturePanelLayout.pullInSectionHeaderHeight
                : CapturePanelLayout.pullInKeepMovingHeaderHeight
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .background(.regularMaterial)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(
            [
                section.title,
                "\(section.rows.filter(\.isSelectable).count) offers",
                section.caption,
                section.contrastTag,
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
    }

    private var glyphColor: Color {
        if section.isNewProject {
            return .brown
        }
        if section.isKeepMoving || section.isNotePull {
            return CaptureEditorPalette.checkboxSymbolColor("*")
        }
        if section.isRelation {
            return .secondary
        }
        return section.group == "project_finished" ? .green : .secondary
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

/// One 44pt two-line offer row, after the Refs rows. Verdict rows reuse
/// relation complete/cancel symbols and palette; colour is never the only
/// signal because the glyph and words always carry the verdict.
@available(macOS 26.0, *)
struct CapturePullInOfferRow: View {
    let choice: CapturePullInChoiceState
    let row: CapturePullInChoiceRow
    var isHighlighted = false
    var isMarked = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var offerKey: String? {
        row.offerKey
    }

    private var verdict: CapturePullInOfferVerdict? {
        offerKey.flatMap { choice.verdicts[$0] }
    }

    private var isDone: Bool {
        verdict == .done
    }

    private var isCancelled: Bool {
        if case .cancel = verdict {
            return true
        }
        return false
    }

    private var isEffective: Bool {
        guard let key = row.offerKey else {
            return false
        }
        return choice.isEffectivelySelected(key)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            verdictMarkSlot
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(titleRichText)
                        .font(.body)
                        .foregroundStyle(verdict == nil ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Spacer(minLength: 6)
                    trailingCapsule
                }
                metaLine
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let cancelDetail = cancelDetailText {
                    Text(cancelDetail.text)
                        .font(.caption)
                        .foregroundStyle(cancelDetail.faint ? .tertiary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
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

    @ViewBuilder
    private var verdictMarkSlot: some View {
        if isDone {
            Image(systemName: RelationSourceEffect.complete.symbolName)
                .foregroundStyle(CaptureEditorPalette.color(for: .relationCompleteLabel))
                .frame(width: 22, height: 22)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isDone)
                .accessibilityHidden(true)
        } else if isCancelled {
            Image(systemName: RelationSourceEffect.cancel.symbolName)
                .foregroundStyle(CaptureEditorPalette.color(for: .relationCancelLabel))
                .frame(width: 22, height: 22)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isCancelled)
                .accessibilityHidden(true)
        } else {
            CapturePullInCheckbox(isMarked: isMarked)
        }
    }

    @ViewBuilder
    private var trailingCapsule: some View {
        if isDone {
            Text("✓ Done")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
                .foregroundStyle(CaptureEditorPalette.color(for: .relationCompleteLabel))
                .transition(.opacity)
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.15), value: isDone)
        } else if isCancelled {
            Text("⊘ Cancel")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
                .foregroundStyle(CaptureEditorPalette.color(for: .relationCancelLabel))
                .transition(.opacity)
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.15), value: isCancelled)
        } else if let destination = row.destinationText {
            CapturePullInDestinationCapsule(
                text: destination,
                isEffective: isEffective
            )
        }
    }

    private var cancelDetailText: (text: String, faint: Bool)? {
        guard let key = offerKey, case .cancel(let reason) = verdict else {
            return nil
        }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ("no reason", true)
        }
        return ("“\(trimmed)”", false)
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
        if row.isKeepMoving || row.isNotePull || row.isRelation, let lane = row.laneText {
            parts.append((lane, nil))
        }
        if !row.isKeepMoving,
            !row.isRelation,
            choice.showsRowCauses,
            let cause = row.offerRow?.unblockedBy.first,
            !cause.text.isEmpty
        {
            parts.append(("from \(SuccessorRows.truncate(cause.text))", nil))
        }
        if verdict == nil, let key = offerKey {
            let unblocks = choice.outcomes.unblocksCount(for: key)
            if unblocks > 0 {
                parts.append((
                    unblocks == 1 ? "unblocks 1" : "unblocks \(unblocks)",
                    nil))
            }
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
            if case .done = verdict {
                label += ", will be completed"
            } else if case .cancel(let reason) = verdict {
                let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    label += ", will be cancelled, no reason"
                } else {
                    label += ", will be cancelled: \(trimmed)"
                }
            } else if choice.markedKeys.contains(key) {
                label += ", marked"
            } else if choice.isEffectivelySelected(key) {
                label += ", will be pulled in"
            }
            if let why = choice.refusalReason(for: key),
                !choice.isCloseEligible(key)
            {
                label += ", \(why)"
            }
        }
        return label
    }
}

/// Inline Cancel reason field. It lives outside the row's toggle Button
/// hit target so text interaction never toggles Pull In.
@available(macOS 26.0, *)
struct CapturePullInReasonField: View {
    @ObservedObject var model: CapturePanelModel
    let choice: CapturePullInChoiceState
    let rowKey: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Text("⊘ Why cancel?")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                "Why cancel? (optional)",
                text: Binding(
                    get: { choice.activeReasonText },
                    set: { model.updatePullInReasonText($0) }))
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .onSubmit {
                model.confirmPullInReason()
            }
            .accessibilityIdentifier(pullInReasonFieldAccessibilityIdentifier)
            .accessibilityLabel("Why cancel? optional reason")
            Text("↵ · Esc back")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .padding(.leading, 30)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: choice.activeReasonKey)
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
/// card: the consequence strip sits above the hints, the left holds keycap
/// hints, the right holds Skip / Pull In / Close.
@available(macOS 26.0, *)
struct CapturePullInChoiceFooter: View {
    @ObservedObject var model: CapturePanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Keycap plus action pairs, in display order. Kept static so tests can
    /// assert the documented keyboard contract without rendering.
    static let hintItems: [(keys: String, action: String)] = [
        ("⌃N ⌃P", "Move"),
        ("space", "Mark"),
        ("⌘A", "All"),
        ("⌃X", "Done"),
        ("⌃⇧X", "Cancel"),
        ("esc", "Back"),
        ("⌃↩", "Pull In & Open"),
    ]

    static func hintItems(openAfterCapture: Bool, closeSupported: Bool = false) -> [(
        keys: String, action: String
    )] {
        var items = hintItems
        if !closeSupported {
            items.removeAll { $0.keys == "⌃X" || $0.keys == "⌃⇧X" }
        }
        if openAfterCapture {
            return Array(items.dropLast())
        }
        return items
    }

    static let accessibilityText =
        "Up, Down, Control-N, or Control-P moves the highlight. Space marks the highlighted offer. Command-A marks every offer. Control-X stages Done, Control-Shift-X stages Cancel with an optional reason. Return applies every staged choice. Shift-Return skips pull-ins and applies verdicts. Control-Return applies everything and opens the reported notes. Escape needs two presses while verdicts are staged."

    static let openIntentAccessibilityText =
        "Up, Down, Control-N, or Control-P moves the highlight. Space marks the highlighted offer. Command-A marks every offer. Control-X stages Done, Control-Shift-X stages Cancel with an optional reason. Return applies every staged choice, then opens the reported notes. Shift-Return skips pull-ins and applies verdicts. Escape needs two presses while verdicts are staged."

    private var openAfterCapture: Bool {
        model.pullInChoice?.openAfterCapture == true
    }

    private var isOnlyNotePull: Bool {
        model.pullInChoice?.isOnlyNotePull == true
    }

    private var closeSupported: Bool {
        model.pullInChoice?.closeSupported == true
    }

    private var hasVerdicts: Bool {
        (model.pullInChoice?.closeCount ?? 0) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let strip = verdictStripText {
                Text(strip.text)
                    .font(.caption)
                    .foregroundStyle(strip.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity)
                    .animation(
                        reduceMotion ? nil : .snappy(duration: 0.15),
                        value: strip.text)
                    .accessibilityAddTraits(.isStaticText)
            }
            HStack(alignment: .center, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    hintRow(
                        items: Self.hintItems(
                            openAfterCapture: openAfterCapture,
                            closeSupported: closeSupported))
                    hintRow(
                        items: Array(
                            Self.hintItems(
                                openAfterCapture: openAfterCapture,
                                closeSupported: closeSupported
                            ).filter { $0.keys != "⌃↩" }))
                    hintRow(
                        items: Array(
                            Self.hintItems(
                                openAfterCapture: true,
                                closeSupported: closeSupported
                            ).dropLast()))
                    hintRow(
                        items: Array(
                            Self.hintItems(
                                openAfterCapture: true,
                                closeSupported: closeSupported
                            ).prefix(2)))
                }
                Spacer(minLength: 12)
                Text(model.pullInChoice?.footerSummaryText ?? "Choose offers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if isOnlyNotePull, !hasVerdicts {
                    Text("⇧↩ Back to draft")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        model.chooseNoPullInOffers()
                    } label: {
                        HStack(spacing: 4) {
                            Text(skipTitle)
                            if openAfterCapture {
                                Image(systemName: "arrow.up.forward")
                            }
                            Text("⇧↩")
                                .opacity(0.7)
                        }
                    }
                    .buttonStyle(CapturePullInActionButtonStyle(prominent: false))
                    .disabled(model.isSubmitting)
                }
                Button {
                    model.confirmPullInChoice()
                } label: {
                    HStack(spacing: 4) {
                        Text(pullInTitle)
                            .contentTransition(.numericText())
                        if openAfterCapture {
                            Image(systemName: "arrow.up.forward")
                        }
                        Text("↩")
                            .opacity(0.7)
                    }
                }
                .buttonStyle(CapturePullInActionButtonStyle(prominent: true))
                .disabled(model.isSubmitting || !canCommit)
            }
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            isOnlyNotePull && !hasVerdicts
                ? "Shift-Return returns to the draft. Escape returns to the draft without writing."
                : openAfterCapture ? Self.openIntentAccessibilityText : Self.accessibilityText
        )
        .onChange(of: model.statusAnnouncementTick) { _, _ in
            guard !model.statusText.isEmpty else {
                return
            }
            AccessibilityNotification.Announcement(model.statusText).post()
        }
    }

    private var verdictStripText: (text: String, color: Color)? {
        guard let choice = model.pullInChoice else {
            return nil
        }
        if let armed = choice.outcomes.escArmedText {
            return (armed, .yellow)
        }
        if let refusal = choice.verdictRefusalMessage ?? choice.errorMessage,
            !refusal.isEmpty,
            hasVerdicts || choice.activeReasonKey != nil
        {
            return (refusal, .red)
        }
        if let message = choice.consequenceMessage, !message.isEmpty {
            return (message, .secondary)
        }
        return nil
    }

    private var canCommit: Bool {
        model.pullInChoice?.canCommit ?? false
    }

    private var pullInTitle: String {
        model.pullInChoice?.primaryCommitLabel ?? "Pull In"
    }

    private var skipTitle: String {
        model.pullInChoice?.skipCommitLabel ?? "Skip"
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
