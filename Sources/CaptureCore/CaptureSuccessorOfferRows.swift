import Foundation

extension CaptureCommandSuccess {
    /// Unblocked successor rows from every close this capture carries, in
    /// preview order: `task_complete`, then `pomodoro_close`, then each
    /// `relation_completes` close.
    public var allUnblockedRows: [TaskCompleteUnblocked] {
        var rows: [TaskCompleteUnblocked] = taskComplete?.unblocked ?? []
        rows.append(contentsOf: pomodoroClose?.unblocked ?? [])
        for relationComplete in relationCompletes {
            rows.append(contentsOf: relationComplete.taskComplete?.unblocked ?? [])
        }
        return rows
    }

    /// Keep-moving offer rows from the same closes, in the same order.
    public var allKeepMovingRows: [TaskCompleteUnblocked] {
        var rows: [TaskCompleteUnblocked] = taskComplete?.keepMoving ?? []
        rows.append(contentsOf: pomodoroClose?.keepMoving ?? [])
        for relationComplete in relationCompletes {
            rows.append(contentsOf: relationComplete.taskComplete?.keepMoving ?? [])
        }
        return rows
    }
}
