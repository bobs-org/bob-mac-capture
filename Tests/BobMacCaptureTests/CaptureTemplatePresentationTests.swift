import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureTemplatePresentationTests: XCTestCase {
    func testTemplateSlotPaletteUsesSixColorsAndWrapsByFieldIndex() {
        let colors: [Color] = (0..<6).map(CaptureEditorPalette.templateSlotColor(field:))

        XCTAssertEqual(colors, [.orange, .teal, .pink, .green, .purple, .brown])
        XCTAssertEqual(CaptureEditorPalette.templateSlotColor(field: 6), colors[0])
        XCTAssertEqual(CaptureEditorPalette.templateSlotColor(field: 7), colors[1])
        XCTAssertEqual(CaptureEditorPalette.templateSlotColor(field: -1), colors[5])
    }

    func testTemplateRowNeedIsQuietAndUsesBobsDiagnostic() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "@@template:\n"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)

        await waitUntil { model.parseDiagnostics.contains { $0.code == "template_missing_rows" } }

        let diagnostic = try XCTUnwrap(
            model.parseDiagnostics.first { $0.code == "template_missing_rows" }
        )
        XCTAssertNotNil(model.parsedTemplate)
        XCTAssertEqual(model.statusText, diagnostic.message)
        XCTAssertEqual(model.previewState, .idle)
        XCTAssertNil(model.errorMessage)
    }

    func testTemplateDiagnosticUnderlineUsesTypedRange() async throws {
        let model = try await modelForTemplateArityError()
        let diagnostic = try XCTUnwrap(model.parseDiagnostics.first { $0.code == "template_row_arity" })
        let range = try XCTUnwrap(diagnostic.range)
        let expectedRange = try XCTUnwrap(stringRange(in: model.plainDraft, byteRange: range))
        let underlined = model.attributedDraft.runs.compactMap { run -> String? in
            guard run.underlineStyle == .single, run.underlineColor == .red else {
                return nil
            }
            return String(model.attributedDraft[run.range].characters)
        }

        XCTAssertEqual(underlined.joined(), String(model.plainDraft[expectedRange]))
    }

    @available(macOS 26.0, *)
    func testRenderTemplateDraftAndPreviewInLightAndDark() async throws {
        guard ProcessInfo.processInfo.environment[
            "BOB_MAC_CAPTURE_RENDER_DIR"
        ]?.isEmpty == false else {
            throw XCTSkip("Set BOB_MAC_CAPTURE_RENDER_DIR to render the template presentation fixtures.")
        }

        let model = try await modelForTemplateArityError()
        let success = try decodeCaptureFixture("capture-template-example.json")
        model.previewResult = success
        model.previewResults = [success]
        model.previewState = .ready(success)

        let draft = VStack(alignment: .leading, spacing: 8) {
            Text("Template draft")
                .font(.headline)
            Text(model.attributedDraft)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            PreviewPane(model: model)
        }
        for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
            try RenderFixtureWriter.write(
                draft,
                name: "capture-template-draft",
                width: 724,
                appearance: appearance
            )
        }
    }

    private func modelForTemplateArityError() async throws -> CapturePanelModel {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "@@template:\nRecord {0} @work:{1}\n\nAcme abc extra"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil { model.parseDiagnostics.contains { $0.code == "template_row_arity" } }
        return model
    }

    private func decodeCaptureFixture(_ name: String) throws -> CaptureCommandSuccess {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            throw NSError(domain: "CaptureTemplatePresentationTests", code: 1)
        }
        return success
    }

    private func fakeBobPath() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("fake-bob")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw NSError(domain: "CaptureTemplatePresentationTests", code: 2)
        }
        return url.path
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        predicate: @escaping () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !predicate(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(predicate(), "Timed out waiting for the template parse to finish")
    }
}
