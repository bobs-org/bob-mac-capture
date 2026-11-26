import Foundation

/// Persistent bounded day-scoped collection of terminally handled wake
/// IDs. A held batch is never marked delivered merely because the
/// observer read it: only acknowledgement, expiry, or day purge adds an
/// ID. Later batches with the same ID never replay, and restarting never
/// resurrects an intentionally consumed ID.
final class SnoozeWakeHandledStore: Sendable {
    static let maxEntries = 256
    private static let dayKey = "snoozeWakeHandledDay"
    private static let idsKey = "snoozeWakeHandledIDs"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The day the stored IDs belong to, if any.
    var day: String? {
        lock.lock()
        defer { lock.unlock() }
        return defaults.string(forKey: Self.dayKey)
    }

    /// The stored IDs for `day`, or empty when the day differs.
    func handledIDs(for day: String) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        guard defaults.string(forKey: Self.dayKey) == day else {
            return []
        }
        let stored = defaults.stringArray(forKey: Self.idsKey) ?? []
        return Set(stored)
    }

    func contains(_ wakeID: String, day: String) -> Bool {
        handledIDs(for: day).contains(wakeID)
    }

    /// Records one terminally handled wake ID for `day`. A day change
    /// clears the previous day's IDs first. The collection stays bounded.
    func acknowledge(_ wakeID: String, day: String) {
        lock.lock()
        defer { lock.unlock() }
        var ids: Set<String>
        if defaults.string(forKey: Self.dayKey) != day {
            defaults.set(day, forKey: Self.dayKey)
            ids = []
        } else {
            ids = Set(defaults.stringArray(forKey: Self.idsKey) ?? [])
        }
        ids.insert(wakeID)
        while ids.count > Self.maxEntries {
            ids.removeFirst()
        }
        defaults.set(Array(ids), forKey: Self.idsKey)
    }

    /// Drops the previous day's IDs when the day rolls over.
    func purge(day: String) {
        lock.lock()
        defer { lock.unlock() }
        if defaults.string(forKey: Self.dayKey) != day {
            defaults.set(day, forKey: Self.dayKey)
            defaults.set([], forKey: Self.idsKey)
        }
    }
}
