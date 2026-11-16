import XCTest

@testable import CaptureCore

/// Warm-snapshot rules for the `/` ⇄ `//` no-blink swap: fill, trust,
/// staleness, content-diff replacement, and vault relevance. The store is
/// pure value logic so it runs on Linux under `just portable-check`.
final class NoteGotoSnapshotStoreTests: XCTestCase {
    private func candidate(_ path: String) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            detail: nil,
            kind: "note",
            matchKeys: [path],
            rank: 4,
            hue: nil,
            status: nil,
            title: path,
            depth: nil,
            group: nil,
            notePath: path
        )
    }

    private func noteGoto(listed: Int = 2) -> CaptureCompletionNoteGoto {
        CaptureCompletionNoteGoto(vaultRoot: "/vault", listed: listed)
    }

    func testEmptyStoreRendersNothingAndNeedsRefresh() {
        let store = NoteGotoSnapshotStore()
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(store.rows(bobIdentity: "bob-1"))
        XCTAssertTrue(store.needsRefresh(bobIdentity: "bob-1"))
    }

    func testStoredSnapshotRendersForSameIdentityUntilStale() {
        var store = NoteGotoSnapshotStore(stalenessInterval: 60)
        let now = Date()
        store.store(
            candidates: [candidate("a.md")],
            noteGoto: noteGoto(),
            bobIdentity: "bob-1",
            now: now
        )
        XCTAssertFalse(store.isEmpty)
        XCTAssertEqual(store.rows(bobIdentity: "bob-1", now: now)?.candidates.map(\.notePath), ["a.md"])
        XCTAssertFalse(store.needsRefresh(bobIdentity: "bob-1", now: now))
        XCTAssertFalse(
            store.needsRefresh(bobIdentity: "bob-1", now: now.addingTimeInterval(59))
        )
        XCTAssertTrue(
            store.needsRefresh(bobIdentity: "bob-1", now: now.addingTimeInterval(60))
        )
    }

    func testOtherBobIdentityNeverRendersAndAlwaysRefreshes() {
        var store = NoteGotoSnapshotStore()
        store.store(
            candidates: [candidate("a.md")],
            noteGoto: noteGoto(),
            bobIdentity: "bob-1"
        )
        XCTAssertNil(store.rows(bobIdentity: "bob-2"))
        XCTAssertTrue(store.needsRefresh(bobIdentity: "bob-2"))
    }

    func testInvalidateEmptiesTheStore() {
        var store = NoteGotoSnapshotStore()
        store.store(
            candidates: [candidate("a.md")],
            noteGoto: noteGoto(),
            bobIdentity: "bob-1"
        )
        store.invalidate()
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(store.needsRefresh(bobIdentity: "bob-1"))
    }

    func testArchivedCatalogNeverReplacesTheWarmLivingSnapshot() {
        var store = NoteGotoSnapshotStore()
        store.store(
            candidates: [candidate("Areas/cash.md")],
            noteGoto: noteGoto(),
            bobIdentity: "bob-1"
        )
        store.store(
            candidates: [candidate("done/a_done.md")],
            noteGoto: CaptureCompletionNoteGoto(vaultRoot: "/vault", listed: 1, archived: true),
            bobIdentity: "bob-1"
        )
        XCTAssertEqual(
            store.rows(bobIdentity: "bob-1")?.candidates.map(\.notePath),
            ["Areas/cash.md"]
        )
        XCTAssertEqual(store.rows(bobIdentity: "bob-1")?.noteGoto.archived, false)
    }

    func testContentDiffDetectsReplacementVsIdenticalRows() {
        var store = NoteGotoSnapshotStore()
        let candidates = [candidate("a.md"), candidate("b.md")]
        let meta = noteGoto(listed: 2)
        store.store(candidates: candidates, noteGoto: meta, bobIdentity: "bob-1")
        let snapshot = try? XCTUnwrap(store.rows(bobIdentity: "bob-1"))
        XCTAssertNotNil(snapshot)
        XCTAssertFalse(
            NoteGotoSnapshotStore.contentDiffers(
                snapshot!,
                candidates: candidates,
                noteGoto: meta
            )
        )
        XCTAssertTrue(
            NoteGotoSnapshotStore.contentDiffers(
                snapshot!,
                candidates: [candidate("a.md")],
                noteGoto: meta
            )
        )
        XCTAssertTrue(
            NoteGotoSnapshotStore.contentDiffers(
                snapshot!,
                candidates: candidates,
                noteGoto: noteGoto(listed: 3)
            )
        )
        // Order matters: Bob's canonical order is part of the contract.
        XCTAssertTrue(
            NoteGotoSnapshotStore.contentDiffers(
                snapshot!,
                candidates: [candidate("b.md"), candidate("a.md")],
                noteGoto: meta
            )
        )
    }

    func testSelectionRetentionKeepsTheSameNotePath() {
        let ids = ["a.md", "b.md", "c.md"]
        XCTAssertEqual(CapturePickerNavigation.resolvedSelection(preferred: "b.md", in: ids), "b.md")
        XCTAssertEqual(CapturePickerNavigation.resolvedSelection(preferred: "gone.md", in: ids), "a.md")
        XCTAssertNil(CapturePickerNavigation.resolvedSelection(preferred: "b.md", in: []))
    }

    func testRelevanceIgnoresDotPathsAndNonNotes() {
        let root = "/vault"
        XCTAssertFalse(
            NoteGotoSnapshotStore.isRelevant(VaultChangeBatch(paths: [], flags: []), vaultRoot: root)
        )
        XCTAssertFalse(
            NoteGotoSnapshotStore.isRelevant(
                VaultChangeBatch(paths: ["/vault/.git/refs/heads/m.md"], flags: []),
                vaultRoot: root
            )
        )
        XCTAssertFalse(
            NoteGotoSnapshotStore.isRelevant(
                VaultChangeBatch(paths: ["/vault/.obsidian/workspace.json"], flags: []),
                vaultRoot: root
            )
        )
        XCTAssertFalse(
            NoteGotoSnapshotStore.isRelevant(
                VaultChangeBatch(paths: ["/vault/lib/papers/p.pdf"], flags: []),
                vaultRoot: root
            )
        )
        XCTAssertTrue(
            NoteGotoSnapshotStore.isRelevant(
                VaultChangeBatch(paths: ["/vault/Areas/cash.md"], flags: []),
                vaultRoot: root
            )
        )
        XCTAssertTrue(
            NoteGotoSnapshotStore.isRelevant(
                VaultChangeBatch(paths: ["/vault/Views/Monthly.base"], flags: []),
                vaultRoot: root
            )
        )
        XCTAssertTrue(
            NoteGotoSnapshotStore.isRelevant(
                VaultChangeBatch(paths: ["/vault/Areas/cash.md"], flags: [.itemRenamed]),
                vaultRoot: root
            )
        )
        XCTAssertTrue(
            NoteGotoSnapshotStore.isRelevant(
                VaultChangeBatch(paths: ["/vault/img/a.png"], flags: [.mustScanSubDirs]),
                vaultRoot: root
            )
        )
    }

    func testLoadingAndUnavailableStatesStayDistinct() {
        XCTAssertEqual(CapturePickerEmptyState.loadingNotes.title, "Loading notes…")
        XCTAssertEqual(CapturePickerEmptyState.notesUnavailable.title, "Couldn't load notes")
        XCTAssertNotEqual(
            CapturePickerEmptyState.loadingNotes.message,
            CapturePickerEmptyState.noMatches(query: "cash").message
        )
        XCTAssertNotEqual(
            CapturePickerEmptyState.notesUnavailable.message,
            CapturePickerEmptyState.noMatches(query: "cash").message
        )
    }
}
