import CaptureCore
import Foundation

/// The `bob` calls the Refs library refreshes from. Lanes match the
/// refresh table: `refs-list` for the snapshot, `refs-git` for the added-
/// date backfill, `refs-plan` for Today, `refs-show` for the inspector's
/// per-note hydration, `refs-rename` for the non-cancelling rename, and
/// `refs-pull` for the vault fast-forward before a panel show or refresh.
public protocol RefsFetching: Sendable {
  func list(gitDates: Bool) async throws -> RefsListResponse
  func plan() async throws -> RefsPlanResponse
  func show(path: String) async throws -> RefsShowResponse
  func scan() async throws -> RefsScanResponse
  func rename(notePath: String, name: String) async throws -> RefsRenameResponse
  func linkToToday(
    notePath: String, selector: RefsTodayLinkSelector, dryRun: Bool
  ) async throws -> RefsTodayLinkResponse
  func pull() async throws
}

public enum RefsFetchingError: Error, Sendable {
  case unsupported
}

public extension RefsFetching {
  /// Older fake fetchers need not implement the Today-link lane unless a
  /// panel-model test exercises it. The production fetcher supplies the
  /// Bob-backed implementation below.
  func linkToToday(
    notePath: String, selector: RefsTodayLinkSelector, dryRun: Bool
  ) async throws -> RefsTodayLinkResponse {
    throw RefsFetchingError.unsupported
  }

  /// Older fake fetchers need not implement the pull lane unless a
  /// pull test exercises it. The production fetcher runs
  /// `bob vault-sync -q` on the `refs-pull` lane.
  func pull() async throws {
    throw RefsFetchingError.unsupported
  }
}

public final class BobRefsFetcher: RefsFetching, @unchecked Sendable {
  /// A scan takes seconds: the hook can wait out SSH timeouts and a
  /// 347-PDF scan takes about 8 s, so the scan lane allows 5 minutes.
  public static let scanTimeout: TimeInterval = 300

  /// A rename may wait for bob's sync and scan locks, then run both sync
  /// cycles. Keep the client timeout above those server-side budgets.
  public static let renameTimeout: TimeInterval = 180

  public static let todayLinkTimeout: TimeInterval = 30

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
    var arguments = ["ref", "scan", "-w", "-f", "json"]
    let sendAttended = !client.attendedFlagKnownUnsupported
    if sendAttended {
      arguments = ["ref", "scan", "-a", "-w", "-f", "json"]
    }
    return try await client.decodeReport(
      arguments: arguments,
      expectedSchema: 1,
      lane: "refs-scan",
      cancelsPreviousInLane: false,
      timeout: Self.scanTimeout,
      allowsGuardFallback: sendAttended
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

  public func linkToToday(
    notePath: String, selector: RefsTodayLinkSelector = .automatic, dryRun: Bool
  ) async throws -> RefsTodayLinkResponse {
    try await client.decodeReport(
      arguments: ["ref", "today", "-f", "json"] + (dryRun ? ["-d"] : [])
        + selector.arguments + ["--", notePath],
      expectedSchema: 1,
      lane: dryRun ? "refs-today-preview" : "refs-today",
      cancelsPreviousInLane: dryRun,
      timeout: dryRun ? BobProcessClient.defaultTimeout : Self.todayLinkTimeout
    )
  }

  /// Fast-forwards the local vault before a panel show or refresh.
  /// `bob vault-sync` returns quietly when the maintenance lock is held,
  /// so this never fights the 15 s LaunchAgent, a scan, or a rename.
  public func pull() async throws {
    let result = try await client.run(
      arguments: ["vault-sync", "-q"],
      lane: "refs-pull",
      cancelsPreviousInLane: false
    )
    guard result.exitStatus == 0 else {
      throw BobClientError.processFailed(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: result.stderr
      )
    }
  }

}
