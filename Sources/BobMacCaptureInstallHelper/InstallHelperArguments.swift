import Foundation

enum InstallHelperCommand: Equatable {
    case help
    case discover(installPath: String)
    case restart(installPath: String, pids: [pid_t])
}

enum InstallHelperArguments {
    static let usage = """
        Usage: BobMacCaptureInstallHelper discover <install-path>
               BobMacCaptureInstallHelper restart <install-path> [pid ...]
               BobMacCaptureInstallHelper -h|--help

        discover writes decimal PIDs of running Bob Mac Capture instances whose
        launch-time bundle path equals <install-path>, one PID per line.

        restart asks those still-live PIDs to terminate, waits for them to exit,
        then opens the installed bundle once. With no PIDs, or if every PID has
        already exited, restart succeeds without launching.

        Paths and PIDs are discrete arguments and are never interpolated into a
        shell command. stdout is reserved for discover PIDs.
        """

    static func parse(_ arguments: [String]) throws -> InstallHelperCommand {
        guard let command = arguments.first else {
            throw InstallHelperError.invalidArguments("Missing command.")
        }
        switch command {
        case "-h", "--help":
            return .help
        case "discover":
            guard arguments.count == 2 else {
                throw InstallHelperError.invalidArguments(
                    "discover requires exactly one install path."
                )
            }
            return .discover(installPath: arguments[1])
        case "restart":
            guard arguments.count >= 2 else {
                throw InstallHelperError.invalidArguments(
                    "restart requires an install path."
                )
            }
            let pids = try arguments.dropFirst(2).map(parsePID)
            return .restart(installPath: arguments[1], pids: pids)
        default:
            throw InstallHelperError.invalidArguments("Unknown command: \(command)")
        }
    }

    static func parsePID(_ raw: String) throws -> pid_t {
        guard let value = pid_t(raw), value > 0, String(value) == raw else {
            throw InstallHelperError.malformedPID(raw)
        }
        return value
    }
}
