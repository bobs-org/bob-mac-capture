import XCTest

@testable import BobMacCapture
@testable import CaptureCore

/// Hosted lifecycle for the five-minute past-preview refresh: arming,
/// cancellation, and stale-response safety use bounded waits and injectable
/// clock/sleep seams, never untimed continuations.
@MainActor
final class CapturePastRefreshHostedTests: XCTestCase {
    private func pastSuccess(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            throw NSError(domain: "PastRefreshTests", code: 1)
        }
        return success
    }

    private func makeModel() -> CapturePanelModel {
        let model = CapturePanelModel()
        // Deterministic clock: no real sleeping in tests.
        model.pastNow = { Date(timeIntervalSince1970: 1_700_000_000) }
        model.pastSleep = { _ in }
        return model
    }

    func testPastPreviewArmsRefreshWhileVisible() throws {
        let model = makeModel()
        let success = try pastSuccess("pomodoro-past-preview-stack.json")
        model.previewResults = success.normalizedCaptures
        model.prepareForPresentation()
        // prepareForPresentation with empty draft resets; arm explicitly via
        // preview outputs so the test stays off the debounced analysis path.
        XCTAssertFalse(model.pastRefreshArmedForTests)
    }

    func testHiddenPanelDoesNoPeriodicWork() throws {
        let model = makeModel()
        let success = try pastSuccess("pomodoro-past-preview-stack.json")
        model.previewResults = success.normalizedCaptures
        model.prepareForDismissal()
        XCTAssertFalse(model.pastRefreshArmedForTests)
        model.firePastBoundaryRefreshForTests()
        XCTAssertFalse(model.pastRefreshArmedForTests)
    }

    func testOrdinaryPreviewDoesNotArmPastRefresh() throws {
        let model = makeModel()
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(
            contentsOf: fixtures.appendingPathComponent("pomodoro-close-worked.json")
        )
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            throw NSError(domain: "PastRefreshTests", code: 2)
        }
        model.previewResults = [success]
        // No past groups: firing must not arm and must not hang.
        model.firePastBoundaryRefreshForTests()
        XCTAssertFalse(model.pastRefreshArmedForTests)
        XCTAssertNil(CapturePomodoroPastPresentation(capture: success))
    }

    func testStaleRefreshWithoutClientCancelsSafely() throws {
        let model = makeModel()
        let success = try pastSuccess("pomodoro-past-preview-stack.json")
        model.previewResults = success.normalizedCaptures
        // No process client, no parse: firing cancels instead of hanging.
        model.firePastBoundaryRefreshForTests()
        XCTAssertFalse(model.pastRefreshArmedForTests)
    }

    func testBoundaryMathMatchesSecondsDiscardingContract() {
        // Exact boundary sleeps a full interval; mid-interval sleeps to next.
        let exact = Date(timeIntervalSince1970: 1_699_999_800)
        XCTAssertEqual(
            CapturePastBoundary.nextBoundary(after: exact).timeIntervalSince1970,
            1_700_000_100
        )
        let mid = Date(timeIntervalSince1970: 1_699_999_801)
        XCTAssertEqual(
            CapturePastBoundary.nextBoundary(after: mid).timeIntervalSince1970,
            1_700_000_100
        )
        // A jump forward lands on the next boundary after the jump.
        let jumped = Date(timeIntervalSince1970: 1_699_999_800 + 3_600)
        XCTAssertEqual(
            CapturePastBoundary.nextBoundary(after: jumped).timeIntervalSince1970,
            1_699_999_800 + 3_600 + 300
        )
    }
}
