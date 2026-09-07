import AppKit
import CaptureCore

struct RunningApplicationRecord: Equatable {
    var processIdentifier: pid_t
    var bundleIdentifier: String?
    var bundleURL: URL?
}

extension RunningApplicationRecord {
    init(_ application: NSRunningApplication) {
        self.processIdentifier = application.processIdentifier
        self.bundleIdentifier = application.bundleIdentifier
        self.bundleURL = application.bundleURL
    }
}

// Mirrors AppRelauncher's lifecycle ordering from outside the outgoing process:
// discover the installed copy, ask it to terminate normally, wait until those PIDs
// exit, then open the replacement once. Launching before the old PID exits lets
// LaunchServices reactivate it and leaves the Carbon hotkey on the wrong instance;
// `open -n` would overlap two copies and conflict the hotkey.
struct InstallRelauncher {
    static let bundleIdentifier = "org.bobs.bob-mac-capture"
    // Same ~10s bound as AppRelauncher's waiter (100 × 0.1s).
    static let exitWaitAttempts = 100
    static let exitWaitInterval: TimeInterval = 0.1
    // Same three tries as AppRelauncher, with a one-second pause between failures.
    static let openAttempts = 3
    static let openRetryInterval: TimeInterval = 1

    var runningApplications: (String) -> [RunningApplicationRecord] = { bundleIdentifier in
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .map(RunningApplicationRecord.init)
    }
    var applicationForPID: (pid_t) -> RunningApplicationRecord? = { processIdentifier in
        NSRunningApplication(processIdentifier: processIdentifier).map(RunningApplicationRecord.init)
    }
    var terminate: (pid_t) -> Bool = { processIdentifier in
        guard let application = NSRunningApplication(processIdentifier: processIdentifier) else {
            return true
        }
        return application.terminate()
    }
    var isTerminated: (pid_t) -> Bool = { processIdentifier in
        guard let application = NSRunningApplication(processIdentifier: processIdentifier) else {
            return true
        }
        return application.isTerminated
    }
    var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    var open: (String, [String]) throws -> Void = { bundlePath, applicationArguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = InstallRelauncher.openArguments(
            bundlePath: bundlePath,
            applicationArguments: applicationArguments
        )
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallHelperError.openFailed("open exited \(process.terminationStatus)")
        }
    }

    // `/usr/bin/open <bundle> --args <tokens...>` keeps the bundle path, the `--args`
    // flag, and each application argument as distinct Process tokens. `--args` is an
    // `open` switch, not something interpolated into the bundle path.
    static func openArguments(bundlePath: String, applicationArguments: [String]) -> [String] {
        var arguments = [bundlePath]
        if !applicationArguments.isEmpty {
            arguments.append("--args")
            arguments.append(contentsOf: applicationArguments)
        }
        return arguments
    }

    static func normalizedPath(_ path: String) -> String {
        normalizedPath(URL(fileURLWithPath: path))
    }

    static func normalizedPath(_ url: URL) -> String {
        strippingPrivatePrefix(url.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    // resolvingSymlinksInPath only walks existing components, so /var and
    // /private/var miss each other unless the well-known /private prefixes fold.
    private static func strippingPrivatePrefix(_ path: String) -> String {
        for root in ["var", "tmp", "etc"] {
            let privateRoot = "/private/\(root)"
            if path == privateRoot {
                return "/\(root)"
            }
            let prefix = privateRoot + "/"
            if path.hasPrefix(prefix) {
                return "/\(root)/" + path.dropFirst(prefix.count)
            }
        }
        return path
    }

    func discover(installPath: String) -> [pid_t] {
        let targetPath = Self.normalizedPath(installPath)
        return runningApplications(Self.bundleIdentifier)
            .filter { record in
                guard record.bundleIdentifier == Self.bundleIdentifier else {
                    return false
                }
                guard let bundleURL = record.bundleURL else {
                    return false
                }
                return Self.normalizedPath(bundleURL) == targetPath
            }
            .map(\.processIdentifier)
            .sorted()
    }

    func restart(installPath: String, pids: [pid_t]) throws {
        let uniquePIDs = Array(Set(pids)).sorted()
        let live = uniquePIDs.compactMap { processIdentifier -> RunningApplicationRecord? in
            guard let record = applicationForPID(processIdentifier) else {
                return nil
            }
            guard record.bundleIdentifier == Self.bundleIdentifier else {
                return nil
            }
            return record
        }

        guard !live.isEmpty else {
            return
        }

        var refused: [pid_t] = []
        for record in live {
            if !terminate(record.processIdentifier) {
                refused.append(record.processIdentifier)
            }
        }
        if !refused.isEmpty {
            throw InstallHelperError.terminateRefused(refused)
        }

        var remaining = live.map(\.processIdentifier)
        var attempts = 0
        while attempts < Self.exitWaitAttempts {
            remaining = remaining.filter { !isTerminated($0) }
            if remaining.isEmpty {
                break
            }
            sleep(Self.exitWaitInterval)
            attempts += 1
        }
        remaining = remaining.filter { !isTerminated($0) }
        if !remaining.isEmpty {
            throw InstallHelperError.exitTimeout(remaining)
        }

        try openInstalledBundle(installPath)
    }

    private func openInstalledBundle(_ bundlePath: String) throws {
        let applicationArguments = [BobMacCaptureLaunchContext.installRestartArgument]
        var lastFailure = "open failed"
        for attempt in 1...Self.openAttempts {
            do {
                try open(bundlePath, applicationArguments)
                return
            } catch {
                switch error as? InstallHelperError {
                case .openFailed(let reason):
                    lastFailure = reason
                default:
                    lastFailure = String(describing: error)
                }
                if attempt < Self.openAttempts {
                    sleep(Self.openRetryInterval)
                }
            }
        }
        throw InstallHelperError.openFailed(lastFailure)
    }
}
