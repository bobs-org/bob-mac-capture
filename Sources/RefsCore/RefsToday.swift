import Foundation

/// One Today entry for a task: its ledger order and Pomodoro name.
public struct RefsTodayEntry: Codable, Equatable, Sendable {
    public let order: Int
    public let pomodoroName: String

    public init(order: Int, pomodoroName: String) {
        self.order = order
        self.pomodoroName = pomodoroName
    }
}

/// Today is the set of `today_tasks[]` keyed by `(path, block_id)`.
/// Order is first occurrence in the array, so the first link wins a
/// duplicate. Entries for non-reference paths are kept; the ranker
/// matches them against rows.
///
/// `entries` stays path-keyed for rows without a located task: an
/// older `bob` sends no `task` object on `ref list` rows (and no
/// `block_id` on plan rows), and those rows join on the note path
/// exactly as before. Rows with a task join on the composite
/// `taskEntries` key instead, so two references whose tasks share one
/// parent note no longer both light up when only one is linked.
public struct RefsToday: Equatable, Sendable {
    public var entries: [String: RefsTodayEntry]
    public var taskEntries: [String: RefsTodayEntry]

    public init(
        entries: [String: RefsTodayEntry] = [:],
        taskEntries: [String: RefsTodayEntry] = [:]
    ) {
        self.entries = entries
        self.taskEntries = taskEntries
    }

    public init(plan: RefsPlanResponse) {
        var entries: [String: RefsTodayEntry] = [:]
        var taskEntries: [String: RefsTodayEntry] = [:]
        for task in plan.todayTasks {
            let entry = RefsTodayEntry(
                order: entries.count + taskEntries.count,
                pomodoroName: task.entryName
            )
            if let blockID = task.blockID {
                let key = Self.taskKey(path: task.path, blockID: blockID)
                guard taskEntries[key] == nil else {
                    continue
                }
                taskEntries[key] = entry
            } else {
                guard entries[task.path] == nil else {
                    continue
                }
                entries[task.path] = entry
            }
        }
        self.entries = entries
        self.taskEntries = taskEntries
    }

    /// The composite key for one located task.
    public static func taskKey(path: String, blockID: String) -> String {
        "\(path)#\(blockID)"
    }

    /// The Today entry for one reference row: the composite
    /// `(task.path, task.block_id)` join when the row carries a task
    /// with a block ID, else the note-path join for older-`bob` rows.
    public func entry(for record: RefRecord) -> RefsTodayEntry? {
        if let blockID = record.task?.blockID {
            let key = Self.taskKey(path: record.task?.path ?? record.path, blockID: blockID)
            return taskEntries[key]
        }
        return entries[record.path]
    }

    /// The Today entry for one library item: the composite join on its
    /// located task, else the note-path fallback.
    public func entry(for item: RefItem) -> RefsTodayEntry? {
        if let task = item.task, let blockID = task.blockID {
            return taskEntries[Self.taskKey(path: task.path, blockID: blockID)]
        }
        return entries[item.id]
    }
}

extension RefsToday: Codable {
    private enum CodingKeys: String, CodingKey {
        case entries
        case taskEntries = "task_entries"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent(
            [String: RefsTodayEntry].self,
            forKey: .entries
        ) ?? [:]
        taskEntries = try container.decodeIfPresent(
            [String: RefsTodayEntry].self,
            forKey: .taskEntries
        ) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(taskEntries, forKey: .taskEntries)
    }
}
