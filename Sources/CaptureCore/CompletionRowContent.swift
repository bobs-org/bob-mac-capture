import Foundation

/// The semantic family a piece of capture-marker or wikilink syntax belongs to. Shared by
/// editor highlighting and completion-row presentation so both draw from one palette instead
/// of duplicating a kind-to-color mapping.
public enum CaptureSemanticCategory: Equatable, Sendable {
    case route
    case section
    case blockID
    case schedule
    case priority
    case clipboard
    case wikilinkDelimiter
    case wikilinkTarget
    case wikilinkHeading
    case wikilinkBlock
    case wikilinkAlias
    case interactivePlaceholder
    case neutral
}

/// Maps a `capture-parse` span kind to its semantic category. Unrecognized kinds fall back to
/// `.neutral`, matching ordinary prose rather than signaling an error.
public func captureSemanticCategory(forSpanKind kind: String) -> CaptureSemanticCategory {
    switch kind {
    case "route", "pomodoro_route", "sub_bullet_route":
        return .route
    case "section":
        return .section
    case "pomodoro_block_id", "sub_bullet_block_id":
        return .blockID
    case "schedule":
        return .schedule
    case "priority":
        return .priority
    case "clipboard":
        return .clipboard
    case "wikilink_delimiter":
        return .wikilinkDelimiter
    case "wikilink_target":
        return .wikilinkTarget
    case "wikilink_heading":
        return .wikilinkHeading
    case "wikilink_block_id":
        return .wikilinkBlock
    case "wikilink_alias":
        return .wikilinkAlias
    case "interactive_placeholder":
        return .interactivePlaceholder
    default:
        return .neutral
    }
}

/// The completion contexts `capture-complete` can report, typed so row presentation cannot
/// silently mishandle an unrecognized string. `capture-complete --help` documents these exact
/// wire values.
public enum CaptureCompletionContext: Equatable, Sendable {
    case route
    case section
    case pomodoroBlockID
    case task
    case wikilinkNote
    case wikilinkHeading
    case wikilinkBlock

    public init?(rawContext: String?) {
        switch rawContext {
        case "route": self = .route
        case "section": self = .section
        case "pomodoro_block_id": self = .pomodoroBlockID
        case "task": self = .task
        case "wikilink_note": self = .wikilinkNote
        case "wikilink_heading": self = .wikilinkHeading
        case "wikilink_block": self = .wikilinkBlock
        default: return nil
        }
    }
}

/// Everything a completion row needs to render its context icon, primary/secondary text,
/// badges, and accessibility description, computed once per candidate so `CompletionRow` in
/// the app target stays a thin SwiftUI layer instead of branching on raw candidate fields.
public struct CompletionRowContent: Equatable, Sendable {
    public let category: CaptureSemanticCategory
    public let symbolName: String
    public let contextLabel: String
    public let primaryText: String
    /// Character-offset range within `primaryText` that matches the in-progress query,
    /// case-insensitively, for restrained emphasis. `nil` when the query is empty or the
    /// matched field isn't the one shown as `primaryText`.
    public let primaryMatchRange: Range<Int>?
    public let secondaryText: String?
    public let badges: [String]
    public let accessibilityLabel: String
    public let accessibilityHint: String

    public init(
        category: CaptureSemanticCategory,
        symbolName: String,
        contextLabel: String,
        primaryText: String,
        primaryMatchRange: Range<Int>?,
        secondaryText: String?,
        badges: [String],
        accessibilityLabel: String,
        accessibilityHint: String
    ) {
        self.category = category
        self.symbolName = symbolName
        self.contextLabel = contextLabel
        self.primaryText = primaryText
        self.primaryMatchRange = primaryMatchRange
        self.secondaryText = secondaryText
        self.badges = badges
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
    }
}

/// Builds the presentation content for one completion candidate. `query` is the in-progress
/// text between the completion replacement's start and the cursor; pass an empty string when
/// there is none (an empty-query result list still renders, just without match emphasis).
public func completionRowContent(
    for candidate: CaptureCompletionCandidate,
    context rawContext: String?,
    query: String
) -> CompletionRowContent {
    let context = CaptureCompletionContext(rawContext: rawContext)

    let category: CaptureSemanticCategory
    let symbolName: String
    let contextLabel: String
    let primaryText: String
    var secondaryText: String?
    var badges: [String] = []
    let accessibilityHint: String

    switch context {
    case .route:
        category = .route
        symbolName = "signpost.right"
        contextLabel = "Destination"
        primaryText = candidate.route ?? candidate.label ?? candidate.replacement
        if let label = candidate.label, label != primaryText {
            secondaryText = label
        }
        badges = [candidate.kind, candidate.status].compactMap { $0 }.filter { !$0.isEmpty }
        accessibilityHint = "Sets the capture destination."

    case .section:
        category = .section
        symbolName = "list.bullet.indent"
        contextLabel = "Section"
        primaryText = candidate.title ?? candidate.replacement
        if let level = candidate.level {
            badges = ["H\(level)"]
        }
        accessibilityHint = "Inserts this section heading."

    case .pomodoroBlockID, .task:
        category = .blockID
        symbolName = "arrow.turn.down.right"
        contextLabel = context == .pomodoroBlockID ? "Pomodoro Task" : "Parent Task"
        primaryText = candidate.text ?? candidate.replacement
        secondaryText = candidate.section
        if let symbol = candidate.statusSymbol, let name = candidate.statusName {
            badges.append("[\(symbol)] \(name)")
        } else if let name = candidate.statusName {
            badges.append(name)
        }
        if let blockID = candidate.blockID {
            badges.append("^\(blockID)")
        }
        accessibilityHint = "Nests the capture under this task."

    case .wikilinkNote:
        category = .wikilinkTarget
        symbolName = "doc.text"
        contextLabel = "Note"
        primaryText = candidate.alias ?? candidate.name ?? candidate.replacement
        secondaryText = candidate.path
        if candidate.alias != nil {
            badges = ["Alias"]
        }
        accessibilityHint = "Inserts a link to this note."

    case .wikilinkHeading:
        category = .wikilinkHeading
        symbolName = "number"
        contextLabel = "Heading"
        primaryText = candidate.heading ?? candidate.replacement
        secondaryText = candidate.path
        if let level = candidate.level {
            badges = ["H\(level)"]
        }
        accessibilityHint = "Inserts a link to this heading."

    case .wikilinkBlock:
        category = .wikilinkBlock
        symbolName = "paragraphsign"
        contextLabel = "Block"
        primaryText = candidate.blockID.map { "^\($0)" } ?? candidate.replacement
        secondaryText = candidate.path
        if let preview = candidate.preview, !preview.isEmpty {
            badges = [preview]
        }
        accessibilityHint = "Inserts a link to this block."

    case nil:
        category = .neutral
        symbolName = "text.cursor"
        contextLabel = ""
        primaryText = candidate.label ?? candidate.text ?? candidate.title ?? candidate.replacement
        accessibilityHint = "Inserts this completion."
    }

    let matchRange = completionMatchRange(in: primaryText, query: query)
    let accessibilityLabel = completionAccessibilityLabel(
        contextLabel: contextLabel,
        primaryText: primaryText,
        secondaryText: secondaryText,
        badges: badges
    )

    return CompletionRowContent(
        category: category,
        symbolName: symbolName,
        contextLabel: contextLabel,
        primaryText: primaryText,
        primaryMatchRange: matchRange,
        secondaryText: secondaryText,
        badges: badges,
        accessibilityLabel: accessibilityLabel,
        accessibilityHint: accessibilityHint
    )
}

private func completionAccessibilityLabel(
    contextLabel: String,
    primaryText: String,
    secondaryText: String?,
    badges: [String]
) -> String {
    var parts: [String] = []
    if !contextLabel.isEmpty {
        parts.append(contextLabel)
    }
    parts.append(primaryText)
    if let secondaryText, !secondaryText.isEmpty {
        parts.append(secondaryText)
    }
    parts.append(contentsOf: badges)
    return parts.joined(separator: ", ")
}

/// Case-insensitive first-occurrence match of `query` within `text`, expressed as a
/// `Character`-offset range so callers don't need to reason about `String.Index` validity
/// across differently-sourced strings.
public func completionMatchRange(in text: String, query: String) -> Range<Int>? {
    guard !query.isEmpty else {
        return nil
    }
    guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
        return nil
    }

    let lowerOffset = text.distance(from: text.startIndex, to: range.lowerBound)
    let upperOffset = text.distance(from: text.startIndex, to: range.upperBound)
    return lowerOffset..<upperOffset
}

/// Truncates `path` to at most `maxLength` characters, preserving the final path component
/// (the basename) intact and collapsing the middle of the leading directory portion with an
/// ellipsis. Falls back to plain middle truncation when there is no `/` or the basename alone
/// exceeds the budget.
public func middleTruncatedPath(_ path: String, maxLength: Int) -> String {
    guard maxLength > 0, path.count > maxLength else {
        return path
    }

    let ellipsis = "\u{2026}"
    guard let lastSlash = path.lastIndex(of: "/") else {
        return middleTruncated(path, maxLength: maxLength, ellipsis: ellipsis)
    }

    let basename = String(path[path.index(after: lastSlash)...])
    let suffix = "/\(basename)"
    if suffix.count >= maxLength {
        return middleTruncated(basename, maxLength: maxLength, ellipsis: ellipsis)
    }

    let directoryBudget = maxLength - suffix.count - ellipsis.count
    guard directoryBudget > 0 else {
        return "\(ellipsis)\(suffix)"
    }

    let directory = String(path[path.startIndex..<lastSlash])
    let headCount = (directoryBudget + 1) / 2
    let tailCount = directoryBudget - headCount
    let head = directory.prefix(headCount)
    let tail = directory.suffix(tailCount)
    return "\(head)\(ellipsis)\(tail)\(suffix)"
}

private func middleTruncated(_ text: String, maxLength: Int, ellipsis: String) -> String {
    guard text.count > maxLength else {
        return text
    }
    guard maxLength > ellipsis.count else {
        return String(ellipsis.prefix(maxLength))
    }

    let budget = maxLength - ellipsis.count
    let headCount = (budget + 1) / 2
    let tailCount = budget - headCount
    let head = text.prefix(headCount)
    let tail = text.suffix(tailCount)
    return "\(head)\(ellipsis)\(tail)"
}
