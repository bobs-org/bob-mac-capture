import Carbon
import XCTest

@testable import BobMacCapture

final class CaptureAliasHotkeyRegistrationTests: XCTestCase {
    func testSyncRegistersAndUnregisters() {
        let registrar = CaptureAliasFakeRegistrar()
        let registry = HotKeyRegistry(registrar: registrar) { _ in }
        var errors: [String] = []

        XCTAssertTrue(
            CaptureAliasHotkeyRegistration.sync(registry: registry, enabled: true) {
                errors.append($0)
            }
        )
        XCTAssertTrue(registry.isRegistered(.captureAlias))
        XCTAssertTrue(errors.isEmpty)

        XCTAssertFalse(
            CaptureAliasHotkeyRegistration.sync(registry: registry, enabled: false) {
                errors.append($0)
            }
        )
        XCTAssertFalse(registry.isRegistered(.captureAlias))
        XCTAssertTrue(errors.isEmpty)
    }

    func testSyncRegistersCommandBackslashUnderId8() {
        let registrar = CaptureAliasFakeRegistrar()
        let registry = HotKeyRegistry(registrar: registrar) { _ in }
        var errors: [String] = []

        XCTAssertTrue(
            CaptureAliasHotkeyRegistration.sync(registry: registry, enabled: true) {
                errors.append($0)
            }
        )
        XCTAssertEqual(HotKeyAction.captureAlias.rawValue, 8)
        XCTAssertEqual(
            registrar.configuration(for: .captureAlias),
            .captureCommandBackslash
        )
        XCTAssertEqual(
            registrar.configuration(for: .captureAlias)?.keyCode,
            UInt32(kVK_ANSI_Backslash)
        )
        XCTAssertEqual(
            registrar.configuration(for: .captureAlias)?.modifiers,
            UInt32(cmdKey)
        )
        XCTAssertTrue(registrar.liveIDs.contains(HotKeyAction.captureAlias.rawValue))
        XCTAssertTrue(errors.isEmpty)
    }

    func testConflictIsReportedAndKeepsCapture() throws {
        let registrar = CaptureAliasFakeRegistrar()
        registrar.failIDs = [HotKeyAction.captureAlias.rawValue]
        let registry = HotKeyRegistry(registrar: registrar) { _ in }
        try registry.register(.capture, configuration: .development)
        var errors: [String] = []

        XCTAssertFalse(
            CaptureAliasHotkeyRegistration.sync(registry: registry, enabled: true) {
                errors.append($0)
            }
        )

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].hasPrefix("Capture alias hotkey conflict: "))
        XCTAssertTrue(registry.isRegistered(.capture))
        XCTAssertFalse(registry.isRegistered(.captureAlias))
    }
}

/// Records registrations per action id so alias tests can assert routing
/// without Carbon.
private final class CaptureAliasFakeRegistrar: HotKeyRegistering {
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
