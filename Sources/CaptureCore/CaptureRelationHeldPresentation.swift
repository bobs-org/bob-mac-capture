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

    /// True when held/check lines may render for this pull-in state.
    /// Held rows are muted and appear only when no picker is involved;
    /// an explicit `none` choice stays silent, and a picker with offers
    /// already carries folded diagnostics. Older payloads without
    /// pull-in still render.
    public static func shouldPresentHeld(pullIn: CapturePullIn?) -> Bool {
        if pullIn?.choice == "none" {
            return false
        }
        guard let pullIn else {
            return true
        }
        if !pullIn.supported {
            return true
        }
        return pullIn.offerCount == 0
    }

    /// Held plus uncertainty lines for one presentation, gated on the
    /// enclosing picker state. Uses the already-aggregated held/check
    /// locations so item-level, task, Pomodoro, nested, and batch routes
    /// share one gate. `already_planned` stays JSON-only via `heldNotice`.
    public static func lines(
        held: [CaptureRelationHeld],
        check: String?,
        relationRows: [TaskCompleteUnblocked],
        pullIn: CapturePullIn?
    ) -> [String] {
        guard shouldPresentHeld(pullIn: pullIn) else {
            return []
        }
        var out = heldNotices(for: held)
        if let line = uncertaintyNotice(check: check, held: held, relationRows: relationRows) {
            out.append(line)
        }
        return out
    }

    /// Aggregate held/check lines for a whole capture, reusing the
    /// `allRelation*` traversal so batch roots mirroring the first item
    /// do not double-count. Gated on this capture's picker state.
    public static func lines(for capture: CaptureCommandSuccess) -> [String] {
        lines(
            held: capture.allRelationHeld,
            check: capture.allRelationCheck,
            relationRows: capture.allRelationSuccessors,
            pullIn: capture.pullIn
        )
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
            // Rust `relation_held_row_json` emits every held-blocked row as
            // `reason: blocked` with scheduled/project metadata. Mirror its
            // `held_copy_reason` precedence: scheduled, then project, then
            // dependency count. The `scheduled`/`project` reason strings
            // below are legacy synthetic shapes only.
            if let date = held.scheduled, !date.isEmpty {
                return "scheduled \(SuccessorRows.shortMonthDay(date) ?? date)"
            }
            if let project = held.project,
                !project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return "blocked by its project"
            }
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
