import Foundation
import XCTest

@testable import CaptureCore

final class CaptureDrawerAnnotationTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    private func line(_ json: String) throws -> CaptureBlockLine {
        try JSONDecoder().decode(CaptureBlockLine.self, from: Data(json.utf8))
    }

    private func success(_ data: Data) throws -> CaptureCommandSuccess {
        try JSONDecoder().decode(CaptureCommandSuccess.self, from: data)
    }

    func testAnnotationDecodesFullAndPartialPayloads() throws {
        let full = try line(
            #"{"text":"\t- **Perf Budget**","depth":1,"change":"added","drawer":{"title":"Perf Budget","key":"PERF BUDGET","marker":"bold","empty":true}}"#
        )
        XCTAssertEqual(full.text, "\t- **Perf Budget**")
        XCTAssertEqual(full.depth, 1)
        XCTAssertEqual(full.change, .added)
        XCTAssertEqual(full.drawer?.title, "Perf Budget")
        XCTAssertEqual(full.drawer?.key, "PERF BUDGET")
        XCTAssertEqual(full.drawer?.marker, .bold)
        XCTAssertTrue(try XCTUnwrap(full.drawer).empty)

        let partials = [
            (#"{"title":"Future Work","marker":"section","empty":false}"#, "Future Work"),
            (#"{"title":"Future Work","key":"FUTURE WORK","empty":false}"#, "FUTURE WORK"),
            (#"{"title":"Future Work","key":"FUTURE WORK","marker":"bold"}"#, "FUTURE WORK"),
        ]
        for (payload, expectedKey) in partials {
            let decoded = try line(#"{"text":"- **Future Work**","drawer":\#(payload)}"#)
            let drawer = try XCTUnwrap(decoded.drawer)
            XCTAssertEqual(drawer.title, "Future Work")
            XCTAssertEqual(drawer.key, expectedKey)
        }
    }

    func testMalformedAnnotationDoesNotDiscardItsLine() throws {
        let decoded = try line(
            #"{"text":"  - **Future Work**","depth":2,"change":"added","before":"old","drawer":{"title":17,"key":"FUTURE WORK","marker":"bold","empty":false}}"#
        )
        XCTAssertNil(decoded.drawer)
        XCTAssertEqual(decoded.text, "  - **Future Work**")
        XCTAssertEqual(decoded.depth, 2)
        XCTAssertEqual(decoded.change, .added)
        XCTAssertEqual(decoded.before, "old")
    }

    func testDrawerMarkersAndVerbatimUnicodeTitles() throws {
        let cases: [(String, CaptureDrawerMarker)] = [
            ("bold", .bold),
            ("legacy_caps", .legacyCaps),
            ("section", .section),
            ("future_marker", .unknown),
        ]
        for (marker, expected) in cases {
            let decoded = try line(
                #"{"text":"- Future","drawer":{"title":"Café","key":"CAFE","marker":"\#(marker)","empty":false}}"#
            )
            XCTAssertEqual(decoded.drawer?.marker, expected)
            XCTAssertEqual(decoded.drawer?.title, "Café")
        }

        for title in ["Café", "C++ Notes", "Q1: Goals", "𐐷 Plan"] {
            let encodedTitle = try XCTUnwrap(
                String(data: JSONSerialization.data(withJSONObject: [title]), encoding: .utf8)
            )
            let titleJSON = String(encodedTitle.dropFirst().dropLast())
            let decoded = try line(
                #"{"text":"- title","drawer":{"title":\#(titleJSON),"key":"key","marker":"bold","empty":false}}"#
            )
            XCTAssertEqual(decoded.drawer?.title, title)
        }
    }

    func testSummaryMarkerIsOptionalTolerantAndUnknownSafe() throws {
        let absent = try JSONDecoder().decode(
            CaptureDrawerSummary.self,
            from: Data(#"{"title":"Perf Budget","key":"PERF BUDGET","created":true}"#.utf8)
        )
        XCTAssertNil(absent.marker)

        for (marker, expected) in [
            ("section", CaptureDrawerMarker.section),
            ("future_marker", CaptureDrawerMarker.unknown),
        ] {
            let decoded = try JSONDecoder().decode(
                CaptureDrawerSummary.self,
                from: Data(#"{"title":"Perf Budget","marker":"\#(marker)"}"#.utf8)
            )
            XCTAssertEqual(decoded.marker, expected)
            XCTAssertEqual(decoded.title, "Perf Budget")
        }

        let malformed = try JSONDecoder().decode(
            CaptureDrawerSummary.self,
            from: Data(#"{"title":"Perf Budget","key":17,"created":"yes","marker":3}"#.utf8)
        )
        XCTAssertEqual(malformed.title, "Perf Budget")
        XCTAssertEqual(malformed.key, "Perf Budget")
        XCTAssertFalse(malformed.created)
        XCTAssertNil(malformed.marker)
    }

    func testGeneratedDrawerFixturesReachTaskAndPomodoroRowsWithoutChangingRows() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: fixtures.path)
            .filter { $0.hasPrefix("drawer-capture-") && $0.hasSuffix(".json") }
            .sorted()
        var annotatedLines: [CaptureBlockLine] = []
        var checkedAnnotations = 0

        for name in names {
            let capture = try success(Data(contentsOf: fixtures.appendingPathComponent(name)))
            for block in capture.taskBlocks {
                let presentation = CaptureTaskBlockPresentation(block: block, dryRun: true)
                XCTAssertEqual(
                    presentation.identity.blockID,
                    block.blockID,
                    "\(name) keeps block identity"
                )
                for source in block.lines where source.drawer != nil {
                    checkedAnnotations += 1
                    annotatedLines.append(source)
                    let row = try XCTUnwrap(
                        presentation.rows.first {
                            $0.content == source.text.trimmingCharacters(in: .whitespaces)
                        })
                    XCTAssertEqual(row.drawer, source.drawer, name)
                    XCTAssertEqual(row.change, source.change, name)
                    XCTAssertEqual(row.depth, source.depth, name)
                    XCTAssertEqual(row.tokens.map(\.text).joined(), row.content, name)
                    XCTAssertEqual(
                        row.content, source.text.trimmingCharacters(in: .whitespaces), name)
                }
            }
        }
        XCTAssertGreaterThan(checkedAnnotations, 0)

        let pomodoro = CapturePomodoroBlockPresentation(
            block: CapturePomodoroBlock(
                relativeTarget: "day.md",
                line: 1,
                name: "GTD",
                status: .running,
                lines: annotatedLines
            ),
            dryRun: true
        )
        let pomodoroRows = pomodoro.rows.filter { $0.drawer != nil }
        XCTAssertEqual(pomodoroRows.count, checkedAnnotations)
        for (row, source) in zip(pomodoroRows, annotatedLines) {
            XCTAssertEqual(row.drawer, source.drawer)
            XCTAssertEqual(row.change, source.change)
            XCTAssertEqual(row.content, source.text.trimmingCharacters(in: .whitespaces))
            XCTAssertEqual(row.tokens.map(\.text).joined(), row.content)
        }

        let legacy = try success(
            Data(contentsOf: fixtures.appendingPathComponent("drawer-capture-new.json"))
        )
        XCTAssertTrue(
            legacy.taskBlocks.flatMap(\.lines).contains {
                $0.drawer?.title == "FUTURE WORK" && $0.drawer?.marker == .legacyCaps
            }
        )
    }

    func testTransferAndMergeInDrawerLabelsPreserveVerbatimCase() throws {
        let transferData = try Data(
            contentsOf: fixtures.appendingPathComponent("capture-transfer-drawer-merge.json")
        )
        let transferObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: transferData) as? [String: Any]
        )
        let transferCapture = try success(
            try JSONSerialization.data(
                withJSONObject: replacingDrawer(
                    in: transferObject,
                    value: "Perf Budget"
                )))
        let transfer = try XCTUnwrap(CaptureTransferPresentation(capture: transferCapture))
        XCTAssertEqual(transfer.destination.containerLabel, "› Perf Budget")

        let mergeInData = try Data(
            contentsOf: fixtures.appendingPathComponent("capture-merge-in-complete-one.json")
        )
        let mergeInObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: mergeInData) as? [String: Any]
        )
        let mergeInCapture = try success(
            try JSONSerialization.data(
                withJSONObject: replacingDrawer(
                    in: mergeInObject,
                    value: "Perf Budget"
                )))
        let mergeIn = try XCTUnwrap(CaptureMergeInPresentation(capture: mergeInCapture))
        XCTAssertEqual(mergeIn.destination.containerLabel, "› Perf Budget")
    }

    func testDrawerHeaderBranchIsKeyedOnlyOnTheAnnotation() {
        let drawer = CaptureDrawerAnnotation(
            title: "Perf Budget", key: "PERF BUDGET", marker: .bold, empty: false)
        func row(
            drawer: CaptureDrawerAnnotation? = drawer,
            req: CaptureRequirementAnnotation? = nil,
            isRelationSuccessor: Bool = false,
            isKeepMoving: Bool = false,
            isUnblocked: Bool = false,
            change: CapturePomodoroBlockChange = .added
        ) -> CaptureBlockDiffRow {
            CaptureBlockDiffRow(
                content: "- **Perf Budget**",
                depth: 1,
                change: change,
                isHeadline: false,
                tokens: [],
                isUnblocked: isUnblocked,
                isKeepMoving: isKeepMoving,
                isRelationSuccessor: isRelationSuccessor,
                req: req,
                drawer: drawer
            )
        }

        XCTAssertTrue(row().showsDrawerHeader)
        // An unannotated row, including a bold ordinary note, never takes it.
        XCTAssertFalse(row(drawer: nil).showsDrawerHeader)
        // Badge rows keep their current precedence even when annotated.
        let req = CaptureRequirementAnnotation(depth: 1, state: .pending)
        XCTAssertFalse(row(req: req).showsDrawerHeader)
        XCTAssertFalse(row(isRelationSuccessor: true).showsDrawerHeader)
        XCTAssertFalse(row(isKeepMoving: true).showsDrawerHeader)
        XCTAssertFalse(row(isUnblocked: true).showsDrawerHeader)
        // A removed annotated row still takes the branch: the card strikes it.
        XCTAssertTrue(row(change: .removed).showsDrawerHeader)
        // Empty and unknown markers take the same conservative branch.
        XCTAssertTrue(
            row(drawer: CaptureDrawerAnnotation(
                title: "Drafts", key: "DRAFTS", marker: .bold, empty: true
            )).showsDrawerHeader
        )
        XCTAssertTrue(
            row(drawer: CaptureDrawerAnnotation(
                title: "Someday", key: "SOMEDAY", marker: .unknown, empty: false
            )).showsDrawerHeader
        )
    }

    private func replacingDrawer(in object: [String: Any], value: String) -> [String: Any] {
        var result = object
        guard var merges = result["merges"] as? [[String: Any]],
            !merges.isEmpty,
            var target = merges[0]["target"] as? [String: Any]
        else {
            return result
        }
        target["drawer"] = value
        merges[0]["target"] = target
        result["merges"] = merges
        return result
    }
}
