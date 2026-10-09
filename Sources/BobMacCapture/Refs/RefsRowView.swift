import RefsCore
import SwiftUI

/// The 28 pt kind tile: a rounded rect in the kind tint with the kind
/// symbol, carrying the kind label for accessibility.
@available(macOS 26.0, *)
struct RefsKindTile: View {
    let kind: RefKind
    var size: CGFloat = RefsVisualTokens.kindTileSize

    @Environment(\.accessibilityIncreaseContrast) private var increaseContrast

    var body: some View {
        let tint = RefsVisualTokens.tint(for: kind)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(tint.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.25)
                        .strokeBorder(
                            tint.opacity(increaseContrast ? 0.5 : 0.28),
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

/// One 44 pt two-line row: the unopened gutter, the kind tile, the
/// rich title plus caption, and the trailing Today pill, annotation
/// and narration marks, and state glyph. Single click selects;
/// double-click opens. An unavailable row dims and never opens
/// whatever slid into its index.
@available(macOS 26.0, *)
struct RefsRowView: View {
    let content: RefsRowContent
    let isSelected: Bool
    let pomodoroName: String?
    let onSelect: () -> Void
    let onActivate: () -> Void

    @Environment(\.accessibilityIncreaseContrast) private var increaseContrast
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            gutter
            if let item = content.item {
                RefsKindTile(kind: item.kind)
            } else {
                RefsKindTile(kind: .other(raw: nil))
            }
            textColumn
            Spacer(minLength: 8)
            if let pomodoroName {
                RefsTodayPill(pomodoroName: pomodoroName)
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
            RefsStateGlyph(content: content)
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
            Text(content.caption)
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
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
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                isSelected
                    ? Color.accentColor.opacity(increaseContrast ? 0.30 : 0.16)
                    : hovering
                        ? Color.primary.opacity(increaseContrast ? 0.12 : 0.06)
                        : Color.clear
            )
            .padding(.horizontal, 6)
    }

    private var accessibilityLabel: String {
        guard let item = content.item else {
            return "\(content.title), \(content.caption)"
        }
        var parts = [
            item.title.text,
            item.kind.label,
            RefsCaption.stateLabel(item),
            content.caption,
        ]
        if pomodoroName != nil {
            parts.append("in Today Pomodoro")
        }
        if content.isUnopened {
            parts.append("never opened")
        }
        return parts.joined(separator: ", ")
    }
}
