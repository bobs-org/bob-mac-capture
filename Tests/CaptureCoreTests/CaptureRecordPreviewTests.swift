import Foundation
import XCTest

@testable import CaptureCore

/// Decoding and presentation for Bob's record-result wire data: top-level
/// `note_files`, the per-item `record_note` summary, and the structured
/// refusal payload. Real fixtures come from the implementation's Bob
/// binary (see `record-fixtures-README.md`); tolerance cases are
/// synthetic and labeled as such.
private enum CaptureRecordPreviewFixtureError: Error {
    case expectedSuccess
    case expectedFailure
}

final class CaptureRecordPreviewTests: XCTestCase {
    private func fixtureData(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/\(name)"))
    }

    private func decodeSuccess(_ name: String) throws -> CaptureCommandSuccess {
        let decoded = try JSONDecoder().decode(
            CaptureCommandResponse.self, from: fixtureData(name))
        guard case .success(let success) = decoded else {
            throw CaptureRecordPreviewFixtureError.expectedSuccess
        }
        return success
    }

    private func decodeFailure(_ name: String) throws -> CaptureCommandFailure {
        let decoded = try JSONDecoder().decode(
            CaptureCommandResponse.self, from: fixtureData(name))
        guard case .failure(let failure) = decoded else {
            throw CaptureRecordPreviewFixtureError.expectedFailure
        }
        return failure
    }

    // MARK: - Real new-record response

    func testRestaurantDryRunDecodesNoteFileAndSummary() throws {
        let success = try decodeSuccess("record-capture-restaurant.json")
        XCTAssertEqual(success.kind, "record_note")
        XCTAssertTrue(success.dryRun)
        let summary = try XCTUnwrap(success.recordNote)
        XCTAssertEqual(summary.action, "create")
        XCTAssertEqual(summary.label, "Restaurant")
        XCTAssertEqual(summary.emoji, "🍽️")
        XCTAssertEqual(summary.path, "eat/cafe_møø_ramen.md")
        XCTAssertEqual(summary.notes, 2)
        XCTAssertEqual(
            summary.properties.map(\.key),
            ["status", "category", "location", "companions", "visited", "url"])
        let files = success.noteFiles
        XCTAssertEqual(files.count, 1)
        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(file.path, summary.path)
        XCTAssertEqual(file.action, "create")
        XCTAssertEqual(file.recordType, "restaurant")
        XCTAssertTrue(file.isUsable)
    }

    func testRestaurantMarkdownIsPreservedExactly() throws {
        let success = try decodeSuccess("record-capture-restaurant.json")
        let file = try XCTUnwrap(success.noteFiles.first)
        XCTAssertTrue(file.markdown.hasSuffix("\n"), "trailing newline survives")
        XCTAssertTrue(file.markdown.contains("title: \"Café \\\"Møø\\\": Ramen!\""))
        XCTAssertTrue(file.markdown.contains("location: \"Clark: Downtown\""))
        XCTAssertTrue(file.markdown.contains("- 2026-10-30: First visit was great."))
        XCTAssertTrue(file.markdown.contains("  - Extra chili oil on the side."))
        XCTAssertFalse(file.body.isEmpty)
        XCTAssertTrue(file.body.contains("First visit was great."))
    }

    func testRestaurantCommitMatchesDryRun() throws {
        let dry = try decodeSuccess("record-capture-restaurant.json")
        let commit = try decodeSuccess("record-capture-restaurant-commit.json")
        XCTAssertFalse(commit.dryRun)
        XCTAssertEqual(commit.recordNote, dry.recordNote)
        XCTAssertEqual(commit.noteFiles.first?.markdown, dry.noteFiles.first?.markdown)
    }

    func testRestaurantHeadlineAndDetail() throws {
        let success = try decodeSuccess("record-capture-restaurant-commit.json")
        let summary = try XCTUnwrap(success.recordNote)
        XCTAssertEqual(
            CaptureRecordPreviewPresentation.headline(for: summary),
            "🍽️ new restaurant  eat/cafe_møø_ramen.md")
        let detail = CaptureRecordPreviewPresentation.detail(for: summary)
        XCTAssertTrue(detail.contains("Liked"), detail)
        XCTAssertTrue(detail.contains("Ramen"), detail)
        XCTAssertTrue(detail.contains("Clark: Downtown"), detail)
        XCTAssertTrue(detail.contains("with Kel"), detail)
        XCTAssertTrue(detail.contains("2 notes"), detail)
    }

    func testPodcastWithoutNotes() throws {
        let success = try decodeSuccess("record-capture-podcast.json")
        let summary = try XCTUnwrap(success.recordNote)
        XCTAssertEqual(summary.label, "Podcast")
        XCTAssertEqual(summary.notes, 0)
        XCTAssertEqual(
            CaptureRecordPreviewPresentation.headline(for: summary),
            "🎙️ new podcast  podcasts/talk_python.md")
        XCTAssertTrue(
            CaptureRecordPreviewPresentation.detail(for: summary).contains("no notes"))
    }

    func testTwoRecordsPairInOrder() throws {
        let success = try decodeSuccess("record-capture-two-records.json")
        XCTAssertEqual(success.normalizedCaptures.count, 2)
        let pairs = CaptureRecordPreviewPresentation.pair(
            files: success.noteFiles, items: success.normalizedCaptures)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].file.path, "eat/ramen_nagi.md")
        XCTAssertEqual(pairs[1].file.path, "podcasts/talk_python.md")
        // The first item omits its typed companion, so Bob's default wins.
        let companions = try XCTUnwrap(
            pairs[0].item.recordNote?.properties.first(where: { $0.key == "companions" }))
        XCTAssertTrue(companions.isDefault)
        XCTAssertEqual(companions.source, "default")
        XCTAssertEqual(companions.resolvedDisplay, "kelly")
    }

    func testMixedBatchKeepsItemOrderAndOmitsTaskSummary() throws {
        let success = try decodeSuccess("record-capture-mixed.json")
        let items = success.normalizedCaptures
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].kind, "task")
        XCTAssertNil(items[0].recordNote)
        XCTAssertEqual(items[1].kind, "record_note")
        XCTAssertNotNil(items[1].recordNote)
        XCTAssertNil(success.recordNote, "top-level mirror follows the first item")
        let pairs = CaptureRecordPreviewPresentation.pair(
            files: success.noteFiles, items: items)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].file.path, "eat/ramen_nagi.md")
    }

    func testExplicitEmptyOptionalHasNoValueOrDisplay() throws {
        let success = try decodeSuccess("record-capture-optional-empty.json")
        let summary = try XCTUnwrap(success.recordNote)
        let companions = try XCTUnwrap(
            summary.properties.first(where: { $0.key == "companions" }))
        XCTAssertEqual(companions.label, "Companions")
        XCTAssertNil(companions.value)
        XCTAssertNil(companions.display)
        XCTAssertNil(companions.resolvedDisplay)
        XCTAssertFalse(
            CaptureRecordPreviewPresentation.detail(for: summary).contains("Companions"))
    }

    // MARK: - Real refusals

    func testMissingRefusalDecodesWithoutCode() throws {
        let failure = try decodeFailure("record-capture-missing.json")
        XCTAssertNil(failure.code, "missing-field refusals carry no code")
        let refusal = try XCTUnwrap(failure.recordRefusal)
        XCTAssertEqual(refusal.missing, ["category", "location"])
        XCTAssertTrue(refusal.invalid.isEmpty)
        let draft = try XCTUnwrap(refusal.draft)
        XCTAssertTrue(draft.contains("status:: liked"), draft)
        XCTAssertTrue(draft.contains("category::"), draft)
    }

    func testInvalidRefusalCarriesFieldCodeAndMessage() throws {
        let failure = try decodeFailure("record-capture-invalid.json")
        XCTAssertEqual(failure.code, "record_invalid_value")
        let refusal = try XCTUnwrap(failure.recordRefusal)
        XCTAssertTrue(refusal.missing.isEmpty)
        XCTAssertEqual(refusal.invalid.count, 1)
        XCTAssertEqual(refusal.invalid[0].field, "status")
        XCTAssertEqual(refusal.invalid[0].code, "record_invalid_value")
        XCTAssertFalse(refusal.invalid[0].message.isEmpty)
        XCTAssertNotNil(refusal.draft)
    }

    // MARK: - Tolerance (synthetic payloads)

    func testLegacyResponseWithoutRecordKeysStillDecodes() throws {
        // Synthetic: an older Bob with no note_files or record_note keys.
        let data = Data(
            """
            {"ok":true,"dry_run":true,"routed":true,"route_label":"mac_inbox.md",\
            "relative_target":"mac_inbox.md","target":"/vault/mac_inbox.md",\
            "text":"Buy milk","task_line":"- [ ] Buy milk","kind":"task",\
            "created":"2026-10-30","placement":"created"}
            """.utf8)
        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = decoded else {
            throw CaptureRecordPreviewFixtureError.expectedSuccess
        }
        XCTAssertEqual(success.kind, "task")
        XCTAssertTrue(success.noteFiles.isEmpty)
        XCTAssertNil(success.recordNote)
    }

    func testMalformedAdditivePayloadsCannotBreakLegacyResponse() throws {
        // Synthetic: garbage where the additive keys live.
        let data = Data(
            """
            {"ok":true,"dry_run":true,"routed":true,"route_label":"eat",\
            "relative_target":"eat/ramen_nagi.md","target":"/vault/eat/ramen_nagi.md",\
            "text":"Ramen Nagi","task_line":"","kind":"record_note",\
            "created":"2026-10-30","placement":"created",\
            "note_files":"not-an-array","record_note":42}
            """.utf8)
        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = decoded else {
            throw CaptureRecordPreviewFixtureError.expectedSuccess
        }
        XCTAssertEqual(success.kind, "record_note")
        XCTAssertTrue(success.noteFiles.isEmpty)
        XCTAssertNil(success.recordNote)
    }

    func testMalformedFileRowIsDroppedWhileSiblingsSurvive() throws {
        // Synthetic: one bad row inside note_files.
        let data = Data(
            """
            {"ok":true,"dry_run":true,"routed":true,"route_label":"eat",\
            "relative_target":"eat/ramen_nagi.md","target":"/vault/eat/ramen_nagi.md",\
            "text":"Ramen Nagi","task_line":"","kind":"record_note",\
            "created":"2026-10-30","placement":"created",\
            "note_files":["bad-row",{"path":"eat/ramen_nagi.md","action":"create",\
            "record_type":"restaurant","properties":[],"body":"","markdown":"---\\n"}]}
            """.utf8)
        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = decoded else {
            throw CaptureRecordPreviewFixtureError.expectedSuccess
        }
        XCTAssertEqual(success.noteFiles.count, 1)
        XCTAssertEqual(success.noteFiles[0].path, "eat/ramen_nagi.md")
    }

    func testUnrelatedFailureHasNoRecordRefusal() throws {
        // Synthetic: a non-record refusal without the structured keys.
        let data = Data(
            """
            {"ok":false,"error":"nothing to pull in"}
            """.utf8)
        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .failure(let failure) = decoded else {
            throw CaptureRecordPreviewFixtureError.expectedFailure
        }
        XCTAssertNil(failure.recordRefusal)
        XCTAssertTrue(failure.recordMissing.isEmpty)
        XCTAssertTrue(failure.recordInvalid.isEmpty)
    }

    func testResolvedDisplayFallsBackToCanonicalValue() throws {
        // Synthetic values with no display string.
        XCTAssertEqual(
            CaptureNoteFileProperty(key: "rating", label: "Rating", value: .number(4.5))
                .resolvedDisplay,
            "4.5")
        XCTAssertEqual(
            CaptureNoteFileProperty(key: "flag", label: "Flag", value: .bool(false))
                .resolvedDisplay,
            "false")
        XCTAssertEqual(
            CaptureNoteFileProperty(key: "count", label: "Count", value: .number(0))
                .resolvedDisplay,
            "0")
        XCTAssertEqual(
            CaptureNoteFileProperty(
                key: "tags", label: "Tags",
                value: .list([.string("spicy"), .string("lunch")])
            ).resolvedDisplay,
            "spicy, lunch")
        XCTAssertNil(
            CaptureNoteFileProperty(key: "url", label: "Url").resolvedDisplay)
    }

    func testSamePathCreateAndUpdatePairSeparately() throws {
        // Synthetic: two operations on one path consume one file each.
        let files = [
            CaptureNoteFile(path: "eat/nagi.md", action: "create", markdown: "a"),
            CaptureNoteFile(path: "eat/nagi.md", action: "update", markdown: "b"),
        ]
        let items = [
            CaptureCommandSuccess(
                ok: true, dryRun: true, routed: true, routeLabel: "eat",
                relativeTarget: "eat/nagi.md", target: "/vault/eat/nagi.md",
                text: "Nagi", taskLine: "", kind: "record_note", created: "2026-10-30",
                placement: "created",
                recordNote: CaptureRecordNoteSummary(action: "create", path: "eat/nagi.md"),
                ref: nil),
            CaptureCommandSuccess(
                ok: true, dryRun: true, routed: true, routeLabel: "eat",
                relativeTarget: "eat/nagi.md", target: "/vault/eat/nagi.md",
                text: "Nagi", taskLine: "", kind: "record_update",
                created: "2026-10-30", placement: "updated",
                recordNote: CaptureRecordNoteSummary(action: "update", path: "eat/nagi.md"),
                ref: nil),
        ]
        let pairs = CaptureRecordPreviewPresentation.pair(files: files, items: items)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].file.markdown, "a")
        XCTAssertEqual(pairs[1].file.markdown, "b")
    }

    func testNoteCountText() {
        XCTAssertEqual(CaptureRecordPreviewPresentation.noteCountText(0), "no notes")
        XCTAssertEqual(CaptureRecordPreviewPresentation.noteCountText(1), "1 note")
        XCTAssertEqual(CaptureRecordPreviewPresentation.noteCountText(3), "3 notes")
    }

    func testRefusalPresentationFromMissingFixture() throws {
        let data = try fixtureData("record-capture-missing.json")
        let failure = try JSONDecoder().decode(CaptureCommandFailure.self, from: data)
        let presentation = try XCTUnwrap(
            CaptureRecordRefusalPresentation(failure: failure))
        XCTAssertTrue(presentation.message.text.contains("required field"))
        XCTAssertEqual(presentation.missing, ["category", "location"])
        XCTAssertTrue(presentation.invalid.isEmpty)
        XCTAssertNotNil(presentation.draft)
        XCTAssertTrue(presentation.accessibilitySummary.contains("category"))
    }

    func testRefusalPresentationUsesParseLabels() throws {
        let data = try fixtureData("record-capture-invalid.json")
        let failure = try JSONDecoder().decode(CaptureCommandFailure.self, from: data)
        let presentation = try XCTUnwrap(
            CaptureRecordRefusalPresentation(
                failure: failure, fieldLabels: ["status": "Status"]))
        XCTAssertEqual(presentation.displayLabel(for: "status"), "Status")
        XCTAssertTrue(presentation.accessibilitySummary.contains("Status:"))
        XCTAssertEqual(presentation.invalid.count, 1)
    }

    func testRefusalPresentationNilWithoutStructuredPayload() throws {
        // Synthetic: an unrelated failure.
        let data = Data(
            """
            {"ok":false,"error":"nothing to pull in"}
            """.utf8)
        let failure = try JSONDecoder().decode(CaptureCommandFailure.self, from: data)
        XCTAssertNil(CaptureRecordRefusalPresentation(failure: failure))
    }

    func testNotificationTitleAndBodyMirrorPanelCopy() throws {
        let success = try decodeSuccess("record-capture-restaurant-commit.json")
        let summary = try XCTUnwrap(success.recordNote)
        XCTAssertEqual(
            CaptureRecordPreviewPresentation.notificationTitle(for: summary),
            CaptureRecordPreviewPresentation.headline(for: summary))
        XCTAssertEqual(
            CaptureRecordPreviewPresentation.notificationBody(for: summary),
            CaptureRecordPreviewPresentation.detail(for: summary))
        let line = CaptureRecordPreviewPresentation.recordBatchLine(for: summary)
        XCTAssertTrue(line.contains("eat/cafe_møø_ramen.md"), line)
        XCTAssertTrue(line.contains("2 notes"), line)
    }

    func testPairIndexedKeepsItemOrder() throws {
        let success = try decodeSuccess("record-capture-mixed.json")
        let items = success.normalizedCaptures
        let map = CaptureRecordPreviewPresentation.pairIndexed(
            files: success.noteFiles, items: items)
        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map[1]?.path, "eat/ramen_nagi.md")
        XCTAssertNil(map[0], "task items never pair")
    }

    func testUpdateDryRunPairsAndExtractsChangedLines() throws {
        let success = try decodeSuccess("record-capture-update.json")
        XCTAssertEqual(success.kind, "record_update")
        let pairs = CaptureRecordPreviewPresentation.pair(
            files: success.noteFiles, items: success.normalizedCaptures)
        XCTAssertEqual(pairs.count, 1)
        let file = try XCTUnwrap(pairs.first?.file)
        XCTAssertEqual(file.action, "update")
        XCTAssertEqual(file.path, "eat/nagi.md")
        XCTAssertTrue(file.isUsable)
        let changed = try XCTUnwrap(file.changedLines)
        XCTAssertFalse(changed.isEmpty)
        XCTAssertTrue(changed.contains { $0.change == "added" })
        XCTAssertTrue(changed.contains { $0.text.contains("Went back") })
        XCTAssertFalse(
            (file.lines ?? []).contains { $0.change == "unchanged" } && changed.isEmpty)
    }

    func testChangedPropertiesFilterDisplayDifferences() {
        let status = CaptureNoteFileProperty(
            key: "status",
            label: "Status",
            value: .string("liked"),
            display: "Liked",
            before: .string("to_try"),
            beforeDisplay: "To try"
        )
        let location = CaptureNoteFileProperty(
            key: "location",
            label: "Location",
            value: .string("Clark"),
            display: "Clark",
            before: .string("Clark"),
            beforeDisplay: "Clark"
        )
        XCTAssertTrue(status.displayChanged)
        XCTAssertFalse(location.displayChanged)
        let file = CaptureNoteFile(
            path: "eat/nagi.md",
            action: "update",
            properties: [status, location],
            markdown: "# Nagi\n"
        )
        XCTAssertEqual(file.changedProperties.map(\.key), ["status"])
    }

    func testChangedLinesNilWhenOlderBobOmitsKey() throws {
        let file = CaptureNoteFile(
            path: "eat/nagi.md",
            action: "update",
            body: "- leftover body",
            markdown: "# Nagi\n"
        )
        XCTAssertNil(file.lines)
        XCTAssertNil(file.changedLines)

        let omitted = Data(
            """
            {"path":"eat/nagi.md","action":"update","markdown":"#"}
            """.utf8)
        let decoded = try JSONDecoder().decode(CaptureNoteFile.self, from: omitted)
        XCTAssertNil(decoded.lines)

        let empty = Data(
            """
            {"path":"eat/nagi.md","action":"update","markdown":"#","lines":[]}
            """.utf8)
        let emptyFile = try JSONDecoder().decode(CaptureNoteFile.self, from: empty)
        XCTAssertEqual(emptyFile.lines, [])
        XCTAssertEqual(emptyFile.changedLines, [])
    }

    func testChangedLinesEmptyWhenEveryLineIsUnchanged() {
        let file = CaptureNoteFile(
            path: "eat/nagi.md",
            action: "update",
            markdown: "# Nagi\n",
            lines: [
                CaptureNoteFileLine(text: "# Nagi", depth: 0, change: "unchanged")
            ]
        )
        XCTAssertEqual(file.changedLines, [])
    }

    func testLiveUpdateChangedLinesRequiresReadyMatchingDraft() {
        let added = CaptureNoteFileLine(
            text: "- 2026-10-30: Went back", depth: 0, change: "added")
        let file = CaptureNoteFile(
            path: "eat/nagi.md",
            action: "update",
            markdown: "# Nagi\n",
            lines: [added]
        )
        let preview = CaptureCommandSuccess(
            ok: true, dryRun: true, routed: true, routeLabel: "eat",
            relativeTarget: "eat/nagi.md", target: "/vault/eat/nagi.md",
            text: "Nagi", taskLine: "", kind: "record_update",
            created: "2026-10-30", placement: "updated",
            noteFiles: [file],
            recordNote: CaptureRecordNoteSummary(action: "update", path: "eat/nagi.md")
        )
        let draft = "@eat/nagi\n- Went back"
        XCTAssertEqual(
            CaptureRecordPreviewPresentation.liveUpdateChangedLines(
                path: "eat/nagi.md",
                previewDraft: draft,
                plainDraft: draft,
                isPreviewing: false,
                preview: preview
            )?.map(\.text),
            [added.text]
        )
        XCTAssertNil(
            CaptureRecordPreviewPresentation.liveUpdateChangedLines(
                path: "eat/nagi.md",
                previewDraft: draft,
                plainDraft: draft,
                isPreviewing: true,
                preview: preview
            )
        )
        XCTAssertNil(
            CaptureRecordPreviewPresentation.liveUpdateChangedLines(
                path: "eat/nagi.md",
                previewDraft: "stale",
                plainDraft: draft,
                isPreviewing: false,
                preview: preview
            )
        )
        XCTAssertNil(
            CaptureRecordPreviewPresentation.liveUpdateChangedLines(
                path: "eat/nagi.md",
                previewDraft: draft,
                plainDraft: draft,
                isPreviewing: false,
                preview: nil
            )
        )
        XCTAssertNil(
            CaptureRecordPreviewPresentation.liveUpdateChangedLines(
                path: "eat/other.md",
                previewDraft: draft,
                plainDraft: draft,
                isPreviewing: false,
                preview: preview
            )
        )
    }
}
