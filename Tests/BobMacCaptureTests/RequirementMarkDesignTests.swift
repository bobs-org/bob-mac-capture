import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class RequirementMarkDesignTests: XCTestCase {
    func testMarksKeepOneSlotAndMetSharesPendingOutline() {
        let rect = CGRect(x: 0, y: 0, width: 16, height: 16)
        let pending = RequirementMarkShape(state: .pending).path(in: rect)
        let met = RequirementMarkShape(state: .met).path(in: rect)
        XCTAssertEqual(pending, met)
        XCTAssertEqual(pending.boundingRect.width, 12.6, accuracy: 0.001)
        XCTAssertEqual(pending.boundingRect.height, 12.6, accuracy: 0.001)
        XCTAssertNotEqual(RequirementMarkShape(state: .dropped).path(in: rect), pending)
        XCTAssertNotEqual(RequirementMarkShape(state: .carried).path(in: rect), pending)
        for state in CaptureRequirementState.allCases {
            let host = NSHostingView(rootView: RequirementMark(state: state))
            XCTAssertEqual(host.fittingSize.width, 13, accuracy: 0.01)
            XCTAssertEqual(host.fittingSize.height, 13, accuracy: 0.01)
        }
    }

    func testRenderRequirementPreviewAndAgendaStates() throws {
        let lines = CaptureRequirementState.allCases.enumerated().map { index, state in
            CaptureBlockLine(
                text: "\t- [ ] \(state.rawValue.capitalized) scope with [[dev|details]]",
                depth: index % 3 + 1,
                change: state == .dropped ? .changed : .unchanged,
                before: state == .dropped ? "\t- [ ] Earlier scope" : nil,
                req: CaptureRequirementAnnotation(depth: index % 3 + 1, state: state))
        }
        let block = CaptureTaskBlock(
            relativeTarget: "dev.md", route: "dev", line: 1, text: "Ship parser",
            lines: [CaptureBlockLine(text: "- [ ] #task Ship parser")] + lines)
        let presentation = CaptureTaskBlockPresentation(block: block, dryRun: true)
        let view = VStack(alignment: .leading, spacing: 12) {
            Text("Requirements in the preview").font(.headline)
            BlockDiffCard(railTint: .teal, rows: presentation.rows, headlineEmphasis: true)
            Text("Requirements in today's agenda").font(.headline)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let req = line.req!
                let row = CaptureAgendaRow(
                    kind: .childLine, text: "\(req.state.rawValue.capitalized) scope",
                    depth: line.depth, lineLimit: 2,
                    accessibilityLabel: req.accessibilityLabel, req: req)
                CaptureAgendaRowView(
                    row: row, role: .current, expands: false, chipUnit: nil, onExpand: { _ in })
            }
        }
        .padding(16)
        for width in [CGFloat(420), CGFloat(760)] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                try RenderFixtureWriter.write(
                    view, name: "requirement-states-\(Int(width))", width: width,
                    appearance: appearance)
            }
        }
    }
}
