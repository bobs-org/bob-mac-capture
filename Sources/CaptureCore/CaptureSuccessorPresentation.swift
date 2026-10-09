import Foundation

/// Shared successor-link row builder for the `!` completion card and the
/// Pomodoro close card. Both cards render the same additive successor JSON
/// (`unblocked[]` / `still_blocked[]`, `docs/task-dependencies.md` §12.5)
/// with the same copy (`docs/task-dependencies.md` §12.6), so the wording
/// lives here once: destination capsules, minted-ID and reason captions,
/// still-blocked captions, and the one notification line.
///
/// Wording mirrors `print_human_successor_rows` in
/// `src/native/capture/output.rs` (`linked`/`would link`, `unblocked`, and
/// `still blocked` rows) and the §12.6 notice-text table, so the panel's
/// preview and the CLI's human output describe the same change the same
/// way. Pure data: the SwiftUI layer only reads these strings.
public enum SuccessorRowKind: Equatable, Sendable {
    /// The gesture linked this dependent into its predecessor's slot.
    case linked
    /// The gesture unblocked this dependent but did not link it.
    case recovered
    /// This dependent stays blocked.
    case stillBlocked
}

/// One `unblocked[]` row: linked (with a destination capsule and an
/// optional minted-ID caption) or recovered (with a reason caption).
public struct SuccessorUnblockedRow: Equatable, Sendable {
    public let kind: SuccessorRowKind
    /// `"[?] → [*]  Re-launch agents"`.
    public let transitionText: String
    /// `"sase.md ^relaunch-failed-agents"`.
    public let locatorText: String
    /// The dependent's plain text, for notification bodies.
    public let text: String
    /// `"→ FIX"` / `"→ new BOB · next up"`, linked rows only.
    public let destinationText: String?
    /// `"added ^id"` when an ID was minted, or `"Ready · not planned
    /// today"` on recovered rows. Nil when there is nothing to say.
    public let captionText: String?
    /// True when the dependent lives in an inbox file.
    public let isInbox: Bool

    public init(
        kind: SuccessorRowKind,
        transitionText: String,
        locatorText: String,
        text: String,
        destinationText: String? = nil,
        captionText: String? = nil,
        isInbox: Bool = false
    ) {
        self.kind = kind
        self.transitionText = transitionText
        self.locatorText = locatorText
        self.text = text
        self.destinationText = destinationText
        self.captionText = captionText
        self.isInbox = isInbox
    }
}

/// One `still_blocked[]` row: muted, with a `stays …` caption.
public struct SuccessorStillBlockedRow: Equatable, Sendable {
    /// The dependent's plain text.
    public let text: String
    /// `"sase.md ^badges"`.
    public let locatorText: String
    /// `"stays Blocked · waits on 1 more"` / `"stays Blocked · until Oct 13"`.
    public let captionText: String

    public init(text: String, locatorText: String, captionText: String) {
        self.text = text
        self.locatorText = locatorText
        self.captionText = captionText
    }
}

/// One linked `unblocked[]` row paired with its successor placement.
private typealias LinkedRow = (item: TaskCompleteUnblocked, link: TaskCompleteSuccessorLink)

public enum SuccessorRows {
    /// Builds the `unblocked[]` rows: a row with `link` is linked, any
    /// other row is recovered. `transition` formats the status change the
    /// way the caller's card does (`"[?] → [*]  text"`).
    public static func unblockedRows(
        from items: [TaskCompleteUnblocked],
        transition: (TaskCompleteUnblocked) -> String,
        locator: (TaskCompleteUnblocked) -> String
    ) -> [SuccessorUnblockedRow] {
        items.map { item in
            if let link = item.link {
                return SuccessorUnblockedRow(
                    kind: .linked,
                    transitionText: transition(item),
                    locatorText: locator(item),
                    text: item.text,
                    destinationText: destinationCapsule(link: link),
                    captionText: mintedCaption(item: item, link: link),
                    isInbox: item.inbox
                )
            }
            return SuccessorUnblockedRow(
                kind: .recovered,
                transitionText: transition(item),
                locatorText: locator(item),
                text: item.text,
                destinationText: nil,
                captionText: recoveredCaption(item: item),
                isInbox: item.inbox
            )
        }
    }

    public static func stillBlockedRows(
        from items: [TaskCompleteStillBlocked],
        locator: (TaskCompleteStillBlocked) -> String
    ) -> [SuccessorStillBlockedRow] {
        items.map { item in
            SuccessorStillBlockedRow(
                text: item.text,
                locatorText: locator(item),
                captionText: stillBlockedCaption(item: item)
            )
        }
    }

    /// `"→ FIX"`, `"→ new BOB · next up"`, `"→ new session"`, or
    /// `"→ line 37"`: the trailing destination capsule on a linked row.
    public static func destinationCapsule(link: TaskCompleteSuccessorLink) -> String {
        var destination: String
        if link.entryCreated {
            if link.entryName.isEmpty {
                destination = "new session"
            } else {
                destination = "new \(link.entryName)"
            }
        } else if link.entryName.isEmpty {
            destination = "line \(link.entryLine)"
        } else {
            destination = link.entryName
        }
        if link.nextUp {
            destination += " · next up"
        }
        return "→ \(destination)"
    }

    /// `"FIX"`, `"new BOB session (next up)"`, `"new session"`, or
    /// `"line 37"`: the destination in notification and human-output
    /// wording, matching Bob's `successor_destination`.
    public static func notificationDestination(link: TaskCompleteSuccessorLink) -> String {
        var destination: String
        if link.entryCreated {
            if link.entryName.isEmpty {
                destination = "new session"
            } else {
                destination = "new \(link.entryName) session"
            }
        } else if link.entryName.isEmpty {
            destination = "line \(link.entryLine)"
        } else {
            destination = link.entryName
        }
        if link.nextUp {
            destination += " (next up)"
        }
        return destination
    }

    /// The one notification line from the §12.6 notice-text table, or nil
    /// when nothing was linked and the breaker did not fire (the caller
    /// then keeps its existing `· unblocked A, B` body).
    public static func notificationLine(unblocked: [TaskCompleteUnblocked]) -> String? {
        let linked: [LinkedRow] = unblocked.compactMap { item in
            guard let link = item.link else { return nil }
            return (item, link)
        }
        if linked.isEmpty {
            let breakerCount = unblocked.filter {
                $0.link == nil && $0.notLinked == "breaker"
            }.count
            guard breakerCount > 0 else { return nil }
            return "🔓 \(breakerCount) unblocked · not linked (more than 5)"
        }
        if linked.count == 1 {
            let (item, link) = linked[0]
            return "🔓 Next in \(notificationDestination(link: link)): \(truncate(item.text))"
        }
        let destinations = linked.map { notificationDestination(link: $0.1) }
        let distinct = orderedUnique(destinations)
        if distinct.count == 1, let destination = distinct.first {
            let texts = linked.map { truncate($0.0.text) }
            return "🔓 \(linked.count) linked → \(destination): \(joinedHeads(texts))"
        }
        return "🔓 \(linked.count) linked · \(distinct.joined(separator: ", "))"
    }

    /// The recovered-only fallback from the §12.6 notice-text table
    /// (`🔓 Unblocked: Book flights (Ready)`), or nil when no recovered
    /// row exists. The Mac notification keeps its existing `· unblocked
    /// A, B` body in this case; the line is the shared plain-text form.
    public static func recoveredLine(unblocked: [TaskCompleteUnblocked]) -> String? {
        guard
            unblocked.allSatisfy({ $0.link == nil }),
            let first = unblocked.first(where: { $0.notLinked != "breaker" })
        else {
            return nil
        }
        let lane = first.statusName.isEmpty ? "Ready" : first.statusName
        return "🔓 Unblocked: \(truncate(first.text)) (\(lane))"
    }

    /// Human reason suffix for a recovered row, matching Bob's
    /// `not_linked_reason`.
    public static func notLinkedReasonText(_ reason: String?) -> String? {
        switch reason {
        case nil:
            return nil
        case "already_planned":
            return "already planned"
        case "not_planned_today":
            return "not planned today"
        case "breaker":
            return "not linked · more than 5"
        case "project_task":
            return "project task"
        case "hidden":
            return "hidden"
        case "disabled":
            return "linking off"
        case "failed":
            return "couldn't link"
        case "cancelled":
            return "cancelled"
        case let other:
            return other
        }
    }

    /// Task text truncated to 48 characters with `…`. Never leads with a
    /// block ID: callers pass the plain text Bob reports.
    public static func truncate(_ text: String) -> String {
        guard text.count > 48 else { return text }
        return String(text.prefix(48)) + "…"
    }

    private static func mintedCaption(
        item: TaskCompleteUnblocked,
        link: TaskCompleteSuccessorLink
    ) -> String? {
        guard link.blockIDCreated else { return nil }
        if let afterCaret = link.blockLink.split(separator: "^").last,
           let minted = afterCaret.split(separator: "]").first,
           !minted.isEmpty
        {
            return "added ^\(minted)"
        }
        if !item.blockID.isEmpty {
            return "added ^\(item.blockID)"
        }
        return nil
    }

    private static func recoveredCaption(item: TaskCompleteUnblocked) -> String? {
        guard let reason = notLinkedReasonText(item.notLinked) else {
            return item.statusName.isEmpty ? nil : item.statusName
        }
        if item.statusName.isEmpty {
            return reason
        }
        return "\(item.statusName) · \(reason)"
    }

    private static func stillBlockedCaption(item: TaskCompleteStillBlocked) -> String {
        let lane = item.statusName.isEmpty ? "Blocked" : item.statusName
        if item.reason == "scheduled" {
            if let date = item.scheduled {
                return "stays \(lane) · until \(shortMonthDay(date) ?? date)"
            }
            return "stays \(lane) · scheduled"
        }
        return "stays \(lane) · waits on \(item.waitsOn) more"
    }

    /// `"Oct 13"` from `"2026-10-13"`, or nil when the date does not
    /// parse (the caller then falls back to the raw string).
    public static func shortMonthDay(_ date: String) -> String? {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        let names = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ]
        guard month >= 1, month <= 12 else { return nil }
        return "\(names[month - 1]) \(day)"
    }

    private static func joinedHeads(_ texts: [String]) -> String {
        if texts.count <= 2 {
            return texts.joined(separator: ", ")
        }
        return texts.prefix(2).joined(separator: ", ") + ", +\(texts.count - 2)"
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values where seen.insert(value).inserted {
            ordered.append(value)
        }
        return ordered
    }
}
