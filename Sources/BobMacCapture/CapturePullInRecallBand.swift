import AppKit
import CaptureCore
import SwiftUI

/// `USED BEFORE` cancel recall band under the pull-in reason field.
///
/// Same anatomy as `SimilarTasksBandView`: a 0.5pt hairline, an SF Symbol
/// `clock.arrow.circlepath` at `.caption2` `.tertiary`, a `USED BEFORE`
/// header in `.caption2.weight(.semibold).tracking(0.6)` `.secondary`,
/// trailing keycaps, 22pt `.callout` rows, and
/// `.caption.monospacedDigit()` `.tertiary` metadata.
///
/// Rows never take focus: they are plain rows with an `onTapGesture` (no
/// Button), so clicks fill via a suppress-blur token plus a refocus and
/// never confirm. Hovering never selects.
@available(macOS 26.0, *)
struct CapturePullInRecallBand: View {
    @ObservedObject var model: CapturePanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let recall = model.pullInRecall
        let rows = recall.visibleRows
        guard !rows.isEmpty else {
            return AnyView(EmptyView())
        }
        let header = LogRecallBandPresentation.header(
            draft: recall.draft, selectedIndex: recall.selectedIndex,
            total: recall.ranked.count)
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: 4)
                    .accessibilityHidden(true)
                Rectangle()
                    .fill(BlockDiffCard.hairlineColor(contrast: contrast))
                    .frame(height: 0.5)
                    .accessibilityHidden(true)
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(header.title)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if header.showsKeycaps {
                        Text("⌃N ⌃P")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    } else if !header.trailing.isEmpty {
                        Text(header.trailing)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: CGFloat(LogRecallBandPresentation.headerHeight))
                .accessibilityHidden(true)
                ForEach(rows, id: \.phrase.key) { row in
                    recallRow(row, recall: recall)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel(recall: recall, header: header))
            .transition(.opacity)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.12),
                value: rows.map(\.phrase.key))
        )
    }

    @ViewBuilder
    private func recallRow(
        _ row: LogRecallRanking.Ranked, recall: LogRecallState
    ) -> some View {
        let isSelected = recall.selectedKey == row.phrase.key
        HStack(spacing: 6) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .accessibilityHidden(true)
            }
            phraseText(row, isSelected: isSelected)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(
                LogRecallBandPresentation.meta(
                    uses: row.phrase.uses, lastUsed: row.phrase.lastUsed)
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .layoutPriority(0)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CGFloat(LogRecallBandPresentation.rowHeight))
        .padding(.horizontal, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor.opacity(contrast == .increased ? 0.30 : 0.16))
            }
        }
        .offset(x: isSelected ? bumpOffset : 0)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: model.pullInRecallBumpSeed
        )
        .help(
            LogRecallBandPresentation.tooltip(
                lastUsed: row.phrase.lastUsed, uses: row.phrase.uses)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Recalled \(row.phrase.text), \(row.phrase.uses) uses, last used \(row.phrase.lastUsed)"
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectPullInRecallRow(key: row.phrase.key)
        }
    }

    private var bumpOffset: CGFloat {
        // Edge bump nudges the selected row 2px in the pressed direction
        // for 120 ms, no wrap. Reduce Motion replaces motion with a 120 ms
        // opacity dip (handled by the row transition below).
        if reduceMotion { return 0 }
        return model.pullInRecallBumpSeed % 2 == 1 ? 2 : 0
    }

    private func phraseText(
        _ row: LogRecallRanking.Ranked, isSelected: Bool
    ) -> Text {
        let phrase = row.phrase.text
        let query = model.pullInRecall.draft.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !query.isEmpty,
            let range = phrase.range(
                of: query, options: [.caseInsensitive, .diacriticInsensitive])
        else {
            return Text(phrase)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        let before = String(phrase[..<range.lowerBound])
        let hit = String(phrase[range])
        let after = String(phrase[range.upperBound...])
        return Text(before)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            + Text(hit)
            .foregroundStyle(Color.accentColor)
            .fontWeight(.semibold)
            + Text(after)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
    }

    private func accessibilityLabel(
        recall: LogRecallState, header: LogRecallBandPresentation.Header
    ) -> String {
        if let index = recall.selectedIndex {
            let text = recall.filledText() ?? ""
            return LogRecallBandPresentation.announcement(
                index: index, total: recall.ranked.count, text: text)
        }
        return header.title
    }
}
