import Foundation
import XCTest

@testable import RefsCore

/// Today tests: composite `(path, block_id)` join, first-occurrence
/// dedupe, Pomodoro names, and the older-`bob` note-path fallback.
final class RefsTodayTests: XCTestCase {
    func testPlanFixtureOrdersTodayEntriesByCompositeKey() throws {
        let data = try RefsModelTests.fixtureData("refs-plan.json")
        let plan = try JSONDecoder().decode(RefsPlanResponse.self, from: data)
        let today = RefsToday(plan: plan)

        // Every fixture row carries a `block_id`, so all four land in
        // the composite join and the path fallback stays empty.
        XCTAssertEqual(today.taskEntries.count, 4)
        XCTAssertTrue(today.entries.isEmpty)
        XCTAssertEqual(
            today.taskEntries["ref/chat/omnigent_review_notes.md#ref"]?.order,
            0
        )
        XCTAssertEqual(
            today.taskEntries["ref/chat/blog_post_retrospective.md#ref"]?.order,
            1
        )
        XCTAssertEqual(
            today.taskEntries["ref/chat/shipping_second_post.md#ref"]?.order,
            2
        )
        XCTAssertEqual(today.taskEntries["sase.md#ref"]?.order, 3)
        XCTAssertEqual(
            today.taskEntries["ref/chat/omnigent_review_notes.md#ref"]?.pomodoroName,
            "BLOG"
        )
        XCTAssertEqual(today.taskEntries["sase.md#ref"]?.pomodoroName, "GTD")
    }

    func testFirstOccurrenceWinsDuplicates() {
        let plan = RefsPlanResponse(schemaVersion: 2, todayTasks: [
            RefsPlanTodayTask(path: "ref/chat/x.md", entryName: "BLOG"),
            RefsPlanTodayTask(path: "ref/chat/x.md", entryName: "LATER"),
        ])

        let today = RefsToday(plan: plan)

        XCTAssertEqual(today.entries.count, 1)
        XCTAssertEqual(today.entries["ref/chat/x.md"]?.order, 0)
        XCTAssertEqual(today.entries["ref/chat/x.md"]?.pomodoroName, "BLOG")
    }

    func testFirstOccurrenceWinsCompositeDuplicates() {
        let plan = RefsPlanResponse(schemaVersion: 2, todayTasks: [
            RefsPlanTodayTask(path: "sase.md", blockID: "ref-a", entryName: "BLOG"),
            RefsPlanTodayTask(path: "sase.md", blockID: "ref-a", entryName: "LATER"),
        ])

        let today = RefsToday(plan: plan)

        XCTAssertEqual(today.taskEntries.count, 1)
        XCTAssertEqual(today.taskEntries["sase.md#ref-a"]?.pomodoroName, "BLOG")
    }

    func testEmptyPlanYieldsEmptyToday() {
        let today = RefsToday(plan: RefsPlanResponse(schemaVersion: 2))
        XCTAssertTrue(today.entries.isEmpty)
        XCTAssertTrue(today.taskEntries.isEmpty)
    }

    func testV2JoinMatchesOnlyTheLinkedTaskInASharedNote() throws {
        let list = try JSONDecoder().decode(
            RefsListResponse.self,
            from: RefsModelTests.fixtureData("refs-list-v2.json")
        )
        let plan = try JSONDecoder().decode(
            RefsPlanResponse.self,
            from: RefsModelTests.fixtureData("refs-plan-v2.json")
        )
        let today = RefsToday(plan: plan)
        let items = RefsCatalog.items(
            from: RefsSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1),
                records: list.refs
            )
        )
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        // Only first_essay is linked from Today; second_essay shares
        // sase.md but must not light up on the note path alone.
        let first = try XCTUnwrap(byID["ref/chat/first_essay.md"])
        let second = try XCTUnwrap(byID["ref/chat/second_essay.md"])
        XCTAssertEqual(today.entry(for: first)?.pomodoroName, "GTD")
        XCTAssertNil(today.entry(for: second))

        // The frozen v1 tracker still joins on its in-note `^ref`.
        let frozen = try XCTUnwrap(byID["ref/chat/frozen_tracker.md"])
        XCTAssertEqual(today.entry(for: frozen)?.pomodoroName, "GTD")
    }

    func testOlderBobRowsFallBackToTheNotePathJoin() throws {
        let record = try JSONDecoder().decode(
            RefRecord.self,
            from: Data("""
            {"path":"ref/chat/x.md","link":"[[ref/chat/x]]","title":"X",
             "source_pdf":"lib/chat/x.pdf"}
            """.utf8)
        )
        let plan = RefsPlanResponse(schemaVersion: 2, todayTasks: [
            RefsPlanTodayTask(path: "ref/chat/x.md", entryName: "BLOG"),
        ])

        XCTAssertEqual(RefsToday(plan: plan).entry(for: record)?.pomodoroName, "BLOG")
    }

    func testTaskWithoutBlockIDFallsBackToTheNotePathJoin() throws {
        let record = try JSONDecoder().decode(
            RefRecord.self,
            from: Data("""
            {"path":"ref/chat/x.md","link":"[[ref/chat/x]]","title":"X",
             "source_pdf":"lib/chat/x.pdf",
             "task":{"path":"sase.md","mark":"*","archived":false}}
            """.utf8)
        )
        let plan = RefsPlanResponse(schemaVersion: 2, todayTasks: [
            RefsPlanTodayTask(path: "ref/chat/x.md", entryName: "BLOG"),
        ])

        XCTAssertEqual(RefsToday(plan: plan).entry(for: record)?.pomodoroName, "BLOG")
    }

    func testTodayRoundTripsThroughTheSnapshotStore() throws {
        let data = try RefsModelTests.fixtureData("refs-plan.json")
        let plan = try JSONDecoder().decode(RefsPlanResponse.self, from: data)
        let today = RefsToday(plan: plan)

        let encoded = try RefsStoreCodecs.encoder().encode(today)
        let roundTripped = try RefsStoreCodecs.decoder().decode(RefsToday.self, from: encoded)

        XCTAssertEqual(roundTripped, today)
    }

    func testOlderCacheWithoutTaskEntriesStillDecodes() throws {
        let legacy = try JSONDecoder().decode(
            RefsToday.self,
            from: Data("""
            {"entries":{"sase.md":{"order":0,"pomodoroName":"GTD"}}}
            """.utf8)
        )

        XCTAssertEqual(legacy.entries["sase.md"]?.pomodoroName, "GTD")
        XCTAssertTrue(legacy.taskEntries.isEmpty)
    }
}
