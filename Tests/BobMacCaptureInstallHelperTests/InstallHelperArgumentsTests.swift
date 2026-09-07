import XCTest

@testable import BobMacCaptureInstallHelper

final class InstallHelperArgumentsTests: XCTestCase {
    func testParseDiscoverRequiresExactlyOnePath() throws {
        XCTAssertEqual(
            try InstallHelperArguments.parse(["discover", "/Applications/Bob Mac Capture.app"]),
            .discover(installPath: "/Applications/Bob Mac Capture.app")
        )
        XCTAssertThrowsError(try InstallHelperArguments.parse(["discover"])) { error in
            XCTAssertEqual(
                error as? InstallHelperError,
                .invalidArguments("discover requires exactly one install path.")
            )
        }
        XCTAssertThrowsError(
            try InstallHelperArguments.parse([
                "discover",
                "/Applications/Bob Mac Capture.app",
                "extra",
            ])
        )
    }

    func testParseRestartKeepsAQuotedPathAsOneArgument() throws {
        let bundlePath = "/tmp/Weird \"Bob\" Path/Bob Mac Capture.app"
        let command = try InstallHelperArguments.parse(["restart", bundlePath, "99"])

        XCTAssertEqual(
            command,
            .restart(installPath: bundlePath, pids: [99])
        )
    }

    func testParseRestartAcceptsZeroOrMorePIDs() throws {
        XCTAssertEqual(
            try InstallHelperArguments.parse(["restart", "/Applications/Bob Mac Capture.app"]),
            .restart(installPath: "/Applications/Bob Mac Capture.app", pids: [])
        )
        XCTAssertEqual(
            try InstallHelperArguments.parse([
                "restart",
                "/Applications/Bob Mac Capture.app",
                "12",
                "15",
            ]),
            .restart(installPath: "/Applications/Bob Mac Capture.app", pids: [12, 15])
        )
    }

    func testParseRejectsMalformedPIDs() {
        let malformed = ["", "abc", "0", "-1", "01", "+12", "1.5", "0x10", "12abc"]
        for raw in malformed {
            XCTAssertThrowsError(
                try InstallHelperArguments.parse([
                    "restart",
                    "/Applications/Bob Mac Capture.app",
                    raw,
                ]),
                "expected \(raw) to be rejected"
            ) { error in
                XCTAssertEqual(error as? InstallHelperError, .malformedPID(raw))
            }
        }
    }

    func testParseHelpAndUnknownCommands() throws {
        XCTAssertEqual(try InstallHelperArguments.parse(["-h"]), .help)
        XCTAssertEqual(try InstallHelperArguments.parse(["--help"]), .help)
        XCTAssertThrowsError(try InstallHelperArguments.parse([]))
        XCTAssertThrowsError(try InstallHelperArguments.parse(["relaunch"])) { error in
            XCTAssertEqual(
                error as? InstallHelperError,
                .invalidArguments("Unknown command: relaunch")
            )
        }
        XCTAssertThrowsError(try InstallHelperArguments.parse(["restart"])) { error in
            XCTAssertEqual(
                error as? InstallHelperError,
                .invalidArguments("restart requires an install path.")
            )
        }
    }
}
