import Foundation

/// A bounded key buffer for editor operations whose meaning can change after an
/// asynchronous rewrite reply. The caller supplies monotonic timestamps so deadline
/// behavior stays deterministic in tests.
public enum CaptureTypeAheadHoldDefaults {
    public static let deadline: TimeInterval = 0.2
    public static let capacity = 32
}

public struct CaptureTypeAheadHold<Key> {
    public struct Snapshot {
        public let generation: UInt64
        public let keys: [Key]
        public let duration: TimeInterval
    }

    public enum AppendResult {
        case inactive
        case buffered
        case expired(Snapshot)
        case overflow(Snapshot)
    }

    public let deadline: TimeInterval
    public let capacity: Int

    public private(set) var generation: UInt64?
    public private(set) var keyCount = 0
    private var startedAt: TimeInterval?
    private var keys: [Key] = []

    public init(
        deadline: TimeInterval = CaptureTypeAheadHoldDefaults.deadline,
        capacity: Int = CaptureTypeAheadHoldDefaults.capacity
    ) {
        self.deadline = max(0, deadline)
        self.capacity = max(0, capacity)
    }

    public var isActive: Bool {
        generation != nil
    }

    public func timeRemaining(at time: TimeInterval) -> TimeInterval? {
        guard let startedAt, isActive else {
            return nil
        }
        return max(0, startedAt + deadline - time)
    }

    @discardableResult
    public mutating func begin(generation: UInt64, at time: TimeInterval) -> Bool {
        guard !isActive else {
            return false
        }
        self.generation = generation
        startedAt = time
        keyCount = 0
        keys = []
        return true
    }

    /// Queues one key. The key that crosses the deadline or cap is included in the
    /// returned snapshot so callers can replay edit keys and discard submit keys in
    /// typed order.
    public mutating func append(_ key: Key, at time: TimeInterval) -> AppendResult {
        guard isActive else {
            return .inactive
        }
        keys.append(key)
        keyCount = keys.count
        if hasExpired(at: time) {
            return .expired(takeSnapshot(at: time))
        }
        if keys.count > capacity {
            return .overflow(takeSnapshot(at: time))
        }
        return .buffered
    }

    public mutating func expire(generation: UInt64, at time: TimeInterval) -> Snapshot? {
        guard self.generation == generation, hasExpired(at: time) else {
            return nil
        }
        return takeSnapshot(at: time)
    }

    public mutating func finish(generation: UInt64, at time: TimeInterval) -> Snapshot? {
        guard self.generation == generation else {
            return nil
        }
        return takeSnapshot(at: time)
    }

    /// Ends the active hold for a focus, click, or dismissal flush.
    public mutating func end(at time: TimeInterval) -> Snapshot? {
        guard isActive else {
            return nil
        }
        return takeSnapshot(at: time)
    }

    private func hasExpired(at time: TimeInterval) -> Bool {
        guard let startedAt else {
            return false
        }
        return time >= startedAt + deadline
    }

    private mutating func takeSnapshot(at time: TimeInterval) -> Snapshot {
        let snapshot = Snapshot(
            generation: generation ?? 0,
            keys: keys,
            duration: max(0, time - (startedAt ?? time))
        )
        generation = nil
        startedAt = nil
        keyCount = 0
        keys = []
        return snapshot
    }
}
