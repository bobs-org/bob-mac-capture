import Foundation

/// Pure presentation model for one batch-level Pomodoro block
/// (`pomodoro_blocks` on a `bob capture --format json` success), built once
/// from `CapturePomodoroBlock` so the SwiftUI layer never branches on
/// block JSON fields. The preview's only source of truth is Bob's resolved
/// block — which itself comes from `bob capture --dry-run --no-clip
/// --format json` for live preview and the same command without
/// `--dry-run`/`--no-clip` for submission — so there is no Swift-side
/// ledger logic here, only wording. Works for dry-run previews and
/// committed captures alike; `dryRun` only changes the created badge.
public struct CapturePomodoroBlockPresentation: Equatable, Sendable {
    /// Shared with the parent-task presentation: one display-only diff row.
    public typealias Row = CaptureBlockDiffRow

    /// The deepest rendered indent step; deeper Bob depths still show,
    /// clamped to this level.
    public static let maxDepth = 8

    public let status: CapturePomodoroBlockStatus
    /// The SF Symbol for the caption row: `play.circle.fill` while running,
    /// `checkmark.circle.fill` when completed, `circle.dashed` otherwise.
    public let statusSymbolName: String
    /// `"Running · line 27"`.
    public let captionText: String
    /// `"New"` on a dry run that creates the entry, `"Created"` once
    /// committed, nil unless the block is created. Rendered as a small
    /// pink capsule in the start card's `createdBadgeText` style.
    public let badgeText: String?
    public let rows: [Row]
    public let accessibilitySummary: String

    public init(block: CapturePomodoroBlock, dryRun: Bool) {
        status = block.status
        let statusText: String
        switch block.status {
        case .running:
            statusText = "Running"
            statusSymbolName = "play.circle.fill"
        case .completed:
            statusText = "Completed"
            statusSymbolName = "checkmark.circle.fill"
        case .queued:
            statusText = "Queued"
            statusSymbolName = "circle.dashed"
        case .other:
            statusText = "Pomodoro"
            statusSymbolName = "circle.dashed"
        }
        captionText = "\(statusText) · line \(block.line)"
        badgeText = block.created ? (dryRun ? "New" : "Created") : nil
        rows = block.lines.map { line in
            let content = Self.stripped(line.text)
            let depth = min(max(line.depth, 0), Self.maxDepth)
            let isHeadline = depth == 0 && !content.isEmpty
            return Row(
                content: content,
                depth: depth,
                change: line.change,
                beforeContent: line.before.map(Self.stripped),
                isHeadline: isHeadline,
                tokens: CapturePomodoroLineTokens.tokenize(content, isHeadline: isHeadline),
                isUnblocked: line.change == .added && line.reason == "unblocked"
            )
        }

        var summary = "\(block.name ?? "Unnamed"), \(statusText), line \(block.line)"
        if let badgeText {
            summary += ", \(badgeText)"
        }
        let spokenRows = rows.map { row -> String in
            switch row.change {
            case .added:
                if row.isUnblocked {
                    return "added \(row.content), unblocked successor"
                }
                return "added \(row.content)"
            case .removed:
                return "removed \(row.content)"
            case .changed:
                if let before = row.beforeContent, !before.isEmpty {
                    return "changed from \(before) to \(row.content)"
                }
                return "changed \(row.content)"
            case .unchanged:
                return row.content
            }
        }
        if !spokenRows.isEmpty {
            summary += ": " + spokenRows.joined(separator: "; ")
        }
        accessibilitySummary = summary
    }

    /// True when the blocks already show every verbatim preview line, so the
    /// standard item can omit its `previewBlockLines` stack: blocks is
    /// non-empty and every preview line equals the text of a non-removed
    /// line in a block filed under the capture's own `relativeTarget`.
    public static func covers(
        _ capture: CaptureCommandSuccess,
        blocks: [CapturePomodoroBlock]
    ) -> Bool {
        guard !blocks.isEmpty else {
            return false
        }
        return capture.previewBlockLines.allSatisfy { preview in
            blocks.contains { block in
                block.relativeTarget == capture.relativeTarget
                    && block.lines.contains { line in
                        line.change != .removed && line.text == preview
                    }
            }
        }
    }

    static func stripped(_ value: String) -> String {
        var result = value
        while result.hasPrefix(" ") || result.hasPrefix("\t") {
            result.removeFirst()
        }
        return result
    }
}
