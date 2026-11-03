import AppKit
import CaptureCore
import SwiftUI

/// The single source of truth for capture-marker and wikilink semantic colors. Both editor
/// highlighting (`CapturePanelModel.applyHighlighting`) and completion-row accents
/// (`CompletionRow`) resolve a `CaptureSemanticCategory` through this palette so the two
/// surfaces can never drift into inconsistent colors for the same syntax.
///
/// Colors are all adaptive system colors (`Color.accentColor`, `.secondary`, and the fixed
/// semantic hues already used elsewhere in the app) so they carry correct contrast in light,
/// dark, and increased-contrast appearances without bespoke handling here.
enum CaptureEditorPalette {
    private static let templateSlotColors: [Color] = [
        .orange, .teal, .pink, .green, .purple, .brown,
    ]

    static func templateSlotColor(field: Int) -> Color {
        let index = ((field % templateSlotColors.count) + templateSlotColors.count)
            % templateSlotColors.count
        return templateSlotColors[index]
    }

    /// Status glyph and color for a capture picker row, so the card and any
    /// future surface share one mapping.
    static func taskStatus(_ status: CapturePickerTaskStatus) -> (symbol: String, color: Color) {
        switch status {
        case .inProgress:
            return ("circle.lefthalf.filled", .orange)
        case .next:
            return ("circle.inset.filled", .blue)
        case .todo:
            return ("circle", .secondary)
        case .blocked:
            return ("pause.circle", .secondary)
        case .done:
            return ("checkmark.circle", .green)
        case .canceled:
            return ("xmark.circle", .secondary)
        case .other:
            return ("circle.dashed", .secondary)
        }
    }

    /// Checkbox-symbol tint for a Pomodoro block headline, next to
    /// `taskStatus`: done reads green, in-progress orange, next blue, an
    /// empty box tertiary, and anything else secondary.
    static func checkboxSymbolColor(_ symbol: Character) -> Color {
        switch symbol {
        case "x":
            return .green
        case "/":
            return .orange
        case "*":
            return .blue
        case " ":
            // `Color.tertiary` is a shape style, not a color.
            return Color(nsColor: .tertiaryLabelColor)
        default:
            return .secondary
        }
    }

    /// The soft manila wash behind every span of a sealed project-note marker
    /// (`@cash^goog-exit@`, `@cash:goog-exit@`). The spans are contiguous across
    /// the marker, so the per-span washes read as one chip. Increase Contrast
    /// raises the alpha so the chip survives the stronger system contrast.
    static func projectNoteWash(increaseContrast: Bool) -> Color {
        Color(nsColor: .systemBrown).opacity(increaseContrast ? 0.26 : 0.16)
    }

    static func color(for category: CaptureSemanticCategory) -> Color {
        switch category {
        case .route:
            return .accentColor
        case .section:
            return .purple
        case .blockID:
            return .indigo
        case .schedule:
            return .green
        case .priority:
            return .orange
        case .directive:
            return .teal
        case .wikilinkDelimiter:
            return .secondary
        case .wikilinkTarget:
            return .accentColor
        case .wikilinkHeading:
            return .purple
        case .wikilinkBlock:
            return .indigo
        case .wikilinkAlias:
            return .teal
        case .interactivePlaceholder:
            return .secondary
        case .explicitToggle:
            return .yellow
        case .projectNoteName, .projectNoteSeal:
            // Brown reads as a manila folder: a new project note. It is the
            // one system hue the editor has not already given a role.
            return .brown
        case .projectNoteOfferSeal:
            // The Pull-In card's "will be linked" green: a choice card follows.
            return .green
        case .blockedTaskSigil:
            return .teal
        case .relationSigil:
            return .mint
        case .relationLabel:
            return .secondary
        case .relationCancelLabel:
            // Cancelled-status family, distinct from muted labels, amber
            // caveats, and SwiftUI error red.
            return Color(nsColor: .systemRed)
        case .relationCompleteLabel:
            // Done-status family, matching the picker's Done glyph and the
            // `!` seal. A distinct role from the `!` sigil's category even
            // though both render green.
            return .green
        case .relationSuccessorLabel:
            // Successor labels remain neutral effects: the relation sigil's
            // mint hue distinguishes them without implying a close.
            return .mint
        case .taskType, .taskTypeMarker:
            return Color(nsColor: .tertiaryLabelColor)
        case .pomodoroStart:
            return .pink
        case .pomodoroCloseInProgress:
            return .orange
        case .pomodoroClosePark:
            return .teal
        case .pomodoroCloseComplete:
            return .green
        case .pomodoroCloseDrop:
            return .gray
        case .pomodoroCloseLog:
            return .cyan
        case .pomodoroStartDrop:
            return .gray
        case .link:
            return Color(nsColor: .linkColor)
        case .templateSlot(let field):
            return templateSlotColor(field: field)
        case .neutral:
            return .primary
        }
    }
}
