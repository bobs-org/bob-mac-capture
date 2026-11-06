import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureMergeInDesignTests: XCTestCase {
    func testRenderCompleteMergeInPreviews() throws {
        for name in [
            "one", "two", "five", "long-title", "duplicate-titles", "title-only",
            "blocked-target", "label", "task-list",
        ] {
            let success: CaptureCommandSuccess = try fixture(
                "capture-merge-in-complete-\(name).json")
            XCTAssertNotNil(CaptureMergeInPresentation(capture: success), name)
            let model = CapturePanelModel()
            model.previewResult = success
            model.previewResults = [success]
            model.previewState = .ready(success)
            try render(PreviewPane(model: model), name: "complete-\(name)")
            if name == "five" {
                let presentation = try XCTUnwrap(CaptureMergeInPresentation(capture: success))
                try render(
                    CaptureMergeInBandView(presentation: presentation, offerContent: nil),
                    name: "native-five", nativeControls: true
                )
            }
        }
    }

    func testRenderWarningFromFoldedSource() throws {
        let base: CaptureCommandSuccess = try fixture("capture-merge-in-complete-five.json")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        var merges = try XCTUnwrap(object["merges"] as? [[String: Any]])
        // Synthetic warning on the fifth source: its row starts folded, but
        // its consequence must stay visible below the disclosure button.
        let warning =
            "“Epsilon task” waited on “Approval”; “New outcome” does not · add &inbox:approval"
        let consequence: [String: Any] = [
            "kind": "prerequisite_left", "tone": "warning", "text": warning,
            "keys": ["inbox.md#^approval"],
        ]
        merges[4]["consequences"] = [consequence]
        object["merges"] = merges
        let success = try JSONDecoder().decode(
            CaptureCommandSuccess.self, from: JSONSerialization.data(withJSONObject: object))
        let presentation = try XCTUnwrap(CaptureMergeInPresentation(capture: success))
        XCTAssertEqual(presentation.count, 5)
        XCTAssertEqual(presentation.consequences.last?.text, warning)
        XCTAssertEqual(presentation.consequences.last?.symbol, "exclamationmark.triangle")
        try render(
            CaptureMergeInBandView(presentation: presentation, offerContent: nil),
            name: "native-folded-warning", nativeControls: true
        )
    }

    func testRenderPendingSourcesAndErrors() throws {
        for name in ["second", "error", "unmergeable"] {
            let failure: CaptureCommandFailure = try fixture(
                "capture-merge-in-pending-\(name).json")
            let pending = try XCTUnwrap(failure.mergeInPending)
            let presentation = try XCTUnwrap(CaptureMergeInPendingPresentation(pending: pending))
            XCTAssertFalse(presentation.canSubmit)
            try render(
                CaptureMergeInPendingCardView(presentation: presentation),
                name: "pending-\(name)"
            )
        }
    }

    func testRenderRefusalRewriteButtons() throws {
        for name in ["needs-new-task", "extra", "spacing-unicode"] {
            let parse: CaptureParseResponse = try fixture(
                "capture-merge-in-parse-rewrite-\(name).json")
            let diagnostic = try XCTUnwrap(parse.diagnostics.first)
            let rewrite = try XCTUnwrap(diagnostic.rewrite)
            let presentation = try XCTUnwrap(
                CaptureMergeInRefusalPresentation(
                    failure: CaptureCommandFailure(
                        error: diagnostic.message, code: diagnostic.code),
                    rewrites: [rewrite]
                ))
            try render(
                CaptureMergeInRefusalCardView(presentation: presentation) { _ in },
                name: "refusal-\(name)", nativeControls: true
            )
        }
    }

    func testRenderOriginDisclosuresForBothArrows() throws {
        for name in ["complete-two", "transfer-origin"] {
            let success: CaptureCommandSuccess = try fixture("capture-merge-in-\(name).json")
            let block = try XCTUnwrap(
                success.taskBlocks.first { $0.roles.contains("merge_target") })
            let presentation = CaptureTaskBlockPresentation(
                block: block, dryRun: success.dryRun, merges: success.merges)
            let folded = presentation.items(expandedFolds: [])
            let originIDs = Set(
                folded.compactMap { item -> Int? in
                    guard case .fold(let fold) = item, fold.style == .mergeOrigin else {
                        return nil
                    }
                    return fold.id
                })
            XCTAssertFalse(originIDs.isEmpty)
            for expanded in [false, true] {
                let items = presentation.items(expandedFolds: expanded ? originIDs : [])
                try render(
                    BlockDiffCard(
                        railTint: .purple, items: items, headlineEmphasis: true,
                        onExpandFold: { _ in }
                    ),
                    name: "origin-\(name)-\(expanded ? "expanded" : "folded")"
                )
            }
        }
    }

    private func fixture<T: Decodable>(_ name: String) throws -> T {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func render<V: View>(
        _ view: V, name: String, nativeControls: Bool = false
    ) throws {
        for width in [760, 620] as [CGFloat] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let filename = "merge-in-\(name)-\(Int(width))"
                if nativeControls {
                    try renderHosted(view, name: filename, width: width, appearance: appearance)
                } else {
                    try RenderFixtureWriter.write(
                        view, name: filename, width: width, appearance: appearance
                    )
                }
            }
        }
    }

    /// ImageRenderer substitutes yellow placeholders for native link buttons.
    /// Capture a hosted view to review the actual disclosure and rewrite controls.
    private func renderHosted<V: View>(
        _ view: V, name: String, width: CGFloat, appearance: NSAppearance.Name
    ) throws {
        guard let renderDir = ProcessInfo.processInfo.environment["BOB_MAC_CAPTURE_RENDER_DIR"],
            !renderDir.isEmpty
        else {
            throw XCTSkip("Set BOB_MAC_CAPTURE_RENDER_DIR to render native merge-in controls.")
        }
        _ = NSApplication.shared
        let dark = appearance == .darkAqua
        let host = NSHostingView(
            rootView:
                view
                .padding(10)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
        )
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(
            to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }
}
