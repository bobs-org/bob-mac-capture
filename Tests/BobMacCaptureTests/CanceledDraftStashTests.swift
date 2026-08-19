import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class CanceledDraftStashTests: XCTestCase {
    func testPushPreservesExactUnicodeMultilineTextNewestFirstAndDuplicates() {
        let stash = CanceledDraftStash(capacity: 10)
        let text = "  café\n- 子 task\n"

        let first = stash.push(text)
        let second = stash.push(text)

        XCTAssertEqual(stash.entries.map(\.text), [text, text])
        XCTAssertNotEqual(first?.id, second?.id)
        XCTAssertGreaterThanOrEqual(
            stash.entries.first?.createdAt ?? .distantPast,
            stash.entries.last?.createdAt ?? .distantFuture
        )
    }

    func testOverflowEvictsOldestEntries() {
        let stash = CanceledDraftStash(capacity: 2)

        stash.push("oldest")
        stash.push("middle")
        stash.push("newest")

        XCTAssertEqual(stash.entries.map(\.text), ["newest", "middle"])
    }

    func testRemoveByIdentityPopsOnlyTheChosenEntry() throws {
        let stash = CanceledDraftStash(capacity: 5)
        let old = try XCTUnwrap(stash.push("old"))
        let middle = try XCTUnwrap(stash.push("middle"))
        let new = try XCTUnwrap(stash.push("new"))

        let removed = stash.remove(id: middle.id)

        XCTAssertEqual(removed, middle)
        XCTAssertEqual(stash.entries, [new, old])
    }

    func testCapacityReductionKeepsNewestEntriesAndZeroDisablesStorage() {
        let stash = CanceledDraftStash(capacity: 4)
        stash.push("one")
        stash.push("two")
        stash.push("three")
        stash.push("four")

        stash.updateCapacity(2)
        XCTAssertEqual(stash.entries.map(\.text), ["four", "three"])

        stash.updateCapacity(0)
        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertNil(stash.push("ignored"))
        XCTAssertTrue(stash.entries.isEmpty)
    }

    func testClearAndSelectionHelpersAreBounded() {
        let stash = CanceledDraftStash(capacity: 3)
        stash.push("one")
        stash.push("two")
        stash.push("three")

        XCTAssertEqual(stash.clampedSelectionIndex(-10), 0)
        XCTAssertEqual(stash.clampedSelectionIndex(99), 2)
        XCTAssertEqual(stash.nextSelectionIndex(after: 2), 0)
        XCTAssertEqual(stash.previousSelectionIndex(before: 0), 2)

        stash.clear()
        XCTAssertEqual(stash.clampedSelectionIndex(2), 0)
        XCTAssertEqual(stash.nextSelectionIndex(after: 2), 0)
        XCTAssertEqual(stash.previousSelectionIndex(before: 2), 0)
    }

    func testAcceleratorsCoverAllThirtySixSlots() {
        let expected = Array("1234567890ABC-EFGHIJKLMNOPQRSTUVWXYZ").map(String.init)

        XCTAssertEqual((0..<36).compactMap(CanceledDraftStash.accelerator(for:)), expected)
        XCTAssertEqual(Set(expected).count, 36)
        XCTAssertFalse(expected.contains("D"))
        XCTAssertNil(CanceledDraftStash.accelerator(for: 36))
        XCTAssertEqual(CanceledDraftStash.acceleratorIndex(for: "1", entryCount: 36), 0)
        XCTAssertEqual(CanceledDraftStash.acceleratorIndex(for: "0", entryCount: 36), 9)
        XCTAssertEqual(CanceledDraftStash.acceleratorIndex(for: "a", entryCount: 36), 10)
        XCTAssertEqual(CanceledDraftStash.acceleratorIndex(for: "-", entryCount: 36), 13)
        XCTAssertNil(CanceledDraftStash.acceleratorIndex(for: "d", entryCount: 36))
        XCTAssertNil(CanceledDraftStash.acceleratorIndex(for: "D", entryCount: 36))
        XCTAssertEqual(CanceledDraftStash.acceleratorIndex(for: "E", entryCount: 36), 14)
        XCTAssertEqual(CanceledDraftStash.acceleratorIndex(for: "N", entryCount: 36), 23)
        XCTAssertEqual(CanceledDraftStash.acceleratorIndex(for: "Z", entryCount: 36), 35)
        XCTAssertNil(CanceledDraftStash.acceleratorIndex(for: "Z", entryCount: 35))
        XCTAssertNil(CanceledDraftStash.acceleratorIndex(for: "-", entryCount: 13))
        XCTAssertNil(CanceledDraftStash.acceleratorIndex(for: "é", entryCount: 36))
    }

    func testPreviewAndMetadataFormattingDoNotMutatePayload() throws {
        let text = "\n   \n  This is a deliberately long first meaningful line with café and preserved spacing\nsecond"
        let entry = CanceledDraftEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            text: text,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        let preview = CanceledDraftStash.previewLine(for: entry.text, maxCharacters: 25)
        let metadata = CanceledDraftStash.metadataDescription(
            for: entry,
            now: Date(timeIntervalSince1970: 1_180)
        )

        XCTAssertEqual(preview, "This is a deliberately...")
        XCTAssertEqual(metadata, "4 lines - 3m ago")
        XCTAssertEqual(entry.text, text)
    }

    func testInitLoadsPersistedEntriesNewestFirst() {
        let drafts = [
            samplePersistedDraft(text: "newest", createdAt: Date(timeIntervalSince1970: 3)),
            samplePersistedDraft(text: "middle", createdAt: Date(timeIntervalSince1970: 2)),
            samplePersistedDraft(text: "oldest", createdAt: Date(timeIntervalSince1970: 1)),
        ]
        let store = RecordingCanceledDraftStashStore(drafts: drafts)

        let stash = CanceledDraftStash(capacity: 10, store: store)

        XCTAssertEqual(stash.entries.map(\.text), ["newest", "middle", "oldest"])
        XCTAssertEqual(stash.entries.map(\.id), drafts.map(\.id))
        XCTAssertEqual(stash.entries.map(\.createdAt), drafts.map(\.createdAt))
        XCTAssertTrue(store.snapshots.isEmpty)
    }

    func testInitTrimsOverflowAndPersistsImmediately() {
        let drafts = [
            samplePersistedDraft(text: "newest", createdAt: Date(timeIntervalSince1970: 4)),
            samplePersistedDraft(text: "kept", createdAt: Date(timeIntervalSince1970: 3)),
            samplePersistedDraft(text: "dropped", createdAt: Date(timeIntervalSince1970: 2)),
            samplePersistedDraft(text: "oldest", createdAt: Date(timeIntervalSince1970: 1)),
        ]
        let store = RecordingCanceledDraftStashStore(drafts: drafts)

        let stash = CanceledDraftStash(capacity: 2, store: store)

        XCTAssertEqual(stash.entries.map(\.text), ["newest", "kept"])
        XCTAssertEqual(store.snapshots.last?.map(\.text), ["newest", "kept"])
        XCTAssertEqual(store.snapshots.last?.map(\.id), Array(drafts.prefix(2).map(\.id)))
    }

    func testInitWithCapacityZeroDoesNotLoadAndSavesEmpty() {
        let store = RecordingCanceledDraftStashStore(
            drafts: [samplePersistedDraft(text: "should not load")]
        )

        let stash = CanceledDraftStash(capacity: 0, store: store)

        XCTAssertEqual(store.loadCount, 0)
        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertEqual(store.snapshots, [[]])
    }

    func testMutationsWriteThroughAndMatchPublishedEntries() throws {
        let store = RecordingCanceledDraftStashStore()
        let stash = CanceledDraftStash(capacity: 10, store: store)

        let first = try XCTUnwrap(stash.push("first"))
        XCTAssertEqual(store.snapshots.last, persisted(stash.entries))

        let second = try XCTUnwrap(stash.push("second"))
        XCTAssertEqual(store.snapshots.last, persisted(stash.entries))
        XCTAssertEqual(store.snapshots.last?.map(\.text), ["second", "first"])

        XCTAssertEqual(stash.remove(id: first.id), first)
        XCTAssertEqual(store.snapshots.last, persisted(stash.entries))
        XCTAssertEqual(store.snapshots.last?.map(\.id), [second.id])

        stash.clear()
        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertEqual(store.snapshots.last, [])
        XCTAssertEqual(store.snapshots.last, persisted(stash.entries))
    }

    func testUpdateCapacityZeroEmptiesMemoryAndRecordsEmptySave() {
        let store = RecordingCanceledDraftStashStore()
        let stash = CanceledDraftStash(capacity: 10, store: store)
        stash.push("retained")

        stash.updateCapacity(0)

        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertEqual(store.snapshots.last, [])
        XCTAssertNil(stash.push("ignored"))
        XCTAssertEqual(store.snapshots.last, [])
    }

    func testUnreadableStoreLeavesStashEmptyAndForwardsMessage() {
        let message = FileCanceledDraftStashStore.unreadableQuarantinedMessage
        let store = RecordingCanceledDraftStashStore(
            drafts: [samplePersistedDraft(text: "secret")]
        )
        store.loadErrorMessage = message

        let stash = CanceledDraftStash(capacity: 10, store: store)

        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertEqual(store.messages, [message])
        XCTAssertTrue(store.snapshots.isEmpty)
    }

    private func samplePersistedDraft(
        text: String,
        createdAt: Date = Date(timeIntervalSince1970: 1)
    ) -> PersistedCanceledDraft {
        PersistedCanceledDraft(id: UUID(), text: text, createdAt: createdAt)
    }

    private func persisted(_ entries: [CanceledDraftEntry]) -> [PersistedCanceledDraft] {
        entries.map { PersistedCanceledDraft(id: $0.id, text: $0.text, createdAt: $0.createdAt) }
    }
}

final class RecordingCanceledDraftStashStore: CanceledDraftStashStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var drafts: [PersistedCanceledDraft]
    private var recordedSnapshots: [[PersistedCanceledDraft]] = []
    private var recordedMessages: [String] = []
    private var recordedLoadCount = 0
    var loadErrorMessage: String?

    init(drafts: [PersistedCanceledDraft] = []) {
        self.drafts = drafts
    }

    var snapshots: [[PersistedCanceledDraft]] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSnapshots
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedLoadCount
    }

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedMessages
    }

    func load() -> [PersistedCanceledDraft] {
        lock.lock()
        recordedLoadCount += 1
        let message = loadErrorMessage
        let result = drafts
        if let message {
            recordedMessages.append(message)
            lock.unlock()
            return []
        }
        lock.unlock()
        return result
    }

    func save(_ drafts: [PersistedCanceledDraft]) {
        lock.lock()
        recordedSnapshots.append(drafts)
        self.drafts = drafts
        lock.unlock()
    }
}
