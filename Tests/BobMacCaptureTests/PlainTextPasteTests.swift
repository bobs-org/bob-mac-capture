import AppKit
import XCTest

@testable import BobMacCapture

final class PlainTextPasteTests: XCTestCase {
    @MainActor
    func testNormalizedCanonicalizesCRLFAndLoneCR() {
        // Regression guard for capture grammar parsing: pasted text must use physical
        // LF-delimited lines no matter which platform produced the clipboard text.
        XCTAssertEqual(PlainTextPaste.normalized("a\r\nb"), "a\nb")
        XCTAssertEqual(PlainTextPaste.normalized("a\rb"), "a\nb")
        XCTAssertEqual(PlainTextPaste.normalized("a\rb\r\nc\nd"), "a\nb\nc\nd")
        XCTAssertEqual(PlainTextPaste.normalized("a\nb"), "a\nb")
        XCTAssertEqual(PlainTextPaste.normalized(""), "")
    }

    @MainActor
    func testPlainTextReadsOnlyStringFlavorWhenRichFlavorsAlsoExist() throws {
        // Regression guard for browser pasteboards: HTML/RTF source must never become
        // literal capture text when a plain-text flavor is available.
        try withScratchPasteboard { pasteboard in
            writeRichAndPlainPasteboard(pasteboard, plain: "Plain capture text")

            XCTAssertEqual(PlainTextPaste.plainText(from: pasteboard), "Plain capture text")
        }
    }

    @MainActor
    func testPlainTextDeclinesReaderWithoutStringFlavorAndLeavesTextViewUntouched() {
        // Regression guard for rich-only pasteboards: a converting accessor may produce
        // plain text, but the plain-text path only consumes a reported `.string`.
        let pasteboard = TestPasteboardReader(
            types: [.html, .rtf],
            strings: [.string: "Rich capture text"]
        )
        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "unchanged"
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        var willInsertRan = false

        XCTAssertFalse(pasteboard.types?.contains(.string) ?? false)
        XCTAssertNotNil(pasteboard.string(forType: .string))
        XCTAssertNil(PlainTextPaste.plainText(from: pasteboard))
        XCTAssertFalse(
            PlainTextPaste.insert(
                into: textView,
                from: pasteboard,
                willInsert: { willInsertRan = true }
            )
        )
        XCTAssertEqual(textView.string, "unchanged")
        XCTAssertFalse(willInsertRan)
    }

    func testResolverJoinsTopLevelPastedBulletListIntoPlaceholder() {
        let draft = "Parent\n- "
        let (edit, result) = resolvePaste(
            draft: draft,
            selectedRange: NSRange(location: draft.utf16.count, length: 0),
            clipboardText: "- first\n- second"
        )

        XCTAssertEqual(
            edit.replacementRange,
            NSRange(location: "Parent\n".utf16.count, length: "- ".utf16.count)
        )
        XCTAssertEqual(result, "Parent\n- first\n- second")
    }

    func testResolverRebasesFlatListOntoNestedPlaceholder() {
        let draft = "Parent\n  - "
        let (_, result) = resolvePaste(
            draft: draft,
            selectedRange: NSRange(location: draft.utf16.count, length: 0),
            clipboardText: "- first\n- second"
        )

        XCTAssertEqual(result, "Parent\n  - first\n  - second")
    }

    func testResolverRebasesIndentedClipboardFromFirstBulletBaseline() {
        let draft = "Parent\n- "
        let (_, result) = resolvePaste(
            draft: draft,
            selectedRange: NSRange(location: draft.utf16.count, length: 0),
            clipboardText: "  - first\n    - child\n  - second"
        )

        XCTAssertEqual(result, "Parent\n- first\n  - child\n- second")
    }

    func testResolverRetainsPlaceholderMarkerWhenClipboardUsesDifferentMarker() {
        for marker in ["*", "+"] {
            let draft = "Parent\n\(marker) "
            let (_, result) = resolvePaste(
                draft: draft,
                selectedRange: NSRange(location: draft.utf16.count, length: 0),
                clipboardText: "- first\n- second"
            )

            XCTAssertEqual(result, "Parent\n\(marker) first\n- second")
        }
    }

    func testResolverPreservesBlankLinesAndTrailingNewlineWithoutWhitespaceOnlyRows() {
        let draft = "Parent\n  - "
        let (_, result) = resolvePaste(
            draft: draft,
            selectedRange: NSRange(location: draft.utf16.count, length: 0),
            clipboardText: "- first\n  \n  - child\n"
        )

        XCTAssertEqual(result, "Parent\n  - first\n\n    - child\n")
    }

    func testResolverFallsBackToExactPlainTextInsertionOutsidePlaceholderListPaste() {
        let cases: [(
            name: String,
            draft: String,
            selectedRange: NSRange,
            clipboardText: String
        )] = [
            (
                "prose clipboard",
                "Parent\n- ",
                NSRange(location: "Parent\n- ".utf16.count, length: 0),
                "plain text"
            ),
            (
                "unsupported first clipboard line",
                "Parent\n- ",
                NSRange(location: "Parent\n- ".utf16.count, length: 0),
                "-first"
            ),
            (
                "marker-only clipboard line",
                "Parent\n- ",
                NSRange(location: "Parent\n- ".utf16.count, length: 0),
                "- "
            ),
            (
                "noncollapsed selection",
                "Parent\n- ",
                NSRange(location: "Parent\n".utf16.count, length: "- ".utf16.count),
                "- first"
            ),
            (
                "multiline selection",
                "Parent\n- \nChild",
                NSRange(location: 0, length: "Parent\n- ".utf16.count),
                "- first"
            ),
            (
                "mid-line caret",
                "Parent\n-  suffix",
                NSRange(location: "Parent\n- ".utf16.count, length: 0),
                "- first"
            ),
            (
                "authored bullet row",
                "Parent\n- existing",
                NSRange(location: "Parent\n- existing".utf16.count, length: 0),
                "- first"
            ),
            (
                "unsupported placeholder indentation",
                "Parent\n - ",
                NSRange(location: "Parent\n - ".utf16.count, length: 0),
                "- first"
            ),
        ]

        for testCase in cases {
            let (edit, result) = resolvePaste(
                draft: testCase.draft,
                selectedRange: testCase.selectedRange,
                clipboardText: testCase.clipboardText
            )

            XCTAssertEqual(edit.replacementRange, testCase.selectedRange, testCase.name)
            XCTAssertEqual(edit.replacementText, testCase.clipboardText, testCase.name)
            XCTAssertEqual(
                result,
                defaultPasteResult(
                    draft: testCase.draft,
                    selectedRange: testCase.selectedRange,
                    clipboardText: testCase.clipboardText
                ),
                testCase.name
            )
        }
    }

    @MainActor
    func testInsertSplicesPlainTextAndDoesNotImportRichFormatting() throws {
        // Regression guard for slow rich paste: inserting must use the plain flavor
        // only, so links/colors/fonts from HTML or RTF never enter the editor.
        try withScratchPasteboard { pasteboard in
            writeRichAndPlainPasteboard(pasteboard, plain: "PLAIN")

            let textView = NSTextView()
            textView.isEditable = true
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.black,
            ]
            let textStorage = try XCTUnwrap(textView.textStorage)
            textStorage.setAttributedString(
                NSAttributedString(string: "AlphaOmega", attributes: attributes)
            )
            textView.typingAttributes = attributes
            textView.setSelectedRange(NSRange(location: 5, length: 0))
            var willInsertRan = false

            XCTAssertTrue(
                PlainTextPaste.insert(
                    into: textView,
                    from: pasteboard,
                    willInsert: { willInsertRan = true }
                )
            )

            XCTAssertEqual(textView.string, "AlphaPLAINOmega")
            XCTAssertTrue(willInsertRan)
            assertNoLinkAttribute(in: textStorage)
            assertSingleEffectiveRun(for: .font, in: textStorage)
            assertSingleEffectiveRun(for: .foregroundColor, in: textStorage)
        }
    }

    @MainActor
    func testInsertJoinsBulletListThroughNativePlainTextPath() throws {
        try withScratchPasteboard { pasteboard in
            writeRichAndPlainPasteboard(pasteboard, plain: "+ first\r\n- second")

            let textView = NSTextView()
            textView.isEditable = true
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.black,
            ]
            let textStorage = try XCTUnwrap(textView.textStorage)
            textStorage.setAttributedString(
                NSAttributedString(string: "Parent\n* ", attributes: attributes)
            )
            textView.typingAttributes = attributes
            textView.setSelectedRange(
                NSRange(location: "Parent\n* ".utf16.count, length: 0)
            )
            var willInsertCount = 0

            XCTAssertTrue(
                PlainTextPaste.insert(
                    into: textView,
                    from: pasteboard,
                    willInsert: { willInsertCount += 1 }
                )
            )

            XCTAssertEqual(textView.string, "Parent\n* first\n- second")
            XCTAssertEqual(
                textView.selectedRange(),
                NSRange(location: "Parent\n* first\n- second".utf16.count, length: 0)
            )
            XCTAssertEqual(willInsertCount, 1)
            assertNoLinkAttribute(in: textStorage)
            assertSingleEffectiveRun(for: .font, in: textStorage)
            assertSingleEffectiveRun(for: .foregroundColor, in: textStorage)
        }
    }

    @MainActor
    func testInsertDeclinesNilUnrelatedAndNoneditableResponders() throws {
        // Regression guard for responder-chain fallthrough: plain-text paste only
        // consumes events when the target is an editable text view.
        try withScratchPasteboard { pasteboard in
            writeRichAndPlainPasteboard(pasteboard, plain: "inserted")

            let noneditable = NSTextView()
            noneditable.isEditable = false
            noneditable.string = "unchanged"

            XCTAssertFalse(PlainTextPaste.insert(into: nil, from: pasteboard))
            XCTAssertFalse(
                PlainTextPaste.insert(
                    into: NSButton(title: "Preview", target: nil, action: nil),
                    from: pasteboard
                )
            )
            XCTAssertFalse(PlainTextPaste.insert(into: noneditable, from: pasteboard))
            XCTAssertEqual(noneditable.string, "unchanged")
        }
    }

    @MainActor
    private func withScratchPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        try body(pasteboard)
    }

    @MainActor
    private func writeRichAndPlainPasteboard(_ pasteboard: NSPasteboard, plain: String) {
        writeRichOnlyPasteboard(pasteboard)
        XCTAssertTrue(pasteboard.setString(plain, forType: .string))
    }

    @MainActor
    private func writeRichOnlyPasteboard(_ pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        XCTAssertTrue(
            pasteboard.setString(
                "<a href=\"https://example.com\">Rich capture text</a>",
                forType: .html
            )
        )
        let rtf = #"{\rtf1\ansi{\field{\*\fldinst{HYPERLINK "https://example.com"}}{\fldrslt Rich capture text}}}"#
            .data(using: .utf8)!
        XCTAssertTrue(pasteboard.setData(rtf, forType: .rtf))
    }

    private func resolvePaste(
        draft: String,
        selectedRange: NSRange,
        clipboardText: String
    ) -> (edit: PlainTextPasteEdit, result: String) {
        let edit = PlainTextPasteEditResolver.resolve(
            in: draft,
            selectedRange: selectedRange,
            clipboardText: clipboardText
        )
        let result = NSMutableString(string: draft)
        result.replaceCharacters(in: edit.replacementRange, with: edit.replacementText)
        return (edit, String(result))
    }

    private func defaultPasteResult(
        draft: String,
        selectedRange: NSRange,
        clipboardText: String
    ) -> String {
        let result = NSMutableString(string: draft)
        result.replaceCharacters(in: selectedRange, with: clipboardText)
        return String(result)
    }

    private struct TestPasteboardReader: PlainTextPasteboardReading {
        let types: [NSPasteboard.PasteboardType]?
        let strings: [NSPasteboard.PasteboardType: String]

        func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
            strings[dataType]
        }
    }

    @MainActor
    private func assertNoLinkAttribute(
        in textStorage: NSTextStorage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            XCTAssertNil(value, "Unexpected .link attribute in \(range)", file: file, line: line)
        }
    }

    @MainActor
    private func assertSingleEffectiveRun(
        for key: NSAttributedString.Key,
        in textStorage: NSTextStorage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var firstValue: Any?
        var hasFirstValue = false
        var runCount = 0

        textStorage.enumerateAttribute(key, in: fullRange) { value, _, _ in
            runCount += 1
            if !hasFirstValue {
                firstValue = value
                hasFirstValue = true
            } else {
                XCTAssertTrue(
                    attributeValue(value, equals: firstValue),
                    "Expected \(key.rawValue) to be uniform",
                    file: file,
                    line: line
                )
            }
        }

        XCTAssertEqual(runCount, textStorage.length == 0 ? 0 : 1, file: file, line: line)
    }

    @MainActor
    private func attributeValue(_ lhs: Any?, equals rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            if let lhsObject = lhs as? NSObject, let rhsObject = rhs as? NSObject {
                return lhsObject.isEqual(rhsObject)
            }
            return String(describing: lhs) == String(describing: rhs)
        default:
            return false
        }
    }
}
