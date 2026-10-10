import AppKit
import CaptureCore
import SwiftUI

/// Idle-agenda views: the agenda pane renders `CaptureAgendaPlan`
/// rows verbatim. All wording, fold decisions, and row order come
/// from `CaptureAgendaPresentation` and `CaptureAgendaFitPlanner`; the
/// views below never branch on snapshot JSON or folding logic.
///
/// Height contract: every constant comes from
/// `CaptureAgendaLayoutMetrics`, and inter-row gaps live inside the
/// row views (headers and the title take 4 pt below, other rows 2 pt,
/// the strip takes 4 pt above and nothing below). Group containers
/// add half their vertical insets on top and half below, and groups
/// are separated by exactly `groupSpacing`. The rendered stack is
/// therefore identical to the planner's total, which
/// `CaptureAgendaHeightConsistencyTests` proves within 2 pt.
@available(macOS 26.0, *)
struct CaptureAgendaPaneView: View {
    let plan: CaptureAgendaPlan
    let presentation: CaptureAgendaPresentation
    var onExpand: (CaptureAgendaUnitID) -> Void = { _ in }
    var onContentWidthChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        let rows = CaptureAgendaRowsView(
            plan: plan,
            presentation: presentation,
            onExpand: onExpand,
            onContentWidthChange: onContentWidthChange
        )
        Group {
            if plan.overflows {
                ScrollView(.vertical) {
                    rows
                }
                .scrollBounceBehavior(.basedOnSize)
                .mask(
                    LinearGradient(
                        colors: [.black, .black, .black.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .bottomTrailing) {
                    if plan.hiddenCount > 0 {
                        Text("\(plan.hiddenCount) more")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .padding(6)
                    }
                }
                .frame(
                    height: cappedHeight,
                    alignment: .top
                )
            } else {
                rows
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(CGFloat(CaptureAgendaLayoutMetrics.panePadding))
        .background(.thinMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: CGFloat(CaptureAgendaLayoutMetrics.cornerRadius)
            )
        )
    }

    private var cappedHeight: CGFloat {
        let total = CGFloat(plan.totalHeight)
        let budget = CGFloat(plan.budget)
        guard budget > 0 else {
            return total
        }
        return min(total, budget)
    }
}

/// The spacing-exact row stack: title, warning, groups separated by
/// `groupSpacing`, and the strip. No pane chrome, so its fitting size
/// is exactly the planner's total. Group membership is recovered from
/// row kinds (a group header or one-row summary starts a group), and
/// each group's role, insets, and card come from matching its rows
/// against the presentation by value.
@available(macOS 26.0, *)
struct CaptureAgendaRowsView: View {
    let plan: CaptureAgendaPlan
    let presentation: CaptureAgendaPresentation
    var onExpand: (CaptureAgendaUnitID) -> Void = { _ in }
    var onContentWidthChange: (CGFloat) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let targets = CaptureAgendaChipMap.targets(
            presentation: presentation,
            plan: plan
        )
        let blocks = CaptureAgendaSections.make(
            rows: plan.rows,
            presentation: presentation
        )
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .row(let index):
                    CaptureAgendaRowView(
                        row: plan.rows[index],
                        role: .later,
                        expands: CaptureAgendaRowView.showsChip(
                            for: plan.rows[index]
                        ),
                        chipUnit: targets[index],
                        onExpand: onExpand
                    )
                case .group(let group, let indices, let spacerBefore):
                    if spacerBefore {
                        Spacer(minLength: 0)
                            .frame(
                                height: CGFloat(
                                    CaptureAgendaLayoutMetrics.groupSpacing
                                )
                            )
                    }
                    CaptureAgendaGroupView(
                        group: group,
                        rows: indices.map { plan.rows[$0] },
                        targets: targets,
                        baseIndex: indices.first ?? 0,
                        onExpand: onExpand
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // In-place updates cross-fade; height is never animated.
        // Reduce Motion disables the fade.
        .animation(agendaUpdateAnimation, value: plan.rows)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            guard width.isFinite, width > 0 else {
                return
            }
            onContentWidthChange(width)
        }
    }

    private var agendaUpdateAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: CaptureAgendaHold.updateFadeSeconds)
    }
}

/// Row-kind structure of a plan's render list: standalone rows (title,
/// warning, state, strip) stay flat, while a group header or one-row
/// summary starts a group that owns the rows up to the next header,
/// one-row summary, or strip. Group metadata (role, insets, card,
/// accessibility label) comes from matching the opening row against
/// the presentation by value: an exact match wins, else the single
/// group whose header shares the row's title text.
@available(macOS 26.0, *)
enum CaptureAgendaSectionBlock {
    case row(Int)
    case group(CaptureAgendaGroup, [Int], Bool)
}

@available(macOS 26.0, *)
enum CaptureAgendaSections {
    static func make(
        rows: [CaptureAgendaRow],
        presentation: CaptureAgendaPresentation
    ) -> [CaptureAgendaSectionBlock] {
        var blocks: [CaptureAgendaSectionBlock] = []
        var index = 0
        var groupSeen = false
        while index < rows.count {
            let row = rows[index]
            if row.kind == .groupHeader || row.kind == .groupOneRow {
                var owned: [Int] = [index]
                var cursor = index + 1
                while cursor < rows.count {
                    let next = rows[cursor]
                    if next.kind == .groupHeader || next.kind == .groupOneRow
                        || next.kind == .strip
                    {
                        break
                    }
                    owned.append(cursor)
                    cursor += 1
                }
                if let group = owner(of: row, in: presentation) {
                    blocks.append(.group(group, owned, groupSeen))
                    groupSeen = true
                } else {
                    for member in owned {
                        blocks.append(.row(member))
                    }
                }
                index = cursor
            } else {
                blocks.append(.row(index))
                index += 1
            }
        }
        return blocks
    }

    static func owner(
        of row: CaptureAgendaRow,
        in presentation: CaptureAgendaPresentation
    ) -> CaptureAgendaGroup? {
        for group in presentation.groups {
            if row == group.headerRow || row == group.oneRowRow {
                return group
            }
        }
        let named = presentation.groups.filter {
            row.kind == .groupHeader && $0.headerRow.text == row.text
        }
        if named.count == 1 {
            return named[0]
        }
        return named.first { $0.headerRow.accessoryText == row.accessoryText }
    }
}

/// Chip targets by plan-row index: which foldable unit a chip button
/// expands. Rows are matched against the presentation's precomputed
/// row lists by value, so the view never re-derives folding logic.
/// The strip always maps to the strip unit.
@available(macOS 26.0, *)
enum CaptureAgendaChipMap {
    static func targets(
        presentation: CaptureAgendaPresentation,
        plan: CaptureAgendaPlan
    ) -> [Int: CaptureAgendaUnitID] {
        var targets: [Int: CaptureAgendaUnitID] = [:]
        for (index, row) in plan.rows.enumerated() {
            if row.kind == .strip {
                targets[index] = .strip
                continue
            }
            guard let found = owner(of: row, in: presentation) else {
                continue
            }
            targets[index] = found
        }
        return targets
    }

    private static func owner(
        of row: CaptureAgendaRow,
        in presentation: CaptureAgendaPresentation
    ) -> CaptureAgendaUnitID? {
        for group in presentation.groups {
            for task in group.tasks {
                if task.fullRows.contains(row) || task.noLogsRows.contains(row)
                    || task.oneLineRow == row
                {
                    return task.id
                }
            }
            if row == group.oneRowRow {
                return group.id
            }
            if row != group.headerRow && row.kind == .groupHeader
                && row.text == group.headerRow.text
            {
                return group.id
            }
        }
        return nil
    }
}

/// One Pomodoro group: the Now card (pink rail plus faint wash) for
/// the running entry, plain rows otherwise. The container adds half
/// the role's vertical insets above and half below, so the block
/// matches the planner's `groupInsets + rows` exactly: measured row
/// heights already carry their bottom gaps.
@available(macOS 26.0, *)
struct CaptureAgendaGroupView: View {
    let group: CaptureAgendaGroup
    let rows: [CaptureAgendaRow]
    let targets: [Int: CaptureAgendaUnitID]
    let baseIndex: Int
    var onExpand: (CaptureAgendaUnitID) -> Void = { _ in }

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                CaptureAgendaRowView(
                    row: row,
                    role: group.role,
                    expands: CaptureAgendaRowView.showsChip(for: row),
                    chipUnit: targets[baseIndex + offset],
                    onExpand: onExpand
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        if group.role == .current {
            HStack(
                alignment: .top,
                spacing: CGFloat(CaptureAgendaLayoutMetrics.nowCardInnerPadding)
            ) {
                RoundedRectangle(
                    cornerRadius: CGFloat(CaptureAgendaLayoutMetrics.railWidth / 2)
                )
                .fill(CaptureEditorPalette.color(for: .pomodoroStart))
                .frame(
                    width: CGFloat(CaptureAgendaLayoutMetrics.railWidth)
                )
                stack
            }
            .padding(CGFloat(CaptureAgendaLayoutMetrics.nowCardInnerPadding))
            .background(
                CaptureEditorPalette.color(for: .pomodoroStart).opacity(0.06),
                in: RoundedRectangle(
                    cornerRadius: CGFloat(CaptureAgendaLayoutMetrics.cornerRadius)
                )
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(group.accessibilityLabel)
        } else {
            stack
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(group.accessibilityLabel)
        }
    }

    private var insets: Double {
        CaptureAgendaLayoutMetrics.groupVerticalInsets(role: group.role)
    }

    private var topInset: CGFloat {
        // The Now card's inner padding is uniform; other roles split
        // their insets half above and half below, matching the
        // planner's `groupInsets + rows` exactly.
        group.role == .current ? 0 : CGFloat(insets / 2)
    }

    private var bottomInset: CGFloat {
        guard group.role != .current else {
            return 0
        }
        return CGFloat(insets / 2)
    }
}

/// One rendered agenda row. Gaps live inside the row (headers and the
/// title take 4 pt below, other rows 2 pt, the strip takes 4 pt above
/// and nothing below), so the stack's height is exactly the sum the
/// planner budgets. `role` only affects group headers; every other
/// kind renders from the row alone.
@available(macOS 26.0, *)
struct CaptureAgendaRowView: View {
    let row: CaptureAgendaRow
    let role: CaptureAgendaRole
    let expands: Bool
    let chipUnit: CaptureAgendaUnitID?
    var onExpand: (CaptureAgendaUnitID) -> Void = { _ in }

    /// Whether the row's accessory renders as a chip button: every
    /// row whose presentation names an expansion action, plus the
    /// strip, truncation, and one-row rows, which always expand.
    static func showsChip(for row: CaptureAgendaRow) -> Bool {
        if row.accessoryAccessibilityLabel != nil {
            return true
        }
        switch row.kind {
        case .strip, .truncation, .groupOneRow:
            return true
        case .title, .multiOpenWarning, .stateLine, .groupHeader,
             .sessionNote, .taskHeadline, .ledgerNote, .childLine,
             .logHeader, .logEntry, .warning, .duplicate, .struck,
             .retired, .emptyGroup:
            return false
        }
    }

    var body: some View {
        content
            .padding(.leading, indent)
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var indent: CGFloat {
        CGFloat(row.depth) * CGFloat(CaptureAgendaLayoutMetrics.indentStep)
    }

    private var topPad: CGFloat {
        row.kind == .strip ? CGFloat(CaptureAgendaLayoutMetrics.headerBottomSpacing) : 0
    }

    private var bottomPad: CGFloat {
        switch row.kind {
        case .title, .groupHeader:
            return CGFloat(CaptureAgendaLayoutMetrics.headerBottomSpacing)
        case .stateLine, .strip:
            return 0
        case .multiOpenWarning, .sessionNote, .taskHeadline, .ledgerNote,
             .childLine, .logHeader, .logEntry, .warning, .duplicate,
             .struck, .retired, .emptyGroup, .truncation, .groupOneRow:
            return CGFloat(CaptureAgendaLayoutMetrics.rowSpacing)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch row.kind {
        case .title:
            titleView
        case .multiOpenWarning:
            warningLineView
        case .stateLine:
            quietLineView
        case .groupHeader:
            headerView
        case .sessionNote:
            bulletLineView(base: .callout, color: .secondary)
        case .taskHeadline:
            headlineView
        case .ledgerNote:
            inlineLineView(
                base: .callout,
                color: .secondary,
                italic: true,
                glyph: nil
            )
        case .childLine:
            inlineLineView(
                base: .callout,
                color: .secondary,
                italic: false,
                glyph: row.statusGlyph
            )
        case .logHeader:
            inlineLineView(
                base: .footnote,
                color: Color(nsColor: .tertiaryLabelColor),
                italic: false,
                glyph: nil
            )
        case .logEntry:
            inlineLineView(
                base: .footnote,
                color: Color(nsColor: .tertiaryLabelColor),
                italic: false,
                glyph: row.statusGlyph
            )
        case .warning:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                CaptureAgendaRowInlineText.text(
                    row.text,
                    base: .callout,
                    color: .primary
                )
                .lineLimit(row.lineLimit)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(row.accessibilityLabel ?? row.text)
        case .duplicate:
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                CaptureAgendaBadge(number: row.numberBadge)
                statusGlyphView(size: .callout)
                duplicateTextView
                    .lineLimit(row.lineLimit)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(row.accessibilityLabel ?? row.text)
        case .struck:
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                CaptureAgendaBadge(number: row.numberBadge)
                statusGlyphView(size: .callout)
                CaptureAgendaRowInlineText.text(
                    row.text,
                    base: .callout,
                    color: .secondary
                )
                .lineLimit(row.lineLimit)
                .strikethrough()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(row.accessibilityLabel ?? row.text)
        case .retired:
            Text(row.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(row.lineLimit)
                .accessibilityLabel(row.accessibilityLabel ?? row.text)
        case .emptyGroup:
            Text(row.text)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .lineLimit(row.lineLimit)
                .accessibilityLabel(row.accessibilityLabel ?? row.text)
        case .truncation:
            chipButton(text: row.text, label: row.accessibilityLabel ?? row.text)
        case .groupOneRow:
            oneRowView
        case .strip:
            stripView
        }
    }

    // MARK: - Title

    private var titleView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            titleLeadingView
            Spacer(minLength: 12)
            titleAccessoryView
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel ?? row.text)
    }

    @ViewBuilder
    private var titleAccessoryView: some View {
        if let accessory = row.accessoryText {
            if accessory == CaptureAgendaPresentation.staleSuffix {
                staleMarkerView(summary: nil)
            } else if accessory.hasSuffix(titleStaleSuffix) {
                let cut = accessory.index(
                    accessory.endIndex,
                    offsetBy: -titleStaleSuffix.count
                )
                staleMarkerView(summary: String(accessory[..<cut]))
            } else {
                Text(accessory)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var titleStaleSuffix: String {
        " · \(CaptureAgendaPresentation.staleSuffix)"
    }

    private func staleMarkerView(summary: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(CaptureAgendaPresentation.staleSuffix)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var titleLeadingView: some View {
        // "Today" reads semibold primary; the date and running note
        // stay secondary. The split is on display text, never JSON.
        let parts = row.text.split(separator: "·", maxSplits: 1)
        let head = parts.first.map(String.init) ?? row.text
        let rest = parts.count > 1 ? "·\(parts[1])" : ""
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(head.trimmingCharacters(in: .whitespaces))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if !rest.isEmpty {
                Text(rest)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Quiet lines

    private var quietLineView: some View {
        Text(row.text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(row.lineLimit)
            .accessibilityLabel(row.accessibilityLabel ?? row.text)
    }

    private var warningLineView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            CaptureAgendaRowInlineText.text(row.text, base: .callout, color: .primary)
                .lineLimit(row.lineLimit)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel ?? row.text)
    }

    private func bulletLineView(base: Font, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
                .font(base)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            CaptureAgendaRowInlineText.text(row.text, base: base, color: color)
                .lineLimit(row.lineLimit)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel ?? row.text)
    }

    private func inlineLineView(
        base: Font,
        color: Color,
        italic: Bool,
        glyph: String?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let glyph, !glyph.isEmpty {
                CaptureAgendaStatusGlyph(symbol: glyph, base: base)
            } else if row.kind == .childLine {
                Text("•")
                    .font(base)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            styledInlineText(base: base, color: color, italic: italic)
                .lineLimit(row.lineLimit)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel ?? row.text)
    }

    private func styledInlineText(base: Font, color: Color, italic: Bool) -> Text {
        var text = CaptureAgendaRowInlineText.text(row.text, base: base, color: color)
        if italic {
            text = text.italic()
        }
        return text
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        if role == .current, let countdown = headerCountdownText {
            headerStack
                .accessibilityElement(children: .combine)
                .accessibilityLabel(row.accessibilityLabel ?? row.text)
                .accessibilityValue(countdown)
        } else {
            headerStack
                .accessibilityElement(children: .combine)
                .accessibilityLabel(row.accessibilityLabel ?? row.text)
        }
    }

    private var headerStack: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            headerGlyphView
            Text(row.text)
                .font(.subheadline.weight(.semibold))
                .tracking(0.3)
                .lineLimit(row.lineLimit)
            Spacer(minLength: 12)
            headerAccessoryView
        }
    }

    /// The Now countdown ("12m left", "ending now", "overdue 8m") read
    /// as the header's accessibility value, so it is not re-announced
    /// every minute. Split from display text, never JSON.
    private var headerCountdownText: String? {
        guard role == .current, let accessory = row.accessoryText else {
            return nil
        }
        let parts = accessory.split(separator: "·")
        guard parts.count > 1 else {
            return nil
        }
        let countdown = parts[1].trimmingCharacters(in: .whitespaces)
        return countdown.isEmpty ? nil : countdown
    }

    @ViewBuilder
    private var headerGlyphView: some View {
        switch role {
        case .current:
            Image(systemName: "play.circle.fill")
                .foregroundStyle(CaptureEditorPalette.color(for: .pomodoroStart))
                .accessibilityHidden(true)
        case .open:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        case .next:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .later, .completed, .other:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var headerAccessoryView: some View {
        if expands {
            chipButton(
                text: row.accessoryText ?? "",
                label: row.accessoryAccessibilityLabel ?? row.accessoryText ?? ""
            )
        } else if role == .next, row.accessoryText == "= starts it" {
            HStack(spacing: 0) {
                Text("= ")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(
                        CaptureEditorPalette.color(for: .pomodoroStart)
                    )
                Text("starts it")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        } else if role == .open, let accessory = row.accessoryText {
            HStack(spacing: 6) {
                Text("Open")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                if accessory != "Open" {
                    Text(openRangeText(accessory))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else if let accessory = row.accessoryText {
            headerTimeView(accessory)
        }
    }

    private func openRangeText(_ accessory: String) -> String {
        if accessory.hasPrefix("Open · ") {
            return String(accessory.dropFirst(7))
        }
        return accessory
    }

    private func headerTimeView(_ accessory: String) -> some View {
        // The current entry joins "range · countdown"; an overdue
        // countdown reads orange. Later entries show "=#slug".
        let parts = accessory.split(separator: "·")
        let first = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? accessory
        let second = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespaces)
            : nil
        let overdue = second?.hasPrefix("overdue") == true
        let slug = first.hasPrefix("=#")
        return HStack(spacing: 4) {
            Text(first)
                .font(.callout.monospacedDigit())
                .foregroundStyle(slug ? .tertiary : .secondary)
                .lineLimit(1)
            if let second {
                Text("· \(second)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(overdue ? .orange : .secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Task headline

    private var headlineView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            CaptureAgendaBadge(number: row.numberBadge)
            statusGlyphView(size: .callout)
            CaptureAgendaRowInlineText.text(row.text, base: .callout, color: .primary)
                .lineLimit(row.lineLimit)
            Spacer(minLength: 12)
            headlineAccessoryView
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel ?? row.text)
    }

    @ViewBuilder
    private var headlineAccessoryView: some View {
        if expands {
            chipButton(
                text: row.accessoryText ?? "",
                label: row.accessoryAccessibilityLabel ?? row.accessoryText ?? ""
            )
        } else if let accessory = row.accessoryText {
            Text(accessory)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var duplicateTextView: some View {
        // "title ↑ in GROUP": the title reads primary, the pointer
        // secondary. The split is on display text, never JSON.
        if let range = row.text.range(of: " ↑ in ", options: .backwards) {
            HStack(spacing: 0) {
                CaptureAgendaRowInlineText.text(
                    String(row.text[..<range.lowerBound]),
                    base: .callout,
                    color: .primary
                )
                Text(String(row.text[range.lowerBound...]))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 0) {
                CaptureAgendaRowInlineText.text(
                    row.text,
                    base: .callout,
                    color: .primary
                )
            }
        }
    }

    // MARK: - One-row summary and strip

    private var oneRowView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            CaptureAgendaRowInlineText.text(row.text, base: .callout, color: .primary)
                .lineLimit(row.lineLimit)
            Spacer(minLength: 12)
            chipButton(
                text: row.accessoryText ?? "",
                label: row.accessibilityLabel ?? row.text
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel ?? row.text)
    }

    private var stripView: some View {
        CaptureAgendaChipButton(
            text: row.text,
            accessibilityLabel: row.accessibilityLabel ?? row.text,
            font: .footnote.weight(.medium),
            action: { [chipUnit, onExpand] in
                if let chipUnit {
                    onExpand(chipUnit)
                }
            }
        )
    }

    // MARK: - Shared pieces

    private func statusGlyphView(size: Font) -> some View {
        Group {
            if let symbol = row.statusGlyph, !symbol.isEmpty {
                CaptureAgendaStatusGlyph(symbol: symbol, base: size)
                    .frame(
                        width: CGFloat(CaptureAgendaLayoutMetrics.glyphColumnWidth),
                        alignment: .center
                    )
            } else {
                Color.clear.frame(
                    width: CGFloat(CaptureAgendaLayoutMetrics.glyphColumnWidth),
                    height: 1
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func chipButton(text: String, label: String) -> some View {
        CaptureAgendaChipButton(
            text: text,
            accessibilityLabel: label,
            action: { [chipUnit, onExpand] in
                if let chipUnit {
                    onExpand(chipUnit)
                }
            }
        )
    }
}

/// Plain chip buttons that never take focus, with a hover highlight.
/// Tapping expands the unit in place; the model returns focus to the
/// editor, so keyboard focus never leaves the editor in v1.
@available(macOS 26.0, *)
struct CaptureAgendaChipButton: View {
    let text: String
    let accessibilityLabel: String
    var font: Font = .caption2.weight(.medium)
    var action: () -> Void = {}
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(font)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(hovered ? .tertiary : .quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The fixed-width leading number badge: `N.circle` through 50, then
/// monospaced digits in a capsule. Mirrors the start/close badges;
/// unnumbered rows keep a clear spacer so text stays aligned.
@available(macOS 26.0, *)
struct CaptureAgendaBadge: View {
    let number: Int?

    var body: some View {
        Group {
            if let number, number > 50 {
                Text("\(number)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .frame(
                        width: CGFloat(CaptureAgendaLayoutMetrics.badgeColumnWidth) + 14,
                        alignment: .center
                    )
            } else if let number {
                Image(systemName: "\(number).circle")
                    .foregroundStyle(.secondary)
                    .frame(
                        width: CGFloat(CaptureAgendaLayoutMetrics.badgeColumnWidth),
                        alignment: .center
                    )
            } else {
                Color.clear.frame(
                    width: CGFloat(CaptureAgendaLayoutMetrics.badgeColumnWidth),
                    height: 1
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// A checkbox status symbol: single characters reuse the editor
/// palette's checkbox colors, and SF Symbol names render directly.
@available(macOS 26.0, *)
struct CaptureAgendaStatusGlyph: View {
    let symbol: String
    let base: Font

    var body: some View {
        Group {
            if symbol.count == 1, let first = symbol.first {
                Text(symbol)
                    .font(base)
                    .foregroundStyle(CaptureEditorPalette.checkboxSymbolColor(first))
            } else {
                Image(systemName: symbol)
                    .font(base)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Inline display text: code spans read monospaced, wikilink display
/// text reads link-tinted and never clickable, strong and emphasis
/// use their intents, and fields and tags read dimmed. Unmatched
/// delimiters stay literal, as the parser guarantees.
@available(macOS 26.0, *)
enum CaptureAgendaRowInlineText {
    static func text(_ raw: String, base: Font, color: Color) -> Text {
        let parsed = CaptureAgendaInlineText(parsing: raw)
        let chars = Array(parsed.text)
        var result = Text("")
        for segment in parsed.segments {
            let slice = String(chars[segment.range])
            result = result + styledSlice(slice, kind: segment.kind, color: color)
        }
        return result.font(base).foregroundStyle(color)
    }

    private static func styledSlice(
        _ slice: String,
        kind: CaptureAgendaInlineSegment.Kind,
        color: Color
    ) -> Text {
        switch kind {
        case .plain:
            return Text(slice)
        case .code:
            return Text(AttributedString(slice, attributes: inlineCodeAttributes))
        case .link:
            return Text(slice)
                .foregroundStyle(CaptureEditorPalette.color(for: .link))
        case .strong:
            return Text(AttributedString(slice, attributes: strongAttributes))
        case .emphasis:
            return Text(AttributedString(slice, attributes: emphasisAttributes))
        case .field, .tag:
            return Text(slice).foregroundStyle(.secondary)
        }
    }

    private static var inlineCodeAttributes: AttributeContainer {
        var container = AttributeContainer()
        container.inlinePresentationIntent = .code
        return container
    }

    private static var strongAttributes: AttributeContainer {
        var container = AttributeContainer()
        container.inlinePresentationIntent = .stronglyEmphasized
        return container
    }

    private static var emphasisAttributes: AttributeContainer {
        var container = AttributeContainer()
        container.inlinePresentationIntent = .emphasized
        return container
    }
}
