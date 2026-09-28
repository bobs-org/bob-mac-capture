import CaptureCore
import Foundation
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

    func testSinglePomodoroStartSuccessContentAppendsSessionDetail() {
        let content = NotificationService.successContent(captures: [
            capture(
                kind: "pomodoro_task",
                routeLabel: "sase.md",
                target: "/Users/bryan/bob/sase.md",
                text: "Write outline",
                pomodoroStart: PomodoroStartSummary(
                    start: "0930",
                    end: "0945",
                    durationMinutes: 15,
                    offsetUnits: 0,
                    pomodoroName: nil,
                    pomodoroLine: 12,
                    createdPomodoro: false,
                    timeRange: "(**0930-0945** [t:: 15m])"
                )
            ),
        ])

        XCTAssertEqual(content.title, "Task captured")
        XCTAssertEqual(content.subtitle, "sase.md")
        XCTAssertTrue(content.body.contains("Write outline"))
        XCTAssertTrue(content.body.contains("Started next session 0930-0945 (15m) at line 12"))
    }

    func testSinglePomodoroAdjustSuccessContentAppendsBeforeAfterDetail() {
        let content = NotificationService.successContent(captures: [
            capture(
                kind: "pomodoro_adjust",
                routeLabel: "",
                target: "/Users/bryan/bob/2026/20260814.md",
                text: "+5",
                pomodoroAdjust: PomodoroAdjustSummary(
                    direction: "plus",
                    requestedUnits: 5,
                    requestedMinutes: 25,
                    deltaMinutes: 25,
                    beforeStart: "0900",
                    beforeEnd: "0930",
                    beforeDurationMinutes: 30,
                    afterStart: "0900",
                    afterEnd: "0955",
                    afterDurationMinutes: 55,
                    pomodoroLine: 3,
                    pomodoroName: "FOCUS",
                    timeRange: "(**0900-0955** [t:: 55m])",
                    clamped: false
                ),
                relativeTarget: "day.md"
            ),
        ])

        XCTAssertEqual(content.title, "Adjustment captured")
        XCTAssertEqual(content.subtitle, "day.md")
        XCTAssertTrue(content.body.contains("+5"))
        XCTAssertTrue(content.body.contains("Adjusted FOCUS 0900-0930 (30m) to 0900-0955 (55m), +25m at line 3"))
    }

    func testPomodoroCloseNotificationIncludesResolvedSessionWorkLogAndNextSession() throws {
        let closed = try closeSuccessFixture("pomodoro-close-worked.json")
        let content = NotificationService.successContent(captures: [closed])

        XCTAssertEqual(content.title, "Closed CAPTURE")
        XCTAssertEqual(content.subtitle, "2026/20260928.md")
        XCTAssertTrue(content.body.contains("0920-0940 (20m)"))
        XCTAssertTrue(content.body.contains("0920-0950 → 0920-0940 · stopped 0937 · −10m"))
        XCTAssertTrue(content.body.contains("*2026-09-28* — Designed the `=x` grammar"))
        XCTAssertTrue(content.body.contains("Next: CAPTURE · untimed · line 13 · created"))
        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureCategoryIdentifier)
    }

    func testSingleClampedAdjustSuccessContentKeepsRequestedNote() {
        let content = NotificationService.successContent(captures: [
            capture(
                kind: "pomodoro_adjust",
                routeLabel: "",
                target: "/Users/bryan/bob/2026/20260814.md",
                text: "-9",
                pomodoroAdjust: PomodoroAdjustSummary(
                    direction: "minus",
                    requestedUnits: 9,
                    requestedMinutes: -45,
                    deltaMinutes: -10,
                    beforeStart: "0900",
                    beforeEnd: "0910",
                    beforeDurationMinutes: 10,
                    afterStart: "0900",
                    afterEnd: "0900",
                    afterDurationMinutes: 0,
                    pomodoroLine: 3,
                    pomodoroName: "FOCUS",
                    timeRange: "(**0900-0900** [t:: 0m])",
                    clamped: true
                ),
                relativeTarget: "day.md"
            ),
        ])

        XCTAssertEqual(content.title, "Adjustment captured")
        XCTAssertTrue(content.body.contains("(requested -45m in 9 units clamped)"))
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

    func testSingleProjectNoteSuccessContentUsesProjectTitle() {
        let content = NotificationService.successContent(captures: [
            capture(
                kind: "project_note",
                routeLabel: "cash_goog_exit.md",
                target: "/Users/bryan/bob/cash_goog_exit.md",
                text: "Finish the Google exit packet!"
            ),
        ])

        XCTAssertEqual(content.title, "Project captured")
        XCTAssertEqual(content.subtitle, "cash_goog_exit.md")
        XCTAssertEqual(content.body, "Finish the Google exit packet!")
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

    func testGlobalSameTargetBatchUsesCompactSharedScopeBody() {
        let content = NotificationService.successContent(
            captures: [
                capture(
                    kind: "task",
                    routeLabel: "foo.md",
                    target: "/Users/bryan/bob/foo.md",
                    text: "First task"
                ),
                capture(
                    kind: "task",
                    routeLabel: "foo.md",
                    target: "/Users/bryan/bob/foo.md",
                    text: "Second task"
                ),
            ],
            globalDestination: CaptureGlobalDestination(mode: "task", route: "foo")
        )

        XCTAssertEqual(content.title, "2 items captured")
        XCTAssertEqual(content.subtitle, "2 tasks \u{00b7} foo.md")
        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureCategoryIdentifier)
        XCTAssertTrue(content.body.contains("1. First task"))
        XCTAssertTrue(content.body.contains("2. Second task"))
        XCTAssertFalse(content.body.contains("-> foo.md"))
        XCTAssertFalse(content.body.contains("@@"))
    }

    func testGlobalSharedParentBatchMentionsParentOnce() {
        let content = NotificationService.successContent(
            captures: [
                capture(
                    kind: "sub_bullet",
                    routeLabel: "file.md",
                    target: "/Users/bryan/bob/file.md",
                    text: "First note",
                    blockID: "hand"
                ),
                capture(
                    kind: "sub_bullet",
                    routeLabel: "file.md",
                    target: "/Users/bryan/bob/file.md",
                    text: "Second note",
                    blockID: "hand"
                ),
            ],
            globalDestination: CaptureGlobalDestination(
                mode: "sub_bullet",
                route: "file",
                blockID: "hand"
            )
        )

        XCTAssertEqual(content.subtitle, "2 notes \u{00b7} file.md \u{00b7} under ^hand")
        XCTAssertTrue(content.body.contains("1. First note"))
        XCTAssertFalse(content.body.contains("1. First note \u{2192} file.md"))
    }

    func testGlobalMixedOverrideBatchNamesOnlyOverrideDestination() {
        let content = NotificationService.successContent(
            captures: [
                capture(
                    kind: "task",
                    routeLabel: "foo.md",
                    target: "/Users/bryan/bob/foo.md",
                    text: "First task"
                ),
                capture(
                    kind: "task",
                    routeLabel: "bar.md",
                    target: "/Users/bryan/bob/bar.md",
                    text: "Second task"
                ),
            ],
            globalDestination: CaptureGlobalDestination(mode: "task", route: "foo")
        )

        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureBatchCategoryIdentifier)
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            [
                "/Users/bryan/bob/foo.md",
                "/Users/bryan/bob/bar.md",
            ]
        )
        XCTAssertTrue(content.subtitle.contains("1 local override"))
        XCTAssertTrue(content.body.contains("1. First task"))
        XCTAssertTrue(content.body.contains("2. Second task \u{2192} bar.md"))
        XCTAssertFalse(content.body.contains("1. First task \u{2192} foo.md"))
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

    func testTaskToggleSuccessContentUsesToggleCopyAndOpensBothChangedNotes() {
        let content = NotificationService.successContent(captures: [
            toggleCapture(direction: "next", dayFileChanged: true),
        ])

        XCTAssertEqual(content.title, "Set Next")
        XCTAssertEqual(content.subtitle, "cash.md \u{00b7} ^goog-exit")
        XCTAssertTrue(content.body.contains("Ready \u{2192} Next"))
        XCTAssertTrue(content.body.contains("+ [[cash#^goog-exit]]"))
        // Two files changed (the route note and the daily note), so this uses the
        // plural "Open Notes" category the same way an ordinary multi-target batch does.
        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureBatchCategoryIdentifier)
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            ["/tmp/bob/cash.md", "/tmp/bob/2026/20260910.md"]
        )
    }

    func testEnsureNextSuccessContentUsesCombinedTitleAndOpensBothNotes() {
        let content = NotificationService.successContent(captures: [
            ensureNextCapture(statusChanged: true, linkAction: "moved"),
        ])

        XCTAssertEqual(content.title, "Ensured Next and moved")
        XCTAssertEqual(content.subtitle, "cash.md \u{00b7} ^goog-exit")
        XCTAssertTrue(content.body.contains("Ready \u{2192} Next"))
        XCTAssertTrue(content.body.contains("Moved LATER \u{2192} CURRENT"))
        XCTAssertFalse(content.body.contains("+ [["))
        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureBatchCategoryIdentifier)
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            ["/tmp/bob/cash.md", "/tmp/bob/2026/20260910.md"]
        )
    }

    func testEnsureNextNoOpOpensOnlyTheRouteNote() {
        let content = NotificationService.successContent(captures: [
            ensureNextCapture(statusChanged: false, linkAction: "already_current"),
        ])

        XCTAssertEqual(content.title, "Already Next")
        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureCategoryIdentifier)
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathKey] as? String,
            "/tmp/bob/cash.md"
        )
        // The unchanged day file is excluded; the single route note still yields ordered paths.
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            ["/tmp/bob/cash.md"]
        )
    }

    func testEnsureNextNamedCreationOpensBothNotes() {
        let content = NotificationService.successContent(captures: [
            ensureNextCapture(
                statusChanged: true,
                linkAction: "moved",
                createsPomodoro: true,
                destinationName: "FRESH"
            ),
        ])

        XCTAssertEqual(content.title, "Ensured Next and created")
        XCTAssertTrue(content.body.contains("created FRESH"))
        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureBatchCategoryIdentifier)
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            ["/tmp/bob/cash.md", "/tmp/bob/2026/20260910.md"]
        )
    }

    func testPomodoroLinkSuccessContentUsesLinkCopyAndOpensBothNotes() {
        let content = NotificationService.successContent(captures: [
            linkCapture(action: "linked", statusChanged: true),
        ])

        XCTAssertEqual(content.title, "Linked to BUGS")
        XCTAssertEqual(content.subtitle, "sase.md \u{00b7} ^ready")
        XCTAssertTrue(content.body.contains("Todo \u{2192} Next"))
        XCTAssertTrue(content.body.contains("Linked under BUGS"))
        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureBatchCategoryIdentifier)
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            ["/tmp/bob/sase.md", "/tmp/bob/2026/20260710.md"]
        )
    }

    func testPomodoroLinkAlreadyCurrentOpensOnlyTheRouteNote() {
        let content = NotificationService.successContent(captures: [
            linkCapture(action: "already_current", statusChanged: false),
        ])

        XCTAssertEqual(content.title, "Already in BUGS")
        XCTAssertTrue(content.body.contains("Task Link already in BUGS; no ledger change."))
        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureCategoryIdentifier)
        // The unchanged day file is excluded; the single route note still yields ordered paths.
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            ["/tmp/bob/sase.md"]
        )
    }

    func testPomodoroLinkStartUsesStartedTitleAndSessionDetail() {
        let content = NotificationService.successContent(captures: [
            linkCapture(
                action: "moved",
                statusChanged: false,
                destinationName: "FOCUS",
                createsPomodoro: true,
                pomodoroStart: PomodoroStartSummary(
                    start: "0905",
                    end: "0920",
                    durationMinutes: 15,
                    offsetUnits: 0,
                    pomodoroName: "FOCUS",
                    pomodoroLine: 5,
                    createdPomodoro: true,
                    timeRange: "(**0905-0920** [t:: 15m])"
                )
            ),
        ])

        XCTAssertEqual(content.title, "Started FOCUS")
        XCTAssertTrue(content.body.contains("Moved Task Link BUGS \u{2192} FOCUS (created FOCUS)"))
        XCTAssertTrue(
            content.body.contains("Started FOCUS 0905-0920 (15m) (created) at line 5")
        )
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            ["/tmp/bob/sase.md", "/tmp/bob/2026/20260710.md"]
        )
    }

    func testPomodoroLinkBatchLineUsesTransitionTextAndLinkKind() {
        let content = NotificationService.successContent(captures: [
            linkCapture(action: "linked", statusChanged: true),
            capture(
                kind: "task",
                routeLabel: "sase.md",
                target: "/tmp/bob/sase.md",
                text: "Follow up"
            ),
        ])

        XCTAssertEqual(content.title, "2 items captured")
        XCTAssertEqual(content.subtitle, "1 link, 1 task across 2 destinations")
        XCTAssertTrue(content.body.contains("1. Link -> sase.md: [ ] \u{2192} [*]  #task Ready thing"))
        XCTAssertTrue(content.body.contains("2. Task -> sase.md: Follow up"))
    }

    func testTaskToggleSuccessContentOmitsDayFileFromTargetsWhenNothingChangedThere() {
        let content = NotificationService.successContent(captures: [
            toggleCapture(direction: "next", dayFileChanged: false),
        ])

        XCTAssertEqual(content.categoryIdentifier, NotificationService.captureCategoryIdentifier)
        XCTAssertEqual(
            content.userInfo[NotificationService.targetPathsKey] as? [String],
            ["/tmp/bob/cash.md"]
        )
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
                NotificationService.installRestartCategoryIdentifier,
            ]
        )
    }

    func testInstallCompleteContentUsesStaticCopyDefaultSoundAndDedicatedCategory() {
        let content = NotificationService.installCompleteContent()

        XCTAssertEqual(content.title, "Install complete")
        XCTAssertEqual(content.body, "Bob Mac Capture restarted successfully.")
        XCTAssertTrue(content.sound?.isEqual(UNNotificationSound.default) == true)
        XCTAssertEqual(
            content.categoryIdentifier,
            NotificationService.installRestartCategoryIdentifier
        )
        XCTAssertTrue(content.userInfo.isEmpty)
        XCTAssertTrue(content.subtitle.isEmpty)
        XCTAssertTrue(content.attachments.isEmpty)
        XCTAssertNil(content.userInfo[NotificationService.targetPathKey])
        XCTAssertNil(content.userInfo[NotificationService.targetPathsKey])
    }

    func testInstallRestartCategoryRegistersForegroundCaptureAction() {
        let category = NotificationService.installRestartCategory()

        XCTAssertEqual(
            category.identifier,
            NotificationService.installRestartCategoryIdentifier
        )
        XCTAssertEqual(
            category.actions.map(\.identifier),
            [NotificationService.captureActionIdentifier]
        )
        XCTAssertEqual(category.actions[0].title, "Capture")
        XCTAssertTrue(category.actions[0].options.contains(.foreground))
    }

    func testInstallRestartRoutesBodyClickAndCaptureToShowCapture() {
        XCTAssertEqual(
            NotificationService.route(
                forActionIdentifier: UNNotificationDefaultActionIdentifier,
                categoryIdentifier: NotificationService.installRestartCategoryIdentifier,
                userInfo: [:]
            ),
            .showCapture
        )
        XCTAssertEqual(
            NotificationService.route(
                forActionIdentifier: NotificationService.captureActionIdentifier,
                categoryIdentifier: NotificationService.installRestartCategoryIdentifier,
                userInfo: [:]
            ),
            .showCapture
        )
    }

    func testInstallRestartDismissalAndMismatchedActionsAreNoOps() {
        XCTAssertEqual(
            NotificationService.route(
                forActionIdentifier: UNNotificationDismissActionIdentifier,
                categoryIdentifier: NotificationService.installRestartCategoryIdentifier,
                userInfo: [:]
            ),
            .none
        )
        XCTAssertEqual(
            NotificationService.route(
                forActionIdentifier: NotificationService.openNoteActionIdentifier,
                categoryIdentifier: NotificationService.installRestartCategoryIdentifier,
                userInfo: [:]
            ),
            .none
        )
        XCTAssertEqual(
            NotificationService.route(
                forActionIdentifier: NotificationService.captureActionIdentifier,
                categoryIdentifier: NotificationService.captureCategoryIdentifier,
                userInfo: [
                    NotificationService.targetPathKey: "/Users/bryan/bob/cash.md"
                ]
            ),
            .none
        )
        XCTAssertEqual(
            NotificationService.route(
                forActionIdentifier: UNNotificationDefaultActionIdentifier,
                categoryIdentifier: NotificationService.installRestartCategoryIdentifier,
                userInfo: [
                    NotificationService.targetPathKey: "/Users/bryan/bob/cash.md"
                ]
            ),
            .showCapture
        )
    }

    func testCaptureRoutesRemainObsidianURLsForDefaultClickAndOpenActions() {
        let userInfo: [AnyHashable: Any] = [
            NotificationService.targetPathKey: "/Users/bryan/bob/work.md",
            NotificationService.targetPathsKey: [
                "/Users/bryan/bob/work.md",
                "/Users/bryan/bob/ideas.md",
            ],
        ]

        let defaultClick = NotificationService.route(
            forActionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: NotificationService.captureBatchCategoryIdentifier,
            userInfo: userInfo
        )
        let openNotes = NotificationService.route(
            forActionIdentifier: NotificationService.openNotesActionIdentifier,
            categoryIdentifier: NotificationService.captureBatchCategoryIdentifier,
            userInfo: userInfo
        )
        let openNote = NotificationService.route(
            forActionIdentifier: NotificationService.openNoteActionIdentifier,
            categoryIdentifier: NotificationService.captureCategoryIdentifier,
            userInfo: [
                NotificationService.targetPathKey: "/Users/bryan/bob/cash.md"
            ]
        )
        let dismiss = NotificationService.route(
            forActionIdentifier: UNNotificationDismissActionIdentifier,
            categoryIdentifier: NotificationService.captureCategoryIdentifier,
            userInfo: userInfo
        )

        guard case .openURLs(let defaultURLs) = defaultClick else {
            return XCTFail("default click on a capture notification should open Obsidian URLs")
        }
        guard case .openURLs(let notesURLs) = openNotes else {
            return XCTFail("Open Notes should open Obsidian URLs")
        }
        guard case .openURLs(let noteURLs) = openNote else {
            return XCTFail("Open Note should open an Obsidian URL")
        }
        XCTAssertEqual(defaultURLs.count, 2)
        XCTAssertEqual(notesURLs.count, 2)
        XCTAssertEqual(defaultURLs.map(\.scheme), ["obsidian", "obsidian"])
        XCTAssertEqual(noteURLs.map(\.scheme), ["obsidian"])
        XCTAssertEqual(dismiss, .none)
    }

    func testExecuteShowCaptureInvokesPanelCallbackOnly() {
        var opened: [URL] = []
        var showCaptureCount = 0

        NotificationService.execute(
            .showCapture,
            opener: { opened.append($0) },
            showCapture: { showCaptureCount += 1 }
        )

        XCTAssertEqual(showCaptureCount, 1)
        XCTAssertTrue(opened.isEmpty)
    }

    func testExecuteOpenURLsInvokesOpenerOnly() {
        let urls = [
            URL(string: "obsidian://open?path=work")!,
            URL(string: "obsidian://open?path=ideas")!,
        ]
        var opened: [URL] = []
        var showCaptureCount = 0

        NotificationService.execute(
            .openURLs(urls),
            opener: { opened.append($0) },
            showCapture: { showCaptureCount += 1 }
        )

        XCTAssertEqual(opened, urls)
        XCTAssertEqual(showCaptureCount, 0)
    }

    func testExecuteNoneInvokesNeitherCallback() {
        var opened: [URL] = []
        var showCaptureCount = 0

        NotificationService.execute(
            .none,
            opener: { opened.append($0) },
            showCapture: { showCaptureCount += 1 }
        )

        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(showCaptureCount, 0)
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
        parentText: String? = nil,
        blockID: String? = nil,
        pomodoroStart: PomodoroStartSummary? = nil,
        pomodoroAdjust: PomodoroAdjustSummary? = nil,
        relativeTarget: String? = nil
    ) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: !target.isEmpty,
            routeLabel: routeLabel,
            relativeTarget: relativeTarget ?? routeLabel,
            target: target,
            text: text,
            taskLine: "- [ ] #task \(text)",
            kind: kind,
            created: "2026-08-14",
            scheduled: scheduled,
            placement: "inserted",
            blockID: blockID,
            parentText: parentText,
            pomodoroStart: pomodoroStart,
            pomodoroAdjust: pomodoroAdjust
        )
    }

    private func closeSuccessFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            XCTFail("expected a successful Bob close response")
            throw NSError(domain: "NotificationServiceTests", code: 1)
        }
        return success
    }

    // `dayFileChanged: false` models an idempotent re-toggle onto an already-linked
    // entry, the one path where `CaptureTogglePresentation.dayFileChanged` is false for
    // direction `next` with no later-duplicate cleanup.
    private func toggleCapture(direction: String, dayFileChanged: Bool) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: true,
            route: "cash",
            routeLabel: "cash.md",
            relativeTarget: "cash.md",
            target: "/tmp/bob/cash.md",
            text: "",
            taskLine: "- [*] #task Finish Google Exit Packet! ^goog-exit",
            kind: "task_toggle",
            created: "2026-09-10",
            placement: "toggled",
            blockID: "goog-exit",
            dayFile: "/tmp/bob/2026/20260910.md",
            blockLink: "[[cash#^goog-exit]]",
            toggleDirection: direction,
            previousTaskLine: "- [ ] #task Finish Google Exit Packet! ^goog-exit",
            statusSymbol: "*",
            statusName: "Next",
            previousStatusSymbol: " ",
            previousStatusName: "Ready",
            createsPomodoro: false,
            pomodoroAlreadyLinked: !dayFileChanged,
            removedPomodoroLinks: 0,
            pomodoroSelectorUnused: false
        )
    }

    // A committed `pomodoro_link` capture. `linked` models a fresh insert with a
    // Ready-to-Next promotion; the other actions model an already-queued task.
    private func linkCapture(
        action: String,
        statusChanged: Bool,
        destinationName: String = "BUGS",
        createsPomodoro: Bool = false,
        pomodoroStart: PomodoroStartSummary? = nil
    ) -> CaptureCommandSuccess {
        let changed = statusChanged
        return CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: true,
            route: "sase",
            routeLabel: "sase.md",
            relativeTarget: "sase.md",
            target: "/tmp/bob/sase.md",
            text: "",
            taskLine: changed
                ? "- [*] #task Ready thing ^ready"
                : "- [*] #task Fix deep bug ^deep-fix",
            kind: "pomodoro_link",
            created: "2026-07-10",
            placement: "linked",
            blockID: changed ? "ready" : "deep-fix",
            dayFile: "/tmp/bob/2026/20260710.md",
            blockLink: changed ? "[[sase#^ready]]" : "[[sase#^deep-fix]]",
            previousTaskLine: changed
                ? "- [ ] #task Ready thing ^ready"
                : "- [*] #task Fix deep bug ^deep-fix",
            statusSymbol: "*",
            statusName: "Next",
            previousStatusSymbol: changed ? " " : "*",
            previousStatusName: changed ? "Todo" : "Next",
            pomodoroName: destinationName,
            createsPomodoro: createsPomodoro,
            statusChanged: changed,
            pomodoroLinkAction: action,
            pomodoroLinkSource: action == "linked"
                ? nil
                : PomodoroLinkEndpoint(line: 5, name: "BUGS"),
            pomodoroLinkDestination: PomodoroLinkEndpoint(line: 5, name: destinationName),
            pomodoroStart: pomodoroStart
        )
    }

    private func ensureNextCapture(
        statusChanged: Bool,
        linkAction: String,
        createsPomodoro: Bool = false,
        destinationName: String = "CURRENT"
    ) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: true,
            route: "cash",
            routeLabel: "cash.md",
            relativeTarget: "cash.md",
            target: "/tmp/bob/cash.md",
            text: "",
            taskLine: "- [*] #task Finish Google Exit Packet! ^goog-exit",
            kind: "task_toggle",
            created: "2026-09-10",
            placement: "toggled",
            blockID: "goog-exit",
            dayFile: "/tmp/bob/2026/20260910.md",
            blockLink: "[[cash#^goog-exit]]",
            toggleDirection: "next",
            previousTaskLine: statusChanged
                ? "- [ ] #task Finish Google Exit Packet! ^goog-exit"
                : "- [*] #task Finish Google Exit Packet! ^goog-exit",
            statusSymbol: "*",
            statusName: "Next",
            previousStatusSymbol: statusChanged ? " " : "*",
            previousStatusName: statusChanged ? "Ready" : "Next",
            pomodoroName: destinationName,
            createsPomodoro: createsPomodoro,
            pomodoroAlreadyLinked: linkAction == "already_current",
            removedPomodoroLinks: 0,
            pomodoroSelectorUnused: false,
            toggleBehavior: "ensure_next",
            statusChanged: statusChanged,
            pomodoroLinkAction: linkAction,
            pomodoroLinkSource: PomodoroLinkEndpoint(line: 4, name: "LATER"),
            pomodoroLinkDestination: PomodoroLinkEndpoint(
                line: createsPomodoro ? 5 : 2,
                name: destinationName,
                timeRange: createsPomodoro ? nil : "0900-0930"
            )
        )
    }
}
