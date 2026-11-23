import Foundation
import XCTest

@testable import CaptureCore

final class CaptureRequirementCardDecodingTests: XCTestCase {
    func testBobRequirementFixturesDecodeRowsReceiptsAndStaleRecovery() throws {
        let preview = try decodeFixture("capture-req-close-preview.json")
        XCTAssertEqual(preview.pullIn?.reqs?.supported, true)
        XCTAssertEqual(preview.pullIn?.reqs?.pending, 3)

        let group = try XCTUnwrap(preview.allRequirementGroups.first)
        XCTAssertEqual(group.effectiveKind, "requirements")
        XCTAssertEqual(group.copy?.glyph, "requirement")
        XCTAssertEqual(
            preview.taskBlocks.first?.lines.compactMap(\.req).map(\.state),
            [.met, .met, .met])
        XCTAssertEqual(group.owner?.taskKey, "sase.md#^ship")
        XCTAssertEqual(group.requirementOwnerKey, group.owner?.key)
        XCTAssertEqual(group.copy?.scope, "3 requirements in 2 branches")
        XCTAssertEqual(
            group.copy?.footer, "⌃X met · ⌃⇧X drop · ⌃⇧T own task · space pull in · ⌃J jump")
        XCTAssertEqual(group.rows.map(\.req.siblingPath), [[1], [1, 1], [2]])
        XCTAssertEqual(group.rows.map(\.req.depth), [1, 2, 1])
        XCTAssertEqual(group.rows[0].req.pendingDescendants, 1)
        XCTAssertEqual(group.rows[1].req.parentKey, group.rows[0].offer.key)
        XCTAssertEqual(
            group.rows[0].consequences.carryPulled,
            "→ “Handles empty input” is its own task now · pulled in")
        XCTAssertTrue(group.rows.allSatisfy(\.isSelectable))

        XCTAssertEqual(preview.allRequirementOutcomes.count, 1)
        XCTAssertEqual(preview.allRequirementOutcomes.first?.verdict, "met")
        XCTAssertEqual(preview.allRequirementOutcomes.first?.ownerTaskKey, "sase.md#^ship")

        let mixed = try decodeFixture("capture-req-close-mixed.json")
        XCTAssertEqual(mixed.allRequirementGroups.count, 1)
        XCTAssertEqual(mixed.pullIn?.groups.contains(where: { $0.group == "hand_off" }), true)
        XCTAssertEqual(mixed.allUnblockedRows.compactMap(\.blockID), ["docs"])
        XCTAssertFalse(
            mixed.allUnblockedRows.contains { row in
                mixed.allRequirementGroups.contains { group in
                    group.rows.contains { $0.offer.key == row.offer?.key }
                }
            })

        let write = try decodeFixture("capture-req-close-write.json")
        let drop = try XCTUnwrap(
            write.allRequirementOutcomes.first(where: { $0.verdict == "drop" }))
        XCTAssertEqual(drop.reason, "No longer required")
        XCTAssertEqual(drop.path, "1")

        let staleText = try fixtureText("capture-req-close-stale.json")
        let stale = try JSONDecoder().decode(
            CaptureCommandResponse.self, from: Data(staleText.utf8))
        guard case .failure(let failure) = stale else {
            return XCTFail("Expected stale requirement refusal")
        }
        XCTAssertEqual(failure.code, "req_close_stale")
        XCTAssertEqual(stale.requirementGroups.first?.rows.count, 3)
        XCTAssertEqual(
            failure.current?.rows.map(\.kind), ["requirement", "requirement", "requirement"])

        let legacy = try decodeFixture("capture-req-close-legacy.json")
        XCTAssertNil(legacy.pullIn?.reqs)
        XCTAssertTrue(legacy.allRequirementGroups.isEmpty)
        XCTAssertTrue(legacy.allRequirementOutcomes.isEmpty)
        XCTAssertEqual(legacy.allUnblockedRows.compactMap(\.blockID), ["docs"])
    }

    func testMalformedRequirementRowIsDroppedWithoutLosingSiblingOrTaskOffers() throws {
        var payload = try fixtureObject("capture-req-close-mixed.json")
        var pullIn = try XCTUnwrap(payload["pull_in"] as? [String: Any])
        var groups = try XCTUnwrap(pullIn["groups"] as? [[String: Any]])
        var requirements = try XCTUnwrap(groups.first)
        var rows = try XCTUnwrap(requirements["rows"] as? [[String: Any]])
        rows.append([
            "offer": ["key": "bad-key", "n": 8, "group": "requirements"],
            "req": ["owner": "same-owner", "path": "1..2", "depth": 2, "text": "bad", "line": 9],
            "consequences": [
                "met": "Met", "drop": "Drop", "carry": "Carry", "carry_pulled": "Carry and pull",
            ],
        ])
        requirements["rows"] = rows
        groups[0] = requirements
        pullIn["groups"] = groups
        payload["pull_in"] = pullIn

        let data = try JSONSerialization.data(withJSONObject: payload)
        guard
            case .success(let decoded) = try JSONDecoder().decode(
                CaptureCommandResponse.self, from: data)
        else {
            return XCTFail("Expected successful mixed response")
        }
        XCTAssertEqual(decoded.allRequirementGroups.first?.rows.count, 3)
        XCTAssertEqual(decoded.allUnblockedRows.map(\.blockID), ["docs"])
    }

    func testBatchRootMirrorMergesByOpaqueOwnerAndDeduplicatesRowsAndReceipts() throws {
        var root = try fixtureObject("capture-req-close-preview.json")
        let rootPullIn = try XCTUnwrap(root["pull_in"] as? [String: Any])
        let rootGroups = try XCTUnwrap(rootPullIn["groups"] as? [[String: Any]])
        let rootGroup = try XCTUnwrap(rootGroups.first)
        let rootRows = try XCTUnwrap(rootGroup["rows"] as? [[String: Any]])
        let duplicateReceipt = try XCTUnwrap((root["req_outcomes"] as? [[String: Any]])?.first)

        var item = try fixtureObject("capture-req-close-preview.json")
        var itemPullIn = try XCTUnwrap(item["pull_in"] as? [String: Any])
        var itemGroups = try XCTUnwrap(itemPullIn["groups"] as? [[String: Any]])
        var itemGroup = try XCTUnwrap(itemGroups.first)
        let firstRow = try XCTUnwrap(rootRows.first)
        var changedExtraRow = firstRow
        var extraOffer = try XCTUnwrap(changedExtraRow["offer"] as? [String: Any])
        extraOffer["key"] = "opaque-extra-requirement-key"
        extraOffer["n"] = 4
        changedExtraRow["offer"] = extraOffer
        var extraRequirement = try XCTUnwrap(changedExtraRow["req"] as? [String: Any])
        extraRequirement["path"] = "3"
        extraRequirement["depth"] = 1
        extraRequirement["text"] = "Added in item"
        extraRequirement["line"] = 5
        changedExtraRow["req"] = extraRequirement
        itemGroup["rows"] = [firstRow, changedExtraRow]
        itemGroups[0] = itemGroup
        itemPullIn["groups"] = itemGroups
        item["pull_in"] = itemPullIn
        item["req_outcomes"] = [duplicateReceipt]
        root["captures"] = [item]
        root["pull_in"] = rootPullIn

        let data = try JSONSerialization.data(withJSONObject: root)
        guard
            case .success(let response) = try JSONDecoder().decode(
                CaptureCommandResponse.self, from: data)
        else {
            return XCTFail("Expected successful batch response")
        }
        XCTAssertEqual(response.allRequirementGroups.count, 1)
        XCTAssertEqual(response.allRequirementGroups.first?.rows.count, 4)
        let expectedOwner = try XCTUnwrap(rootGroup["owner"] as? [String: Any])
        XCTAssertEqual(
            response.allRequirementGroups.first?.requirementOwnerKey,
            expectedOwner["key"] as? String
        )
        XCTAssertTrue(
            response.allRequirementGroups.first?.rows.contains(where: {
                $0.req.text == "Added in item"
            }) == true
        )
        XCTAssertEqual(response.allRequirementOutcomes.count, 1)
    }

    private func decodeFixture(_ name: String) throws -> CaptureCommandSuccess {
        let text = try fixtureText(name)
        guard
            case .success(let response) = try JSONDecoder().decode(
                CaptureCommandResponse.self,
                from: Data(text.utf8)
            )
        else {
            throw NSError(domain: "CaptureRequirementCardDecodingTests", code: 1)
        }
        return response
    }

    private func fixtureText(_ name: String) throws -> String {
        try String(contentsOf: fixturesDirectory().appendingPathComponent(name), encoding: .utf8)
    }

    private func fixtureObject(_ name: String) throws -> [String: Any] {
        let text = try fixtureText(name)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func fixturesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../Fixtures", isDirectory: true)
            .standardizedFileURL
    }
}
