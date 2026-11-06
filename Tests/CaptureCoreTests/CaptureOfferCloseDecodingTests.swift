import Foundation
import XCTest

@testable import CaptureCore

final class CaptureOfferCloseDecodingTests: XCTestCase {
    func testRealBobPreviewAndWriteFixturesDecodeOfferCloseFields() throws {
        let preview = try decodeSuccess(fixture("capture-offer-close-preview.json"))
        XCTAssertEqual(preview.pullIn?.close?.supported, true)
        XCTAssertEqual(preview.pullIn?.close?.doneCount, 0)
        let offer = try XCTUnwrap(preview.taskComplete?.unblocked.first?.offer)
        XCTAssertEqual(offer.close?.complete, true)
        XCTAssertEqual(offer.close?.cancel, true)
        XCTAssertFalse(try XCTUnwrap(offer.close?.completeConsequence).isEmpty)
        XCTAssertNil(offer.verdict)

        let write = try decodeSuccess(fixture("capture-offer-close-write.json"))
        XCTAssertEqual(write.pullIn?.close?.doneCount, 1)
        XCTAssertEqual(write.offerCloses.count, 1)
        let close = try XCTUnwrap(write.offerCloses.first)
        XCTAssertEqual(close.outcome, "done")
        XCTAssertEqual(close.key, "deps.md#^alpha")
        XCTAssertFalse(close.message.isEmpty)
        XCTAssertEqual(close.recovered.count, 1)
        XCTAssertFalse(try XCTUnwrap(close.recovered.first).unblockedStamped)
        XCTAssertEqual(
            write.taskComplete?.unblocked.first(where: { $0.offer?.key == close.key })?.offer?
                .verdict,
            "done"
        )
    }

    func testOfferCloseRefusalPayloadsRetainTheirCurrentOffers() throws {
        let stale = try decodeFailure(fixture("capture-offer-close-stale.json"))
        XCTAssertEqual(stale.code, "offer_close_stale")
        XCTAssertNil(stale.offerCloseRefused)
        XCTAssertFalse(stale.offers.isEmpty)
        XCTAssertEqual(stale.pullIn?.close?.supported, true)
        XCTAssertNotNil(stale.offers.first?.offer?.close)

        let refused = try decodeFailure(fixture("capture-offer-close-refused.json"))
        XCTAssertEqual(refused.code, "offer_close_refused")
        XCTAssertEqual(refused.offerCloseRefused?.outcome, "done")
        XCTAssertTrue(try XCTUnwrap(refused.offerCloseRefused?.why).contains("new in this capture"))
        XCTAssertFalse(refused.offers.isEmpty)

        let conflict = try decodeFailure(fixture("capture-offer-close-conflict.json"))
        XCTAssertEqual(conflict.code, "offer_verdict_conflict")
        XCTAssertFalse(conflict.offers.isEmpty)
        XCTAssertNil(conflict.offerCloseRefused)
    }

    func testLegacyBobPayloadWithoutCloseStillDecodes() throws {
        let legacy = try decodeSuccess(fixture("capture-offer-close-legacy.json"))
        XCTAssertNil(legacy.pullIn?.close)
        XCTAssertNil(legacy.taskComplete?.unblocked.first?.offer?.close)
        XCTAssertNil(legacy.taskComplete?.unblocked.first?.offer?.verdict)
        XCTAssertEqual(legacy.offerCloses, [])
    }

    func testMalformedAdditionsDegradeWithoutDroppingTheCapture() throws {
        let original =
            try JSONSerialization.jsonObject(
                with: Data(fixture("capture-offer-close-preview.json").utf8)
            ) as! [String: Any]
        var malformed = original
        malformed["offer_closes"] = [["n": "bad"]]
        if var pullIn = malformed["pull_in"] as? [String: Any] {
            pullIn["close"] = "bad"
            malformed["pull_in"] = pullIn
        }
        if var taskComplete = malformed["task_complete"] as? [String: Any],
            var unblocked = taskComplete["unblocked"] as? [[String: Any]],
            !unblocked.isEmpty,
            var offer = unblocked[0]["offer"] as? [String: Any]
        {
            offer["close"] = "bad"
            unblocked[0]["offer"] = offer
            taskComplete["unblocked"] = unblocked
            malformed["task_complete"] = taskComplete
        }
        let data = try JSONSerialization.data(withJSONObject: malformed)
        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let capture) = decoded else {
            return XCTFail("Malformed additive fields must not fail capture decoding")
        }
        XCTAssertEqual(capture.offerCloses, [CaptureOfferClose()])
        XCTAssertNil(capture.pullIn?.close)
        XCTAssertNil(capture.taskComplete?.unblocked.first?.offer?.close)
    }

    private func decodeSuccess(_ text: String) throws -> CaptureCommandSuccess {
        guard
            case .success(let response) = try JSONDecoder().decode(
                CaptureCommandResponse.self,
                from: Data(text.utf8)
            )
        else {
            throw NSError(domain: "CaptureOfferCloseDecodingTests", code: 1)
        }
        return response
    }

    private func decodeFailure(_ text: String) throws -> CaptureCommandFailure {
        guard
            case .failure(let response) = try JSONDecoder().decode(
                CaptureCommandResponse.self,
                from: Data(text.utf8)
            )
        else {
            throw NSError(domain: "CaptureOfferCloseDecodingTests", code: 2)
        }
        return response
    }

    private func fixture(_ name: String) throws -> String {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../Fixtures", isDirectory: true)
            .standardizedFileURL
        return try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}
