@preconcurrency import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public struct BobProcessResult: Equatable {
  public let generation: UInt64
  public let command: [String]
  public let exitStatus: Int32
  public let stdout: String
  public let stderr: String
}

/// A deliberate answer to Bob's successor-offer prompt. Keys are Bob's
/// opaque identities, kept in display order; `.none` is distinct from no
/// decision so an explicit empty choice can be committed safely.
public enum CapturePullInSelection: Equatable, Sendable {
  case keys([String])
  case none
}

public final class BobProcessClient: @unchecked Sendable {
  // Every `bob` invocation is local, offline, and expected to finish in well under a
  // second; 20s is a generous bound that only fires for a genuinely wedged process
  // (missing dependency, stuck filesystem mount) so the panel can never wait forever.
  public static let defaultTimeout: TimeInterval = 20

  private let executablePath: String
  private let environment: [String: String]
  private let decoder: JSONDecoder
  private let stateQueue = DispatchQueue(label: "org.bobs.bob-mac-capture.process-client")
  private var activeProcesses: [String: ActiveProcess] = [:]
  private var activeGeneration: UInt64 = 0
  private var unsupportedGuardIdentity: String?
  private var unsupportedGuardFlags: Set<String> = []
  private var savedTemplatesIdentity: String?

  public init(
    executablePath: String,
    environment: [String: String],
    decoder: JSONDecoder = BobProcessClient.makeDecoder()
  ) {
    self.executablePath = executablePath
    self.environment = environment
    self.decoder = decoder
  }

  public static func makeDecoder() -> JSONDecoder {
    JSONDecoder()
  }

  /// Changes if the resolved executable is replaced in place, which
  /// invalidates the cached compatibility result for its guard flags.
  public var identityToken: String {
    let attributes = try? FileManager.default.attributesOfItem(atPath: executablePath)
    let device = attributes?[.systemNumber].map { String(describing: $0) } ?? "?"
    let inode = attributes?[.systemFileNumber].map { String(describing: $0) } ?? "?"
    let size = attributes?[.size].map { String(describing: $0) } ?? "?"
    let modified = attributes?[.modificationDate].map { String(describing: $0) } ?? "?"
    return "\(executablePath)|\(device)|\(inode)|\(size)|\(modified)"
  }

  public var pullInGuardKnownUnsupported: Bool {
    guardFlagKnownUnsupported("--require-pull-in-choice")
  }

  public var refuseOverrideKnownUnsupported: Bool {
    guardFlagKnownUnsupported("--refuse-override")
  }

  public func captureParse(
    _ draft: String,
    lane: String = "parse"
  ) async throws -> CaptureParseResponse {
    let response: CaptureParseResponse = try await decode(
      arguments: ["capture-parse", "--format", "json", "--", draft],
      expectedSchema: 1,
      lane: lane
    )
    return response
  }

  public func capturePomodoros(includeCompleted: Bool = false) async throws
    -> CapturePomodorosResponse
  {
    var arguments = ["capture-pomodoros", "--format", "json"]
    if includeCompleted {
      arguments.append("--all")
    }
    let response: CapturePomodorosResponse = try await decode(
      arguments: arguments,
      expectedSchema: 1,
      lane: "pomodoros"
    )
    return response
  }

  /// Today's agenda from `bob capture-pomodoros --tasks --format json`.
  /// Byte-identical stdout is a no-op: when `previous` matches the fresh
  /// output bytes, nothing is decoded and `.unchanged` is returned. An
  /// older bob without `--tasks` fails with clap's unexpected-argument
  /// error, which maps to `BobClientError.unsupportedOption`.
  public func captureAgenda(previous: Data? = nil) async throws -> CaptureAgendaFetch {
    let arguments = ["capture-pomodoros", "--format", "json", "--tasks"]
    let result = try await run(arguments: arguments, lane: "agenda")
    let command = [executablePath] + arguments
    let stderr = boundedProcessText(result.stderr)

    if result.exitStatus != 0 {
      if Self.isUnsupportedOptionFailure(stderr: stderr, option: "--tasks") {
        throw BobClientError.unsupportedOption("--tasks")
      }
      throw BobClientError.processFailed(
        command: command,
        exitStatus: result.exitStatus,
        stderr: stderr
      )
    }

    let bytes = Data(result.stdout.utf8)
    if let previous, previous == bytes {
      return .unchanged
    }

    let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedStdout.isEmpty else {
      throw BobClientError.emptyStdout(
        command: command,
        exitStatus: result.exitStatus,
        stderr: stderr
      )
    }

    do {
      let snapshot = try decoder.decode(
        CaptureAgendaSnapshot.self,
        from: Data(trimmedStdout.utf8)
      )
      guard snapshot.schemaVersion == 1 else {
        throw BobClientError.schemaMismatch(
          command: command,
          expected: 1,
          actual: snapshot.schemaVersion
        )
      }
      return .changed(snapshot: snapshot, bytes: bytes)
    } catch let error as BobClientError {
      throw error
    } catch {
      throw BobClientError.malformedJSON(
        command: command,
        exitStatus: result.exitStatus,
        stderr: stderr,
        reason: error.localizedDescription
      )
    }
  }

  /// Clap reports an unknown flag as `error: unexpected argument
  /// '<flag>' found` on stderr: that is an old bob, not a broken vault.
  static func isUnsupportedOptionFailure(stderr: String, option: String) -> Bool {
    stderr.contains("unexpected argument") && stderr.contains(option)
  }

  public func captureRewrite(
    _ draft: String,
    cursor: Int
  ) async throws -> CaptureRewriteResponse {
    let response: CaptureRewriteResponse = try await decode(
      arguments: [
        "capture-rewrite",
        "--cursor",
        String(cursor),
        "--format",
        "json",
        "--",
        draft,
      ],
      expectedSchema: 1,
      lane: "rewrite"
    )
    return response
  }

  public func captureComplete(
    _ draft: String,
    cursor: Int
  ) async throws -> CaptureCompletionResponse {
    let response: CaptureCompletionResponse = try await decode(
      arguments: [
        "capture-complete",
        "--all-tasks",
        "--cursor",
        String(cursor),
        "--format",
        "json",
        "--",
        draft,
      ],
      expectedSchema: 1,
      lane: "completion"
    )
    return response
  }

  public func assignCaptureTaskID(
    route: String,
    taskRef: String,
    blockID: String,
    dryRun: Bool = false
  ) async throws -> CaptureTaskIDResponse {
    var arguments = [
      "capture-task-id",
      "--route",
      route,
      "--task-ref",
      taskRef,
      "--block-id",
      blockID,
      "--format",
      "json",
    ]
    if dryRun {
      arguments.append("--dry-run")
    }

    return try await decodeCaptureTaskIDResult(arguments: arguments, lane: "task-id")
  }

  /// Explicit Add block ID for a `task_dependency` candidate: the exact
  /// vault-relative `notePath` round-trips nested, case-sensitive, and
  /// quoted paths without touching the lowercasing route parser, so the
  /// app never rebuilds a locator with string interpolation. `allowClosed`
  /// additionally permits Done/Cancelled history rows without reopening
  /// them. The success carries Bob's `dependency_replacement` to splice.
  public func assignDependencyTaskID(
    notePath: String,
    taskRef: String,
    blockID: String,
    dryRun: Bool = false,
    allowClosed: Bool = false
  ) async throws -> CaptureTaskIDResponse {
    var arguments = [
      "capture-task-id",
      "--note-path",
      notePath,
      "--task-ref",
      taskRef,
      "--block-id",
      blockID,
      "--format",
      "json",
    ]
    if dryRun {
      arguments.append("--dry-run")
    }
    if allowClosed {
      arguments.append("--allow-closed")
    }

    return try await decodeCaptureTaskIDResult(arguments: arguments, lane: "task-id")
  }

  public func assignPomodoroName(
    ref: String,
    name: String,
    dryRun: Bool = false
  ) async throws -> CapturePomodoroNameResponse {
    var arguments = [
      "capture-pomodoro-name",
      "--pomodoro-ref",
      ref,
      "--name",
      name,
      "--format",
      "json",
    ]
    if dryRun {
      arguments.append("--dry-run")
    }

    return try await decodeCapturePomodoroNameResult(arguments: arguments, lane: "pomodoro-name")
  }

  public func captureTargets() async throws -> CaptureTargetsResponse {
    let response: CaptureTargetsResponse = try await decode(
      arguments: ["capture-targets", "--format", "json"],
      expectedSchema: 1,
      lane: "targets"
    )
    return response
  }

  /// Read the bob-owned template shelf. A successful read proves that this
  /// executable understands `--template-origin`; the identity token is
  /// checked again before remembering that capability in case bob changed
  /// while the child process was running.
  public func savedTemplates() async throws -> CaptureSavedTemplatesResponse {
    let requestedIdentity = identityToken
    let response: CaptureSavedTemplatesResponse = try await decodeTemplateCommand(
      arguments: ["capture-templates", "--format", "json"],
      expectedSchema: 1,
      lane: "template-list"
    )
    let currentIdentity = identityToken
    if requestedIdentity == currentIdentity {
      stateQueue.sync {
        savedTemplatesIdentity = currentIdentity
      }
    }
    return response
  }

  public func saveTemplate(
    _ draft: String,
    origin: String? = nil
  ) async throws -> CaptureTemplateSaveResponse {
    var arguments = ["capture-templates", "save", "--format", "json"]
    if let origin, !origin.isEmpty {
      arguments += ["--template-origin", origin]
    }
    arguments += ["--", draft]
    return try await decodeTemplateCommand(
      arguments: arguments,
      lane: "template-save"
    )
  }

  public func deleteSavedTemplates(ids: [String]) async throws -> CaptureTemplateDeleteResponse {
    var arguments = ["capture-templates", "delete"] + ids
    arguments += ["--format", "json"]
    return try await decodeTemplateCommand(
      arguments: arguments,
      lane: "template-delete"
    )
  }

  public func clearSavedTemplates() async throws -> CaptureTemplateClearResponse {
    try await decodeTemplateCommand(
      arguments: ["capture-templates", "clear", "--format", "json"],
      lane: "template-clear"
    )
  }

  public func captureLivePreview(
    _ draft: String,
    priorityRollSeed: String
  ) async throws -> CaptureCommandResponse {
    let arguments = [
      "capture",
      "--dry-run",
      "--no-clip",
      "--format",
      "json",
      "--",
      draft,
    ]
    Self.preconditionLivePreviewArguments(arguments)

    let response = try await decodeCaptureResult(
      arguments: arguments,
      environmentOverrides: ["BOB_PRIORITY_ROLL_SEED": priorityRollSeed],
      lane: "preview"
    )
    return response
  }

  public func capture(
    _ draft: String,
    dryRun: Bool = false,
    readClipboard: Bool = true,
    priorityRollSeed: String? = nil,
    pullInSelection: CapturePullInSelection? = nil,
    requirePullInChoice: Bool = false,
    refuseOverride: Bool = false,
    pullInCapabilityAdvertised: Bool = false,
    templateOrigin: String? = nil
  ) async throws -> CaptureCommandResponse {
    if pullInSelection != nil, !pullInCapabilityAdvertised {
      throw BobClientError.unsupportedOption("--pull-in")
    }
    var arguments = ["capture", "--format", "json"]
    if dryRun {
      arguments.append("--dry-run")
    }
    if !readClipboard {
      arguments.append("--no-clip")
    }
    if let pullInSelection {
      switch pullInSelection {
      case .keys(let keys):
        guard !keys.isEmpty, keys.allSatisfy({ !$0.isEmpty }) else {
          throw BobClientError.unsupportedOption("--pull-in requires opaque offer keys")
        }
        arguments += ["--pull-in", keys.joined(separator: ",")]
      case .none:
        arguments += ["--pull-in", "none"]
      }
    }
    let requireGuard = requirePullInChoice && !pullInGuardKnownUnsupported
    if requireGuard {
      arguments.append("--require-pull-in-choice")
    }
    let sendRefuseOverride = refuseOverride && !refuseOverrideKnownUnsupported
    if sendRefuseOverride {
      arguments.append("--refuse-override")
    }
    let currentIdentity = identityToken
    let maySendTemplateOrigin = stateQueue.sync {
      savedTemplatesIdentity == currentIdentity
    }
    if maySendTemplateOrigin, let templateOrigin, !templateOrigin.isEmpty {
      arguments += ["--template-origin", templateOrigin]
    }
    arguments.append("--")
    arguments.append(draft)
    let environmentOverrides = priorityRollSeed.map { ["BOB_PRIORITY_ROLL_SEED": $0] } ?? [:]
    let lane = dryRun ? "preview-explicit" : "submit"
    return try await decodeCaptureResult(
      arguments: arguments,
      environmentOverrides: environmentOverrides,
      lane: lane,
      allowsGuardFallback: requireGuard || sendRefuseOverride
    )
  }

  private func guardFlagKnownUnsupported(_ flag: String) -> Bool {
    let identity = identityToken
    return stateQueue.sync {
      if unsupportedGuardIdentity != identity {
        unsupportedGuardIdentity = identity
        unsupportedGuardFlags = []
      }
      return unsupportedGuardFlags.contains(flag)
    }
  }

  private func rememberGuardFlagUnsupported(_ flag: String) {
    let identity = identityToken
    stateQueue.sync {
      if unsupportedGuardIdentity != identity {
        unsupportedGuardIdentity = identity
        unsupportedGuardFlags = []
      }
      unsupportedGuardFlags.insert(flag)
    }
  }

  private static func unsupportedGuardFlag(exitStatus: Int32, stderr: String) -> String? {
    guard exitStatus == 2 else { return nil }
    let normalized = stderr.lowercased()
    for flag in ["--require-pull-in-choice", "--refuse-override"] {
      if normalized.contains("unexpected argument '\(flag)'")
        || normalized.contains("unexpected argument \"\(flag)\"")
      {
        return flag
      }
    }
    return nil
  }

  public func run(
    arguments: [String],
    environmentOverrides: [String: String] = [:],
    lane: String = "default",
    cancelsPreviousInLane: Bool = true,
    timeout: TimeInterval = BobProcessClient.defaultTimeout
  ) async throws -> BobProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.environment = environment.merging(environmentOverrides) { _, override in override }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let command = [executablePath] + arguments
    let generation = nextGeneration(
      replacingWith: process,
      lane: lane,
      cancelsPreviousInLane: cancelsPreviousInLane
    )

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        // Both the timeout and the real termination handler race to resume the
        // continuation; this guard makes whichever fires first authoritative and
        // makes the other a no-op instead of a fatal double-resume.
        let resumeGuard = ResumeGuard()

        // A pipe holds at most 64 KiB: a child writing more blocks in
        // `write(2)` until someone drains it. `task_link` responses are
        // hundreds of KiB, so stdout and stderr must drain concurrently
        // while the child runs — never only after it exits.
        let drain = ProcessOutputDrain(
          stdout: stdoutPipe.fileHandleForReading,
          stderr: stderrPipe.fileHandleForReading
        )

        // Runs on `stateQueue` (see `asyncAfter` below), so it must use the
        // already-on-the-queue clear helper, not the `.sync`-wrapping one.
        //
        // `DispatchWorkItem.cancel()` is documented thread-safe, so it's sound to
        // share this across the termination handler's `@Sendable` closure even
        // though the type itself isn't `Sendable`.
        //
        // The timeout covers the whole span (exit plus both drains reaching
        // EOF) and is cancelled only when all three are done. A grandchild
        // that inherits a pipe then times out instead of hanging forever.
        nonisolated(unsafe) let timeoutWorkItem = DispatchWorkItem { [weak self] in
          guard resumeGuard.markResumed() else { return }
          Self.terminateIfRunning(process)
          self?.clearActiveProcessAlreadyOnStateQueue(
            process: process, generation: generation, lane: lane)
          continuation.resume(throwing: BobClientError.timedOut(command: command, seconds: timeout))
        }
        // Every resume funnels through `ResumeGuard`, so sharing the
        // continuation with the `@Sendable` drain completion below is sound.
        let unsafeContinuation = continuation
        let completionQueue = stateQueue
        stateQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

        process.terminationHandler = { [weak self] completedProcess in
          let exitStatus = completedProcess.terminationStatus
          drain.notifyComplete(on: completionQueue) { [weak self] stdout, stderr in
            timeoutWorkItem.cancel()
            guard resumeGuard.markResumed() else { return }
            // Already on `stateQueue` (see `notifyComplete` call site),
            // so use the already-on-the-queue clear helper to keep the
            // no-reentrant `stateQueue.sync` rule.
            if let self {
              self.clearActiveProcessAlreadyOnStateQueue(
                process: completedProcess,
                generation: generation,
                lane: lane
              )
            }
            unsafeContinuation.resume(
              returning: BobProcessResult(
                generation: generation,
                command: command,
                exitStatus: exitStatus,
                stdout: stdout,
                stderr: stderr
              )
            )
          }
        }

        do {
          try Self.launch(process)
          drain.start()
        } catch {
          drain.cancelForLaunchFailure()
          timeoutWorkItem.cancel()
          guard resumeGuard.markResumed() else { return }
          clearActiveProcess(process: process, generation: generation, lane: lane)
          continuation.resume(throwing: error)
        }
      }
    } onCancel: {
      Self.terminateIfRunning(process)
    }
  }

  public func cancelActiveProcess() {
    stateQueue.sync {
      for active in activeProcesses.values {
        Self.terminateIfRunning(active.process)
      }
      activeProcesses.removeAll()
    }
  }

  // Foundation raises NSInvalidArgumentException (which Swift cannot catch) when
  // `terminate()` is sent before `run()`. A process enters `activeProcesses` just
  // before it is launched, so cancellation and lane replacement must tolerate that
  // short pre-launch interval instead of taking down the host application.
  static func terminateIfRunning(_ process: Process) {
    guard process.isRunning else {
      return
    }
    process.terminate()
  }

  private static func launch(_ process: Process) throws {
    // Foundation inherits the calling thread's signal mask when it starts a
    // process. Swift concurrency workers can block SIGTERM (and other signals),
    // which makes terminate() ineffective and can disrupt normal child handling.
    var childSignalMask = sigset_t()
    sigemptyset(&childSignalMask)

    var previousSignalMask = sigset_t()
    let maskError = pthread_sigmask(SIG_SETMASK, &childSignalMask, &previousSignalMask)
    guard maskError == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: Int32(maskError)) ?? .EINVAL)
    }

    defer {
      pthread_sigmask(SIG_SETMASK, &previousSignalMask, nil)
    }
    try process.run()
  }

  public static func preconditionLivePreviewArguments(_ arguments: [String]) {
    precondition(arguments.first == "capture", "live preview must invoke bob capture")
    precondition(arguments.contains("--dry-run"), "live preview must be a dry run")
    precondition(arguments.contains("--no-clip"), "live preview must never read clipboard")
    precondition(arguments.contains("--format"), "live preview must request JSON")
  }

  /// Shared JSON-envelope decode for `bob` subcommands that report a
  /// `schema_version`: runs `bob` on `lane`, maps transport failures, and
  /// rejects an unexpected schema. RefsCore reuses this instead of
  /// duplicating the error mapping.
  public func decode<T: Decodable & SchemaVersioned>(
    arguments: [String],
    expectedSchema: Int,
    environmentOverrides: [String: String] = [:],
    lane: String = "default",
    timeout: TimeInterval = BobProcessClient.defaultTimeout
  ) async throws -> T {
    let result = try await run(
      arguments: arguments,
      environmentOverrides: environmentOverrides,
      lane: lane,
      timeout: timeout
    )
    let stderr = boundedProcessText(result.stderr)

    guard result.exitStatus == 0 else {
      throw BobClientError.processFailed(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr
      )
    }

    let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedStdout.isEmpty else {
      throw BobClientError.emptyStdout(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr
      )
    }

    do {
      let value = try decoder.decode(T.self, from: Data(trimmedStdout.utf8))
      guard value.schemaVersion == expectedSchema else {
        throw BobClientError.schemaMismatch(
          command: result.command,
          expected: expectedSchema,
          actual: value.schemaVersion
        )
      }
      return value
    } catch let error as BobClientError {
      throw error
    } catch {
      throw BobClientError.malformedJSON(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr,
        reason: error.localizedDescription
      )
    }
  }

  private func decodeTemplateCommand<T: Decodable>(
    arguments: [String],
    expectedSchema: Int? = nil,
    lane: String
  ) async throws -> T {
    let result = try await run(arguments: arguments, lane: lane)
    let stderr = boundedProcessText(result.stderr)
    let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if result.exitStatus != 0 {
      if Self.isUnsupportedCaptureTemplatesFailure(exitStatus: result.exitStatus, stderr: stderr) {
        throw BobClientError.unsupportedCommand("capture-templates")
      }
      if !trimmedStdout.isEmpty,
        let value = try? decoder.decode(T.self, from: Data(trimmedStdout.utf8)),
        let failure = value as? CaptureTemplateProtocolResponse,
        !failure.ok,
        failure.error != nil
      {
        return value
      }
      throw BobClientError.processFailed(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr
      )
    }

    guard !trimmedStdout.isEmpty else {
      throw BobClientError.emptyStdout(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr
      )
    }

    do {
      let value = try decoder.decode(T.self, from: Data(trimmedStdout.utf8))
      if let expectedSchema, let versioned = value as? SchemaVersioned,
        versioned.schemaVersion != expectedSchema
      {
        throw BobClientError.schemaMismatch(
          command: result.command,
          expected: expectedSchema,
          actual: versioned.schemaVersion
        )
      }
      return value
    } catch let error as BobClientError {
      throw error
    } catch {
      throw BobClientError.malformedJSON(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr,
        reason: error.localizedDescription
      )
    }
  }

  static func isUnsupportedCaptureTemplatesFailure(exitStatus: Int32, stderr: String) -> Bool {
    guard exitStatus == 2 else { return false }
    let normalized = stderr.lowercased()
    return normalized.contains("unrecognized subcommand 'capture-templates'")
      || normalized.contains("unrecognized subcommand \"capture-templates\"")
  }

  /// Report decode for `bob` subcommands whose stdout carries a valid
  /// envelope even on a non-zero exit (`bob ref scan -f json` reports
  /// per-PDF and hard failures that way). Unlike `decode`, the exit
  /// status is consulted only after stdout fails to decode:
  ///
  /// 1. Trimmed stdout decodes as `T`: the schema is checked
  ///    (`schemaMismatch` on a mismatch) and the value is returned
  ///    whatever the exit status.
  /// 2. Non-empty stdout does not decode: a non-zero exit throws
  ///    `processFailed` with bounded stderr; exit 0 throws
  ///    `malformedJSON`.
  /// 3. Empty stdout: a non-zero exit throws `processFailed`; exit 0
  ///    throws `emptyStdout`.
  ///
  /// Timeouts and launch errors propagate unchanged.
  public func decodeReport<T: Decodable & SchemaVersioned>(
    arguments: [String],
    expectedSchema: Int,
    environmentOverrides: [String: String] = [:],
    lane: String = "default",
    cancelsPreviousInLane: Bool = true,
    timeout: TimeInterval = BobProcessClient.defaultTimeout
  ) async throws -> T {
    let result = try await run(
      arguments: arguments,
      environmentOverrides: environmentOverrides,
      lane: lane,
      cancelsPreviousInLane: cancelsPreviousInLane,
      timeout: timeout
    )
    let stderr = boundedProcessText(result.stderr)
    let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

    do {
      let value = try decoder.decode(T.self, from: Data(trimmedStdout.utf8))
      guard value.schemaVersion == expectedSchema else {
        throw BobClientError.schemaMismatch(
          command: result.command,
          expected: expectedSchema,
          actual: value.schemaVersion
        )
      }
      return value
    } catch let error as BobClientError {
      throw error
    } catch {
      if !trimmedStdout.isEmpty {
        if result.exitStatus != 0 {
          throw BobClientError.processFailed(
            command: result.command,
            exitStatus: result.exitStatus,
            stderr: stderr
          )
        }
        throw BobClientError.malformedJSON(
          command: result.command,
          exitStatus: result.exitStatus,
          stderr: stderr,
          reason: error.localizedDescription
        )
      }
      if result.exitStatus != 0 {
        throw BobClientError.processFailed(
          command: result.command,
          exitStatus: result.exitStatus,
          stderr: stderr
        )
      }
      throw BobClientError.emptyStdout(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr
      )
    }
  }

  // `bob capture` has no schema_version and reports `ok: false` failures with a
  // non-zero exit but a fully valid JSON body, so it cannot use `decode(_:expectedSchema:)`:
  // that path treats any non-zero exit as a transport failure before looking at stdout,
  // which would discard the real, actionable `error` message bob already produced.
  private func decodeCaptureResult(
    arguments: [String],
    environmentOverrides: [String: String] = [:],
    lane: String = "default",
    allowsGuardFallback: Bool = false
  ) async throws -> CaptureCommandResponse {
    let result = try await run(
      arguments: arguments, environmentOverrides: environmentOverrides, lane: lane)
    let stderr = boundedProcessText(result.stderr)
    let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

    if allowsGuardFallback,
      trimmedStdout.isEmpty,
      let unsupportedFlag = Self.unsupportedGuardFlag(
        exitStatus: result.exitStatus, stderr: stderr),
      let flagIndex = arguments.firstIndex(of: unsupportedFlag)
    {
      rememberGuardFlagUnsupported(unsupportedFlag)
      var retryArguments = arguments
      retryArguments.remove(at: flagIndex)
      return try await decodeCaptureResult(
        arguments: retryArguments,
        environmentOverrides: environmentOverrides,
        lane: lane,
        allowsGuardFallback: true
      )
    }

    guard !trimmedStdout.isEmpty else {
      if result.exitStatus != 0 {
        throw BobClientError.processFailed(
          command: result.command,
          exitStatus: result.exitStatus,
          stderr: stderr
        )
      }
      throw BobClientError.emptyStdout(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr
      )
    }

    do {
      return try decoder.decode(CaptureCommandResponse.self, from: Data(trimmedStdout.utf8))
    } catch {
      if result.exitStatus != 0 {
        throw BobClientError.processFailed(
          command: result.command,
          exitStatus: result.exitStatus,
          stderr: stderr
        )
      }
      throw BobClientError.malformedJSON(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr,
        reason: error.localizedDescription
      )
    }
  }

  private func decodeCaptureTaskIDResult(
    arguments: [String],
    lane: String
  ) async throws -> CaptureTaskIDResponse {
    let result = try await run(arguments: arguments, lane: lane)
    let stderr = boundedProcessText(result.stderr)
    let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedStdout.isEmpty else {
      if result.exitStatus != 0 {
        throw BobClientError.processFailed(
          command: result.command,
          exitStatus: result.exitStatus,
          stderr: stderr
        )
      }
      throw BobClientError.emptyStdout(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr
      )
    }

    do {
      let response = try decoder.decode(CaptureTaskIDResponse.self, from: Data(trimmedStdout.utf8))
      if case .success(let success) = response, success.schemaVersion != 1 {
        throw BobClientError.schemaMismatch(
          command: result.command,
          expected: 1,
          actual: success.schemaVersion
        )
      }
      return response
    } catch let error as BobClientError {
      throw error
    } catch {
      if result.exitStatus != 0 {
        throw BobClientError.processFailed(
          command: result.command,
          exitStatus: result.exitStatus,
          stderr: stderr
        )
      }
      throw BobClientError.malformedJSON(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr,
        reason: error.localizedDescription
      )
    }
  }

  private func decodeCapturePomodoroNameResult(
    arguments: [String],
    lane: String
  ) async throws -> CapturePomodoroNameResponse {
    let result = try await run(arguments: arguments, lane: lane)
    let stderr = boundedProcessText(result.stderr)
    let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedStdout.isEmpty else {
      if result.exitStatus != 0 {
        throw BobClientError.processFailed(
          command: result.command,
          exitStatus: result.exitStatus,
          stderr: stderr
        )
      }
      throw BobClientError.emptyStdout(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr
      )
    }

    do {
      let response = try decoder.decode(
        CapturePomodoroNameResponse.self, from: Data(trimmedStdout.utf8))
      if case .success(let success) = response, success.schemaVersion != 1 {
        throw BobClientError.schemaMismatch(
          command: result.command,
          expected: 1,
          actual: success.schemaVersion
        )
      }
      return response
    } catch let error as BobClientError {
      throw error
    } catch {
      if result.exitStatus != 0 {
        throw BobClientError.processFailed(
          command: result.command,
          exitStatus: result.exitStatus,
          stderr: stderr
        )
      }
      throw BobClientError.malformedJSON(
        command: result.command,
        exitStatus: result.exitStatus,
        stderr: stderr,
        reason: error.localizedDescription
      )
    }
  }

  private func nextGeneration(
    replacingWith process: Process,
    lane: String,
    cancelsPreviousInLane: Bool
  ) -> UInt64 {
    stateQueue.sync {
      activeGeneration += 1
      if cancelsPreviousInLane {
        if let active = activeProcesses[lane] {
          Self.terminateIfRunning(active.process)
        }
      }
      activeProcesses[lane] = ActiveProcess(
        generation: activeGeneration,
        process: process
      )
      return activeGeneration
    }
  }

  private func clearActiveProcess(process: Process, generation: UInt64, lane: String) {
    stateQueue.sync {
      clearActiveProcessAlreadyOnStateQueue(process: process, generation: generation, lane: lane)
    }
  }

  // The timeout `DispatchWorkItem` below is itself scheduled on `stateQueue`, so it
  // must mutate `activeProcesses` directly instead of calling `clearActiveProcess`:
  // a `stateQueue.sync` from a block already running on `stateQueue` is a same-queue
  // reentrant deadlock, not a re-entrant no-op.
  private func clearActiveProcessAlreadyOnStateQueue(
    process: Process, generation: UInt64, lane: String
  ) {
    if let active = activeProcesses[lane],
      active.process === process,
      active.generation == generation
    {
      activeProcesses[lane] = nil
    }
  }
}

private struct ActiveProcess {
  let generation: UInt64
  let process: Process
}

/// Concurrent stdout/stderr drain for one child process.
///
/// A pipe holds at most 64 KiB: a child writing more blocks in `write(2)` until
/// someone reads. `task_link` responses are hundreds of KiB, so both pipes must
/// drain on background readers while the child runs — never only after exit.
private final class ProcessOutputDrain: @unchecked Sendable {
  private let lock = NSLock()
  private var stdoutData = Data()
  private var stderrData = Data()
  private let group = DispatchGroup()
  private let stdoutHandle: FileHandle
  private let stderrHandle: FileHandle

  init(stdout: FileHandle, stderr: FileHandle) {
    stdoutHandle = stdout
    stderrHandle = stderr
    // Enter before launch so an instant exit cannot race ahead of the readers.
    group.enter()
    group.enter()
  }

  func start() {
    DispatchQueue.global(qos: .userInitiated).async { [self] in
      let data = stdoutHandle.readDataToEndOfFile()
      lock.lock()
      stdoutData = data
      lock.unlock()
      group.leave()
    }
    DispatchQueue.global(qos: .userInitiated).async { [self] in
      let data = stderrHandle.readDataToEndOfFile()
      lock.lock()
      stderrData = data
      lock.unlock()
      group.leave()
    }
  }

  func cancelForLaunchFailure() {
    group.leave()
    group.leave()
  }

  func notifyComplete(
    on queue: DispatchQueue, handler: @escaping @Sendable (String, String) -> Void
  ) {
    group.notify(queue: queue) { [self] in
      // Buffers are read only here, after both readers reached EOF.
      lock.lock()
      let stdout = stdoutData
      let stderr = stderrData
      lock.unlock()
      handler(
        String(data: stdout, encoding: .utf8) ?? "",
        String(data: stderr, encoding: .utf8) ?? ""
      )
    }
  }
}

private final class ResumeGuard: @unchecked Sendable {
  private let lock = NSLock()
  private var hasResumed = false

  func markResumed() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !hasResumed else { return false }
    hasResumed = true
    return true
  }
}

public protocol SchemaVersioned {
  var schemaVersion: Int { get }
}

extension CaptureParseResponse: SchemaVersioned {}
extension CaptureRewriteResponse: SchemaVersioned {}
extension CaptureTargetsResponse: SchemaVersioned {}
extension CaptureCompletionResponse: SchemaVersioned {}
extension CapturePomodorosResponse: SchemaVersioned {}
extension CaptureAgendaSnapshot: SchemaVersioned {}
