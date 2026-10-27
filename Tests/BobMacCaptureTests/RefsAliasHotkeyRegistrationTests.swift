import Carbon
import XCTest

@testable import BobMacCapture

final class RefsAliasHotkeyRegistrationTests: XCTestCase {
    func testSyncRegistersAndUnregisters() {
        let registrar = RefsAliasFakeRegistrar()
        let registry = HotKeyRegistry(registrar: registrar) { _ in }
        var errors: [String] = []

        XCTAssertTrue(
            RefsAliasHotkeyRegistration.sync(registry: registry, enabled: true) {
                errors.append($0)
            }
        )
        XCTAssertTrue(registry.isRegistered(.refsAlias))
        XCTAssertTrue(errors.isEmpty)

        XCTAssertFalse(
            RefsAliasHotkeyRegistration.sync(registry: registry, enabled: false) {
                errors.append($0)
            }
        )
        XCTAssertFalse(registry.isRegistered(.refsAlias))
        XCTAssertTrue(errors.isEmpty)
    }

    func testSyncRegistersCommandSlashUnderId9() {
        let registrar = RefsAliasFakeRegistrar()
        let registry = HotKeyRegistry(registrar: registrar) { _ in }
        var errors: [String] = []

        XCTAssertTrue(
            RefsAliasHotkeyRegistration.sync(registry: registry, enabled: true) {
                errors.append($0)
            }
        )
        XCTAssertEqual(HotKeyAction.refsAlias.rawValue, 9)
        XCTAssertEqual(
            registrar.configuration(for: .refsAlias),
            .refsCommandSlash
        )
        XCTAssertEqual(
            registrar.configuration(for: .refsAlias)?.keyCode,
            UInt32(kVK_ANSI_Slash)
        )
        XCTAssertEqual(
            registrar.configuration(for: .refsAlias)?.modifiers,
            UInt32(cmdKey)
        )
        XCTAssertTrue(registrar.liveIDs.contains(HotKeyAction.refsAlias.rawValue))
        XCTAssertTrue(errors.isEmpty)
    }

    func testConflictIsReportedAndKeepsRefs() throws {
        let registrar = RefsAliasFakeRegistrar()
        registrar.failIDs = [HotKeyAction.refsAlias.rawValue]
        let registry = HotKeyRegistry(registrar: registrar) { _ in }
        try registry.register(.refs, configuration: .refs)
        var errors: [String] = []

        XCTAssertFalse(
            RefsAliasHotkeyRegistration.sync(registry: registry, enabled: true) {
                errors.append($0)
            }
        )

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].hasPrefix("Refs alias hotkey conflict: "))
        XCTAssertTrue(registry.isRegistered(.refs))
        XCTAssertFalse(registry.isRegistered(.refsAlias))
    }
}

/// Records registrations per action id so alias tests can assert routing
/// without Carbon.
private final class RefsAliasFakeRegistrar: HotKeyRegistering {
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
