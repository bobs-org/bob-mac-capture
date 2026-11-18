import XCTest

@testable import CaptureCore

final class WalkAttentionRefreshPolicyTests: XCTestCase {
    func testShowRefreshesWhenDirtyNeverRefreshedOrStale() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(
            WalkAttentionRefreshPolicy.shouldRefreshOnShow(
                dirty: true, lastSuccess: now, now: now))
        XCTAssertTrue(
            WalkAttentionRefreshPolicy.shouldRefreshOnShow(
                dirty: false, lastSuccess: nil, now: now))
        XCTAssertTrue(
            WalkAttentionRefreshPolicy.shouldRefreshOnShow(
                dirty: false,
                lastSuccess: now.addingTimeInterval(-60),
                now: now))
        XCTAssertTrue(
            WalkAttentionRefreshPolicy.shouldRefreshOnShow(
                dirty: false,
                lastSuccess: now.addingTimeInterval(-61),
                now: now))
    }

    func testShowPaintsCacheWhenFresh() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(
            WalkAttentionRefreshPolicy.shouldRefreshOnShow(
                dirty: false,
                lastSuccess: now.addingTimeInterval(-59),
                now: now))
        XCTAssertFalse(
            WalkAttentionRefreshPolicy.shouldRefreshOnShow(
                dirty: false, lastSuccess: now, now: now))
    }

    func testDebounceIntervalsMatchNamedConstants() {
        XCTAssertEqual(WalkAttentionRefreshPolicy.visibleDebounce, 2)
        XCTAssertEqual(WalkAttentionRefreshPolicy.hiddenDebounce, 10)
        XCTAssertEqual(WalkAttentionRefreshPolicy.debounceInterval(visible: true), 2)
        XCTAssertEqual(WalkAttentionRefreshPolicy.debounceInterval(visible: false), 10)
        XCTAssertEqual(WalkAttentionRefreshPolicy.showStaleAfter, 60)
    }

    func testSingleFlightReusesAgendaRefreshState() {
        var state = CaptureAgendaRefreshState()
        XCTAssertNotNil(state.begin())
        // One refresh in flight with at most one follow-up.
        XCTAssertNil(state.begin())
        XCTAssertNil(state.begin())
        XCTAssertTrue(state.followUpQueued)
        XCTAssertEqual(state.end(generation: state.generation), .followUp)
    }

    func testWalksDateGuardOnSharedState() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/walks-all.json")
        let snapshot = try JSONDecoder().decode(
            WalkAttentionSnapshot.self,
            from: Data(contentsOf: url)
        )
        var state = CaptureAgendaRefreshState()
        state.today = { "2026-11-17" }
        XCTAssertTrue(state.isCurrent(snapshot))
        state.today = { "2026-11-18" }
        XCTAssertFalse(state.isCurrent(snapshot))
        state.today = { "2026-11-17" }
        XCTAssertFalse(state.isCurrent(WalkAttentionSnapshot()))
    }
}
