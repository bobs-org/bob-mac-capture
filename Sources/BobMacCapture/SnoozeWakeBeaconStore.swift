import Foundation

/// Bounded acknowledgement metadata for the shared wake beacon/record
/// lifecycle. Persists unexpired delivered batches' IDs, task keys, delivery
/// and expiry dates, and vault so a restart restores the beacon and its
/// clearing rules without re-announcing. Works even when notification
/// permission denied creation of a record. Expired or foreign-vault entries
/// are purged on read. Metadata only: IDs, keys, dates, vault — never task
/// text.
final class SnoozeWakeBeaconStore: Sendable {
    static let maxEntries = 256
    private static let key = "snoozeWakeBeaconMetadata"

    struct Entry: Codable, Equatable {
        let wakeID: String
        let taskKeys: [String]
        let taskCount: Int
        let deliveredAt: Date
        let wokenAt: Date
        let date: String
        let vaultRoot: String
    }

    private struct Stored: Codable {
        var entries: [Entry]
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Active entries for `today` and `vaultRoot` that have not expired.
    /// Expiry is the earlier of 60 minutes after delivery (beacon lifetime)
    /// and four hours after the wake instant (receipt max age). Expired and
    /// foreign-vault entries are purged as a side effect.
    func activeEntries(today: String, vaultRoot: String, now: Date) -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        var stored = readLocked()
        let before = stored.entries.count
        stored.entries = stored.entries.filter { entry in
            guard entry.date == today else { return false }
            let canonicalEntry = standardized(entry.vaultRoot)
            let canonicalRoot = standardized(vaultRoot)
            guard !canonicalRoot.isEmpty, canonicalEntry == canonicalRoot else { return false }
            let beaconExpiry = entry.deliveredAt.addingTimeInterval(60 * 60)
            let receiptExpiry = entry.wokenAt.addingTimeInterval(4 * 60 * 60)
            return now < beaconExpiry && now < receiptExpiry
        }
        if stored.entries.count != before {
            writeLocked(stored)
        }
        return stored.entries
    }

    func save(
        wakeID: String,
        taskKeys: [String],
        taskCount: Int,
        deliveredAt: Date,
        wokenAt: Date,
        date: String,
        vaultRoot: String
    ) {
        lock.lock()
        defer { lock.unlock() }
        var stored = readLocked()
        stored.entries.removeAll(where: { $0.wakeID == wakeID })
        stored.entries.append(Entry(
            wakeID: wakeID,
            taskKeys: taskKeys,
            taskCount: taskCount,
            deliveredAt: deliveredAt,
            wokenAt: wokenAt,
            date: date,
            vaultRoot: vaultRoot
        ))
        while stored.entries.count > Self.maxEntries {
            stored.entries.removeFirst()
        }
        writeLocked(stored)
    }

    func remove(wakeID: String) {
        lock.lock()
        defer { lock.unlock() }
        var stored = readLocked()
        let before = stored.entries.count
        stored.entries.removeAll(where: { $0.wakeID == wakeID })
        if stored.entries.count != before {
            writeLocked(stored)
        }
    }

    func removeAll(wakeIDs: Set<String>) {
        guard !wakeIDs.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var stored = readLocked()
        let before = stored.entries.count
        stored.entries.removeAll(where: { wakeIDs.contains($0.wakeID) })
        if stored.entries.count != before {
            writeLocked(stored)
        }
    }

    /// Removes every persisted beacon for `vaultRoot`. Call when the app's
    /// configured vault or Bob executable changes so no old record survives
    /// into the new client configuration.
    func removeAll(vaultRoot: String) {
        guard !vaultRoot.isEmpty else { return }
        let root = standardized(vaultRoot)
        lock.lock()
        defer { lock.unlock() }
        var stored = readLocked()
        let before = stored.entries.count
        stored.entries.removeAll { standardized($0.vaultRoot) == root }
        if stored.entries.count != before {
            writeLocked(stored)
        }
    }

    /// Drops entries that do not belong to `today` or `vaultRoot`, or that
    /// have expired as of `now`.
    func purge(today: String, vaultRoot: String, now: Date) {
        _ = activeEntries(today: today, vaultRoot: vaultRoot, now: now)
    }

    private func readLocked() -> Stored {
        guard let data = defaults.data(forKey: Self.key) else {
            return Stored(entries: [])
        }
        if let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            return stored
        }
        // Tolerate the legacy bare-array shape if it ever existed.
        if let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            return Stored(entries: entries)
        }
        return Stored(entries: [])
    }

    private func writeLocked(_ stored: Stored) {
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }
}
