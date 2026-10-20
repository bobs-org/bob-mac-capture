import Foundation

/// Role of one contiguous quote piece after `**` pairing and
/// underline-gap splitting.
public enum RefsQuotePieceRole: Equatable, Hashable, Sendable {
    case plain
    case underlined
    case underlineGap
}

/// One contiguous stretch of quote text with a single underline role.
public struct RefsQuotePiece: Equatable, Sendable {
    public let text: String
    public let role: RefsQuotePieceRole

    public init(text: String, role: RefsQuotePieceRole) {
        self.text = text
        self.role = role
    }
}

/// One laid-out run on a line, with its horizontal extent.
public struct RefsQuoteLineRun: Equatable, Sendable {
    public let role: RefsQuotePieceRole
    public let minX: Double
    public let maxX: Double

    public init(role: RefsQuotePieceRole, minX: Double, maxX: Double) {
        self.role = role
        self.minX = minX
        self.maxX = maxX
    }
}

/// A merged underline span on one laid-out line, after end-gap trimming.
public struct RefsUnderlineSpan: Equatable, Sendable {
    public let minX: Double
    public let maxX: Double

    public init(minX: Double, maxX: Double) {
        self.minX = minX
        self.maxX = maxX
    }
}

/// A gold underline bar under one laid-out line span.
public struct RefsUnderlineBar: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let cornerRadius: Double

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        cornerRadius: Double
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
}

/// Splits a quote into underline pieces and lays out gold bars under
/// the underlined spans. Built on `RefsQuoteEmphasis.runs`; the stored
/// form stays `**`.
public enum RefsQuoteUnderline {
    /// SF's line height as a multiple of em: ascent + descent ≈ 1.19 em.
    public static let emFromLineMetrics = 1.19
    /// Default bar thickness as a fraction of em.
    public static let thicknessEm = 0.15
    /// Increase Contrast bar thickness as a fraction of em.
    public static let thicknessEmIncreased = 0.20
    /// Floor for default thickness, in points.
    public static let minThickness = 1.5
    /// Floor for Increase Contrast thickness, in points.
    public static let minThicknessIncreased = 2.0
    /// Distance from the baseline to the bar's top edge, as a fraction
    /// of em. Clears the baseline and sits in the descender zone.
    public static let topOffsetEm = 0.08

    /// Pieces of `quote` after pairing `**` and splitting strong runs
    /// into underlined words, in-run gaps, and plain edge whitespace.
    /// Joining `text` values recovers `RefsQuoteEmphasis.plainText`.
    public static func pieces(_ quote: String) -> [RefsQuotePiece] {
        var collected: [RefsQuotePiece] = []
        for run in RefsQuoteEmphasis.runs(quote) {
            if run.isStrong {
                collected.append(contentsOf: splitStrong(run.text))
            } else if !run.text.isEmpty {
                collected.append(RefsQuotePiece(text: run.text, role: .plain))
            }
        }
        return compacted(collected)
    }

    /// Underlined phrases in order, trimmed and non-empty. Consecutive
    /// underlined words with in-run gaps form one phrase.
    public static func phrases(_ quote: String) -> [String] {
        var phrases: [String] = []
        var current = ""
        for piece in pieces(quote) {
            switch piece.role {
            case .underlined, .underlineGap:
                current += piece.text
            case .plain:
                appendPhrase(current, to: &phrases)
                current = ""
            }
        }
        appendPhrase(current, to: &phrases)
        return phrases
    }

    /// True when the quote has underlined words and no non-whitespace
    /// plain piece, including a whole-quote `**` wrap.
    public static func isWhollyUnderlined(_ quote: String) -> Bool {
        let all = pieces(quote)
        guard all.contains(where: { $0.role == .underlined }) else {
            return false
        }
        return all.allSatisfy { piece in
            piece.role != .plain || piece.text.allSatisfy(\.isWhitespace)
        }
    }

    /// Merges consecutive underlined and gap runs into spans, dropping
    /// gap runs at either end. A span made only of gaps produces no bar.
    public static func bars(in runs: [RefsQuoteLineRun]) -> [RefsUnderlineSpan] {
        var spans: [[RefsQuoteLineRun]] = []
        var current: [RefsQuoteLineRun] = []
        for run in runs {
            switch run.role {
            case .underlined, .underlineGap:
                current.append(run)
            case .plain:
                if !current.isEmpty {
                    spans.append(current)
                    current = []
                }
            }
        }
        if !current.isEmpty {
            spans.append(current)
        }
        return spans.compactMap { span in
            let trimmed = trimGaps(span)
            guard let first = trimmed.first, let last = trimmed.last else {
                return nil
            }
            let minX = first.minX
            let maxX = last.maxX
            guard maxX > minX else {
                return nil
            }
            return RefsUnderlineSpan(minX: minX, maxX: maxX)
        }
    }

    /// Geometry for one gold bar. Estimates em from the line metrics,
    /// applies the documented thickness and offset, and snaps `y` and
    /// `height` to device pixels. Nil when width is zero or negative.
    public static func bar(
        minX: Double,
        maxX: Double,
        baseline: Double,
        ascent: Double,
        descent: Double,
        increasedContrast: Bool,
        displayScale: Double
    ) -> RefsUnderlineBar? {
        let width = maxX - minX
        guard width > 0 else {
            return nil
        }
        let lineHeight = max(ascent + descent, 0)
        let em = lineHeight > 0 ? lineHeight / emFromLineMetrics : 0
        let thicknessFraction =
            increasedContrast ? thicknessEmIncreased : thicknessEm
        let minThick =
            increasedContrast ? minThicknessIncreased : minThickness
        let thickness = max(thicknessFraction * em, minThick)
        let scale = displayScale > 0 ? displayScale : 1
        let y = snap(baseline + topOffsetEm * em, scale: scale)
        let height = snap(thickness, scale: scale)
        guard height > 0 else {
            return nil
        }
        return RefsUnderlineBar(
            x: minX,
            y: y,
            width: width,
            height: height,
            cornerRadius: height / 2
        )
    }

    private static func snap(_ value: Double, scale: Double) -> Double {
        (value * scale).rounded() / scale
    }

    private static func splitStrong(_ text: String) -> [RefsQuotePiece] {
        guard !text.isEmpty else {
            return []
        }
        let leadingCount = text.prefix(while: \.isWhitespace).count
        let trailingCount = text.reversed().prefix(while: \.isWhitespace).count
        if leadingCount + trailingCount >= text.count {
            return [RefsQuotePiece(text: text, role: .plain)]
        }
        var pieces: [RefsQuotePiece] = []
        if leadingCount > 0 {
            let end = text.index(text.startIndex, offsetBy: leadingCount)
            pieces.append(
                RefsQuotePiece(text: String(text[..<end]), role: .plain)
            )
        }
        let bodyStart = text.index(text.startIndex, offsetBy: leadingCount)
        let bodyEnd = text.index(text.endIndex, offsetBy: -trailingCount)
        pieces.append(contentsOf: splitBody(String(text[bodyStart..<bodyEnd])))
        if trailingCount > 0 {
            pieces.append(
                RefsQuotePiece(text: String(text[bodyEnd...]), role: .plain)
            )
        }
        return pieces
    }

    private static func splitBody(_ text: String) -> [RefsQuotePiece] {
        var pieces: [RefsQuotePiece] = []
        var current = ""
        var currentIsWhitespace = false
        var started = false
        for character in text {
            let isWhitespace = character.isWhitespace
            if !started {
                current = String(character)
                currentIsWhitespace = isWhitespace
                started = true
                continue
            }
            if isWhitespace == currentIsWhitespace {
                current.append(character)
            } else {
                pieces.append(
                    pieceForBodyStretch(
                        current, isWhitespace: currentIsWhitespace
                    )
                )
                current = String(character)
                currentIsWhitespace = isWhitespace
            }
        }
        if started {
            pieces.append(
                pieceForBodyStretch(current, isWhitespace: currentIsWhitespace)
            )
        }
        return pieces
    }

    private static func pieceForBodyStretch(
        _ text: String,
        isWhitespace: Bool
    ) -> RefsQuotePiece {
        if !isWhitespace {
            return RefsQuotePiece(text: text, role: .underlined)
        }
        let role: RefsQuotePieceRole =
            text.contains(where: \.isNewline) ? .plain : .underlineGap
        return RefsQuotePiece(text: text, role: role)
    }

    private static func compacted(_ pieces: [RefsQuotePiece]) -> [RefsQuotePiece] {
        var result: [RefsQuotePiece] = []
        for piece in pieces where !piece.text.isEmpty {
            if let last = result.last, last.role == piece.role {
                result[result.count - 1] = RefsQuotePiece(
                    text: last.text + piece.text,
                    role: last.role
                )
            } else {
                result.append(piece)
            }
        }
        return result
    }

    private static func trimGaps(
        _ span: [RefsQuoteLineRun]
    ) -> [RefsQuoteLineRun] {
        var start = 0
        var end = span.count
        while start < end, span[start].role == .underlineGap {
            start += 1
        }
        while end > start, span[end - 1].role == .underlineGap {
            end -= 1
        }
        return Array(span[start..<end])
    }

    private static func appendPhrase(_ current: String, to phrases: inout [String]) {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            phrases.append(trimmed)
        }
    }
}
