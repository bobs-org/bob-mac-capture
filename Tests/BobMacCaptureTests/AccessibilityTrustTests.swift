import XCTest

@testable import BobMacCapture

final class AccessibilityTrustTests: XCTestCase {
    func testStatusTextReadsAllowedWhenTrusted() {
        XCTAssertEqual(AccessibilityTrust.statusText(isTrusted: true), "Allowed")
    }

    func testStatusTextReadsNotAllowedWhenUntrusted() {
        XCTAssertEqual(AccessibilityTrust.statusText(isTrusted: false), "Not allowed")
    }

    func testAdHocCaptionAppearsOnlyOnAdHocBuilds() {
        XCTAssertEqual(
            AccessibilityTrust.adHocCaption(isAdHocBuild: true),
            "Grants reset when an ad-hoc build is reinstalled."
        )
        XCTAssertNil(AccessibilityTrust.adHocCaption(isAdHocBuild: false))
    }
}
