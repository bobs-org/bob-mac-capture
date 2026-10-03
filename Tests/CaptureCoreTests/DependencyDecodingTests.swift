import XCTest

@testable import CaptureCore

/// Decoding tests for the additive `task_dependency` wire shapes: the
/// exact-path `capture-task-id` success, the `dependency_update` capture
/// detail, and the dependency parse spans. Payloads mirror real Bob output.
final class DependencyDecodingTests: XCTestCase {
    func testTaskIDNotePathSuccess() throws {
        let response = try JSONDecoder().decode(
            CaptureTaskIDResponse.self,
            from: Data("""
            {
              "ok": true, "schema_version": 1, "dry_run": true,
              "relative_target": "cash.md",
              "note_path": "cash.md",
              "block_id": "grocery-run",
              "dependency_replacement": "&cash:grocery-run",
              "line": 20,
              "ref": "20:bb67e4a6",
              "task": {
                "ref": "20:bb67e4a6", "line": 20, "block_id": "grocery-run",
                "status_symbol": " ", "status_name": "Todo", "status_type": "TODO",
                "text": "Figure out snacks", "section": "Tasks",
                "depth": 0, "child_count": 0
              }
            }
            """.utf8)
        )
        guard case .success(let success) = response else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(success.route, "")
        XCTAssertEqual(success.notePath, "cash.md")
        XCTAssertEqual(success.dependencyReplacement, "&cash:grocery-run")
    }

    func testTaskIDRouteSuccessStillDecodes() throws {
        let response = try JSONDecoder().decode(
            CaptureTaskIDResponse.self,
            from: Data("""
            {
              "ok": true, "schema_version": 1, "dry_run": false,
              "route": "cash", "relative_target": "cash.md",
              "block_id": "grocery-run", "line": 20, "ref": "20:bb67e4a6",
              "task": {
                "ref": "20:bb67e4a6", "line": 20, "block_id": "grocery-run",
                "status_symbol": " ", "status_name": "Todo", "status_type": "TODO",
                "text": "Figure out snacks", "section": "Tasks",
                "depth": 0, "child_count": 0
              }
            }
            """.utf8)
        )
        guard case .success(let success) = response else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(success.route, "cash")
        XCTAssertNil(success.notePath)
        XCTAssertNil(success.dependencyReplacement)
    }

    func testDependencyUpdateDecodes() throws {
        let update = try JSONDecoder().decode(
            DependencyUpdateSummary.self,
            from: Data("""
            {
              "dependent_note": "mac_inbox.md",
              "dependent_text": "Buy Groceries!",
              "new_task": true,
              "added": 1, "already_present": 0, "open_prerequisites": 1,
              "prerequisites": [
                {
                  "note": "cash.md", "block_id": "find-real-id-number",
                  "link": "[[cash#^find-real-id-number]]",
                  "status_symbol": "?", "status_name": "Blocked",
                  "text": "Find number you need", "open": true
                }
              ],
              "dependent_status": "?",
              "dependent_status_name": "Blocked",
              "status_changed": true
            }
            """.utf8)
        )
        XCTAssertEqual(update.headline, "New task · depends on 1 task")
        XCTAssertEqual(update.managedLineText, "**DEPENDS ON:** [[cash#^find-real-id-number]]")
        XCTAssertEqual(update.waitingText, "Waiting on 1 open prerequisite · Blocked")
        XCTAssertTrue(update.prerequisites[0].isOpen)
    }

    func testDependencyUpdateHeadlineForExistingDependent() {
        let update = DependencyUpdateSummary(
            dependentNote: "body.md",
            dependentText: "Exercise",
            isNewTask: false,
            added: 1,
            alreadyPresent: 1,
            openPrerequisites: 0,
            prerequisites: [],
            dependentStatus: " ",
            dependentStatusName: "Todo",
            statusChanged: false
        )
        XCTAssertEqual(update.headline, "Add dependency to \u{201C}Exercise\u{201D}")
        XCTAssertEqual(update.waitingText, "No open prerequisites · Todo")
        XCTAssertTrue(update.previewAccessibilitySummary.contains("1 already present"))
    }

    func testDependencySpansHighlight() {
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "dependency_sigil"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "dependency_note"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "dependency_block_id"), .blockID)
    }

    func testDependencySourceStrings() {
        let source = CapturePickerSource.dependency
        XCTAssertEqual(source.triggerByte, 38)
        XCTAssertEqual(source.scopeSymbolText, "&")
        XCTAssertEqual(source.scopeCaption, "Depends On")
        XCTAssertEqual(source.chipLabel, "Choose dependency")
        XCTAssertEqual(source.cardAccessibilityLabel, "Dependency picker")
        XCTAssertEqual(source.pickerUsedDefaultsKey, "org.bobs.bob-mac-capture.dependency-picker-used")
    }

    func testDependencyNeedStatus() {
        XCTAssertEqual(
            CapturePickerNeed.dependency.statusText,
            "Pick a prerequisite — press Tab to browse"
        )
    }
}
