import AppKit
import CaptureCore
import SwiftUI

/// `LINK` wikilink-completion band under the pull-in reason field.
///
/// Same anatomy as `CapturePullInRecallBand`, in whose slot it renders
/// while open: a 0.5pt hairline, an SF Symbol `link` at `.caption2`
/// `.tertiary`, a `LINK` header in `.caption2.weight(.semibold).tracking(0.6)`
/// `.secondary`, trailing keycaps, 22pt `.callout` rows rendered with
/// `CompletionRowContent`, `.caption.monospacedDigit()` `.tertiary`
/// metadata, and a detail strip naming the exact `[[…]]` link Return
/// inserts.
///
/// Rows never take focus: they are plain rows with an `onTapGesture` (no
/// Button), so clicks insert via a suppress-blur token plus a refocus and
/// never confirm. Hovering never selects.
@available(macOS 26.0, *)
struct CapturePullInLinkBand: View {
    @ObservedObject var model: CapturePanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let link = model.pullInLink
        let rows = link.visibleCandidates
        let header = PullInLinkBandPresentation.header(
            selectedIndex: link.selectedIndex, total: link.candidates.count)
        let query = link.queryText()
        let context = rawContext(link.context)
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 4)
                .accessibilityHidden(true)
            Rectangle()
                .fill(BlockDiffCard.hairlineColor(contrast: contrast))
                .frame(height: 0.5)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                Image(systemName: "link")
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
                    Text(header.trailing)
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
            .frame(height: CGFloat(PullInLinkBandPresentation.headerHeight))
            .accessibilityHidden(true)
            ForEach(rows, id: \.id) { candidate in
                linkRow(
                    candidate,
                    content: completionRowContent(
                        for: candidate, context: context, query: query),
                    isSelected: link.selectedID == candidate.id)
            }
            if let preview = model.pullInLinkDetailPreview {
                Text("↵ \(preview)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(
                        height: CGFloat(PullInLinkBandPresentation.detailHeight),
                        alignment: .leading)
                    .padding(.horizontal, 4)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel(link: link, header: header))
        .transition(.opacity)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.12),
            value: rows.map(\.id))
    }

    private func rawContext(_ context: CaptureCompletionContext?) -> String? {
        switch context {
        case .wikilinkNote:
            return "wikilink_note"
        case .wikilinkHeading:
            return "wikilink_heading"
        case .wikilinkBlock:
            return "wikilink_block"
        case .none, .some:
            return nil
        }
    }

    @ViewBuilder
    private func linkRow(
        _ candidate: CaptureCompletionCandidate,
        content: CompletionRowContent,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 6) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .accessibilityHidden(true)
            }
            Image(systemName: content.symbolName)
                .font(.callout)
                .foregroundStyle(
                    CaptureEditorPalette.color(for: content.category))
                .frame(width: 16)
                .accessibilityHidden(true)
            emphasizedPrimaryText(content)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(secondaryLine(content))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(0)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CGFloat(PullInLinkBandPresentation.rowHeight))
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
            value: model.pullInLinkBumpSeed
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint(content.accessibilityHint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contentShape(Rectangle())
        .onTapGesture {
            model.insertPullInLinkRow(id: candidate.id)
        }
    }

    private var bumpOffset: CGFloat {
        // Edge bump nudges the selected row 2px in the pressed direction
        // for 120 ms, no wrap. Reduce Motion replaces motion with a 120 ms
        // opacity dip (handled by the row transition below).
        if reduceMotion { return 0 }
        return model.pullInLinkBumpSeed % 2 == 1 ? 2 : 0
    }

    private func secondaryLine(_ content: CompletionRowContent) -> String {
        var parts: [String] = []
        if let secondary = content.secondaryText, !secondary.isEmpty {
            parts.append(secondary)
        }
        parts.append(contentsOf: content.badges.filter { !$0.isEmpty })
        return parts.joined(separator: " · ")
    }

    private func emphasizedPrimaryText(_ content: CompletionRowContent) -> Text {
        let primary = content.primaryText
        guard let match = content.primaryMatchRange,
            match.lowerBound >= 0,
            match.upperBound <= primary.count,
            match.lowerBound < match.upperBound,
            let lower = primary.index(
                primary.startIndex, offsetBy: match.lowerBound,
                limitedBy: primary.endIndex),
            let upper = primary.index(
                lower, offsetBy: match.upperBound - match.lowerBound,
                limitedBy: primary.endIndex)
        else {
            return Text(primary)
        }
        let before = String(primary[primary.startIndex..<lower])
        let hit = String(primary[lower..<upper])
        let after = String(primary[upper..<primary.endIndex])
        return Text(before)
            + Text(hit)
            .foregroundStyle(Color.accentColor)
            .fontWeight(.semibold)
            + Text(after)
    }

    private func accessibilityLabel(
        link: PullInLinkState, header: PullInLinkBandPresentation.Header
    ) -> String {
        if let index = link.selectedIndex,
            let candidate = link.selectedCandidate
        {
            let content = completionRowContent(
                for: candidate, context: rawContext(link.context),
                query: link.queryText())
            return PullInLinkBandPresentation.announcement(
                index: index, total: link.candidates.count,
                text: content.primaryText)
        }
        return header.title
    }
}
