import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Panel-side tests for reference items (`kind == "ref"`): the link palette
/// color, the underlined `ref_url` highlight, the live-preview card data and
/// footer verb, submit status and open-target behavior, and the notification.
/// Capture-side decode and wording live in `CaptureRefPresentationTests`
/// (`CaptureCoreTests`); every draft below is served by
/// `Tests/Fixtures/fake-bob` from the real-bob `ref-*.json` fixtures.
@MainActor
final class CaptureRefPanelTests: XCTestCase {
    func testLinkCategoryUsesLinkColor() {
        XCTAssertEqual(NSColor(CaptureEditorPalette.color(for: .link)), .linkColor)
    }

    func testLinkColorDiffersFromOtherCategories() {
        let link = NSColor(CaptureEditorPalette.color(for: .link))
        XCTAssertNotEqual(link, NSColor(CaptureEditorPalette.color(for: .neutral)))
        XCTAssertNotEqual(link, NSColor(CaptureEditorPalette.color(for: .route)))
    }

    func testQueuedPreviewNamesQueueActionAndStatus() async throws {
        let model = try refModel(draft: "https://example.com/post")

        model.preview()
        await waitUntil { !model.isPreviewing }

        let presentation = try XCTUnwrap(model.refPresentation)
        XCTAssertEqual(presentation.headline, "Save to reading queue")
        XCTAssertEqual(presentation.destinationLabel, "example.com/post")
        XCTAssertEqual(model.primaryActionTitle, "Queue")
        XCTAssertEqual(model.statusText, "Would queue for clipping → reading queue")
    }

    func testMixedBatchKeepsTodaysFooterTitle() async throws {
        let model = try refModel(draft: "buy milk\n\nhttps://example.com/2")

        model.preview()
        await waitUntil { !model.isPreviewing }

        XCTAssertEqual(model.previewResults.count, 2)
        XCTAssertNil(model.refPresentation)
        XCTAssertEqual(model.primaryActionTitle, "Capture")
    }

    func testRefURLSpanIsUnderlinedInEditor() async throws {
        let model = try refModel(draft: "https://example.com/post")
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil { model.previewResult != nil }

        let underlined = model.attributedDraft.runs.compactMap { run -> String? in
            guard run.underlineStyle == .single else {
                return nil
            }
            return String(model.attributedDraft[run.range].characters)
        }
        XCTAssertEqual(underlined.joined(), "https://example.com/post")
    }

    func testQueuedSubmitOpensNothing() async throws {
        let model = try refModel(draft: "https://example.com/post")
        var openedURLs: [URL] = []
        model.targetOpener = { openedURLs.append($0) }

        model.submit(openAfterCapture: true)
        await waitUntil { !model.isSubmitting }

        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertEqual(model.statusText, "Queued for clipping → reading queue")
    }

    func testInLibrarySubmitOpensTheNote() async throws {
        let model = try refModel(draft: "https://example.com/captured")
        var openedPaths: [String] = []
        model.targetOpener = { url in
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let path = components?.queryItems?.first { $0.name == "path" }?.value
            openedPaths.append(path ?? "")
        }

        model.submit(openAfterCapture: true)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(openedPaths, ["/tmp/bob-mac-capture-ref/vault/ref/papers/captured.md"])
        XCTAssertEqual(model.statusText, "Already in your library: Captured Post")
    }

    func testSingleQueuedRefNotificationContent() throws {
        let content = NotificationService.successContent(captures: [
            try refSuccessFixture("ref-queued.json"),
        ])

        XCTAssertEqual(content.title, "Queued for reading")
        XCTAssertEqual(content.subtitle, "example.com/post")
        XCTAssertEqual(content.body, "example.com/post → reading queue")
    }

    func testSingleInLibraryRefNotificationContent() throws {
        let content = NotificationService.successContent(captures: [
            try refSuccessFixture("ref-in-library.json"),
        ])

        XCTAssertEqual(content.title, "Already in your library")
        XCTAssertEqual(content.subtitle, "ref/papers/captured.md")
        XCTAssertEqual(content.body, "Captured Post")
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            ["/tmp/bob-mac-capture-ref/vault/ref/papers/captured.md"]
        )
    }

    private func refModel(draft: String) throws -> CapturePanelModel {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = draft
        return model
    }

    private func refSuccessFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            XCTFail("expected a successful Bob ref response")
            throw NSError(domain: "CaptureRefPanelTests", code: 1)
        }
        return success
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
