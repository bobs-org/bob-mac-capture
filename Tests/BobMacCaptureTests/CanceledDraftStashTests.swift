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
        let expected = Array("1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)

        XCTAssertEqual((0..<36).compactMap(CanceledDraftStash.accelerator(for:)), expected)
        XCTAssertNil(CanceledDraftStash.accelerator(for: 36))
        XCTAssertEqual(CanceledDraftStash.acceleratorIndex(for: "1", entryCount: 36), 0)
        XCTAssertEqual(CanceledDraftStash.acceleratorIndex(for: "0", entryCount: 36), 9)
        XCTAssertEqual(CanceledDraftStash.acceleratorIndex(for: "a", entryCount: 36), 10)
        XCTAssertEqual(CanceledDraftStash.acceleratorIndex(for: "Z", entryCount: 36), 35)
        XCTAssertNil(CanceledDraftStash.acceleratorIndex(for: "Z", entryCount: 35))
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
}
