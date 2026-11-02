import Foundation
import XCTest

@testable import CaptureCore

final class CaptureGrammarGateTests: XCTestCase {
    func testMissingAndLowerRevisionsAreIncompatible() {
        XCTAssertFalse(CaptureGrammarGate.isCompatible(nil))
        XCTAssertFalse(CaptureGrammarGate.isCompatible(0))
        XCTAssertFalse(CaptureGrammarGate.isCompatible(1))
        XCTAssertFalse(CaptureGrammarGate.isCompatible(2), "grammar 2 predates drawers")
        XCTAssertFalse(CaptureGrammarGate.isCompatible(3))
        XCTAssertFalse(CaptureGrammarGate.isCompatible(4), "grammar 4 predates split/merge")
    }

    func testMinimumAndHigherRevisionsAreCompatible() {
        XCTAssertEqual(CaptureGrammarGate.minimumRevision, 5)
        XCTAssertTrue(CaptureGrammarGate.isCompatible(5))
        XCTAssertTrue(CaptureGrammarGate.isCompatible(6))
    }

    func testBlockedMessageIsThePrescribedCopy() {
        XCTAssertEqual(
            CaptureGrammarGate.blockedMessage,
            "Update bob to use Pomodoro split and merge syntax"
        )
    }

    func testGrammarFiveSplitAndMergeModesKeepBobNeeds() throws {
        let split = try decodeParse(
            #"{"ok":true,"schema_version":1,"grammar":5,"input":"=/build#f","body":"","mode":"pomodoro_split","needs":["pomodoro_split_type"]}"#
        )
        let merge = try decodeParse(
            #"{"ok":true,"schema_version":1,"grammar":5,"input":"=*build#f","body":"","mode":"pomodoro_merge","needs":["pomodoro_merge_dest"]}"#
        )

        XCTAssertEqual(split.mode, "pomodoro_split")
        XCTAssertEqual(split.needs, ["pomodoro_split_type"])
        XCTAssertEqual(merge.mode, "pomodoro_merge")
        XCTAssertEqual(merge.needs, ["pomodoro_merge_dest"])
        XCTAssertEqual(
            CapturePickerNeed.pomodoroSplitType.statusText,
            "Pick a type to split out — press Tab to browse"
        )
        XCTAssertEqual(
            CapturePickerNeed.pomodoroMergeDestination.statusText,
            "Pick a Pomodoro to merge in — press Tab to browse"
        )
    }

    private func decodeParse(_ text: String) throws -> CaptureParseResponse {
        try JSONDecoder().decode(CaptureParseResponse.self, from: Data(text.utf8))
    }
}
