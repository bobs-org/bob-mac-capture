import XCTest

@testable import CaptureCore

final class BobMacCaptureLaunchContextTests: XCTestCase {
    private let process =
        "/Applications/Bob Mac Capture.app/Contents/MacOS/BobMacCapture"
    private let flag = BobMacCaptureLaunchContext.installRestartArgument

    func testInstallRestartArgumentIsRecognizedExactly() {
        XCTAssertTrue(
            BobMacCaptureLaunchContext.requestsInstallRestartNotification([
                process,
                flag,
            ])
        )
        XCTAssertTrue(
            BobMacCaptureLaunchContext.requestsInstallRestartNotification([flag])
        )
        XCTAssertTrue(
            BobMacCaptureLaunchContext.requestsInstallRestartNotification([
                process,
                "-NSDocumentRevisionsDebugMode",
                "YES",
                flag,
            ])
        )
    }

    func testUnrelatedPrefixSuffixEmptyAndOrdinaryArgumentsDoNotOptIn() {
        XCTAssertFalse(BobMacCaptureLaunchContext.requestsInstallRestartNotification([]))
        XCTAssertFalse(BobMacCaptureLaunchContext.requestsInstallRestartNotification([""]))
        XCTAssertFalse(BobMacCaptureLaunchContext.requestsInstallRestartNotification([process]))
        XCTAssertFalse(
            BobMacCaptureLaunchContext.requestsInstallRestartNotification([process, ""])
        )
        XCTAssertFalse(
            BobMacCaptureLaunchContext.requestsInstallRestartNotification([
                process,
                flag + "-extra",
            ])
        )
        XCTAssertFalse(
            BobMacCaptureLaunchContext.requestsInstallRestartNotification([
                process,
                "prefix" + flag,
            ])
        )
        XCTAssertFalse(
            BobMacCaptureLaunchContext.requestsInstallRestartNotification([flag + flag])
        )
        XCTAssertFalse(
            BobMacCaptureLaunchContext.requestsInstallRestartNotification([" " + flag])
        )
        XCTAssertFalse(
            BobMacCaptureLaunchContext.requestsInstallRestartNotification([
                process,
                flag.uppercased(),
            ])
        )
        XCTAssertFalse(
            BobMacCaptureLaunchContext.requestsInstallRestartNotification([
                process,
                "-NSDocumentRevisionsDebugMode",
                "YES",
            ])
        )
        XCTAssertFalse(
            BobMacCaptureLaunchContext.requestsInstallRestartNotification([process, "--help"])
        )
    }
}
