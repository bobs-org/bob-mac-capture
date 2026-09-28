import XCTest

@testable import CaptureCore

final class ActiveTaskDisplayTextTests: XCTestCase {
    func testCodeSpanHidesBackticks() {
        let parsed = ActiveTaskDisplayText(parsing: "Fix `deep` bug")
        XCTAssertEqual(parsed.text, "Fix deep bug")
        XCTAssertEqual(
            parsed.segments,
            [
                ActiveTaskDisplaySegment(kind: .plain, range: 0..<4),
                ActiveTaskDisplaySegment(kind: .code, range: 4..<8),
                ActiveTaskDisplaySegment(kind: .plain, range: 8..<12),
            ]
        )
    }

    func testAliasedWikilinkShowsAlias() {
        let parsed = ActiveTaskDisplayText(parsing: "from [[ref/chat/ux|UX chat]]")
        XCTAssertEqual(parsed.text, "from UX chat")
        XCTAssertEqual(
            parsed.segments,
            [
                ActiveTaskDisplaySegment(kind: .plain, range: 0..<5),
                ActiveTaskDisplaySegment(kind: .link, range: 5..<12),
            ]
        )
    }

    func testUnaliasedWikilinkShowsTarget() {
        let parsed = ActiveTaskDisplayText(parsing: "Archive [[ref/chat/old]] items")
        XCTAssertEqual(parsed.text, "Archive ref/chat/old items")
        XCTAssertEqual(
            parsed.segments,
            [
                ActiveTaskDisplaySegment(kind: .plain, range: 0..<8),
                ActiveTaskDisplaySegment(kind: .link, range: 8..<20),
                ActiveTaskDisplaySegment(kind: .plain, range: 20..<26),
            ]
        )
    }

    func testWikilinkAliasUsesLastPipe() {
        let parsed = ActiveTaskDisplayText(parsing: "[[a|b|tail]]")
        XCTAssertEqual(parsed.text, "tail")
        XCTAssertEqual(
            parsed.segments,
            [ActiveTaskDisplaySegment(kind: .link, range: 0..<4)]
        )
    }

    func testMixedLineParsesBothKinds() {
        let parsed = ActiveTaskDisplayText(parsing: "Fix `deep` bug from [[ref/chat/ux|UX chat]]")
        XCTAssertEqual(parsed.text, "Fix deep bug from UX chat")
        XCTAssertEqual(
            parsed.segments.map { $0.kind },
            [.plain, .code, .plain, .link]
        )
        assertTilesExactly(parsed)
    }

    func testUnmatchedBacktickStaysLiteral() {
        let parsed = ActiveTaskDisplayText(parsing: "fix `oops and `ok`")
        XCTAssertEqual(parsed.text, "fix `oops and ok")
        XCTAssertEqual(
            parsed.segments.map { $0.kind },
            [.plain, .code]
        )
        assertTilesExactly(parsed)
    }

    func testEmptyCodePairStaysLiteral() {
        let parsed = ActiveTaskDisplayText(parsing: "a `` b")
        XCTAssertEqual(parsed.text, "a `` b")
        XCTAssertEqual(
            parsed.segments,
            [ActiveTaskDisplaySegment(kind: .plain, range: 0..<6)]
        )
    }

    func testUnmatchedWikilinkStaysLiteral() {
        let parsed = ActiveTaskDisplayText(parsing: "see [[ref/chat/old")
        XCTAssertEqual(parsed.text, "see [[ref/chat/old")
        XCTAssertEqual(
            parsed.segments,
            [ActiveTaskDisplaySegment(kind: .plain, range: 0..<18)]
        )
        assertTilesExactly(parsed)
    }

    func testFirstDelimiterWins() {
        let codeFirst = ActiveTaskDisplayText(parsing: "`[[x]]`")
        XCTAssertEqual(codeFirst.text, "[[x]]")
        XCTAssertEqual(
            codeFirst.segments,
            [ActiveTaskDisplaySegment(kind: .code, range: 0..<5)]
        )
        let linkFirst = ActiveTaskDisplayText(parsing: "[[a `b` c]]")
        XCTAssertEqual(linkFirst.text, "a `b` c")
        XCTAssertEqual(
            linkFirst.segments,
            [ActiveTaskDisplaySegment(kind: .link, range: 0..<7)]
        )
    }

    func testCurlyQuotesAndBangStayPlain() {
        let parsed = ActiveTaskDisplayText(parsing: "Add “card blocks”!")
        XCTAssertEqual(parsed.text, "Add “card blocks”!")
        XCTAssertEqual(
            parsed.segments,
            [ActiveTaskDisplaySegment(kind: .plain, range: 0..<18)]
        )
    }

    private func assertTilesExactly(
        _ parsed: ActiveTaskDisplayText,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var cursor = 0
        for segment in parsed.segments {
            XCTAssertEqual(segment.range.lowerBound, cursor, file: file, line: line)
            cursor = segment.range.upperBound
        }
        XCTAssertEqual(cursor, parsed.text.count, file: file, line: line)
    }
}
