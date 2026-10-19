import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

final class RefsWatcherRelevanceTests: XCTestCase {
    private let root = "/vault"

    func testDotPathOnlyBatchesAreIgnored() {
        let batches = [
            VaultChangeBatch(paths: ["/vault/.git/index"]),
            VaultChangeBatch(
                paths: ["/vault/.git/refs/remotes/origin"],
                flags: [.itemIsDir]
            ),
            VaultChangeBatch(paths: ["/vault/.obsidian/workspace.json"]),
            VaultChangeBatch(paths: ["/vault/.trash/old.pdf"]),
        ]

        for batch in batches {
            XCTAssertFalse(
                RefsWatcherRelevance.isRelevant(batch, vaultRoot: root),
                "expected hidden-only batch to be ignored: \(batch.paths)"
            )
        }
    }

    func testVisiblePathsAndConservativeBatchesAreRelevant() {
        let batches = [
            VaultChangeBatch(paths: ["/vault/ref/x.md"]),
            VaultChangeBatch(paths: ["/vault/lib/y.pdf"]),
            VaultChangeBatch(paths: ["/vault/inbox.md"]),
            VaultChangeBatch(paths: ["/vault/done/z.md"]),
            VaultChangeBatch(paths: ["/vault/.git/index", "/vault/ref/x.md"]),
            VaultChangeBatch(paths: ["/other/ref/x.md"]),
            VaultChangeBatch(),
        ]

        for batch in batches {
            XCTAssertTrue(
                RefsWatcherRelevance.isRelevant(batch, vaultRoot: root),
                "expected conservative/visible batch to refresh: \(batch.paths)"
            )
        }
    }

    func testRescanAndDroppedFlagsAreAlwaysRelevant() {
        let flags: [VaultChangeFlags] = [
            .mustScanSubDirs,
            .rootChanged,
            .kernelDropped,
            .userDropped,
        ]

        for flag in flags {
            XCTAssertTrue(
                RefsWatcherRelevance.isRelevant(
                    VaultChangeBatch(paths: ["/vault/.git/index"], flags: flag),
                    vaultRoot: root
                )
            )
        }
    }

    func testResolvedVaultRootMatchesEventsThroughSymlink() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let realVault = temporaryRoot.appendingPathComponent("real-vault")
        let vaultAlias = temporaryRoot.appendingPathComponent("vault-alias")
        try FileManager.default.createDirectory(
            at: realVault,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: vaultAlias,
            withDestinationURL: realVault
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let batch = VaultChangeBatch(
            paths: [realVault.appendingPathComponent("lib/book.pdf").path]
        )
        XCTAssertTrue(
            RefsWatcherRelevance.isRelevant(batch, vaultRoot: vaultAlias.path)
        )
    }
}
