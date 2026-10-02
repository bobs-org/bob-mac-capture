import Foundation

/// Pure presentation model for one batch-level parent-task block
/// (`task_blocks` on a `bob capture --format json` success), built once
/// from `CaptureTaskBlock` so the SwiftUI layer never branches on block
/// JSON fields. The preview's only source of truth is Bob's resolved
/// block — which itself comes from `bob capture --dry-run --no-clip
/// --format json` for live preview and the same command without
/// `--dry-run`/`--no-clip` for submission — so there is no Swift-side
/// vault logic here, only wording. Works for dry-run previews and
/// committed captures alike; `dryRun` only changes the created badge.
public struct CaptureTaskBlockPresentation: Equatable, Sendable {
    /// One collapsed run of unchanged rows. `id` is the first hidden row
    /// index, stable for the card's identity so expansion survives
    /// re-renders; `depth` is the run's shallowest depth, where the fold
    /// row renders with indent guides.
    public struct FoldRun: Equatable, Sendable {
        public let id: Int
        public let count: Int
        public let depth: Int
        public let rows: [CaptureBlockDiffRow]

        public init(id: Int, count: Int, depth: Int, rows: [CaptureBlockDiffRow]) {
            self.id = id
            self.count = count
            self.depth = depth
            self.rows = rows
        }
    }

    public enum Item: Equatable, Sendable {
        case row(CaptureBlockDiffRow)
        case fold(FoldRun)
    }

    /// Card identity: expansions reset when any of these change.
    public struct Identity: Equatable, Sendable {
        public let relativeTarget: String
        public let line: Int
        public let blockID: String?

        public init(relativeTarget: String, line: Int, blockID: String?) {
            self.relativeTarget = relativeTarget
            self.line = line
            self.blockID = blockID
        }
    }

    /// Blocks this small always render in full; effectively every task.
    public static let foldThreshold = 24
    /// Visible rows kept on each side of a change when folding.
    public static let contextRadius = 2
    /// Shorter unchanged runs never collapse; they render in full.
    public static let minimumFoldRun = 4

    public let status: CapturePickerTaskStatus
    /// Bob's `status_name`, unless it is empty or `Unknown`; then the
    /// canonical `CapturePickerTaskStatus.displayName`.
    public let statusText: String
    /// `"In Progress · sase.md · line 1"`, mirroring the Pomodoro caption.
    public let captionText: String
    /// `"New"` on a dry run that creates the parent, `"Created"` once
    /// committed, nil unless the parent is new to the batch. Rendered as
    /// a small pink capsule in the Pomodoro card's `createdBadgeText`
    /// style.
    public let badgeText: String?
    public let rows: [CaptureBlockDiffRow]
    public let identity: Identity
    public let accessibilitySummary: String

    public init(block: CaptureTaskBlock, dryRun: Bool) {
        let symbol = block.statusSymbol.isEmpty ? nil : block.statusSymbol
        status = CapturePickerTaskStatus(symbol: symbol, name: block.statusName)
        if block.statusName.isEmpty || block.statusName == "Unknown" {
            statusText = status.displayName
        } else {
            statusText = block.statusName
        }
        captionText = "\(statusText) · \(block.relativeTarget) · line \(block.line)"
        badgeText = block.created ? (dryRun ? "New" : "Created") : nil
        identity = Identity(
            relativeTarget: block.relativeTarget,
            line: block.line,
            blockID: block.blockID
        )
        rows = block.lines.enumerated().map { index, line in
            let content = Self.stripped(line.text)
            let depth = min(max(line.depth, 0), CapturePomodoroBlockPresentation.maxDepth)
            let isHeadline = index == 0
            return CaptureBlockDiffRow(
                content: content,
                depth: depth,
                change: line.change,
                beforeContent: line.before.map(Self.stripped),
                isHeadline: isHeadline,
                tokens: CapturePomodoroLineTokens.tokenizeTaskRow(
                    content,
                    isHeadline: isHeadline
                )
            )
        }

        var summary = "\(block.text), \(statusText), \(block.relativeTarget) line \(block.line)"
        if let badgeText {
            summary += ", \(badgeText)"
        }
        let spokenRows = rows.map { row -> String in
            switch row.change {
            case .added:
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

    /// Rows and folds to render: the task line, every non-`unchanged`
    /// row, `contextRadius` rows on each side of a change, and each
    /// change's structural ancestors (the nearest preceding row at each
    /// shallower depth). Any other run of at least `minimumFoldRun`
    /// unchanged rows collapses into one fold row; folds whose id is in
    /// `expandedFolds` inline their rows instead. Blocks at or below
    /// `foldThreshold` rows, and blocks with no changes, never fold.
    public func items(expandedFolds: Set<Int>) -> [Item] {
        guard rows.count > Self.foldThreshold,
            rows.contains(where: { $0.change != .unchanged })
        else {
            return rows.map(Item.row)
        }
        var visible: Set<Int> = [0]
        for (index, row) in rows.enumerated() where row.change != .unchanged {
            let lower = max(0, index - Self.contextRadius)
            let upper = min(rows.count - 1, index + Self.contextRadius)
            for neighbour in lower...upper {
                visible.insert(neighbour)
            }
            var depth = row.depth
            var cursor = index - 1
            while cursor >= 0 {
                if rows[cursor].depth < depth {
                    visible.insert(cursor)
                    depth = rows[cursor].depth
                    if depth <= 0 {
                        break
                    }
                }
                cursor -= 1
            }
        }
        var result: [Item] = []
        var hidden: [Int] = []
        func flushHidden() {
            if hidden.count >= Self.minimumFoldRun {
                if expandedFolds.contains(hidden[0]) {
                    result.append(contentsOf: hidden.map { Item.row(rows[$0]) })
                } else {
                    let foldRows = hidden.map { rows[$0] }
                    result.append(
                        Item.fold(
                            FoldRun(
                                id: hidden[0],
                                count: hidden.count,
                                depth: foldRows.map(\.depth).min() ?? 0,
                                rows: foldRows
                            )
                        )
                    )
                }
            } else {
                result.append(contentsOf: hidden.map { Item.row(rows[$0]) })
            }
            hidden.removeAll(keepingCapacity: true)
        }
        for index in rows.indices {
            if visible.contains(index) {
                flushHidden()
                result.append(.row(rows[index]))
            } else {
                hidden.append(index)
            }
        }
        flushHidden()
        return result
    }

    /// True when the task blocks already show every verbatim preview line
    /// of a sub-bullet capture, so the standard item can omit its
    /// `previewBlockLines` stack: blocks is non-empty and every preview
    /// line, with leading whitespace stripped, matches a distinct `added`
    /// or `changed` row, likewise stripped, of a task block filed under
    /// the capture's own `relativeTarget`. Matching is one-to-one, so
    /// duplicate bullets in one item each need their own row. Stripping
    /// is required because Bob's `task_line` is unindented while the
    /// block line carries the parent's child indentation.
    public static func covers(
        _ capture: CaptureCommandSuccess,
        blocks: [CaptureTaskBlock]
    ) -> Bool {
        guard !blocks.isEmpty else {
            return false
        }
        var available: [(target: String, text: String)] = []
        for block in blocks {
            for line in block.lines where line.change == .added || line.change == .changed {
                available.append((block.relativeTarget, stripped(line.text)))
            }
        }
        for preview in capture.previewBlockLines {
            let needle = stripped(preview)
            guard
                let match = available.firstIndex(where: {
                    $0.target == capture.relativeTarget && $0.text == needle
                })
            else {
                return false
            }
            available.remove(at: match)
        }
        return true
    }

    static func stripped(_ value: String) -> String {
        CapturePomodoroBlockPresentation.stripped(value)
    }
}
