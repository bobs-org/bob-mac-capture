import Foundation

/// Scope and candidate provenance for one Go To Notes picker session.
///
/// The requested archive scope can move ahead of the displayed rows while Bob
/// is fetching. `appliedIncludesArchivedNotes` always describes `candidates`;
/// a failed request returns the desired scope to that applied snapshot. `true`
/// requests and describes Bob's archived-notes catalog.
public struct CaptureNoteGotoScopeState: Equatable {
    public struct Snapshot: Equatable {
        public let candidates: [CaptureCompletionCandidate]
        public let appliedIncludesArchivedNotes: Bool
        public let desiredIncludesArchivedNotes: Bool

        fileprivate init(
            candidates: [CaptureCompletionCandidate],
            appliedIncludesArchivedNotes: Bool,
            desiredIncludesArchivedNotes: Bool
        ) {
            self.candidates = candidates
            self.appliedIncludesArchivedNotes = appliedIncludesArchivedNotes
            self.desiredIncludesArchivedNotes = desiredIncludesArchivedNotes
        }
    }

    public struct Request: Equatable, Sendable {
        fileprivate let sessionID: UUID
        public let generation: UInt64
        public let includesArchivedNotes: Bool
    }

    public private(set) var sessionID: UUID?
    public private(set) var generation: UInt64 = 0
    public private(set) var candidates: [CaptureCompletionCandidate] = []
    public private(set) var appliedIncludesArchivedNotes = false
    public private(set) var desiredIncludesArchivedNotes = false
    public private(set) var pendingRequest: Request?

    public var hasPendingRequest: Bool { pendingRequest != nil }

    public init() {}

    /// Starts a distinct picker session from a Bob response or a chip snapshot.
    public mutating func beginSession(
        candidates: [CaptureCompletionCandidate],
        appliedIncludesArchivedNotes: Bool,
        desiredIncludesArchivedNotes: Bool? = nil
    ) {
        sessionID = UUID()
        generation = 0
        self.candidates = candidates
        self.appliedIncludesArchivedNotes = appliedIncludesArchivedNotes
        self.desiredIncludesArchivedNotes =
            desiredIncludesArchivedNotes ?? appliedIncludesArchivedNotes
        pendingRequest = nil
    }

    public mutating func beginSession(from snapshot: Snapshot) {
        beginSession(
            candidates: snapshot.candidates,
            appliedIncludesArchivedNotes: snapshot.appliedIncludesArchivedNotes,
            desiredIncludesArchivedNotes: snapshot.desiredIncludesArchivedNotes
        )
    }

    /// Requests a full replacement snapshot for the requested scope.
    @discardableResult
    public mutating func request(includesArchivedNotes: Bool) -> Request? {
        guard let sessionID else {
            return nil
        }
        generation &+= 1
        desiredIncludesArchivedNotes = includesArchivedNotes
        let request = Request(
            sessionID: sessionID,
            generation: generation,
            includesArchivedNotes: includesArchivedNotes
        )
        pendingRequest = request
        return request
    }

    /// Flips the latest requested choice, including while an earlier fetch is pending.
    @discardableResult
    public mutating func toggle() -> Request? {
        request(includesArchivedNotes: !desiredIncludesArchivedNotes)
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
        appliedIncludesArchivedNotes = request.includesArchivedNotes
        desiredIncludesArchivedNotes = request.includesArchivedNotes
        pendingRequest = nil
        return true
    }

    /// Settles a failed latest request back to the scope of its usable rows.
    @discardableResult
    public mutating func fail(_ request: Request) -> Bool {
        guard isCurrent(request) else {
            return false
        }
        desiredIncludesArchivedNotes = appliedIncludesArchivedNotes
        pendingRequest = nil
        return true
    }

    public var snapshot: Snapshot {
        Snapshot(
            candidates: candidates,
            appliedIncludesArchivedNotes: appliedIncludesArchivedNotes,
            desiredIncludesArchivedNotes: desiredIncludesArchivedNotes
        )
    }
}
