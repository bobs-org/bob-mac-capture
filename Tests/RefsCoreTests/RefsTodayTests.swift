import Foundation
import XCTest

@testable import RefsCore

/// Today tests: ledger order, first-occurrence dedupe, and Pomodoro names.
final class RefsTodayTests: XCTestCase {
    func testPlanFixtureOrdersTodayEntries() throws {
        let data = try RefsModelTests.fixtureData("refs-plan.json")
        let plan = try JSONDecoder().decode(RefsPlanResponse.self, from: data)
        let today = RefsToday(plan: plan)

        XCTAssertEqual(today.entries.count, 4)
        XCTAssertEqual(today.entries["ref/chat/omnigent_review_notes.md"]?.order, 0)
        XCTAssertEqual(today.entries["ref/chat/blog_post_retrospective.md"]?.order, 1)
        XCTAssertEqual(today.entries["ref/chat/shipping_second_post.md"]?.order, 2)
        XCTAssertEqual(today.entries["sase.md"]?.order, 3)
        XCTAssertEqual(
            today.entries["ref/chat/omnigent_review_notes.md"]?.pomodoroName,
            "BLOG"
        )
        XCTAssertEqual(today.entries["sase.md"]?.pomodoroName, "GTD")
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

    func testEmptyPlanYieldsEmptyToday() {
        XCTAssertTrue(RefsToday(plan: RefsPlanResponse(schemaVersion: 2)).entries.isEmpty)
    }

    func testTodayRoundTripsThroughTheSnapshotStore() throws {
        let data = try RefsModelTests.fixtureData("refs-plan.json")
        let plan = try JSONDecoder().decode(RefsPlanResponse.self, from: data)
        let today = RefsToday(plan: plan)

        let encoded = try RefsStoreCodecs.encoder().encode(today)
        let roundTripped = try RefsStoreCodecs.decoder().decode(RefsToday.self, from: encoded)

        XCTAssertEqual(roundTripped, today)
    }
}
