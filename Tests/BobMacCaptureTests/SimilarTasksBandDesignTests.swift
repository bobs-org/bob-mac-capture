import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Rendered-image review for the similar-tasks band: one PNG per visual
/// state at full and minimum panel widths, in both appearances.
@MainActor
final class SimilarTasksBandDesignTests: XCTestCase {
    func testRenderSimilarTasksBandStatesToPNG() throws {
        let cases: [(name: String, item: SimilarTasksBandItem?, folded: Bool)] = [
            ("none", nil, false),
            ("one", oneRow, false),
            ("two-plus", twoRowsPlus, false),
            ("same-title", sameTitle, false),
            ("closed", closedRow, false),
            ("project", projectRow, false),
            ("reading", readingRow, false),
            ("bulk", bulkRow, false),
            ("folded", twoRowsPlus, true),
            ("linked", linkedRow, false),
            ("focused", focusedRow, false),
        ]
        for entry in cases {
            let view = card(
                item: entry.item,
                folded: entry.folded,
                focusedRowID: entry.name == "focused" ? entry.item?.rows.first?.id : nil,
                chosenAction: entry.name == "focused" ? .note : nil
            )
            for width in [760, 620] as [CGFloat] {
                try RenderFixtureWriter.write(
                    view,
                    name: "similar-tasks-\(entry.name)-\(Int(width))",
                    width: width,
                    appearance: .aqua
                )
                try RenderFixtureWriter.write(
                    view,
                    name: "similar-tasks-\(entry.name)-\(Int(width))",
                    width: width,
                    appearance: .darkAqua
                )
            }
        }
    }

    private var oneRow: SimilarTasksBandItem {
        SimilarTasksBandItem(
            index: 0,
            mode: "task",
            rows: [
                row(
                    number: 1,
                    title: "Install new UPS battery",
                    band: .possibleDuplicate,
                    ranges: [CaptureRange(start: 12, end: 23)],
                    statusSymbol: "?",
                    statusName: "Blocked"
                ),
            ],
            showsHeader: true
        )
    }

    private var twoRowsPlus: SimilarTasksBandItem {
        SimilarTasksBandItem(
            index: 0,
            mode: "task",
            rows: [
                row(
                    number: 1,
                    title: "Install new UPS battery",
                    band: .possibleDuplicate,
                    ranges: [CaptureRange(start: 12, end: 23)],
                    statusSymbol: "?",
                    statusName: "Blocked"
                ),
                row(
                    number: 2,
                    title: "Order a replacement UPS battery for athena",
                    band: .similar,
                    ranges: [CaptureRange(start: 22, end: 33)],
                    statusSymbol: " ",
                    statusName: "Ready",
                    key: "dev.md#order-ups"
                ),
            ],
            overflowCount: 2,
            showsHeader: true
        )
    }

    private var sameTitle: SimilarTasksBandItem {
        SimilarTasksBandItem(
            index: 0,
            mode: "task",
            rows: [
                row(
                    number: 1,
                    title: "Install new UPS battery",
                    band: .sameTitle,
                    ranges: [CaptureRange(start: 0, end: 23)],
                    statusSymbol: " ",
                    statusName: "Todo"
                ),
            ],
            showsHeader: true
        )
    }

    private var closedRow: SimilarTasksBandItem {
        SimilarTasksBandItem(
            index: 0,
            mode: "task",
            rows: [
                row(
                    number: 1,
                    title: "Close all open task beads",
                    band: .closedDuplicate,
                    statusSymbol: "x",
                    statusName: "Done",
                    closed: CaptureRelatedClosed(
                        status: "done",
                        date: "2026-10-12",
                        daysAgo: 8
                    ),
                    locator: "sase",
                    route: "sase",
                    key: "sase.md#close-beads"
                ),
            ],
            showsHeader: true
        )
    }

    private var projectRow: SimilarTasksBandItem {
        SimilarTasksBandItem(
            index: 0,
            mode: "project_note",
            rows: [
                row(
                    number: 1,
                    title: "Ship similar tasks band",
                    band: .possibleDuplicate,
                    kind: "project",
                    statusSymbol: "?",
                    statusName: "Blocked",
                    locator: "sase",
                    route: "sase",
                    key: "sase.md#prj"
                ),
            ],
            showsHeader: true
        )
    }

    private var readingRow: SimilarTasksBandItem {
        SimilarTasksBandItem(
            index: 0,
            mode: "task",
            rows: [
                row(
                    number: 1,
                    title: "Read the capture paper",
                    band: .similar,
                    kind: "reading",
                    statusSymbol: "*",
                    statusName: "Next",
                    locator: "ref",
                    route: "ref",
                    key: "ref.md#capture-paper"
                ),
            ],
            showsHeader: true
        )
    }

    private var bulkRow: SimilarTasksBandItem {
        SimilarTasksBandItem(
            index: 0,
            mode: "task",
            rows: [
                row(
                    number: 1,
                    title: "Close all open task beads",
                    band: .closedDuplicate,
                    statusSymbol: "x",
                    statusName: "Done",
                    closed: CaptureRelatedClosed(
                        status: "done",
                        date: "2026-10-12",
                        daysAgo: 8
                    ),
                    locator: "sase",
                    route: "sase",
                    key: "sase.md#close-beads"
                ),
            ],
            showsHeader: false
        )
    }

    private var linkedRow: SimilarTasksBandItem {
        SimilarTasksBandItem(
            index: 0,
            mode: "task",
            rows: [
                SimilarTasksBandRow(
                    itemIndex: 0,
                    rowNumber: 1,
                    match: match(
                        title: "Install new UPS battery",
                        band: .possibleDuplicate,
                        ranges: [CaptureRange(start: 12, end: 23)],
                        statusSymbol: "?",
                        statusName: "Blocked"
                    ),
                    linkedBy: .relation
                ),
            ],
            showsHeader: true
        )
    }

    private var focusedRow: SimilarTasksBandItem {
        SimilarTasksBandItem(
            index: 0,
            mode: "task",
            rows: [
                SimilarTasksBandRow(
                    itemIndex: 0,
                    rowNumber: 1,
                    match: CaptureRelatedMatch(
                        key: "dev.md#ups",
                        band: .possibleDuplicate,
                        title: "Install new UPS battery",
                        matchedRanges: [CaptureRange(start: 12, end: 23)],
                        kind: "task",
                        statusSymbol: "?",
                        statusName: "Blocked",
                        route: "dev",
                        locator: "dev",
                        notePath: "dev.md",
                        target: "/Users/test/bob/dev.md",
                        line: 42,
                        taskRef: "42:ab12cd34",
                        blockID: "ups",
                        actions: [.relate, .note, .needs, .blocks, .open, .discard],
                        defaultAction: .note
                    )
                ),
            ],
            showsHeader: true
        )
    }

    private func card(
        item: SimilarTasksBandItem?,
        folded: Bool,
        focusedRowID: String? = nil,
        chosenAction: CaptureRelatedAction? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("+ dev · end of Tasks · task")
                .foregroundStyle(.secondary)
            Text("- [ ] Install new UPS battery")
            Text("dev.md")
                .foregroundStyle(.secondary)
            if let item {
                SimilarTasksBandView(
                    item: item,
                    folded: folded,
                    focusedRowID: focusedRowID,
                    chosenAction: chosenAction
                )
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }

    private func row(
        number: Int,
        title: String,
        band: CaptureRelatedBand,
        ranges: [CaptureRange] = [],
        kind: String = "task",
        statusSymbol: String,
        statusName: String,
        closed: CaptureRelatedClosed? = nil,
        locator: String = "dev",
        route: String = "dev",
        key: String? = nil
    ) -> SimilarTasksBandRow {
        SimilarTasksBandRow(
            itemIndex: 0,
            rowNumber: number,
            match: match(
                title: title,
                band: band,
                ranges: ranges,
                kind: kind,
                statusSymbol: statusSymbol,
                statusName: statusName,
                closed: closed,
                locator: locator,
                route: route,
                key: key
            )
        )
    }

    private func match(
        title: String,
        band: CaptureRelatedBand,
        ranges: [CaptureRange] = [],
        kind: String = "task",
        statusSymbol: String,
        statusName: String,
        closed: CaptureRelatedClosed? = nil,
        locator: String = "dev",
        route: String = "dev",
        key: String? = nil
    ) -> CaptureRelatedMatch {
        CaptureRelatedMatch(
            key: key ?? "\(route).md#\(title)",
            band: band,
            title: title,
            matchedRanges: ranges,
            kind: kind,
            statusSymbol: statusSymbol,
            statusName: statusName,
            closed: closed,
            route: route,
            locator: locator,
            notePath: "\(route).md"
        )
    }
}
