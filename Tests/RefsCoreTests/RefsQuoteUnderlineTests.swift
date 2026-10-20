import XCTest

@testable import RefsCore

final class RefsQuoteUnderlineTests: XCTestCase {
    func testPiecesOfAPlainQuoteStayPlain() {
        XCTAssertEqual(
            RefsQuoteUnderline.pieces("plain text"),
            [RefsQuotePiece(text: "plain text", role: .plain)]
        )
        assertJoinsBack("plain text")
    }

    func testPiecesOfAMidQuoteRun() {
        XCTAssertEqual(
            RefsQuoteUnderline.pieces("Say **this** now"),
            [
                RefsQuotePiece(text: "Say ", role: .plain),
                RefsQuotePiece(text: "this", role: .underlined),
                RefsQuotePiece(text: " now", role: .plain),
            ]
        )
        assertJoinsBack("Say **this** now")
    }

    func testPiecesStripLeadingAndTrailingSpacesOfAStrongRun() {
        XCTAssertEqual(
            RefsQuoteUnderline.pieces("Say **  this  ** now"),
            [
                RefsQuotePiece(text: "Say   ", role: .plain),
                RefsQuotePiece(text: "this", role: .underlined),
                RefsQuotePiece(text: "   now", role: .plain),
            ]
        )
        assertJoinsBack("Say **  this  ** now")
    }

    func testPiecesMarkMultiWordGaps() {
        XCTAssertEqual(
            RefsQuoteUnderline.pieces("**hello world**"),
            [
                RefsQuotePiece(text: "hello", role: .underlined),
                RefsQuotePiece(text: " ", role: .underlineGap),
                RefsQuotePiece(text: "world", role: .underlined),
            ]
        )
        assertJoinsBack("**hello world**")
    }

    func testPiecesTreatANewlineInsideARunAsPlain() {
        XCTAssertEqual(
            RefsQuoteUnderline.pieces("**hello\nworld**"),
            [
                RefsQuotePiece(text: "hello", role: .underlined),
                RefsQuotePiece(text: "\n", role: .plain),
                RefsQuotePiece(text: "world", role: .underlined),
            ]
        )
        XCTAssertEqual(
            RefsQuoteUnderline.pieces("**hello \n world**"),
            [
                RefsQuotePiece(text: "hello", role: .underlined),
                RefsQuotePiece(text: " \n ", role: .plain),
                RefsQuotePiece(text: "world", role: .underlined),
            ]
        )
        assertJoinsBack("**hello\nworld**")
        assertJoinsBack("**hello \n world**")
    }

    func testPiecesOfAWholeQuoteRun() {
        XCTAssertEqual(
            RefsQuoteUnderline.pieces("**whole quote**"),
            [
                RefsQuotePiece(text: "whole", role: .underlined),
                RefsQuotePiece(text: " ", role: .underlineGap),
                RefsQuotePiece(text: "quote", role: .underlined),
            ]
        )
        XCTAssertTrue(RefsQuoteUnderline.isWhollyUnderlined("**whole quote**"))
        assertJoinsBack("**whole quote**")
    }

    func testPiecesOfAdjacentRunsKeepThePlainGap() {
        XCTAssertEqual(
            RefsQuoteUnderline.pieces("**A** **B**"),
            [
                RefsQuotePiece(text: "A", role: .underlined),
                RefsQuotePiece(text: " ", role: .plain),
                RefsQuotePiece(text: "B", role: .underlined),
            ]
        )
        XCTAssertEqual(RefsQuoteUnderline.phrases("**A** **B**"), ["A", "B"])
        XCTAssertTrue(RefsQuoteUnderline.isWhollyUnderlined("**A** **B**"))
        assertJoinsBack("**A** **B**")
    }

    func testPiecesLeaveUnpairedMarkersLiteral() {
        XCTAssertEqual(
            RefsQuoteUnderline.pieces("hello **"),
            [RefsQuotePiece(text: "hello **", role: .plain)]
        )
        XCTAssertEqual(
            RefsQuoteUnderline.pieces("a ** b"),
            [RefsQuotePiece(text: "a ** b", role: .plain)]
        )
        XCTAssertEqual(RefsQuoteUnderline.pieces("****"), [])
        XCTAssertEqual(RefsQuoteUnderline.pieces(""), [])
        assertJoinsBack("hello **")
        assertJoinsBack("a ** b")
        assertJoinsBack("****")
        assertJoinsBack("")
    }

    func testJoinBackInvariantOnMixedQuotes() {
        let quotes = [
            "plain text",
            "Say **this** now",
            "**  padded  **",
            "before **one two** after",
            "**hello\nworld**",
            "**A** **B**",
            "hello **",
            "**whole quote**",
            "star * and _under_ and __wide__ and `code`",
        ]
        for quote in quotes {
            assertJoinsBack(quote)
        }
    }

    func testPhrasesAndWhollyUnderlined() {
        XCTAssertEqual(RefsQuoteUnderline.phrases("plain text"), [])
        XCTAssertFalse(RefsQuoteUnderline.isWhollyUnderlined("plain text"))
        XCTAssertEqual(
            RefsQuoteUnderline.phrases("Say **this** now"),
            ["this"]
        )
        XCTAssertFalse(RefsQuoteUnderline.isWhollyUnderlined("Say **this** now"))
        XCTAssertEqual(
            RefsQuoteUnderline.phrases("**hello world**"),
            ["hello world"]
        )
        XCTAssertEqual(
            RefsQuoteUnderline.phrases("**one** and **two**"),
            ["one", "two"]
        )
        XCTAssertFalse(
            RefsQuoteUnderline.isWhollyUnderlined("**one** and **two**")
        )
        XCTAssertTrue(RefsQuoteUnderline.isWhollyUnderlined("**  whole  **"))
        XCTAssertFalse(RefsQuoteUnderline.isWhollyUnderlined("**   **"))
        XCTAssertFalse(RefsQuoteUnderline.isWhollyUnderlined("hello **"))
    }

    func testBarsTrimEndGapsAndMergeFallbackSplits() {
        XCTAssertEqual(
            RefsQuoteUnderline.bars(in: [
                RefsQuoteLineRun(role: .underlineGap, minX: 0, maxX: 4),
                RefsQuoteLineRun(role: .underlined, minX: 4, maxX: 12),
                RefsQuoteLineRun(role: .underlineGap, minX: 12, maxX: 16),
            ]),
            [RefsUnderlineSpan(minX: 4, maxX: 12)]
        )
        XCTAssertEqual(
            RefsQuoteUnderline.bars(in: [
                RefsQuoteLineRun(role: .underlined, minX: 0, maxX: 10),
                RefsQuoteLineRun(role: .underlined, minX: 10, maxX: 20),
            ]),
            [RefsUnderlineSpan(minX: 0, maxX: 20)]
        )
        XCTAssertEqual(
            RefsQuoteUnderline.bars(in: [
                RefsQuoteLineRun(role: .underlined, minX: 0, maxX: 8),
                RefsQuoteLineRun(role: .underlineGap, minX: 8, maxX: 10),
                RefsQuoteLineRun(role: .underlined, minX: 10, maxX: 18),
            ]),
            [RefsUnderlineSpan(minX: 0, maxX: 18)]
        )
        XCTAssertEqual(
            RefsQuoteUnderline.bars(in: [
                RefsQuoteLineRun(role: .underlineGap, minX: 0, maxX: 10),
                RefsQuoteLineRun(role: .underlineGap, minX: 10, maxX: 16),
            ]),
            []
        )
        XCTAssertEqual(
            RefsQuoteUnderline.bars(in: [
                RefsQuoteLineRun(role: .underlined, minX: 0, maxX: 8),
                RefsQuoteLineRun(role: .plain, minX: 8, maxX: 12),
                RefsQuoteLineRun(role: .underlined, minX: 12, maxX: 20),
            ]),
            [
                RefsUnderlineSpan(minX: 0, maxX: 8),
                RefsUnderlineSpan(minX: 12, maxX: 20),
            ]
        )
        XCTAssertEqual(
            RefsQuoteUnderline.bars(in: [
                RefsQuoteLineRun(role: .plain, minX: 0, maxX: 10),
            ]),
            []
        )
    }

    func testBarMinimumThicknessIncreaseContrastSnappingAndZeroWidth() throws {
        XCTAssertNil(
            RefsQuoteUnderline.bar(
                minX: 10,
                maxX: 10,
                baseline: 20,
                ascent: 10,
                descent: 2,
                increasedContrast: false,
                displayScale: 2
            )
        )
        XCTAssertNil(
            RefsQuoteUnderline.bar(
                minX: 12,
                maxX: 8,
                baseline: 20,
                ascent: 10,
                descent: 2,
                increasedContrast: false,
                displayScale: 2
            )
        )

        let tiny = try XCTUnwrap(
            RefsQuoteUnderline.bar(
                minX: 0,
                maxX: 40,
                baseline: 20,
                ascent: 0.2,
                descent: 0.2,
                increasedContrast: false,
                displayScale: 2
            )
        )
        XCTAssertEqual(tiny.height, 1.5)
        XCTAssertEqual(tiny.cornerRadius, 0.75)
        XCTAssertEqual(tiny.x, 0)
        XCTAssertEqual(tiny.width, 40)

        let contrast = try XCTUnwrap(
            RefsQuoteUnderline.bar(
                minX: 0,
                maxX: 40,
                baseline: 20,
                ascent: 0.2,
                descent: 0.2,
                increasedContrast: true,
                displayScale: 2
            )
        )
        XCTAssertEqual(contrast.height, 2.0)
        XCTAssertEqual(contrast.cornerRadius, 1.0)

        let unsnappedY = barYUnsnapped(baseline: 20.6, ascent: 10, descent: 1.9)
        let scale1 = try XCTUnwrap(
            RefsQuoteUnderline.bar(
                minX: 0,
                maxX: 40,
                baseline: 20.6,
                ascent: 10,
                descent: 1.9,
                increasedContrast: false,
                displayScale: 1
            )
        )
        let scale2 = try XCTUnwrap(
            RefsQuoteUnderline.bar(
                minX: 0,
                maxX: 40,
                baseline: 20.6,
                ascent: 10,
                descent: 1.9,
                increasedContrast: false,
                displayScale: 2
            )
        )
        XCTAssertEqual(scale1.y, snap(unsnappedY, scale: 1))
        XCTAssertEqual(scale2.y, snap(unsnappedY, scale: 2))
        XCTAssertEqual(scale1.height, snap(expectedThickness(), scale: 1))
        XCTAssertEqual(scale2.height, snap(expectedThickness(), scale: 2))
        XCTAssertNotEqual(scale1.y, scale2.y)
        XCTAssertNotEqual(scale1.height, scale2.height)
    }

    private func expectedThickness() -> Double {
        let em = (10.0 + 1.9) / RefsQuoteUnderline.emFromLineMetrics
        return max(
            RefsQuoteUnderline.thicknessEm * em,
            RefsQuoteUnderline.minThickness
        )
    }

    private func barYUnsnapped(
        baseline: Double,
        ascent: Double,
        descent: Double
    ) -> Double {
        let em = (ascent + descent) / RefsQuoteUnderline.emFromLineMetrics
        return baseline + RefsQuoteUnderline.topOffsetEm * em
    }

    private func snap(_ value: Double, scale: Double) -> Double {
        (value * scale).rounded() / scale
    }

    private func assertJoinsBack(
        _ quote: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let joined = RefsQuoteUnderline.pieces(quote).map(\.text).joined()
        XCTAssertEqual(
            joined,
            RefsQuoteEmphasis.plainText(quote),
            file: file,
            line: line
        )
    }
}
