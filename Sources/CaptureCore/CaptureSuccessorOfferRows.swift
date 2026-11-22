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

    /// Requirement groups in Bob's item order. Requirements stay in their own
    /// typed collection and never enter `allUnblockedRows` as recovered tasks.
    /// In batch responses, item groups are authoritative and the root-level
    /// mirror is appended only to recover groups an older or partial item lacks.
    public var allRequirementGroups: [CapturePullInGroup] {
        var groups = normalizedCaptures.flatMap { $0.pullIn?.groups ?? [] }
        if !captures.isEmpty {
            groups.append(contentsOf: pullIn?.groups ?? [])
        }
        return Self.canonicalRequirementGroups(groups)
    }

    /// Bob-authored requirement receipts in normalized item order. Batch root
    /// mirrors are deduplicated by the full opaque receipt key.
    public var allRequirementOutcomes: [CaptureRequirementOutcome] {
        var outcomes = normalizedCaptures.flatMap(\.reqOutcomes)
        if !captures.isEmpty {
            outcomes.append(contentsOf: reqOutcomes)
        }
        var seen = Set<String>()
        return outcomes.filter { !$0.key.isEmpty && seen.insert($0.key).inserted }
    }

    public static func canonicalRequirementGroups(
        _ groups: [CapturePullInGroup]
    ) -> [CapturePullInGroup] {
        var result: [CapturePullInGroup] = []
        var ownerIndices: [String: Int] = [:]
        var seenRowKeys = Set<String>()

        for group in groups where group.isRequirementGroup {
            let declaredOwnerKey = group.owner?.key.isEmpty == false ? group.owner?.key : nil
            var ownerKeys: [String] = []
            for row in group.rows where row.isSelectable {
                guard declaredOwnerKey == nil || row.req.ownerKey == declaredOwnerKey else {
                    continue
                }
                if !ownerKeys.contains(row.req.ownerKey) {
                    ownerKeys.append(row.req.ownerKey)
                }
            }

            for ownerKey in ownerKeys {
                let ownerRows = group.rows.filter {
                    $0.isSelectable && $0.req.ownerKey == ownerKey
                }
                let newRows = ownerRows.filter { seenRowKeys.insert($0.offer.key).inserted }
                guard !newRows.isEmpty else { continue }
                if let index = ownerIndices[ownerKey] {
                    let existingRows = result[index].rows
                    result[index] = result[index].replacingRequirementRows(existingRows + newRows)
                } else {
                    ownerIndices[ownerKey] = result.count
                    result.append(group.replacingRequirementRows(newRows))
                }
            }
        }
        return result
    }

    /// Every ordinary Pull-In offer this capture can stage, in preview order:
    /// unblocked, keep-moving, project-note successors, note-pull, then
    /// relation/merge hand-offs. Requirement rows stay in
    /// `allRequirementGroups` and never appear here as recovered tasks.
    public var allPullInOfferRows: [TaskCompleteUnblocked] {
        var rows: [TaskCompleteUnblocked] = []
        for capture in normalizedCaptures {
            rows.append(contentsOf: capture.taskComplete?.unblocked ?? [])
            rows.append(contentsOf: capture.taskComplete?.keepMoving ?? [])
            rows.append(contentsOf: capture.pomodoroClose?.unblocked ?? [])
            rows.append(contentsOf: capture.pomodoroClose?.keepMoving ?? [])
            rows.append(contentsOf: capture.pomodoroPast?.close.unblocked ?? [])
            rows.append(contentsOf: capture.pomodoroPast?.close.keepMoving ?? [])
            for relationComplete in capture.relationCompletes {
                rows.append(contentsOf: relationComplete.taskComplete?.unblocked ?? [])
                rows.append(contentsOf: relationComplete.taskComplete?.keepMoving ?? [])
            }
            if let projectNote = capture.projectNote, projectNote.form == "offer" {
                rows.append(contentsOf: projectNote.successors)
            }
            rows.append(contentsOf: capture.allNotePullRows)
            rows.append(contentsOf: capture.allRelationSuccessors)
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

extension CapturePullIn {
    /// Reconstruct the same capability object with a new group list.
    public func replacingGroups(_ groups: [CapturePullInGroup]) -> CapturePullIn {
        CapturePullIn(
            supported: supported,
            offerCount: offerCount,
            choice: choice,
            pickedCount: pickedCount,
            groups: groups,
            copy: copy,
            close: close,
            jump: jump,
            reqs: reqs
        )
    }

    public var selectableRequirementRows: [CaptureRequirementRow] {
        groups.filter(\.isRequirementGroup).flatMap(\.rows).filter(\.isSelectable)
    }

    public var hasSelectableRequirements: Bool {
        !selectableRequirementRows.isEmpty
    }
}

extension CaptureCommandSuccess {
    /// `pull_in` with canonical requirement groups first, then Bob's ordinary
    /// groups. Batch root mirrors collapse to one owner each.
    public func pullInWithCanonicalRequirementGroups() -> CapturePullIn? {
        guard let pullIn else { return nil }
        let ordinary = pullIn.groups.filter { !$0.isRequirementGroup }
        return pullIn.replacingGroups(allRequirementGroups + ordinary)
    }
}

extension CaptureCommandResponse {
    /// Current response's requirement groups, whether it succeeded or
    /// returned a stale-key refusal with fresh `current.groups`.
    public var requirementGroups: [CapturePullInGroup] {
        switch self {
        case .success(let success):
            return success.allRequirementGroups
        case .failure(let failure):
            return failure.currentRequirementGroups
        }
    }

    public var requirementOutcomes: [CaptureRequirementOutcome] {
        guard case .success(let success) = self else { return [] }
        return success.allRequirementOutcomes
    }
}
