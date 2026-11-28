import AppKit
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class SnoozeWakeAcceptanceProbeTests: XCTestCase {
    private final class FakeHost: SnoozeWakeAcceptanceProbeHost {
        var lastCommand: String?
        var lastArgs: [String] = []
        var result: [String: Any] = ["hud": ["visible": false]]

        func probeHandle(command: String, args: [String]) async throws -> [String: Any] {
            lastCommand = command
            lastArgs = args
            if command == "boom" {
                throw ProbeCommandError("boom")
            }
            return result
        }
    }

    private func defaults(probeEnabled: Bool) -> (UserDefaults, String) {
        let suite = "org.bobs.bob-mac-capture.probe-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if probeEnabled {
            defaults.set(true, forKey: SnoozeWakeAcceptanceProbe.defaultsKey)
        }
        return (defaults, suite)
    }

    func testProductionIdentityNeverEnablesTheProbe() {
        let (defaults, _) = defaults(probeEnabled: true)
        XCTAssertFalse(
            SnoozeWakeAcceptanceProbe.isEnabled(
                bundleIdentifier: "org.bobs.bob-mac-capture",
                defaults: defaults
            )
        )
        XCTAssertFalse(
            SnoozeWakeAcceptanceProbe.isEnabled(
                bundleIdentifier: "org.bobs.bob-mac-capture.beta",
                defaults: defaults
            )
        )
    }

    func testAcceptIdentityEnablesWhenDefaultIsSet() {
        let (on, _) = defaults(probeEnabled: true)
        let (off, _) = defaults(probeEnabled: false)
        XCTAssertTrue(
            SnoozeWakeAcceptanceProbe.isEnabled(
                bundleIdentifier: "org.bobs.bob-mac-capture.accept",
                defaults: on
            )
        )
        XCTAssertFalse(
            SnoozeWakeAcceptanceProbe.isEnabled(
                bundleIdentifier: "org.bobs.bob-mac-capture.accept",
                defaults: off
            )
        )
    }

    func testAcceptNoauthPrefixMatchesTheGate() {
        let (defaults, _) = defaults(probeEnabled: true)
        XCTAssertTrue(
            SnoozeWakeAcceptanceProbe.isEnabled(
                bundleIdentifier: "org.bobs.bob-mac-capture.accept-noauth",
                defaults: defaults
            )
        )
    }

    func testResponseShapeIncludesSeqOkErrorAndResult() async throws {
        let host = FakeHost()
        let probe = SnoozeWakeAcceptanceProbe(
            host: host,
            bundleIdentifier: "org.bobs.bob-mac-capture.accept"
        )
        let response = await probe.handle(seq: 7, command: "snapshot", args: ["png"])
        XCTAssertEqual(response["seq"] as? Int, 7)
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertTrue(response["error"] is NSNull)
        XCTAssertEqual(host.lastCommand, "snapshot")
        XCTAssertEqual(host.lastArgs, ["png"])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual((result["hud"] as? [String: Any])?["visible"] as? Bool, false)
    }

    func testUnknownCommandWritesAnErrorResponse() async {
        let host = FakeHost()
        let probe = SnoozeWakeAcceptanceProbe(
            host: host,
            bundleIdentifier: "org.bobs.bob-mac-capture.accept"
        )
        let response = await probe.handle(seq: 3, command: "boom", args: [])
        XCTAssertEqual(response["seq"] as? Int, 3)
        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "boom")
        XCTAssertTrue(response["result"] is NSNull)
    }

    func testProcessRequestWritesResponseFile() async throws {
        let host = FakeHost()
        let state = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: state) }
        let probe = SnoozeWakeAcceptanceProbe(
            host: host,
            bundleIdentifier: "org.bobs.bob-mac-capture.accept",
            environment: ["XDG_STATE_HOME": state.path]
        )
        let directory = SnoozeWakeAcceptanceProbe.probeDirectory(
            environment: ["XDG_STATE_HOME": state.path]
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let request: [String: Any] = [
            "seq": 11,
            "command": "hover",
            "args": ["enter"],
        ]
        let requestData = try JSONSerialization.data(withJSONObject: request)
        try requestData.write(
            to: directory.appendingPathComponent("request.json"), options: .atomic)
        await probe.processRequest()
        let responseURL = directory.appendingPathComponent("response-11.json")
        let data = try Data(contentsOf: responseURL)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["seq"] as? Int, 11)
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertEqual(host.lastCommand, "hover")
        XCTAssertEqual(host.lastArgs, ["enter"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("request.json").path)
        )
    }

    func testProbeDirectoryUsesXDGStateHome() {
        let url = SnoozeWakeAcceptanceProbe.probeDirectory(
            environment: ["XDG_STATE_HOME": "/tmp/bob-wake-accept/state"]
        )
        XCTAssertEqual(
            url.path, "/tmp/bob-wake-accept/state/bob-mac-capture-accept/probe")
    }

    func testDisabledProbeDoesNotStart() {
        let (defaults, _) = defaults(probeEnabled: false)
        let probe = SnoozeWakeAcceptanceProbe(
            host: FakeHost(),
            defaults: defaults,
            bundleIdentifier: "org.bobs.bob-mac-capture.accept",
            register: { _ in
                XCTFail("must not register")
                return 1
            }
        )
        probe.start()
        XCTAssertFalse(probe.isStarted)
    }
}
