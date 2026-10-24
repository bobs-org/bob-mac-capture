import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

final class HighlightsSaveKeyTests: XCTestCase {
    func testOnlyPlainCommandSMatches() {
        XCTAssertTrue(matches("s", command: true))
        XCTAssertTrue(matches("S", command: true))
        XCTAssertTrue(matches("s", command: true, isARepeat: false))
        XCTAssertFalse(matches("s", command: true, shift: true))
        XCTAssertFalse(matches("s", command: true, option: true))
        XCTAssertFalse(matches("s", command: true, control: true))
        XCTAssertFalse(matches("s", command: false))
        XCTAssertFalse(matches("s", command: true, isARepeat: true))
        XCTAssertFalse(matches("x", command: true))
        XCTAssertFalse(matches(nil, command: true))
    }

    private func matches(
        _ characters: String?,
        command: Bool,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false,
        isARepeat: Bool = false
    ) -> Bool {
        HighlightsSaveKey.matches(
            charactersIgnoringModifiers: characters,
            command: command,
            shift: shift,
            option: option,
            control: control,
            isARepeat: isARepeat
        )
    }
}

final class HighlightsSaveScanTriggerTests: XCTestCase {
    private let root = "/vault"
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    func testNoChangeUsesFallbackAndFiresExactlyOnce() {
        var trigger = HighlightsSaveScanTrigger(vaultRoot: root)
        trigger.keyPressed(at: base)
        XCTAssertEqual(trigger.nextDeadline, base.addingTimeInterval(2.5))
        XCTAssertFalse(trigger.poll(at: base.addingTimeInterval(2.49)))
        XCTAssertTrue(trigger.poll(at: base.addingTimeInterval(2.5)))
        XCTAssertFalse(trigger.poll(at: base.addingTimeInterval(3)))
        XCTAssertNil(trigger.nextDeadline)
    }

    func testRelevantChangeUsesQuietPeriod() {
        var trigger = HighlightsSaveScanTrigger(vaultRoot: root)
        trigger.keyPressed(at: base)
        trigger.libraryChanged(
            VaultChangeBatch(paths: ["/vault/lib/book.pdf"]),
            at: base.addingTimeInterval(0.4)
        )
        XCTAssertEqual(trigger.nextDeadline, base.addingTimeInterval(1.4))
        XCTAssertFalse(trigger.poll(at: base.addingTimeInterval(1.39)))
        XCTAssertTrue(trigger.poll(at: base.addingTimeInterval(1.4)))
    }

    func testContinuousChangesFireAtCap() {
        var trigger = HighlightsSaveScanTrigger(vaultRoot: root)
        trigger.keyPressed(at: base)
        for second in stride(from: 0.5, through: 9.5, by: 0.5) {
            trigger.libraryChanged(
                VaultChangeBatch(paths: ["/vault/lib/book.pdf"]),
                at: base.addingTimeInterval(second)
            )
        }
        XCTAssertEqual(trigger.nextDeadline, base.addingTimeInterval(10))
        XCTAssertTrue(trigger.poll(at: base.addingTimeInterval(10)))
    }

    func testRepeatedSaveCoalescesAndExtendsOnlyFallback() {
        var trigger = HighlightsSaveScanTrigger(vaultRoot: root)
        trigger.keyPressed(at: base)
        trigger.keyPressed(at: base.addingTimeInterval(2))
        XCTAssertEqual(trigger.nextDeadline, base.addingTimeInterval(4.5))
        XCTAssertTrue(trigger.poll(at: base.addingTimeInterval(4.5)))
        XCTAssertFalse(trigger.poll(at: base.addingTimeInterval(5)))

        trigger.keyPressed(at: base.addingTimeInterval(10))
        trigger.keyPressed(at: base.addingTimeInterval(15))
        XCTAssertEqual(trigger.nextDeadline, base.addingTimeInterval(17.5))
    }

    func testPathsBeforeArmingHiddenAndOutsideLibraryAreIgnored() {
        var trigger = HighlightsSaveScanTrigger(vaultRoot: root)
        trigger.libraryChanged(
            VaultChangeBatch(paths: ["/vault/lib/book.pdf"]), at: base
        )
        trigger.keyPressed(at: base)
        trigger.libraryChanged(
            VaultChangeBatch(paths: ["/vault/.git/lib/book.pdf"]),
            at: base.addingTimeInterval(0.1)
        )
        trigger.libraryChanged(
            VaultChangeBatch(paths: ["/vault/ref/book.md"]),
            at: base.addingTimeInterval(0.2)
        )
        XCTAssertEqual(trigger.nextDeadline, base.addingTimeInterval(2.5))
    }

    func testIncompleteBatchesAreRelevant() {
        let flags: [VaultChangeFlags] = [
            .mustScanSubDirs, .rootChanged, .kernelDropped, .userDropped,
        ]
        for flag in flags {
            var trigger = HighlightsSaveScanTrigger(vaultRoot: root)
            trigger.keyPressed(at: base)
            trigger.libraryChanged(
                VaultChangeBatch(paths: ["/vault/.git/index"], flags: flag),
                at: base.addingTimeInterval(0.25)
            )
            XCTAssertEqual(trigger.nextDeadline, base.addingTimeInterval(1.25))
        }
    }

    func testLibraryChangesWithoutKeypressNeverArmOrFire() {
        var trigger = HighlightsSaveScanTrigger(vaultRoot: root)
        trigger.libraryChanged(
            VaultChangeBatch(paths: ["/vault/lib/book.pdf"]), at: base
        )
        XCTAssertNil(trigger.nextDeadline)
        XCTAssertFalse(trigger.poll(at: base.addingTimeInterval(100)))
    }

    func testDisarmCancelsPendingCycle() {
        var trigger = HighlightsSaveScanTrigger(vaultRoot: root)
        trigger.keyPressed(at: base)
        trigger.disarm()
        XCTAssertNil(trigger.nextDeadline)
        XCTAssertFalse(trigger.poll(at: base.addingTimeInterval(100)))
    }
}

final class HighlightsSaveScanScopeTests: XCTestCase {
    func testLibraryDirectoriesAndOutsidePath() {
        XCTAssertEqual(
            HighlightsSaveScanScope.isLibraryDocument(
                path: "/vault/lib/book.pdf", vaultRoot: "/vault"
            ),
            true
        )
        XCTAssertEqual(
            HighlightsSaveScanScope.isLibraryDocument(
                path: "/vault/xlib/pending/book.pdf", vaultRoot: "/vault"
            ),
            true
        )
        XCTAssertEqual(
            HighlightsSaveScanScope.isLibraryDocument(
                path: "/vault/ref/book.pdf", vaultRoot: "/vault"
            ),
            false
        )
        XCTAssertNil(
            HighlightsSaveScanScope.isLibraryDocument(path: nil, vaultRoot: "/vault")
        )
    }

    func testSymlinkedRootResolvesAndParentEscapeIsOutside() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let realVault = temporaryRoot.appendingPathComponent("real-vault")
        let vaultAlias = temporaryRoot.appendingPathComponent("vault-alias")
        try FileManager.default.createDirectory(
            at: realVault.appendingPathComponent("lib"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: vaultAlias,
            withDestinationURL: realVault
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        XCTAssertEqual(
            HighlightsSaveScanScope.isLibraryDocument(
                path: vaultAlias.appendingPathComponent("lib/book.pdf").path,
                vaultRoot: vaultAlias.path
            ),
            true
        )
        XCTAssertEqual(
            HighlightsSaveScanScope.isLibraryDocument(
                path: vaultAlias.appendingPathComponent("lib/../../outside.pdf").path,
                vaultRoot: vaultAlias.path
            ),
            false
        )
    }
}
