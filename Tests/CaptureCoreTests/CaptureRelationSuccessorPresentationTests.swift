import XCTest

@testable import CaptureCore

final class CaptureRelationSuccessorPresentationTests: XCTestCase {
    func testOffersUseBobMessageAndCannotDimSource() {
        let message =
            "🪢 Offers “Prepare evaluation prompt” when “Send implementation prompt” is parked or done · never blocks"
        let slot = CaptureRelationCloseEffect.slot(
            effect: .offers,
            appliesToSource: true,
            verdict: "offers",
            message: message,
            hint: nil
        )

        XCTAssertEqual(
            slot,
            RelationSourceSlot(text: message, style: .offers, effect: .offers)
        )
        XCTAssertFalse(
            CaptureRelationCloseEffect.dimsSource(
                closesSource: true,
                verdict: "completes",
                effect: .offers
            )
        )
        XCTAssertEqual(RelationSourceEffect.offers.symbolName, "link")
        XCTAssertEqual(RelationSourceEffect.offers.capsuleText, "offers")
    }

    func testReleasedSourceCaveatsAreAmberAndRemainBobAuthored() {
        for verdict in ["already_parked", "already_closed"] {
            let message = "Bob's exact caveat for \(verdict)"
            let slot = CaptureRelationCloseEffect.slot(
                effect: .offers,
                appliesToSource: true,
                verdict: verdict,
                message: message,
                hint: nil
            )

            XCTAssertEqual(
                slot,
                RelationSourceSlot(text: message, style: .caveat, effect: .offers)
            )
        }
    }

    func testInverseHintNeedsNoVerdictAndStaysMuted() {
        let hint = "“starts before” never offers anything · use the inverse relation"
        let slot = CaptureRelationCloseEffect.slot(
            effect: nil,
            appliesToSource: false,
            verdict: nil,
            message: nil,
            hint: hint
        )

        XCTAssertEqual(slot, RelationSourceSlot(text: hint, style: .muted, effect: nil))
    }

    func testExistingCloseEffectsKeepTheirVerdictsAndMutedRefusals() {
        let cancel = CaptureRelationCloseEffect.slot(
            effect: .cancel,
            appliesToSource: true,
            verdict: "cancels",
            message: "Bob cancel message",
            hint: nil
        )
        let complete = CaptureRelationCloseEffect.slot(
            effect: .complete,
            appliesToSource: true,
            verdict: "completes",
            message: "Bob complete message",
            hint: nil
        )
        let refused = CaptureRelationCloseEffect.slot(
            effect: .complete,
            appliesToSource: true,
            verdict: "already_closed",
            message: "Already Done · link only",
            hint: nil
        )

        XCTAssertEqual(cancel?.style, .cancel)
        XCTAssertEqual(complete?.style, .complete)
        XCTAssertEqual(refused?.style, .muted)
        XCTAssertTrue(
            CaptureRelationCloseEffect.dimsSource(
                closesSource: true,
                verdict: "completes",
                effect: .complete
            )
        )
    }
}