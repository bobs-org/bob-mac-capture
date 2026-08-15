import CaptureCore
import UserNotifications
import XCTest

@testable import BobMacCapture

// These tests exercise only the pure, static surfaces of NotificationService.
// UNUserNotificationCenter/UNNotification/UNNotificationResponse have no public
// initializers and instantiating the live center requires a proper app bundle
// identity, so content building, categories, and action routing are deliberately
// factored out as static functions that take/return plain values instead.
final class NotificationServiceTests: XCTestCase {
    func testSingleTaskSuccessContentIncludesSemanticTextScheduleAndTargetMetadata() {
        let content = NotificationService.successContent(captures: [
            capture(
                kind: "task",
                routeLabel: "cash.md",
                target: "/Users/bryan/bob/cash.md",
                text: "Call bank",
                scheduled: "2026-08-18"
            ),
        ])

        XCTAssertEqual(content.title, "Task captured")
        XCTAssertEqual(content.subtitle, "cash.md")
        XCTAssertEqual(content.body, "Call bank\nScheduled: 2026-08-18")
        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureCategoryIdentifier)
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathKey] as? String,
            "/Users/bryan/bob/cash.md"
        )
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            ["/Users/bryan/bob/cash.md"]
        )
    }

    func testSingleNoteSuccessContentUsesNoteTitleAndSafeBodyFallback() {
        let content = NotificationService.successContent(captures: [
            capture(
                kind: "bullet",
                routeLabel: "ideas.md",
                target: "/Users/bryan/bob/ideas.md",
                text: "",
                parentText: "Sketch notification polish"
            ),
        ])

        XCTAssertEqual(content.title, "Note captured")
        XCTAssertEqual(content.subtitle, "ideas.md")
        XCTAssertEqual(content.body, "Sketch notification polish")
    }

    func testSameTargetBatchUsesOrderedBodyLinesAndSingleOpenAction() {
        let content = NotificationService.successContent(captures: [
            capture(
                kind: "task",
                routeLabel: "today.md",
                target: "/Users/bryan/bob/today.md",
                text: "Pay rent"
            ),
            capture(
                kind: "sub-bullet",
                routeLabel: "today.md",
                target: "/Users/bryan/bob/today.md",
                text: "Add lease note"
            ),
        ])

        XCTAssertEqual(content.title, "2 items captured")
        XCTAssertEqual(content.subtitle, "1 note, 1 task across 1 destination")
        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureCategoryIdentifier)
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            ["/Users/bryan/bob/today.md"]
        )
        XCTAssertTrue(content.body.contains("1. Task -> today.md: Pay rent"))
        XCTAssertTrue(content.body.contains("2. Note -> today.md: Add lease note"))
        XCTAssertFalse(content.body.contains("..."))
        XCTAssertFalse(content.body.contains("\u{2026}"))
    }

    func testCrossTargetBatchUsesPluralCategoryAndPreservesTargetOrder() {
        let content = NotificationService.successContent(captures: [
            capture(
                kind: "pomodoro-task",
                routeLabel: "work.md",
                target: "/Users/bryan/bob/work.md",
                text: "Ship release",
                scheduled: "2026-08-19"
            ),
            capture(
                kind: "bullet",
                routeLabel: "ideas.md",
                target: "/Users/bryan/bob/ideas.md",
                text: "Capture follow-up"
            ),
        ])

        XCTAssertEqual(content.title, "2 items captured")
        XCTAssertEqual(content.subtitle, "1 note, 1 task across 2 destinations")
        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureBatchCategoryIdentifier)
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            [
                "/Users/bryan/bob/work.md",
                "/Users/bryan/bob/ideas.md",
            ]
        )
        XCTAssertTrue(content.body.contains("1. Task -> work.md: Ship release scheduled 2026-08-19"))
        XCTAssertTrue(content.body.contains("2. Note -> ideas.md: Capture follow-up"))
    }

    func testSuccessWithNoUsableTargetOmitsOpenCategoryAndTargetMetadata() {
        let content = NotificationService.successContent(captures: [
            capture(kind: "future-kind", routeLabel: "external", target: "", text: "Captured elsewhere"),
        ])

        XCTAssertEqual(content.title, "Future Kind captured")
        XCTAssertEqual(content.body, "Captured elsewhere")
        XCTAssertTrue(content.categoryIdentifier.isEmpty)
        XCTAssertNil(content.userInfo[NotificationService.targetPathKey])
        XCTAssertNil(content.userInfo[NotificationService.targetPathsKey])
    }

    func testFailureContentCarriesOnlyTheProvidedMessage() {
        let content = NotificationService.failureContent(message: "route not found")

        XCTAssertEqual(content.title, "Capture failed")
        XCTAssertEqual(content.body, "route not found")
        XCTAssertNil(content.userInfo[NotificationService.targetPathKey])
    }

    func testRestartFailureContentIsLabelledDistinctlyFromCaptureFailure() {
        let content = NotificationService.restartFailureContent(message: "not running from an app bundle")

        XCTAssertEqual(content.title, "Restart failed")
        XCTAssertEqual(content.body, "not running from an app bundle")
        XCTAssertNotEqual(content.title, NotificationService.failureContent(message: "x").title)
    }

    func testTestContentDoesNotReferenceCaptureState() {
        let content = NotificationService.testContent()

        XCTAssertFalse(content.title.isEmpty)
        XCTAssertFalse(content.body.isEmpty)
    }

    func testForegroundPresentationOptionsIncludeBannerSoundAndList() {
        XCTAssertEqual(
            NotificationService.foregroundPresentationOptions,
            [.banner, .sound, .list]
        )
    }

    func testCaptureCategoriesRegisterSingularAndPluralOpenActions() {
        let singular = NotificationService.captureCategory()
        let plural = NotificationService.captureBatchCategory()

        XCTAssertEqual(singular.identifier, NotificationService.captureCategoryIdentifier)
        XCTAssertEqual(singular.actions.map(\.identifier), [NotificationService.openNoteActionIdentifier])
        XCTAssertEqual(singular.actions[0].title, "Open Note")
        XCTAssertTrue(singular.actions[0].options.contains(.foreground))

        XCTAssertEqual(plural.identifier, NotificationService.captureBatchCategoryIdentifier)
        XCTAssertEqual(plural.actions.map(\.identifier), [NotificationService.openNotesActionIdentifier])
        XCTAssertEqual(plural.actions[0].title, "Open Notes")
        XCTAssertEqual(
            Set(NotificationService.captureCategories().map(\.identifier)),
            [
                NotificationService.captureCategoryIdentifier,
                NotificationService.captureBatchCategoryIdentifier,
            ]
        )
    }

    func testTargetURLsOpenOnDefaultClickSingularPluralAndLegacyMetadata() {
        let batchUserInfo: [AnyHashable: Any] = [
            NotificationService.targetPathKey: "/Users/bryan/bob/work.md",
            NotificationService.targetPathsKey: [
                "/Users/bryan/bob/work.md",
                "/Users/bryan/bob/ideas.md",
                "/Users/bryan/bob/work.md",
            ],
        ]
        let legacyUserInfo: [AnyHashable: Any] = [
            NotificationService.targetPathKey: "/Users/bryan/bob/cash.md",
        ]

        let defaultClickURLs = NotificationService.targetURLs(
            forActionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: batchUserInfo
        )
        let pluralActionURLs = NotificationService.targetURLs(
            forActionIdentifier: NotificationService.openNotesActionIdentifier,
            userInfo: batchUserInfo
        )
        let legacyURL = NotificationService.targetURL(
            forActionIdentifier: NotificationService.openNoteActionIdentifier,
            userInfo: legacyUserInfo
        )

        XCTAssertEqual(defaultClickURLs.count, 2)
        XCTAssertEqual(pluralActionURLs.count, 2)
        XCTAssertEqual(defaultClickURLs.map(\.scheme), ["obsidian", "obsidian"])
        XCTAssertEqual(legacyURL?.scheme, "obsidian")
        XCTAssertEqual(legacyURL?.host, "open")
    }

    func testTargetURLsAreEmptyForDismissActionOrMissingTarget() {
        let userInfo: [AnyHashable: Any] = [
            NotificationService.targetPathKey: "/Users/bryan/bob/cash.md",
        ]

        XCTAssertEqual(
            NotificationService.targetURLs(
                forActionIdentifier: UNNotificationDismissActionIdentifier,
                userInfo: userInfo
            ),
            []
        )
        XCTAssertEqual(
            NotificationService.targetURLs(
                forActionIdentifier: UNNotificationDefaultActionIdentifier,
                userInfo: [:]
            ),
            []
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

    private func capture(
        kind: String,
        routeLabel: String,
        target: String,
        text: String,
        scheduled: String? = nil,
        parentText: String? = nil
    ) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: !target.isEmpty,
            routeLabel: routeLabel,
            relativeTarget: routeLabel,
            target: target,
            text: text,
            taskLine: "- [ ] #task \(text)",
            kind: kind,
            created: "2026-08-14",
            scheduled: scheduled,
            placement: "inserted",
            parentText: parentText
        )
    }
}
