import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Panel-side tests for the File-under parent picker: a bare URL that will
/// queue under the default parent opens the route list on its own with the
/// **File under** header, accepting splices ` @<route>`, Esc keeps the
/// default without reopening, and library hits never open it. Every draft
/// below is served by `Tests/Fixtures/fake-bob` from real-bob `ref-*.json`
/// and `capture-parse-ref*.json` fixtures.
@MainActor
final class CaptureFileUnderPanelTests: XCTestCase {
    /// The `UserDefaults` key `CapturePanelModel` remembers the last-used
    /// File-under parent under. Tests clear it so the list order is the
    /// deterministic last-used-free order (mirrors the model's key).
    private let lastUsedKey = "refFileUnderLastUsedParent"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: lastUsedKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: lastUsedKey)
        super.tearDown()
    }

    func testBareURLAutoOpensFileUnder() async throws {
        let model = try fileUnderModel()
        model.plainDraft = "https://example.com/post"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil { model.completionVisible }

        XCTAssertTrue(model.fileUnderActive)
        XCTAssertEqual(model.completionResponse?.context, "route")
        XCTAssertEqual(
            model.completionResponse?.candidates.map { $0.route },
            ["mac_inbox", "sase"]
        )
        // Accepting splices ` @<route>` at the end of the draft.
        XCTAssertEqual(model.selectedCompletion?.route, "mac_inbox")
    }

    func testFileUnderAcceptInsertsTheChosenRoute() async throws {
        let model = try fileUnderModel()
        model.plainDraft = "https://example.com/post"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil { model.completionVisible }

        model.acceptSelectedCompletion()

        XCTAssertEqual(model.plainDraft, "https://example.com/post @mac_inbox")
        XCTAssertFalse(model.fileUnderActive)
    }

    func testFileUnderEscapeKeepsTheDefaultWithoutReopening() async throws {
        let model = try fileUnderModel()
        let draft = "https://example.com/post"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionVisible }

        // Esc dismisses the list and keeps the bare URL (the default parent).
        model.dismissCompletion()
        XCTAssertFalse(model.completionVisible)
        XCTAssertEqual(model.plainDraft, draft)

        // A re-analysis of the same URL does not reopen the list.
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.previewResult != nil }
        XCTAssertFalse(model.completionVisible)
        XCTAssertFalse(model.fileUnderActive)
        XCTAssertEqual(
            model.statusText,
            "Would queue example.com/post → mac_inbox"
        )
    }

    func testFileUnderNeverOpensForLibraryHits() async throws {
        let model = try fileUnderModel()
        let draft = "https://example.com/captured"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.previewResult != nil }

        XCTAssertFalse(model.completionVisible)
        XCTAssertFalse(model.fileUnderActive)
        XCTAssertNil(model.completionResponse)
        XCTAssertEqual(model.statusText, "Already in your library: Captured Post")
    }

    func testExplicitRouteDraftNeverOpensFileUnder() async throws {
        let model = try fileUnderModel()
        let draft = "https://example.com/post @sase"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.previewResult != nil }

        XCTAssertFalse(model.fileUnderActive)
        XCTAssertEqual(
            model.statusText,
            "Would queue example.com/post → sase"
        )
    }

    private func fileUnderModel() throws -> CapturePanelModel {
        let model = CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
            ),
            debounceNanoseconds: 0
        )
        installTargetCache(
            on: model,
            targets: [
                CaptureTarget(
                    route: "mac_inbox",
                    name: "mac_inbox",
                    label: "mac_inbox.md",
                    kind: "inbox",
                    isDefault: true,
                    relativePath: "mac_inbox.md"
                ),
                CaptureTarget(
                    route: "sase",
                    name: "sase",
                    label: "sase.md",
                    kind: "project",
                    status: "wip",
                    relativePath: "sase.md"
                ),
            ]
        )
        return model
    }

    private func installTargetCache(
        on model: CapturePanelModel,
        targets: [CaptureTarget]
    ) {
        model.updateTargetCacheSnapshot(
            CaptureTargetsSnapshot(
                targets: CaptureTargetsResponse(ok: true, targets: targets),
                refreshedAt: Date(),
                stale: false,
                errorDescription: nil
            )
        )
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return source
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
