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
    @State private var nameFieldIsFocused = false

    var body: some View {
        let link = model.pullInLink
        let rows = link.visibleCandidates
        let header =
            link.name.map { PullInLinkBandPresentation.nameHeader(for: $0) }
            ?? PullInLinkBandPresentation.header(
                selectedIndex: link.selectedIndex, total: link.candidates.count,
                tasks: link.isTasks)
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
            if let stage = link.name {
                nameStage(stage)
            } else if link.isTasks {
                let contents = PullInTaskRowContent.rows(
                    for: rows, state: link, query: query)
                ForEach(Array(zip(rows, contents)), id: \.0.id) { candidate, content in
                    taskRow(
                        candidate, content: content,
                        context: context, query: query,
                        isSelected: link.selectedID == candidate.id)
                }
            } else {
                ForEach(rows, id: \.id) { candidate in
                    linkRow(
                        candidate,
                        content: completionRowContent(
                            for: candidate, context: context, query: query),
                        isSelected: link.selectedID == candidate.id)
                }
            }
            if let detail = model.pullInLinkDetailLine {
                Text(detail)
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
        // A `((` session never animates between its list and NAME stages.
        .animation(
            link.isTasks
                ? nil
                : reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.12),
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
        case .wikilinkTask:
            return "wikilink_task"
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

    /// One task row of the tasks band: a status glyph, the display text, a
    /// group capsule or badge, and the locator drawn as the link it will
    /// insert (target, `#^`, then the ID; an ID-less row shows `⊕` and the
    /// suggestion in italic). Guarded and closed rows dim.
    @ViewBuilder
    private func taskRow(
        _ candidate: CaptureCompletionCandidate,
        content: PullInTaskRowContent,
        context: String?,
        query: String,
        isSelected: Bool
    ) -> some View {
        let style = CaptureEditorPalette.taskStatus(content.status)
        let hint = completionRowContent(
            for: candidate, context: context, query: query
        ).accessibilityHint
        HStack(spacing: 6) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .accessibilityHidden(true)
            }
            Image(systemName: style.symbol)
                .font(.callout)
                .foregroundStyle(style.color)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(
                CapturePickerRichText.displayText(
                    content.text, segments: content.segments,
                    matches: content.matchRanges)
            )
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(1)
            if let capsule = content.groupCapsule ?? content.badge {
                Text(capsule)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous).fill(Color.primary.opacity(0.07))
                    )
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            locatorText(content)
                .font(.caption.monospacedDigit())
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
        .opacity(content.isDimmed ? 0.6 : 1)
        .offset(x: isSelected ? bumpOffset : 0)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: model.pullInLinkBumpSeed
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint(hint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contentShape(Rectangle())
        .onTapGesture {
            model.insertPullInLinkRow(id: candidate.id)
        }
    }

    /// The link the row will insert, in the picker's colours: target in the
    /// wikilink target colour, `#^` in the delimiter colour, the ID in the
    /// block ID colour. An ID-less row leads with `⊕` and shows the
    /// suggestion in italic.
    private func locatorText(_ content: PullInTaskRowContent) -> Text {
        guard let target = content.locatorTarget, !target.isEmpty else {
            return Text(content.locatorID.map { "^\($0)" } ?? "")
                .foregroundStyle(CaptureEditorPalette.color(for: .blockID))
        }
        let delimiter = Text("#^")
            .foregroundStyle(CaptureEditorPalette.color(for: .wikilinkDelimiter))
        let head = Text(target)
            .foregroundStyle(CaptureEditorPalette.color(for: .wikilinkTarget))
        guard let id = content.locatorID else { return head }
        if content.locatorIsSuggestion {
            return Text("⊕ ").foregroundStyle(.tertiary) + head + delimiter
                + Text(id).italic().foregroundStyle(.tertiary)
        }
        return head + delimiter
            + Text(id).foregroundStyle(CaptureEditorPalette.color(for: .blockID))
    }

    /// The NAME stage: the chosen task pinned with its `Add ID` capsule, the
    /// ID line (`^` and the reusable `BlockIDField`, focused and prefilled
    /// with bob's first suggestion), and bob's other suggestions. The
    /// reason field above is untouched.
    @ViewBuilder
    private func nameStage(_ stage: PullInLinkNameStage) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(stage.target.taskText)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text("⊕ Add ID")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
                .accessibilityHidden(true)
        }
        .frame(height: CGFloat(PullInLinkBandPresentation.rowHeight))
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Naming \(stage.target.taskText)")
        HStack(spacing: 0) {
            Text("^")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(CaptureEditorPalette.color(for: .blockID))
                .padding(.leading, 8)
                .accessibilityHidden(true)
            BlockIDField(
                text: Binding(
                    get: { model.pullInLink.name?.authoredID ?? "" },
                    set: { model.updatePullInLinkNameID($0) }
                ),
                isEnabled: !stage.isSaving,
                focusRequest: model.focusRequest,
                focusDidChange: { nameFieldIsFocused = $0 }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 5)
            Text(stage.validationMessage == nil && stage.errorMessage == nil ? "✓" : "✕")
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    stage.validationMessage == nil && stage.errorMessage == nil
                        ? Color.green : Color.orange
                )
                .padding(.trailing, 8)
                .accessibilityHidden(true)
        }
        .frame(height: CGFloat(PullInLinkBandPresentation.nameFieldHeight))
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    nameFieldIsFocused
                        ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.24),
                    lineWidth: nameFieldIsFocused ? 1 : 0.5
                )
        )
        .padding(.horizontal, 4)
        .onDisappear { nameFieldIsFocused = false }
        HStack(spacing: 6) {
            ForEach(Array(stage.target.suggestions.enumerated()), id: \.offset) { index, idea in
                if index > 0 {
                    Text("·").foregroundStyle(.tertiary)
                }
                Text(idea)
                    .font(.caption.monospaced())
                    .foregroundStyle(idea == stage.authoredID ? Color.accentColor : Color.secondary)
            }
            Spacer(minLength: 8)
            if stage.target.suggestions.count > 1 {
                Text("⇥ next idea")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .frame(height: CGFloat(PullInLinkBandPresentation.rowHeight))
        .padding(.horizontal, 8)
        .accessibilityHidden(true)
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
        if let stage = link.name {
            return PullInLinkBandPresentation.nameAnnouncement(for: stage)
        }
        if link.isTasks, let index = link.selectedIndex,
            let candidate = link.selectedCandidate
        {
            let row = PullInTaskRowContent(
                candidate: candidate, action: link.rowAction(for: candidate))
            return "Task \(index) of \(link.candidates.count): \(row.accessibilityLabel)"
        }
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
