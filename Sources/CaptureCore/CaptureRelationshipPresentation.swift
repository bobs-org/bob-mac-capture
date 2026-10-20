import Foundation

/// One relationship row in Bob's `dependency_updates[]` order. The app
/// presents Bob's resolved text, note, status, and direction without parsing
/// the managed Depends-On/Blocks Markdown rows.
public struct CaptureRelationshipRow: Equatable, Sendable {
    public let text: String
    public let accessibilityLabel: String

    public init(text: String, accessibilityLabel: String? = nil) {
        self.text = text
        self.accessibilityLabel = accessibilityLabel ?? text
    }
}

/// The owner summary for an existing-task relationship capture.
public struct CaptureTaskDependencyOwnerHeader: Equatable, Sendable {
    public let text: String
    public let locationText: String
    public let statusText: String

    public var accessibilitySummary: String {
        ["Owner \(text)", locationText, statusText]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// Mac preview and notification copy for the ordered relationship effects
/// returned by Bob. It handles new tasks, sub-bullets, and existing owners
/// with one set of rows; only a `task_dependency` item gets an owner header
/// and relationship-specific notification.
public struct CaptureRelationshipPresentation: Equatable, Sendable {
    public let rows: [CaptureRelationshipRow]
    public let ownerHeader: CaptureTaskDependencyOwnerHeader?
    public let notification: Notification?

    public struct Notification: Equatable, Sendable {
        public let title: String
        public let subtitle: String
        public let body: String

        public init(title: String, subtitle: String, body: String) {
            self.title = title
            self.subtitle = subtitle
            self.body = body
        }
    }

    public init(capture: CaptureCommandSuccess) {
        let dependencyRows = capture.dependencyUpdates.flatMap { Self.rows(for: $0) }
        let relationRows = capture.relationUpdates.map { Self.row(for: $0, capture: capture) }
        rows = dependencyRows + relationRows
        if Self.isTaskDependency(capture) {
            ownerHeader = Self.ownerHeader(for: capture)
            notification = Self.notification(for: capture)
        } else if !capture.relationUpdates.isEmpty {
            ownerHeader = nil
            notification = Self.relationOnlyNotification(for: capture)
        } else {
            ownerHeader = nil
            notification = nil
        }
    }

    /// True when this capture carries any relation writes.
    public static func hasRelations(_ capture: CaptureCommandSuccess) -> Bool {
        !capture.relationUpdates.isEmpty
    }

    public static func isTaskDependency(_ capture: CaptureCommandSuccess) -> Bool {
        capture.kind.lowercased().replacingOccurrences(of: "-", with: "_") == "task_dependency"
    }

    /// Put the item owner ahead of its relationship targets in the preview
    /// cards. Bob's first-touch order is retained for every other block.
    public static func ownerFirstTaskBlocks(
        for capture: CaptureCommandSuccess,
        blocks: [CaptureTaskBlock]
    ) -> [CaptureTaskBlock] {
        guard Self.isTaskDependency(capture),
            let blockID = capture.blockID,
            let index = blocks.firstIndex(where: {
                $0.relativeTarget == capture.relativeTarget && $0.blockID == blockID
            }),
            index > 0
        else {
            return blocks
        }
        var ordered = blocks
        let owner = ordered.remove(at: index)
        ordered.insert(owner, at: 0)
        return ordered
    }

    private static func rows(for update: DependencyUpdateSummary) -> [CaptureRelationshipRow] {
        if update.role == "blocked_task" {
            guard !update.dependentText.isEmpty else {
                return []
            }
            let verb = update.added == 0 ? "already blocks" : "blocks"
            let previous = statusName(update.previousStatus, name: update.previousStatusName)
            let current = statusName(update.dependentStatus, name: update.dependentStatusName)
            let transition = update.statusChanged && !previous.isEmpty && !current.isEmpty
                ? "\(previous) → \(current)"
                : current
            var parts = ["🧱 \(verb)", update.dependentText]
            let location = locationText(note: update.dependentNote, blockID: update.dependentBlockID)
            if !location.isEmpty {
                parts.append(location)
            }
            if !transition.isEmpty {
                parts.append(transition)
            }
            if update.blockedResidents > 0 {
                let noun = update.blockedResidents == 1 ? "task" : "tasks"
                parts.append("blocks \(update.blockedResidents) project \(noun)")
            }
            return [CaptureRelationshipRow(text: parts.joined(separator: " · "))]
        }

        return update.prerequisites.map { prerequisite in
            let already = prerequisite.alreadyPresent ?? (update.added == 0)
            let verb = already ? "already depends on" : "depends on"
            var parts = ["⛓ \(verb)", prerequisite.text]
            let location = locationText(note: prerequisite.note, blockID: prerequisite.blockID)
            if !location.isEmpty {
                parts.append(location)
            }
            let current = statusName(prerequisite.statusSymbol, name: prerequisite.statusName)
            let previous = statusName(
                prerequisite.previousStatus,
                name: prerequisite.previousStatusName
            )
            let transition =
                prerequisite.previousStatus != nil && !previous.isEmpty && !current.isEmpty
                ? "\(previous) → \(current)"
                : current
            if !transition.isEmpty {
                parts.append(transition)
            }
            return CaptureRelationshipRow(text: parts.joined(separator: " · "))
        }
    }

    /// One 🪢 preview row for a relation edge. Relations never render red,
    /// consumption, or status arrows: only the quoted text, the label, the
    /// locator, and the archived live-only suffix.
    private static func row(
        for update: CaptureRelationUpdate,
        capture: CaptureCommandSuccess
    ) -> CaptureRelationshipRow {
        let isFrom = update.direction == "from"
        let endpoint = isFrom ? update.source : update.target
        let quoted = "“\(endpoint.text)”"
        let label = (update.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let labelSuffix = label.isEmpty ? "" : " · \(label)"
        let locator = locationText(note: endpoint.path, blockID: endpoint.blockID.isEmpty ? nil : endpoint.blockID)
        let locatorSuffix = locator.isEmpty ? "" : "   \(locator)"
        let archived = isArchived(update: update, capture: capture)
        let archivedSuffix = archived ? " · archived: LINKED FROM shows live only" : ""
        let text: String
        switch update.action {
        case "relabeled":
            text = "🪢 relabeled \(quoted)\(labelSuffix)\(locatorSuffix)\(archivedSuffix)"
        case "unchanged":
            text = "🪢 already linked \(quoted)\(labelSuffix)\(locatorSuffix)\(archivedSuffix)"
        default:
            if isFrom {
                text = "🪢 \(quoted) now links here\(labelSuffix)\(locatorSuffix)\(archivedSuffix)"
            } else {
                text = "🪢 links to \(quoted)\(labelSuffix)\(locatorSuffix)\(archivedSuffix)"
            }
        }
        return CaptureRelationshipRow(text: text)
    }

    private static func isArchived(
        update: CaptureRelationUpdate,
        capture: CaptureCommandSuccess
    ) -> Bool {
        if update.target.archived == true || update.source.archived == true {
            return true
        }
        let ids = [update.target.blockID, update.source.blockID].filter { !$0.isEmpty }
        return capture.mirrorSkipped.contains { skipped in
            skipped.reason == "archived_target" && ids.contains(skipped.blockID)
        }
    }

    private static func ownerHeader(
        for capture: CaptureCommandSuccess
    ) -> CaptureTaskDependencyOwnerHeader {
        let ownerBlock = capture.taskBlocks.first(where: {
            $0.relativeTarget == capture.relativeTarget && $0.blockID == capture.blockID
        })
        let text = nonempty(capture.text) ?? nonempty(ownerBlock?.text) ?? "Task"
        let blockID = capture.blockID ?? ownerBlock?.blockID
        let location = locationText(note: capture.relativeTarget, blockID: blockID)
        let current = statusName(capture.statusSymbol, name: capture.statusName)
        let previous = statusName(capture.previousStatusSymbol, name: capture.previousStatusName)
        let status = (capture.statusChanged ?? false) && !previous.isEmpty && !current.isEmpty
            ? "\(previous) → \(current)"
            : current
        return CaptureTaskDependencyOwnerHeader(
            text: text,
            locationText: location,
            statusText: status
        )
    }

    private static func notification(for capture: CaptureCommandSuccess) -> Notification? {
        let dependentUpdates = capture.dependencyUpdates.filter { $0.role != "blocked_task" }
        let blockedUpdates = capture.dependencyUpdates.filter { $0.role == "blocked_task" }
        let dependencyCount = dependentUpdates.reduce(0) { $0 + $1.prerequisites.count }
        let blockedCount = blockedUpdates.count
        let relationCount = capture.relationUpdates.count
        guard dependencyCount + blockedCount + relationCount > 0 else {
            return nil
        }

        let owner = nonempty(capture.text)
            ?? capture.taskBlocks.first(where: {
                $0.relativeTarget == capture.relativeTarget && $0.blockID == capture.blockID
            }).flatMap { nonempty($0.text) }
            ?? "Task"
        let title: String
        if dependencyCount == 0 && blockedCount == 0 {
            title = relationTitle(owner: owner, capture: capture)
        } else if relationCount == 0 {
            if dependencyCount > 0 && blockedCount > 0 {
                title = "\(owner) · depends on \(dependencyCount) · blocks \(blockedCount)"
            } else if dependencyCount > 0 {
                if dependencyCount == 1,
                    let target = dependentUpdates.flatMap(\.prerequisites).first?.text,
                    !target.isEmpty
                {
                    title = "⛓ \(owner) now depends on \(target)"
                } else {
                    title = "\(owner) now depends on \(dependencyCount) tasks"
                }
            } else if blockedCount == 1,
                let target = blockedUpdates.first?.dependentText,
                !target.isEmpty
            {
                title = "🧱 \(owner) now blocks \(target)"
            } else {
                title = "\(owner) now blocks \(blockedCount) tasks"
            }
        } else {
            var parts: [String] = []
            if dependencyCount > 0 {
                parts.append("depends on \(dependencyCount)")
            }
            if blockedCount > 0 {
                parts.append("blocks \(blockedCount)")
            }
            parts.append("links \(relationCount)")
            title = "\(owner) · \(parts.joined(separator: " · "))"
        }

        let body = capture.consumedLinks
            .map { $0.previewText(dryRun: capture.dryRun) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return Notification(
            title: title,
            subtitle: capture.routeLabel.isEmpty ? capture.relativeTarget : capture.routeLabel,
            body: body
        )
    }

    /// Notification for a new-task relation capture (`kind == "task"` with
    /// `relation_updates[]` and no `task_dependency` owner). Relations count
    /// separately from dependencies and blocks; a mixed `&` + `~` new task
    /// names both counts.
    private static func relationOnlyNotification(for capture: CaptureCommandSuccess) -> Notification? {
        guard !capture.relationUpdates.isEmpty else {
            return nil
        }
        let owner = nonempty(capture.text) ?? "Task"
        let dependencyCount = capture.dependencyUpdates.reduce(0) { $0 + $1.prerequisites.count }
        let title: String
        if dependencyCount > 0 {
            title = "\(owner) · depends on \(dependencyCount) · links \(capture.relationUpdates.count)"
        } else {
            title = relationTitle(owner: owner, capture: capture)
        }
        return Notification(
            title: title,
            subtitle: capture.routeLabel.isEmpty ? capture.relativeTarget : capture.routeLabel,
            body: ""
        )
    }

    private static func relationTitle(owner: String, capture: CaptureCommandSuccess) -> String {
        let updates = capture.relationUpdates
        if updates.count == 1, let update = updates.first {
            let isFrom = update.direction == "from"
            let other = isFrom ? update.source.text : update.target.text
            if other.isEmpty {
                return "🪢 \(owner) · links 1"
            }
            if isFrom {
                return "🪢 “\(other)” now links here"
            }
            return "🪢 \(owner) now links to “\(other)”"
        }
        return "🪢 \(owner) · links \(updates.count)"
    }

    private static func statusName(_ symbol: String?, name: String?) -> String {
        let resolvedName = name ?? ""
        if !resolvedName.isEmpty, resolvedName != "Unknown" {
            return resolvedName
        }
        if let symbol, !symbol.isEmpty {
            return symbol == " " ? "Todo" : symbol
        }
        return resolvedName == "Unknown" ? "" : resolvedName
    }

    private static func locationText(note: String, blockID: String?) -> String {
        guard !note.isEmpty else {
            return ""
        }
        guard let blockID, !blockID.isEmpty else {
            return note
        }
        return "\(note) ^\(blockID)"
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}
