import XCTest

@testable import CaptureCore

final class CaptureAgendaInlineTextTests: XCTestCase {
    private func kindList(
        _ parsed: CaptureAgendaInlineText
    ) -> [CaptureAgendaInlineSegment.Kind] {
        parsed.segments.map(\.kind)
    }

    private func assertTilesExactly(
        _ parsed: CaptureAgendaInlineText,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var cursor = parsed.text.startIndex
        for segment in parsed.segments {
            let start = parsed.text.startIndex
            let lower = parsed.text.index(start, offsetBy: segment.range.lowerBound)
            let upper = parsed.text.index(start, offsetBy: segment.range.upperBound)
            XCTAssertEqual(lower, cursor, file: file, line: line)
            cursor = upper
        }
        XCTAssertEqual(cursor, parsed.text.endIndex, file: file, line: line)
    }

    // MARK: - Table: one input, one text, one kind sequence

    func testInlineTable() {
        let cases: [(source: String, text: String, kinds: [CaptureAgendaInlineSegment.Kind])] = [
            ("plain words", "plain words", [.plain]),
            ("Fix `deep` bug", "Fix deep bug", [.plain, .code, .plain]),
            ("from [[ref/chat/ux|UX chat]]", "from UX chat", [.plain, .link]),
            ("**strong** words", "strong words", [.strong, .plain]),
            ("a *soft* word", "a soft word", [.plain, .emphasis, .plain]),
            ("a _soft_ word", "a soft word", [.plain, .emphasis, .plain]),
            ("due [due:: 2026-08-28]", "due [due:: 2026-08-28]", [.plain, .field]),
            ("read #blog post", "read #blog post", [.plain, .tag, .plain]),
            ("Title ^deep-fix", "Title", [.plain]),
            ("**bold `code` done**", "bold `code` done", [.strong]),
            ("`code **not** strong`", "code **not** strong", [.code]),
            ("[[a|*x*]]", "*x*", [.link]),
        ]
        for (source, text, kinds) in cases {
            let parsed = CaptureAgendaInlineText(parsing: source)
            XCTAssertEqual(parsed.text, text, "source: \(source)")
            XCTAssertEqual(kindList(parsed), kinds, "source: \(source)")
            assertTilesExactly(parsed)
        }
    }

    // MARK: - Unmatched delimiters stay literal

    func testUnmatchedDelimitersStayLiteral() {
        let cases = [
            "a `lone backtick",
            "an empty `` pair",
            "unclosed [[link",
            "**unclosed strong",
            "*unclosed emphasis",
            "_unclosed emphasis",
            "[no field here]",
            "a bare # hashtag",
            "a trailing hash #",
            "a#b",
            "snake_case stays",
            "2 ** 2 is not strong",
        ]
        for source in cases {
            let parsed = CaptureAgendaInlineText(parsing: source)
            XCTAssertEqual(parsed.text, source, "source: \(source)")
            XCTAssertEqual(kindList(parsed), [.plain], "source: \(source)")
            assertTilesExactly(parsed)
        }
    }

    // MARK: - Kind details

    func testStrongNeedsNonSpaceInside() {
        let parsed = CaptureAgendaInlineText(parsing: "** not** strong")
        XCTAssertEqual(parsed.text, "** not** strong")
        XCTAssertEqual(kindList(parsed), [.plain])
    }

    func testSingleStarNextToDoubleStarStaysLiteral() {
        let parsed = CaptureAgendaInlineText(parsing: "a *** b")
        XCTAssertEqual(parsed.text, "a *** b")
        XCTAssertEqual(kindList(parsed), [.plain])
    }

    func testFieldKeepsBrackets() {
        let parsed = CaptureAgendaInlineText(parsing: "x [k:: v] y")
        XCTAssertEqual(parsed.text, "x [k:: v] y")
        XCTAssertEqual(parsed.segments.count, 3)
        XCTAssertEqual(parsed.segments[1].kind, .field)
        let origin = parsed.text.startIndex
        let bounds = parsed.segments[1].range
        let start = parsed.text.index(origin, offsetBy: bounds.lowerBound)
        let end = parsed.text.index(origin, offsetBy: bounds.upperBound)
        XCTAssertEqual(String(parsed.text[start..<end]), "[k:: v]")
    }

    func testTagStopsAtBoundary() {
        let parsed = CaptureAgendaInlineText(parsing: "#blog, and #gtd/pre")
        XCTAssertEqual(parsed.text, "#blog, and #gtd/pre")
        XCTAssertEqual(kindList(parsed), [.tag, .plain, .tag])
    }

    func testOnlyTrailingBlockIDIsHidden() {
        let parsed = CaptureAgendaInlineText(parsing: "^a ^b")
        XCTAssertEqual(parsed.text, "^a")
        let only = CaptureAgendaInlineText(parsing: "^alone")
        XCTAssertEqual(only.text, "^alone")
    }

    func testCodeAndLinkMatchTaskDisplayText() {
        let sources = [
            "Fix `deep` bug",
            "from [[ref/chat/ux|UX chat]]",
            "Archive [[ref/chat/old]] items",
            "[[a|b|tail]]",
            "Fix `deep` bug from [[ref/chat/ux|UX chat]]",
        ]
        for source in sources {
            let inline = CaptureAgendaInlineText(parsing: source)
            let classic = TaskDisplayText(parsing: source)
            XCTAssertEqual(inline.text, classic.text, "source: \(source)")
            XCTAssertEqual(
                inline.segments.map(\.range),
                classic.segments.map(\.range),
                "source: \(source)"
            )
            let mapped = classic.segments.map { segment -> CaptureAgendaInlineSegment.Kind in
                switch segment.kind {
                case .plain:
                    return .plain
                case .code:
                    return .code
                case .link:
                    return .link
                }
            }
            XCTAssertEqual(kindList(inline), mapped, "source: \(source)")
        }
    }

    func testSegmentsTileOnMixedInput() {
        let parsed = CaptureAgendaInlineText(
            parsing: "Fix **deep `wiring` bug** in [[tasks|tasks file]] [k:: v] #gtd ^x1"
        )
        XCTAssertEqual(parsed.text, "Fix deep `wiring` bug in tasks file [k:: v] #gtd")
        XCTAssertEqual(
            kindList(parsed),
            [.plain, .strong, .plain, .link, .plain, .field, .plain, .tag]
        )
        assertTilesExactly(parsed)
    }
}
