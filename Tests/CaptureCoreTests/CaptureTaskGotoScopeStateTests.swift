import XCTest

@testable import CaptureCore

final class CaptureTaskGotoScopeStateTests: XCTestCase {
    private func candidate(_ ref: String) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(replacement: "", taskRef: ref)
    }

    func testLatestToggleAppliesScopeAndCandidatesTogether() throws {
        let open = candidate("open")
        let completed = candidate("completed")
        var state = CaptureTaskGotoScopeState()
        state.beginSession(candidates: [open], appliedIncludesClosedTasks: false)

        let show = try XCTUnwrap(state.toggle())
        XCTAssertTrue(state.desiredIncludesClosedTasks)
        XCTAssertFalse(state.appliedIncludesClosedTasks)
        XCTAssertEqual(state.candidates, [open])

        let hide = try XCTUnwrap(state.toggle())
        XCTAssertFalse(state.desiredIncludesClosedTasks)
        XCTAssertFalse(state.isCurrent(show))
        XCTAssertFalse(state.apply(candidates: [completed], for: show))
        XCTAssertFalse(state.fail(show))

        XCTAssertTrue(state.apply(candidates: [open], for: hide))
        XCTAssertEqual(state.candidates, [open])
        XCTAssertFalse(state.appliedIncludesClosedTasks)
        XCTAssertFalse(state.desiredIncludesClosedTasks)
        XCTAssertFalse(state.hasPendingRequest)
    }

    func testLatestFailureRestoresTheAppliedSnapshotScope() throws {
        let open = candidate("open")
        let completed = candidate("completed")
        var state = CaptureTaskGotoScopeState()
        state.beginSession(candidates: [open, completed], appliedIncludesClosedTasks: true)

        let hide = try XCTUnwrap(state.request(includesClosedTasks: false))
        XCTAssertTrue(state.fail(hide))

        XCTAssertEqual(state.candidates, [open, completed])
        XCTAssertTrue(state.appliedIncludesClosedTasks)
        XCTAssertTrue(state.desiredIncludesClosedTasks)
        XCTAssertFalse(state.hasPendingRequest)
    }

    func testChipSnapshotKeepsAppliedAndDesiredScopeProvenance() throws {
        let open = candidate("open")
        let completed = candidate("completed")
        var state = CaptureTaskGotoScopeState()
        state.beginSession(candidates: [open, completed], appliedIncludesClosedTasks: true)
        let request = try XCTUnwrap(state.request(includesClosedTasks: false))

        let snapshot = state.snapshot
        XCTAssertEqual(snapshot.candidates, [open, completed])
        XCTAssertTrue(snapshot.appliedIncludesClosedTasks)
        XCTAssertFalse(snapshot.desiredIncludesClosedTasks)

        state.invalidatePendingRequest()
        XCTAssertEqual(state.snapshot, snapshot)
        XCTAssertFalse(state.isCurrent(request))
        XCTAssertFalse(state.hasPendingRequest)
    }

    func testNewIdenticalDraftSessionRejectsOldResponse() throws {
        let open = candidate("open")
        let completed = candidate("completed")
        var state = CaptureTaskGotoScopeState()
        state.beginSession(candidates: [open], appliedIncludesClosedTasks: false)
        let oldRequest = try XCTUnwrap(state.request(includesClosedTasks: true))

        state.beginSession(candidates: [open], appliedIncludesClosedTasks: false)
        let newRequest = try XCTUnwrap(state.request(includesClosedTasks: true))

        XCTAssertNotEqual(oldRequest, newRequest)
        XCTAssertFalse(state.apply(candidates: [open, completed], for: oldRequest))
        XCTAssertTrue(state.apply(candidates: [open, completed], for: newRequest))
        XCTAssertTrue(state.appliedIncludesClosedTasks)
    }
}
