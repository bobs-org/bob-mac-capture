import XCTest

@testable import CaptureCore

final class CaptureGrammarGateTests: XCTestCase {
    func testMissingAndLowerRevisionsAreIncompatible() {
        XCTAssertFalse(CaptureGrammarGate.isCompatible(nil))
        XCTAssertFalse(CaptureGrammarGate.isCompatible(0))
        XCTAssertFalse(CaptureGrammarGate.isCompatible(1))
        XCTAssertFalse(CaptureGrammarGate.isCompatible(2), "grammar 2 predates drawers")
    }

    func testMinimumAndHigherRevisionsAreCompatible() {
        XCTAssertEqual(CaptureGrammarGate.minimumRevision, 3)
        XCTAssertTrue(CaptureGrammarGate.isCompatible(3))
        XCTAssertTrue(CaptureGrammarGate.isCompatible(4))
    }

    func testBlockedMessageIsThePrescribedCopy() {
        XCTAssertEqual(
            CaptureGrammarGate.blockedMessage,
            "Update bob to use drawers and % directives"
        )
    }
}
