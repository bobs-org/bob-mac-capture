import XCTest

@testable import CaptureCore

final class CaptureRequirementMarkTests: XCTestCase {
    func testAnnotationsDecodeOnBothLineKindsAndUnknownStateIsPending() throws {
        for state in CaptureRequirementState.allCases {
            let json = """
                {"text":"[ ] Scope", "req":{"depth":3,"state":"\(state.rawValue)"}}
                """
            let data = Data(json.utf8)
            let block = try JSONDecoder().decode(CaptureBlockLine.self, from: data)
            let agenda = try JSONDecoder().decode(CaptureAgendaLine.self, from: data)
            XCTAssertEqual(block.req, CaptureRequirementAnnotation(depth: 3, state: state))
            XCTAssertEqual(agenda.req, block.req)
            let roundTrip = try JSONDecoder().decode(
                CaptureBlockLine.self, from: JSONEncoder().encode(block))
            XCTAssertEqual(roundTrip, block)
        }
        let future = Data(#"{"req":{"depth":2,"state":"future-state"}}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(CaptureBlockLine.self, from: future).req?.state, .pending)
        XCTAssertEqual(
            try JSONDecoder().decode(CaptureAgendaLine.self, from: future).req?.state, .pending)
    }

    func testMissingAndMalformedAnnotationsPreserveTheLine() throws {
        let fragments = [
            "", #", "req":null"#, #", "req":false"#, #", "req":"pending""#,
            #", "req":{}"#, #", "req":{"depth":1}"#,
            #", "req":{"depth":"1","state":"met"}"#,
            #", "req":{"depth":0,"state":"met"}"#,
            #", "req":{"depth":1,"state":false}"#,
        ]
        for fragment in fragments {
            let data = Data("{\"text\":\"[ ] Ordinary checkbox\"\(fragment)}".utf8)
            let block = try JSONDecoder().decode(CaptureBlockLine.self, from: data)
            let agenda = try JSONDecoder().decode(CaptureAgendaLine.self, from: data)
            XCTAssertNil(block.req, fragment)
            XCTAssertNil(agenda.req, fragment)
            XCTAssertEqual(block.text, "[ ] Ordinary checkbox")
            XCTAssertEqual(agenda.text, block.text)
        }
    }

    func testPreviewKeepsVerbatimTokensAndUsesOnlyBobAnnotations() throws {
        for change in [CapturePomodoroBlockChange.added, .changed, .removed, .unchanged] {
            for depth in 1...3 {
                let req = CaptureRequirementAnnotation(depth: depth, state: .met)
                let lines = [
                    CaptureBlockLine(text: "- [x] #task Ship"),
                    CaptureBlockLine(
                        text: "\t- [ ] Scope with [[target|a link]]", depth: depth,
                        change: change, before: "\t- [ ] Old scope", req: req),
                    CaptureBlockLine(text: "\t- [ ] Ordinary checkbox", depth: 1),
                    CaptureBlockLine(text: "\t- **Notes**", depth: 1),
                ]
                let block = CaptureTaskBlock(
                    relativeTarget: "dev.md", route: "dev", line: 1, text: "Ship", lines: lines)
                let rows = CaptureTaskBlockPresentation(block: block, dryRun: true).rows
                XCTAssertEqual(rows[1].req, req)
                XCTAssertEqual(rows[1].change, change)
                let checkbox = try XCTUnwrap(rows[1].requirementCheckboxIndex)
                XCTAssertEqual(rows[1].tokens[checkbox].text, "[ ]")
                XCTAssertEqual(rows[1].beforeContent, "- [ ] Old scope")
                XCTAssertNil(rows[0].requirementCheckboxIndex)
                XCTAssertNil(rows[2].requirementCheckboxIndex)
                XCTAssertNil(rows[3].requirementCheckboxIndex)
                for row in rows {
                    XCTAssertEqual(row.tokens.map(\.text).joined(), row.content)
                }
            }
        }
    }

    func testSectionPreviewPropagatesRequirements() throws {
        let data = Data(
            #"{"heading":"Tasks","lines":[{"text":"  - [>] Moved","depth":2,"req":{"depth":1,"state":"carried"}}]}"#
                .utf8)
        let block = try JSONDecoder().decode(CaptureSectionBlock.self, from: data)
        let row = try XCTUnwrap(
            CaptureSectionBlockPresentation(block: block, dryRun: true).rows.first)
        XCTAssertEqual(row.req?.state, .carried)
        XCTAssertNotNil(row.requirementCheckboxIndex)
        XCTAssertEqual(row.tokens.map(\.text).joined(), "- [>] Moved")
    }

    func testAgendaStripsOnlyAnnotatedCheckboxesAndNamesStateAndDepth() throws {
        for state in CaptureRequirementState.allCases {
            let req = CaptureRequirementAnnotation(depth: 3, state: state)
            let rows = CaptureAgendaPresentation.childRowsForLines([
                CaptureAgendaLine(text: "[ ] Scope", depth: 4, req: req),
                CaptureAgendaLine(text: "[ ] Ordinary checkbox", depth: 4),
                CaptureAgendaLine(text: "Unexpected prefix", depth: 4, req: req),
            ])
            XCTAssertEqual(rows[0].text, "Scope")
            XCTAssertEqual(rows[0].depth, 4)
            XCTAssertEqual(rows[0].req, req)
            XCTAssertEqual(rows[0].key.req, req)
            XCTAssertEqual(
                rows[0].accessibilityLabel,
                "Requirement · \(state.rawValue.capitalized) · level 3, Scope")
            XCTAssertEqual(rows[1].text, "[ ] Ordinary checkbox")
            XCTAssertNil(rows[1].req)
            XCTAssertEqual(rows[2].text, "Unexpected prefix")
        }
        let annotation = CaptureRequirementAnnotation(depth: 1, state: .pending)
        for symbol in [" ", "x", "X", "-", ">", "?"] {
            XCTAssertEqual(annotation.agendaText("[\(symbol)] Scope"), "Scope")
        }
    }

    func testStagedMarksAndStateTreatments() {
        XCTAssertEqual(CaptureRequirementState.staged(nil), .pending)
        XCTAssertEqual(CaptureRequirementState.staged(.drop(reason: "Scope changed")), .dropped)
        XCTAssertEqual(CaptureRequirementState.staged(.carry), .carried)
        XCTAssertEqual(CaptureRequirementState.staged(.carryPulled), .carried)
        XCTAssertEqual(CaptureRequirementState.pending.markOpacity, 0.9)
        XCTAssertEqual(CaptureRequirementState.met.markOpacity, 0.62)
        XCTAssertEqual(CaptureRequirementState.moot.markOpacity, 0.42)
        XCTAssertEqual(CaptureRequirementState.dropped.markOpacity, 0.55)
        XCTAssertEqual(CaptureRequirementState.carried.markOpacity, 0.9)
        XCTAssertEqual(CaptureRequirementState.excluded.markOpacity, 0.42)
        XCTAssertTrue(CaptureRequirementState.met.textIsMuted)
        XCTAssertFalse(CaptureRequirementState.carried.textIsMuted)
    }
}
