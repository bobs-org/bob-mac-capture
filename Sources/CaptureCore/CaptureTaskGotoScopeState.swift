import Foundation

/// Scope and candidate provenance for one Go To picker session.
///
/// The requested scope can move ahead of the displayed rows while Bob is
/// fetching. `appliedIncludesClosedTasks` always describes `candidates`; a
/// failed request returns the desired scope to that applied snapshot.
public struct CaptureTaskGotoScopeState: Equatable {
    public struct Snapshot: Equatable {
        public let candidates: [CaptureCompletionCandidate]
        public let appliedIncludesClosedTasks: Bool
        public let desiredIncludesClosedTasks: Bool

        fileprivate init(
            candidates: [CaptureCompletionCandidate],
            appliedIncludesClosedTasks: Bool,
            desiredIncludesClosedTasks: Bool
        ) {
            self.candidates = candidates
            self.appliedIncludesClosedTasks = appliedIncludesClosedTasks
            self.desiredIncludesClosedTasks = desiredIncludesClosedTasks
        }
    }

    public struct Request: Equatable, Sendable {
        fileprivate let sessionID: UUID
        public let generation: UInt64
        public let includesClosedTasks: Bool
    }

    public private(set) var sessionID: UUID?
    public private(set) var generation: UInt64 = 0
    public private(set) var candidates: [CaptureCompletionCandidate] = []
    public private(set) var appliedIncludesClosedTasks = false
    public private(set) var desiredIncludesClosedTasks = false
    public private(set) var pendingRequest: Request?

    public var hasPendingRequest: Bool { pendingRequest != nil }

    public init() {}

    /// Starts a distinct picker session from a Bob response or a chip snapshot.
    public mutating func beginSession(
        candidates: [CaptureCompletionCandidate],
        appliedIncludesClosedTasks: Bool,
        desiredIncludesClosedTasks: Bool? = nil
    ) {
        sessionID = UUID()
        generation = 0
        self.candidates = candidates
        self.appliedIncludesClosedTasks = appliedIncludesClosedTasks
        self.desiredIncludesClosedTasks = desiredIncludesClosedTasks ?? appliedIncludesClosedTasks
        pendingRequest = nil
    }

    public mutating func beginSession(from snapshot: Snapshot) {
        beginSession(
            candidates: snapshot.candidates,
            appliedIncludesClosedTasks: snapshot.appliedIncludesClosedTasks,
            desiredIncludesClosedTasks: snapshot.desiredIncludesClosedTasks
        )
    }

    /// Requests a full replacement snapshot for the requested scope.
    @discardableResult
    public mutating func request(includesClosedTasks: Bool) -> Request? {
        guard let sessionID else {
            return nil
        }
        generation &+= 1
        desiredIncludesClosedTasks = includesClosedTasks
        let request = Request(
            sessionID: sessionID,
            generation: generation,
            includesClosedTasks: includesClosedTasks
        )
        pendingRequest = request
        return request
    }

    /// Flips the latest requested choice, including while an earlier fetch is pending.
    @discardableResult
    public mutating func toggle() -> Request? {
        request(includesClosedTasks: !desiredIncludesClosedTasks)
    }

    /// Invalidates in-flight responses while preserving the chip's desired scope
    /// and the applied candidate snapshot.
    public mutating func invalidatePendingRequest() {
        generation &+= 1
        pendingRequest = nil
    }

    public func isCurrent(_ request: Request) -> Bool {
        pendingRequest == request
            && sessionID == request.sessionID
            && generation == request.generation
    }

    /// Applies candidates and their scope as one operation for the latest request.
    @discardableResult
    public mutating func apply(
        candidates: [CaptureCompletionCandidate],
        for request: Request
    ) -> Bool {
        guard isCurrent(request) else {
            return false
        }
        self.candidates = candidates
        appliedIncludesClosedTasks = request.includesClosedTasks
        desiredIncludesClosedTasks = request.includesClosedTasks
        pendingRequest = nil
        return true
    }

    /// Settles a failed latest request back to the scope of its usable rows.
    @discardableResult
    public mutating func fail(_ request: Request) -> Bool {
        guard isCurrent(request) else {
            return false
        }
        desiredIncludesClosedTasks = appliedIncludesClosedTasks
        pendingRequest = nil
        return true
    }

    public var snapshot: Snapshot {
        Snapshot(
            candidates: candidates,
            appliedIncludesClosedTasks: appliedIncludesClosedTasks,
            desiredIncludesClosedTasks: desiredIncludesClosedTasks
        )
    }
}
