import AppKit
import Carbon
import ServiceManagement
import XCTest

@testable import BobMacCapture

final class BobMacCaptureTests: XCTestCase {
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
    }

    func testHotKeyRegistrationConflictIsReported() {
        let registrar = FakeHotKeyRegistrar(status: eventHotKeyExistsErr)
        let manager = HotKeyManager(registrar: registrar) {}

        XCTAssertThrowsError(try manager.register(configuration: .development)) { error in
            XCTAssertEqual(
                error as? HotKeyRegistrationError,
                .registrationFailed(eventHotKeyExistsErr)
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
