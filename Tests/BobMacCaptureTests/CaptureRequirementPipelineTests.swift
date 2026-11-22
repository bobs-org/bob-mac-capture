import Foundation
import XCTest

@testable import BobMacCapture
@testable import CaptureCore

@MainActor
final class CaptureRequirementPipelineTests: XCTestCase {
    private static let owner =
        "sase.md#^ship@7509122af6ef7ccfc5ee142ebf96f11ac12ef529379b6b0cc912f32aacdb3668"
    private static let req1 = "\(owner)/req/1~a59403fe"
    private static let req11 = "\(owner)/req/1.1~5b8c8295"
    private static let req2 = "\(owner)/req/2~32b0533b"
    private static let staleReq1 =
        "sase.md#^ship@b2c872778b4e69d8611f104bcb08cecb256d69ba791ac8695ce31ebe9b7df344/req/1~323df93c"
    private static let docs = "deps.md#^docs"

    func testRequirementOnlyPreviewOpensCardAndDefaultReturnSendsReqChoice() async throws {
        let record = temporaryURL()
        let model = try makeModel(
            record: record,
            dryRun: fixture("capture-req-close-preview.json"),
            write: fixture("capture-req-close-write.json")
        )
        model.plainDraft = "!sase:ship"
        model.preview()
        try await waitUntil { !model.isPreviewing }

        let preview = try XCTUnwrap(captureBlocks(try recordText(record)).last)
        XCTAssertFalse(preview.contains("--req-choice"), preview)
        XCTAssertEqual(model.previewResults.first?.pullIn?.reqs?.supported, true)

        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        let choice = try XCTUnwrap(model.pullInChoice)
        XCTAssertTrue(model.pullInChoiceVisible)
        XCTAssertEqual(
            choice.outcomes.requirementRows.map(\.offer.key),
            [
                Self.req1, Self.req11, Self.req2,
            ])
        XCTAssertEqual(choice.highlightedKey, Self.req1)
        XCTAssertTrue(choice.canCommit)
        XCTAssertEqual(choice.selectableKeys, [])
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)

        model.panelDismisser = {}
        model.confirmPullInChoice()
        try await waitUntil { !model.isSubmitting }

        let write = try XCTUnwrap(captureBlocks(try recordText(record)).last)
        XCTAssertFalse(write.contains("--dry-run"), write)
        XCTAssertTrue(write.contains("--req-choice"), write)
        XCTAssertTrue(write.contains("--pull-in none"), write)
        XCTAssertFalse(write.contains("--carry"), write)
        XCTAssertFalse(write.contains("--cancel-offer"), write)
        XCTAssertFalse(write.contains("--complete-offer"), write)
        XCTAssertTrue(
            model.statusText.contains("✓ 1 requirements met with “Ship parser”"),
            model.statusText)
        XCTAssertTrue(
            model.statusText.contains("⊘ Dropped “Handles empty input”"),
            model.statusText)
        XCTAssertFalse(model.statusText.contains("Write docs"))
        XCTAssertNil(model.pullInChoice)
    }

    func testMixedCarryAndDropFlagsOnGuardedSubmit() async throws {
        let record = temporaryURL()
        let model = try makeModel(
            record: record,
            dryRun: fixture("capture-req-close-mixed.json"),
            write: fixture("capture-req-close-write.json")
        )
        model.plainDraft = "!sase:ship"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)

        let choice = try XCTUnwrap(model.pullInChoice)
        XCTAssertEqual(choice.outcomes.requirementRows.count, 3)
        XCTAssertEqual(choice.selectableKeys, [Self.docs])
        stage(model) { state in
            state.beginRequirementDrop(Self.req1)
            state.updateReasonText("No longer required")
            state.confirmRequirementDrop()
            state.stageRequirementCarry(Self.req2)
        }
        model.togglePullInOffer(Self.docs)
        model.panelDismisser = {}
        model.confirmPullInChoice()
        try await waitUntil { !model.isSubmitting }

        let write = try XCTUnwrap(captureBlocks(try recordText(record)).last)
        XCTAssertTrue(write.contains("--req-choice"), write)
        XCTAssertTrue(write.contains("--pull-in \(Self.docs)"), write)
        XCTAssertTrue(
            write.contains("--cancel-offer \(Self.req1)=No longer required"), write)
        XCTAssertTrue(write.contains("--carry \(Self.req2)"), write)
        XCTAssertFalse(write.contains("--carry \(Self.req1)"), write)
        XCTAssertFalse(write.contains("--pull-in \(Self.req1)"), write)
        XCTAssertFalse(write.contains("--pull-in \(Self.req2)"), write)
    }

    func testShiftReturnDowngradesCarryPullWithoutMutatingStagedChoice() async throws {
        let record = temporaryURL()
        let model = try makeModel(
            record: record,
            dryRun: fixture("capture-req-close-preview.json"),
            write: fixture("capture-req-close-write.json")
        )
        model.plainDraft = "!sase:ship"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        stage(model) { $0.stageRequirementCarryPulled(Self.req2) }
        XCTAssertEqual(
            model.pullInChoice?.outcomes.requirementChoice(for: Self.req2),
            .carryPulled)
        model.panelDismisser = {}
        model.chooseNoPullInOffers()
        try await waitUntil { !model.isSubmitting }

        let write = try XCTUnwrap(captureBlocks(try recordText(record)).last)
        XCTAssertTrue(write.contains("--pull-in none"), write)
        XCTAssertTrue(write.contains("--carry \(Self.req2)"), write)
        XCTAssertFalse(write.contains("--pull-in \(Self.req2)"), write)
        XCTAssertTrue(write.contains("--req-choice"), write)
    }

    func testEscRetainsDraftAndStructuralChoiceArmsTwoStepDiscard() async throws {
        let record = temporaryURL()
        let model = try makeModel(
            record: record,
            dryRun: fixture("capture-req-close-preview.json"),
            write: fixture("capture-req-close-write.json")
        )
        model.plainDraft = "!sase:ship"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)

        model.cancelPullInChoiceFromKeyboard()
        XCTAssertFalse(model.pullInChoiceVisible)
        XCTAssertEqual(model.plainDraft, "!sase:ship")
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)

        model.submit(openAfterCapture: false)
        stage(model) { $0.stageRequirementCarry(Self.req2) }
        XCTAssertEqual(model.pullInChoice?.totalCloseCount, 1)
        model.cancelPullInChoiceFromKeyboard()
        XCTAssertTrue(model.pullInChoiceVisible)
        XCTAssertTrue(model.statusText.contains("Esc again to discard 1 close"))
        model.cancelPullInChoiceFromKeyboard()
        XCTAssertFalse(model.pullInChoiceVisible)
        XCTAssertEqual(model.plainDraft, "!sase:ship")
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)
    }

    func testStaleCurrentRefreshReplacesLostKeys() async throws {
        let record = temporaryURL()
        let model = try makeModel(
            record: record,
            dryRun: fixture("capture-req-close-preview.json"),
            write: fixture("capture-req-close-stale.json"),
            writeExit: "1"
        )
        model.plainDraft = "!sase:ship"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        stage(model) { $0.stageRequirementCarry(Self.req1) }
        model.confirmPullInChoice()
        try await waitUntil { model.pullInChoiceVisible && !model.isSubmitting }

        let choice = try XCTUnwrap(model.pullInChoice)
        XCTAssertEqual(model.plainDraft, "!sase:ship")
        XCTAssertEqual(
            choice.outcomes.requirementRows.map(\.offer.key).first, Self.staleReq1)
        XCTAssertFalse(choice.outcomes.requirementRows.map(\.offer.key).contains(Self.req1))
        XCTAssertNil(choice.outcomes.requirementChoice(for: Self.req1))
        XCTAssertTrue(model.statusText.contains("lost"), model.statusText)
        XCTAssertEqual(writeCallCount(try recordText(record)), 1)
    }

    func testOverlapRefusalKeepsCardAndDraftWithoutResubmitting() async throws {
        let record = temporaryURL()
        let model = try makeModel(
            record: record,
            dryRun: fixture("capture-req-close-preview.json"),
            write: overlapRefusal()
        )
        model.plainDraft = "!sase:ship"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        stage(model) { $0.stageRequirementCarry(Self.req2) }
        model.confirmPullInChoice()
        try await waitUntil { model.pullInChoiceVisible && !model.isSubmitting }

        let choice = try XCTUnwrap(model.pullInChoice)
        XCTAssertEqual(model.plainDraft, "!sase:ship")
        XCTAssertEqual(choice.outcomes.requirementChoice(for: Self.req2), .carry)
        XCTAssertTrue(choice.errorMessage?.contains("overlap") == true, choice.errorMessage ?? "")
        XCTAssertEqual(writeCallCount(try recordText(record)), 1)
    }

    func testExecutableReplacementDismissesWithoutWritingOldKeys() async throws {
        let record = temporaryURL()
        var identity = "bob-first"
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "BOB_DIR": "/tmp/req-pipeline-\(UUID().uuidString)",
                "FAKE_BOB_RECORD_PATH": record.path,
                "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": try fixture(
                    "capture-req-close-preview.json"),
                "FAKE_BOB_CAPTURE_WRITE_STDOUT": try fixture("capture-req-close-write.json"),
                "FAKE_BOB_CAPTURE_WRITE_EXIT": "0",
            ]
        )
        client.identityTokenProvider = { identity }
        let model = CapturePanelModel(processClient: client, debounceNanoseconds: 0)
        model.plainDraft = "!sase:ship"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        XCTAssertTrue(model.pullInChoiceVisible)
        stage(model) { $0.stageRequirementCarry(Self.req2) }

        identity = "bob-replaced"
        model.confirmPullInChoice()
        XCTAssertFalse(model.pullInChoiceVisible)
        XCTAssertEqual(model.statusText, "Successor choice canceled")
        XCTAssertEqual(writeCallCount(try recordText(record)), 0)
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)
    }

    func testLegacyRefusalThenCapableRetrySendsReqChoice() async throws {
        let record = temporaryURL()
        let model = CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "BOB_DIR": "/tmp/req-pipeline-\(UUID().uuidString)",
                    "FAKE_BOB_RECORD_PATH": record.path,
                    "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": capabilityPreviewWithoutReqs(),
                    "FAKE_BOB_CAPTURE_WRITE_STDOUT": capableEmptyGroupsRefusal(),
                    "FAKE_BOB_CAPTURE_WRITE_EXIT": "1",
                ]
            ),
            debounceNanoseconds: 0
        )
        model.plainDraft = "!sase:ship"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        XCTAssertNil(model.previewResults.first?.pullIn?.reqs)
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        try await waitUntil { !model.isSubmitting }

        let blocks = captureBlocks(try recordText(record))
        XCTAssertEqual(blocks.count, 3)
        XCTAssertFalse(blocks[0].contains("--req-choice"), blocks[0])
        XCTAssertTrue(blocks[1].contains("--require-pull-in-choice"), blocks[1])
        XCTAssertFalse(blocks[1].contains("--req-choice"), blocks[1])
        XCTAssertTrue(blocks[2].contains("--req-choice"), blocks[2])
        XCTAssertTrue(blocks[2].contains("--require-pull-in-choice"), blocks[2])
        XCTAssertEqual(model.plainDraft, "!sase:ship")
        XCTAssertFalse(model.pullInChoiceVisible)
    }

    func testInboxRouteBackAndSubmitPreservesRequirementSubmission() async throws {
        let record = temporaryURL()
        let responseFile = temporaryURL()
        try write(fixture("inbox-route-choice-required.json"), to: responseFile)
        let model = try makeModel(
            record: record,
            dryRun: previewWithInboxRoute(),
            writeFile: responseFile
        )
        model.plainDraft = "!sase:ship"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        XCTAssertTrue(model.pullInChoiceVisible)
        XCTAssertFalse(model.inboxRouteChoiceVisible)
        stage(model) { $0.stageRequirementCarry(Self.req2) }
        model.confirmPullInChoice()
        try await waitUntil { model.inboxRouteChoiceVisible }

        XCTAssertFalse(model.pullInChoiceVisible)
        XCTAssertEqual(writeCallCount(try recordText(record)), 1)
        let firstWrite = try XCTUnwrap(captureBlocks(try recordText(record)).last)
        XCTAssertTrue(firstWrite.contains("--carry \(Self.req2)"), firstWrite)
        XCTAssertTrue(firstWrite.contains("--req-choice"), firstWrite)

        model.backInboxRouteChoice()
        let restored = try XCTUnwrap(model.pullInChoice)
        XCTAssertTrue(model.pullInChoiceVisible)
        XCTAssertEqual(restored.outcomes.requirementChoice(for: Self.req2), .carry)
        XCTAssertEqual(writeCallCount(try recordText(record)), 1)

        model.confirmPullInChoice()
        try await waitUntil { model.inboxRouteChoiceVisible }
        try write(fixture("inbox-route-moved.json"), to: responseFile)
        model.selectInboxRouteDestination("health.md")
        model.panelDismisser = {}
        model.confirmInboxRouteChoice()
        try await waitUntil { !model.isSubmitting }

        let routeSubmit = try XCTUnwrap(captureBlocks(try recordText(record)).last)
        XCTAssertTrue(routeSubmit.contains("--carry \(Self.req2)"), routeSubmit)
        XCTAssertTrue(routeSubmit.contains("--req-choice"), routeSubmit)
        XCTAssertTrue(
            routeSubmit.contains("--inbox-route mac_inbox.md#^route-task=health.md"),
            routeSubmit)
        let seeds = captureBlocks(try recordText(record)).compactMap { block in
            block.components(separatedBy: "BOB_PRIORITY_ROLL_SEED=").dropFirst()
                .first?.components(separatedBy: "\n").first
        }
        XCTAssertGreaterThanOrEqual(seeds.count, 2)
        XCTAssertEqual(seeds.dropFirst().first, seeds.last)
    }

    func testCarriedDescendantJumpUsesBobLanding() async throws {
        let record = temporaryURL()
        let model = try makeModel(
            record: record,
            dryRun: fixture("capture-req-close-preview.json"),
            write: writeWithJumpLanding()
        )
        model.plainDraft = "!sase:ship"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        stage(model) { $0.stageRequirementCarry(Self.req1) }
        model.toggleJumpForRow(Self.req11)
        XCTAssertEqual(model.pullInChoice?.jumpKey, Self.req11)

        var opened: [URL] = []
        model.noteOpener = { url, completion in
            opened.append(url)
            completion(nil)
        }
        model.panelDismisser = {}
        model.confirmPullInChoice()
        try await waitUntil { !model.isSubmitting }

        let write = try XCTUnwrap(captureBlocks(try recordText(record)).last)
        XCTAssertTrue(write.contains("--jump-offer \(Self.req11)"), write)
        XCTAssertTrue(write.contains("--carry \(Self.req1)"), write)
        XCTAssertEqual(opened.count, 1)
        let items =
            URLComponents(
                url: try XCTUnwrap(opened.first), resolvingAgainstBaseURL: false
            )?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "path1" })?.value, "/tmp/sase.md")
        XCTAssertEqual(items.first(where: { $0.name == "line1" })?.value, "3")
        XCTAssertNil(items.first(where: { $0.name == "path2" }))
    }

    private func makeModel(
        record: URL,
        dryRun: String,
        write: String? = nil,
        writeFile: URL? = nil,
        writeExit: String = "0"
    ) throws -> CapturePanelModel {
        let file =
            try writeFile
            ?? {
                let url = temporaryURL()
                try self.write(write ?? "", to: url)
                return url
            }()
        if writeFile == nil, let write {
            try self.write(write, to: file)
        }
        return CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "BOB_DIR": "/tmp/req-pipeline-\(UUID().uuidString)",
                    "FAKE_BOB_RECORD_PATH": record.path,
                    "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": dryRun,
                    "FAKE_BOB_CAPTURE_WRITE_STDOUT_FILE": file.path,
                    "FAKE_BOB_CAPTURE_WRITE_EXIT": writeExit,
                ]
            ),
            debounceNanoseconds: 0
        )
    }

    private func stage(
        _ model: CapturePanelModel,
        _ mutate: (inout CapturePullInChoiceState) -> Void
    ) {
        guard var choice = model.pullInChoice else {
            return XCTFail("Expected an open Pull-In card")
        }
        mutate(&choice)
        model.pullInChoice = choice
    }

    private func fakeBobPath() throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw NSError(
                domain: "CaptureRequirementPipelineTests",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "missing fake-bob at \(path)"
                ]
            )
        }
        return path
    }

    private func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func recordText(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for model state")
    }

    private func previewWithInboxRoute() throws -> String {
        try fixture("capture-req-close-preview.json").replacingOccurrences(
            of:
                "\"inbox_route\":{\"supported\":true,\"candidate_count\":0,\"routed_count\":0,\"kept_count\":0,\"candidates\":[]}",
            with: """
                "inbox_route":{"supported":true,"candidate_count":1,"routed_count":0,"kept_count":0,"candidates":[{"key":"mac_inbox.md#^route-task","n":1,"note_path":"mac_inbox.md","inbox":"mac_inbox","block_id":"route-task","line":6,"text":"Route me","previous_status_symbol":" ","previous_status_name":"Ready","status_symbol":"*","status_name":"Next","outcome":"pending"}],"destinations":[{"relative_path":"health.md","route":"health","label":"health","kind":"area","blocked":false}]}
                """
        )
    }

    private func writeWithJumpLanding() throws -> String {
        try fixture("capture-req-close-write.json").replacingOccurrences(
            of: "\"inbox_route\":",
            with: """
                "jump":{"key":"\(Self.req11)","n":2,"label":"Handles zero bytes","outcome":"left","landing":{"path":"/tmp/sase.md","relative_path":"sase.md","role":"note","label":"sase","line":3,"ref":"3:abcdef12","block_id":"ship"}},"inbox_route":
                """
        )
    }

    private func overlapRefusal() -> String {
        #"{"ok":false,"error":"Cannot carry “Handles unicode” while an ancestor is already dropped: overlap","code":"req_verdict_overlap"}"#
    }

    private func capabilityPreviewWithoutReqs() -> String {
        #"""
        {"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"","relative_target":"sase.md","target":"/tmp/sase.md","text":"!sase:ship","task_line":"- [x] #task Ship parser","kind":"task_complete","created":"2026-10-05","placement":"updated","pull_in":{"supported":true,"offer_count":0,"choice":null,"picked_count":0},"task_complete":{"raw":"!sase:ship","unblocked":[]}}
        """#
    }

    private func capableEmptyGroupsRefusal() -> String {
        #"{"ok":false,"error":"Choose successor offers","code":"pull_in_choice_required","pull_in":{"supported":true,"offer_count":0,"choice":"explicit","picked_count":0,"reqs":{"supported":true,"pending":3}},"offers":[]}"#
    }
}

private func captureCallCount(_ record: String) -> Int {
    captureBlocks(record).count
}

private func captureBlocks(_ record: String) -> [String] {
    record.components(separatedBy: "argv=")
        .dropFirst()
        .filter { $0.hasPrefix("capture ") }
}

private func writeCallCount(_ record: String) -> Int {
    captureBlocks(record).filter { !$0.contains("--dry-run") }.count
}
