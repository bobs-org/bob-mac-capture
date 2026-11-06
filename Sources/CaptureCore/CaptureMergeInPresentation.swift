import Foundation

/// Pure card, status, notification, and VoiceOver content for one new-task
/// merge-in result (`<` syntax). Bob owns source resolution, merge effects,
/// and copy; the Mac only displays what Bob returns
/// (`decisions:mac-capture-is-a-thin-client`). Built only from a nonempty
/// `merges[]` on a task-creating kind; transfer kinds keep their whole-card
/// `CaptureTransferPresentation` path and never route here.
public struct CaptureMergeInPresentation: Equatable, Sendable {
    private static let taskCreatingKinds: Set<String> = [
        "task",
        "pomodoro_task",
        "project_note",
        "pomodoro_project_note",
    ]

    public struct SourceRow: Equatable, Sendable {
        public let stableID: String
        public let title: TaskDisplayText
        public let status: CapturePickerTaskStatus?
        public let targetStatus: CapturePickerTaskStatus?
        public let statusName: String?
        public let targetStatusName: String?
        public let locator: String
        public let detailText: String?
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

    public let sourceRows: [SourceRow]
    public let destination: DestinationRow
    public let consequences: [ConsequenceRow]
    public let offers: [TaskCompleteUnblocked]
    public let isDryRun: Bool
    public let relativeTarget: String

    public init?(capture: CaptureCommandSuccess) {
        guard Self.taskCreatingKinds.contains(capture.kind),
            !capture.merges.isEmpty
        else {
            return nil
        }
        let merges = capture.merges
        let hasEnrichedMerge = merges.contains { $0.statusName != nil }
        sourceRows = merges.map { merge in
            let stableID = "\(merge.source.path)#^\(merge.source.blockID)"
            if hasEnrichedMerge, merge.statusName != nil {
                let movedText: String
                if merge.movedNotes == 0 {
                    movedText = "title only"
                } else if merge.movedNotes == 1 {
                    movedText = "1 note"
                } else {
                    movedText = "\(merge.movedNotes) notes"
                }
                return SourceRow(
                    stableID: stableID,
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
                    detailText: movedText,
                    fallback: false
                )
            }
            return SourceRow(
                stableID: stableID,
                title: TaskDisplayText(
                    parsing: merge.message.isEmpty
                        ? merge.source.title ?? "Task" : merge.message
                ),
                status: nil,
                targetStatus: nil,
                statusName: nil,
                targetStatusName: nil,
                locator: Self.locator(path: merge.source.path, line: merge.source.line),
                detailText: nil,
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
                : CapturePickerTaskStatus(
                    symbol: target.statusSymbol,
                    name: target.statusName
                ),
            statusName: target.statusName,
            relativePath: target.path,
            locator: Self.locator(path: target.path, line: target.line),
            containerLabel: Self.containerLabel(for: target),
            isNew: target.created == true
        )
        var seenKeys = Set<String>()
        var deduped: [ConsequenceRow] = []
        for consequence in merges.flatMap(\.consequences) {
            guard !consequence.text.isEmpty else { continue }
            let key = consequence.kind + "\u{0}" + consequence.keys.joined(separator: "\u{0}")
            guard seenKeys.insert(key).inserted else { continue }
            deduped.append(ConsequenceRow(
                kind: consequence.kind,
                tone: consequence.tone,
                text: consequence.text,
                symbol: Self.consequenceSymbol(for: consequence.kind)
            ))
        }
        consequences = deduped
        offers = capture.mergeOffers
        isDryRun = capture.dryRun
        relativeTarget = capture.relativeTarget
    }

    public var count: Int { sourceRows.count }

    private var noun: String { count == 1 ? "task" : "tasks" }

    /// Band header inside the new-task card.
    public var headerText: String {
        "⤵ Merging in \(count) \(noun)"
    }

    /// Label for the keyboard-accessible disclosure past three sources.
    public var disclosureLabel: String? {
        guard count > 3 else { return nil }
        return "Show all \(count)"
    }

    /// Footer primary action for a single merge-in item. Mixed/bulk drafts
    /// keep the aggregate `Capture` title in the panel model.
    public var primaryActionTitle: String {
        "Capture & merge \(count) \(noun)"
    }

    private var targetDisplayName: String {
        destination.hasTitle ? "“\(destination.title.text)”" : Self.displayPath(destination.relativePath)
    }

    /// Live preview status. Committed captures use the created wording.
    public var statusLineText: String {
        if isDryRun {
            return "Would create \(targetDisplayName) and merge \(count) \(noun) into it · \(Self.displayPath(relativeTarget))"
        }
        return "Created \(targetDisplayName) and merged \(count) \(noun) into it · \(Self.displayPath(relativeTarget))"
    }

    /// Committed notification title. Always the created wording.
    public var notificationTitle: String {
        "Created \(targetDisplayName) · merged \(count) \(noun)"
    }

    public var notificationBody: String {
        sourceRows.map(Self.notificationLine).joined(separator: "\n")
    }

    /// VoiceOver copy for a settled merge-in. The panel announces this only
    /// when Bob's resolved source set changes; the card keeps its visual glyph.
    public var settledAnnouncement: String {
        let sources = sourceRows.map(Self.spokenSourceLine).joined(separator: "; ")
        return [
            Self.destinationIdentity(destination, relativeTarget: relativeTarget),
            "Merging in \(count) \(noun): \(sources)",
        ].joined(separator: ". ")
    }

    public var previewAccessibilitySummary: String {
        let sources = sourceRows.map(Self.accessibilityLine).joined(separator: "; ")
        var summary = [
            Self.destinationIdentity(destination, relativeTarget: relativeTarget),
            "Merging in \(count) \(noun): \(sources)",
        ]
        summary.append(contentsOf: consequences.map(\.text))
        if !offers.isEmpty {
            summary.append("Pull-In offers: \(offers.map(\.text).joined(separator: ", "))")
        }
        return summary.joined(separator: ". ")
    }

    private static func destinationIdentity(
        _ destination: DestinationRow,
        relativeTarget: String
    ) -> String {
        var parts = ["New task \(destination.title.text)", displayPath(relativeTarget)]
        if destination.isNew { parts.append("new") }
        if let statusName = destination.statusName, !statusName.isEmpty {
            parts.append(statusName)
        }
        return parts.joined(separator: ", ")
    }

    private static func spokenSourceLine(_ row: SourceRow) -> String {
        guard !row.fallback else { return row.title.text }
        var parts = [row.title.text]
        if let source = row.statusName, let target = row.targetStatusName, source != target {
            parts.append("\(source) to \(target)")
        }
        if let detail = row.detailText { parts.append(detail) }
        return parts.joined(separator: ", ")
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
        guard !row.fallback else { return row.title.text }
        var parts = [row.title.text]
        if let source = row.statusName, let target = row.targetStatusName, source != target {
            parts.append("\(source) to \(target)")
        }
        if !row.locator.isEmpty { parts.append(row.locator) }
        if let detail = row.detailText { parts.append(detail) }
        return parts.joined(separator: ", ")
    }

    private static func isSameStatus(_ row: SourceRow) -> Bool {
        row.status == row.targetStatus && row.statusName == row.targetStatusName
    }

    private static func consequenceSymbol(for kind: String) -> String {
        switch kind {
        case "dependent": return "link"
        case "prerequisite_left", "successor_orphaned": return "exclamationmark.triangle"
        case "link_pruned": return "minus.circle"
        default: return "info.circle"
        }
    }

    private static func containerLabel(for target: CaptureTransferTaskDescriptor) -> String? {
        if let drawer = target.drawer, !drawer.isEmpty { return "› \(drawer.uppercased())" }
        if let section = target.section, !section.isEmpty { return "§ \(section)" }
        return nil
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

/// Calm pending copy for a merge-in whose sources are still being typed.
/// Never simulates a write; a source-less draft must not flash red.
public struct CaptureMergeInPendingPresentation: Equatable, Sendable {
    public struct SourceRow: Equatable, Sendable {
        public let title: TaskDisplayText?
        public let statusName: String?
        public let locator: String
        public let errorMessage: TaskDisplayText?
        public let mergeableMessage: String?
    }

    public static let prompt = "⤵ Merge tasks into this one — type + to pick"

    public let sourceRows: [SourceRow]
    public let targetTitle: TaskDisplayText?
    public let accessibilitySummary: String

    public init?(pending: CaptureMergeInPending, targetTitle: TaskDisplayText? = nil) {
        guard pending.need == "merge_in_source" else { return nil }
        self.targetTitle = targetTitle
        sourceRows = pending.sources.map { source in
            let title = source.title.map { TaskDisplayText(parsing: $0) }
            let locator: String
            if let path = source.path, !path.isEmpty {
                let name = (path as NSString).lastPathComponent
                locator = source.line.map { "\(name):\($0)" } ?? name
            } else {
                locator = ""
            }
            let errorMessage = source.error.map { TaskDisplayText(parsing: $0.message) }
            return SourceRow(
                title: title,
                statusName: source.statusName,
                locator: locator,
                errorMessage: errorMessage,
                mergeableMessage: source.mergeableMessage
            )
        }
        let count = sourceRows.count
        let spokenPrompt = Self.prompt
            .replacingOccurrences(of: "⤵", with: "")
            .trimmingCharacters(in: .whitespaces)
        let targetPrefix = targetTitle.map { "New task \($0.text). " } ?? ""
        if count == 0 {
            accessibilitySummary = targetPrefix + spokenPrompt
        } else {
            let rows = sourceRows.map { row in
                [row.title?.text, row.locator, row.errorMessage?.text ?? row.mergeableMessage]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            }
            let spokenRows = ([spokenPrompt] + rows).joined(separator: ". ")
            accessibilitySummary = targetPrefix + spokenRows
        }
    }

    /// Pending input is never submittable; ineligible sources stay visible inline.
    public var canSubmit: Bool { false }
}

/// Refusal copy for a merge-in the dry run rejected. Shows Bob's message and
/// one button per available explicit rewrite; Return never rewrites.
public struct CaptureMergeInRefusalPresentation: Equatable, Sendable {
    public let message: TaskDisplayText
    public let code: String?
    public let rewrites: [CaptureDiagnosticRewrite]

    public init?(failure: CaptureCommandFailure, rewrites: [CaptureDiagnosticRewrite] = []) {
        guard failure.mergeInPending == nil else { return nil }
        guard !failure.error.isEmpty else { return nil }
        message = TaskDisplayText(parsing: failure.error)
        code = failure.code
        self.rewrites = rewrites
    }

    public var accessibilitySummary: String {
        ([message.text] + rewrites.map(\.label)).joined(separator: ". ")
    }
}
