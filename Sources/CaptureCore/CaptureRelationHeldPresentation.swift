import Foundation

/// Pure presentation helpers for relation held rows and lookup state,
/// shared by passive capture previews and post-capture presentation.
/// Copy matches Bob's `relation_successors/copy.rs` held and uncertainty
/// notices (`docs/task-dependencies.md` §12.18); Swift never derives
/// eligibility or recomputes the gate.
public enum CaptureRelationHeldPresentation {
    /// One muted held line per row, or nil when the row carries no notice.
    /// `already_planned` rows are JSON-only and never render. A `waits_for`
    /// row without targets carries no notice, matching Bob.
    public static func heldNotice(for held: CaptureRelationHeld) -> String? {
        let source = SuccessorRows.truncate(held.text)
        let prefix: String
        if let relation = held.relation,
           !relation.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let target = relation.after.compactMap({ target -> String? in
               let text = target.text.trimmingCharacters(in: .whitespacesAndNewlines)
               return text.isEmpty ? nil : text
           }).first
        {
            prefix = "🪢 “\(source)” \(relation.label) “\(SuccessorRows.truncate(target))”"
        } else if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prefix = "🪢 “\(source)”"
        } else {
            return nil
        }
        guard let reason = heldReasonText(for: held) else {
            return nil
        }
        return "\(prefix) · not offered: \(reason)"
    }

    /// Muted uncertainty line when the relation lookup did not run to
    /// completion. Nil unless `check` is `"unavailable"`. A single distinct
    /// relation label names that label's links; otherwise the generic
    /// `relation links` subject is used.
    public static func uncertaintyNotice(
        check: String?,
        held: [CaptureRelationHeld] = [],
        relationRows: [TaskCompleteUnblocked] = []
    ) -> String? {
        guard check == "unavailable" else {
            return nil
        }
        var labels: [String] = []
        var seen = Set<String>()
        for label in held.compactMap(\.relation?.label) + relationRows.compactMap(\.relation?.label) {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                continue
            }
            labels.append(trimmed)
        }
        let subject = labels.count == 1 ? "\(labels[0]) links" : "relation links"
        return "🪢 Couldn't check \(subject) · nothing offered"
    }

    /// Held lines for every row, in Bob's report order, skipping
    /// JSON-only and empty-target rows.
    public static func heldNotices(for held: [CaptureRelationHeld]) -> [String] {
        held.compactMap(heldNotice)
    }

    private static func heldReasonText(for held: CaptureRelationHeld) -> String? {
        switch held.reason {
        case "already_planned":
            return nil
        case "already_started":
            return "already started"
        case "waits_for":
            let targets = (held.waitsFor ?? []).compactMap { target -> String? in
                let text = target.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
            guard let first = targets.first else {
                return nil
            }
            if targets.count == 1 {
                return "waits for “\(SuccessorRows.truncate(first))”"
            }
            return "waits for “\(SuccessorRows.truncate(first))” and \(targets.count - 1) more"
        case "blocked":
            let count = held.waitsOn?.count ?? 0
            return "blocked (waits on \(count))"
        case "scheduled":
            if let date = held.scheduled, !date.isEmpty {
                return "scheduled \(SuccessorRows.shortMonthDay(date) ?? date)"
            }
            return "scheduled"
        case "project":
            return "blocked by its project"
        case "hidden":
            return "hidden"
        default:
            return held.reason.isEmpty ? nil : held.reason
        }
    }
}
