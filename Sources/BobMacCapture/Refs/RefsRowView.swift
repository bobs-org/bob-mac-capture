import RefsCore
import SwiftUI

/// The 28 pt kind tile: a rounded rect in the kind tint with the kind
/// symbol, carrying the kind label for accessibility.
@available(macOS 26.0, *)
struct RefsKindTile: View {
    let kind: RefKind
    var size: CGFloat = RefsVisualTokens.kindTileSize

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let tint = RefsVisualTokens.tint(for: kind)
        // The named radii: the 44 pt hero tile takes heroTileRadius,
        // every other size the kind tile radius.
        let radius =
            size == RefsVisualTokens.heroTileSize
            ? RefsVisualTokens.heroTileRadius
            : RefsVisualTokens.kindTileRadius
        return ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(tint.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(
                            tint.opacity(contrast == .increased ? 0.5 : 0.28),
                            lineWidth: 0.5
                        )
                )
            Image(systemName: kind.symbolName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(kind.label)
        .accessibilityHidden(false)
    }
}

/// The state glyph in a fixed 18 pt column so glyphs align down the
/// list. A missing PDF replaces it with an orange warning triangle.
@available(macOS 26.0, *)
struct RefsStateGlyph: View {
    let content: RefsRowContent

    var body: some View {
        Group {
            if content.isMissingPDF {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("PDF missing")
            } else if let item = content.item {
                let resolved = CaptureEditorPalette.taskStatus(
                    RefsVisualTokens.paletteStatus(for: item)
                )
                Image(systemName: resolved.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(resolved.color)
                    .accessibilityLabel(RefsCaption.stateLabel(item))
            } else {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, alignment: .center)
    }
}

/// The pink Today pill, matching capture's NOW pill: a capsule with a
/// white timer glyph and the Pomodoro name, truncated at 12
/// characters, or "TODAY" when the name is empty.
@available(macOS 26.0, *)
struct RefsTodayPill: View {
    let pomodoroName: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .bold))
            Text(label)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.pink, in: Capsule())
        .accessibilityLabel("Today in \(label) Pomodoro")
    }

    private var label: String {
        if pomodoroName.isEmpty {
            return "TODAY"
        }
        if pomodoroName.count > 12 {
            return String(pomodoroName.prefix(12)) + "…"
        }
        return pomodoroName
    }
}

/// The "Current · p. 5/25" pill marking the frontmost Highlights
/// tab in Tabs mode: an accent capsule in the trailing pill slot,
/// next to the pink Today pill when a row has both.
@available(macOS 26.0, *)
struct RefsCurrentTabPill: View {
    let pageCaption: String?

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.16), in: Capsule())
            .accessibilityHidden(true)
    }

    private var label: String {
        if let pageCaption {
            return "Current · \(pageCaption)"
        }
        return "Current"
    }
}

/// The neutral document tile for collision and unmatched Tabs rows:
/// a secondary rounded rect with a document glyph, in place of the
/// kind tile. Deliberately chroma-free, so these rows never read as
/// a kind or a state.
@available(macOS 26.0, *)
struct RefsTabDocTile: View {
    var size: CGFloat = RefsVisualTokens.kindTileSize

    var body: some View {
        // The named radii: the 44 pt hero tile takes heroTileRadius,
        // every other size the kind tile radius, matching RefsKindTile.
        let radius =
            size == RefsVisualTokens.heroTileSize
            ? RefsVisualTokens.heroTileRadius
            : RefsVisualTokens.kindTileRadius
        return ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(.secondary.opacity(0.12))
            Image(systemName: "doc")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One 44 pt two-line row: the unopened gutter, the kind tile, the
/// rich title plus caption, and the trailing Today pill, annotation
/// and narration marks, and state glyph. Single click selects;
/// double-click opens. An unavailable row dims and never opens
/// whatever slid into its index.
///
/// In Tabs mode a matched row also carries its open tab: the current
/// tab shows the Current pill, and every tab row names Highlights in
/// its accessibility label. Collision and unmatched rows (no item)
/// render dimmed with the neutral document tile and glyph instead of
/// the kind tile and state glyph — a legible treatment distinct from
/// the unavailable 0.45 dim.
@available(macOS 26.0, *)
struct RefsRowView: View {
    let content: RefsRowContent
    let isSelected: Bool
    let pomodoroName: String?
    let onSelect: () -> Void
    let onActivate: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false

    /// Whether this row is a collision or unmatched Tabs row.
    private var isTabFallback: Bool {
        content.item == nil && content.openTab != nil
    }

    var body: some View {
        HStack(spacing: 10) {
            gutter
            // The tile and glyph stay out of the VoiceOver tree: the
            // row label below already names the kind and state once.
            if let item = content.item {
                RefsKindTile(kind: item.kind)
                    .accessibilityHidden(true)
            } else if isTabFallback {
                RefsTabDocTile()
            } else {
                RefsKindTile(kind: .other(raw: nil))
                    .accessibilityHidden(true)
            }
            textColumn
            Spacer(minLength: 8)
            if let pomodoroName {
                RefsTodayPill(pomodoroName: pomodoroName)
            }
            if let openTab = content.openTab, openTab.isCurrent {
                RefsCurrentTabPill(pageCaption: openTab.pageCaption)
            }
            if let item = content.item, item.annotationCount > 0 {
                Label(
                    "\(item.annotationCount)",
                    systemImage: "highlighter"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            if content.item?.audioPath != nil {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isTabFallback {
                Image(systemName: "doc")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .center)
                    .accessibilityHidden(true)
            } else {
                RefsStateGlyph(content: content)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: RefsVisualTokens.rowHeight)
        .background(background)
        .opacity(content.isUnavailable ? 0.45 : 1)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onActivate)
        .onTapGesture(count: 1, perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var gutter: some View {
        ZStack {
            if content.isUnopened {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 8)
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleLine
            Text(captionLine)
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// The caption the row shows: a collision row names its
    /// candidate notes after the model's "Matches N notes", so Bryan
    /// can tell the candidates apart without opening the inspector.
    private var displayCaption: String {
        guard isTabFallback, !content.candidateItems.isEmpty else {
            return content.caption
        }
        let names = content.candidateItems.map(\.title.text).joined(separator: " · ")
        return "\(content.caption): \(names)"
    }

    /// The caption with the matched stem or secondary part in the
    /// accent color (§8). The ranges come from the model, as
    /// `Character` offsets into the caption text.
    private var captionLine: AttributedString {
        CapturePickerRichText.displayText(
            displayCaption,
            segments: [],
            matches: content.captionMatch.map { [$0] } ?? []
        )
    }

    /// Speaks a tab page caption ("p. 5/25") as "page 5 of 25" for
    /// VoiceOver. Pure so tests pin the phrasing without building the
    /// view. An unrecognized shape falls back to the raw caption.
    static func spokenPagePhrase(_ pageCaption: String?) -> String? {
        guard let pageCaption else {
            return nil
        }
        let trimmed = pageCaption.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.hasPrefix("p. ") ? String(trimmed.dropFirst(3)) : trimmed
        let parts = digits.split(separator: "/")
        guard parts.count == 2,
              let page = Int(parts[0]),
              let total = Int(parts[1])
        else {
            return pageCaption
        }
        return "page \(page) of \(total)"
    }

    private var titleLine: some View {
        HStack(spacing: 0) {
            if let item = content.item {
                Text(
                    CapturePickerRichText.displayText(
                        item.title.text,
                        segments: item.title.segments,
                        matches: content.match?.titleRanges ?? []
                    )
                )
                .font(.system(size: 13.5, weight: content.isUnopened ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                if let disambiguator = item.titleDisambiguator {
                    Text(" · \(disambiguator)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            } else {
                Text(content.title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(isTabFallback ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var background: some View {
        let increased = contrast == .increased
        return RoundedRectangle(cornerRadius: 8)
            .fill(
                isSelected
                    ? Color.accentColor.opacity(increased ? 0.30 : 0.16)
                    : hovering
                        ? Color.primary.opacity(increased ? 0.12 : 0.06)
                        : Color.clear
            )
            .padding(.horizontal, 6)
    }

    private var accessibilityLabel: String {
        guard let item = content.item else {
            return "\(content.title), \(displayCaption), open in Highlights"
        }
        var parts = [
            item.title.text,
            item.kind.label,
            RefsCaption.stateLabel(item),
            content.caption.replacingOccurrences(of: " pp", with: " pages"),
        ]
        if let pomodoroName {
            let name = pomodoroName.isEmpty ? "TODAY" : pomodoroName
            parts.append("Today in \(name) Pomodoro")
        }
        if content.isUnopened {
            parts.append("never opened")
        }
        if let openTab = content.openTab {
            parts.append("open in Highlights")
            if openTab.isCurrent {
                if let spoken = Self.spokenPagePhrase(openTab.pageCaption) {
                    parts.append("current tab, \(spoken)")
                } else {
                    parts.append("current tab")
                }
            }
        }
        return parts.joined(separator: ", ")
    }
}
