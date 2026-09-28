import AppKit
import XCTest

@testable import BobMacCapture

final class CaptureEditorTextConfigurationTests: XCTestCase {
    func testConfigureDisablesOnlyDashSubstitution() {
        let textView = NSTextView()
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true

        CaptureEditorTextConfiguration.configure(textView)

        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertTrue(
            textView.isAutomaticQuoteSubstitutionEnabled,
            "Smart quotes must stay enabled so prose quoting is unchanged"
        )
    }

    func testConfigureIsIdempotentForShiftDrafts() {
        let textView = NSTextView()
        textView.string = "--3"
        textView.isAutomaticDashSubstitutionEnabled = true

        CaptureEditorTextConfiguration.configure(textView)
        CaptureEditorTextConfiguration.configure(textView)

        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertEqual(textView.string, "--3")
    }

    func testConfigureEditorTextViewsFindsEditableTextViewsOnly() {
        let container = NSView()
        let editable = NSTextView()
        editable.isEditable = true
        editable.isAutomaticDashSubstitutionEnabled = true
        let readOnly = NSTextView()
        readOnly.isEditable = false
        readOnly.isAutomaticDashSubstitutionEnabled = true
        container.addSubview(editable)
        container.addSubview(readOnly)

        CaptureEditorTextConfiguration.configureEditorTextViews(in: container)

        XCTAssertFalse(editable.isAutomaticDashSubstitutionEnabled)
        XCTAssertTrue(
            readOnly.isAutomaticDashSubstitutionEnabled,
            "Non-editable views are not the draft editor and must be left alone"
        )
    }

    func testConfigureEditorTextViewsToleratesNil() {
        // Must not trap when the panel has no content view yet.
        CaptureEditorTextConfiguration.configureEditorTextViews(in: nil)
    }
}
