import CaptureCore
import XCTest

@testable import BobMacCaptureInstallHelper

private let applicationsPath = "/Applications/Bob Mac Capture.app"
private let homeApplicationsPath = "/Users/test/Applications/Bob Mac Capture.app"
private let rawExecutablePath = "/Users/test/bob-mac-capture/.build/debug/BobMacCapture"

private func applicationRecord(
    pid: pid_t,
    path: String,
    bundleIdentifier: String = InstallRelauncher.bundleIdentifier
) -> RunningApplicationRecord {
    RunningApplicationRecord(
        processIdentifier: pid,
        bundleIdentifier: bundleIdentifier,
        bundleURL: URL(fileURLWithPath: path)
    )
}

final class InstallRelauncherTests: XCTestCase {
    func testNormalizedPathsTreatSymlinkPrefixesAndTrailingSlashesAsEqual() {
        XCTAssertEqual(
            InstallRelauncher.normalizedPath(applicationsPath),
            InstallRelauncher.normalizedPath(applicationsPath + "/")
        )
        XCTAssertEqual(
            InstallRelauncher.normalizedPath("/var/folders/xx/T/Bob Mac Capture.app"),
            InstallRelauncher.normalizedPath("/private/var/folders/xx/T/Bob Mac Capture.app")
        )
    }

    func testDiscoverSelectsTheExactInstalledBundleAndIgnoresOthers() {
        let matching = applicationRecord(
            pid: 11,
            path: applicationsPath
        )
        let otherInstall = applicationRecord(
            pid: 12,
            path: homeApplicationsPath
        )
        let rawExecutable = applicationRecord(
            pid: 13,
            path: rawExecutablePath
        )
        let missingURL = RunningApplicationRecord(
            processIdentifier: 14,
            bundleIdentifier: InstallRelauncher.bundleIdentifier,
            bundleURL: nil
        )
        let unrelated = applicationRecord(
            pid: 15,
            path: applicationsPath,
            bundleIdentifier: "com.apple.Safari"
        )
        let trailingSlashMatch = applicationRecord(
            pid: 16,
            path: applicationsPath + "/"
        )

        let relauncher = InstallRelauncher(
            runningApplications: { bundleIdentifier in
                XCTAssertEqual(bundleIdentifier, InstallRelauncher.bundleIdentifier)
                return [
                    matching,
                    otherInstall,
                    rawExecutable,
                    missingURL,
                    unrelated,
                    trailingSlashMatch,
                ]
            },
            terminate: { _ in
                XCTFail("discover must not terminate")
                return false
            },
            open: { _, _ in
                XCTFail("discover must not open")
            }
        )

        XCTAssertEqual(relauncher.discover(installPath: applicationsPath), [11, 16])
        XCTAssertEqual(relauncher.discover(installPath: homeApplicationsPath), [12])
        XCTAssertEqual(relauncher.discover(installPath: rawExecutablePath), [13])
    }

    func testDiscoverMatchesVarAndPrivateVarBundleSpellings() {
        let relauncher = InstallRelauncher(
            runningApplications: { _ in
                [
                    applicationRecord(
                        pid: 77,
                        path: "/private/var/folders/xx/T/Bob Mac Capture.app"
                    )
                ]
            },
            terminate: { _ in
                XCTFail("discover must not terminate")
                return false
            },
            open: { _, _ in
                XCTFail("discover must not open")
            }
        )

        XCTAssertEqual(
            relauncher.discover(installPath: "/var/folders/xx/T/Bob Mac Capture.app"),
            [77]
        )
    }

    func testRestartWithEmptySnapshotOrExitedPIDsIsANoOp() throws {
        var terminateCalled = false
        var openCalled = false
        let relauncher = InstallRelauncher(
            applicationForPID: { _ in nil },
            terminate: { _ in
                terminateCalled = true
                return false
            },
            open: { _, _ in
                openCalled = true
            }
        )

        try relauncher.restart(installPath: applicationsPath, pids: [])
        try relauncher.restart(installPath: applicationsPath, pids: [4242, 4243])

        XCTAssertFalse(terminateCalled)
        XCTAssertFalse(openCalled)
    }

    func testRestartTerminatesEveryLivePIDThenOpensOnce() throws {
        var events: [String] = []
        var live: Set<pid_t> = [21, 22]
        let records: [pid_t: RunningApplicationRecord] = [
            21: applicationRecord(pid: 21, path: applicationsPath),
            22: applicationRecord(pid: 22, path: applicationsPath),
        ]
        let relauncher = InstallRelauncher(
            applicationForPID: { records[$0] },
            terminate: { pid in
                events.append("terminate \(pid)")
                live.remove(pid)
                return true
            },
            isTerminated: { pid in
                !live.contains(pid)
            },
            sleep: { _ in
                XCTFail("must not wait when terminate already emptied the snapshot")
            },
            open: { path, applicationArguments in
                XCTAssertTrue(live.isEmpty, "open must wait until every PID has exited")
                events.append("open")
                XCTAssertEqual(path, applicationsPath)
                XCTAssertEqual(
                    applicationArguments,
                    [BobMacCaptureLaunchContext.installRestartArgument]
                )
            }
        )

        try relauncher.restart(installPath: applicationsPath, pids: [21, 22])

        XCTAssertEqual(events, ["terminate 21", "terminate 22", "open"])
    }

    func testRestartIgnoresAReusedPIDWithADifferentBundleIdentifier() throws {
        var terminateCalled = false
        var openCalled = false
        let relauncher = InstallRelauncher(
            applicationForPID: { pid in
                applicationRecord(
                    pid: pid,
                    path: "/Applications/Safari.app",
                    bundleIdentifier: "com.apple.Safari"
                )
            },
            terminate: { _ in
                terminateCalled = true
                return false
            },
            open: { _, _ in
                openCalled = true
            }
        )

        try relauncher.restart(installPath: applicationsPath, pids: [99])

        XCTAssertFalse(terminateCalled)
        XCTAssertFalse(openCalled)
    }

    func testRestartFailsWhenTerminateIsRefusedWithoutOpening() {
        var opened = false
        let relauncher = InstallRelauncher(
            applicationForPID: { pid in applicationRecord(pid: pid, path: applicationsPath) },
            terminate: { _ in false },
            isTerminated: { _ in
                XCTFail("must not wait after a refused terminate")
                return false
            },
            open: { _, _ in
                opened = true
            }
        )

        XCTAssertThrowsError(
            try relauncher.restart(installPath: applicationsPath, pids: [31])
        ) { error in
            XCTAssertEqual(error as? InstallHelperError, .terminateRefused([31]))
        }
        XCTAssertFalse(opened)
    }

    func testRestartFailsOnExitTimeoutWithoutOpening() {
        var openCount = 0
        var sleepCount = 0
        let relauncher = InstallRelauncher(
            applicationForPID: { pid in applicationRecord(pid: pid, path: applicationsPath) },
            terminate: { _ in true },
            isTerminated: { _ in false },
            sleep: { interval in
                XCTAssertEqual(interval, InstallRelauncher.exitWaitInterval)
                sleepCount += 1
            },
            open: { _, _ in
                openCount += 1
            }
        )

        XCTAssertThrowsError(
            try relauncher.restart(installPath: applicationsPath, pids: [41])
        ) { error in
            XCTAssertEqual(error as? InstallHelperError, .exitTimeout([41]))
        }
        XCTAssertEqual(sleepCount, InstallRelauncher.exitWaitAttempts)
        XCTAssertEqual(openCount, 0)
    }

    func testRestartRetriesOpenAndFailsWithoutLaunchingEarly() {
        var events: [String] = []
        var live: Set<pid_t> = [51]
        var openCount = 0
        let relauncher = InstallRelauncher(
            applicationForPID: { pid in applicationRecord(pid: pid, path: applicationsPath) },
            terminate: { pid in
                events.append("terminate")
                live.remove(pid)
                return true
            },
            isTerminated: { pid in
                !live.contains(pid)
            },
            sleep: { interval in
                XCTAssertEqual(interval, InstallRelauncher.openRetryInterval)
                events.append("sleep")
            },
            open: { path, applicationArguments in
                XCTAssertTrue(live.isEmpty)
                XCTAssertEqual(path, "/tmp/Weird \"Bob\" Path/Bob Mac Capture.app")
                XCTAssertEqual(
                    applicationArguments,
                    [BobMacCaptureLaunchContext.installRestartArgument]
                )
                openCount += 1
                events.append("open")
                throw InstallHelperError.openFailed("open exited 1")
            }
        )

        XCTAssertThrowsError(
            try relauncher.restart(
                installPath: "/tmp/Weird \"Bob\" Path/Bob Mac Capture.app",
                pids: [51]
            )
        ) { error in
            XCTAssertEqual(
                error as? InstallHelperError,
                .openFailed("open exited 1")
            )
        }
        XCTAssertEqual(openCount, InstallRelauncher.openAttempts)
        XCTAssertEqual(events, ["terminate", "open", "sleep", "open", "sleep", "open"])
    }

    func testRestartWaitsUntilEveryPIDHasExitedBeforeOpening() throws {
        var events: [String] = []
        var live: Set<pid_t> = [61, 62]
        var polls = 0
        let relauncher = InstallRelauncher(
            applicationForPID: { pid in applicationRecord(pid: pid, path: applicationsPath) },
            terminate: { pid in
                events.append("terminate \(pid)")
                return true
            },
            isTerminated: { pid in
                polls += 1
                if polls >= 3 {
                    live.removeAll()
                }
                return !live.contains(pid)
            },
            sleep: { _ in
                events.append("sleep")
            },
            open: { path, applicationArguments in
                XCTAssertTrue(live.isEmpty)
                XCTAssertEqual(path, applicationsPath)
                XCTAssertEqual(
                    applicationArguments,
                    [BobMacCaptureLaunchContext.installRestartArgument]
                )
                events.append("open")
            }
        )

        try relauncher.restart(installPath: applicationsPath, pids: [61, 62])

        XCTAssertEqual(events, ["terminate 61", "terminate 62", "sleep", "open"])
    }

    func testOpenArgumentsKeepsPathArgsFlagAndSignalAsDistinctTokens() {
        XCTAssertEqual(
            InstallRelauncher.openArguments(
                bundlePath: applicationsPath,
                applicationArguments: [BobMacCaptureLaunchContext.installRestartArgument]
            ),
            [
                applicationsPath,
                "--args",
                BobMacCaptureLaunchContext.installRestartArgument,
            ]
        )
        XCTAssertEqual(
            InstallRelauncher.openArguments(
                bundlePath: "/tmp/Weird \"Bob\" Path/Bob Mac Capture.app",
                applicationArguments: [BobMacCaptureLaunchContext.installRestartArgument]
            ),
            [
                "/tmp/Weird \"Bob\" Path/Bob Mac Capture.app",
                "--args",
                BobMacCaptureLaunchContext.installRestartArgument,
            ]
        )
        XCTAssertEqual(
            InstallRelauncher.openArguments(
                bundlePath: applicationsPath,
                applicationArguments: []
            ),
            [applicationsPath]
        )
    }
}
