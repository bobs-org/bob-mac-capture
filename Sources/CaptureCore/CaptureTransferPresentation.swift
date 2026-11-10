import Foundation

/// Decodes arrays whose individual additive rows may be malformed. One bad
/// optional transfer row must not hide the other rows or the capture itself.
struct CaptureLossyArray<Element: Decodable>: Decodable {
    let values: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []
        while !container.isAtEnd {
            // `decode` can leave some unkeyed containers on the same element
            // after a type mismatch. Claim the slot first so one malformed
            // additive row cannot trap decoding in this loop.
            let elementDecoder = try container.superDecoder()
            if let value = try? Element(from: elementDecoder) {
                values.append(value)
            }
        }
        self.values = values
    }
}

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
    public let destinationLine: Int?
    public let destinationSection: String?
    public let statusSymbol: String?
    public let statusName: String?

    public init(
        sourcePath: String = "",
        destinationPath: String = "",
        sourceLine: Int = 0,
        title: String = "",
        oldBlockID: String? = nil,
        newBlockID: String? = nil,
        oldDependencyID: String? = nil,
        newDependencyID: String? = nil,
        destinationLine: Int? = nil,
        destinationSection: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil
    ) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.sourceLine = sourceLine
        self.title = title
        self.oldBlockID = oldBlockID
        self.newBlockID = newBlockID
        self.oldDependencyID = oldDependencyID
        self.newDependencyID = newDependencyID
        self.destinationLine = destinationLine
        self.destinationSection = destinationSection
        self.statusSymbol = statusSymbol
        self.statusName = statusName
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
        destinationLine = try? container.decodeIfPresent(Int.self, forKey: .destinationLine)
        destinationSection = try? container.decodeIfPresent(String.self, forKey: .destinationSection)
        statusSymbol = try? container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try? container.decodeIfPresent(String.self, forKey: .statusName)
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
        case destinationLine = "destination_line"
        case destinationSection = "destination_section"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
    }
}

/// A descriptor from Bob's `merges[]` result. The same tolerant shape works
/// for source and destination records; fields that do not apply are absent.
public struct CaptureTransferTaskDescriptor: Codable, Equatable, Sendable {
    public let path: String
    public let blockID: String?
    public let line: Int?
    public let title: String?
    public let drawer: String?
    public let section: String?
    public let kind: String?
    public let created: Bool?
    public let statusSymbol: String?
    public let statusName: String?

    public init(
        path: String = "",
        blockID: String? = nil,
        line: Int? = nil,
        title: String? = nil,
        drawer: String? = nil,
        section: String? = nil,
        kind: String? = nil,
        created: Bool? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil
    ) {
        self.path = path
        self.blockID = blockID
        self.line = line
        self.title = title
        self.drawer = drawer
        self.section = section
        self.kind = kind
        self.created = created
        self.statusSymbol = statusSymbol
        self.statusName = statusName
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
        created = try? container.decodeIfPresent(Bool.self, forKey: .created)
        statusSymbol = try? container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try? container.decodeIfPresent(String.self, forKey: .statusName)
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case blockID = "block_id"
        case line
        case title
        case drawer
        case section
        case kind
        case created
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
    }
}

/// One Bob-authored effect of a merge. The Mac displays `text` and never
/// reconstructs a consequence from keys, counts, or the vault.
public struct CaptureTransferConsequence: Codable, Equatable, Sendable {
    public let kind: String
    public let tone: String
    public let text: String
    public let keys: [String]

    public init(kind: String = "", tone: String = "info", text: String = "", keys: [String] = []) {
        self.kind = kind
        self.tone = tone
        self.text = text
        self.keys = keys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? container.decode(String.self, forKey: .kind)) ?? ""
        tone = (try? container.decode(String.self, forKey: .tone)) ?? "info"
        text = (try? container.decode(String.self, forKey: .text)) ?? ""
        keys = (try? container.decode([String].self, forKey: .keys)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case tone
        case text
        case keys
    }
}

/// Bob's source-ordered result for one task merge in a capture transfer.
public struct CaptureTransferMerge: Codable, Equatable, Sendable {
    public let source: CaptureTransferTaskDescriptor
    public let target: CaptureTransferTaskDescriptor
    public let label: String
    public let outcome: String
    public let previousStatus: String?
    public let previousStatusName: String?
    public let statusSymbol: String?
    public let statusName: String?
    public let movedLines: Int
    public let movedNotes: Int
    public let message: String
    public let consequences: [CaptureTransferConsequence]

    public init(
        source: CaptureTransferTaskDescriptor = CaptureTransferTaskDescriptor(),
        target: CaptureTransferTaskDescriptor = CaptureTransferTaskDescriptor(),
        label: String = "",
        outcome: String = "",
        previousStatus: String? = nil,
        previousStatusName: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        movedLines: Int = 0,
        movedNotes: Int = 0,
        message: String = "",
        consequences: [CaptureTransferConsequence] = []
    ) {
        self.source = source
        self.target = target
        self.label = label
        self.outcome = outcome
        self.previousStatus = previousStatus
        self.previousStatusName = previousStatusName
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.movedLines = movedLines
        self.movedNotes = movedNotes
        self.message = message
        self.consequences = consequences
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
        previousStatusName = try? container.decodeIfPresent(String.self, forKey: .previousStatusName)
        statusSymbol = try? container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try? container.decodeIfPresent(String.self, forKey: .statusName)
        movedLines = (try? container.decode(Int.self, forKey: .movedLines)) ?? 0
        movedNotes = (try? container.decode(Int.self, forKey: .movedNotes)) ?? 0
        message = (try? container.decode(String.self, forKey: .message)) ?? ""
        consequences =
            (try? container.decode(CaptureLossyArray<CaptureTransferConsequence>.self, forKey: .consequences))?
            .values ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case target
        case label
        case outcome
        case previousStatus = "previous_status"
        case previousStatusName = "previous_status_name"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case movedLines = "moved_lines"
        case movedNotes = "moved_notes"
        case message
        case consequences
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

/// Pure card, status, notification, and VoiceOver content for one Bob transfer
/// result. Bob supplies every title, status, destination, and consequence.
public struct CaptureTransferPresentation: Equatable, Sendable {
    public enum Verb: Equatable, Sendable {
        case move
        case merge

        public var actionText: String { self == .move ? "Move" : "Merge" }
        public var gerund: String { self == .move ? "moving" : "merging" }
        public var glyph: String { self == .move ? "arrow.right" : "arrow.triangle.merge" }
    }

    public enum State: Equatable, Sendable {
        case planned
        case alreadyMerged
    }

    public struct SourceRow: Equatable, Sendable {
        public let title: TaskDisplayText
        public let status: CapturePickerTaskStatus?
        public let targetStatus: CapturePickerTaskStatus?
        public let statusName: String?
        public let targetStatusName: String?
        public let locator: String
        public let detailText: String?
        public let detailIsRename: Bool
        public let fallback: Bool
    }

    public struct DestinationRow: Equatable, Sendable {
        public let kind: String
        public let title: TaskDisplayText
        public let hasTitle: Bool
        public let status: CapturePickerTaskStatus?
        public let statusName: String?
        public let relativePath: String
        public let locator: String
        public let containerLabel: String?
        public let isNew: Bool
    }

    public struct ConsequenceRow: Equatable, Sendable {
        public let kind: String
        public let tone: String
        public let text: String
        public let symbol: String
    }

    public let verb: Verb
    public let state: State
    public let sourceRows: [SourceRow]
    public let destination: DestinationRow
    public let consequences: [ConsequenceRow]
    public let repairText: String?
    public let offers: [TaskCompleteUnblocked]
    public let statusLineText: String
    public let notificationTitle: String
    public let notificationBody: String
    public let previewAccessibilitySummary: String
    public let alreadyMergedText: String?

    public var primaryActionTitle: String { verb.actionText }

    public init?(capture: CaptureCommandSuccess) {
        guard capture.kind == "task_move" || capture.kind == "task_merge",
              !capture.moves.isEmpty || !capture.merges.isEmpty
        else {
            return nil
        }

        let isMove = !capture.moves.isEmpty
        verb = isMove ? .move : .merge
        let mergesAreUnchanged = !capture.merges.isEmpty
            && capture.merges.allSatisfy { $0.outcome == "unchanged" }
        state = mergesAreUnchanged ? .alreadyMerged : .planned
        offers = capture.mergeOffers

        if isMove {
            let moves = capture.moves
            sourceRows = moves.map { move in
                let status = move.statusSymbol == nil && move.statusName == nil
                    ? nil
                    : CapturePickerTaskStatus(symbol: move.statusSymbol, name: move.statusName)
                return SourceRow(
                    title: TaskDisplayText(parsing: move.title),
                    status: status,
                    targetStatus: status,
                    statusName: move.statusName,
                    targetStatusName: move.statusName,
                    locator: Self.locator(path: move.sourcePath, line: move.sourceLine),
                    detailText: Self.moveDetail(move),
                    detailIsRename: Self.isMoveRename(move),
                    fallback: false
                )
            }
            let first = moves[0]
            let path = Self.displayPath(first.destinationPath)
            let section = first.destinationSection.flatMap { $0.isEmpty ? nil : $0 }
            let containerLabel = section.map { "› \($0)" }
            destination = DestinationRow(
                kind: "note",
                title: TaskDisplayText(parsing: path),
                hasTitle: false,
                status: nil,
                statusName: nil,
                relativePath: first.destinationPath,
                locator: Self.locator(path: first.destinationPath, line: first.destinationLine),
                containerLabel: containerLabel,
                isNew: false
            )
            consequences = []
        } else {
            let merges = capture.merges
            let hasEnrichedMerge = merges.contains { $0.statusName != nil }
            sourceRows = merges.map { merge in
                if hasEnrichedMerge && merge.statusName != nil {
                    return SourceRow(
                        title: TaskDisplayText(parsing: merge.source.title ?? "Task"),
                        status: CapturePickerTaskStatus(
                            symbol: merge.previousStatus,
                            name: merge.previousStatusName
                        ),
                        targetStatus: CapturePickerTaskStatus(
                            symbol: merge.statusSymbol,
                            name: merge.statusName
                        ),
                        statusName: merge.previousStatusName,
                        targetStatusName: merge.statusName,
                        locator: Self.locator(path: merge.source.path, line: merge.source.line),
                        detailText: Self.mergeDetail(merge),
                        detailIsRename: false,
                        fallback: false
                    )
                }
                return SourceRow(
                    title: TaskDisplayText(parsing: merge.message.isEmpty
                        ? merge.source.title ?? "Task"
                        : merge.message),
                    status: nil,
                    targetStatus: nil,
                    statusName: nil,
                    targetStatusName: nil,
                    locator: Self.locator(path: merge.source.path, line: merge.source.line),
                    detailText: nil,
                    detailIsRename: false,
                    fallback: true
                )
            }
            let target = merges[0].target
            let bobTitle = target.title.flatMap { $0.isEmpty ? nil : $0 }
            let targetTitle = bobTitle ?? Self.displayPath(target.path)
            destination = DestinationRow(
                kind: target.kind ?? "task",
                title: TaskDisplayText(parsing: targetTitle),
                hasTitle: bobTitle != nil,
                status: target.statusSymbol == nil && target.statusName == nil
                    ? nil
                    : CapturePickerTaskStatus(symbol: target.statusSymbol, name: target.statusName),
                statusName: target.statusName,
                relativePath: target.path,
                locator: Self.locator(path: target.path, line: target.line),
                containerLabel: Self.containerLabel(for: target),
                isNew: target.created == true
            )
            consequences = merges.flatMap(\.consequences).compactMap { consequence in
                guard !consequence.text.isEmpty else { return nil }
                return ConsequenceRow(
                    kind: consequence.kind,
                    tone: consequence.tone,
                    text: consequence.text,
                    symbol: Self.consequenceSymbol(for: consequence.kind)
                )
            }
        }

        let count = sourceRows.count
        let noun = count == 1 ? "task" : "tasks"
        let isDryRun = capture.dryRun
        let action = verb == .move ? "move" : "merge"
        let prefix = isDryRun ? "Would \(action)" : (verb == .move ? "Moved" : "Merged")
        let destinationText = Self.statusDestinationText(verb: verb, destination: destination)
        statusLineText = "\(prefix) \(count) \(noun) into \(destinationText)"
        let quotedTarget = Self.notificationDestinationText(verb: verb, destination: destination)
        notificationTitle = "\(prefix) \(count) \(noun) into \(quotedTarget)"

        let repairedLinks = capture.repairedFiles.reduce(0) { $0 + $1.linkCount }
        let repairedNotes = capture.repairedFiles.filter { $0.linkCount > 0 }.count
        if repairedLinks > 0 {
            repairText = "\(repairedLinks) link\(repairedLinks == 1 ? "" : "s") repaired in "
                + "\(repairedNotes) note\(repairedNotes == 1 ? "" : "s")"
        } else {
            repairText = nil
        }

        if state == .alreadyMerged {
            let announced = Self.announcementDestinationText(destination: destination)
            alreadyMergedText = "Already merged into \(announced)"
        } else {
            alreadyMergedText = nil
        }
        let sourceLines = sourceRows.map(Self.notificationLine)
        notificationBody = (sourceLines + consequences.map(\.text) + (repairText.map { [$0] } ?? []))
            .joined(separator: "\n")

        let spokenSources = sourceRows.map(Self.accessibilityLine)
        var summary = [statusLineText]
        if state == .alreadyMerged {
            summary.append(alreadyMergedText ?? "Already merged")
            summary.append("Nothing to write")
        } else {
            summary.append(contentsOf: spokenSources)
            var destinationSpeech: String
            if destination.hasTitle {
                destinationSpeech = "into \(destination.title.text)"
            } else {
                let untitled = Self.untitledDestinationPhrase(destination: destination)
                destinationSpeech = "into \(untitled)"
            }
            if let statusName = destination.statusName, !statusName.isEmpty {
                destinationSpeech += ", \(statusName)"
            }
            if !destination.locator.isEmpty {
                destinationSpeech += ", \(destination.locator)"
            }
            if destination.hasTitle,
                let container = destination.containerLabel, !container.isEmpty
            {
                destinationSpeech += ", \(container)"
            }
            if destination.isNew { destinationSpeech += ", new" }
            summary.append(destinationSpeech)
            summary.append(contentsOf: consequences.map(\.text))
            if let repairText { summary.append(repairText) }
            if !offers.isEmpty {
                summary.append("Pull-In offers: \(offers.map(\.text).joined(separator: ", "))")
            }
        }
        previewAccessibilitySummary = summary.joined(separator: ". ")
    }

    private static func notificationLine(_ row: SourceRow) -> String {
        var parts = [row.title.text]
        if let source = row.statusName, let target = row.targetStatusName,
            !isSameStatus(row)
        {
            parts.append("\(source) → \(target)")
        }
        if let detail = row.detailText { parts.append(detail) }
        return parts.joined(separator: " · ")
    }

    private static func accessibilityLine(_ row: SourceRow) -> String {
        var parts = [row.title.text]
        if let source = row.statusName, let target = row.targetStatusName,
            !isSameStatus(row)
        {
            parts.append("\(source) to \(target)")
        }
        if !row.locator.isEmpty { parts.append(row.locator) }
        if let detail = row.detailText { parts.append(detail) }
        return parts.joined(separator: ", ")
    }

    /// True when a move renamed its block ID: both IDs present and different.
    /// Merges and fallbacks never set the flag; the words carry the rename
    /// so color is never the only signal.
    private static func isMoveRename(_ move: CaptureTransferMove) -> Bool {
        guard let oldID = move.oldBlockID, let newID = move.newBlockID else {
            return false
        }
        return oldID != newID
    }

    /// True when source and target status names and symbols are equal, so a
    /// move row shows no transition chip or `X → X` fragment. The leading
    /// status glyph already carries the status.
    private static func isSameStatus(_ row: SourceRow) -> Bool {
        row.status == row.targetStatus && row.statusName == row.targetStatusName
    }

    /// Unquoted destination phrase for merge targets Bob did not title: the
    /// display path plus the container label, e.g. `db.md § Future Work`.
    private static func untitledDestinationPhrase(destination: DestinationRow) -> String {
        let base = displayPath(destination.relativePath)
        if let container = destination.containerLabel, !container.isEmpty {
            return "\(base) \(container)"
        }
        return base
    }

    /// Destination wording for announcements and the already-merged line:
    /// the quoted title when Bob supplied one, else the unquoted phrase.
    public static func announcementDestinationText(destination: DestinationRow) -> String {
        guard destination.hasTitle else {
            return untitledDestinationPhrase(destination: destination)
        }
        return "“\(destination.title.text)”"
    }

    private static func moveDetail(_ move: CaptureTransferMove) -> String? {
        guard let newID = move.newBlockID ?? move.oldBlockID else { return nil }
        if let oldID = move.oldBlockID, oldID != newID {
            return "^\(oldID) → ^\(newID)"
        }
        return "^\(newID)"
    }

    /// Canonical merge source detail: `title only`, `1 note copied`, or
    /// `N notes copied`. Counts still come from Bob's `moved_notes` field.
    private static func mergeDetail(_ merge: CaptureTransferMerge) -> String {
        if merge.movedNotes == 0 {
            return "title only"
        }
        if merge.movedNotes == 1 {
            return "1 note copied"
        }
        return "\(merge.movedNotes) notes copied"
    }

    private static func statusDestinationText(
        verb: Verb,
        destination: DestinationRow
    ) -> String {
        if verb == .merge, !destination.hasTitle {
            return untitledDestinationPhrase(destination: destination)
        }
        let title = destination.title.text
        let base = verb == .merge ? "“\(title)” · \(displayPath(destination.relativePath))" : title
        if let container = destination.containerLabel, !container.isEmpty {
            return "\(base) \(container)"
        }
        return base
    }

    private static func notificationDestinationText(
        verb: Verb,
        destination: DestinationRow
    ) -> String {
        if verb == .merge { return announcementDestinationText(destination: destination) }
        return destination.title.text
    }

    private static func containerLabel(for target: CaptureTransferTaskDescriptor) -> String? {
        if let drawer = target.drawer, !drawer.isEmpty { return "› \(drawer.uppercased())" }
        if let section = target.section, !section.isEmpty { return "§ \(section)" }
        return nil
    }

    private static func consequenceSymbol(for kind: String) -> String {
        switch kind {
        case "dependent": return "link"
        case "prerequisite_left", "successor_orphaned": return "exclamationmark.triangle"
        case "link_pruned": return "minus.circle"
        default: return "info.circle"
        }
    }

    private static func locator(path: String, line: Int?) -> String {
        let name = displayPath(path)
        guard !name.isEmpty else { return "" }
        return line.map { "\(name):\($0)" } ?? name
    }

    private static func displayPath(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }
}
