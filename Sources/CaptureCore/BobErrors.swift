import Foundation

public enum BobClientError: Error, Equatable, CustomStringConvertible {
    case executableOverrideNotAbsolute(String)
    case executableNotFound([String])
    case executableNotRunnable(String)
    case emptyStdout(command: [String], exitStatus: Int32, stderr: String)
    case malformedJSON(command: [String], exitStatus: Int32, stderr: String, reason: String)
    case schemaMismatch(command: [String], expected: Int, actual: Int)
    case processFailed(command: [String], exitStatus: Int32, stderr: String)
    case timedOut(command: [String], seconds: TimeInterval)

    public var description: String {
        switch self {
        case .executableOverrideNotAbsolute(let path):
            return "Configured bob executable must be an absolute path: \(path)"
        case .executableNotFound(let candidates):
            return "Unable to find an executable bob. Checked: \(candidates.joined(separator: ", "))"
        case .executableNotRunnable(let path):
            return "Configured bob executable is not executable: \(path)"
        case .emptyStdout(let command, let exitStatus, let stderr):
            return "bob command produced empty stdout (exit \(exitStatus)): \(commandLine(command)). \(stderr)"
        case .malformedJSON(let command, let exitStatus, let stderr, let reason):
            return "bob command produced malformed JSON (exit \(exitStatus)): \(commandLine(command)). \(reason). \(stderr)"
        case .schemaMismatch(let command, let expected, let actual):
            return "Unsupported bob JSON schema for \(commandLine(command)): expected \(expected), got \(actual)"
        case .processFailed(let command, let exitStatus, let stderr):
            return "bob command failed (exit \(exitStatus)): \(commandLine(command)). \(stderr)"
        case .timedOut(let command, let seconds):
            return "bob command timed out after \(Int(seconds))s and was terminated: \(commandLine(command))"
        }
    }

    private func commandLine(_ command: [String]) -> String {
        var redacted: [String] = []
        var shouldRedactNextArgument = false

        for argument in command {
            if shouldRedactNextArgument {
                redacted.append("<capture-text>")
                break
            }

            redacted.append(argument)
            if argument == "--" {
                shouldRedactNextArgument = true
            }
        }

        return redacted.joined(separator: " ")
    }
}

public func boundedProcessText(_ text: String, limit: Int = 4096) -> String {
    guard text.utf8.count > limit else {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var bytes = Array(text.utf8.prefix(limit))
    while String(bytes: bytes, encoding: .utf8) == nil, !bytes.isEmpty {
        bytes.removeLast()
    }

    let prefix = String(bytes: bytes, encoding: .utf8) ?? ""
    return prefix.trimmingCharacters(in: .whitespacesAndNewlines) + "..."
}
