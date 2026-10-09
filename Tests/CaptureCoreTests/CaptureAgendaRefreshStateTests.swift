import XCTest

@testable import CaptureCore

final class CaptureAgendaRefreshStateTests: XCTestCase {
    func testFirstBeginStartsRefresh() {
        var state = CaptureAgendaRefreshState()
        let generation = state.begin()
        XCTAssertNotNil(generation)
        XCTAssertTrue(state.isRefreshing)
        XCTAssertFalse(state.followUpQueued)
    }

    func testBeginDuringRefreshQueuesExactlyOneFollowUp() {
        var state = CaptureAgendaRefreshState()
        XCTAssertNotNil(state.begin())
        XCTAssertNil(state.begin())
        XCTAssertNil(state.begin())
        XCTAssertTrue(state.followUpQueued)
        XCTAssertEqual(state.end(generation: state.generation), .followUp)
        // The follow-up is a fresh refresh, not a lingering flag.
        XCTAssertFalse(state.isRefreshing)
        XCTAssertFalse(state.followUpQueued)
        XCTAssertNotNil(state.begin())
        XCTAssertEqual(state.end(generation: state.generation), .done)
    }

    func testEndWithCurrentGenerationCompletes() {
        var state = CaptureAgendaRefreshState()
        let generation = state.begin()
        XCTAssertEqual(state.end(generation: generation!), .done)
        XCTAssertFalse(state.isRefreshing)
    }

    func testEndWithStaleGenerationDiscardsWithoutTouchingFlags() {
        var state = CaptureAgendaRefreshState()
        let first = state.begin()!
        state.reset()
        XCTAssertEqual(state.end(generation: first), .discarded)
        // The reset cleared the flight; the stale end must not revive it.
        XCTAssertFalse(state.isRefreshing)
        XCTAssertFalse(state.followUpQueued)
        // A refresh started after the reset still completes.
        let second = state.begin()!
        XCTAssertEqual(state.end(generation: second), .done)
    }

    func testResetClearsBytesAndCapability() {
        var state = CaptureAgendaRefreshState()
        _ = state.begin()
        state.lastBytes = Data("bytes".utf8)
        state.capability = .supported
        state.reset()
        XCTAssertNil(state.lastBytes)
        XCTAssertEqual(state.capability, .unknown)
        XCTAssertFalse(state.isRefreshing)
    }

    func testInvalidateInFlightKeepsBytesAndCapability() {
        var state = CaptureAgendaRefreshState()
        let first = state.begin()!
        state.lastBytes = Data("bytes".utf8)
        state.capability = .supported
        state.invalidateInFlight()
        XCTAssertEqual(state.end(generation: first), .discarded)
        XCTAssertEqual(state.lastBytes, Data("bytes".utf8))
        XCTAssertEqual(state.capability, .supported)
    }

    func testDateGuardTable() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/agenda-current.json")
        let snapshot = try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: Data(contentsOf: url)
        )
        var state = CaptureAgendaRefreshState()
        state.today = { "2026-08-28" }
        XCTAssertTrue(state.isCurrent(snapshot))
        state.today = { "2026-08-29" }
        XCTAssertFalse(state.isCurrent(snapshot))
    }

    func testMissingDateIsNeverCurrent() {
        var state = CaptureAgendaRefreshState()
        state.today = { "2026-08-28" }
        XCTAssertFalse(state.isCurrent(CaptureAgendaSnapshot()))
    }
}
