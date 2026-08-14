import XCTest

@testable import BobMacCapture

@MainActor
final class AppRelauncherTests: XCTestCase {
    func testRestartSpawnsTheWaiterBeforeTerminating() throws {
        var callOrder: [String] = []
        var spawnedPath: String?
        var spawnedArguments: [String]?

        var relauncher = AppRelauncher(
            bundleURL: URL(fileURLWithPath: "/Applications/Bob Mac Capture.app"),
            processIdentifier: 4242,
            fileExists: { _ in true },
            spawn: { path, arguments in
                spawnedPath = path
                spawnedArguments = arguments
                callOrder.append("spawn")
            },
            terminate: {
                callOrder.append("terminate")
            }
        )

        try relauncher.restart()

        XCTAssertEqual(callOrder, ["spawn", "terminate"])
        XCTAssertEqual(spawnedPath, "/bin/sh")
        let arguments = try XCTUnwrap(spawnedArguments)
        XCTAssertEqual(arguments[0], "-c")
        XCTAssertTrue(arguments.contains("4242"))
        XCTAssertTrue(arguments.contains("/Applications/Bob Mac Capture.app"))
    }

    func testRestartRefusesWhenNotRunningFromAnAppBundle() {
        var spawnCalled = false
        var terminateCalled = false
        let relauncher = AppRelauncher(
            bundleURL: URL(fileURLWithPath: "/path/to/.build/debug/BobMacCapture"),
            fileExists: { _ in true },
            spawn: { _, _ in spawnCalled = true },
            terminate: { terminateCalled = true }
        )

        XCTAssertThrowsError(try relauncher.restart()) { error in
            XCTAssertEqual(
                error as? AppRelaunchError,
                .notBundled(path: "/path/to/.build/debug/BobMacCapture")
            )
        }
        XCTAssertFalse(spawnCalled)
        XCTAssertFalse(terminateCalled)
    }

    func testRestartRefusesWhenTheInstalledBundleIsMissing() {
        var terminateCalled = false
        let relauncher = AppRelauncher(
            bundleURL: URL(fileURLWithPath: "/Applications/Bob Mac Capture.app"),
            fileExists: { _ in false },
            spawn: { _, _ in XCTFail("spawn must not be called when the bundle is missing") },
            terminate: { terminateCalled = true }
        )

        XCTAssertThrowsError(try relauncher.restart()) { error in
            XCTAssertEqual(
                error as? AppRelaunchError,
                .bundleMissing(path: "/Applications/Bob Mac Capture.app")
            )
        }
        XCTAssertFalse(terminateCalled)
    }

    func testRestartDoesNotTerminateWhenTheHelperFailsToSpawn() {
        struct SpawnFailure: Error {}
        var terminateCalled = false
        let relauncher = AppRelauncher(
            bundleURL: URL(fileURLWithPath: "/Applications/Bob Mac Capture.app"),
            fileExists: { _ in true },
            spawn: { _, _ in throw SpawnFailure() },
            terminate: { terminateCalled = true }
        )

        XCTAssertThrowsError(try relauncher.restart())
        XCTAssertFalse(terminateCalled)
    }

    func testRelaunchArgumentsNeverInterpolateThePathIntoTheScript() {
        let bundlePath = "/Applications/Weird \"Bob\" Path.app"

        let arguments = AppRelauncher.relaunchArguments(processIdentifier: 99, bundlePath: bundlePath)

        XCTAssertEqual(arguments[0], "-c")
        let script = arguments[1]
        XCTAssertFalse(script.contains(bundlePath))
        XCTAssertTrue(arguments.contains(bundlePath))
        XCTAssertTrue(arguments.contains("99"))
    }
}
