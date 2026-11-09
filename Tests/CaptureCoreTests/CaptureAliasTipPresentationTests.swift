import Foundation
import XCTest

@testable import CaptureCore

final class CaptureAliasTipPresentationTests: XCTestCase {
    private func tip(keys: [String] = ["."], sigil: String = "@", where phrase: String? = nil)
        -> CaptureSigilAliasTip
    {
        CaptureSigilAliasTip(
            id: "route_after_text",
            sigil: sigil,
            keys: keys,
            range: CaptureRange(start: 9, end: 10),
            positionPhrase: phrase
        )
    }

    func testLeadAndHelpText() {
        let presentation = CaptureAliasTipPresentation(tip: tip())
        XCTAssertEqual(presentation.leadText, "Next time")
        XCTAssertEqual(presentation.helpText, "Typing tips can be turned off in Settings")
    }

    func testAccessibilitySentenceWithPhrase() {
        let presentation = CaptureAliasTipPresentation(
            tip: tip(where: "after a word")
        )
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Tip for next time: after a word, period types at sign."
        )
    }

    func testAccessibilitySentenceWithoutPhrase() {
        let presentation = CaptureAliasTipPresentation(tip: tip())
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Tip for next time: period types at sign."
        )
    }

    func testKeyShowsFirstKeyOnly() {
        let presentation = CaptureAliasTipPresentation(
            tip: tip(keys: ["/", "\\"], sigil: "#", where: "after a word")
        )
        XCTAssertEqual(presentation.key, "/")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Tip for next time: after a word, slash types hash."
        )
    }

    func testGlyphNamesCoverEveryWireCharacter() {
        let expected: [String: String] = [
            ".": "period",
            ";": "semicolon",
            ",": "comma",
            "/": "slash",
            "\\": "backslash",
            "=": "equals sign",
            "@": "at sign",
            "#": "hash",
            "^": "caret",
            ":": "colon",
            "+": "plus",
            "~": "tilde",
            "&": "ampersand",
            "*": "asterisk",
        ]
        for (glyph, name) in expected {
            XCTAssertEqual(CaptureAliasTipPresentation.glyphName(for: glyph), name, glyph)
        }
    }

    func testUnknownGlyphFallsBackToText() {
        XCTAssertEqual(CaptureAliasTipPresentation.glyphName(for: "?"), "?")
    }
}
