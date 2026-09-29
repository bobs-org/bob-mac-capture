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
        case .neutral:
            return .primary
        }
    }
}
