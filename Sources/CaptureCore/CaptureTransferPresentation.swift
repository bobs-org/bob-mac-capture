import Foundation

/// One task moved by `bob capture`'s `>` transfer syntax. Bob owns source
/// resolution, move semantics, and link repair; the Mac client only displays
/// these returned records.
public struct CaptureTransferMove: Codable, Equatable, Sendable {
    public let sourcePath: String
    public let destinationPath: String
    public let sourceLine: Int
    public let title: String
    public let oldBlockID: String?
    public let newBlockID: String?
    public let oldDependencyID: String?
    public let newDependencyID: String?

    public init(
        sourcePath: String = "",
        destinationPath: String = "",
        sourceLine: Int = 0,
        title: String = "",
        oldBlockID: String? = nil,
        newBlockID: String? = nil,
        oldDependencyID: String? = nil,
        newDependencyID: String? = nil
    ) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.sourceLine = sourceLine
        self.title = title
        self.oldBlockID = oldBlockID
        self.newBlockID = newBlockID
        self.oldDependencyID = oldDependencyID
        self.newDependencyID = newDependencyID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = (try? container.decode(String.self, forKey: .sourcePath)) ?? ""
        destinationPath = (try? container.decode(String.self, forKey: .destinationPath)) ?? ""
        sourceLine = (try? container.decode(Int.self, forKey: .sourceLine)) ?? 0
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        oldBlockID = try? container.decodeIfPresent(String.self, forKey: .oldBlockID)
        newBlockID = try? container.decodeIfPresent(String.self, forKey: .newBlockID)
        oldDependencyID = try? container.decodeIfPresent(String.self, forKey: .oldDependencyID)
        newDependencyID = try? container.decodeIfPresent(String.self, forKey: .newDependencyID)
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePath = "source_path"
        case destinationPath = "destination_path"
        case sourceLine = "source_line"
        case title
        case oldBlockID = "old_block_id"
        case newBlockID = "new_block_id"
        case oldDependencyID = "old_dependency_id"
        case newDependencyID = "new_dependency_id"
    }
}

/// A descriptor from Bob's `merges[]` result. The same tolerant shape works
/// for source and destination records; fields that do not apply to a target
/// are absent.
public struct CaptureTransferTaskDescriptor: Codable, Equatable, Sendable {
    public let path: String
    public let blockID: String?
    public let line: Int?
    public let title: String?
    public let drawer: String?
    public let section: String?
    public let kind: String?

    public init(
        path: String = "",
        blockID: String? = nil,
        line: Int? = nil,
        title: String? = nil,
        drawer: String? = nil,
        section: String? = nil,
        kind: String? = nil
    ) {
        self.path = path
        self.blockID = blockID
        self.line = line
        self.title = title
        self.drawer = drawer
        self.section = section
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decode(String.self, forKey: .path)) ?? ""
        blockID = try? container.decodeIfPresent(String.self, forKey: .blockID)
        line = try? container.decodeIfPresent(Int.self, forKey: .line)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        drawer = try? container.decodeIfPresent(String.self, forKey: .drawer)
        section = try? container.decodeIfPresent(String.self, forKey: .section)
        kind = try? container.decodeIfPresent(String.self, forKey: .kind)
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case blockID = "block_id"
        case line
        case title
        case drawer
        case section
        case kind
    }
}

/// Bob's source-ordered result for one task merge in a capture transfer.
/// Its message is Bob-authored consequence copy and is displayed verbatim.
public struct CaptureTransferMerge: Codable, Equatable, Sendable {
    public let source: CaptureTransferTaskDescriptor
    public let target: CaptureTransferTaskDescriptor
    public let label: String
    public let outcome: String
    public let previousStatus: String?
    public let movedLines: Int
    public let movedNotes: Int
    public let message: String

    public init(
        source: CaptureTransferTaskDescriptor = CaptureTransferTaskDescriptor(),
        target: CaptureTransferTaskDescriptor = CaptureTransferTaskDescriptor(),
        label: String = "",
        outcome: String = "",
        previousStatus: String? = nil,
        movedLines: Int = 0,
        movedNotes: Int = 0,
        message: String = ""
    ) {
        self.source = source
        self.target = target
        self.label = label
        self.outcome = outcome
        self.previousStatus = previousStatus
        self.movedLines = movedLines
        self.movedNotes = movedNotes
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? container.decode(CaptureTransferTaskDescriptor.self, forKey: .source))
            ?? CaptureTransferTaskDescriptor()
        target = (try? container.decode(CaptureTransferTaskDescriptor.self, forKey: .target))
            ?? CaptureTransferTaskDescriptor()
        label = (try? container.decode(String.self, forKey: .label)) ?? ""
        outcome = (try? container.decode(String.self, forKey: .outcome)) ?? ""
        previousStatus = try? container.decodeIfPresent(String.self, forKey: .previousStatus)
        movedLines = (try? container.decode(Int.self, forKey: .movedLines)) ?? 0
        movedNotes = (try? container.decode(Int.self, forKey: .movedNotes)) ?? 0
        message = (try? container.decode(String.self, forKey: .message)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case target
        case label
        case outcome
        case previousStatus = "previous_status"
        case movedLines = "moved_lines"
        case movedNotes = "moved_notes"
        case message
    }
}

/// One vault file Bob repaired after a transfer move.
public struct CaptureTransferRepairedFile: Codable, Equatable, Sendable {
    public let path: String
    public let linkCount: Int
    public let dependencyTokenCount: Int

    public init(path: String = "", linkCount: Int = 0, dependencyTokenCount: Int = 0) {
        self.path = path
        self.linkCount = linkCount
        self.dependencyTokenCount = dependencyTokenCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decode(String.self, forKey: .path)) ?? ""
        linkCount = (try? container.decode(Int.self, forKey: .linkCount)) ?? 0
        dependencyTokenCount =
            (try? container.decode(Int.self, forKey: .dependencyTokenCount)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case linkCount = "link_count"
        case dependencyTokenCount = "dependency_token_count"
    }
}

/// Presentation for Bob's `moves[]` transfer results. No task resolution,
/// destination selection, or link-repair math happens in the client.
public struct CaptureTransferMovePresentation: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let text: String
        public let accessibilityText: String

        public init(text: String, accessibilityText: String) {
            self.text = text
            self.accessibilityText = accessibilityText
        }
    }

    public let headerText: String
    public let rows: [Row]
    public let repairFooterText: String?
    public let primaryActionTitle: String
    public let notificationTitle: String
    public let notificationBody: String
    public let previewAccessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard !capture.moves.isEmpty else { return nil }
        let destination = Self.displayPath(capture.moves[0].destinationPath)
        let count = capture.moves.count
        let noun = count == 1 ? "task" : "tasks"
        headerText = "↪ Moves \(count) \(noun) into \(destination)"
        rows = capture.moves.map { move in
            let identity = Self.identity(from: move)
            let location = "\(Self.displayPath(move.sourcePath)):\(move.sourceLine)"
            let destinationPath = Self.displayPath(move.destinationPath)
            let text = "\(identity) \(location) → \(destinationPath)  \(move.title)"
            let spokenIdentity = identity == "(no block ID)" ? "" : ", \(identity)"
            return Row(
                text: text,
                accessibilityText:
                    "\(move.title), moved from \(location) into \(destinationPath)\(spokenIdentity)"
            )
        }

        let repairedLinks = capture.repairedFiles.reduce(0) { $0 + $1.linkCount }
        let repairedNotes = capture.repairedFiles.filter { $0.linkCount > 0 }.count
        if repairedLinks > 0 {
            let linkNoun = repairedLinks == 1 ? "link" : "links"
            let noteNoun = repairedNotes == 1 ? "note" : "notes"
            repairFooterText =
                "\(repairedLinks) \(linkNoun) repaired in \(repairedNotes) \(noteNoun)"
        } else {
            repairFooterText = nil
        }

        primaryActionTitle = "Move"
        let verb = capture.dryRun ? "Would move" : "Moved"
        notificationTitle = "\(verb) \(count) \(noun) into \(destination)"
        notificationBody =
            ([headerText] + rows.map(\.text) + (repairFooterText.map { [$0] } ?? []))
            .joined(separator: "\n")
        previewAccessibilitySummary =
            ([headerText] + rows.map(\.accessibilityText)
                + (repairFooterText.map { [$0] } ?? []))
            .joined(separator: "; ")
    }

    private static func identity(from move: CaptureTransferMove) -> String {
        if let oldID = move.oldBlockID, let newID = move.newBlockID, oldID != newID {
            return "^\(oldID) → ^\(newID)"
        }
        if let blockID = move.newBlockID ?? move.oldBlockID {
            return "^\(blockID)"
        }
        return "(no block ID)"
    }

    private static func displayPath(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }
}

/// Presentation for Bob's `merges[]` transfer results. Row details are the
/// exact consequence sentences Bob returned, including status and note counts.
public struct CaptureTransferMergePresentation: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let text: String

        public init(text: String) {
            self.text = text
        }
    }

    public let headerText: String
    public let targetLabel: String
    public let rows: [Row]
    public let primaryActionTitle: String
    public let notificationTitle: String
    public let notificationBody: String
    public let previewAccessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard !capture.merges.isEmpty else { return nil }
        let first = capture.merges[0].target
        let resolvedTargetLabel: String
        if let drawer = first.drawer, !drawer.isEmpty {
            resolvedTargetLabel = "\(drawer) in \(first.title ?? Self.displayPath(first.path))"
        } else if let section = first.section, !section.isEmpty {
            resolvedTargetLabel = "\(section) in \(Self.displayPath(first.path))"
        } else if let title = first.title, !title.isEmpty {
            resolvedTargetLabel = title
        } else {
            resolvedTargetLabel = Self.displayPath(first.path)
        }
        targetLabel = resolvedTargetLabel

        let count = capture.merges.count
        let noun = count == 1 ? "task" : "tasks"
        headerText = "⤵ Merges \(count) \(noun) into \(targetLabel)"
        rows = capture.merges.map { merge in
            let text = merge.message.isEmpty
                ? "\(merge.source.title ?? merge.source.blockID ?? "Task") → \(resolvedTargetLabel)"
                : merge.message
            return Row(text: text)
        }
        primaryActionTitle = "Merge"
        let verb = capture.dryRun ? "Would merge" : "Merged"
        notificationTitle = "\(verb) \(count) \(noun) into \(targetLabel)"
        notificationBody = rows.map(\.text).joined(separator: "\n")
        previewAccessibilitySummary =
            ([headerText] + rows.map(\.text)).joined(separator: "; ")
    }

    private static func displayPath(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }
}
