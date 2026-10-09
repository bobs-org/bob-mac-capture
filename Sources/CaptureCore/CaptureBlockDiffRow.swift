import Foundation

/// One display-only row of a batch-level block diff card, shared by the
/// Pomodoro and parent-task presentations. `content` is the line with its
/// leading spaces and tabs dropped; `depth` is the nesting level relative
/// to the headline, clamped to `CapturePomodoroBlockPresentation.maxDepth`;
/// `beforeContent` holds the old text on `changed` rows, likewise stripped,
/// and is nil otherwise. Tokenizing never adds, drops, or reorders
/// characters: `tokens.map(\.text).joined()` always equals `content`.
public struct CaptureBlockDiffRow: Equatable, Sendable {
    public let content: String
    public let depth: Int
    public let change: CapturePomodoroBlockChange
    public let beforeContent: String?
    /// True for a non-empty depth-0 row.
    public let isHeadline: Bool
    public let tokens: [CapturePomodoroLineToken]
    /// True for an added line Bob marked `reason == "unblocked"`: a
    /// surviving successor link. Renders a trailing badge.
    public let isUnblocked: Bool

    public init(
        content: String,
        depth: Int,
        change: CapturePomodoroBlockChange,
        beforeContent: String? = nil,
        isHeadline: Bool,
        tokens: [CapturePomodoroLineToken],
        isUnblocked: Bool = false
    ) {
        self.content = content
        self.depth = depth
        self.change = change
        self.beforeContent = beforeContent
        self.isHeadline = isHeadline
        self.tokens = tokens
        self.isUnblocked = isUnblocked
    }
}
