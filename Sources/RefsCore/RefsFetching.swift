import CaptureCore
import Foundation

/// The `bob` calls the Refs library refreshes from. Lanes match the
/// refresh table: `refs-list` for the snapshot, `refs-git` for the added-
/// date backfill, `refs-plan` for Today, `refs-show` for the inspector's
/// per-note hydration, and `refs-rename` for the non-cancelling rename.
public protocol RefsFetching: Sendable {
  func list(gitDates: Bool) async throws -> RefsListResponse
  func plan() async throws -> RefsPlanResponse
  func show(path: String) async throws -> RefsShowResponse
  func scan() async throws -> RefsScanResponse
  func rename(notePath: String, name: String) async throws -> RefsRenameResponse
}

public final class BobRefsFetcher: RefsFetching, @unchecked Sendable {
  /// A scan takes seconds: the hook can wait out SSH timeouts and a
  /// 347-PDF scan takes about 8 s, so the scan lane allows 5 minutes.
  public static let scanTimeout: TimeInterval = 300

  /// A rename may wait for bob's sync and scan locks, then run both sync
  /// cycles. Keep the client timeout above those server-side budgets.
  public static let renameTimeout: TimeInterval = 180

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
      arguments: ["ref", "show", path, "-f", "json"],
      expectedSchema: 1,
      lane: "refs-show"
    )
  }

  public func scan() async throws -> RefsScanResponse {
    try await client.decodeReport(
      arguments: ["ref", "scan", "-w", "-f", "json"],
      expectedSchema: 1,
      lane: "refs-scan",
      cancelsPreviousInLane: false,
      timeout: Self.scanTimeout
    )
  }

  public func rename(notePath: String, name: String) async throws -> RefsRenameResponse {
    try await client.decodeReport(
      arguments: ["ref", "rename", "-f", "json", "--", notePath, name],
      expectedSchema: 1,
      lane: "refs-rename",
      cancelsPreviousInLane: false,
      timeout: Self.renameTimeout
    )
  }
}
