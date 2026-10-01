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
        case .clipboard:
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
        case .neutral:
            return .primary
        }
    }
}
