import Foundation

public struct CaptureTargetsSnapshot: Equatable {
    public let targets: CaptureTargetsResponse?
    public let refreshedAt: Date?
    public let stale: Bool
    public let errorDescription: String?

    public init(
        targets: CaptureTargetsResponse?,
        refreshedAt: Date?,
        stale: Bool,
        errorDescription: String?
    ) {
        self.targets = targets
        self.refreshedAt = refreshedAt
        self.stale = stale
        self.errorDescription = errorDescription
    }
}

public actor CaptureTargetsCache {
    private var lastGoodResponse: CaptureTargetsResponse?
    private var lastRefreshDate: Date?

    public init() {}

    public func snapshot() -> CaptureTargetsSnapshot {
        CaptureTargetsSnapshot(
            targets: lastGoodResponse,
            refreshedAt: lastRefreshDate,
            stale: false,
            errorDescription: nil
        )
    }

    public func refresh(
        using client: BobProcessClient,
        now: @Sendable () -> Date = { Date() }
    ) async -> CaptureTargetsSnapshot {
        do {
            let response = try await client.captureTargets()
            lastGoodResponse = response
            lastRefreshDate = now()
            return CaptureTargetsSnapshot(
                targets: response,
                refreshedAt: lastRefreshDate,
                stale: false,
                errorDescription: nil
            )
        } catch {
            return CaptureTargetsSnapshot(
                targets: lastGoodResponse,
                refreshedAt: lastRefreshDate,
                stale: lastGoodResponse != nil,
                errorDescription: String(describing: error)
            )
        }
    }

    public func markStale(errorDescription: String) -> CaptureTargetsSnapshot {
        CaptureTargetsSnapshot(
            targets: lastGoodResponse,
            refreshedAt: lastRefreshDate,
            stale: true,
            errorDescription: errorDescription
        )
    }
}
