import Foundation
import XCTest

@testable import CaptureCore

final class CaptureRelationCancelTests: XCTestCase {
    func testOldBobOmitsCancelFields() throws {
        let completion = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(oldCompletionJSON.utf8)
        )
        XCTAssertNil(completion.relationCancel)
        XCTAssertEqual(completion.candidates.count, 1)
        XCTAssertFalse(completion.candidates[0].cancelsSource)
        XCTAssertFalse(completion.candidates[0].configured)

        let span = try JSONDecoder().decode(
            CaptureSpan.self,
            from: Data(#"{"start":40,"end":52,"kind":"relation_label"}"#.utf8)
        )
        XCTAssertFalse(span.cancelsSource)
        XCTAssertEqual(captureSemanticCategory(forSpan: span), .relationLabel)

        let capture = try decodeSuccess(oldCaptureJSON)
        XCTAssertTrue(capture.relationCancels.isEmpty)
        XCTAssertNil(capture.relationUpdates.first?.cancelEffect)
        XCTAssertFalse(capture.warnings.contains(where: \.isRelationCancelledSource))
        XCTAssertTrue(
            CaptureRelationCancelPresentation.previewWarningRows(for: capture).isEmpty
        )
        XCTAssertEqual(
            CaptureRelationshipPresentation(capture: capture).rows.map(\.usesCancelledTint),
            [false]
        )
    }

    func testCompletionCancelFieldsDecode() throws {
        let completion = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(cancelCompletionJSON.utf8)
        )
        let cancel = try XCTUnwrap(completion.relationCancel)
        XCTAssertEqual(cancel.verdict, "cancels")
        XCTAssertEqual(cancel.source.path, "cash.md")
        XCTAssertEqual(cancel.source.blockID, "sell")
        XCTAssertEqual(cancel.source.text, "Sell stocks!")
        XCTAssertEqual(cancel.source.statusSymbol, " ")
        XCTAssertEqual(cancel.source.statusName, "Todo")
        XCTAssertEqual(
            cancel.message,
            "⊘ Cancels “Sell stocks!” · Todo → Cancelled"
        )
        XCTAssertNil(cancel.hint)

        let overlay = try XCTUnwrap(
            completion.candidates.first(where: { $0.key == "duplicate of" })
        )
        XCTAssertTrue(overlay.cancelsSource)
        XCTAssertTrue(overlay.configured)
        XCTAssertEqual(overlay.replacement, "|\"duplicate of\"")

        let typed = try XCTUnwrap(completion.candidates.first(where: { $0.typed }))
        XCTAssertFalse(typed.cancelsSource)
        XCTAssertFalse(typed.configured)
    }

    func testAlreadyClosedAndHintDecode() throws {
        let completion = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(alreadyClosedCompletionJSON.utf8)
        )
        let cancel = try XCTUnwrap(completion.relationCancel)
        XCTAssertEqual(cancel.verdict, "already_closed")
        XCTAssertEqual(cancel.message, "Already Cancelled · link only")
        XCTAssertEqual(
            cancel.hint,
            "“supersedes” never cancels · to retire “Sell stocks now!”, use ~~ with “superseded by”"
        )
    }

    func testParseSpanCancelTint() throws {
        let span = try JSONDecoder().decode(
            CaptureSpan.self,
            from: Data(
                #"{"start":40,"end":52,"kind":"relation_label","cancels_source":true}"#.utf8
            )
        )
        XCTAssertTrue(span.cancelsSource)
        XCTAssertEqual(captureSemanticCategory(forSpan: span), .relationCancelLabel)
        XCTAssertTrue(CaptureSemanticCategory.relationCancelLabel.isItalic)
        XCTAssertTrue(CaptureSemanticCategory.relationLabel.isItalic)
    }

    func testRelationLabelRowCapsuleBadge() {
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

    func testSlotAndDimmedSourcePerVerdict() {
        let canceling = CaptureCompletionCandidate(
            replacement: "|\"duplicate of\"",
            label: "duplicate of",
            cancelsSource: true
        )
        let ordinary = CaptureCompletionCandidate(
            replacement: "|implements",
            label: "implements"
        )
        let cancels = CaptureCompletionRelationCancel(
            source: CaptureCompletionRelationCancelSource(text: "Sell stocks!"),
            verdict: "cancels",
            message: "⊘ Cancels “Sell stocks!” · Todo → Cancelled"
        )
        let closed = CaptureCompletionRelationCancel(
            source: CaptureCompletionRelationCancelSource(text: "Gone idea"),
            verdict: "already_closed",
            message: "Already Cancelled · link only"
        )
        let recurring = CaptureCompletionRelationCancel(
            source: CaptureCompletionRelationCancelSource(text: "Weekly review"),
            verdict: "recurring",
            message: "“Weekly review” repeats — cancel it with Obsidian Tasks first"
        )
        let hinted = CaptureCompletionRelationCancel(
            source: CaptureCompletionRelationCancelSource(text: "Sell stocks!"),
            verdict: "cancels",
            message: "⊘ Cancels “Sell stocks!” · Todo → Cancelled",
            hint: "“supersedes” never cancels · to retire “Sell stocks now!”, use ~~ with “superseded by”"
        )

        XCTAssertTrue(
            CaptureRelationCancelPresentation.dimsSource(candidate: canceling, cancel: cancels)
        )
        XCTAssertFalse(
            CaptureRelationCancelPresentation.dimsSource(candidate: canceling, cancel: closed)
        )
        XCTAssertFalse(
            CaptureRelationCancelPresentation.dimsSource(candidate: ordinary, cancel: cancels)
        )
        XCTAssertEqual(
            CaptureRelationCancelPresentation.slot(candidate: canceling, cancel: cancels),
            CaptureRelationCancelSlot(
                text: "⊘ Cancels “Sell stocks!” · Todo → Cancelled",
                style: .cancels
            )
        )
        XCTAssertEqual(
            CaptureRelationCancelPresentation.slot(candidate: canceling, cancel: closed),
            CaptureRelationCancelSlot(text: "Already Cancelled · link only", style: .muted)
        )
        XCTAssertNil(
            CaptureRelationCancelPresentation.slot(candidate: canceling, cancel: recurring)
        )
        XCTAssertEqual(
            CaptureRelationCancelPresentation.slot(candidate: ordinary, cancel: hinted)?.style,
            .muted
        )
        XCTAssertEqual(
            CaptureRelationCancelPresentation.sourceAccessibilityLabel(
                sourceText: "Sell stocks!",
                dimsSource: true
            ),
            "Cancels Sell stocks!"
        )
    }

    func testCaptureCancelRowsAndWarningRestyle() throws {
        let capture = try decodeSuccess(cancelCaptureJSON)
        XCTAssertEqual(capture.relationUpdates.first?.cancelEffect, "cancelled")
        XCTAssertEqual(capture.relationCancels.count, 1)
        XCTAssertEqual(
            capture.relationCancels[0].previousStatus,
            " "
        )
        XCTAssertEqual(capture.relationCancels[0].previousStatusName, "Todo")
        XCTAssertEqual(capture.relationCancels[0].source.blockID, "sell")
        XCTAssertNil(capture.relationCancels[0].target.line)
        XCTAssertTrue(capture.warnings.contains(where: \.isRelationCancelledSource))

        let presentation = CaptureRelationshipPresentation(capture: capture)
        XCTAssertEqual(
            presentation.rows.map(\.text),
            [
                "🪢 links to “Sell stocks now!” · duplicate of   invest.md ^now",
                "⊘ would cancel “Sell stocks!” · Todo → Cancelled",
            ]
        )
        XCTAssertEqual(presentation.rows.map(\.usesCancelledTint), [false, true])
        XCTAssertTrue(
            CaptureRelationCancelPresentation.previewWarningRows(for: capture).isEmpty
        )

        var withoutCancels = try decodeSuccess(cancelCaptureJSON)
        withoutCancels = CaptureCommandSuccess(
            ok: withoutCancels.ok,
            dryRun: withoutCancels.dryRun,
            routed: withoutCancels.routed,
            routeLabel: withoutCancels.routeLabel,
            relativeTarget: withoutCancels.relativeTarget,
            target: withoutCancels.target,
            text: withoutCancels.text,
            taskLine: withoutCancels.taskLine,
            kind: withoutCancels.kind,
            created: withoutCancels.created,
            placement: withoutCancels.placement,
            relationUpdates: withoutCancels.relationUpdates,
            warnings: withoutCancels.warnings
        )
        let leftover = CaptureRelationCancelPresentation.previewWarningRows(for: withoutCancels)
        XCTAssertEqual(leftover.count, 1)
        XCTAssertEqual(leftover[0].style, .cancelled)
        XCTAssertTrue(leftover[0].text.contains("would cancel"))
    }

    func testHideWarningStaysAmberBesideCancelRows() throws {
        let capture = try decodeSuccess(hideAndCancelJSON)
        let warnings = CaptureRelationCancelPresentation.previewWarningRows(for: capture)
        XCTAssertEqual(warnings.map(\.style), [.amber])
        XCTAssertTrue(warnings[0].text.contains("hides"))
        XCTAssertEqual(
            CaptureRelationCancelPresentation.startCardWarningRows(for: capture).map(\.style),
            [.amber]
        )
    }

    func testSubmitHintCountsCancels() throws {
        let capture = try decodeSuccess(cancelCaptureJSON)
        XCTAssertEqual(CaptureRelationCancelPresentation.cancelCount(in: [capture]), 1)
        XCTAssertEqual(
            CaptureRelationCancelPresentation.submitHint(cancelCount: 1),
            "Capture & cancel 1 task"
        )
        XCTAssertEqual(
            CaptureRelationCancelPresentation.submitHint(cancelCount: 2),
            "Capture & cancel 2 tasks"
        )
        XCTAssertNil(CaptureRelationCancelPresentation.submitHint(cancelCount: 0))
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
                    "relation-cancel-complete-duplicate.json"
                )
            )
        )
        XCTAssertEqual(completion.context, "relation_label")
        XCTAssertEqual(completion.relationCancel?.verdict, "cancels")
        XCTAssertEqual(
            completion.relationCancel?.message,
            "⊘ Cancels “Sell stocks!” · Todo → Cancelled"
        )
        XCTAssertTrue(completion.candidates.contains(where: \.cancelsSource))

        let overlay = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(
                contentsOf: fixtures.appendingPathComponent(
                    "relation-cancel-complete-dup.json"
                )
            )
        )
        let configured = try XCTUnwrap(
            overlay.candidates.first(where: { $0.configured })
        )
        XCTAssertTrue(configured.cancelsSource)
        XCTAssertEqual(configured.key, "duplicate of")

        let inverse = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(
                contentsOf: fixtures.appendingPathComponent(
                    "relation-cancel-complete-inverse.json"
                )
            )
        )
        XCTAssertEqual(inverse.relationCancel?.verdict, "cancels")
        XCTAssertTrue(inverse.relationCancel?.hint?.contains("never cancels") == true)

        let closed = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(
                contentsOf: fixtures.appendingPathComponent(
                    "relation-cancel-complete-already-closed.json"
                )
            )
        )
        XCTAssertEqual(closed.relationCancel?.verdict, "already_closed")
        XCTAssertEqual(closed.relationCancel?.message, "Already Cancelled · link only")

        let parse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(
                contentsOf: fixtures.appendingPathComponent("relation-cancel-parse.json")
            )
        )
        XCTAssertTrue(parse.spans.contains { $0.kind == "relation_label" && $0.cancelsSource })

        let dryRun = try decodeSuccess(
            String(
                contentsOf: fixtures.appendingPathComponent("relation-cancel-dry-run.json"),
                encoding: .utf8
            )
        )
        XCTAssertTrue(dryRun.dryRun)
        XCTAssertFalse(dryRun.relationCancels.isEmpty)
        XCTAssertEqual(dryRun.relationUpdates.first?.cancelEffect, "cancelled")
        XCTAssertTrue(dryRun.warnings.contains(where: \.isRelationCancelledSource))
        XCTAssertTrue(
            CaptureRelationshipPresentation(capture: dryRun).rows.contains {
                $0.usesCancelledTint
            }
        )

        let commit = try decodeSuccess(
            String(
                contentsOf: fixtures.appendingPathComponent("relation-cancel-commit.json"),
                encoding: .utf8
            )
        )
        XCTAssertFalse(commit.dryRun)
        XCTAssertEqual(commit.relationCancels.first?.message.contains("cancelled"), true)
        XCTAssertEqual(commit.relationUpdates.first?.cancelEffect, "cancelled")
    }

    private func decodeSuccess(_ json: String) throws -> CaptureCommandSuccess {
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(json.utf8)
        )
        guard case .success(let success) = response else {
            throw FixtureError.expectedSuccess
        }
        return success
    }
}

private enum FixtureError: Error {
    case expectedSuccess
}

private let oldCompletionJSON = """
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

private let cancelCompletionJSON = """
{
  "ok": true,
  "schema_version": 1,
  "cursor": 40,
  "replacement": {"start": 33, "end": 37},
  "context": "relation_label",
  "query": "dup",
  "candidates": [
    {"replacement": "|dup", "label": "dup", "typed": true, "key": "dup", "existing": false},
    {
      "replacement": "|\\"duplicate of\\"",
      "label": "duplicate of",
      "key": "duplicate of",
      "count": 0,
      "cancels_source": true,
      "configured": true
    }
  ],
  "relation_cancel": {
    "source": {
      "path": "cash.md",
      "block_id": "sell",
      "text": "Sell stocks!",
      "status_symbol": " ",
      "status_name": "Todo"
    },
    "verdict": "cancels",
    "message": "⊘ Cancels “Sell stocks!” · Todo → Cancelled"
  }
}
"""

private let alreadyClosedCompletionJSON = """
{
  "ok": true,
  "schema_version": 1,
  "cursor": 20,
  "replacement": {"start": 10, "end": 20},
  "context": "relation_label",
  "query": "supersedes",
  "candidates": [
    {"replacement": "|supersedes", "label": "supersedes", "typed": true, "key": "supersedes"}
  ],
  "relation_cancel": {
    "source": {
      "path": "invest.md",
      "block_id": "gone",
      "text": "Gone idea",
      "status_symbol": "-",
      "status_name": "Cancelled"
    },
    "verdict": "already_closed",
    "message": "Already Cancelled · link only",
    "hint": "“supersedes” never cancels · to retire “Sell stocks now!”, use ~~ with “superseded by”"
  }
}
"""

private let oldCaptureJSON = """
{
  "ok": true, "dry_run": true, "routed": false,
  "route_label": "cash.md", "relative_target": "cash.md",
  "target": "/tmp/vault/cash.md", "text": "Sell stocks!",
  "task_line": "- [ ] #task Sell stocks!", "kind": "task",
  "created": "2026-10-28", "placement": "updated",
  "relation_updates": [{
    "direction": "to",
    "source": {"path": "cash.md", "line": 1, "block_id": "sell", "text": "Sell stocks!"},
    "target": {"path": "invest.md", "line": 1, "block_id": "now", "text": "Sell stocks now!"},
    "label": "follow-up of",
    "action": "added"
  }]
}
"""

private let cancelCaptureJSON = """
{
  "ok": true, "dry_run": true, "routed": false,
  "route_label": "cash.md", "relative_target": "cash.md",
  "target": "/tmp/vault/cash.md", "text": "Sell stocks!",
  "task_line": "- [ ] #task Sell stocks!", "kind": "task",
  "created": "2026-10-28", "placement": "updated",
  "relation_updates": [{
    "direction": "to",
    "source": {"path": "cash.md", "line": 1, "block_id": "sell", "text": "Sell stocks!"},
    "target": {"path": "invest.md", "line": 1, "block_id": "now", "text": "Sell stocks now!"},
    "label": "duplicate of",
    "action": "added",
    "cancel_effect": "cancelled"
  }],
  "relation_cancels": [{
    "source": {"path": "cash.md", "line": 1, "block_id": "sell", "text": "Sell stocks!"},
    "target": {"path": "invest.md", "block_id": "now", "text": "Sell stocks now!"},
    "labels": ["duplicate of"],
    "action": "added",
    "previous_status": " ",
    "previous_status_name": "Todo",
    "cancel_log": "none",
    "pomodoro_links_removed": 0,
    "recovered": [],
    "message": "⊘ would cancel “Sell stocks!” · Todo → Cancelled"
  }],
  "warnings": [{
    "code": "relation_cancelled_source",
    "label": "duplicate of",
    "message": "⊘ would cancel “Sell stocks!” (“duplicate of” “Sell stocks now!”)"
  }]
}
"""

private let hideAndCancelJSON = """
{
  "ok": true, "dry_run": true, "routed": false,
  "route_label": "cash.md", "relative_target": "cash.md",
  "target": "/tmp/vault/cash.md", "text": "Sell stocks!",
  "task_line": "- [ ] #task Sell stocks!", "kind": "task",
  "created": "2026-10-28", "placement": "updated",
  "relation_updates": [{
    "direction": "to",
    "source": {"path": "cash.md", "line": 1, "block_id": "sell", "text": "Sell stocks!"},
    "target": {"path": "invest.md", "line": 1, "block_id": "now", "text": "Sell stocks now!"},
    "label": "duplicate of",
    "action": "added",
    "cancel_effect": "cancelled"
  }],
  "relation_cancels": [{
    "source": {"path": "cash.md", "line": 1, "block_id": "sell", "text": "Sell stocks!"},
    "target": {"path": "invest.md", "block_id": "now", "text": "Sell stocks now!"},
    "labels": ["duplicate of"],
    "action": "added",
    "previous_status": " ",
    "previous_status_name": "Todo",
    "cancel_log": "none",
    "pomodoro_links_removed": 0,
    "recovered": [],
    "message": "⊘ would cancel “Sell stocks!” · Todo → Cancelled"
  }],
  "warnings": [
    {
      "code": "relation_cancelled_source",
      "label": "duplicate of",
      "message": "⊘ would cancel “Sell stocks!” (“duplicate of” “Sell stocks now!”)"
    },
    {
      "code": "hides_existing_relation_label",
      "label": "duplicate of",
      "count": 1,
      "message": "hides \\"duplicate of\\" from relation suggestions (1 links)"
    }
  ]
}
"""
