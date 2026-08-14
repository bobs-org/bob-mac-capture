@preconcurrency import Foundation

public struct BobProcessResult: Equatable {
    public let generation: UInt64
    public let command: [String]
    public let exitStatus: Int32
    public let stdout: String
    public let stderr: String
}

public final class BobProcessClient: @unchecked Sendable {
    private let executablePath: String
    private let environment: [String: String]
    private let decoder: JSONDecoder
    private let stateQueue = DispatchQueue(label: "org.bobs.bob-mac-capture.process-client")
    private var activeProcess: Process?
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
            expectedSchema: 1
        )
        return response
    }

    public func captureTargets() async throws -> CaptureTargetsResponse {
        let response: CaptureTargetsResponse = try await decode(
            arguments: ["capture-targets", "--format", "json"],
            expectedSchema: 1
        )
        return response
    }

    public func capture(
        _ draft: String,
        dryRun: Bool = false,
        readClipboard: Bool = true,
        openAfterCapture: Bool = false
    ) async throws -> CaptureCommandResponse {
        var arguments = ["capture", "--format", "json"]
        if dryRun {
            arguments.append("--dry-run")
        }
        if !readClipboard {
            arguments.append("--no-clip")
        }
        if openAfterCapture {
            arguments.append("--open")
        }
        arguments.append("--")
        arguments.append(draft)

        let response: CaptureCommandResponse = try await decode(
            arguments: arguments,
            expectedSchema: 1
        )
        return response
    }

    public func run(arguments: [String]) async throws -> BobProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let command = [executablePath] + arguments
        let generation = nextGeneration(replacingWith: process)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak self] completedProcess in
                    let stdout = String(
                        data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    let stderr = String(
                        data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""

                    self?.clearActiveProcess(process: completedProcess, generation: generation)
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
                    clearActiveProcess(process: process, generation: generation)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    public func cancelActiveProcess() {
        stateQueue.sync {
            activeProcess?.terminate()
            activeProcess = nil
        }
    }

    private func decode<T: Decodable & SchemaVersioned>(
        arguments: [String],
        expectedSchema: Int
    ) async throws -> T {
        let result = try await run(arguments: arguments)
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

    private func nextGeneration(replacingWith process: Process) -> UInt64 {
        stateQueue.sync {
            activeGeneration += 1
            activeProcess?.terminate()
            activeProcess = process
            return activeGeneration
        }
    }

    private func clearActiveProcess(process: Process, generation: UInt64) {
        stateQueue.sync {
            if activeProcess === process, activeGeneration == generation {
                activeProcess = nil
            }
        }
    }
}

public protocol SchemaVersioned {
    var schemaVersion: Int { get }
}

extension CaptureParseResponse: SchemaVersioned {}
extension CaptureCommandResponse: SchemaVersioned {}
extension CaptureTargetsResponse: SchemaVersioned {}
