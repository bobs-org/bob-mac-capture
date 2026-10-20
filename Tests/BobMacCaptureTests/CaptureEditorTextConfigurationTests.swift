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

    func testCachedConfigureSkipsWalkWhileEditorStaysInPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        editor.isEditable = true
        editor.isAutomaticDashSubstitutionEnabled = true
        panel.contentView?.addSubview(editor)

        var cache = CaptureEditorTextConfiguration.CachedEditorTextView()
        CaptureEditorTextConfiguration.configureEditorTextViews(
            in: panel.contentView,
            panel: panel,
            cache: &cache
        )
        XCTAssertFalse(editor.isAutomaticDashSubstitutionEnabled)
        XCTAssertTrue(cache.textView === editor)

        editor.isAutomaticDashSubstitutionEnabled = true
        CaptureEditorTextConfiguration.configureEditorTextViews(
            in: panel.contentView,
            panel: panel,
            cache: &cache
        )
        XCTAssertTrue(
            editor.isAutomaticDashSubstitutionEnabled,
            "A still-attached cached editor must not be walked and reconfigured"
        )

        let otherPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        CaptureEditorTextConfiguration.configureEditorTextViews(
            in: panel.contentView,
            panel: otherPanel,
            cache: &cache
        )
        XCTAssertFalse(editor.isAutomaticDashSubstitutionEnabled)
    }

    @MainActor
    func testPickerFilterFieldUsesFirstResponderField() {
        let field = CapturePickerFilterNSTextField()
        field.setAccessibilityIdentifier(pickerFilterFieldAccessibilityIdentifier)

        XCTAssertTrue(
            CapturePanelController.pickerFilterField(
                fromFirstResponder: field,
                identifier: pickerFilterFieldAccessibilityIdentifier
            ) === field
        )
        XCTAssertNil(
            CapturePanelController.pickerFilterField(
                fromFirstResponder: field,
                identifier: pullInFilterFieldAccessibilityIdentifier
            )
        )
        XCTAssertNil(
            CapturePanelController.pickerFilterField(
                fromFirstResponder: NSTextView(),
                identifier: pickerFilterFieldAccessibilityIdentifier
            )
        )
    }
}
