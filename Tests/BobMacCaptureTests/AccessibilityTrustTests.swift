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

    func testAccessibilitySettingsURLOpensAccessibilityPane() {
        XCTAssertEqual(
            AccessibilityTrust.settingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testPermissionHintExplainsAdHocRecovery() {
        XCTAssertEqual(
            AccessibilityTrust.permissionHint(isAdHocBuild: true),
            "Grants reset when an ad-hoc build is reinstalled. Re-add the app, or run `tccutil reset Accessibility org.bobs.bob-mac-capture`."
        )
    }

    func testPermissionHintExplainsSignedBuildRecovery() {
        XCTAssertEqual(
            AccessibilityTrust.permissionHint(isAdHocBuild: false),
            "Already on in System Settings? Remove Bob Mac Capture there and add it again."
        )
    }
}
