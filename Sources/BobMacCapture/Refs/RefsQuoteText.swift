import RefsCore
import SwiftUI

/// Shared quote-text builder for the inspector and the Copy card
/// picker: paired `**` runs render as semibold full-ink words over a
/// gold underline, so both views agree. Payloads, tooltips, and the
/// clipboard keep the raw `**` Markdown.
@available(macOS 26.0, *)
enum RefsQuoteText {
    static func text(_ quote: String) -> Text {
        let pieces = RefsQuoteUnderline.pieces(quote)
        guard let first = pieces.first else {
            return Text(verbatim: "")
        }
        return pieces.dropFirst().reduce(text(for: first)) { result, piece in
            Text("\(result)\(text(for: piece))")
        }
    }

    private static func text(for piece: RefsQuotePiece) -> Text {
        let base = Text(verbatim: piece.text)
        switch piece.role {
        case .plain:
            return base
        case .underlined:
            return base
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .customAttribute(RefsUnderlineMark(role: .underlined))
        case .underlineGap:
            return base
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .customAttribute(RefsUnderlineMark(role: .underlineGap))
        }
    }
}
