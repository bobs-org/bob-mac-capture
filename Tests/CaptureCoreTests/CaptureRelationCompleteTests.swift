import Foundation
import XCTest

@testable import CaptureCore

final class CaptureRelationCompleteTests: XCTestCase {
    func testOldBobOmitsCompleteFields() throws {
        let completion = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(completeOldCompletionJSON.utf8)
        )
        XCTAssertNil(completion.relationComplete)
        XCTAssertEqual(completion.candidates.count, 1)
        XCTAssertFalse(completion.candidates[0].completesSource)
        XCTAssertFalse(completion.candidates[0].configured)

        let span = try JSONDecoder().decode(
            CaptureSpan.self,
            from: Data(#"{"start":40,"end":52,"kind":"relation_label"}"#.utf8)
        )
        XCTAssertFalse(span.completesSource)
        XCTAssertEqual(captureSemanticCategory(forSpan: span), .relationLabel)

        let capture = try decodeSuccess(completeOldCaptureJSON)
        XCTAssertTrue(capture.relationCompletes.isEmpty)
        XCTAssertNil(capture.relationUpdates.first?.completeEffect)
        XCTAssertFalse(capture.warnings.contains(where: \.isRelationCompletedSource))
        XCTAssertTrue(
            CaptureRelationCompletePresentation.previewWarningRows(for: capture).isEmpty
        )
        XCTAssertEqual(
            CaptureRelationshipPresentation(capture: capture).rows.map(\.usesCompletedTint),
            [false]
        )
    }

    func testCompletionCompleteFieldsDecode() throws {
        let completion = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(completeVerdictCompletionJSON.utf8)
        )
        let complete = try XCTUnwrap(completion.relationComplete)
        XCTAssertEqual(complete.verdict, "completes")
        XCTAssertEqual(complete.source.path, "design.md")
        XCTAssertEqual(complete.source.blockID, "ship")
        XCTAssertEqual(complete.source.text, "Ship retry policy")
        XCTAssertEqual(complete.source.statusSymbol, " ")
        XCTAssertEqual(complete.source.statusName, "Todo")
        XCTAssertEqual(
            complete.message,
            "✓ Completes “Ship retry policy” · Todo → Done"
        )
        XCTAssertNil(complete.hint)

        let overlay = try XCTUnwrap(
            completion.candidates.first(where: { $0.key == "implemented by" })
        )
        XCTAssertTrue(overlay.completesSource)
        XCTAssertFalse(overlay.cancelsSource)
        XCTAssertEqual(overlay.replacement, "|\"implemented by\"")

        let typed = try XCTUnwrap(completion.candidates.first(where: { $0.typed }))
        XCTAssertFalse(typed.completesSource)
        XCTAssertFalse(typed.configured)
    }

    func testAlreadyClosedAndHintDecode() throws {
        let completion = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(completeAlreadyClosedCompletionJSON.utf8)
        )
        let complete = try XCTUnwrap(completion.relationComplete)
        XCTAssertEqual(complete.verdict, "already_closed")
        XCTAssertEqual(complete.message, "Already Done · link only")
        XCTAssertEqual(
            complete.hint,
            "“implements” never completes · to finish “Verify cancel labels”, use ~~ with “implemented by”"
        )
    }

    func testParseSpanCompleteTint() throws {
        let span = try JSONDecoder().decode(
            CaptureSpan.self,
            from: Data(
                #"{"start":39,"end":53,"kind":"relation_label","completes_source":true}"#.utf8
            )
        )
        XCTAssertTrue(span.completesSource)
        XCTAssertEqual(captureSemanticCategory(forSpan: span), .relationCompleteLabel)
        XCTAssertTrue(CaptureSemanticCategory.relationCompleteLabel.isItalic)
    }

    func testRelationLabelRowCompletesCapsuleBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "|\"implemented by\"",
            label: "implemented by",
            count: 2,
            key: "implemented by",
            completesSource: true,
            configured: true
        )
        let content = completionRowContent(
            for: candidate,
            context: "relation_label",
            query: "impl"
        )
        XCTAssertEqual(content.category, .relationCompleteLabel)
        XCTAssertEqual(content.symbolName, "checkmark.circle")
        XCTAssertEqual(content.badges, ["completes"])
        XCTAssertEqual(content.accessibilityHint, "Inserts this complete relation label.")
    }

    func testCompletesAndCancelsStayExclusive() {
        let candidate = CaptureCompletionCandidate(
            replacement: "|\"duplicate of\"",
            label: "duplicate of",
            count: 1,
            key: "duplicate of",
            cancelsSource: true,
            configured: true
        )
        let content = completionRowContent(
            for: candidate,
            context: "relation_label",
            query: "dup"
        )
        XCTAssertEqual(content.category, .relationCancelLabel)
        XCTAssertEqual(content.symbolName, "circle.slash")
        XCTAssertEqual(content.badges, ["cancels"])
    }

    func testSlotAndDimmedSourcePerVerdict() throws {
        let completing = CaptureCompletionCandidate(
            replacement: "|\"implemented by\"",
            label: "implemented by",
            completesSource: true
        )
        let ordinary = CaptureCompletionCandidate(
            replacement: "|implements",
            label: "implements"
        )
        let completes = CaptureCompletionRelationComplete(
            source: CaptureCompletionRelationCompleteSource(text: "Ship retry policy"),
            verdict: "completes",
            message: "✓ Completes “Ship retry policy” · Todo → Done"
        )
        let closed = CaptureCompletionRelationComplete(
            source: CaptureCompletionRelationCompleteSource(text: "Old idea"),
            verdict: "already_closed",
            message: "Already Done · link only"
        )
        let recurring = CaptureCompletionRelationComplete(
            source: CaptureCompletionRelationCompleteSource(text: "Weekly review"),
            verdict: "recurring",
            message: "“Weekly review” repeats — complete it in Obsidian so Tasks writes the next one"
        )
        let newTask = CaptureCompletionRelationComplete(
            source: CaptureCompletionRelationCompleteSource(text: "New idea"),
            verdict: "new_task",
            message: "“New idea” is new — it would be born done"
        )
        let hinted = CaptureCompletionRelationComplete(
            source: CaptureCompletionRelationCompleteSource(text: "Ship retry policy"),
            verdict: "completes",
            message: "✓ Completes “Ship retry policy” · Todo → Done",
            hint: "“implements” never completes · to finish “Verify cancel labels”, use ~~ with “implemented by”"
        )

        XCTAssertTrue(
            CaptureRelationCompletePresentation.dimsSource(
                candidate: completing,
                complete: completes
            )
        )
        XCTAssertFalse(
            CaptureRelationCompletePresentation.dimsSource(
                candidate: completing,
                complete: closed
            )
        )
        XCTAssertFalse(
            CaptureRelationCompletePresentation.dimsSource(
                candidate: ordinary,
                complete: completes
            )
        )
        XCTAssertFalse(
            CaptureRelationCompletePresentation.dimsSource(
                candidate: completing,
                complete: recurring
            )
        )
        XCTAssertFalse(
            CaptureRelationCompletePresentation.dimsSource(
                candidate: completing,
                complete: newTask
            )
        )
        XCTAssertEqual(
            CaptureRelationCompletePresentation.slot(
                candidate: completing,
                complete: completes
            ),
            CaptureRelationCompleteSlot(
                text: "✓ Completes “Ship retry policy” · Todo → Done",
                style: .completes
            )
        )
        XCTAssertEqual(
            CaptureRelationCompletePresentation.slot(
                candidate: completing,
                complete: closed
            ),
            CaptureRelationCompleteSlot(text: "Already Done · link only", style: .muted)
        )
        XCTAssertEqual(
            CaptureRelationCompletePresentation.slot(
                candidate: completing,
                complete: recurring
            ),
            CaptureRelationCompleteSlot(text: recurring.message, style: .muted)
        )
        XCTAssertEqual(
            CaptureRelationCompletePresentation.slot(
                candidate: completing,
                complete: newTask
            ),
            CaptureRelationCompleteSlot(text: newTask.message, style: .muted)
        )
        XCTAssertNil(
            CaptureRelationCompletePresentation.slot(
                candidate: ordinary,
                complete: recurring
            )
        )
        XCTAssertNil(
            CaptureRelationCompletePresentation.slot(
                candidate: ordinary,
                complete: newTask
            )
        )
        XCTAssertEqual(
            CaptureRelationCompletePresentation.slot(
                candidate: ordinary,
                complete: hinted
            )?.style,
            .muted
        )
        XCTAssertEqual(
            CaptureRelationCompletePresentation.sourceAccessibilityLabel(
                sourceText: "Ship retry policy",
                dimsSource: true
            ),
            "Completes Ship retry policy"
        )
        XCTAssertEqual(RelationSourceEffect.complete.symbolName, "checkmark.circle")
        XCTAssertEqual(RelationSourceEffect.complete.capsuleText, "completes")
        XCTAssertEqual(RelationSourceEffect.cancel.symbolName, "circle.slash")
    }

    func testCaptureCompleteRowsAndWarningRestyle() throws {
        let capture = try decodeSuccess(completeDryRunCaptureJSON)
        XCTAssertEqual(capture.relationUpdates.first?.completeEffect, "completed")
        XCTAssertEqual(capture.relationCompletes.count, 1)
        XCTAssertEqual(capture.relationCompletes[0].previousStatus, " ")
        XCTAssertEqual(capture.relationCompletes[0].previousStatusName, "Todo")
        XCTAssertEqual(capture.relationCompletes[0].source.blockID, "ship")
        XCTAssertNil(capture.relationCompletes[0].target.line)
        XCTAssertTrue(capture.warnings.contains(where: \.isRelationCompletedSource))

        let presentation = CaptureRelationshipPresentation(capture: capture)
        XCTAssertEqual(
            presentation.rows.map(\.text),
            [
                "🪢 links to “Verify cancel labels” · implemented by   verify.md ^confirm",
                "✓ would complete “Ship retry policy” · Todo → Done",
                "[ ] → [x]  Ship retry policy",
            ]
        )
        XCTAssertEqual(presentation.rows.map(\.usesCompletedTint), [false, true, true])
        XCTAssertTrue(
            CaptureRelationCompletePresentation.previewWarningRows(for: capture).isEmpty
        )

        var withoutCompletes = try decodeSuccess(completeDryRunCaptureJSON)
        withoutCompletes = CaptureCommandSuccess(
            ok: withoutCompletes.ok,
            dryRun: withoutCompletes.dryRun,
            routed: withoutCompletes.routed,
            routeLabel: withoutCompletes.routeLabel,
            relativeTarget: withoutCompletes.relativeTarget,
            target: withoutCompletes.target,
            text: withoutCompletes.text,
            taskLine: withoutCompletes.taskLine,
            kind: withoutCompletes.kind,
            created: withoutCompletes.created,
            placement: withoutCompletes.placement,
            relationUpdates: withoutCompletes.relationUpdates,
            warnings: withoutCompletes.warnings
        )
        let leftover = CaptureRelationCompletePresentation.previewWarningRows(
            for: withoutCompletes
        )
        XCTAssertEqual(leftover.count, 1)
        XCTAssertEqual(leftover[0].style, .completed)
        XCTAssertTrue(leftover[0].text.contains("would complete"))
    }

    func testCommitRowsUseCompletedTense() throws {
        let capture = try decodeSuccess(completeCommittedCaptureJSON)
        XCTAssertFalse(capture.dryRun)
        let presentation = CaptureRelationshipPresentation(capture: capture)
        XCTAssertTrue(
            presentation.rows.contains {
                $0.text.contains("✓ completed “Ship retry policy”")
                    && $0.usesCompletedTint
            }
        )
        XCTAssertFalse(
            presentation.rows.contains { $0.text.contains("would complete") }
        )
    }

    func testSubmitHintCountsCompletesAndMixed() throws {
        let capture = try decodeSuccess(completeDryRunCaptureJSON)
        XCTAssertEqual(
            CaptureRelationCompletePresentation.completeCount(in: [capture]),
            1
        )
        XCTAssertEqual(
            CaptureRelationCompletePresentation.submitHint(completeCount: 1),
            "Capture & complete 1 task"
        )
        XCTAssertEqual(
            CaptureRelationCompletePresentation.submitHint(completeCount: 2),
            "Capture & complete 2 tasks"
        )
        XCTAssertNil(CaptureRelationCompletePresentation.submitHint(completeCount: 0))
        XCTAssertEqual(
            CaptureRelationCompletePresentation.submitHint(cancelCount: 1, completeCount: 1),
            "Capture & close 2 tasks"
        )
        XCTAssertEqual(
            CaptureRelationCompletePresentation.submitHint(cancelCount: 0, completeCount: 1),
            "Capture & complete 1 task"
        )
        XCTAssertEqual(
            CaptureRelationCompletePresentation.submitHint(cancelCount: 2, completeCount: 0),
            "Capture & cancel 2 tasks"
        )
        XCTAssertNil(
            CaptureRelationCompletePresentation.submitHint(cancelCount: 0, completeCount: 0)
        )
    }

    func testRealBobFixturesDecode() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let completion = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(
                contentsOf: fixtures.appendingPathComponent(
                    "relation-complete-complete-implemented-by.json"
                )
            )
        )
        XCTAssertEqual(completion.context, "relation_label")
        XCTAssertEqual(completion.relationComplete?.verdict, "completes")
        XCTAssertEqual(
            completion.relationComplete?.message,
            "✓ Completes “Ship retry policy” · Todo → Done"
        )
        XCTAssertTrue(completion.candidates.contains(where: \.completesSource))

        for fixtureName in [
            "relation-complete-complete-new-task.json",
            "relation-complete-complete-new-task-typed.json",
            "relation-complete-complete-recurring.json",
        ] {
            let refused = try JSONDecoder().decode(
                CaptureCompletionResponse.self,
                from: Data(contentsOf: fixtures.appendingPathComponent(fixtureName))
            )
            let refusedRows = refused.candidates.filter(\.completesSource)
            XCTAssertFalse(refusedRows.isEmpty, "expected complete rows in \(fixtureName)")
            XCTAssertTrue(
                refusedRows.allSatisfy {
                    $0.replacement.isEmpty && $0.disabledReason?.isEmpty == false
                },
                "expected refused complete rows in \(fixtureName)"
            )
        }

        let typedRefusal = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(
                contentsOf: fixtures.appendingPathComponent(
                    "relation-complete-complete-new-task-typed.json"
                )
            )
        )
        let typedRefusedRow = try XCTUnwrap(typedRefusal.candidates.first(where: \.typed))
        XCTAssertTrue(typedRefusedRow.completesSource)
        XCTAssertTrue(typedRefusedRow.replacement.isEmpty)
        XCTAssertTrue(typedRefusedRow.disabledReason?.isEmpty == false)

        let overlay = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(
                contentsOf: fixtures.appendingPathComponent(
                    "relation-complete-complete-impl.json"
                )
            )
        )
        let implementedBy = try XCTUnwrap(
            overlay.candidates.first(where: { $0.key == "implemented by" })
        )
        XCTAssertTrue(implementedBy.completesSource)
        XCTAssertEqual(implementedBy.count, 2)
        XCTAssertEqual(overlay.relationComplete?.verdict, "completes")

        let inverse = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(
                contentsOf: fixtures.appendingPathComponent(
                    "relation-complete-complete-inverse.json"
                )
            )
        )
        XCTAssertEqual(inverse.relationComplete?.verdict, "completes")
        XCTAssertTrue(inverse.relationComplete?.hint?.contains("never completes") == true)

        let closed = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(
                contentsOf: fixtures.appendingPathComponent(
                    "relation-complete-complete-already-closed.json"
                )
            )
        )
        XCTAssertEqual(closed.relationComplete?.verdict, "already_closed")
        XCTAssertEqual(closed.relationComplete?.message, "Already Done · link only")

        let parse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(
                contentsOf: fixtures.appendingPathComponent("relation-complete-parse.json")
            )
        )
        XCTAssertTrue(parse.spans.contains { $0.kind == "relation_label" && $0.completesSource })

        let dryRun = try decodeSuccess(
            String(
                contentsOf: fixtures.appendingPathComponent("relation-complete-dry-run.json"),
                encoding: .utf8
            )
        )
        XCTAssertTrue(dryRun.dryRun)
        XCTAssertFalse(dryRun.relationCompletes.isEmpty)
        XCTAssertEqual(dryRun.relationUpdates.first?.completeEffect, "completed")
        XCTAssertTrue(dryRun.warnings.contains(where: \.isRelationCompletedSource))
        // The dry run recovers one dependent and offers the other, so the
        // in-panel successor choice opens exactly as for `!`.
        let dryTaskComplete = try XCTUnwrap(dryRun.relationCompletes.first?.taskComplete)
        XCTAssertEqual(dryTaskComplete.unblocked.count, 2)
        XCTAssertTrue(dryTaskComplete.unblocked.contains { $0.offer != nil })
        XCTAssertEqual(dryRun.pullIn?.offerCount, 1)
        XCTAssertTrue(
            CaptureRelationshipPresentation(capture: dryRun).rows.contains {
                $0.usesCompletedTint
            }
        )

        let commit = try decodeSuccess(
            String(
                contentsOf: fixtures.appendingPathComponent("relation-complete-commit.json"),
                encoding: .utf8
            )
        )
        XCTAssertFalse(commit.dryRun)
        XCTAssertEqual(commit.relationCompletes.first?.message.contains("completed"), true)
        XCTAssertEqual(commit.relationUpdates.first?.completeEffect, "completed")
        let commitTaskComplete = try XCTUnwrap(commit.relationCompletes.first?.taskComplete)
        XCTAssertTrue(commitTaskComplete.unblocked.contains { $0.offer?.selected == true })
    }

    private func decodeSuccess(_ json: String) throws -> CaptureCommandSuccess {
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(json.utf8)
        )
        guard case .success(let success) = response else {
            throw CompleteFixtureError.expectedSuccess
        }
        return success
    }
}

private enum CompleteFixtureError: Error {
    case expectedSuccess
}

private let completeOldCompletionJSON = """
{
  "ok": true,
  "schema_version": 1,
  "cursor": 30,
  "replacement": {"start": 23, "end": 23},
  "context": "relation_label",
  "candidates": [
    {"replacement": "|follow", "label": "follow-up of", "count": 4, "typed": false}
  ]
}
"""

private let completeVerdictCompletionJSON = """
{
  "ok": true,
  "schema_version": 1,
  "cursor": 54,
  "replacement": {"start": 37, "end": 54},
  "context": "relation_label",
  "query": "implemented by",
  "candidates": [
    {"replacement": "|impl-off", "label": "impl-off", "typed": true, "key": "impl-off", "existing": false},
    {
      "replacement": "|\\"implemented by\\"",
      "label": "implemented by",
      "key": "implemented by",
      "count": 2,
      "completes_source": true,
      "configured": true
    }
  ],
  "relation_complete": {
    "source": {
      "path": "design.md",
      "block_id": "ship",
      "text": "Ship retry policy",
      "status_symbol": " ",
      "status_name": "Todo"
    },
    "verdict": "completes",
    "message": "✓ Completes “Ship retry policy” · Todo → Done"
  }
}
"""

private let completeAlreadyClosedCompletionJSON = """
{
  "ok": true,
  "schema_version": 1,
  "cursor": 20,
  "replacement": {"start": 10, "end": 20},
  "context": "relation_label",
  "query": "implements",
  "candidates": [
    {"replacement": "|implements", "label": "implements", "typed": true, "key": "implements"}
  ],
  "relation_complete": {
    "source": {
      "path": "design.md",
      "block_id": "old",
      "text": "Old idea",
      "status_symbol": "x",
      "status_name": "Done"
    },
    "verdict": "already_closed",
    "message": "Already Done · link only",
    "hint": "“implements” never completes · to finish “Verify cancel labels”, use ~~ with “implemented by”"
  }
}
"""

private let completeOldCaptureJSON = """
{
  "ok": true, "dry_run": true, "routed": false,
  "route_label": "design.md", "relative_target": "design.md",
  "target": "/tmp/vault/design.md", "text": "Ship retry policy",
  "task_line": "- [ ] #task Ship retry policy", "kind": "task",
  "created": "2026-10-28", "placement": "updated",
  "relation_updates": [{
    "direction": "to",
    "source": {"path": "design.md", "line": 1, "block_id": "ship", "text": "Ship retry policy"},
    "target": {"path": "verify.md", "line": 1, "block_id": "confirm", "text": "Verify cancel labels"},
    "label": "follow-up of",
    "action": "added"
  }]
}
"""

private let completeDryRunCaptureJSON = """
{
  "ok": true, "dry_run": true, "routed": true,
  "route": "design", "route_label": "design.md", "relative_target": "design.md",
  "target": "/tmp/vault/design.md", "text": "Close this",
  "task_line": "- Close this", "kind": "sub_bullet",
  "created": "2026-10-28", "placement": "appended", "block_id": "ship",
  "parent_line": 1, "parent_text": "Ship retry policy",
  "parent_status_symbol": " ", "parent_status_name": "Todo",
  "pull_in": {"supported": true, "offer_count": 0, "choice": null, "picked_count": 0},
  "relation_updates": [{
    "direction": "to",
    "source": {"path": "design.md", "line": 1, "block_id": "ship", "text": "Ship retry policy"},
    "target": {"path": "verify.md", "line": 1, "block_id": "confirm", "text": "Verify cancel labels"},
    "label": "implemented by",
    "action": "added",
    "complete_effect": "completed"
  }],
  "relation_completes": [{
    "source": {"path": "design.md", "line": 1, "block_id": "ship", "text": "Ship retry policy"},
    "target": {"path": "verify.md", "block_id": "confirm", "text": "Verify cancel labels"},
    "labels": ["implemented by"],
    "action": "added",
    "previous_status": " ",
    "previous_status_name": "Todo",
    "task_complete": {
      "raw": "~verify:confirm|\\"implemented by\\"",
      "note": "design",
      "note_path": "design.md",
      "block_id": "ship",
      "action": "completed",
      "text": "Ship retry policy",
      "subtasks": [],
      "subtasks_left_open": [],
      "unblocked": [],
      "still_blocked": [],
      "unblocked_check": "checked"
    },
    "message": "✓ would complete “Ship retry policy” · Todo → Done"
  }],
  "warnings": [
    {"code": "relation_completed_source", "label": "implemented by", "message": "✓ would complete “Ship retry policy” (implemented by “Verify cancel labels”)"}
  ]
}
"""

private let completeCommittedCaptureJSON = """
{
  "ok": true, "dry_run": false, "routed": true,
  "route": "design", "route_label": "design.md", "relative_target": "design.md",
  "target": "/tmp/vault/design.md", "text": "Close this",
  "task_line": "- Close this", "kind": "sub_bullet",
  "created": "2026-10-28", "placement": "appended", "block_id": "ship",
  "parent_line": 1, "parent_text": "Ship retry policy",
  "parent_status_symbol": " ", "parent_status_name": "Todo",
  "pull_in": {"supported": true, "offer_count": 0, "choice": "all", "picked_count": 0},
  "relation_updates": [{
    "direction": "to",
    "source": {"path": "design.md", "line": 1, "block_id": "ship", "text": "Ship retry policy"},
    "target": {"path": "verify.md", "line": 1, "block_id": "confirm", "text": "Verify cancel labels"},
    "label": "implemented by",
    "action": "added",
    "complete_effect": "completed"
  }],
  "relation_completes": [{
    "source": {"path": "design.md", "line": 1, "block_id": "ship", "text": "Ship retry policy"},
    "target": {"path": "verify.md", "block_id": "confirm", "text": "Verify cancel labels"},
    "labels": ["implemented by"],
    "action": "added",
    "previous_status": " ",
    "previous_status_name": "Todo",
    "task_complete": {
      "raw": "~verify:confirm|\\"implemented by\\"",
      "note": "design",
      "note_path": "design.md",
      "block_id": "ship",
      "action": "completed",
      "text": "Ship retry policy",
      "subtasks": [],
      "subtasks_left_open": [],
      "unblocked": [],
      "still_blocked": [],
      "unblocked_check": "checked"
    },
    "message": "✓ completed “Ship retry policy” · Todo → Done"
  }],
  "warnings": [
    {"code": "relation_completed_source", "label": "implemented by", "message": "✓ completed “Ship retry policy” (implemented by “Verify cancel labels”)"}
  ]
}
"""
