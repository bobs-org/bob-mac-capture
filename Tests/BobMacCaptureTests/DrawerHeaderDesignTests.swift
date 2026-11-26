import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Rendered-image review for Bob-annotated drawer headers in the shared
/// block diff card: nonempty, empty, removed, legacy-as-sent, and
/// section-marker headers next to a requirement row and an ordinary bold
/// note, plus a mixed-case transfer destination. Real rows come from
/// `drawer-capture-*.json`; edge cases use inline JSON so this test never
/// touches the drawer fixture generator. Every render goes through
/// `RenderFixtureWriter` in light, dark, and increased contrast so CI
/// uploads them under `render-fixtures`. Inspect the PNGs for the outline
/// tray, semibold verbatim titles with no `**`, muted empty drawers, title
/// wrapping, and no inherited bold or strike leakage.
final class DrawerHeaderDesignTests: XCTestCase {
    @MainActor
    func testDrawerHeadersKeepVerbatimTitles() throws {
        let success: CaptureCommandSuccess = try fixture("drawer-capture-new.json")
        let block = try XCTUnwrap(success.taskBlocks.first)
        let presentation = CaptureTaskBlockPresentation(block: block, dryRun: true)
        let headers = presentation.rows.filter(\.showsDrawerHeader)
        XCTAssertEqual(
            headers.map(\.drawer?.title),
            ["Requirements", "FUTURE WORK", "Perf Budget"]
        )
        for row in headers {
            let title = try XCTUnwrap(row.drawer?.title)
            XCTAssertFalse(title.contains("**"), "header derives no raw stars: \(title)")
        }
        // The legacy ALL-CAPS title keeps its spelling exactly as sent.
        XCTAssertTrue(headers.contains {
            $0.drawer?.title == "FUTURE WORK" && $0.drawer?.marker == .legacyCaps
        })

        let edge = try edgeRows()
        let indexed = Dictionary(uniqueKeysWithValues: edge.map { ($0.content, $0) })
        XCTAssertTrue(try XCTUnwrap(indexed["- **Perf Budget**"]).showsDrawerHeader)
        XCTAssertTrue(try XCTUnwrap(indexed["- ****"]).showsDrawerHeader)
        XCTAssertTrue(try XCTUnwrap(indexed["- **Someday**"]).showsDrawerHeader)
        XCTAssertTrue(try XCTUnwrap(indexed["- **Old Drawer**"]).showsDrawerHeader)
        XCTAssertTrue(try XCTUnwrap(indexed["- **Area Notes**"]).showsDrawerHeader)
        // The badge row keeps requirement precedence even when annotated.
        XCTAssertFalse(try XCTUnwrap(indexed["- [ ] Scope it"]).showsDrawerHeader)
        // An ordinary bold note without an annotation renders as today.
        XCTAssertFalse(try XCTUnwrap(indexed["- **Just bold**"]).showsDrawerHeader)

        let transfer: CaptureCommandSuccess = try fixture(
            "capture-transfer-drawer-merge.json")
        let destination = try XCTUnwrap(
            CaptureTransferPresentation(capture: transfer)?.destination)
        XCTAssertEqual(destination.containerLabel, "› Perf Budget")
    }

    @MainActor
    func testRenderDrawerHeaders() throws {
        let edge = try edgeRows()
        let edgeCard = VStack(alignment: .leading, spacing: 12) {
            Text("Drawer headers in the preview").font(.headline)
            BlockDiffCard(railTint: .purple, rows: edge, headlineEmphasis: true)
        }
        .padding(16)

        let real: CaptureCommandSuccess = try fixture("drawer-capture-new.json")
        let model = CapturePanelModel()
        model.previewResult = real
        model.previewResults = [real]
        model.previewState = .ready(real)
        let realPane = PreviewPane(model: model)

        for width in [760, 620] as [CGFloat] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                let suffix = contrast == .increased ? "-high-contrast" : ""
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    try RenderFixtureWriter.write(
                        edgeCard
                            .frame(width: width)
                            .environment(\._colorSchemeContrast, contrast),
                        name: "drawer-headers-edge-\(Int(width))\(suffix)",
                        width: width,
                        appearance: appearance
                    )
                    try RenderFixtureWriter.write(
                        realPane
                            .frame(width: width)
                            .environment(\._colorSchemeContrast, contrast),
                        name: "drawer-headers-real-\(Int(width))\(suffix)",
                        width: width,
                        appearance: appearance
                    )
                }
            }
        }
    }

    /// Edge-case rows through the real task presentation, so tokens,
    /// requirement precedence, and headline flags match the preview pane.
    private func edgeRows() throws -> [CaptureBlockDiffRow] {
        let lines = try [
            #"{"text":"- **Perf Budget**","depth":0,"change":"added","drawer":{"title":"Perf Budget","key":"PERF BUDGET","marker":"bold","empty":false}}"#,
            #"{"text":"- ****","depth":1,"change":"added","drawer":{"title":"Drafts","key":"DRAFTS","marker":"bold","empty":true}}"#,
            #"{"text":"- **Someday**","depth":1,"change":"added","drawer":{"title":"Someday","key":"SOMEDAY","marker":"future_marker","empty":false}}"#,
            #"{"text":"- **Old Drawer**","depth":1,"change":"removed","drawer":{"title":"Old Drawer","key":"OLD DRAWER","marker":"bold","empty":false}}"#,
            #"{"text":"- **Area Notes**","depth":1,"change":"added","drawer":{"title":"Area Notes","key":"AREA NOTES","marker":"section","empty":false}}"#,
            #"{"text":"- **Quarterly planning follow-ups and deferred maintenance backlog review across every active workstream**","depth":1,"change":"added","drawer":{"title":"Quarterly planning follow-ups and deferred maintenance backlog review across every active workstream","key":"QUARTERLY PLANNING","marker":"bold","empty":false}}"#,
            #"{"text":"- **Release Checklist**","depth":1,"change":"changed","before":"- **RELEASE CHECKLIST**","drawer":{"title":"Release Checklist","key":"RELEASE CHECKLIST","marker":"bold","empty":false}}"#,
            #"{"text":"- [ ] Scope it","depth":1,"change":"added","req":{"depth":1,"state":"pending"},"drawer":{"title":"Scope","key":"SCOPE","marker":"bold","empty":false}}"#,
            #"{"text":"- **Just bold**","depth":1,"change":"added"}"#,
        ].map { json throws -> CaptureBlockLine in
            try JSONDecoder().decode(CaptureBlockLine.self, from: Data(json.utf8))
        }
        let block = CaptureTaskBlock(
            relativeTarget: "foo.md",
            route: "foo",
            line: 7,
            blockID: "bar",
            text: "Upgrade Postgres",
            statusSymbol: " ",
            statusName: "Ready",
            lines: lines
        )
        return CaptureTaskBlockPresentation(block: block, dryRun: true).rows
    }

    private func fixture<T: Decodable>(_ name: String) throws -> T {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
