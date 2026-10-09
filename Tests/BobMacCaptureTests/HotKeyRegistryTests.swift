import Carbon
import XCTest

@testable import BobMacCapture

/// Tests for the shared hotkey registry: one Carbon handler routing every
/// Bob hotkey by `EventHotKeyID`, with per-action registrations that never
/// disturb each other.
final class HotKeyRegistryTests: XCTestCase {
    func testActionsUseDistinctIdentifiersUnderOneSignature() throws {
        let registrar = FakeHotKeyRegistrar()
        let registry = HotKeyRegistry(registrar: registrar) { _ in }

        try registry.register(.capture, configuration: .development)
        try registry.register(.refs, configuration: .refs)
        try registry.register(
            .refsHighlightsOpen,
            configuration: .highlightsCommandO
        )

        XCTAssertEqual(
            registrar.identifiers.map { $0.id },
            [HotKeyAction.capture.rawValue, HotKeyAction.refs.rawValue,
                HotKeyAction.refsHighlightsOpen.rawValue]
        )
        XCTAssertTrue(
            registrar.identifiers.allSatisfy {
                $0.signature == HotKeyRegistry.signature
            }
        )
        XCTAssertTrue(registry.isRegistered(.capture))
        XCTAssertTrue(registry.isRegistered(.refs))
        XCTAssertTrue(registry.isRegistered(.refsHighlightsOpen))
    }

    func testHandleRoutesEachActionByID() {
        let registrar = FakeHotKeyRegistrar()
        var pressed: [HotKeyAction] = []
        let registry = HotKeyRegistry(registrar: registrar) {
            pressed.append($0)
        }

        for action in HotKeyAction.allCases {
            let status = registry.handle(
                hotKeyID: HotKeyRegistry.identifier(for: action)
            )
            XCTAssertEqual(status, noErr)
        }
        XCTAssertEqual(pressed, HotKeyAction.allCases)
    }

    func testHandleRejectsUnknownIDAndForeignSignature() {
        let registrar = FakeHotKeyRegistrar()
        var pressed: [HotKeyAction] = []
        let registry = HotKeyRegistry(registrar: registrar) {
            pressed.append($0)
        }

        XCTAssertEqual(
            registry.handle(
                hotKeyID: EventHotKeyID(
                    signature: HotKeyRegistry.signature,
                    id: 99
                )
            ),
            OSStatus(eventNotHandledErr)
        )
        XCTAssertEqual(
            registry.handle(
                hotKeyID: EventHotKeyID(
                    signature: OSType(0x46414B45),
                    id: HotKeyAction.capture.rawValue
                )
            ),
            OSStatus(eventNotHandledErr)
        )
        XCTAssertTrue(pressed.isEmpty)
    }

    func testReregisteringReplacesOnlyThatAction() throws {
        let registrar = FakeHotKeyRegistrar()
        var pressed: [HotKeyAction] = []
        let registry = HotKeyRegistry(registrar: registrar) {
            pressed.append($0)
        }

        try registry.register(.capture, configuration: .development)
        try registry.register(.refs, configuration: .refs)
        let unregisteredBeforeReregister = registrar.unregistered.count

        try registry.register(.capture, configuration: .production)

        XCTAssertEqual(
            registrar.unregistered.count,
            unregisteredBeforeReregister + 1
        )
        XCTAssertTrue(registry.isRegistered(.capture))
        XCTAssertTrue(registry.isRegistered(.refs))
        XCTAssertEqual(
            registry.handle(
                hotKeyID: HotKeyRegistry.identifier(for: .capture)
            ),
            noErr
        )
        XCTAssertEqual(pressed, [.capture])
    }

    func testFailedRegistrationKeepsOtherRegistrations() throws {
        let registrar = FakeHotKeyRegistrar()
        registrar.failIDs = [HotKeyAction.refs.rawValue]
        var pressed: [HotKeyAction] = []
        let registry = HotKeyRegistry(registrar: registrar) {
            pressed.append($0)
        }

        try registry.register(.capture, configuration: .development)
        XCTAssertThrowsError(
            try registry.register(.refs, configuration: .refs)
        ) { error in
            XCTAssertEqual(
                error as? HotKeyRegistrationError,
                .registrationFailed(registrar.status)
            )
        }

        XCTAssertTrue(registry.isRegistered(.capture))
        XCTAssertFalse(registry.isRegistered(.refs))
        XCTAssertEqual(
            registry.handle(
                hotKeyID: HotKeyRegistry.identifier(for: .capture)
            ),
            noErr
        )
        XCTAssertEqual(pressed, [.capture])
    }

    func testInvalidateUnregistersEverything() throws {
        let registrar = FakeHotKeyRegistrar()
        let registry = HotKeyRegistry(registrar: registrar) { _ in }

        for action in HotKeyAction.allCases {
            try registry.register(action, configuration: .development)
        }
        registry.invalidate()

        XCTAssertFalse(registry.isRegistered(.capture))
        XCTAssertFalse(registry.isRegistered(.refs))
        XCTAssertFalse(registry.isRegistered(.refsHighlightsOpen))
        XCTAssertEqual(
            registrar.unregistered.count,
            HotKeyAction.allCases.count
        )
    }

    func testUnregisterDropsOnlyThatAction() throws {
        let registrar = FakeHotKeyRegistrar()
        let registry = HotKeyRegistry(registrar: registrar) { _ in }

        try registry.register(.capture, configuration: .development)
        try registry.register(.refs, configuration: .refs)
        registry.unregister(.capture)

        XCTAssertFalse(registry.isRegistered(.capture))
        XCTAssertTrue(registry.isRegistered(.refs))
        XCTAssertEqual(registrar.unregistered.count, 1)
    }

    func testRefsAndHighlightsPresets() {
        XCTAssertEqual(
            HotKeyConfiguration.refs.keyCode,
            UInt32(kVK_ANSI_O)
        )
        XCTAssertEqual(
            HotKeyConfiguration.refs.modifiers,
            UInt32(cmdKey | controlKey | shiftKey)
        )
        XCTAssertEqual(HotKeyConfiguration.refs.displayName, "Control-Shift-Command-O")
        XCTAssertEqual(HotKeyConfiguration.development.displayName, "Control-Shift-Command-R")
        XCTAssertEqual(HotKeyConfiguration.production.displayName, "Control-Shift-Command-I")
        XCTAssertEqual(
            HotKeyConfiguration.highlightsCommandO.keyCode,
            UInt32(kVK_ANSI_O)
        )
        XCTAssertEqual(
            HotKeyConfiguration.highlightsCommandO.modifiers,
            UInt32(cmdKey)
        )
        XCTAssertEqual(
            HotKeyConfiguration.highlightsControlO.keyCode,
            UInt32(kVK_ANSI_O)
        )
        XCTAssertEqual(
            HotKeyConfiguration.highlightsControlO.modifiers,
            UInt32(controlKey)
        )
    }

    func testCapturePresetsDoNotCollideWithRefs() {
        for capture in [HotKeyConfiguration.production, HotKeyConfiguration.development] {
            let claimsRefsChord =
                capture.keyCode == HotKeyConfiguration.refs.keyCode
                && capture.modifiers == HotKeyConfiguration.refs.modifiers
            XCTAssertFalse(
                claimsRefsChord,
                "\(capture.displayName) must not claim the Refs chord"
            )
        }
    }

    func testDevelopmentPresetMovedToR() {
        XCTAssertEqual(
            HotKeyConfiguration.development.keyCode,
            UInt32(kVK_ANSI_R)
        )
        XCTAssertEqual(
            HotKeyConfiguration.development.modifiers,
            UInt32(cmdKey | controlKey | shiftKey)
        )
    }
}

private final class FakeHotKeyRegistrar: HotKeyRegistering {
    var failIDs: Set<UInt32> = []
    var status: OSStatus = OSStatus(eventHotKeyExistsErr)
    private(set) var identifiers: [EventHotKeyID] = []
    private(set) var unregistered: [EventHotKeyRef] = []
    private var nextToken = 1

    func register(
        configuration: HotKeyConfiguration,
        identifier: EventHotKeyID,
        reference: UnsafeMutablePointer<EventHotKeyRef?>?
    ) -> OSStatus {
        identifiers.append(identifier)
        if failIDs.contains(identifier.id) {
            return status
        }
        reference?.pointee = OpaquePointer(bitPattern: nextToken)
        nextToken += 1
        return noErr
    }

    func unregister(reference: EventHotKeyRef) {
        unregistered.append(reference)
    }
}
