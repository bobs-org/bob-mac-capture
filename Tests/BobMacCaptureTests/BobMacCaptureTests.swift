import AppKit
import Carbon
import CaptureCore
import ServiceManagement
import XCTest

@testable import BobMacCapture

final class BobMacCaptureTests: XCTestCase {
    @MainActor
    func testPanelHasStableNonActivatingStyleInInitializer() {
        let panel = CapturePanelController.makePanel()

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func testKeyRouterMatchesCaptureShortcuts() {
        let router = CaptureKeyCommandRouter()

        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36)), .submit)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36, modifiers: .command)), .submitAndOpen)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36, modifiers: .shift)), .insertNewline)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36, modifiers: .option)), .insertNewline)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 53)), .escape)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36), completionVisible: true), .acceptCompletion)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 48), completionVisible: true), .acceptCompletion)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 125), completionVisible: true), .nextCompletion)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 126), completionVisible: true), .previousCompletion)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 45, modifiers: .control), completionVisible: true),
            .nextCompletion
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 35, modifiers: .control), completionVisible: true),
            .previousCompletion
        )
    }

    @MainActor
    func testCompletionAcceptanceUsesServerByteReplacementRange() {
        let model = CapturePanelModel()
        model.plainDraft = "idea @ma"
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: 8,
            replacement: CaptureRange(start: 6, end: 8),
            context: "route",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "mac_inbox",
                    route: "mac_inbox",
                    label: "mac_inbox.md",
                    kind: "inbox"
                )
            ]
        )

        model.acceptSelectedCompletion()

        XCTAssertEqual(model.plainDraft, "idea @mac_inbox")
        XCTAssertNil(model.completionResponse)
    }

    func testHotKeyRegistrationConflictIsReported() {
        let conflictStatus = OSStatus(eventHotKeyExistsErr)
        let registrar = FakeHotKeyRegistrar(status: conflictStatus)
        let manager = HotKeyManager(registrar: registrar) {}

        XCTAssertThrowsError(try manager.register(configuration: .development)) { error in
            XCTAssertEqual(
                error as? HotKeyRegistrationError,
                .registrationFailed(conflictStatus)
            )
        }
    }

    func testInfoPlistDeclaresUiElementAndBundleIdentity() throws {
        let plistURL = packageRoot().appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "org.bobs.bob-mac-capture")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Bob Mac Capture")
        XCTAssertEqual(plist["LSUIElement"] as? String, "1")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "26.0")
    }

    @MainActor
    func testOpenSettingsMenuActionUsesRegisteredSettingsPresenterOnce() {
        let delegate = AppDelegate()
        var openSettingsCount = 0
        var activationCount = 0
        delegate.settingsPresentation = SettingsPresentation(
            openSettings: {
                openSettingsCount += 1
            },
            activateApplication: {
                activationCount += 1
            }
        )

        delegate.openSettings()

        XCTAssertEqual(openSettingsCount, 1)
        XCTAssertEqual(activationCount, 1)
    }

    @MainActor
    func testDiagnosticHistoryRecordsChangesAndStaysBounded() {
        let defaults = UserDefaults(suiteName: "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)

        settings.diagnosticStatus = "Starting"
        XCTAssertTrue(settings.diagnosticHistory.isEmpty, "Setting the same value must not record a duplicate")

        for index in 0..<25 {
            settings.diagnosticStatus = "Status \(index)"
        }

        XCTAssertEqual(settings.diagnosticHistory.count, 20)
        XCTAssertFalse(settings.diagnosticHistory.contains { $0.hasSuffix("Status 0") })
        XCTAssertTrue(settings.diagnosticHistory.contains { $0.hasSuffix("Status 24") })
    }

    func testLaunchAtLoginStateMapping() {
        XCTAssertTrue(LaunchAtLoginState(status: .enabled).enabled)
        XCTAssertFalse(LaunchAtLoginState(status: .notRegistered).enabled)
        XCTAssertFalse(LaunchAtLoginState(status: .requiresApproval).enabled)
        XCTAssertFalse(LaunchAtLoginState(status: .notFound).enabled)
    }

    private func keyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class FakeHotKeyRegistrar: HotKeyRegistering {
    let status: OSStatus

    init(status: OSStatus) {
        self.status = status
    }

    func register(
        configuration: HotKeyConfiguration,
        identifier: EventHotKeyID,
        reference: UnsafeMutablePointer<EventHotKeyRef?>?
    ) -> OSStatus {
        status
    }

    func unregister(reference: EventHotKeyRef) {}
}
