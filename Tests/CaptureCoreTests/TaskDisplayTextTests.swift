import XCTest

@testable import CaptureCore

final class TaskDisplayTextTests: XCTestCase {
    func testCodeSpanHidesBackticks() {
        let parsed = TaskDisplayText(parsing: "Fix `deep` bug")
        XCTAssertEqual(parsed.text, "Fix deep bug")
        XCTAssertEqual(
            parsed.segments,
            [
                TaskDisplaySegment(kind: .plain, range: 0..<4),
                TaskDisplaySegment(kind: .code, range: 4..<8),
                TaskDisplaySegment(kind: .plain, range: 8..<12),
            ]
        )
    }

    func testAliasedWikilinkShowsAlias() {
        let parsed = TaskDisplayText(parsing: "from [[ref/chat/ux|UX chat]]")
        XCTAssertEqual(parsed.text, "from UX chat")
        XCTAssertEqual(
            parsed.segments,
            [
                TaskDisplaySegment(kind: .plain, range: 0..<5),
                TaskDisplaySegment(kind: .link, range: 5..<12),
            ]
        )
    }

    func testUnaliasedWikilinkShowsTarget() {
        let parsed = TaskDisplayText(parsing: "Archive [[ref/chat/old]] items")
        XCTAssertEqual(parsed.text, "Archive ref/chat/old items")
        XCTAssertEqual(
            parsed.segments,
            [
                TaskDisplaySegment(kind: .plain, range: 0..<8),
                TaskDisplaySegment(kind: .link, range: 8..<20),
                TaskDisplaySegment(kind: .plain, range: 20..<26),
            ]
        )
    }

    func testWikilinkAliasUsesLastPipe() {
        let parsed = TaskDisplayText(parsing: "[[a|b|tail]]")
        XCTAssertEqual(parsed.text, "tail")
        XCTAssertEqual(
            parsed.segments,
            [TaskDisplaySegment(kind: .link, range: 0..<4)]
        )
    }

    func testMixedLineParsesBothKinds() {
        let parsed = TaskDisplayText(parsing: "Fix `deep` bug from [[ref/chat/ux|UX chat]]")
        XCTAssertEqual(parsed.text, "Fix deep bug from UX chat")
        XCTAssertEqual(
            parsed.segments.map { $0.kind },
            [.plain, .code, .plain, .link]
        )
        assertTilesExactly(parsed)
    }

    func testNextBacktickClosesCodeSpan() {
        let parsed = TaskDisplayText(parsing: "fix `oops and `ok``")
        XCTAssertEqual(parsed.text, "fix oops and ok``")
        XCTAssertEqual(
            parsed.segments,
            [
                TaskDisplaySegment(kind: .plain, range: 0..<4),
                TaskDisplaySegment(kind: .code, range: 4..<13),
                TaskDisplaySegment(kind: .plain, range: 13..<17),
            ]
        )
        assertTilesExactly(parsed)
    }

    func testTrulyUnmatchedSingleBacktickStaysLiteral() {
        let parsed = TaskDisplayText(parsing: "fix `oops")
        XCTAssertEqual(parsed.text, "fix `oops")
        XCTAssertEqual(
            parsed.segments,
            [TaskDisplaySegment(kind: .plain, range: 0..<9)]
        )
        assertTilesExactly(parsed)
    }

    func testEmptyCodePairStaysLiteral() {
        let parsed = TaskDisplayText(parsing: "a `` b")
        XCTAssertEqual(parsed.text, "a `` b")
        XCTAssertEqual(
            parsed.segments,
            [TaskDisplaySegment(kind: .plain, range: 0..<6)]
        )
    }

    func testUnmatchedWikilinkStaysLiteral() {
        let parsed = TaskDisplayText(parsing: "see [[ref/chat/old")
        XCTAssertEqual(parsed.text, "see [[ref/chat/old")
        XCTAssertEqual(
            parsed.segments,
            [TaskDisplaySegment(kind: .plain, range: 0..<18)]
        )
        assertTilesExactly(parsed)
    }

    func testFirstDelimiterWins() {
        let codeFirst = TaskDisplayText(parsing: "`[[x]]`")
        XCTAssertEqual(codeFirst.text, "[[x]]")
        XCTAssertEqual(
            codeFirst.segments,
            [TaskDisplaySegment(kind: .code, range: 0..<5)]
        )
        let linkFirst = TaskDisplayText(parsing: "[[a `b` c]]")
        XCTAssertEqual(linkFirst.text, "a `b` c")
        XCTAssertEqual(
            linkFirst.segments,
            [TaskDisplaySegment(kind: .link, range: 0..<7)]
        )
    }

    func testCurlyQuotesAndBangStayPlain() {
        let parsed = TaskDisplayText(parsing: "Add “card blocks”!")
        XCTAssertEqual(parsed.text, "Add “card blocks”!")
        XCTAssertEqual(
            parsed.segments,
            [TaskDisplaySegment(kind: .plain, range: 0..<18)]
        )
    }

    private func assertTilesExactly(
        _ parsed: TaskDisplayText,
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
