import XCTest

@testable import CaptureCore

/// Presentation coverage for batch-level `task_blocks`: captions and
/// picker statuses per status symbol, the status-name fallback, the
/// New/Created badge, rows and depth clamping, folding of long quiet
/// runs, the accessibility summary, and the covers-preview-lines rule.
/// Fixture provenance is documented on `CaptureModelTests`.
final class CaptureTaskBlockPresentationTests: XCTestCase {
    private func blockFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(
            contentsOf: fixtures.appendingPathComponent(name),
            encoding: .utf8
        )
        let decoded = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(text.utf8)
        )
        guard case .success(let success) = decoded else {
            throw TaskBlockPresentationFixtureError.expectedSuccess
        }
        return success
    }

    private func presentation(
        _ fixture: String,
        blockIndex: Int = 0,
        dryRun: Bool = false
    ) throws -> CaptureTaskBlockPresentation {
        let success = try blockFixture(fixture)
        return CaptureTaskBlockPresentation(
            block: success.taskBlocks[blockIndex],
            dryRun: dryRun
        )
    }

    private func block(
        statusSymbol: String = "/",
        statusName: String = "In Progress",
        created: Bool = false,
        lines: [CaptureBlockLine] = []
    ) -> CaptureTaskBlock {
        CaptureTaskBlock(
            relativeTarget: "sase.md",
            route: "sase",
            line: 1,
            blockID: "capture",
            text: "Port capture to PIW sase-core",
            statusSymbol: statusSymbol,
            statusName: statusName,
            created: created,
            roles: ["sub_bullet"],
            lines: lines
        )
    }

    // MARK: - Captions, statuses, and badges

    func testInProgressCaptionAndStatus() throws {
        let presented = try presentation("sub-bullet-task-block.json", dryRun: true)

        XCTAssertEqual(presented.status, .inProgress)
        XCTAssertEqual(presented.statusText, "In Progress")
        XCTAssertEqual(presented.captionText, "In Progress · sase.md · line 1")
        XCTAssertNil(presented.badgeText)
        XCTAssertEqual(
            presented.identity,
            CaptureTaskBlockPresentation.Identity(
                relativeTarget: "sase.md",
                line: 1,
                blockID: "capture"
            )
        )
    }

    func testStatusPerSymbol() throws {
        let cases: [(symbol: String, name: String, status: CapturePickerTaskStatus)] = [
            ("/", "In Progress", .inProgress),
            ("*", "Next", .next),
            (" ", "Todo", .todo),
            ("?", "Blocked", .blocked),
            ("x", "Done", .done),
            ("-", "Canceled", .canceled),
        ]
        for (symbol, name, status) in cases {
            let presented = CaptureTaskBlockPresentation(
                block: block(statusSymbol: symbol, statusName: name),
                dryRun: true
            )
            XCTAssertEqual(presented.status, status, "symbol \(symbol)")
            XCTAssertEqual(presented.statusText, name, "symbol \(symbol)")
            XCTAssertEqual(
                presented.captionText,
                "\(name) · sase.md · line 1",
                "symbol \(symbol)"
            )
        }
    }

    func testStatusNameFallsBackToDisplayName() throws {
        let empty = CaptureTaskBlockPresentation(
            block: block(statusSymbol: "?", statusName: ""),
            dryRun: true
        )
        XCTAssertEqual(empty.status, .blocked)
        XCTAssertEqual(empty.statusText, "Blocked")
        XCTAssertEqual(empty.captionText, "Blocked · sase.md · line 1")

        let unknown = CaptureTaskBlockPresentation(
            block: block(statusSymbol: "?", statusName: "Unknown"),
            dryRun: true
        )
        XCTAssertEqual(unknown.statusText, "Blocked")
    }

    func testUnknownSymbolKeepsItsStatusName() throws {
        let presented = CaptureTaskBlockPresentation(
            block: block(statusSymbol: "~", statusName: "Waiting"),
            dryRun: true
        )

        XCTAssertEqual(presented.status, .other("Waiting"))
        XCTAssertEqual(presented.statusText, "Waiting")
    }

    func testCreatedBadgeReadsNewOnDryRunAndCreatedOnceCommitted() throws {
        let preview = CaptureTaskBlockPresentation(
            block: block(created: true),
            dryRun: true
        )
        XCTAssertEqual(preview.badgeText, "New")

        let committed = CaptureTaskBlockPresentation(
            block: block(created: true),
            dryRun: false
        )
        XCTAssertEqual(committed.badgeText, "Created")
    }

    // MARK: - Rows

    func testRowsStripIndentationMarkHeadlineAndTokenize() throws {
        let presented = try presentation("sub-bullet-task-block.json", dryRun: true)

        XCTAssertEqual(presented.rows.count, 6)
        let headline = presented.rows[0]
        XCTAssertEqual(
            headline.content,
            "- [/] #task Port capture to PIW sase-core [created:: 2026-09-30] ^capture"
        )
        XCTAssertEqual(headline.depth, 0)
        XCTAssertEqual(headline.change, .unchanged)
        XCTAssertNil(headline.beforeContent)
        XCTAssertTrue(headline.isHeadline)
        XCTAssertFalse(headline.tokens.isEmpty)
        XCTAssertEqual(headline.tokens[0].text, "-")
        XCTAssertEqual(headline.tokens[0].role, .syntax)
        XCTAssertEqual(headline.tokens[2].role, .checkbox("/"))
        XCTAssertTrue(headline.tokens.contains { $0.role == .tag && $0.text == "#task" })
        XCTAssertTrue(headline.tokens.contains { $0.role == .field })
        XCTAssertEqual(headline.tokens.last?.role, .blockID)
        XCTAssertEqual(headline.tokens.last?.text, "^capture")

        XCTAssertEqual(presented.rows[3].content, "- Should reuse as much of PIW sase-core code as possible!")
        XCTAssertEqual(presented.rows[3].depth, 1)
        XCTAssertEqual(presented.rows[3].change, .added)
        XCTAssertFalse(presented.rows[3].isHeadline)
        for child in presented.rows.dropFirst() {
            XCTAssertFalse(child.tokens.isEmpty)
        }
    }

    func testDepthClampsToMaxDepth() throws {
        let presented = CaptureTaskBlockPresentation(
            block: block(lines: [
                CaptureBlockLine(text: "- top", depth: 99),
                CaptureBlockLine(text: "- next", depth: -3),
            ]),
            dryRun: true
        )

        XCTAssertEqual(presented.rows[0].depth, CapturePomodoroBlockPresentation.maxDepth)
        XCTAssertTrue(presented.rows[0].isHeadline)
        XCTAssertEqual(presented.rows[1].depth, 0)
        XCTAssertFalse(presented.rows[1].isHeadline)
    }

    // MARK: - Folding

    private func unchangedBlock(rowCount: Int, changes: [Int] = []) -> CaptureTaskBlock {
        block(lines: (0..<rowCount).map { index in
            CaptureBlockLine(
                text: index == 0 ? "- [/] #task Top ^top" : "- row \(index)",
                depth: index == 0 ? 0 : 1,
                change: changes.contains(index) ? .added : .unchanged
            )
        })
    }

    func testBlocksAtOrBelowThresholdNeverFold() throws {
        for count in [6, 24] {
            let presented = CaptureTaskBlockPresentation(
                block: unchangedBlock(rowCount: count, changes: [count - 1]),
                dryRun: true
            )
            XCTAssertEqual(
                presented.items(expandedFolds: []).count,
                count,
                "\(count) rows render in full"
            )
            XCTAssertTrue(
                presented.items(expandedFolds: []).allSatisfy {
                    if case .row = $0 { return true }
                    return false
                }
            )
        }
    }

    func testBlockWithoutChangesNeverFolds() throws {
        let presented = CaptureTaskBlockPresentation(
            block: unchangedBlock(rowCount: 30),
            dryRun: true
        )

        XCTAssertEqual(presented.items(expandedFolds: []).count, 30)
    }

    func testLongFixtureFoldsItsWorkLogTail() throws {
        let presented = try presentation("sub-bullet-long-task-block.json", dryRun: true)
        let items = presented.items(expandedFolds: [])

        // The task line, the added row, its context, and the nearby
        // ancestors stay visible; the 29 quiet Work Log entries collapse.
        XCTAssertEqual(items.count, 6)
        guard case .row(let first) = items[0] else {
            return XCTFail("the task line stays visible")
        }
        XCTAssertTrue(first.isHeadline)
        XCTAssertTrue(first.content.contains("Long parent"))
        let visibleContents = items.compactMap { item -> String? in
            if case .row(let row) = item { return row.content }
            return nil
        }
        XCTAssertTrue(visibleContents.contains("- fresh note"))
        XCTAssertTrue(visibleContents.contains(where: { $0.contains("WORK LOG") }))
        guard case .fold(let fold) = items.last else {
            return XCTFail("the Work Log tail folds")
        }
        XCTAssertEqual(fold.id, 5)
        XCTAssertEqual(fold.count, 29)
        XCTAssertEqual(fold.depth, 2)
        XCTAssertEqual(fold.rows.count, 29)
    }

    func testExpandingAFoldInlinesItsRows() throws {
        let presented = try presentation("sub-bullet-long-task-block.json", dryRun: true)
        let expanded = presented.items(expandedFolds: [5])

        XCTAssertEqual(expanded.count, 34)
        XCTAssertTrue(expanded.allSatisfy {
            if case .row = $0 { return true }
            return false
        })
    }

    func testShortQuietRunsNeverFold() throws {
        // 26 rows with changes every four rows: the gaps between the
        // visible windows are two rows, so nothing collapses.
        let presented = CaptureTaskBlockPresentation(
            block: unchangedBlock(
                rowCount: 26,
                changes: [5, 9, 13, 17, 21]
            ),
            dryRun: true
        )
        let items = presented.items(expandedFolds: [])

        XCTAssertEqual(items.count, 26)
    }

    // MARK: - Accessibility

    func testAccessibilityCoversEveryRow() throws {
        let presented = try presentation("sub-bullet-long-task-block.json", dryRun: true)

        XCTAssertTrue(
            presented.accessibilitySummary.hasPrefix("Long parent, In Progress, sase.md line 1: ")
        )
        XCTAssertTrue(presented.accessibilitySummary.contains("added - fresh note"))
        XCTAssertTrue(
            presented.accessibilitySummary.contains("- 2026-09-30 worked on entry 30")
        )
    }

    func testAccessibilityAnnouncesCreatedBadge() throws {
        let presented = CaptureTaskBlockPresentation(
            block: block(
                statusSymbol: " ",
                statusName: "Ready",
                created: true,
                lines: [CaptureBlockLine(text: "- [ ] #task New ^new", depth: 0, change: .added)]
            ),
            dryRun: true
        )

        XCTAssertTrue(
            presented.accessibilitySummary.hasPrefix(
                "Port capture to PIW sase-core, Ready, sase.md line 1, New: "
            )
        )
        XCTAssertTrue(presented.accessibilitySummary.contains("added - [ ] #task New ^new"))
    }

    // MARK: - Covers rule

    func testCoversIsTrueForEveryFixtureItem() throws {
        for fixture in [
            "sub-bullet-task-block.json",
            "sub-bullet-section-task-block.json",
            "sub-bullet-children-task-block.json",
            "sub-bullet-global-task-block.json",
            "sub-bullet-long-task-block.json",
        ] {
            let success = try blockFixture(fixture)
            for item in success.normalizedCaptures {
                XCTAssertTrue(
                    CaptureTaskBlockPresentation.covers(item, blocks: success.taskBlocks),
                    "\(fixture): \(item.taskLine) should be covered"
                )
            }
        }
    }

    func testCoversIsFalseWithoutBlocks() throws {
        let success = try blockFixture("sub-bullet-task-block.json")

        XCTAssertFalse(
            CaptureTaskBlockPresentation.covers(success, blocks: [])
        )
    }

    func testCoversIsFalseWhenRelativeTargetsDiffer() throws {
        let success = try blockFixture("sub-bullet-task-block.json")
        let other = CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: true,
            route: "other",
            routeLabel: "other.md",
            relativeTarget: "other.md",
            target: "/tmp/vault/other.md",
            text: "Should reuse as much of PIW sase-core code as possible!",
            taskLine: "- Should reuse as much of PIW sase-core code as possible!",
            kind: "sub_bullet",
            created: "2026-10-02",
            placement: "appended"
        )

        XCTAssertFalse(
            CaptureTaskBlockPresentation.covers(other, blocks: success.taskBlocks)
        )
    }

    func testCoversNeedsADistinctRowPerDuplicateBullet() throws {
        let lines = [
            CaptureBlockLine(
                text: "\t- dup",
                depth: 1,
                change: .added
            ),
        ]
        let single = block(lines: lines)
        let duplicate = CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: true,
            route: "sase",
            routeLabel: "sase.md",
            relativeTarget: "sase.md",
            target: "/tmp/vault/sase.md",
            text: "dup",
            taskLine: "- dup",
            kind: "sub_bullet",
            created: "2026-10-02",
            placement: "appended",
            subBullets: ["- dup"]
        )

        XCTAssertFalse(CaptureTaskBlockPresentation.covers(duplicate, blocks: [single]))
        let doubled = block(lines: lines + lines)
        XCTAssertTrue(CaptureTaskBlockPresentation.covers(duplicate, blocks: [doubled]))
    }

    func testCoversIgnoresRemovedLines() throws {
        let removedOnly = block(lines: [
            CaptureBlockLine(text: "\t- gone", depth: 1, change: .removed),
        ])
        let success = try blockFixture("sub-bullet-task-block.json")

        XCTAssertFalse(
            CaptureTaskBlockPresentation.covers(success, blocks: [removedOnly])
        )
    }
}

private enum TaskBlockPresentationFixtureError: Error {
    case expectedSuccess
}
