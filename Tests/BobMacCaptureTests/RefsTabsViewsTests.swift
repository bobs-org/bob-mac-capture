import XCTest

@testable import BobMacCapture
@testable import RefsCore

/// Tabs rendering helpers: the VoiceOver page phrase and the
/// empty-well message are pure, so these tests pin them without
/// building a view.
final class RefsTabsViewsTests: XCTestCase {
    func testSpokenPagePhrase() {
        XCTAssertEqual(
            RefsRowView.spokenPagePhrase("p. 5/25"),
            "page 5 of 25"
        )
        XCTAssertEqual(
            RefsRowView.spokenPagePhrase("p. 1/4"),
            "page 1 of 4"
        )
        XCTAssertNil(RefsRowView.spokenPagePhrase(nil))
        // An unrecognized shape falls back to the raw caption rather
        // than dropping the page entirely.
        XCTAssertEqual(
            RefsRowView.spokenPagePhrase("Section 3"),
            "Section 3"
        )
    }

    func testTabsEmptyMessage() {
        XCTAssertEqual(
            RefsTabsEmptyView.message(query: "harness", scope: .all),
            "No tabs match “harness”"
        )
        XCTAssertEqual(
            RefsTabsEmptyView.message(query: "  ", scope: .papers),
            "No Papers tabs open · ⌘1 shows All"
        )
        XCTAssertEqual(
            RefsTabsEmptyView.message(query: "", scope: .all),
            "No documents are open in Highlights."
        )
    }

    func testTabsFailedText() {
        XCTAssertEqual(
            RefsTabsViews.readFailedText,
            "Couldn't read Highlights' tabs · ⌘R to retry"
        )
    }
}
