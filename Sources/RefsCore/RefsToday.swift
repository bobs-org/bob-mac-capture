import Foundation

/// One Today entry for a note path: its ledger order and Pomodoro name.
public struct RefsTodayEntry: Codable, Equatable, Sendable {
    public let order: Int
    public let pomodoroName: String

    public init(order: Int, pomodoroName: String) {
        self.order = order
        self.pomodoroName = pomodoroName
    }
}

/// Today is the set of `today_tasks[]` keyed by note path. Order is first
/// occurrence in the array, so the first link wins a duplicate. Entries for
/// non-reference paths are kept; the ranker matches them against rows.
public struct RefsToday: Codable, Equatable, Sendable {
    public var entries: [String: RefsTodayEntry]

    public init(entries: [String: RefsTodayEntry] = [:]) {
        self.entries = entries
    }

    public init(plan: RefsPlanResponse) {
        var entries: [String: RefsTodayEntry] = [:]
        for task in plan.todayTasks {
            guard entries[task.path] == nil else {
                continue
            }
            entries[task.path] = RefsTodayEntry(
                order: entries.count,
                pomodoroName: task.entryName
            )
        }
        self.entries = entries
    }
}
