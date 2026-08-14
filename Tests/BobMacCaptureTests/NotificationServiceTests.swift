import UserNotifications
import XCTest

@testable import BobMacCapture

// These tests exercise only the pure, static surfaces of NotificationService.
// UNUserNotificationCenter/UNNotification/UNNotificationResponse have no public
// initializers and instantiating the live center requires a proper app bundle
// identity, so content building, categories, and action routing are deliberately
// factored out as static functions that take/return plain values instead.
final class NotificationServiceTests: XCTestCase {
    @MainActor
    func testSuccessContentOmitsCapturedTextByDefault() {
        let content = NotificationService.successContent(
            routeLabel: "cash.md",
            targetPath: "/Users/bryan/bob/cash.md"
        )

        XCTAssertEqual(content.title, "Captured")
        XCTAssertEqual(content.subtitle, "cash.md")
        XCTAssertTrue(content.body.isEmpty)
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathKey] as? String,
            "/Users/bryan/bob/cash.md"
        )
    }

    @MainActor
    func testFailureContentCarriesOnlyTheProvidedMessage() {
        let content = NotificationService.failureContent(message: "route not found")

        XCTAssertEqual(content.title, "Capture failed")
        XCTAssertEqual(content.body, "route not found")
        XCTAssertNil(content.userInfo[NotificationService.targetPathKey])
    }

    @MainActor
    func testRestartFailureContentIsLabelledDistinctlyFromCaptureFailure() {
        let content = NotificationService.restartFailureContent(message: "not running from an app bundle")

        XCTAssertEqual(content.title, "Restart failed")
        XCTAssertEqual(content.body, "not running from an app bundle")
        XCTAssertNotEqual(content.title, NotificationService.failureContent(message: "x").title)
    }

    @MainActor
    func testTestContentDoesNotReferenceCaptureState() {
        let content = NotificationService.testContent()

        XCTAssertFalse(content.title.isEmpty)
        XCTAssertFalse(content.body.isEmpty)
    }

    @MainActor
    func testForegroundPresentationOptionsIncludeBannerSoundAndList() {
        XCTAssertEqual(
            NotificationService.foregroundPresentationOptions,
            [.banner, .sound, .list]
        )
    }

    @MainActor
    func testCaptureCategoryRegistersOpenNoteAction() {
        let category = NotificationService.captureCategory()

        XCTAssertEqual(category.identifier, NotificationService.captureCategoryIdentifier)
        XCTAssertEqual(category.actions.map(\.identifier), [NotificationService.openNoteActionIdentifier])
        XCTAssertTrue(category.actions[0].options.contains(.foreground))
    }

    @MainActor
    func testTargetURLOpensOnDefaultClickAndOpenNoteAction() {
        let userInfo: [AnyHashable: Any] = [
            NotificationService.targetPathKey: "/Users/bryan/bob/cash.md"
        ]

        let defaultClickURL = NotificationService.targetURL(
            forActionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: userInfo
        )
        let openNoteURL = NotificationService.targetURL(
            forActionIdentifier: NotificationService.openNoteActionIdentifier,
            userInfo: userInfo
        )

        XCTAssertEqual(defaultClickURL?.scheme, "obsidian")
        XCTAssertEqual(openNoteURL?.scheme, "obsidian")
    }

    @MainActor
    func testTargetURLIsNilForDismissActionOrMissingTarget() {
        let userInfo: [AnyHashable: Any] = [
            NotificationService.targetPathKey: "/Users/bryan/bob/cash.md"
        ]

        XCTAssertNil(
            NotificationService.targetURL(
                forActionIdentifier: UNNotificationDismissActionIdentifier,
                userInfo: userInfo
            )
        )
        XCTAssertNil(
            NotificationService.targetURL(
                forActionIdentifier: UNNotificationDefaultActionIdentifier,
                userInfo: [:]
            )
        )
    }

    func testAuthorizationDisplayMapsEveryStatus() {
        XCTAssertTrue(NotificationAuthorizationDisplay(status: .notDetermined).canRequestAuthorization)
        XCTAssertFalse(NotificationAuthorizationDisplay(status: .denied).canRequestAuthorization)
        XCTAssertFalse(NotificationAuthorizationDisplay(status: .authorized).canRequestAuthorization)
        XCTAssertFalse(NotificationAuthorizationDisplay(status: .provisional).canRequestAuthorization)

        XCTAssertFalse(NotificationAuthorizationDisplay(status: .authorized).displayName.isEmpty)
        XCTAssertFalse(NotificationAuthorizationDisplay(status: .denied).displayName.isEmpty)
    }
}
