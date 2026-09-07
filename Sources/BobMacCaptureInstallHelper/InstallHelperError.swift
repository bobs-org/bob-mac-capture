import Foundation

enum InstallHelperError: Error, Equatable {
    case invalidArguments(String)
    case malformedPID(String)
    case terminateRefused([pid_t])
    case exitTimeout([pid_t])
    case openFailed(String)

    var exitStatus: Int32 {
        switch self {
        case .invalidArguments, .malformedPID:
            return 64
        case .terminateRefused, .exitTimeout, .openFailed:
            return 70
        }
    }

    var message: String {
        switch self {
        case .invalidArguments(let reason):
            return "\(reason)\n\(InstallHelperArguments.usage)"
        case .malformedPID(let raw):
            return "Malformed PID: \(raw)"
        case .terminateRefused(let pids):
            return "Refused to terminate Bob Mac Capture PID \(Self.list(pids))"
        case .exitTimeout(let pids):
            return "Timed out waiting for Bob Mac Capture PID \(Self.list(pids)) to exit"
        case .openFailed(let reason):
            return "Failed to open the installed bundle: \(reason)"
        }
    }

    private static func list(_ pids: [pid_t]) -> String {
        pids.map(String.init).joined(separator: ", ")
    }
}
