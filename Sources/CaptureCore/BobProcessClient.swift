@preconcurrency import Foundation

public struct BobProcessResult: Equatable {
    public let generation: UInt64
    public let command: [String]
    public let exitStatus: Int32
    public let stdout: String
    public let stderr: String
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

    public func captureParse(_ draft: String) async throws -> CaptureParseResponse {
        let response: CaptureParseResponse = try await decode(
            arguments: ["capture-parse", "--format", "json", "--", draft],
            expectedSchema: 1,
            lane: "parse"
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

    public func captureTargets() async throws -> CaptureTargetsResponse {
        let response: CaptureTargetsResponse = try await decode(
            arguments: ["capture-targets", "--format", "json"],
            expectedSchema: 1,
            lane: "targets"
        )
        return response
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
        priorityRollSeed: String? = nil
    ) async throws -> CaptureCommandResponse {
        var arguments = ["capture", "--format", "json"]
        if dryRun {
            arguments.append("--dry-run")
        }
        if !readClipboard {
            arguments.append("--no-clip")
        }
        arguments.append("--")
        arguments.append(draft)

        return try await decodeCaptureResult(
            arguments: arguments,
            environmentOverrides: priorityRollSeed.map { ["BOB_PRIORITY_ROLL_SEED": $0] } ?? [:],
            lane: dryRun ? "preview-explicit" : "submit"
        )
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

                // Runs on `stateQueue` (see `asyncAfter` below), so it must use the
                // already-on-the-queue clear helper, not the `.sync`-wrapping one.
                let timeoutWorkItem = DispatchWorkItem { [weak self] in
                    guard resumeGuard.markResumed() else { return }
                    Self.terminateIfRunning(process)
                    self?.clearActiveProcessAlreadyOnStateQueue(process: process, generation: generation, lane: lane)
                    continuation.resume(throwing: BobClientError.timedOut(command: command, seconds: timeout))
                }
                stateQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

                process.terminationHandler = { [weak self] completedProcess in
                    timeoutWorkItem.cancel()
                    guard resumeGuard.markResumed() else { return }

                    let stdout = String(
                        data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    let stderr = String(
                        data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""

                    self?.clearActiveProcess(
                        process: completedProcess,
                        generation: generation,
                        lane: lane
                    )
                    continuation.resume(
                        returning: BobProcessResult(
                            generation: generation,
                            command: command,
                            exitStatus: completedProcess.terminationStatus,
                            stdout: stdout,
                            stderr: stderr
                        )
                    )
                }

                do {
                    try process.run()
                } catch {
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

    public static func preconditionLivePreviewArguments(_ arguments: [String]) {
        precondition(arguments.first == "capture", "live preview must invoke bob capture")
        precondition(arguments.contains("--dry-run"), "live preview must be a dry run")
        precondition(arguments.contains("--no-clip"), "live preview must never read clipboard")
        precondition(arguments.contains("--format"), "live preview must request JSON")
    }

    private func decode<T: Decodable & SchemaVersioned>(
        arguments: [String],
        expectedSchema: Int,
        environmentOverrides: [String: String] = [:],
        lane: String = "default"
    ) async throws -> T {
        let result = try await run(
            arguments: arguments,
            environmentOverrides: environmentOverrides,
            lane: lane
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

    // `bob capture` has no schema_version and reports `ok: false` failures with a
    // non-zero exit but a fully valid JSON body, so it cannot use `decode(_:expectedSchema:)`:
    // that path treats any non-zero exit as a transport failure before looking at stdout,
    // which would discard the real, actionable `error` message bob already produced.
    private func decodeCaptureResult(
        arguments: [String],
        environmentOverrides: [String: String] = [:],
        lane: String = "default"
    ) async throws -> CaptureCommandResponse {
        let result = try await run(arguments: arguments, environmentOverrides: environmentOverrides, lane: lane)
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
    private func clearActiveProcessAlreadyOnStateQueue(process: Process, generation: UInt64, lane: String) {
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
extension CaptureTargetsResponse: SchemaVersioned {}
extension CaptureCompletionResponse: SchemaVersioned {}
