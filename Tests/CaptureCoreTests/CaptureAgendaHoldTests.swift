import XCTest

@testable import CaptureCore

/// Table-driven tests for the first-keystroke dim-hold state machine
/// (plan §7): the hold starts on the first non-blank keystroke and ends
/// at the first of preview settle, region takeover, the 250 ms ceiling,
/// or the draft returning to blank.
final class CaptureAgendaHoldTests: XCTestCase {
    func testFirstKeystrokeStartsHold() {
        XCTAssertEqual(
            CaptureAgendaHold.next(state: .idle, event: .draftBecameNonBlank),
            .holding
        )
    }

    func testEveryReleasePathEndsHold() {
        let releases: [CaptureAgendaHold.Event] = [
            .previewSettled,
            .regionTaken,
            .timeoutElapsed,
            .draftReturnedToBlank,
        ]
        for event in releases {
            XCTAssertEqual(
                CaptureAgendaHold.next(state: .holding, event: event),
                .idle,
                "holding + \(event) must release"
            )
        }
    }

    func testIdleIgnoresReleaseEvents() {
        let releases: [CaptureAgendaHold.Event] = [
            .previewSettled,
            .regionTaken,
            .timeoutElapsed,
            .draftReturnedToBlank,
        ]
        for event in releases {
            XCTAssertEqual(
                CaptureAgendaHold.next(state: .idle, event: event),
                .idle,
                "idle + \(event) must stay idle"
            )
        }
    }

    func testRepeatKeystrokeKeepsHold() {
        XCTAssertEqual(
            CaptureAgendaHold.next(state: .holding, event: .draftBecameNonBlank),
            .holding
        )
    }

    func testHoldConstantsMatchPlan() {
        XCTAssertEqual(CaptureAgendaHold.timeoutNanoseconds, 250_000_000)
        XCTAssertEqual(CaptureAgendaHold.dimmedOpacity, 0.35)
        XCTAssertEqual(CaptureAgendaHold.updateFadeSeconds, 0.12)
        XCTAssertEqual(CaptureAgendaHold.dimFadeSeconds, 0.1)
    }
}
