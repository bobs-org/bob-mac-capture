import AppKit
import XCTest

@testable import BobMacCapture

@MainActor
final class HighlightsSaveKeyMonitorTests: XCTestCase {
    func testMonitorRequiresSettingFrontmostAppAndAccessibility() {
        let center = NotificationCenter()
        let installer = FakeGlobalKeyMonitorInstaller()
        var frontmost: String? = "other.app"
        var trusted = true
        var enabled = true
        let monitor = makeMonitor(
            center: center,
            installer: installer,
            frontmost: { frontmost },
            trusted: { trusted },
            enabled: { enabled }
        )

        monitor.start()
        XCTAssertEqual(installer.installCount, 0)
        frontmost = HighlightsLocator.bundleIdentifier
        monitor.sync()
        XCTAssertEqual(installer.installCount, 1)

        trusted = false
        monitor.sync()
        XCTAssertEqual(installer.removeCount, 1)
        trusted = true
        enabled = false
        monitor.sync(enabled: enabled)
        XCTAssertEqual(installer.installCount, 1)

        enabled = true
        monitor.sync(enabled: enabled)
        XCTAssertEqual(installer.installCount, 2)
        monitor.stop()
        XCTAssertEqual(installer.removeCount, 2)
    }

    func testWorkspaceChangesResyncTheMonitorWithoutPrompting() async {
        let center = NotificationCenter()
        let installer = FakeGlobalKeyMonitorInstaller()
        var frontmost: String? = HighlightsLocator.bundleIdentifier
        var trusted = true
        var trustChecks = 0
        let monitor = makeMonitor(
            center: center,
            installer: installer,
            frontmost: { frontmost },
            trusted: {
                trustChecks += 1
                return trusted
            }
        )
        monitor.start()
        XCTAssertEqual(installer.installCount, 1)

        frontmost = nil
        center.post(name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        await waitUntil { installer.removeCount == 1 }
        frontmost = HighlightsLocator.bundleIdentifier
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        await waitUntil { installer.installCount == 2 }
        trusted = false
        center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        await waitUntil { installer.removeCount == 2 }

        XCTAssertGreaterThanOrEqual(trustChecks, 3)
        monitor.stop()
    }

    func testAKeyAndFakeClockRequestOneHighlightsSaveScan() async {
        let center = NotificationCenter()
        let installer = FakeGlobalKeyMonitorInstaller()
        var current = Date(timeIntervalSince1970: 1_800_000_000)
        var scans = 0
        let monitor = makeMonitor(
            center: center,
            installer: installer,
            readPath: { nil },
            now: { current },
            onScan: { scans += 1 }
        )
        monitor.start()
        installer.send(commandS)
        await waitUntil { monitor.isWaitingToScan }

        current.addTimeInterval(2.5)
        monitor.pollNow()
        monitor.pollNow()
        XCTAssertEqual(scans, 1)
        monitor.stop()
    }

    func testSaveOutsideLibraryDisarmsWithoutScanning() async {
        let center = NotificationCenter()
        let installer = FakeGlobalKeyMonitorInstaller()
        var current = Date(timeIntervalSince1970: 1_800_000_000)
        var scans = 0
        let monitor = makeMonitor(
            center: center,
            installer: installer,
            readPath: { "/tmp/outside.pdf" },
            now: { current },
            onScan: { scans += 1 }
        )
        monitor.start()
        installer.send(commandS)
        await waitUntil { monitor.didFinishScopeRead && !monitor.isWaitingToScan }

        current.addTimeInterval(20)
        monitor.pollNow()
        XCTAssertEqual(scans, 0)
        monitor.stop()
    }

    private func makeMonitor(
        center: NotificationCenter,
        installer: FakeGlobalKeyMonitorInstaller,
        frontmost: @escaping () -> String? = { HighlightsLocator.bundleIdentifier },
        trusted: @escaping () -> Bool = { true },
        enabled: @escaping () -> Bool = { true },
        readPath: @escaping () async -> String? = { nil },
        now: @escaping () -> Date = { Date() },
        onScan: @escaping () -> Void = {}
    ) -> HighlightsSaveKeyMonitor {
        HighlightsSaveKeyMonitor(
            notificationCenter: center,
            installer: installer,
            frontmostBundleID: frontmost,
            expectedBundleID: { HighlightsLocator.bundleIdentifier },
            isTrusted: trusted,
            isEnabled: enabled,
            vaultRoot: { "/vault" },
            readCurrentDocumentPath: readPath,
            now: now,
            onScan: onScan
        )
    }

    private var commandS: HighlightsSaveKeyEvent {
        HighlightsSaveKeyEvent(
            charactersIgnoringModifiers: "s",
            command: true,
            shift: false,
            option: false,
            control: false,
            isARepeat: false
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition did not become true before timeout")
    }
}

@MainActor
private final class FakeGlobalKeyMonitorInstaller: GlobalKeyMonitorInstalling {
    private final class Token: GlobalKeyMonitorToken {}

    private var handler: ((HighlightsSaveKeyEvent) -> Void)?
    private var token: Token?
    private(set) var installCount = 0
    private(set) var removeCount = 0

    func install(
        handler: @escaping (HighlightsSaveKeyEvent) -> Void
    ) -> GlobalKeyMonitorToken? {
        installCount += 1
        let token = Token()
        self.token = token
        self.handler = handler
        return token
    }

    func remove(_ token: GlobalKeyMonitorToken) {
        guard self.token === (token as? Token) else { return }
        removeCount += 1
        self.token = nil
        handler = nil
    }

    func send(_ event: HighlightsSaveKeyEvent) {
        handler?(event)
    }
}
