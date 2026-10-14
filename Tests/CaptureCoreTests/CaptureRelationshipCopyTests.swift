import XCTest

@testable import CaptureCore

/// Owner-aware `&`/`*` headers, `+` owner-mode titles, and the calm
/// `dependency_target` hint. Copy is built from Bob's JSON plus remembered
/// picker names.
final class CaptureRelationshipCopyTests: XCTestCase {
    func testQuotedUsesCurlyQuotes() {
        XCTAssertEqual(
            CaptureRelationshipCopy.quoted("Buy shoes"),
            "\u{201C}Buy shoes\u{201D}"
        )
    }

    func testNamedListCountsTheRest() {
        XCTAssertEqual(
            CaptureRelationshipCopy.namedList(["Buy shoes"]),
            "\u{201C}Buy shoes\u{201D}"
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.namedList(["Buy shoes", "Milk", "Eggs"]),
            "\u{201C}Buy shoes\u{201D} + 2 more"
        )
    }

    func testDisplayNamePrefersRememberedReplacementThenLocator() {
        XCTAssertEqual(
            CaptureRelationshipCopy.displayName(
                raw: "&foo:bar",
                note: "foo",
                blockID: "bar",
                names: ["&foo:bar": "Buy shoes"]
            ),
            "Buy shoes"
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.displayName(
                raw: "&foo:bar",
                note: "foo",
                blockID: "bar",
                names: [:]
            ),
            "foo:bar"
        )
    }

    func testExistingOwnerHeaderUsesTextAndLocation() {
        let owner = DependencyOwner(
            kind: "existing_task",
            route: "body",
            blockID: "excercise",
            text: "Exercise",
            notePath: "body.md",
            statusSymbol: "/",
            statusName: "In Progress"
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyPickerTitle(owner: owner, direction: .prerequisite),
            "⛓ Exercise depends on\u{2026}"
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyPickerSubtitle(owner: owner, direction: .prerequisite),
            "body.md ^excercise · In Progress"
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyPickerTitle(owner: owner, direction: .blocks),
            "🧱 Exercise blocks\u{2026}"
        )
    }

    func testExistingOwnerFallsBackToTokenWhenTextMissing() {
        let owner = DependencyOwner(
            kind: "existing_task",
            route: "body",
            blockID: "excercise"
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyPickerTitle(owner: owner, direction: .prerequisite),
            "⛓ @body+excercise depends on\u{2026}"
        )
    }

    func testNewTaskOwnerQuotesTextAndOmitsSubtitle() {
        let owner = DependencyOwner(kind: "new_task", text: "Buy Groceries!")
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyPickerTitle(owner: owner, direction: .prerequisite),
            "⛓ \u{201C}Buy Groceries!\u{201D} depends on\u{2026}"
        )
        XCTAssertNil(
            CaptureRelationshipCopy.dependencyPickerSubtitle(owner: owner, direction: .prerequisite)
        )
        let empty = DependencyOwner(kind: "new_task")
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyPickerTitle(owner: empty, direction: .prerequisite),
            "New task depends on\u{2026}"
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyPickerTitle(owner: empty, direction: .blocks),
            "New task blocks\u{2026}"
        )
    }

    func testOwnerlessHeaderKeepsTitleAndTeachesNextStep() {
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyPickerTitle(owner: nil, direction: .prerequisite),
            "Choose a prerequisite"
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyPickerSubtitle(owner: nil, direction: .prerequisite),
            "Then type the task, or + for an existing one"
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyPickerTitle(owner: nil, direction: .blocks),
            "Choose a task to block"
        )
    }

    func testParentPickerOwnerModeTitles() {
        let shoes = CapturePickerRelationship(
            dependencies: [
                CapturePickerRelationshipEntry(
                    raw: "&foo:bar",
                    notePath: "foo.md",
                    blockID: "bar",
                    text: "Buy shoes"
                ),
            ]
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.parentPickerTitle(relationship: shoes),
            "⛓ Which task depends on \u{201C}Buy shoes\u{201D}?"
        )
        let cleanup = CapturePickerRelationship(
            blockedTasks: [
                CapturePickerRelationshipEntry(
                    raw: "*job:cleanup",
                    notePath: "job.md",
                    blockID: "cleanup",
                    text: "Do cleanup tasks"
                ),
            ]
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.parentPickerTitle(relationship: cleanup),
            "🧱 Which task blocks \u{201C}Do cleanup tasks\u{201D}?"
        )
        let both = CapturePickerRelationship(
            dependencies: shoes.dependencies,
            blockedTasks: cleanup.blockedTasks
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.parentPickerTitle(relationship: both),
            "Which task depends on \u{201C}Buy shoes\u{201D} and blocks \u{201C}Do cleanup tasks\u{201D}?"
        )
        let several = CapturePickerRelationship(
            dependencies: [
                CapturePickerRelationshipEntry(
                    raw: "&foo:bar",
                    notePath: "foo.md",
                    blockID: "bar",
                    text: "Buy shoes"
                ),
                CapturePickerRelationshipEntry(
                    raw: "&cash:milk",
                    notePath: "cash.md",
                    blockID: "milk",
                    text: "Milk"
                ),
            ]
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.parentPickerTitle(relationship: several),
            "⛓ Which task depends on \u{201C}Buy shoes\u{201D} + 1 more?"
        )
    }

    func testDependencyTargetHintVariants() {
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyTargetHint(
                dependencyNames: ["Buy shoes"],
                blockedNames: []
            ),
            "⛓ What depends on \u{201C}Buy shoes\u{201D}? Type a new task, or + for an existing one."
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyTargetHint(
                dependencyNames: [],
                blockedNames: ["Do cleanup tasks"]
            ),
            "🧱 What blocks \u{201C}Do cleanup tasks\u{201D}? Type a new task, or + for an existing one"
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyTargetHint(
                dependencyNames: ["Buy shoes"],
                blockedNames: ["Do cleanup tasks"]
            ),
            "Type the task between \u{201C}Buy shoes\u{201D} and \u{201C}Do cleanup tasks\u{201D}, or + for an existing one"
        )
    }

    func testHintUsesParseMarkersAndNameMap() throws {
        let parse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data("""
            {
              "ok": true, "schema_version": 1, "input": "&foo:bar ",
              "body": "", "mode": "incomplete",
              "needs": ["dependency_target"],
              "spans": [], "diagnostics": [],
              "dependencies": [{
                "raw": "&foo:bar", "note": "foo", "block_id": "bar",
                "quoted": false, "range": {"start": 0, "end": 8}
              }]
            }
            """.utf8)
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyTargetHint(parse: parse, names: [:]),
            "⛓ What depends on \u{201C}foo:bar\u{201D}? Type a new task, or + for an existing one."
        )
        XCTAssertEqual(
            CaptureRelationshipCopy.dependencyTargetHint(
                parse: parse,
                names: ["&foo:bar": "Buy shoes"]
            ),
            "⛓ What depends on \u{201C}Buy shoes\u{201D}? Type a new task, or + for an existing one."
        )
    }

    func testDependencyTargetNeedStatusIsCalmFallback() {
        XCTAssertEqual(
            CapturePickerNeed.dependencyTarget.statusText,
            "Type a new task, or + for an existing one"
        )
    }
}
