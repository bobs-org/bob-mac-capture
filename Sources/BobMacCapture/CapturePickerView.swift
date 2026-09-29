import CaptureCore
import SwiftUI

/// Layout constants for the capture picker card. They live on
/// `CapturePanelLayout` so the card, the height policy, and the panel metrics
/// share one source of truth.
extension CapturePanelLayout {
    /// Height of the filter bar (scope token, filter field, count).
    static let pickerFilterBarHeight: CGFloat = 46
    /// Fixed height of one picker row.
    static let pickerRowHeight: CGFloat = 34
    /// Fixed height of one section header.
    static let pickerSectionHeaderHeight: CGFloat = 26
    /// Fixed height of the detail strip.
    static let pickerDetailStripHeight: CGFloat = 80
    /// Padding inside the scrollable list.
    static let pickerListPadding: CGFloat = 6
    /// Visible-row budget bounds. The presentation clamps the grouped
    /// rows-plus-headers count into this range once at open; filtering never
    /// resizes the panel.
    static let pickerMaxRows = 11
    static let pickerMinRows = 3
    /// Corner radius of the picker card.
    static let pickerCornerRadius: CGFloat = 12
}

/// Fixed-height sizing policy for the capture picker card. The budget is
/// fixed at open from the grouped presentation, so filtering never resizes
/// the panel. On short screens the card shrinks to its minimum (filter bar,
/// up to three rows, detail strip) and the list scrolls.
struct CapturePickerHeightPolicy: Equatable {
    var visibleRowBudget: Int
    var displayScale: CGFloat = 1

    /// The budget clamped to the card's row bounds.
    var clampedBudget: Int {
        min(max(visibleRowBudget, 1), CapturePanelLayout.pickerMaxRows)
    }

    /// Rows kept visible in the minimum (short-screen) height.
    var minimumRowCount: Int {
        min(CapturePanelLayout.pickerMinRows, clampedBudget)
    }

    private func listViewportHeight(forRowCount rows: Int) -> CGFloat {
        roundedToPixel(
            CapturePanelLayout.pickerListPadding * 2
                + CapturePanelLayout.pickerRowHeight * CGFloat(rows)
        )
    }

    var listViewportHeight: CGFloat {
        listViewportHeight(forRowCount: clampedBudget)
    }

    var idealHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.pickerFilterBarHeight
                + 1
                + listViewportHeight
                + 1
                + CapturePanelLayout.pickerDetailStripHeight
        )
    }

    var minimumVisibleHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.pickerFilterBarHeight
                + 1
                + listViewportHeight(forRowCount: minimumRowCount)
                + 1
                + CapturePanelLayout.pickerDetailStripHeight
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

/// Builds the picker's rich text: per-segment styling (monospaced plus a faint
/// fill for code, accent tint for links) with semibold plus accent overlaid on
/// the fuzzy-match ranges.
enum CapturePickerRichText {
    static func displayText(
        _ text: String,
        segments: [TaskDisplaySegment],
        matches: [Range<Int>]
    ) -> AttributedString {
        let chars = Array(text)
        let matchedOffsets = Set(matches.flatMap { $0 })
        var result = AttributedString()
        let tiling: [TaskDisplaySegment]
        if segments.isEmpty, !chars.isEmpty {
            tiling = [TaskDisplaySegment(kind: .plain, range: 0..<chars.count)]
        } else {
            tiling = segments
        }
        for segment in tiling {
            let lower = max(segment.range.lowerBound, 0)
            let upper = min(segment.range.upperBound, chars.count)
            guard lower < upper else {
                continue
            }
            var run = lower
            while run < upper {
                let isMatch = matchedOffsets.contains(run)
                var end = run + 1
                while end < upper, matchedOffsets.contains(end) == isMatch {
                    end += 1
                }
                var part = AttributedString(String(chars[run..<end]))
                switch segment.kind {
                case .plain:
                    break
                case .code:
                    part.font = .system(.body, design: .monospaced)
                    part.backgroundColor = Color.primary.opacity(0.08)
                case .link:
                    part.foregroundColor = .accentColor
                }
                if isMatch {
                    part.inlinePresentationIntent = .stronglyEmphasized
                    part.foregroundColor = .accentColor
                }
                result += part
                run = end
            }
        }
        return result
    }
}

/// The final capture picker card: filter bar, pinned section headers, rich
/// rows, detail strip, and warning states in one large elevated card that
/// spans the full auxiliary width. Renders any `CapturePickerPresentation`;
/// the open source supplies its strings through `CapturePickerSource`.
@available(macOS 26.0, *)
struct CapturePickerCard: View {
    @ObservedObject var model: CapturePanelModel
    @Environment(\.displayScale) private var displayScale

    private var budget: Int {
        model.picker?.visibleRowBudget ?? 4
    }

    private var policy: CapturePickerHeightPolicy {
        CapturePickerHeightPolicy(visibleRowBudget: budget, displayScale: displayScale)
    }

    private var presentation: CapturePickerPresentation? {
        model.pickerPresentation
    }

    private var source: CapturePickerSource {
        model.picker?.source ?? .activeTask
    }

    var body: some View {
        VStack(spacing: 0) {
            CapturePickerFilterBar(model: model)
                .frame(height: CapturePanelLayout.pickerFilterBarHeight)

            Divider()

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if let presentation {
                            ForEach(presentation.sections, id: \.id) { section in
                                Section {
                                    ForEach(section.rows, id: \.id) { row in
                                        CapturePickerRowView(
                                            model: model,
                                            row: row,
                                            showsChip: presentation.mode == .filtered
                                        )
                                        .id(row.id)
                                    }
                                } header: {
                                    if section.kind != .matches {
                                        CapturePickerSectionHeader(section: section)
                                    }
                                }
                            }
                        }
                        if let emptyState = presentation?.emptyState {
                            CapturePickerEmptyStateView(emptyState: emptyState)
                                .padding(.vertical, 24)
                        }
                        listFooter
                    }
                    .padding(CapturePanelLayout.pickerListPadding)
                }
                .frame(height: policy.listViewportHeight)
                .onChange(of: model.picker?.selectedRowID) { _, selectedID in
                    if let selectedID {
                        proxy.scrollTo(selectedID, anchor: nil)
                    }
                }
            }

            Divider()

            CapturePickerDetailStrip(model: model)
                .frame(height: CapturePanelLayout.pickerDetailStripHeight, alignment: .top)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CapturePanelLayout.pickerCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CapturePanelLayout.pickerCornerRadius)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(source.cardAccessibilityLabel)
        .accessibilityHint(source.cardAccessibilityHint)
        .onAppear {
            if let presentation {
                postAnnouncement("\(source.appearedAnnouncementPrefix), \(presentation.countText)")
            }
        }
        .onChange(of: presentation?.matchCount) { _, matchCount in
            guard let presentation, presentation.mode == .filtered, let matchCount else {
                return
            }
            postAnnouncement(matchCount == 1 ? "1 match" : "\(matchCount) matches")
        }
        .onChange(of: model.picker?.selectedRowID) { oldID, newID in
            guard oldID != nil,
                  let newID,
                  let row = presentation?.row(id: newID)
            else {
                return
            }
            postAnnouncement(row.accessibilityLabel)
        }
    }

    @ViewBuilder
    private var listFooter: some View {
        let warnings = model.picker?.warnings ?? []
        if let picker = model.picker, picker.snapshotIsPartial {
            Text("Showing Bob's matches only")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 6)
        }
        if let first = warnings.first {
            Text(warnings.count > 1 ? "\(first) (+\(warnings.count - 1) more)" : first)
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 2)
        }
    }

    private func postAnnouncement(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}

/// Filter bar (46pt): scope token capsule, the AppKit-owned filter field, the
/// trailing count, and a spinner only while a snapshot fetch is pending. The
/// placeholder and labels come from the open source.
@available(macOS 26.0, *)
private struct CapturePickerFilterBar: View {
    @ObservedObject var model: CapturePanelModel

    private var source: CapturePickerSource {
        model.picker?.source ?? .activeTask
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(source.scopeSymbolText)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(CaptureEditorPalette.color(for: .route))
                Text(source.scopeCaption)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.background.opacity(0.45), in: Capsule())

            CapturePickerFilterField(
                text: model.picker?.filterText ?? "",
                placeholder: source.filterPlaceholder,
                accessibilityLabel: source.filterAccessibilityLabel,
                focusRequest: model.focusRequest,
                onTextChange: { model.updatePickerFilter($0) }
            )
            .frame(maxWidth: .infinity)

            if model.picker != nil, model.pickerPresentation == nil {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.pickerPresentation?.countText ?? "")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(source.filterAccessibilityLabel)
    }
}

/// One pinned section header (26pt): ordinal, title, formatted time range,
/// pink NOW pill, and task count. Unqueued buckets carry a
/// "Not in a Pomodoro" subtitle inline.
@available(macOS 26.0, *)
private struct CapturePickerSectionHeader: View {
    let section: CapturePickerSection

    var body: some View {
        HStack(spacing: 6) {
            if section.ordinal > 0 {
                Text("\(section.ordinal)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(section.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if let timeRangeText = section.timeRangeText {
                Text(timeRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if section.isCurrent {
                Text("NOW")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.pink, in: Capsule())
                    .accessibilityLabel("Current Pomodoro")
            }
            if section.kind != .pomodoro {
                Text("Not in a Pomodoro")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(section.countText ?? "\(section.rows.count) task\(section.rows.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(height: CapturePanelLayout.pickerSectionHeaderHeight)
        .padding(.horizontal, 8)
        .background(.regularMaterial)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One picker row (34pt, single line): status glyph, rich display text with
/// match highlights, an optional chip in filtered mode, and the locator. A
/// tap selects and inserts. Informational rows render without the button.
@available(macOS 26.0, *)
private struct CapturePickerRowView: View {
    @ObservedObject var model: CapturePanelModel
    let row: CapturePickerRow
    var showsChip: Bool = false
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    private var isSelected: Bool {
        model.picker?.selectedRowID == row.id
    }

    var body: some View {
        Group {
            if row.isSelectable {
                Button {
                    model.selectPickerRow(id: row.id)
                    CapturePickerUsageDidInsert(source: model.picker?.source ?? .activeTask)
                    model.acceptPickerRow(id: row.id, submitAfterInsert: false)
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction {
                    model.acceptPickerRow(id: row.id, submitAfterInsert: false)
                }
            } else {
                rowContent
            }
        }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Image(systemName: statusStyle.symbol)
                .foregroundStyle(statusStyle.color)
                .frame(width: 16)
            Text(displayRichText)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if showsChip, let chip = row.chipText {
                Text(chip)
                    .font(.caption2)
                    .foregroundStyle(.pink)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.pink.opacity(0.12), in: Capsule())
            }
            if let badge = row.badgeText {
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.background.opacity(0.6), in: Capsule())
            }
            Spacer(minLength: 8)
            locatorText
                .frame(maxWidth: 260, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CapturePanelLayout.pickerRowHeight)
        .padding(.horizontal, 8)
        .padding(.leading, CGFloat(min(row.depth, 2)) * 14)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var statusStyle: (symbol: String, color: Color) {
        switch row.glyph {
        case .task(let status):
            return CaptureEditorPalette.taskStatus(status)
        case .anchor, .newID, .alternativeID, .suggestion:
            return ("circle.dashed", .secondary)
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(contrast == .increased ? 0.30 : 0.16)
        }
        if isHovered {
            return Color.primary.opacity(contrast == .increased ? 0.12 : 0.06)
        }
        return .clear
    }

    private var displayRichText: AttributedString {
        CapturePickerRichText.displayText(
            row.displayText,
            segments: row.textSegments,
            matches: row.textMatchRanges
        )
    }

    private var locatorText: some View {
        HStack(spacing: 0) {
            if let route = row.route {
                Text(CapturePickerRichText.displayText(
                    route,
                    segments: [],
                    matches: row.routeMatchRanges
                ))
                .foregroundStyle(CaptureEditorPalette.color(for: .route))
            }
            if row.route != nil, row.blockID != nil {
                Text(":")
                    .foregroundStyle(.secondary)
            }
            if let blockID = row.blockID {
                Text(CapturePickerRichText.displayText(
                    blockID,
                    segments: [],
                    matches: row.blockIDMatchRanges
                ))
                .foregroundStyle(CaptureEditorPalette.color(for: .blockID))
            }
        }
        .font(.caption.monospaced())
        .lineLimit(1)
        .truncationMode(.middle)
    }
}

/// Detail strip (80pt) for the selected row: full text wrapped to two lines,
/// a metadata line, and the insert hint. With no selection it shows the
/// empty-state guidance.
@available(macOS 26.0, *)
private struct CapturePickerDetailStrip: View {
    @ObservedObject var model: CapturePanelModel
    @AppStorage("org.bobs.bob-mac-capture.active-task-picker-used") private var pickerWasUsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let row = model.selectedPickerRow {
                Text(detailRichText(for: row))
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    metadataText(for: row)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    insertionText(for: row)
                        .font(.caption)
                        .lineLimit(1)
                }
                if pickerWasUsed {
                    Text("Then type #name, = to start, or =x to close")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if let emptyState = model.pickerPresentation?.emptyState {
                Text(emptyState.title)
                    .font(.callout.weight(.semibold))
                Text(emptyState.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func detailRichText(for row: CapturePickerRow) -> AttributedString {
        CapturePickerRichText.displayText(
            row.displayText,
            segments: row.textSegments,
            matches: row.textMatchRanges
        )
    }

    private func metadataText(for row: CapturePickerRow) -> Text {
        var metadata = Text(row.detail.statusText)
        let (label, icon) = noteLabel(for: row.detail.route)
        if !label.isEmpty {
            metadata = metadata + Text(" · ") + Text(Image(systemName: icon)) + Text(" \(label)")
        }
        if let section = row.detail.section, !section.isEmpty {
            metadata = metadata + Text(" › \(section)")
        }
        return metadata + Text(" · \(row.detail.summary)")
    }

    /// Note kind icon plus label from the capture-targets cache, falling back
    /// to `route.md` with a generic icon.
    private func noteLabel(for route: String?) -> (label: String, icon: String) {
        guard let route, !route.isEmpty else {
            return ("", "doc")
        }
        if let target = model.targetCacheSnapshot.targets?.targets.first(where: { $0.route == route }) {
            return (target.label, noteKindIcon(for: target.kind))
        }
        return ("\(route).md", "doc")
    }

    private func noteKindIcon(for kind: String) -> String {
        switch kind {
        case "inbox":
            return "tray"
        case "area":
            return "square.stack"
        case "project":
            return "folder"
        default:
            return "doc"
        }
    }

    private func insertionText(for row: CapturePickerRow) -> Text {
        Text("↩ inserts ") .foregroundColor(.secondary)
            + Text(row.detail.insertionPrefix).foregroundColor(.primary)
            + locatorInsertionText(for: row)
    }

    private func locatorInsertionText(for row: CapturePickerRow) -> Text {
        var text = Text("")
        if let route = row.route {
            text = text + Text(route).foregroundColor(CaptureEditorPalette.color(for: .route))
        }
        if row.route != nil, row.blockID != nil {
            text = text + Text(":").foregroundColor(.secondary)
        }
        if let blockID = row.blockID {
            text = text + Text(blockID).foregroundColor(CaptureEditorPalette.color(for: .blockID))
        }
        if row.route == nil, row.blockID == nil {
            text = text + Text(row.id).foregroundColor(.primary)
        }
        return text
    }
}

/// Empty states: no active tasks, or no matches for the current filter.
@available(macOS 26.0, *)
private struct CapturePickerEmptyStateView: View {
    let emptyState: CapturePickerEmptyState

    var body: some View {
        VStack(spacing: 4) {
            Text(emptyState.title)
                .font(.headline)
            Text(emptyState.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(emptyState.title). \(emptyState.message)")
    }
}

/// Compact capsule button shown instead of the picker: after a two-stage
/// Escape cancel, after a caret-only move into a picker's token, or while
/// auto-open is suppressed for the token. Label and icon come from the
/// chip's source.
@available(macOS 26.0, *)
struct CapturePickerChip: View {
    @ObservedObject var model: CapturePanelModel

    private var source: CapturePickerSource {
        model.pickerChip?.source ?? .activeTask
    }

    var body: some View {
        Button {
            model.openPickerFromChip()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: source.chipIcon)
                Text(source.chipLabel)
                Text("⇥")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(source.chipHelp)
        .accessibilityLabel(source.chipAccessibilityLabel)
        .accessibilityHint(source.chipAccessibilityHint)
    }
}

/// Footer key hints shown while the picker is open, at the same footer height
/// path so panel metrics keep working. Items come from the open source.
@available(macOS 26.0, *)
struct CapturePickerKeyHints: View {
    var source: CapturePickerSource = .activeTask

    /// Keycap plus action pairs, in display order. Kept static so tests can
    /// assert the documented keyboard contract without rendering.
    static func items(for source: CapturePickerSource) -> [(keys: String, action: String)] {
        source.keyHintItems()
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<Self.items(for: source).count, id: \.self) { index in
                let item = Self.items(for: source)[index]
                HStack(spacing: 4) {
                    Text(item.keys)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                    Text(item.action)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(source.keyHintsAccessibilityLabel)
    }
}

/// Records a view-driven insert so the detail strip can teach follow-up
/// keystrokes after the first use.
@available(macOS 26.0, *)
private func CapturePickerUsageDidInsert(source: CapturePickerSource) {
    UserDefaults.standard.set(true, forKey: source.pickerUsedDefaultsKey)
}
