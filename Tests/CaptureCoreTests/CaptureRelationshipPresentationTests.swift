import Foundation
import XCTest

@testable import CaptureCore

final class CaptureRelationshipPresentationTests: XCTestCase {
    func testRelationshipRowsCoverExistingNewAndSubBulletOwners() throws {
        let cases: [(String, [String])] = [
            (
                "task-dependency-preview-existing-owner.json",
                ["⛓ depends on · Buy shoes · foo.md ^bar · Ready → In Progress"]
            ),
            (
                "task-dependency-preview-existing-owner-alias.json",
                ["⛓ depends on · Buy shoes · foo.md ^bar · Ready → In Progress"]
            ),
            (
                "task-dependency-preview-existing-owner-consumed.json",
                ["⛓ depends on · Buy shoes · foo.md ^bar · Ready → In Progress"]
            ),
            (
                "task-dependency-preview-new-task.json",
                ["⛓ depends on · Buy shoes · foo.md ^bar · Ready"]
            ),
            (
                "task-dependency-preview-sub-bullet.json",
                ["⛓ depends on · Buy shoes · foo.md ^bar · Ready → In Progress"]
            ),
            (
                "task-dependency-preview-existing-owner-blocks.json",
                ["🧱 blocks · Do cleanup tasks · job.md ^cleanup · Next → Blocked"]
            ),
            (
                "task-dependency-preview-existing-owner-mixed.json",
                [
                    "⛓ depends on · Buy shoes · foo.md ^bar · Ready → In Progress",
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
            "⛓ depends on · Buy shoes · foo.md ^bar · Ready → In Progress",
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
            ["⛓ already depends on · Buy shoes · foo.md ^bar · In Progress"]
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

    func testPerPrerequisiteAlreadyPresentAndStatusArrow() throws {
        let capture = try decodeSuccess(
            Data(
                """
                {
                  "ok": true, "dry_run": true, "routed": true,
                  "route_label": "body.md", "relative_target": "body.md",
                  "target": "/tmp/vault/body.md", "text": "Exercise",
                  "task_line": "- [?] #task Exercise", "kind": "task_dependency",
                  "created": "2026-10-14", "placement": "updated",
                  "dependency_updates": [{
                    "role": "dependent", "added": 1, "already_present": 1,
                    "dependent_text": "Exercise",
                    "prerequisites": [
                      {
                        "note": "foo.md", "block_id": "bar", "link": "[[foo#^bar]]",
                        "status_symbol": "/", "status_name": "In Progress",
                        "text": "Buy shoes", "open": true, "already_present": true
                      },
                      {
                        "note": "foo.md", "block_id": "socks", "link": "[[foo#^socks]]",
                        "status_symbol": "/", "status_name": "In Progress",
                        "previous_status": " ", "previous_status_name": "Ready",
                        "text": "Buy socks", "open": true
                      }
                    ]
                  }]
                }
                """.utf8
            )
        )
        XCTAssertEqual(
            CaptureRelationshipPresentation(capture: capture).rows.map(\.text),
            [
                "⛓ already depends on · Buy shoes · foo.md ^bar · In Progress",
                "⛓ depends on · Buy socks · foo.md ^socks · Ready → In Progress",
            ]
        )
    }

    func testUnchangedOwnerLineIsCoveredForTaskDependency() throws {
        let capture = try captureFixture("task-dependency-preview-existing-owner-unchanged.json")
        let owner = try XCTUnwrap(
            capture.taskBlocks.first(where: {
                $0.relativeTarget == capture.relativeTarget && $0.blockID == capture.blockID
            })
        )
        XCTAssertEqual(owner.lines.first?.change, .unchanged)
        XCTAssertTrue(CaptureTaskBlockPresentation.covers(capture, blocks: capture.taskBlocks))
        XCTAssertEqual(
            CaptureRelationshipPresentation(capture: capture).rows.map(\.text),
            ["🧱 blocks · Do cleanup tasks · job.md ^cleanup · Next → Blocked"]
        )
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

    func testRelationRowsForLXVectors() throws {
        let lx1 = try captureFixture("relation-preview-lx1-archived.json")
        XCTAssertEqual(
            CaptureRelationshipPresentation(capture: lx1).rows.map(\.text),
            [
                "🪢 links to “Capture * blocks existing tasks” · follow-up of   done/bob_done.md ^capture-star · archived: LINKED FROM shows live only"
            ]
        )

        let lx2 = try captureFixture("relation-preview-lx2-from.json")
        XCTAssertEqual(
            CaptureRelationshipPresentation(capture: lx2).rows.map(\.text),
            ["🪢 “Design a retry policy” now links here · next step   sase.md ^retry-design"]
        )

        let lx3 = try captureFixture("relation-preview-lx3-relabeled.json")
        XCTAssertEqual(
            CaptureRelationshipPresentation(capture: lx3).rows.map(\.text),
            ["🪢 relabeled “Retry design” · next   sase.md ^retry-design"]
        )

        let mixed = try captureFixture("relation-preview-mixed-dependency.json")
        let mixedRows = CaptureRelationshipPresentation(capture: mixed).rows.map(\.text)
        XCTAssertEqual(mixedRows.count, 2)
        XCTAssertTrue(mixedRows[0].hasPrefix("⛓ depends on"))
        XCTAssertTrue(mixedRows[1].hasPrefix("🪢 links to"))
        XCTAssertTrue(mixedRows[1].contains("Design a retry policy"))

        let batch = try captureFixture("relation-preview-lx10-same-batch.json")
        XCTAssertEqual(batch.normalizedCaptures.count, 2)
        let firstRows = CaptureRelationshipPresentation(
            capture: batch.normalizedCaptures[0]
        ).rows.map(\.text)
        XCTAssertEqual(firstRows.count, 1)
        XCTAssertTrue(firstRows[0].hasPrefix("🪢 links to"))
    }

    func testRelationRowsNeverRenderStatusArrows() throws {
        for fixture in [
            "relation-preview-lx1-archived.json",
            "relation-preview-lx2-from.json",
            "relation-preview-lx3-relabeled.json",
            "relation-preview-mixed-dependency.json",
        ] {
            let capture = try captureFixture(fixture)
            for row in CaptureRelationshipPresentation(capture: capture).rows
                where row.text.hasPrefix("🪢")
            {
                XCTAssertFalse(
                    row.text.contains("Ready →"),
                    "\(fixture): \(row.text)"
                )
                XCTAssertFalse(
                    row.text.contains("In Progress →"),
                    "\(fixture): \(row.text)"
                )
            }
        }
    }

    func testRelationNotificationsCountSeparately() throws {
        let lx1 = try captureFixture("relation-preview-lx1-archived.json")
        let lx1Notification = try XCTUnwrap(
            CaptureRelationshipPresentation(capture: lx1).notification
        )
        XCTAssertEqual(
            lx1Notification.title,
            "🪢 Fix retries now links to “Capture * blocks existing tasks”"
        )

        let lx2 = try captureFixture("relation-preview-lx2-from.json")
        let lx2Notification = try XCTUnwrap(
            CaptureRelationshipPresentation(capture: lx2).notification
        )
        XCTAssertEqual(
            lx2Notification.title,
            "🪢 “Design a retry policy” now links here"
        )

        let mixed = try captureFixture("relation-preview-mixed-dependency.json")
        let mixedNotification = try XCTUnwrap(
            CaptureRelationshipPresentation(capture: mixed).notification
        )
        XCTAssertEqual(mixedNotification.title, "Buy milk · depends on 1 · links 1")
    }

    func testRelationManagedLinesAreSuppressed() throws {
        let lx3 = try captureFixture("relation-preview-lx3-relabeled.json")
        let suppressed = lx3.taskBlocks.map {
            CaptureTaskBlockPresentation(
                block: $0,
                dryRun: true,
                suppressRelationshipLines: true
            )
        }
        XCTAssertTrue(suppressed.allSatisfy { card in
            card.rows.allSatisfy {
                !$0.content.contains("**LINKS:**") && !$0.content.contains("**LINKED FROM:**")
            }
        })
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
        if var prerequisites = updates[0]["prerequisites"] as? [[String: Any]] {
            for index in prerequisites.indices {
                prerequisites[index]["previous_status"] = nil
                prerequisites[index]["previous_status_name"] = nil
            }
            updates[0]["prerequisites"] = prerequisites
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
