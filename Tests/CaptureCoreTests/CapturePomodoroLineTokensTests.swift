import XCTest

@testable import CaptureCore

/// Tokenizer coverage for Pomodoro block rows: the concatenation invariant
/// over every line of every `pomodoro-*-blocks.json` fixture, plus targeted
/// headline, link, code, and fallback cases. Fixture provenance is
/// documented on `CapturePomodoroBlockPresentationTests`.
final class CapturePomodoroLineTokensTests: XCTestCase {
    private typealias Token = CapturePomodoroLineToken
    private typealias Role = CapturePomodoroLineTokenRole

    private func fixtureBlocks(_ name: String) throws -> [CapturePomodoroBlock] {
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
            throw LineTokensFixtureError.expectedSuccess
        }
        return success.pomodoroBlocks
    }

    private static func stripped(_ value: String) -> String {
        var result = value
        while result.hasPrefix(" ") || result.hasPrefix("\t") {
            result.removeFirst()
        }
        return result
    }

    private func checkInvariant(
        _ content: String,
        isHeadline: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Token] {
        let tokens = CapturePomodoroLineTokens.tokenize(content, isHeadline: isHeadline)
        XCTAssertEqual(
            tokens.map(\.text).joined(),
            content,
            "tokens must preserve every byte",
            file: file,
            line: line
        )
        return tokens
    }

    private func roles(_ tokens: [Token]) -> [Role] {
        tokens.map(\.role)
    }

    // MARK: - Invariant over real fixtures

    func testConcatenationInvariantOverEveryFixtureLine() throws {
        let fixtures = [
            "pomodoro-adjust-blocks.json",
            "pomodoro-shift-blocks.json",
            "pomodoro-start-blocks.json",
            "pomodoro-start-named-blocks-created.json",
            "pomodoro-close-blocks.json",
            "pomodoro-chain-blocks.json",
        ]
        var lineCount = 0
        for fixture in fixtures {
            for block in try fixtureBlocks(fixture) {
                for line in block.lines {
                    let content = Self.stripped(line.text)
                    let tokens = checkInvariant(
                        content,
                        isHeadline: line.depth == 0 && !content.isEmpty
                    )
                    XCTAssertFalse(tokens.isEmpty, "\(fixture): \(content)")
                    lineCount += 1
                }
            }
        }
        XCTAssertGreaterThan(lineCount, 20)
    }

    // MARK: - Headlines

    func testRunningHeadlineTokenizes() throws {
        let tokens = checkInvariant(
            "- [ ] (**0620-0735** [t:: 75m]) — CLEANUP",
            isHeadline: true
        )

        XCTAssertEqual(
            tokens.map { ($0.text, $0.role) }.map { "\($0.0)|\($0.1)" },
            [
                "-|syntax", " |text", "[ ]|checkbox(\" \")", " |text",
                "(|syntax", "**|syntax", "0620-0735|timeRange",
                "**|syntax", " |text", "[t:: 75m]|field",
                ")|syntax", " — |text", "CLEANUP|name",
            ]
        )
        XCTAssertTrue(tokens.allSatisfy { !$0.struck })
    }

    func testPlaceholderHeadlineTokenizes() throws {
        let tokens = checkInvariant("- [ ] () — GTD", isHeadline: true)

        XCTAssertEqual(
            roles(tokens),
            [.syntax, .text, .checkbox(" "), .text, .syntax, .syntax, .text, .name]
        )
        XCTAssertEqual(tokens.last?.text, "GTD")
    }

    func testCompletedHeadlineTokenizesCheckboxSymbol() throws {
        let tokens = checkInvariant(
            "- [x] (**0920-0940** [t:: 20m]) — CAPTURE",
            isHeadline: true
        )

        XCTAssertEqual(tokens[2].role, .checkbox("x"))
        XCTAssertEqual(tokens.last?.role, .name)
        XCTAssertEqual(tokens.last?.text, "CAPTURE")
    }

    func testLegacyHeadlineFallsBackToTextAfterCheckbox() throws {
        let tokens = checkInvariant("- [ ] 0620 CLEANUP", isHeadline: true)

        XCTAssertEqual(
            roles(tokens),
            [.syntax, .text, .checkbox(" "), .text]
        )
        XCTAssertEqual(tokens.last?.text, " 0620 CLEANUP")
    }

    func testUnrecognizedHeadlineTailFallsBackToText() throws {
        let tokens = checkInvariant("- [ ] () extra", isHeadline: true)

        XCTAssertEqual(tokens.last?.role, .text)
        XCTAssertEqual(tokens.last?.text, " extra")
    }

    func testNonListHeadlineStaysPlainText() throws {
        let tokens = checkInvariant("just prose", isHeadline: true)

        XCTAssertEqual(roles(tokens), [.text])
        XCTAssertEqual(tokens.first?.text, "just prose")
    }

    // MARK: - Links

    func testPlainTaskLinkTokenizes() throws {
        let tokens = checkInvariant("- [[sase#^re-launch-failed]]", isHeadline: false)

        XCTAssertEqual(
            roles(tokens),
            [.text, .wikilinkDelimiter, .wikilinkTarget, .wikilinkBlock, .wikilinkDelimiter]
        )
        XCTAssertEqual(tokens[0].text, "- ")
        XCTAssertEqual(tokens[2].text, "sase")
        XCTAssertEqual(tokens[3].text, "#^re-launch-failed")
    }

    func testTomatoLinkKeepsEmojiAsText() throws {
        let tokens = checkInvariant("- 🍅 [[bob#^capture-stop]]", isHeadline: false)

        XCTAssertEqual(tokens[0].role, .text)
        XCTAssertEqual(tokens[0].text, "- 🍅 ")
        XCTAssertEqual(tokens[3].text, "#^capture-stop")
        XCTAssertEqual(tokens[3].role, .wikilinkBlock)
    }

    func testDeferredSuffixTokenizesAsSyntax() throws {
        let tokens = checkInvariant("- [[bob#^web-capture]]#", isHeadline: false)

        XCTAssertEqual(tokens.last?.role, .syntax)
        XCTAssertEqual(tokens.last?.text, "#")
    }

    func testStruckLinkMarksInnerTokens() throws {
        let tokens = checkInvariant("- ~~[[sase#^axe-restart]]~~", isHeadline: false)

        XCTAssertEqual(
            roles(tokens),
            [.text, .syntax, .wikilinkDelimiter, .wikilinkTarget,
             .wikilinkBlock, .wikilinkDelimiter, .syntax]
        )
        // Delimiters stay unstruck; only the link content is struck.
        XCTAssertFalse(tokens[1].struck)
        XCTAssertFalse(tokens[2].struck)
        XCTAssertTrue(tokens[3].struck)
        XCTAssertTrue(tokens[4].struck)
        XCTAssertFalse(tokens[5].struck)
        XCTAssertFalse(tokens[6].struck)
    }

    func testEmbedLinkKeepsBangInDelimiter() throws {
        let tokens = checkInvariant("- ![[bob#^capture-stop]]", isHeadline: false)

        XCTAssertEqual(tokens[1].role, .wikilinkDelimiter)
        XCTAssertEqual(tokens[1].text, "![[")
    }

    func testDroppedLinkMarksTildeAsSyntax() throws {
        let tokens = checkInvariant("- ~[[bob#^gone]]", isHeadline: false)

        XCTAssertEqual(tokens[1].role, .syntax)
        XCTAssertEqual(tokens[1].text, "~")
        XCTAssertEqual(tokens[2].role, .wikilinkDelimiter)
    }

    func testBareBlockLinkWithoutTarget() throws {
        let tokens = checkInvariant("[[#^gtd]]", isHeadline: false)

        XCTAssertEqual(
            roles(tokens),
            [.wikilinkDelimiter, .wikilinkBlock, .wikilinkDelimiter]
        )
        XCTAssertEqual(tokens[1].text, "#^gtd")
    }

    func testHeadingAndAliasLinks() throws {
        let heading = checkInvariant("[[x#Heading]]", isHeadline: false)
        XCTAssertEqual(
            roles(heading),
            [.wikilinkDelimiter, .wikilinkTarget, .wikilinkHeading, .wikilinkDelimiter]
        )
        XCTAssertEqual(heading[2].text, "#Heading")

        let alias = checkInvariant("[[x|alias]]", isHeadline: false)
        XCTAssertEqual(
            roles(alias),
            [.wikilinkDelimiter, .wikilinkTarget, .wikilinkAlias, .wikilinkDelimiter]
        )
        XCTAssertEqual(alias[2].text, "|alias")
    }

    func testBareNoteLinkInsideProse() throws {
        let tokens = checkInvariant("- See [[note]] today", isHeadline: false)

        XCTAssertEqual(
            roles(tokens),
            [.text, .wikilinkDelimiter, .wikilinkTarget, .wikilinkDelimiter, .text]
        )
        XCTAssertEqual(tokens[0].text, "- See ")
        XCTAssertEqual(tokens[4].text, " today")
    }

    // MARK: - Code, fields, and bold

    func testInlineCodeTokenizesDelimitersAsSyntax() throws {
        let tokens = checkInvariant("- Designed the `=x` grammar", isHeadline: false)

        XCTAssertEqual(
            roles(tokens),
            [.text, .syntax, .code, .syntax, .text]
        )
        XCTAssertEqual(tokens[2].text, "=x")
        XCTAssertEqual(tokens[4].text, " grammar")
    }

    func testInlineFieldTokenizesInBodyLines() throws {
        let tokens = checkInvariant("- effort [t:: 75m] done", isHeadline: false)

        XCTAssertEqual(roles(tokens), [.text, .field, .text])
        XCTAssertEqual(tokens[1].text, "[t:: 75m]")
    }

    func testBoldTokenizesDelimitersAsSyntax() throws {
        let tokens = checkInvariant("- **WORK LOG**", isHeadline: false)

        XCTAssertEqual(roles(tokens), [.text, .syntax, .text, .syntax])
        XCTAssertEqual(tokens[2].text, "WORK LOG")
    }
}

private enum LineTokensFixtureError: Error {
    case expectedSuccess
}
