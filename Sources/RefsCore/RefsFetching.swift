import CaptureCore
import Foundation

/// The `bob` calls the Refs library refreshes from. Lanes match the
/// refresh table: `refs-list` for the snapshot, `refs-git` for the added-
/// date backfill, `refs-plan` for Today, and `refs-show` for the
/// inspector's per-note hydration.
public protocol RefsFetching: Sendable {
    func list(gitDates: Bool) async throws -> RefsListResponse
    func plan() async throws -> RefsPlanResponse
    func show(path: String) async throws -> RefsShowResponse
}

public final class BobRefsFetcher: RefsFetching, @unchecked Sendable {
    private let client: BobProcessClient

    public init(client: BobProcessClient) {
        self.client = client
    }

    public func list(gitDates: Bool) async throws -> RefsListResponse {
        var arguments = ["ref", "list", "-R", "all", "-A", "-f", "json"]
        if gitDates {
            arguments.append("-g")
        }
        return try await client.decode(
            arguments: arguments,
            expectedSchema: 1,
            lane: gitDates ? "refs-git" : "refs-list"
        )
    }

    public func plan() async throws -> RefsPlanResponse {
        try await client.decode(
            arguments: ["plan", "-f", "json"],
            expectedSchema: 2,
            lane: "refs-plan"
        )
    }

    public func show(path: String) async throws -> RefsShowResponse {
        try await client.decode(
            arguments: ["ref", "show", path, "-f", "json", "-c"],
            expectedSchema: 1,
            lane: "refs-show"
        )
    }
}
