import Foundation

/// Shared copy for owner-aware `&`/`*` headers, the `+` owner-mode picker,
/// and the calm `dependency_target` hint. Every string is built from Bob's
/// JSON plus the display names remembered from accepted picker rows.
public enum CaptureRelationshipCopy: Sendable {
    public static let curlyOpen = "\u{201C}"
    public static let curlyClose = "\u{201D}"
    public static let ellipsis = "\u{2026}"
    public static let relateStatusText = "Choose the task to relate"

    public static func quoted(_ name: String) -> String {
        "\(curlyOpen)\(name)\(curlyClose)"
    }

    /// First name, plus a count of the rest: `"Buy shoes"` or `"Buy shoes" + 1 more`.
    public static func namedList(_ names: [String]) -> String {
        guard let first = names.first else {
            return quoted("")
        }
        let head = quoted(first)
        if names.count == 1 {
            return head
        }
        return "\(head) + \(names.count - 1) more"
    }

    public static func displayName(
        raw: String,
        note: String?,
        blockID: String?,
        names: [String: String]
    ) -> String {
        if let name = names[raw], !name.isEmpty {
            return name
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let name = names[trimmed], !name.isEmpty {
            return name
        }
        if let note, let blockID, !note.isEmpty, !blockID.isEmpty {
            return "\(note):\(blockID)"
        }
        return trimmed
    }

    public static func parseHasRelationshipModifiers(_ parse: CaptureParseResponse) -> Bool {
        if !parse.dependencies.isEmpty || !parse.blockedTasks.isEmpty || !parse.relations.isEmpty {
            return true
        }
        return parse.items.contains {
            !$0.dependencies.isEmpty || !$0.blockedTasks.isEmpty || !$0.relations.isEmpty
        }
    }

    public static func relationshipMarkers(
        in parse: CaptureParseResponse
    ) -> (
        dependencies: [CaptureParseRelationshipMarker],
        blocked: [CaptureParseRelationshipMarker]
    ) {
        if let item = parse.items.first(where: { $0.needs.contains("dependency_target") })
            ?? parse.items.first(where: {
                !$0.dependencies.isEmpty || !$0.blockedTasks.isEmpty || !$0.relations.isEmpty
            })
        {
            return (item.dependencies, item.blockedTasks)
        }
        return (parse.dependencies, parse.blockedTasks)
    }

    /// Calm footer hint for an outstanding `dependency_target` need.
    public static func dependencyTargetHint(
        parse: CaptureParseResponse,
        names: [String: String]
    ) -> String {
        let markers = relationshipMarkers(in: parse)
        let dependencyNames = markers.dependencies.map {
            displayName(raw: $0.raw, note: $0.note, blockID: $0.blockID, names: names)
        }
        let blockedNames = markers.blocked.map {
            displayName(raw: $0.raw, note: $0.note, blockID: $0.blockID, names: names)
        }
        return dependencyTargetHint(
            dependencyNames: dependencyNames,
            blockedNames: blockedNames
        )
    }

    public static func dependencyTargetHint(
        dependencyNames: [String],
        blockedNames: [String]
    ) -> String {
        let hasDeps = !dependencyNames.isEmpty
        let hasBlocked = !blockedNames.isEmpty
        if hasDeps && hasBlocked {
            return
                "Type the task between \(namedList(dependencyNames)) and \(namedList(blockedNames)), or + for an existing one"
        }
        if hasBlocked {
            return
                "🧱 What blocks \(namedList(blockedNames))? Type a new task, or + for an existing one"
        }
        if hasDeps {
            return
                "⛓ What depends on \(namedList(dependencyNames))? Type a new task, or + for an existing one."
        }
        return "Type a new task, or + for an existing one"
    }

    /// `+` / `@route+` owner-mode header from Bob's `picker.relationship`.
    public static func parentPickerTitle(relationship: CapturePickerRelationship) -> String {
        let dependencyNames = relationship.dependencies.map(\.displayName)
        let blockedNames = relationship.blockedTasks.map(\.displayName)
        let hasDeps = !dependencyNames.isEmpty
        let hasBlocked = !blockedNames.isEmpty
        let relationClause = relationClause(relationship.relations)
        if hasDeps && hasBlocked {
            if let relationClause {
                return
                    "Which task depends on \(namedList(dependencyNames)) and blocks \(namedList(blockedNames)) and \(relationClause)?"
            }
            return
                "Which task depends on \(namedList(dependencyNames)) and blocks \(namedList(blockedNames))?"
        }
        if hasBlocked {
            if let relationClause {
                return "🧱 Which task blocks \(namedList(blockedNames)) and \(relationClause)?"
            }
            return "🧱 Which task blocks \(namedList(blockedNames))?"
        }
        if hasDeps {
            if let relationClause {
                return "⛓ Which task depends on \(namedList(dependencyNames)) and \(relationClause)?"
            }
            return "⛓ Which task depends on \(namedList(dependencyNames))?"
        }
        if let relationClause {
            return "🪢 Which task \(relationClause)?"
        }
        return relateStatusText
    }

    private static func relationClause(_ relations: [CapturePickerRelationEntry]) -> String? {
        guard !relations.isEmpty else {
            return nil
        }
        let toNames = relations.filter { $0.direction != "from" }.map(\.text).filter { !$0.isEmpty }
        let fromNames = relations.filter { $0.direction == "from" }.map(\.text).filter { !$0.isEmpty }
        var parts: [String] = []
        if !toNames.isEmpty {
            parts.append("links to \(namedList(toNames))")
        }
        if !fromNames.isEmpty {
            parts.append("is linked from \(namedList(fromNames))")
        }
        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: " and ")
    }

    /// `&` / `*` / `~` / `~~` picker title. Existing owners are unquoted for
    /// `&`/`*`; relation headers always quote the owner. Ownerless copy is
    /// unchanged for dependencies and uses the knot prompt for relations.
    public static func dependencyPickerTitle(
        owner: DependencyOwner?,
        direction: DependencyPickerDirection
    ) -> String {
        if direction.isRelation {
            return relationPickerTitle(owner: owner, direction: direction)
        }
        let verb = direction == .blocks ? "blocks" : "depends on"
        let glyph = direction == .blocks ? "🧱" : "⛓"
        if let owner {
            if owner.isExistingTask {
                if let text = owner.text, !text.isEmpty {
                    return "\(glyph) \(text) \(verb)\(ellipsis)"
                }
                if let token = owner.tokenHeader {
                    return "\(glyph) \(token) \(verb)\(ellipsis)"
                }
            } else if owner.isNewTask {
                if let text = owner.text, !text.isEmpty {
                    return "\(glyph) \(quoted(text)) \(verb)\(ellipsis)"
                }
                return direction == .blocks ? "New task blocks\(ellipsis)" : "New task depends on\(ellipsis)"
            }
        }
        return direction == .blocks ? "Choose a task to block" : "Choose a prerequisite"
    }

    private static func relationPickerTitle(
        owner: DependencyOwner?,
        direction: DependencyPickerDirection
    ) -> String {
        let ownerName: String?
        if let owner {
            if let text = owner.text, !text.isEmpty {
                ownerName = quoted(text)
            } else if let token = owner.tokenHeader {
                ownerName = quoted(token)
            } else if owner.isNewTask {
                ownerName = quoted("new task")
            } else {
                ownerName = nil
            }
        } else {
            ownerName = nil
        }
        switch direction {
        case .linksTo:
            if let ownerName {
                return "🪢 \(ownerName) links to\(ellipsis)"
            }
            return "🪢 Choose a task to link to\(ellipsis)"
        case .linkedFrom:
            if let ownerName {
                return "🪢 Choose a task that will link to \(ownerName)"
            }
            return "🪢 Choose a task that will link to this task"
        default:
            return "🪢 Choose a task to link"
        }
    }

    /// Existing-owner subtitle is `body.md ^id · Status`. Ownerless copy
    /// teaches the next step. New-task owners have no subtitle so the name
    /// is not repeated.
    public static func dependencyPickerSubtitle(
        owner: DependencyOwner?,
        direction: DependencyPickerDirection
    ) -> String? {
        if direction.isRelation {
            return "any task · ~ flips direction"
        }
        if let owner, owner.isExistingTask {
            return owner.locationSubtitle
        }
        if owner?.isNewTask == true {
            return nil
        }
        if owner != nil {
            return nil
        }
        return "Then type the task, or + for an existing one"
    }
}
