import XCTest

@testable import CaptureCore

final class CaptureNoteGotoScopeStateTests: XCTestCase {
    private func candidate(_ path: String) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(replacement: "", notePath: path)
    }

    func testLatestToggleAppliesScopeAndCandidatesTogether() throws {
        let living = candidate("Areas/cash.md")
        let archived = candidate("done/a_done.md")
        var state = CaptureNoteGotoScopeState()
        state.beginSession(candidates: [living], appliedIncludesArchivedNotes: false)

        let show = try XCTUnwrap(state.toggle())
        XCTAssertTrue(state.desiredIncludesArchivedNotes)
        XCTAssertFalse(state.appliedIncludesArchivedNotes)
        XCTAssertEqual(state.candidates, [living])

        let hide = try XCTUnwrap(state.toggle())
        XCTAssertFalse(state.desiredIncludesArchivedNotes)
        XCTAssertFalse(state.isCurrent(show))
        XCTAssertFalse(state.apply(candidates: [archived], for: show))
        XCTAssertFalse(state.fail(show))

        XCTAssertTrue(state.apply(candidates: [living], for: hide))
        XCTAssertEqual(state.candidates, [living])
        XCTAssertFalse(state.appliedIncludesArchivedNotes)
        XCTAssertFalse(state.desiredIncludesArchivedNotes)
        XCTAssertFalse(state.hasPendingRequest)
    }

    func testLatestFailureRestoresTheAppliedSnapshotScope() throws {
        let living = candidate("Areas/cash.md")
        let archived = candidate("done/a_done.md")
        var state = CaptureNoteGotoScopeState()
        state.beginSession(candidates: [living, archived], appliedIncludesArchivedNotes: true)

        let hide = try XCTUnwrap(state.request(includesArchivedNotes: false))
        XCTAssertTrue(state.fail(hide))

        XCTAssertEqual(state.candidates, [living, archived])
        XCTAssertTrue(state.appliedIncludesArchivedNotes)
        XCTAssertTrue(state.desiredIncludesArchivedNotes)
        XCTAssertFalse(state.hasPendingRequest)
    }

    func testChipSnapshotKeepsAppliedAndDesiredScopeProvenance() throws {
        let living = candidate("Areas/cash.md")
        let archived = candidate("done/a_done.md")
        var state = CaptureNoteGotoScopeState()
        state.beginSession(candidates: [living, archived], appliedIncludesArchivedNotes: true)
        let request = try XCTUnwrap(state.request(includesArchivedNotes: false))

        let snapshot = state.snapshot
        XCTAssertEqual(snapshot.candidates, [living, archived])
        XCTAssertTrue(snapshot.appliedIncludesArchivedNotes)
        XCTAssertFalse(snapshot.desiredIncludesArchivedNotes)

        state.invalidatePendingRequest()
        XCTAssertEqual(state.snapshot, snapshot)
        XCTAssertFalse(state.isCurrent(request))
        XCTAssertFalse(state.hasPendingRequest)
    }

    func testNewIdenticalDraftSessionRejectsOldResponse() throws {
        let living = candidate("Areas/cash.md")
        let archived = candidate("done/a_done.md")
        var state = CaptureNoteGotoScopeState()
        state.beginSession(candidates: [living], appliedIncludesArchivedNotes: false)
        let oldRequest = try XCTUnwrap(state.request(includesArchivedNotes: true))

        state.beginSession(candidates: [living], appliedIncludesArchivedNotes: false)
        let newRequest = try XCTUnwrap(state.request(includesArchivedNotes: true))

        XCTAssertNotEqual(oldRequest, newRequest)
        XCTAssertFalse(state.apply(candidates: [archived], for: oldRequest))
        XCTAssertTrue(state.apply(candidates: [archived], for: newRequest))
        XCTAssertTrue(state.appliedIncludesArchivedNotes)
    }
}
