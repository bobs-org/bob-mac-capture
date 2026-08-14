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
    func testPlainTextDeclinesRichOnlyPasteboardAndLeavesTextViewUntouched() throws {
        // Regression guard for exotic pasteboards: without `.string`, the plain-text
        // path declines so AppKit can fall back to its native paste behavior.
        try withScratchPasteboard { pasteboard in
            writeRichOnlyPasteboard(pasteboard)

            let textView = NSTextView()
            textView.isEditable = true
            textView.string = "unchanged"
            textView.setSelectedRange(NSRange(location: 4, length: 0))
            var willInsertRan = false

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
