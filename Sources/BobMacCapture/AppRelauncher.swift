import AppKit

// Quits the running process and hands off to a detached shell helper that waits for
// this process to exit, then re-launches the installed bundle. The helper must be a
// separate process because the process doing the waiting cannot be the process that is
// exiting, and it must wait rather than launch immediately because LaunchServices
// dedupes by bundle identifier: launching while the old instance still owns the Carbon
// hotkey just activates that instance instead of starting a fresh one.
@MainActor
struct AppRelauncher {
    var bundleURL: URL = Bundle.main.bundleURL
    var processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    var fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    var spawn: (String, [String]) throws -> Void = { executablePath, arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
    var terminate: () -> Void = { NSApp.terminate(nil) }

    // Every failure throws before anything terminates, so a refusal always leaves the
    // app running rather than quitting into nothing.
    func restart() throws {
        let bundlePath = bundleURL.path
        guard bundleURL.pathExtension == "app" else {
            throw AppRelaunchError.notBundled(path: bundlePath)
        }
        guard fileExists(bundlePath) else {
            throw AppRelaunchError.bundleMissing(path: bundlePath)
        }
        do {
            try spawn(
                "/bin/sh",
                Self.relaunchArguments(processIdentifier: processIdentifier, bundlePath: bundlePath)
            )
        } catch {
            throw AppRelaunchError.spawnFailed(String(describing: error))
        }
        terminate()
    }

    static func relaunchArguments(processIdentifier: Int32, bundlePath: String) -> [String] {
        // "bob-mac-capture-relaunch" becomes the script's $0; the PID and bundle path
        // that follow become $1/$2. They are positional parameters, never interpolated
        // into the script text below, so a bundle path containing spaces or quotes (as
        // "Bob Mac Capture.app" does) cannot break shell quoting.
        ["-c", script, "bob-mac-capture-relaunch", String(processIdentifier), bundlePath]
    }

    private static let script = """
        n=0
        # Bounded to roughly ten seconds so a cancelled termination cannot leave an
        # immortal poller behind. If the app is somehow still alive when this loop gives
        # up, `open` below just activates the existing instance, which is harmless.
        while [ "$n" -lt 100 ] && kill -0 "$1" 2>/dev/null; do
          /bin/sleep 0.1
          n=$((n + 1))
        done
        i=0
        # Retries cover a Restart clicked during the brief window in which install.sh
        # has renamed the old bundle away and not yet moved the new one into place.
        while [ "$i" -lt 3 ]; do
          /usr/bin/open "$2" && exit 0
          /bin/sleep 1
          i=$((i + 1))
        done
        exit 1
        """
}

enum AppRelaunchError: Error, Equatable {
    case notBundled(path: String)
    case bundleMissing(path: String)
    case spawnFailed(String)

    var message: String {
        switch self {
        case .notBundled(let path):
            return "Not running from an installed app bundle: \(path)"
        case .bundleMissing(let path):
            return "Installed app bundle not found: \(path)"
        case .spawnFailed(let reason):
            return "Could not start the relaunch helper: \(reason)"
        }
    }
}
