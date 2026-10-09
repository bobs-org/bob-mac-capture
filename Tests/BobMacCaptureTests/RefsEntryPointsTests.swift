import AppKit
import Carbon
import XCTest

@testable import BobMacCapture
@testable import CaptureCore
@testable import RefsCore

/// Entry-point tests for the refs-entry-points phase: the one-panel
/// coordinator, the Highlights-frontmost takeover, the References
/// settings keys, the status-menu row, and live hotkey re-registration
/// with conflict reporting.
@MainActor
final class RefsEntryPointsTests: XCTestCase {
    // MARK: - Coordinator

    func testShowingRefsRetainsCaptureDraft() {
        let capture = CapturePanelModel()
        capture.plainDraft = "keep me"
        let log = EventLog()
        let coordinator = makeCoordinator(
            capture: capture,
            captureVisible: true,
            refsVisible: false,
            log: log
        )

        coordinator.showRefs()

        XCTAssertEqual(log.events, ["close-retain", "show-refs"])
        XCTAssertEqual(capture.plainDraft, "keep me")
    }

    func testShowingRefsWhenCaptureHiddenShowsDirectly() {
        let capture = CapturePanelModel()
        let log = EventLog()
        let coordinator = makeCoordinator(
            capture: capture,
            captureVisible: false,
            refsVisible: false,
            log: log
        )

        coordinator.showRefs()

        XCTAssertEqual(log.events, ["show-refs"])
    }

    func testShowingCaptureHidesRefsFirst() {
        let capture = CapturePanelModel()
        let log = EventLog()
        let coordinator = makeCoordinator(
            capture: capture,
            captureVisible: false,
            refsVisible: true,
            log: log
        )

        coordinator.showCapture()

        XCTAssertEqual(log.events, ["hide-refs", "show-capture"])
    }

    func testShowingCaptureWhenRefsHiddenShowsDirectly() {
        let capture = CapturePanelModel()
        let log = EventLog()
        let coordinator = makeCoordinator(
            capture: capture,
            captureVisible: false,
            refsVisible: false,
            log: log
        )

        coordinator.showCapture()

        XCTAssertEqual(log.events, ["show-capture"])
    }

    func testToggleRefsHidesWhenVisible() {
        let capture = CapturePanelModel()
        capture.plainDraft = "keep me"
        let log = EventLog()
        let coordinator = makeCoordinator(
            capture: capture,
            captureVisible: true,
            refsVisible: true,
            log: log
        )

        coordinator.toggleRefs()

        XCTAssertEqual(log.events, ["hide-refs"])
        XCTAssertEqual(capture.plainDraft, "keep me")
    }

    func testToggleRefsShowsAndRetainsWhenHidden() {
        let capture = CapturePanelModel()
        capture.plainDraft = "keep me"
        let log = EventLog()
        let coordinator = makeCoordinator(
            capture: capture,
            captureVisible: true,
            refsVisible: false,
            log: log
        )

        coordinator.toggleRefs()

        XCTAssertEqual(log.events, ["close-retain", "show-refs"])
        XCTAssertEqual(capture.plainDraft, "keep me")
    }

    // MARK: - Takeover

    func testTakeoverRegistersWhenHighlightsAlreadyFrontmostAtStart() {
        let fixture = makeTakeover(
            frontmost: HighlightsLocator.bundleIdentifier,
            openKey: .cmdO
        )

        fixture.takeover.start()

        XCTAssertTrue(fixture.isTakeoverRegistered)
        XCTAssertEqual(
            fixture.registrar.configuration(for: .refsHighlightsOpen),
            .highlightsCommandO
        )
    }

    func testTakeoverStaysOffForOtherApps() {
        let fixture = makeTakeover(
            frontmost: "com.apple.Safari",
            openKey: .cmdO
        )

        fixture.takeover.start()

        XCTAssertFalse(fixture.isTakeoverRegistered)
    }

    func testTakeoverRegistersOnHighlightsActivation() async {
        let fixture = makeTakeover(frontmost: "com.apple.Safari", openKey: .cmdO)
        fixture.takeover.start()
        XCTAssertFalse(fixture.isTakeoverRegistered)

        fixture.frontmost = HighlightsLocator.bundleIdentifier
        fixture.center.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        await fixture.waitUntil { fixture.isTakeoverRegistered }
        XCTAssertTrue(fixture.isTakeoverRegistered)
    }

    func testTakeoverUnregistersOnOtherActivation() async {
        let fixture = makeTakeover(
            frontmost: HighlightsLocator.bundleIdentifier,
            openKey: .cmdO
        )
        fixture.takeover.start()
        XCTAssertTrue(fixture.isTakeoverRegistered)

        fixture.frontmost = "com.apple.Safari"
        fixture.center.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        await fixture.waitUntil { !fixture.isTakeoverRegistered }
        XCTAssertFalse(fixture.isTakeoverRegistered)
    }

    func testTakeoverOffNeverRegisters() async {
        let fixture = makeTakeover(
            frontmost: HighlightsLocator.bundleIdentifier,
            openKey: .off
        )
        fixture.takeover.start()
        XCTAssertFalse(fixture.isTakeoverRegistered)

        fixture.center.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(fixture.isTakeoverRegistered)
    }

    func testTakeoverMatchesOverrideAppBundleID() {
        let fixture = makeTakeover(
            frontmost: "com.example.HighlightsCopy",
            openKey: .ctrlO,
            override: "com.example.HighlightsCopy"
        )

        fixture.takeover.start()

        XCTAssertTrue(fixture.isTakeoverRegistered)
        XCTAssertEqual(
            fixture.registrar.configuration(for: .refsHighlightsOpen),
            .highlightsControlO
        )
    }

    func testTakeoverIgnoresHighlightsWhenOverridden() {
        let fixture = makeTakeover(
            frontmost: HighlightsLocator.bundleIdentifier,
            openKey: .cmdO,
            override: "com.example.HighlightsCopy"
        )

        fixture.takeover.start()

        XCTAssertFalse(fixture.isTakeoverRegistered)
    }

    func testTakeoverStopUnregisters() {
        let fixture = makeTakeover(
            frontmost: HighlightsLocator.bundleIdentifier,
            openKey: .cmdO
        )
        fixture.takeover.start()
        XCTAssertTrue(fixture.isTakeoverRegistered)

        fixture.takeover.stop()

        XCTAssertFalse(fixture.isTakeoverRegistered)
    }

    func testTakeoverReportsRegistrationFailure() {
        let fixture = makeTakeover(
            frontmost: HighlightsLocator.bundleIdentifier,
            openKey: .cmdO,
            failIDs: [.refsHighlightsOpen]
        )

        fixture.takeover.start()

        XCTAssertEqual(fixture.errors.count, 1)
        XCTAssertTrue(fixture.errors[0].hasPrefix("Refs hotkey conflict: "))
    }

    // MARK: - Settings

    func testRefsSettingsDefaultPersistAndRoundTrip() {
        let suiteName = "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.refsHotkeyEnabled)
        XCTAssertEqual(settings.refsHighlightsOpenKey, .cmdO)
        XCTAssertEqual(settings.refsHighlightsAppPath, "")

        settings.refsHotkeyEnabled = false
        settings.refsHighlightsOpenKey = .ctrlO
        settings.refsHighlightsAppPath = "/Applications/Highlights.app"

        XCTAssertFalse(defaults.bool(forKey: "refsHotkeyEnabled"))
        XCTAssertEqual(defaults.string(forKey: "refsHighlightsOpenKey"), "ctrlO")
        XCTAssertEqual(
            defaults.string(forKey: "refsHighlightsAppPath"),
            "/Applications/Highlights.app"
        )

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.refsHotkeyEnabled)
        XCTAssertEqual(reloaded.refsHighlightsOpenKey, .ctrlO)
        XCTAssertEqual(reloaded.refsHighlightsAppPath, "/Applications/Highlights.app")

        defaults.set("bogus", forKey: "refsHighlightsOpenKey")
        XCTAssertEqual(AppSettings(defaults: defaults).refsHighlightsOpenKey, .cmdO)
    }

    func testVaultRootFallsBackToHomeBob() {
        XCTAssertEqual(
            AppDelegate.vaultRootURL(bobDirectory: ""),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bob")
        )
        XCTAssertEqual(
            AppDelegate.vaultRootURL(bobDirectory: "/tmp/vault"),
            URL(fileURLWithPath: "/tmp/vault")
        )
    }

    func testHighlightsOverrideBundleIDIsNilWithoutPath() {
        XCTAssertNil(AppDelegate.highlightsOverrideBundleID(path: ""))
        XCTAssertNil(AppDelegate.highlightsOverrideBundleID(path: "/nonexistent.app"))
    }

    // MARK: - Menu

    func testStatusMenuShowsBobRefsAfterCapture() {
        let menu = AppDelegate.makeStatusMenu()

        XCTAssertEqual(
            menu.items.map(\.title),
            [
                "Capture", "Bob Refs…", "Settings", "Recheck Bob", "",
                "Restart Bob Mac Capture", "Quit Bob Mac Capture",
            ]
        )
        let refs = menu.items[1]
        XCTAssertEqual(refs.action.map(NSStringFromSelector), "openRefsPanel")
        XCTAssertEqual(refs.keyEquivalent, "r")
        XCTAssertTrue(refs.keyEquivalentModifierMask.contains(.command))
        XCTAssertTrue(refs.keyEquivalentModifierMask.contains(.control))
        XCTAssertTrue(refs.keyEquivalentModifierMask.contains(.shift))
    }

    func testRepresentRefsRetainsCaptureDraft() {
        let capture = CapturePanelModel()
        capture.plainDraft = "keep me"
        let log = EventLog()
        let coordinator = BobPanelCoordinator(
            isCaptureVisible: { true },
            isRefsVisible: { false },
            closeCaptureRetainingDraft: {
                capture.closeRetainingDraft()
                log.events.append("close-retain")
            },
            presentCapture: { log.events.append("show-capture") },
            presentRefs: { log.events.append("show-refs") },
            presentRefsPreservingState: { log.events.append("show-refs-preserving") },
            hideRefs: { log.events.append("hide-refs") }
        )

        coordinator.representRefs()

        XCTAssertEqual(log.events, ["close-retain", "show-refs-preserving"])
        XCTAssertEqual(capture.plainDraft, "keep me")
    }

    // MARK: - Live settings

    func testTogglingRefsHotkeyEnabledRegistersLive() {
        let delegate = AppDelegate()
        let registrar = EntryPointsFakeRegistrar()
        delegate.hotKeyRegistry = HotKeyRegistry(registrar: registrar) { _ in }
        let original = delegate.settings.refsHotkeyEnabled
        delegate.settings.refsHotkeyEnabled = true
        delegate.observeRefsSettings()
        defer { delegate.settings.refsHotkeyEnabled = original }

        delegate.settings.refsHotkeyEnabled = false
        XCTAssertFalse(registrar.liveIDs.contains(HotKeyAction.refs.rawValue))

        delegate.settings.refsHotkeyEnabled = true
        XCTAssertTrue(registrar.liveIDs.contains(HotKeyAction.refs.rawValue))
    }

    func testChangingTakeoverKeySwapsRegistrationLive() {
        let delegate = AppDelegate()
        let fixture = makeTakeover(
            frontmost: HighlightsLocator.bundleIdentifier,
            openKey: .cmdO
        )
        let originalKey = delegate.settings.refsHighlightsOpenKey
        let originalPath = delegate.settings.refsHighlightsAppPath
        delegate.settings.refsHighlightsOpenKey = .cmdO
        delegate.settings.refsHighlightsAppPath = ""
        delegate.highlightsTakeover = fixture.takeover
        delegate.observeRefsSettings()
        defer {
            delegate.settings.refsHighlightsOpenKey = originalKey
            delegate.settings.refsHighlightsAppPath = originalPath
        }

        // The subscribe-time emission registers Command-O.
        XCTAssertEqual(
            fixture.registrar.configuration(for: .refsHighlightsOpen),
            .highlightsCommandO
        )

        delegate.settings.refsHighlightsOpenKey = .ctrlO
        XCTAssertEqual(
            fixture.registrar.configuration(for: .refsHighlightsOpen),
            .highlightsControlO
        )

        delegate.settings.refsHighlightsOpenKey = .off
        XCTAssertFalse(fixture.isTakeoverRegistered)
    }

    func testTakeoverUnregistersWhenHighlightsTerminates() async {
        let fixture = makeTakeover(
            frontmost: HighlightsLocator.bundleIdentifier,
            openKey: .cmdO
        )
        fixture.takeover.start()
        XCTAssertTrue(fixture.isTakeoverRegistered)

        // Highlights is gone: the frontmost app moved on and the
        // workspace posts termination.
        fixture.frontmost = "com.apple.Safari"
        fixture.center.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        await fixture.waitUntil { !fixture.isTakeoverRegistered }
        XCTAssertFalse(fixture.isTakeoverRegistered)
    }

    func testCaptureSuccessRefreshesTodayAndMarksSnapshotStale() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let library = try makeRefsLibrary(environment: [
            "FAKE_BOB_RECORD_PATH": recordURL.path,
        ])

        library.refresh(reason: .manual)
        await waitForEntryPoints { library.lastSuccessAt != nil }
        await waitForEntryPoints { library.signals.today.entries.count == 4 }
        let plansBefore = entryPointsPlanCount(recordURL)

        let delegate = AppDelegate()
        delegate.refsLibrary = library
        delegate.handleCaptureSuccess()

        XCTAssertNil(library.lastSuccessAt)
        await waitForEntryPoints { entryPointsPlanCount(recordURL) > plansBefore }
    }

    // MARK: - Hotkey registration

    func testRefsHotkeySyncRegistersAndUnregisters() {
        let registrar = EntryPointsFakeRegistrar()
        let registry = HotKeyRegistry(registrar: registrar) { _ in }
        var errors: [String] = []

        XCTAssertTrue(
            RefsHotkeyRegistration.sync(registry: registry, enabled: true) {
                errors.append($0)
            }
        )
        XCTAssertTrue(registry.isRegistered(.refs))
        XCTAssertTrue(errors.isEmpty)

        XCTAssertFalse(
            RefsHotkeyRegistration.sync(registry: registry, enabled: false) {
                errors.append($0)
            }
        )
        XCTAssertFalse(registry.isRegistered(.refs))
        XCTAssertTrue(errors.isEmpty)
    }

    func testRefsHotkeyConflictIsReportedAndKeepsCapture() throws {
        let registrar = EntryPointsFakeRegistrar()
        registrar.failIDs = [HotKeyAction.refs.rawValue]
        let registry = HotKeyRegistry(registrar: registrar) { _ in }
        try registry.register(.capture, configuration: .development)
        var errors: [String] = []

        XCTAssertFalse(
            RefsHotkeyRegistration.sync(registry: registry, enabled: true) {
                errors.append($0)
            }
        )

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].hasPrefix("Refs hotkey conflict: "))
        XCTAssertTrue(registry.isRegistered(.capture))
        XCTAssertFalse(registry.isRegistered(.refs))
    }

    // MARK: - Helpers

    private final class EventLog {
        var events: [String] = []
    }

    private func makeCoordinator(
        capture: CapturePanelModel,
        captureVisible: Bool,
        refsVisible: Bool,
        log: EventLog
    ) -> BobPanelCoordinator {
        BobPanelCoordinator(
            isCaptureVisible: { captureVisible },
            isRefsVisible: { refsVisible },
            closeCaptureRetainingDraft: {
                capture.closeRetainingDraft()
                log.events.append("close-retain")
            },
            presentCapture: { log.events.append("show-capture") },
            presentRefs: { log.events.append("show-refs") },
            hideRefs: { log.events.append("hide-refs") }
        )
    }

    @MainActor
    private final class TakeoverFixture {
        let center = NotificationCenter()
        let registrar = EntryPointsFakeRegistrar()
        var frontmost: String?
        var openKey: RefsHighlightsOpenKey
        var override: String?
        var errors: [String] = []
        lazy var takeover: HighlightsTakeover = {
            let registry = HotKeyRegistry(registrar: registrar) { _ in }
            return HighlightsTakeover(
                notificationCenter: center,
                registry: registry,
                frontmostBundleID: { [weak self] in self?.frontmost },
                openKey: { [weak self] in self?.openKey ?? .cmdO },
                overrideBundleID: { [weak self] in self?.override },
                onError: { [weak self] in self?.errors.append($0) }
            )
        }()

        init(
            frontmost: String?,
            openKey: RefsHighlightsOpenKey,
            override: String?,
            failIDs: Set<HotKeyAction>
        ) {
            self.frontmost = frontmost
            self.openKey = openKey
            self.override = override
            registrar.failIDs = Set(failIDs.map(\.rawValue))
        }

        var isTakeoverRegistered: Bool {
            registrar.liveIDs.contains(HotKeyAction.refsHighlightsOpen.rawValue)
        }

        func waitUntil(
            timeout: TimeInterval = 5,
            _ condition: @MainActor @escaping () -> Bool
        ) async {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition() {
                if Date() > deadline {
                    XCTFail("Condition not met before timeout")
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }

    private func makeTakeover(
        frontmost: String?,
        openKey: RefsHighlightsOpenKey,
        override: String? = nil,
        failIDs: Set<HotKeyAction> = []
    ) -> TakeoverFixture {
        let fixture = TakeoverFixture(
            frontmost: frontmost,
            openKey: openKey,
            override: override,
            failIDs: failIDs
        )
        // Force the lazy takeover so every test starts from one place.
        _ = fixture.takeover
        return fixture
    }

    private func makeRefsLibrary(environment: [String: String]) throws -> RefsLibrary {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("ref"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("lib"),
            withIntermediateDirectories: true
        )
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let client = BobProcessClient(
            executablePath: packageRoot
                .appendingPathComponent("Tests/Fixtures/fake-bob")
                .path,
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
                .merging(environment) { _, override in override }
        )
        return RefsLibrary(
            fetcher: BobRefsFetcher(client: client),
            snapshotStore: RefsSnapshotStore(
                fileURL: root.appendingPathComponent("refs-snapshot.json")
            ),
            openLogStore: RefsOpenLogStore(
                fileURL: root.appendingPathComponent("refs-open-log.json")
            ),
            vaultRoot: { vault },
            fileExists: { _ in true },
            spotlight: FakeSpotlight(),
            now: { Date() }
        )
    }

    private func waitForEntryPoints(
        timeout: TimeInterval = 15,
        _ condition: @MainActor @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func entryPointsPlanCount(_ recordURL: URL) -> Int {
        let record = (try? String(contentsOf: recordURL)) ?? ""
        return record.components(separatedBy: "argv=plan -f json").count - 1
    }
}

/// Records registrations per action id so entry-point tests can assert
/// routing without Carbon.
private final class EntryPointsFakeRegistrar: HotKeyRegistering {
    var failIDs: Set<UInt32> = []
    var status: OSStatus = OSStatus(eventHotKeyExistsErr)
    private(set) var liveIDs: Set<UInt32> = []
    private(set) var configurations: [UInt32: HotKeyConfiguration] = [:]
    private var tokenIDs: [EventHotKeyRef: UInt32] = [:]
    private var nextToken = 1

    func configuration(for action: HotKeyAction) -> HotKeyConfiguration? {
        configurations[action.rawValue]
    }

    func register(
        configuration: HotKeyConfiguration,
        identifier: EventHotKeyID,
        reference: UnsafeMutablePointer<EventHotKeyRef?>?
    ) -> OSStatus {
        if failIDs.contains(identifier.id) {
            return status
        }
        guard let token = OpaquePointer(bitPattern: nextToken) else {
            return status
        }
        nextToken += 1
        reference?.pointee = token
        liveIDs.insert(identifier.id)
        configurations[identifier.id] = configuration
        tokenIDs[token] = identifier.id
        return noErr
    }

    func unregister(reference: EventHotKeyRef) {
        if let id = tokenIDs.removeValue(forKey: reference) {
            liveIDs.remove(id)
        }
    }
}
