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

    func testBlockedTaskIDReplacementDecodes() throws {
        let response = try JSONDecoder().decode(
            CaptureTaskIDResponse.self,
            from: Data("""
            {
              "ok": true, "schema_version": 1, "dry_run": true,
              "note_path": "job.md", "relative_target": "job.md",
              "block_id": "cleanup", "blocked_task_replacement": "*job:cleanup",
              "line": 4, "ref": "4:bb67e4a6",
              "task": {
                "ref": "4:bb67e4a6", "line": 4, "block_id": "cleanup",
                "status_symbol": " ", "status_name": "Todo", "status_type": "TODO",
                "text": "Clean up", "section": "Tasks",
                "depth": 0, "child_count": 0
              }
            }
            """.utf8)
        )
        guard case .success(let success) = response else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(success.blockedTaskReplacement, "*job:cleanup")
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
        XCTAssertNil(update.prerequisites[0].alreadyPresent)
        XCTAssertNil(update.prerequisites[0].previousStatus)
        XCTAssertNil(update.prerequisites[0].previousStatusName)
    }

    func testPrerequisiteAlreadyPresentAndPreviousStatusDecodeAdditively() throws {
        let update = try JSONDecoder().decode(
            DependencyUpdateSummary.self,
            from: Data("""
            {
              "dependent_note": "body.md",
              "dependent_text": "Exercise",
              "new_task": false,
              "added": 1, "already_present": 1, "open_prerequisites": 2,
              "prerequisites": [
                {
                  "note": "foo.md", "block_id": "bar",
                  "link": "[[foo#^bar]]",
                  "status_symbol": "/", "status_name": "In Progress",
                  "text": "Buy shoes", "open": true,
                  "already_present": true
                },
                {
                  "note": "foo.md", "block_id": "socks",
                  "link": "[[foo#^socks]]",
                  "status_symbol": "/", "status_name": "In Progress",
                  "previous_status": " ", "previous_status_name": "Ready",
                  "text": "Buy socks", "open": true
                }
              ],
              "dependent_status": "?",
              "dependent_status_name": "Blocked",
              "status_changed": true
            }
            """.utf8)
        )
        XCTAssertEqual(update.prerequisites[0].alreadyPresent, true)
        XCTAssertNil(update.prerequisites[0].previousStatus)
        XCTAssertEqual(update.prerequisites[1].alreadyPresent, nil)
        XCTAssertEqual(update.prerequisites[1].previousStatus, " ")
        XCTAssertEqual(update.prerequisites[1].previousStatusName, "Ready")
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

    func testBlockedTaskContextAndSpans() {
        XCTAssertEqual(CaptureCompletionContext(rawContext: "blocked_task"), .blockedTask)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "blocked_task_sigil"), .blockedTaskSigil)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "blocked_task_note"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "blocked_task_block_id"), .blockID)
    }

    func testBlockedTaskCandidateAndPickerSourceDecode() throws {
        let candidate = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data("""
            {
              "replacement": "*job:cleanup", "ref": "4:bb67e4a6",
              "note_path": "job.md", "locator": "job", "group": "open",
              "block_id": "cleanup", "already_blocked": true,
              "status_symbol": " ", "status_name": "Todo", "text": "Clean up"
            }
            """.utf8)
        )
        XCTAssertTrue(candidate.alreadyBlocked)

        let source = CapturePickerSource.blockedTask
        XCTAssertEqual(source.triggerByte, 42)
        XCTAssertEqual(source.scopeSymbolText, "*")
        XCTAssertEqual(source.scopeCaption, "Blocks")
        XCTAssertEqual(source.chipLabel, "Choose task to block")
        XCTAssertEqual(source.cardAccessibilityLabel, "Blocks picker")
    }

    func testCapturePreviewDecodesBlockedUpdatesConsumptionAndRemovedSession() throws {
        let success = try decodeCaptureSuccess("""
        {
          "ok": true, "dry_run": true, "routed": false,
          "route_label": "mac_inbox.md", "relative_target": "mac_inbox.md",
          "target": "/tmp/vault/mac_inbox.md", "text": "Ask Kelly",
          "task_line": "- [ ] #task Ask Kelly", "kind": "task",
          "created": "2026-10-14", "placement": "created",
          "dependency_updates": [{
            "role": "blocked_task", "dependent_note": "job.md",
            "dependent_block_id": "cleanup", "dependent_text": "Clean up",
            "previous_status": " ", "previous_status_name": "Todo",
            "dependent_status": "?", "dependent_status_name": "Blocked",
            "blocked_residents": 2, "prerequisites": []
          }],
          "consumed_links": [
            {
              "day_file": "2026/20261014.md", "line": 5,
              "link": "[[job#^cleanup]]", "note": "job.md",
              "block_id": "cleanup", "text": "Clean up", "action": "removed",
              "pomodoro": {"line": 4, "name": "JOB", "time_range": "1010-1035",
                "status": "running", "removed": true}
            },
            {
              "day_file": "2026/20261014.md", "line": 9,
              "link": "[[job#^other]]", "note": "job.md",
              "block_id": "other", "text": "Other", "action": "notes_kept",
              "pomodoro": {"line": 8, "name": "PLAN", "status": "queued", "removed": false}
            }
          ],
          "minted_blocker_block_id": {"path": "mac_inbox.md", "line": 1, "block_id": "ask-kelly"},
          "pomodoro_blocks": [{"relative_target": "2026/20261014.md", "line": 4,
            "name": "JOB", "status": "running", "removed": true, "lines": []}]
        }
        """)

        XCTAssertEqual(success.dependencyUpdates.first?.role, "blocked_task")
        XCTAssertEqual(success.dependencyUpdates.first?.blockedResidents, 2)
        XCTAssertEqual(success.mintedBlockerBlockID?.blockID, "ask-kelly")
        XCTAssertEqual(success.consumedLinks.count, 2)
        XCTAssertEqual(
            success.consumedLinks[0].previewText(dryRun: true),
            "− would remove its Task Link from JOB 1010-1035 (running) · would delete the empty Pomodoro"
        )
        XCTAssertEqual(
            success.consumedLinks[1].previewText(dryRun: true),
            "− would keep its notes under PLAN as plain text"
        )
        XCTAssertTrue(success.pomodoroBlocks[0].removed)
    }

    func testDependencyUpdatesFallBackToLegacySingularSummary() throws {
        let success = try decodeCaptureSuccess("""
        {
          "ok": true, "dry_run": true, "routed": false,
          "route_label": "inbox.md", "relative_target": "inbox.md",
          "target": "/tmp/vault/inbox.md", "text": "Do work",
          "task_line": "- [ ] #task Do work", "kind": "task",
          "created": "2026-10-14", "placement": "created",
          "dependency_update": {"dependent_note": "inbox.md", "dependent_text": "Do work"}
        }
        """)
        XCTAssertEqual(success.dependencyUpdates, [success.dependencyUpdate!])
    }

    func testRealBobBlockedTaskFixturesDecode() throws {
        let parse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("blocked-task-parse.json").utf8)
        )
        XCTAssertEqual(parse.mode, "task")
        XCTAssertEqual(parse.body, "Ask Kelly")
        XCTAssertEqual(
            parse.spans.map(\.kind),
            ["blocked_task_sigil", "blocked_task_note", "blocked_task_block_id"]
        )

        let need = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("blocked-task-parse-need.json").utf8)
        )
        XCTAssertEqual(need.needs, ["blocked_task"])

        let complete = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(fixtureText("blocked-task-complete.json").utf8)
        )
        XCTAssertEqual(complete.context, "blocked_task")
        XCTAssertEqual(complete.candidates.first?.replacement, "*job:cleanup")
        XCTAssertEqual(complete.owner?.kind, "new_task")

        let taskID = try JSONDecoder().decode(
            CaptureTaskIDResponse.self,
            from: Data(fixtureText("blocked-task-task-id-success.json").utf8)
        )
        guard case .success(let assignment) = taskID else {
            return XCTFail("expected task ID assignment success")
        }
        XCTAssertEqual(assignment.blockedTaskReplacement, "*job:call-bank")

        let created = try decodeFixture("blocked-task-preview-new.json")
        XCTAssertEqual(created.dependencyUpdates.first?.role, "blocked_task")
        XCTAssertEqual(created.mintedBlockerBlockID?.blockID, "ask-kelly")

        let removed = try decodeFixture("blocked-task-preview-running-removed.json")
        XCTAssertEqual(removed.consumedLinks.first?.action, "removed")
        XCTAssertTrue(try XCTUnwrap(removed.consumedLinks.first?.pomodoro.removed))
        XCTAssertTrue(try XCTUnwrap(removed.pomodoroBlocks.first?.removed))

        let notesKept = try decodeFixture("blocked-task-preview-notes-kept.json")
        XCTAssertEqual(notesKept.consumedLinks.first?.action, "notes_kept")
        XCTAssertFalse(try XCTUnwrap(notesKept.consumedLinks.first?.pomodoro.removed))

        let project = try decodeFixture("blocked-task-preview-project.json")
        XCTAssertEqual(project.dependencyUpdates.first?.dependentBlockID, "prj")
        XCTAssertGreaterThan(try XCTUnwrap(project.dependencyUpdates.first?.blockedResidents), 0)
    }

    private func decodeCaptureSuccess(_ json: String) throws -> CaptureCommandSuccess {
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: Data(json.utf8))
        guard case .success(let success) = response else {
            throw NSError(domain: "DependencyDecodingTests", code: 1)
        }
        return success
    }

    private func decodeFixture(_ name: String) throws -> CaptureCommandSuccess {
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(fixtureText(name).utf8)
        )
        guard case .success(let success) = response else {
            throw NSError(domain: "DependencyDecodingTests", code: 2)
        }
        return success
    }

    private func fixtureText(_ name: String) throws -> String {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        return try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
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

    func testBlockedTaskNeedStatus() {
        XCTAssertEqual(
            CapturePickerNeed.blockedTask.statusText,
            "Pick a task to block — press Tab to browse"
        )
    }

    func testRelationNeedStatusAndSpans() {
        XCTAssertEqual(
            CapturePickerNeed.relationTarget.statusText,
            "Pick a task to link — press Tab to browse"
        )
        XCTAssertEqual(
            CapturePickerNeed.relationLabel.statusText,
            "Type a relation label, or pick a suggestion"
        )
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "relation_sigil"), .relationSigil)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "relation_note"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "relation_block_id"), .blockID)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "relation_label_separator"), .interactivePlaceholder)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "relation_label"), .relationLabel)
        XCTAssertTrue(CaptureSemanticCategory.relationLabel.isItalic)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "relation_to"), .relationTo)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "relation_from"), .relationFrom)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "relation_label"), .relationLabel)
    }

    func testRelationCandidateAndPickerSourceDecode() throws {
        let candidate = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data("""
            {
              "replacement": "~tasks:target", "ref": "1:aaaa1111",
              "note_path": "tasks.md", "locator": "tasks", "group": "open",
              "block_id": "target", "already_linked": true,
              "existing_label": "follow-up of", "also_prerequisite": true,
              "status_symbol": " ", "status_name": "Todo", "text": "Target"
            }
            """.utf8)
        )
        XCTAssertTrue(candidate.alreadyLinked)
        XCTAssertEqual(candidate.existingLabel, "follow-up of")
        XCTAssertTrue(candidate.alsoPrerequisite)

        XCTAssertEqual(CapturePickerSource.linksTo.triggerByte, 126)
        XCTAssertEqual(CapturePickerSource.linksTo.scopeSymbolText, "~")
        XCTAssertEqual(CapturePickerSource.linkedFrom.scopeSymbolText, "~~")
        XCTAssertEqual(CapturePickerSource.linksTo.scopeCaption, "Links To")
        XCTAssertEqual(CapturePickerSource.linkedFrom.scopeCaption, "Linked From")
        XCTAssertEqual(CapturePickerSource.linksTo.chipLabel, "Choose a task to link to")
        XCTAssertTrue(CapturePickerSource.linksTo.isRelation)
        XCTAssertTrue(CapturePickerSource.linkedFrom.isRelationshipModifier)
        XCTAssertEqual(DependencyPickerDirection.linkedFrom.leadingSigil, "~~")
        XCTAssertEqual(DependencyPickerDirection.linkedFrom.leadingSigil.utf8.count, 2)
    }

    func testRelationParseAndTaskIDFixturesDecode() throws {
        let parse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("relation-parse-complete.json").utf8)
        )
        XCTAssertEqual(parse.relations.first?.raw, "~tasks:target")
        XCTAssertEqual(parse.relations.first?.direction, "to")
        XCTAssertEqual(parse.relations.first?.note, "tasks")
        XCTAssertEqual(parse.relations.first?.blockID, "target")

        let fromParse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("relation-parse-from-complete.json").utf8)
        )
        XCTAssertEqual(fromParse.relations.first?.direction, "from")

        let labelParse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("relation-parse-label.json").utf8)
        )
        XCTAssertEqual(labelParse.relations.first?.label, "follow")
        XCTAssertEqual(labelParse.relations.first?.labelRange?.start, 40)

        let response = try JSONDecoder().decode(
            CaptureTaskIDResponse.self,
            from: Data(fixtureText("relation-task-id-success.json").utf8)
        )
        guard case .success(let success) = response else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(success.relationToReplacement, "~tasks:idless-source")
        XCTAssertEqual(success.relationFromReplacement, "~~tasks:idless-source")
    }

    func testRelationCompletionFixtureDecodesOwnerAndFlags() throws {
        let decoded = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(fixtureText("relation-complete-owner-to.json").utf8)
        )
        XCTAssertEqual(decoded.context, "relation_to")
        XCTAssertEqual(decoded.owner?.text, "Owner")
        XCTAssertNil(decoded.relation)
        let target = try XCTUnwrap(decoded.candidates.first { $0.blockID == "target" })
        XCTAssertTrue(target.alreadyLinked)
        XCTAssertEqual(target.existingLabel, "follow-up of")
        XCTAssertTrue(target.alsoPrerequisite)
        XCTAssertEqual(target.replacement, "~tasks:target")

        let parent = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(fixtureText("relation-complete-parent.json").utf8)
        )
        XCTAssertEqual(parent.picker?.relationship?.relations.first?.direction, "to")
        XCTAssertEqual(parent.picker?.relationship?.relations.first?.text, "Target")

        let linkedFrom = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(fixtureText("relation-complete-owner-from.json").utf8)
        )
        XCTAssertNil(linkedFrom.relation)
    }

    func testParseTargetFixtureDecodesRelationshipMarkers() throws {
        let parse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("task-dependency-parse-target.json").utf8)
        )
        XCTAssertEqual(parse.needs, ["dependency_target"])
        XCTAssertEqual(parse.dependencies.first?.raw, "&foo:bar")
        XCTAssertEqual(parse.dependencies.first?.note, "foo")
        XCTAssertEqual(parse.dependencies.first?.blockID, "bar")
        XCTAssertNil(parse.dependencyTarget)
    }

    func testExistingOwnerCompleteFixtureDecodesTextAndThisNote() throws {
        let complete = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(fixtureText("task-dependency-complete-body-exercise.json").utf8)
        )
        XCTAssertEqual(complete.owner?.text, "Exercise")
        XCTAssertEqual(complete.owner?.notePath, "body.md")
        XCTAssertEqual(complete.owner?.statusName, "In Progress")
        XCTAssertEqual(complete.candidates.first?.group, "in_this_note")
        let presentation = DependencyPickerIndex(
            candidates: complete.candidates
        ).presentation(filter: "")
        XCTAssertEqual(presentation.sections.first?.kind, .thisNote)
        XCTAssertEqual(presentation.sections.first?.title, "This note")
    }

    func testRelationGrammarDecodesTolerantly() throws {
        let withGrammar = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("relation-parse-need.json").utf8)
        )
        XCTAssertEqual(withGrammar.relationGrammar, 1)

        let withoutGrammar = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data("""
            {
              "ok": true, "schema_version": 1, "input": "Fix it",
              "body": "Fix it", "mode": "task", "needs": [],
              "spans": [], "diagnostics": []
            }
            """.utf8)
        )
        XCTAssertNil(withoutGrammar.relationGrammar)
    }

    func testRelationUpdatesDecodeTolerantly() throws {
        let lx1 = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(fixtureText("relation-preview-lx1-archived.json").utf8)
        )
        guard case .success(let success) = lx1 else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(success.relationUpdates.count, 1)
        XCTAssertEqual(success.relationUpdates[0].direction, "to")
        XCTAssertEqual(success.relationUpdates[0].action, "added")
        XCTAssertEqual(success.relationUpdates[0].label, "follow-up of")
        XCTAssertEqual(success.relationUpdates[0].target.archived, true)
        XCTAssertEqual(success.mirrorSkipped.count, 1)
        XCTAssertEqual(success.mirrorSkipped[0].reason, "archived_target")

        let legacy = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(fixtureText("task-dependency-preview-new-task.json").utf8)
        )
        guard case .success(let legacySuccess) = legacy else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(legacySuccess.relationUpdates.isEmpty)
        XCTAssertTrue(legacySuccess.linkedFromLineUpdates.isEmpty)
        XCTAssertTrue(legacySuccess.mintedRelationBlockIDs.isEmpty)
        XCTAssertTrue(legacySuccess.mirrorSkipped.isEmpty)
    }

    func testRelationLabelCandidateCountAndTypedDecode() throws {
        let label = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(fixtureText("relation-complete-label.json").utf8)
        )
        XCTAssertEqual(label.context, "relation_label")
        XCTAssertEqual(label.owner?.text, "Owner")
        XCTAssertEqual(label.relation?.direction, "to")
        XCTAssertEqual(label.relation?.range, CaptureRange(start: 26, end: 39))
        XCTAssertEqual(label.relation?.range.end, label.replacement.start)
        let typed = try XCTUnwrap(label.candidates.first(where: { $0.typed }))
        XCTAssertEqual(typed.label, "follow")
        XCTAssertEqual(typed.replacement, "|follow")
        let suggestion = try XCTUnwrap(label.candidates.first(where: { !$0.typed }))
        XCTAssertEqual(suggestion.count, 4)

        let content = completionRowContent(
            for: suggestion,
            context: "relation_label",
            query: "follow"
        )
        XCTAssertEqual(content.primaryText, "follow-up of")
        XCTAssertEqual(content.secondaryText, "4")

        let typedContent = completionRowContent(
            for: typed,
            context: "relation_label",
            query: "follow"
        )
        XCTAssertEqual(typedContent.primaryText, "follow")
        XCTAssertTrue(typedContent.badges.contains("Typed"))

        let oldBob = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(fixtureText("relation-label-complete-old.json").utf8)
        )
        XCTAssertNil(oldBob.relation)
    }

    /// The new vocabulary fields decode additively: bob's canonical `key`,
    /// `inverse`, `hide_replacement`, typed `existing`/`hidden`, and the
    /// response `hidden_count` / `one_off`. Older payloads omit them.
    /// Fixtures are real `bob` output from a scratch vault.
    func testRelationLabelVocabularyFieldsDecode() throws {
        let typedHidden = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(fixtureText("relation-label-complete-typed-hidden.json").utf8)
        )
        XCTAssertEqual(typedHidden.context, "relation_label")
        XCTAssertEqual(typedHidden.hiddenCount, 1)
        XCTAssertNil(typedHidden.oneOff)
        let row = try XCTUnwrap(typedHidden.candidates.first)
        XCTAssertEqual(row.key, "inspired by")
        XCTAssertEqual(row.count, 3)
        XCTAssertEqual(row.replacement, "|\"inspired by\"")
        XCTAssertEqual(row.hideReplacement, "||\"inspired by\"")
        XCTAssertEqual(row.typed, true)
        XCTAssertEqual(row.existing, true)
        XCTAssertEqual(row.hidden, true)

        let oneOff = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(fixtureText("relation-label-complete-one-off.json").utf8)
        )
        XCTAssertEqual(oneOff.oneOff, true)
        let typed = try XCTUnwrap(oneOff.candidates.first(where: { $0.typed }))
        XCTAssertTrue(typed.replacement.hasPrefix("||"))
        XCTAssertEqual(typed.hideReplacement, typed.replacement)

        let vocabulary = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(fixtureText("relation-label-complete-vocabulary.json").utf8)
        )
        XCTAssertEqual(vocabulary.hiddenCount, 1)
        let newTyped = try XCTUnwrap(vocabulary.candidates.first(where: { $0.typed }))
        XCTAssertEqual(newTyped.key, "inspired")
        XCTAssertEqual(newTyped.existing, false)
        XCTAssertEqual(newTyped.hidden, false)
    }

    /// `bob relations list -f json` decodes: totals plus one row per label
    /// with both insertion forms. A row keeps the display spelling.
    func testRelationLabelsListDecode() throws {
        let response = try JSONDecoder().decode(
            CaptureRelationLabelsResponse.self,
            from: Data(fixtureText("relations-list-hidden.json").utf8)
        )
        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.hiddenCount, 1)
        XCTAssertTrue(response.ok)
        let hidden = try XCTUnwrap(response.labels.first(where: { $0.hidden }))
        XCTAssertEqual(hidden.key, "inspired by")
        XCTAssertEqual(hidden.name, "inspired by")
        XCTAssertEqual(hidden.count, 3)
        XCTAssertEqual(hidden.replacement, "|\"inspired by\"")
        XCTAssertEqual(hidden.hideReplacement, "||\"inspired by\"")
    }

    /// Capture warnings decode both shapes: legacy plain strings and the
    /// structured `hides_existing_relation_label` object. `||` dry runs also
    /// carry `relation_label_hides[]`.
    func testCaptureHideWarningAndHidesDecode() throws {
        let item = try JSONDecoder().decode(
            CaptureCommandSuccess.self,
            from: Data(fixtureText("capture-hide-warning.json").utf8)
        )
        let warning = try XCTUnwrap(item.warnings.first(where: { $0.isRelationHideWarning }))
        XCTAssertEqual(
            warning.message,
            "hides \"inspired by\" from relation suggestions (3 links)"
        )
        let hide = try XCTUnwrap(item.relationLabelHides.first)
        XCTAssertEqual(hide.key, "inspired by")
        XCTAssertEqual(hide.existingCount, 3)
        XCTAssertFalse(hide.wasHidden)
        XCTAssertEqual(hide.action, "hide")
    }
}
