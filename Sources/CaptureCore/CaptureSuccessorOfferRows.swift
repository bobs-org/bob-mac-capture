import Foundation

extension CaptureCommandSuccess {
    /// Unblocked successor rows from every close this capture carries, in
    /// preview order: `task_complete`, then `pomodoro_close`, then the nested
    /// past `pomodoro_past.close`, then each `relation_completes` close.
    /// Bob's order is preserved; the panel dedupes by offer key.
    public var allUnblockedRows: [TaskCompleteUnblocked] {
        var rows: [TaskCompleteUnblocked] = taskComplete?.unblocked ?? []
        rows.append(contentsOf: pomodoroClose?.unblocked ?? [])
        rows.append(contentsOf: pomodoroPast?.close.unblocked ?? [])
        for relationComplete in relationCompletes {
            rows.append(contentsOf: relationComplete.taskComplete?.unblocked ?? [])
        }
        return rows
    }

    /// Keep-moving offer rows from the same closes, in the same order.
    public var allKeepMovingRows: [TaskCompleteUnblocked] {
        var rows: [TaskCompleteUnblocked] = taskComplete?.keepMoving ?? []
        rows.append(contentsOf: pomodoroClose?.keepMoving ?? [])
        rows.append(contentsOf: pomodoroPast?.close.keepMoving ?? [])
        for relationComplete in relationCompletes {
            rows.append(contentsOf: relationComplete.taskComplete?.keepMoving ?? [])
        }
        return rows
    }

    /// Note-pull offers from this item, in Bob's resident order.
    public var allNotePullRows: [TaskCompleteUnblocked] {
        notePull?.successors ?? []
    }

    /// Relation and merge hand-off offers in Bob's deterministic item order:
    /// item, task completion, nested relation completion, Pomodoro close, past
    /// close, then merge hand-offs. Batch roots mirror the first item for
    /// legacy compatibility, so normalized children are authoritative.
    public var allRelationSuccessors: [TaskCompleteUnblocked] {
        relationItems.flatMap { item in
            var rows = item.relationSuccessors
            rows.append(contentsOf: item.taskComplete?.relationSuccessors ?? [])
            for relationComplete in item.relationCompletes {
                rows.append(contentsOf: relationComplete.taskComplete?.relationSuccessors ?? [])
            }
            rows.append(contentsOf: item.pomodoroClose?.relationSuccessors ?? [])
            rows.append(contentsOf: item.pomodoroPast?.close.relationSuccessors ?? [])
            rows.append(contentsOf: item.mergeOffers)
            return rows
        }
    }

    /// Held relation rows from every payload location, in offer traversal order.
    public var allRelationHeld: [CaptureRelationHeld] {
        relationItems.flatMap { item in
            var rows = item.relationHeld
            rows.append(contentsOf: item.taskComplete?.relationHeld ?? [])
            for relationComplete in item.relationCompletes {
                rows.append(contentsOf: relationComplete.taskComplete?.relationHeld ?? [])
            }
            rows.append(contentsOf: item.pomodoroClose?.relationHeld ?? [])
            rows.append(contentsOf: item.pomodoroPast?.close.relationHeld ?? [])
            return rows
        }
    }

    /// Relation lookup state from every summary. An unavailable lookup takes
    /// precedence; otherwise the last reported state follows Bob's traversal.
    public var allRelationCheck: String? {
        var checked: String?
        for item in relationItems {
            let values = [item.relationCheck, item.taskComplete?.relationCheck]
                .compactMap { $0 }
                + item.relationCompletes.compactMap { $0.taskComplete?.relationCheck }
                + [item.pomodoroClose?.relationCheck, item.pomodoroPast?.close.relationCheck]
                .compactMap { $0 }
            for value in values {
                if value == "unavailable" {
                    return value
                }
                checked = value
            }
        }
        return checked
    }

    private var relationItems: [CaptureCommandSuccess] {
        captures.isEmpty ? [self] : captures
    }
}
