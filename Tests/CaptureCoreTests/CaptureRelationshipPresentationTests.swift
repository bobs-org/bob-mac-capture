import Foundation
import XCTest

@testable import CaptureCore

final class CaptureRelationshipPresentationTests: XCTestCase {
    func testRelationshipRowsCoverExistingNewAndSubBulletOwners() throws {
        let cases: [(String, [String])] = [
            (
                "task-dependency-preview-existing-owner.json",
                ["⛓ depends on · Buy shoes · foo.md ^bar · Todo"]
            ),
            (
                "task-dependency-preview-existing-owner-alias.json",
                ["⛓ depends on · Buy shoes · foo.md ^bar · Todo"]
            ),
            (
                "task-dependency-preview-existing-owner-consumed.json",
                ["⛓ depends on · Buy shoes · foo.md ^bar · Todo"]
            ),
            (
                "task-dependency-preview-new-task.json",
                ["⛓ depends on · Buy shoes · foo.md ^bar · Todo"]
            ),
            (
                "task-dependency-preview-sub-bullet.json",
                ["⛓ depends on · Buy shoes · foo.md ^bar · Todo"]
            ),
            (
                "task-dependency-preview-existing-owner-blocks.json",
                ["🧱 blocks · Do cleanup tasks · job.md ^cleanup · Next → Blocked"]
            ),
            (
                "task-dependency-preview-existing-owner-mixed.json",
                [
                    "⛓ depends on · Buy shoes · foo.md ^bar · Todo",
                    "🧱 blocks · Do cleanup tasks · job.md ^cleanup · Next → Blocked",
                ]
            ),
        ]

        for (fixture, expectedRows) in cases {
            let capture = try captureFixture(fixture)
            let presentation = CaptureRelationshipPresentation(capture: capture)
            XCTAssertEqual(presentation.rows.map(\.text), expectedRows, fixture)
            XCTAssertEqual(
                presentation.rows.map(\.accessibilityLabel),
                expectedRows,
                fixture
            )
        }

        let mixed = CaptureRelationshipPresentation(
            capture: try captureFixture("task-dependency-preview-existing-owner-mixed.json")
        )
        XCTAssertEqual(mixed.rows.map(\.text), [
            "⛓ depends on · Buy shoes · foo.md ^bar · Todo",
            "🧱 blocks · Do cleanup tasks · job.md ^cleanup · Next → Blocked",
        ])
    }

    func testExistingOwnerHeaderAndOwnerFirstTaskCard() throws {
        let capture = try captureFixture("task-dependency-preview-existing-owner-blocks.json")
        let presentation = CaptureRelationshipPresentation(capture: capture)

        XCTAssertEqual(presentation.ownerHeader?.text, "Exercise")
        XCTAssertEqual(presentation.ownerHeader?.locationText, "body.md ^excercise")
        XCTAssertEqual(presentation.ownerHeader?.statusText, "In Progress")
        XCTAssertEqual(
            CaptureRelationshipPresentation.ownerFirstTaskBlocks(
                for: capture,
                blocks: capture.taskBlocks
            ).first?.blockID,
            "excercise"
        )
    }

    func testOwnerHeaderShowsStatusTransitionAndSuppressesRawRelationshipRows() throws {
        let capture = try captureFixture("task-dependency-preview-existing-owner.json")
        let presentation = CaptureRelationshipPresentation(capture: capture)
        XCTAssertEqual(presentation.ownerHeader?.statusText, "In Progress → Blocked")

        let block = try XCTUnwrap(capture.taskBlocks.first)
        let taskCard = CaptureTaskBlockPresentation(
            block: block,
            dryRun: true,
            suppressRelationshipLines: true
        )
        XCTAssertTrue(
            CaptureTaskBlockPresentation.covers(capture, blocks: capture.taskBlocks)
        )
        XCTAssertEqual(taskCard.rows.map(\.content), [
            "- [?] #task Exercise [fresh:: 2026-10-14] [id:: body__excercise] [dependsOn:: foo__bar] ^excercise",
        ])
        XCTAssertFalse(taskCard.accessibilitySummary.contains("DEPENDS ON"))

        let blocked = try captureFixture("task-dependency-preview-existing-owner-blocks.json")
        let cards = blocked.taskBlocks.map {
            CaptureTaskBlockPresentation(
                block: $0,
                dryRun: true,
                suppressRelationshipLines: true
            )
        }
        XCTAssertTrue(cards.allSatisfy { card in
            card.rows.allSatisfy {
                !$0.content.contains("DEPENDS ON") && !$0.content.contains("BLOCKS")
            }
        })
    }

    func testAlreadyPresentRelationshipsAndUnchangedStatusUseCalmRows() throws {
        let dependency = try captureWithAddedCount(
            0,
            fixture: "task-dependency-preview-existing-owner.json"
        )
        XCTAssertEqual(
            CaptureRelationshipPresentation(capture: dependency).rows.map(\.text),
            ["⛓ already depends on · Buy shoes · foo.md ^bar · Todo"]
        )

        let blocked = try captureWithAddedCount(
            0,
            fixture: "task-dependency-preview-existing-owner-blocks.json"
        )
        let presentation = CaptureRelationshipPresentation(capture: blocked)
        XCTAssertEqual(
            presentation.rows.map(\.text),
            ["🧱 already blocks · Do cleanup tasks · job.md ^cleanup · Blocked"]
        )
        XCTAssertEqual(presentation.ownerHeader?.statusText, "In Progress")
    }

    func testNotificationUsesOwnerAndRelationshipAndConsumedLinkSummary() throws {
        let capture = try captureFixture("task-dependency-preview-existing-owner-consumed.json")
        let notification = try XCTUnwrap(
            CaptureRelationshipPresentation(capture: capture).notification
        )

        XCTAssertEqual(notification.title, "⛓ Exercise now depends on Buy shoes")
        XCTAssertEqual(notification.subtitle, "body.md")
        XCTAssertTrue(notification.body.contains("would remove its Task Link from FOCUS"))
    }

    func testMixedNotificationCountsBothDirections() throws {
        let capture = try captureFixture("task-dependency-preview-existing-owner-mixed.json")
        let notification = try XCTUnwrap(
            CaptureRelationshipPresentation(capture: capture).notification
        )

        XCTAssertEqual(notification.title, "Exercise · depends on 1 · blocks 1")
    }

    private func captureFixture(_ name: String) throws -> CaptureCommandSuccess {
        try decodeSuccess(fixtureData(name))
    }

    private func captureWithAddedCount(
        _ added: Int,
        fixture: String
    ) throws -> CaptureCommandSuccess {
        let data = try fixtureData(fixture)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var updates = try XCTUnwrap(json["dependency_updates"] as? [[String: Any]])
        updates[0]["added"] = added
        if fixture == "task-dependency-preview-existing-owner-blocks.json" {
            updates[0]["status_changed"] = false
        }
        json["dependency_updates"] = updates
        return try decodeSuccess(JSONSerialization.data(withJSONObject: json))
    }

    private func fixtureData(_ name: String) throws -> Data {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        return try Data(contentsOf: fixtures.appendingPathComponent(name))
    }

    private func decodeSuccess(_ data: Data) throws -> CaptureCommandSuccess {
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            throw FixtureError.expectedSuccess
        }
        return success
    }
}

private enum FixtureError: Error {
    case expectedSuccess
}
