import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureTransferPendingTests: XCTestCase {
    func testTransferDestinationNeedsRunDryRunInsteadOfQuietPickerShortcut() async throws {
        let cases: [(parse: String, draft: String, failure: String, activeForm: String?)] = [
            (
                "capture-parse-transfer-incomplete.json",
                "@inbox+bench > ",
                "capture-transfer-pending-destination.json",
                nil
            ),
            (
                "capture-parse-transfer-pending-block-id.json",
                "@inbox+bench > @db+",
                "capture-transfer-pending-block-id.json",
                "@note+task"
            ),
            (
                "capture-parse-transfer-pending-drawer.json",
                "@inbox+bench > @db+upgrade#",
                "capture-transfer-pending-drawer.json",
                "@note+task#drawer"
            ),
            (
                "capture-parse-transfer-pending-section.json",
                "@inbox+bench > @db#",
                "capture-transfer-pending-section.json",
                "@note#section"
            ),
        ]

        for item in cases {
            let parse = try parseFixture(item.parse)
            XCTAssertTrue(parse.spans.contains { $0.kind == "transfer_source" }, item.parse)
            XCTAssertNil(CapturePanelModel.pickerNeed(in: parse), item.parse)

            let record = temporaryURL()
            let model = makeModel(
                record: record,
                parseFixture: item.parse,
                failureFixture: item.failure
            )
            model.plainDraft = item.draft
            model.preview()
            try await waitUntil {
                !model.isPreviewing && model.transferPendingPresentation != nil
            }

            XCTAssertNil(model.errorMessage)
            XCTAssertNil(model.transferRefusalPresentation)
            XCTAssertEqual(
                model.transferPendingPresentation?.forms.filter(\.active).map(\.form),
                item.activeForm.map { [$0] } ?? [])
            XCTAssertTrue(try recordedCaptureDryRun(record))
        }
    }

    func testOrdinaryBlockIDAndSectionNeedsKeepTheirQuietPickerBehavior() throws {
        XCTAssertEqual(
            CapturePanelModel.pickerNeed(in: try parseFixture("list-parse-nested-prompt.json")),
            .blockID
        )
        XCTAssertEqual(
            CapturePanelModel.pickerNeed(
                in: try parseFixture("list-parse-section-incomplete.json")),
            .section
        )
    }

    func testOlderBobPendingFailureLeavesMutedStatusAndIdlePreview() async throws {
        let original = try failureObject("capture-transfer-pending-destination.json")
        var oldBob = original
        oldBob.removeValue(forKey: "transfer_pending")

        let record = temporaryURL()
        let model = makeModel(
            record: record,
            parseFixture: "capture-parse-transfer-incomplete.json",
            failureJSON: try JSONSerialization.data(withJSONObject: oldBob)
        )
        model.plainDraft = "@inbox+bench > "
        model.preview()
        try await waitUntil {
            !model.isPreviewing
                && model.previewState == .idle
                && model.statusText.contains("transfer needs a destination")
        }

        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.transferPendingPresentation)
        XCTAssertTrue(try recordedCaptureDryRun(record))
    }

    func testTransferRefusalShowsDesignedCardWithoutRedErrorCallout() async throws {
        let record = temporaryURL()
        let model = makeModel(
            record: record,
            parseFixture: "capture-parse-transfer-merge.json",
            failureFixture: "capture-transfer-refusal-open-subtasks.json"
        )
        model.plainDraft = "@inbox+bench > @db+upgrade"
        model.preview()
        try await waitUntil {
            !model.isPreviewing && model.transferRefusalPresentation != nil
        }

        XCTAssertEqual(model.transferRefusalPresentation?.verb, .merge)
        XCTAssertEqual(model.transferRefusalPresentation?.code, "merge_source_open_subtasks")
        XCTAssertNil(model.errorMessage)
        guard case .failed = model.previewState else {
            return XCTFail("expected the refusal card to occupy the preview")
        }
        XCTAssertTrue(try recordedCaptureDryRun(record))
    }

    private func makeModel(
        record: URL,
        parseFixture: String,
        failureFixture: String? = nil,
        failureJSON: Data? = nil
    ) -> CapturePanelModel {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "BOB_DIR": "/tmp/transfer-pending-test-\(UUID().uuidString)",
            "FAKE_BOB_RECORD_PATH": record.path,
            "FAKE_BOB_PARSE_FIXTURE": parseFixture,
            "FAKE_BOB_CAPTURE_DRY_RUN_EXIT": "1",
        ]
        if let failureFixture {
            environment["FAKE_BOB_CAPTURE_DRY_RUN_STDOUT"] = try? fixtureText(failureFixture)
        } else if let failureJSON {
            environment["FAKE_BOB_CAPTURE_DRY_RUN_STDOUT"] = String(
                data: failureJSON, encoding: .utf8)
        }
        return CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: fakeBobPath(),
                environment: environment
            ),
            debounceNanoseconds: 0
        )
    }

    private func parseFixture(_ name: String) throws -> CaptureParseResponse {
        try JSONDecoder().decode(CaptureParseResponse.self, from: fixtureData(name))
    }

    private func failureObject(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData(name)) as? [String: Any])
    }

    private func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name))
    }

    private func fixtureText(_ name: String) throws -> String {
        try String(contentsOf: fixtureURL(name), encoding: .utf8)
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    private func fakeBobPath() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func recordText(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func recordedCaptureDryRun(_ url: URL) throws -> Bool {
        try recordText(url).components(separatedBy: .newlines).contains { line in
            line.hasPrefix("argv=capture ") && line.contains("--dry-run")
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
