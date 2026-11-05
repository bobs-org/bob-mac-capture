import Foundation

/// Pure presentation model for one batch-level parent-task block
/// (`task_blocks` on a `bob capture --format json` success), built once
/// from `CaptureTaskBlock` so the SwiftUI layer never branches on block
/// JSON fields. The preview's only source of truth is Bob's resolved
/// block — which itself comes from `bob capture --dry-run [--no-clip]
/// --format json` for live preview (`--no-clip` is omitted only for a `%c`
/// draft) and the same command resolving the clipboard for submission — so
/// there is no Swift-side vault logic here, only wording. Works for
/// dry-run previews and committed captures alike; `dryRun` only changes
/// the created badge.
public struct CaptureTaskBlockPresentation: Equatable, Sendable {
    public enum TransferRole: Equatable, Sendable {
        case mergeTarget
        case mergeSource
        case moved
    }

    public enum FoldStyle: Equatable, Sendable {
        case unchanged
        case movedNotes
    }

    /// One collapsed run of block rows. `id` is the first hidden row
    /// index, stable for the card's identity so expansion survives
    /// re-renders; `depth` is the run's shallowest depth, where the fold
    /// row renders with indent guides.
    public struct FoldRun: Equatable, Sendable {
        public let id: Int
        public let count: Int
        public let depth: Int
        public let rows: [CaptureBlockDiffRow]
        public let style: FoldStyle

        public init(
            id: Int,
            count: Int,
            depth: Int,
            rows: [CaptureBlockDiffRow],
            style: FoldStyle = .unchanged
        ) {
            self.id = id
            self.count = count
            self.depth = depth
            self.rows = rows
            self.style = style
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
        public let transferRole: TransferRole?

        public init(
            relativeTarget: String,
            line: Int,
            blockID: String?,
            transferRole: TransferRole? = nil
        ) {
            self.relativeTarget = relativeTarget
            self.line = line
            self.blockID = blockID
            self.transferRole = transferRole
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
    public let roleBadgeText: String?
    public let movedFromCaption: String?
    public let transferRole: TransferRole?
    public let rows: [CaptureBlockDiffRow]
    public let identity: Identity
    public let accessibilitySummary: String

    public init(
        block: CaptureTaskBlock,
        dryRun: Bool,
        suppressRelationshipLines: Bool = false,
        keepMovingRows: [TaskCompleteUnblocked] = []
    ) {
        let symbol = block.statusSymbol.isEmpty ? nil : block.statusSymbol
        status = CapturePickerTaskStatus(symbol: symbol, name: block.statusName)
        if block.statusName.isEmpty || block.statusName == "Unknown" {
            statusText = status.displayName
        } else {
            statusText = block.statusName
        }
        badgeText = block.created ? (dryRun ? "New" : "Created") : nil
        transferRole = Self.transferRole(for: block.roles)
        roleBadgeText =
            switch transferRole {
            case .mergeTarget: "Merge target"
            case .mergeSource: "Merged"
            case .moved: "Moved"
            case nil: nil
            }
        if let movedFrom = block.movedFrom,
            !movedFrom.relativeTarget.isEmpty,
            movedFrom.line > 0
        {
            movedFromCaption = "from \(movedFrom.relativeTarget):\(movedFrom.line)"
        } else {
            movedFromCaption = nil
        }
        if let movedFromCaption {
            captionText =
                "\(statusText) · \(block.relativeTarget) · line \(block.line) · \(movedFromCaption)"
        } else {
            captionText = "\(statusText) · \(block.relativeTarget) · line \(block.line)"
        }
        identity = Identity(
            relativeTarget: block.relativeTarget,
            line: block.line,
            blockID: block.blockID,
            transferRole: transferRole
        )
        let shouldSuppressRelationshipLines = suppressRelationshipLines && !block.hasTransferRole
        let visibleLines: [CaptureBlockLine]
        if shouldSuppressRelationshipLines {
            visibleLines = block.lines.filter { !Self.isManagedRelationshipLine($0.text) }
        } else {
            visibleLines = block.lines
        }
        rows = visibleLines.enumerated().map { index, line in
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
                ),
                isUnblocked: line.change == .added && line.reason == "unblocked",
                isKeepMoving: line.change == .added && line.reason == "keep_moving",
                isRelationSuccessor: line.change == .added && line.reason == "relation",
                keepMovingProjectName: Self.keepMovingProjectName(
                    in: line,
                    rows: keepMovingRows
                )
            )
        }

        var summary = "\(block.text), \(statusText), \(block.relativeTarget) line \(block.line)"
        if let roleBadgeText {
            summary += ", \(roleBadgeText)"
        }
        if let movedFromCaption {
            summary += ", \(movedFromCaption)"
        }
        if let badgeText {
            summary += ", \(badgeText)"
        }
        let spokenRows = rows.map { row -> String in
            switch row.change {
            case .added:
                if row.isKeepMoving {
                    return "added \(row.content), keep-moving offer"
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

    private static func keepMovingProjectName(
        in line: CaptureBlockLine,
        rows: [TaskCompleteUnblocked]
    ) -> String? {
        guard line.reason == "keep_moving",
              let row = rows.first(where: { !$0.text.isEmpty && line.text.contains($0.text) })
        else {
            return nil
        }
        let path = row.offer?.project ?? row.notePath
        guard !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private static func transferRole(for roles: [String]) -> TransferRole? {
        if roles.contains("merge_target") {
            return .mergeTarget
        }
        if roles.contains("merge_source") {
            return .mergeSource
        }
        if roles.contains("moved") {
            return .moved
        }
        return nil
    }

    private static func isManagedRelationshipLine(_ line: String) -> Bool {
        line.contains("**DEPENDS ON:**") || line.contains("**BLOCKS:**")
            || line.contains("**LINKS:**") || line.contains("**LINKS TO:**")
            || line.contains("**LINKED FROM:**") || line.contains("**BACKLINKS:**")
    }

    /// Rows and folds to render: the task line, every non-`unchanged`
    /// row, `contextRadius` rows on each side of a change, and each
    /// change's structural ancestors (the nearest preceding row at each
    /// shallower depth). Any other run of at least `minimumFoldRun`
    /// unchanged rows collapses into one fold row; folds whose id is in
    /// `expandedFolds` inline their rows instead. Blocks at or below
    /// `foldThreshold` rows, and blocks with no changes, never fold.
    public func items(expandedFolds: Set<Int>) -> [Item] {
        Self.items(
            for: rows,
            expandedFolds: expandedFolds,
            foldRemovedRuns: transferRole == .mergeSource
        )
    }

    /// Shared task and section folding. Merge-source tombstones fold each
    /// contiguous removed run; other blocks fold only long quiet runs.
    public static func items(
        for rows: [CaptureBlockDiffRow],
        expandedFolds: Set<Int>,
        foldRemovedRuns: Bool = false
    ) -> [Item] {
        let hasRemovedRuns = foldRemovedRuns && rows.contains { $0.change == .removed }
        let hasQuietChanges = rows.count > Self.foldThreshold
            && rows.contains(where: { $0.change != .unchanged })
        guard hasRemovedRuns || hasQuietChanges else {
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
                                rows: foldRows,
                                style: .unchanged
                            )
                        )
                    )
                }
            } else {
                result.append(contentsOf: hidden.map { Item.row(rows[$0]) })
            }
            hidden.removeAll(keepingCapacity: true)
        }
        var index = 0
        while index < rows.count {
            if foldRemovedRuns, rows[index].change == .removed {
                flushHidden()
                let start = index
                while index < rows.count, rows[index].change == .removed {
                    index += 1
                }
                let removed = Array(rows[start..<index])
                if expandedFolds.contains(start) {
                    result.append(contentsOf: removed.map(Item.row))
                } else {
                    result.append(
                        .fold(
                            FoldRun(
                                id: start,
                                count: removed.count,
                                depth: removed.map(\.depth).min() ?? 0,
                                rows: removed,
                                style: .movedNotes
                            )
                        )
                    )
                }
                continue
            }
            if visible.contains(index) {
                flushHidden()
                result.append(.row(rows[index]))
            } else {
                hidden.append(index)
            }
            index += 1
        }
        flushHidden()
        return result
    }

    /// True when the task blocks already show every verbatim preview line
    /// of a sub-bullet capture, so the standard item can omit its
    /// `previewBlockLines` stack: blocks is non-empty and every preview
    /// line, with leading whitespace stripped, matches a distinct `added`
    /// or `changed` row, likewise stripped, of a task block filed under
    /// the capture's own `relativeTarget`. A `task_dependency` also treats
    /// every line of the owner block as covering, whatever its change
    /// kind, so an unchanged owner line is not repeated under the owner
    /// header. Matching is one-to-one, so duplicate bullets in one item
    /// each need their own row. Stripping is required because Bob's
    /// `task_line` is unindented while the block line carries the parent's
    /// child indentation.
    public static func covers(
        _ capture: CaptureCommandSuccess,
        blocks: [CaptureTaskBlock]
    ) -> Bool {
        guard !blocks.isEmpty else {
            return false
        }
        let isTaskDependency = CaptureRelationshipPresentation.isTaskDependency(capture)
        var available: [(target: String, text: String)] = []
        for block in blocks {
            let isOwnerBlock = isTaskDependency
                && block.relativeTarget == capture.relativeTarget
                && block.blockID != nil
                && block.blockID == capture.blockID
            for line in block.lines {
                if isOwnerBlock || line.change == .added || line.change == .changed {
                    available.append((block.relativeTarget, stripped(line.text)))
                }
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

/// Pure presentation for a batch-level section target (`section_blocks`).
/// It shares task-block diff folding and row rendering while keeping the
/// heading and locator in the section-specific caption.
public struct CaptureSectionBlockPresentation: Equatable, Sendable {
    public struct Identity: Equatable, Sendable {
        public let relativeTarget: String
        public let line: Int
        public let heading: String

        public init(relativeTarget: String, line: Int, heading: String) {
            self.relativeTarget = relativeTarget
            self.line = line
            self.heading = heading
        }
    }

    public let captionText: String
    public let badgeText: String?
    public let rows: [CaptureBlockDiffRow]
    public let identity: Identity
    public let accessibilitySummary: String

    public init(block: CaptureSectionBlock, dryRun: Bool) {
        captionText = "§ \(block.heading) · \(block.relativeTarget) · line \(block.line)"
        badgeText = block.created ? (dryRun ? "New" : "Created") : nil
        identity = Identity(
            relativeTarget: block.relativeTarget,
            line: block.line,
            heading: block.heading
        )
        rows = block.lines.enumerated().map { index, line in
            let content = CaptureTaskBlockPresentation.stripped(line.text)
            return CaptureBlockDiffRow(
                content: content,
                depth: min(max(line.depth, 0), CapturePomodoroBlockPresentation.maxDepth),
                change: line.change,
                beforeContent: line.before.map {
                    CaptureTaskBlockPresentation.stripped($0)
                },
                isHeadline: index == 0,
                tokens: CapturePomodoroLineTokens.tokenize(content, isHeadline: false)
            )
        }
        var summary = "Section \(block.heading), \(block.relativeTarget) line \(block.line)"
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

    public func items(expandedFolds: Set<Int>) -> [CaptureTaskBlockPresentation.Item] {
        CaptureTaskBlockPresentation.items(for: rows, expandedFolds: expandedFolds)
    }
}

/// Inserts each section target immediately before its first matching merge
/// source while leaving Bob's task-block sequence untouched.
public enum CaptureLandingBlockOrdering {
    public static func sectionInsertions(
        sections: [CaptureSectionBlock],
        taskBlocks: [CaptureTaskBlock],
        merges: [CaptureTransferMerge]
    ) -> [[CaptureSectionBlock]] {
        var insertions = Array(repeating: [CaptureSectionBlock](), count: taskBlocks.count + 1)
        for section in sections {
            let sourceKeys = merges.compactMap { merge -> (String, String)? in
                guard merge.target.kind == "section",
                    merge.target.path == section.relativeTarget,
                    merge.target.section == section.heading,
                    !merge.source.path.isEmpty,
                    let blockID = merge.source.blockID
                else {
                    return nil
                }
                return (merge.source.path, blockID)
            }
            let firstSource = taskBlocks.firstIndex { block in
                block.roles.contains("merge_source")
                    && sourceKeys.contains {
                        $0.0 == block.relativeTarget && $0.1 == block.blockID
                    }
            }
            insertions[firstSource ?? 0].append(section)
        }
        return insertions
    }
}
