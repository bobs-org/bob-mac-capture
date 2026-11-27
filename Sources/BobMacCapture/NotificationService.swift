import AppKit
import CaptureCore
import RefsCore
import UserNotifications

struct NotificationAuthorizationDisplay: Equatable {
    let status: UNAuthorizationStatus
    let displayName: String
    let canRequestAuthorization: Bool

    init(status: UNAuthorizationStatus) {
        self.status = status
        switch status {
        case .notDetermined:
            displayName = "Not requested"
            canRequestAuthorization = true
        case .denied:
            displayName = "Denied — enable in System Settings"
            canRequestAuthorization = false
        case .authorized:
            displayName = "Authorized"
            canRequestAuthorization = false
        case .provisional:
            displayName = "Provisional"
            canRequestAuthorization = false
        case .ephemeral:
            displayName = "Ephemeral"
            canRequestAuthorization = false
        @unknown default:
            displayName = "Unknown"
            canRequestAuthorization = false
        }
    }
}

/// Tracks wake records withdrawn while a Notification Center add is in
/// flight. A late completion removes its own record instead of resurrecting
/// it after acknowledgement, expiry, or a vault change.
final class SnoozeWakeRecordWithdrawalLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var withdrawnIDs: Set<String> = []

    func withdraw(_ wakeID: String) {
        lock.lock()
        defer { lock.unlock() }
        withdrawnIDs.insert(wakeID)
        while withdrawnIDs.count > SnoozeWakeHandledStore.maxEntries {
            if let oldest = withdrawnIDs.first {
                withdrawnIDs.remove(oldest)
            } else {
                break
            }
        }
    }

    func contains(_ wakeID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return withdrawnIDs.contains(wakeID)
    }

    func removeLateAddIfWithdrawn(_ wakeID: String, remove: () -> Void) {
        guard contains(wakeID) else { return }
        remove()
    }
}

@MainActor
final class NotificationService: NSObject, ObservableObject {
    nonisolated static let openNoteActionIdentifier = "org.bobs.bob-mac-capture.open-note"
    nonisolated static let openNotesActionIdentifier = "org.bobs.bob-mac-capture.open-notes"
    nonisolated static let captureActionIdentifier = "org.bobs.bob-mac-capture.install-restart.capture"
    nonisolated static let captureCategoryIdentifier = "org.bobs.bob-mac-capture.capture"
    nonisolated static let captureBatchCategoryIdentifier = "org.bobs.bob-mac-capture.capture-batch"
    nonisolated static let installRestartCategoryIdentifier = "org.bobs.bob-mac-capture.install-restart"
    nonisolated static let refsScanCategoryIdentifier = "org.bobs.bob-mac-capture.refs-scan"
    nonisolated static let refsScanShowActionIdentifier = "org.bobs.bob-mac-capture.refs-scan.show"
    nonisolated static let refsPDFUpdatesThreadIdentifier = "org.bobs.bob-mac-capture.refs-pdf-updates"
    /// Stable Notification Center record for one wake batch. The request
    /// identifier is `snooze-woken-<wake_id>`; the thread is shared.
    nonisolated static let snoozeWakeCategoryIdentifier = "org.bobs.bob-mac-capture.snooze-wake"
    nonisolated static let snoozeWakeOpenActionIdentifier = "org.bobs.bob-mac-capture.snooze-wake.open"
    nonisolated static let snoozeWakeIDKey = "snoozeWakeID"
    nonisolated static let snoozeVaultRootKey = "snoozeVaultRoot"
    nonisolated static let snoozeDateKey = "snoozeDate"
    nonisolated static let snoozeTaskRouteKey = "snoozeTaskRoute"
    nonisolated static let snoozeTaskLineKey = "snoozeTaskLine"
    nonisolated static let snoozeTaskBlockIDKey = "snoozeTaskBlockID"
    nonisolated static let snoozeRecordThreadIdentifier = "snooze"
    nonisolated static let targetPathKey = "targetPath"
    nonisolated static let notePathKey = "notePath"
    nonisolated static let targetPathsKey = "targetPaths"
    nonisolated static let openPlanKey = "openPlan"
    nonisolated static let jumpPlanKey = "jumpPlan"
    nonisolated static let openErrorKey = "openError"
    nonisolated static let foregroundPresentationOptions: UNNotificationPresentationOptions = [
        .banner, .sound, .list,
    ]
    /// Silent record presentation: list-only, never banners, sounds, or badges
    /// while the app is frontmost. Other categories keep the banner path.
    nonisolated static let snoozeForegroundPresentationOptions: UNNotificationPresentationOptions = [
        .list
    ]

    @Published private(set) var authorization = NotificationAuthorizationDisplay(status: .notDetermined)

    private let center: UNUserNotificationCenter
    private let opener: (URL) -> Void
    private let showCapture: () -> Void
    private let showRefs: (String?) -> Void
    /// Acknowledgement hook for the shared wake lifecycle. Fired when the
    /// Default click or Open action runs on a snooze record; the coordinator
    /// owns the beacon/record clearing that follows task navigation.
    var onSnoozeWakeOpened: (String) -> Void = { _ in }
    private let snoozeWakeWithdrawalLedger = SnoozeWakeRecordWithdrawalLedger()

    init(
        center: UNUserNotificationCenter = .current(),
        opener: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        showCapture: @escaping () -> Void = {},
        showRefs: @escaping (String?) -> Void = { _ in }
    ) {
        self.center = center
        self.opener = opener
        self.showCapture = showCapture
        self.showRefs = showRefs
        super.init()
        // The delegate must be assigned before any authorization request so a foreground
        // notification delivered during the same launch is never silently suppressed.
        center.delegate = self
        center.setNotificationCategories(Self.captureCategories())
    }

    func requestAuthorization() {
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorizationStatus()
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorization = NotificationAuthorizationDisplay(status: settings.authorizationStatus)
    }

    func notifyCaptureSuccess(
        captures: [CaptureCommandSuccess],
        globalDestination: CaptureGlobalDestination? = nil,
        openPlan: CaptureOpenPlan? = nil,
        jump: CaptureJump? = nil,
        jumpLost: Bool = false
    ) {
        Task {
            try? await add(Self.successContent(
                captures: captures,
                globalDestination: globalDestination,
                openPlan: openPlan,
                jump: jump,
                jumpLost: jumpLost
            ))
        }
    }

    func notifyCaptureOpenFailure(message: String) {
        Task {
            try? await add(Self.openFailureContent(message: message))
        }
    }

    func notifyCaptureFailure(message: String) {
        Task {
            try? await add(Self.failureContent(message: message))
        }
    }

    // The status menu closes the moment Restart is clicked, so a refusal that leaves
    // the app running needs to be visible without opening Settings. This is kept
    // distinct from `notifyCaptureFailure` so the notification isn't mislabelled
    // "Capture failed".
    func notifyRestartFailure(message: String) {
        Task {
            try? await add(Self.restartFailureContent(message: message))
        }
    }

    // Best-effort confirmation that an install-triggered replacement reached a usable
    // launch point. Must not request authorization; missing or denied permission is
    // silent and non-fatal, matching the other notify paths.
    func notifyInstallComplete() {
        Task {
            try? await add(Self.installCompleteContent())
        }
    }

    /// Posts the hidden-panel scan outcome: added titles, a partial
    /// failure, or a hard failure. A quiet outcome (nothing new while
    /// hidden) posts nothing, and missing or denied permission stays
    /// silent like every other notify path.
    func notifyRefsScan(_ outcome: RefsScanOutcome) {
        guard let content = Self.refsScanContent(outcome) else {
            return
        }
        Task {
            try? await add(content)
        }
    }

    /// Posts grouped, passive open-PDF update notices. Permission denial
    /// stays silent like every other notify path.
    func notifyRefsPDFUpdates(_ notices: [RefsPDFUpdateNotification]) {
        for notice in notices {
            Task {
                try? await add(Self.refsPDFUpdateContent(notice))
            }
        }
    }

    /// Confirms a rename that completed while Bob Refs was hidden.
    /// Permission denial remains silent, matching the other notification
    /// paths.
    func notifyRefsRename(_ response: RefsRenameResponse) {
        guard let stem = response.to?.stem else { return }
        Task {
            try? await add(Self.refsRenameContent(stem: stem))
        }
    }

    /// Reports a rename that failed while Bob Refs was hidden, carrying
    /// the same inline message the card shows.
    func notifyRefsRenameFailure(message: String) {
        Task {
            try? await add(Self.refsRenameFailureContent(message: message))
        }
    }

    /// Confirms a Today link that completed while Bob Refs was hidden.
    func notifyRefsTodayLink(_ response: RefsTodayLinkResponse, title: String) {
        guard let content = Self.refsTodayLinkContent(response: response, title: title) else {
            return
        }
        Task { try? await add(content) }
    }

    /// Reports a Today-link failure that landed while the panel was hidden.
    func notifyRefsTodayLinkFailure(message: String, hint: String?) {
        Task {
            try? await add(Self.refsTodayLinkFailureContent(message: message, hint: hint))
        }
    }

    func sendTestNotification() async throws {
        try await add(Self.testContent())
    }

    /// Posts one silent wake record with the stable `snooze-woken-<wake_id>`
    /// identifier. Queries authorization without prompting: denied or
    /// not-determined skips the record and keeps the HUD functional. A wake
    /// ID withdrawn before the add completes skips the post so a late add
    /// cannot resurrect a cleared record.
    func postSnoozeWakeRecord(batch: SnoozeWakeNoticeBatch, presentation: SnoozeWakeNoticePresentation) {
        CaptureSignpost.event(CaptureSignpost.snoozePresent)
        let wakeID = batch.wakeID
        Task {
            let settings = await center.notificationSettings()
            guard
                Self.canPostSnoozeWakeRecord(
                    authorizationStatus: settings.authorizationStatus
                )
            else {
                return
            }
            guard !snoozeWakeWithdrawalLedger.contains(wakeID) else {
                return
            }
            let content = Self.snoozeWakeContent(batch: batch, presentation: presentation)
            do {
                try await add(content, identifier: presentation.recordID)
            } catch {
                return
            }
            // A withdraw that landed while the add was in flight wins: remove
            // the just-added record instead of leaving a resurrected one.
            snoozeWakeWithdrawalLedger.removeLateAddIfWithdrawn(wakeID) {
                center.removeDeliveredNotifications(withIdentifiers: [presentation.recordID])
                center.removePendingNotificationRequests(withIdentifiers: [presentation.recordID])
            }
        }
    }

    /// Withdraws one wake record from delivered and pending stores and marks
    /// the ID withdrawn so a late add cannot resurrect it.
    func withdrawSnoozeWakeRecord(wakeID: String) {
        CaptureSignpost.event(CaptureSignpost.snoozeWithdraw)
        snoozeWakeWithdrawalLedger.withdraw(wakeID)
        let recordID = SnoozeWakeNoticePresentation.recordID(wakeID: wakeID)
        center.removeDeliveredNotifications(withIdentifiers: [recordID])
        center.removePendingNotificationRequests(withIdentifiers: [recordID])
    }

    /// Reconciles existing snooze records at launch: withdraws every
    /// `snooze-woken-*` delivered or pending ID not in `activeWakeIDs`.
    /// Unrelated notifications are never touched.
    func reconcileSnoozeRecords(activeWakeIDs: Set<String>) {
        Task {
            let delivered: [String] = await withCheckedContinuation { continuation in
                center.getDeliveredNotifications { notifications in
                    continuation.resume(returning: notifications.map(\.request.identifier))
                }
            }
            let pending: [String] = await withCheckedContinuation { continuation in
                center.getPendingNotificationRequests { requests in
                    continuation.resume(returning: requests.map(\.identifier))
                }
            }
            let staleIDs = Self.snoozeWakeRecordIdentifiersToWithdraw(
                deliveredIdentifiers: delivered,
                pendingIdentifiers: pending,
                activeWakeIDs: activeWakeIDs
            )
            for identifier in staleIDs {
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
            }
        }
    }

    nonisolated static func canPostSnoozeWakeRecord(
        authorizationStatus: UNAuthorizationStatus
    ) -> Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    nonisolated static func snoozeWakeRecordIdentifiersToWithdraw(
        deliveredIdentifiers: [String],
        pendingIdentifiers: [String],
        activeWakeIDs: Set<String>
    ) -> Set<String> {
        let prefix = "snooze-woken-"
        let activeIDs = Set(activeWakeIDs.map { "\(prefix)\($0)" })
        return Set(
            (deliveredIdentifiers + pendingIdentifiers).filter { identifier in
                identifier.hasPrefix(prefix) && !activeIDs.contains(identifier)
            })
    }

    private func add(_ content: UNMutableNotificationContent) async throws {
        try await add(content, identifier: UUID().uuidString)
    }

    private func add(_ content: UNMutableNotificationContent, identifier: String) async throws {
        try await CaptureSignpost.measure("notification-schedule") {
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                center.add(request) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    // Pure content/category/routing builders are `nonisolated`: they touch no actor
    // state, so callers (including synchronous, non-MainActor unit tests) can use them
    // without hopping onto the main actor.
    nonisolated static func successContent(
        captures: [CaptureCommandSuccess],
        globalDestination: CaptureGlobalDestination? = nil,
        openPlan: CaptureOpenPlan? = nil,
        jump: CaptureJump? = nil,
        jumpLost: Bool = false
    ) -> UNMutableNotificationContent {
        let openPlan = openPlan ?? CaptureOpenPlan(openNotes: nil, captures: captures)
        let presentation = successPresentation(
            captures: captures,
            globalDestination: globalDestination,
            openPlan: openPlan
        )
        let content = UNMutableNotificationContent()
        content.title = presentation.title
        content.subtitle = presentation.subtitle
        content.body = presentation.body
        let requirementLines = requirementOutcomeMessages(from: captures)
        if !requirementLines.isEmpty {
            content.body +=
                (content.body.isEmpty ? "" : "\n")
                + requirementLines.joined(separator: "\n")
        }
        content.sound = .default
        // A landed pin adds the jump receipt line and retargets the
        // default click at the one-entry jump plan. A lost pin keeps the
        // open-notes target and adds the lost-target line instead.
        let jumpPlan: CaptureOpenPlan? = {
            guard let landing = jump?.landing, !landing.path.isEmpty else { return nil }
            let plan = CaptureOpenPlan(openNotes: [landing], captures: [])
            return plan.isEmpty ? nil : plan
        }()
        if let jump, !jump.label.isEmpty, jumpPlan != nil {
            content.body += (content.body.isEmpty ? "" : "\n") + "↗ \(jump.label)"
        } else if jumpLost, let jump, !jump.label.isEmpty {
            content.body += (content.body.isEmpty ? "" : "\n")
                + "↗ Couldn't find “\(jump.label)” to jump to"
        }
        if !openPlan.isEmpty {
            content.categoryIdentifier = captureOpenPlanCategoryIdentifier(count: openPlan.notes.count)
            var userInfo: [AnyHashable: Any] = [
                openPlanKey: openPlan.notificationPayload,
                targetPathKey: presentation.targetPaths[0],
                targetPathsKey: presentation.targetPaths,
            ]
            if let jumpPlan {
                userInfo[jumpPlanKey] = jumpPlan.notificationPayload
            }
            content.userInfo = userInfo
        }
        return content
    }

    nonisolated static func openFailureContent(message: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Captured, but Obsidian didn't open"
        content.body = message
        content.sound = .default
        content.userInfo = [openErrorKey: message]
        return content
    }

    nonisolated static func successContent(
        routeLabel: String,
        targetPath: String?
    ) -> UNMutableNotificationContent {
        successContent(captures: [
            CaptureCommandSuccess(
                ok: true,
                dryRun: false,
                routed: targetPath != nil,
                routeLabel: routeLabel,
                relativeTarget: routeLabel,
                target: targetPath ?? "",
                text: "",
                taskLine: "",
                kind: "task",
                created: "",
                placement: "inserted"
            ),
        ])
    }

    nonisolated static func failureContent(message: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Capture failed"
        content.body = message
        content.sound = .default
        return content
    }

    nonisolated static func restartFailureContent(message: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Restart failed"
        content.body = message
        content.sound = .default
        return content
    }

    nonisolated static func testContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Bob Mac Capture"
        content.body = "This is a test notification."
        content.sound = .default
        return content
    }

    nonisolated static func installCompleteContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Install complete"
        content.body = "Bob Mac Capture restarted successfully."
        content.sound = .default
        content.categoryIdentifier = installRestartCategoryIdentifier
        return content
    }

    nonisolated static func captureCategory() -> UNNotificationCategory {
        let openNote = UNNotificationAction(
            identifier: openNoteActionIdentifier,
            title: "Open Note",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: captureCategoryIdentifier,
            actions: [openNote],
            intentIdentifiers: [],
            options: []
        )
    }

    nonisolated static func captureBatchCategory() -> UNNotificationCategory {
        let openNotes = UNNotificationAction(
            identifier: openNotesActionIdentifier,
            title: "Open Notes",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: captureBatchCategoryIdentifier,
            actions: [openNotes],
            intentIdentifiers: [],
            options: []
        )
    }

    nonisolated static func captureOpenPlanCategory(count: Int) -> UNNotificationCategory {
        let count = min(max(count, 1), 8)
        let noun = count == 1 ? "Note" : "Notes"
        let action = UNNotificationAction(
            identifier: openNotesActionIdentifier,
            title: "Open \(count) \(noun)",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: captureOpenPlanCategoryIdentifier(count: count),
            actions: [action],
            intentIdentifiers: [],
            options: []
        )
    }

    nonisolated static func captureOpenPlanCategoryIdentifier(count: Int) -> String {
        "org.bobs.bob-mac-capture.capture-open-plan-\(min(max(count, 1), 8))"
    }

    nonisolated static func installRestartCategory() -> UNNotificationCategory {
        let capture = UNNotificationAction(
            identifier: captureActionIdentifier,
            title: "Capture",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: installRestartCategoryIdentifier,
            actions: [capture],
            intentIdentifiers: [],
            options: []
        )
    }

    nonisolated static func captureCategories() -> Set<UNNotificationCategory> {
        var categories: Set<UNNotificationCategory> = [
            captureCategory(),
            captureBatchCategory(),
            installRestartCategory(),
            refsScanCategory(),
            snoozeWakeCategory(),
        ]
        for count in 1...8 {
            categories.insert(captureOpenPlanCategory(count: count))
        }
        return categories
    }

    /// Foreground Open action for one silent wake record. Default click and
    /// Open share the same task navigation and acknowledgement path.
    nonisolated static func snoozeWakeCategory() -> UNNotificationCategory {
        let open = UNNotificationAction(
            identifier: snoozeWakeOpenActionIdentifier,
            title: "Open",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: snoozeWakeCategoryIdentifier,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
    }

    /// Silent wake record content: stable ID, shared thread, passive, no
    /// sound. Title is the shared headline; body names the visible titles,
    /// remaining count, and wake-time provenance. Metadata only in logs.
    nonisolated static func snoozeWakeContent(
        batch: SnoozeWakeNoticeBatch,
        presentation: SnoozeWakeNoticePresentation
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = presentation.headline
        var lines = presentation.visibleTitles
        if presentation.remainingCount > 0 {
            lines.append("+ \(presentation.remainingCount) more")
        }
        lines.append(presentation.subtitleText)
        content.body = lines.joined(separator: "\n")
        content.sound = nil
        content.badge = nil
        content.interruptionLevel = .passive
        content.threadIdentifier = snoozeRecordThreadIdentifier
        content.categoryIdentifier = snoozeWakeCategoryIdentifier
        var userInfo: [AnyHashable: Any] = [
            snoozeWakeIDKey: batch.wakeID,
            snoozeVaultRootKey: batch.vaultRoot ?? "",
            snoozeDateKey: batch.date,
        ]
        if let first = presentation.actionableRows.first {
            if let route = first.route {
                userInfo[snoozeTaskRouteKey] = route
            }
            if let line = first.line {
                userInfo[snoozeTaskLineKey] = line
            }
            if let blockID = first.blockID {
                userInfo[snoozeTaskBlockIDKey] = blockID
            }
        }
        content.userInfo = userInfo
        return content
    }

    /// Task URL for a snooze record's Default/Open action. Validates the
    /// stored vault-relative route against the stored vault root, never a
    /// shell-composed URL.
    nonisolated static func snoozeWakeTaskURL(userInfo: [AnyHashable: Any]) -> URL? {
        guard let wakeID = userInfo[snoozeWakeIDKey] as? String, !wakeID.isEmpty,
            let vaultRoot = userInfo[snoozeVaultRootKey] as? String, !vaultRoot.isEmpty,
            let route = userInfo[snoozeTaskRouteKey] as? String, !route.isEmpty,
            let line = userInfo[snoozeTaskLineKey] as? Int, line > 0
        else {
            return nil
        }
        guard !route.hasPrefix("/"), !route.contains("\\"), !route.contains(":"),
            !route.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            return nil
        }
        let root = URL(fileURLWithPath: vaultRoot, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let file = root.appendingPathComponent(route).standardizedFileURL
            .resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.path.hasPrefix(prefix) else {
            return nil
        }
        let rawBlockID = userInfo[snoozeTaskBlockIDKey] as? String
        let blockID = rawBlockID.map { $0.hasPrefix("^") ? String($0.dropFirst()) : $0 }
        return ObsidianOpenURL.taskGotoURL(
            path: file.path, line: line, ref: nil, blockID: blockID)
    }

    /// The hidden-panel scan content from the §8 strings: nil when the
    /// outcome is quiet (succeeded with nothing created).
    nonisolated static func refsScanContent(
        _ outcome: RefsScanOutcome
    ) -> UNMutableNotificationContent? {
        guard let presentation = RefsScanPresentation.notification(outcome) else {
            return nil
        }
        let content = UNMutableNotificationContent()
        content.title = presentation.title
        content.body = presentation.body
        content.sound = .default
        content.categoryIdentifier = refsScanCategoryIdentifier
        return content
    }

    nonisolated static func refsPDFUpdateContent(
        _ notice: RefsPDFUpdateNotification
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        if let subtitle = notice.subtitle {
            content.subtitle = subtitle
        }
        content.body = notice.body
        content.sound = nil
        content.interruptionLevel = .passive
        content.threadIdentifier = refsPDFUpdatesThreadIdentifier
        content.categoryIdentifier = refsScanCategoryIdentifier
        if !notice.notePath.isEmpty {
            content.userInfo = [notePathKey: notice.notePath]
        }
        return content
    }

    nonisolated static func refsRenameContent(stem: String) -> UNMutableNotificationContent {
        let text = RefsRenamePresentation.notification(stem: stem)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        return content
    }

    nonisolated static func refsRenameFailureContent(
        message: String
    ) -> UNMutableNotificationContent {
        let text = RefsRenamePresentation.failureNotification(message: message)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        return content
    }

    nonisolated static func refsTodayLinkContent(
        response: RefsTodayLinkResponse,
        title: String
    ) -> UNMutableNotificationContent? {
        guard let presentation = RefsTodayLinkPresentation.notification(
            response: response, title: title
        ) else {
            return nil
        }
        let content = UNMutableNotificationContent()
        content.title = presentation.title
        content.body = presentation.body
        return content
    }

    nonisolated static func refsTodayLinkFailureContent(
        message: String,
        hint: String?
    ) -> UNMutableNotificationContent {
        let presentation = RefsTodayLinkPresentation.failureNotification(
            message: message, hint: hint
        )
        let content = UNMutableNotificationContent()
        content.title = presentation.title
        content.body = presentation.body
        return content
    }

    nonisolated static func refsScanCategory() -> UNNotificationCategory {
        let show = UNNotificationAction(
            identifier: refsScanShowActionIdentifier,
            title: "Show in Bob Refs",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: refsScanCategoryIdentifier,
            actions: [show],
            intentIdentifiers: [],
            options: []
        )
    }

    // Body click and Capture on the install-restart category show the capture panel.
    // The default click and the Show action on a refs-scan notification show Bob Refs.
    // Capture notifications keep their existing default-click / Open Note / Open Notes
    // Obsidian routing. A snooze record's Default click and Open share one task
    // navigation path; dismissal and mismatched category/action combinations are
    // no-ops. Takes plain values instead of a live UNNotificationResponse, which
    // the SDK gives no public initializer for, so this routing decision stays
    // unit-testable.
    nonisolated static func route(
        forActionIdentifier actionIdentifier: String,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> NotificationRoute {
        if actionIdentifier == UNNotificationDismissActionIdentifier {
            return .none
        }
        if categoryIdentifier == snoozeWakeCategoryIdentifier {
            guard
                actionIdentifier == UNNotificationDefaultActionIdentifier
                    || actionIdentifier == snoozeWakeOpenActionIdentifier
            else {
                return .none
            }
            guard let wakeID = userInfo[snoozeWakeIDKey] as? String, !wakeID.isEmpty,
                let url = snoozeWakeTaskURL(userInfo: userInfo)
            else {
                // No usable task target: still acknowledge the batch so the
                // beacon/record lifecycle clears, but open nothing.
                if let wakeID = userInfo[snoozeWakeIDKey] as? String, !wakeID.isEmpty {
                    return .openSnoozeWake(wakeID: wakeID, urls: [])
                }
                return .none
            }
            guard let wakeID = userInfo[snoozeWakeIDKey] as? String, !wakeID.isEmpty else {
                return .none
            }
            return .openSnoozeWake(wakeID: wakeID, urls: [url])
        }
        if categoryIdentifier == refsScanCategoryIdentifier {
            guard
                actionIdentifier == UNNotificationDefaultActionIdentifier
                    || actionIdentifier == refsScanShowActionIdentifier
            else {
                return .none
            }
            if let notePath = userInfo[notePathKey] as? String, !notePath.isEmpty {
                return .showRefsSelecting(notePath: notePath)
            }
            return .showRefs
        }
        if categoryIdentifier == installRestartCategoryIdentifier {
            guard
                actionIdentifier == UNNotificationDefaultActionIdentifier
                    || actionIdentifier == captureActionIdentifier
            else {
                return .none
            }
            return .showCapture
        }
        let urls = targetURLs(forActionIdentifier: actionIdentifier, userInfo: userInfo)
        if urls.isEmpty {
            return .none
        }
        return .openURLs(urls)
    }

    nonisolated static func execute(
        _ route: NotificationRoute,
        opener: (URL) -> Void,
        showCapture: () -> Void,
        showRefs: (String?) -> Void = { _ in },
        onSnoozeWakeOpened: (String) -> Void = { _ in }
    ) {
        switch route {
        case .none:
            return
        case .showCapture:
            showCapture()
        case .showRefs:
            showRefs(nil)
        case .showRefsSelecting(let notePath):
            showRefs(notePath)
        case .openURLs(let urls):
            for url in urls {
                opener(url)
            }
        case .openSnoozeWake(let wakeID, let urls):
            for url in urls {
                opener(url)
            }
            onSnoozeWakeOpened(wakeID)
        }
    }

    // Both the explicit Open Note action and clicking the notification body itself open
    // the target; dismissing it must not. Takes plain values instead of a live
    // UNNotificationResponse, which the SDK gives no public initializer for, so this
    // routing decision stays unit-testable.
    nonisolated static func targetURL(
        forActionIdentifier actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> URL? {
        targetURLs(forActionIdentifier: actionIdentifier, userInfo: userInfo).first
    }

    nonisolated static func targetURLs(
        forActionIdentifier actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> [URL] {
        guard
            actionIdentifier == UNNotificationDefaultActionIdentifier
                || actionIdentifier == openNoteActionIdentifier
                || actionIdentifier == openNotesActionIdentifier
        else {
            return []
        }

        // A landed jump pin retargets the default click at the
        // one-entry jump plan. The explicit Open Notes action still opens
        // the captured notes through the open-plan payload below.
        if actionIdentifier == UNNotificationDefaultActionIdentifier,
           let payload = userInfo[jumpPlanKey] as? [[String: Any]],
           let plan = CaptureOpenPlan(notificationPayload: payload),
           let url = ObsidianOpenURL.openNotesURL(for: plan)
        {
            return [url]
        }

        if let payload = userInfo[openPlanKey] as? [[String: Any]],
           let plan = CaptureOpenPlan(notificationPayload: payload),
           let url = ObsidianOpenURL.openNotesURL(for: plan)
        {
            return [url]
        }

        let targetPaths: [String]
        if let paths = userInfo[targetPathsKey] as? [String] {
            targetPaths = paths
        } else if let targetPath = userInfo[targetPathKey] as? String {
            targetPaths = [targetPath]
        } else {
            targetPaths = []
        }
        return orderedUniquePaths(targetPaths)
            .compactMap(ObsidianOpenURL.url(forAbsolutePath:))
    }

    nonisolated private static func successPresentation(
        captures: [CaptureCommandSuccess],
        globalDestination: CaptureGlobalDestination?,
        openPlan: CaptureOpenPlan
    ) -> CaptureNotificationPresentation {
        let nonemptyCaptures = captures.isEmpty ? [] : captures
        let targetPaths = openPlan.notes.map(\.path)
        guard nonemptyCaptures.count != 1, !nonemptyCaptures.isEmpty else {
            guard let capture = nonemptyCaptures.first else {
                return CaptureNotificationPresentation(
                    title: "Captured",
                    subtitle: "",
                    body: "",
                    targetPaths: targetPaths
                )
            }
            if let toggle = CaptureTogglePresentation(capture: capture) {
                return singlePresentation(
                    title: toggle.notificationTitle,
                    subtitle: toggle.routeDestinationLabel,
                    body: toggle.notificationBody,
                    capture: capture,
                    targetPaths: targetPaths
                )
            }
            if let complete = CaptureTaskCompletePresentation(capture: capture) {
                return singlePresentation(
                    title: complete.notificationTitle,
                    subtitle: complete.destinationLabel,
                    body: complete.notificationBody,
                    capture: capture,
                    targetPaths: targetPaths
                )
            }
            if let reset = CapturePomodoroResetPresentation(capture: capture) {
                return CaptureNotificationPresentation(
                    title: reset.notificationTitle,
                    subtitle: displayLabel(for: capture),
                    body: reset.notificationBody,
                    targetPaths: targetPaths
                )
            }
            if let past = CapturePomodoroPastPresentation(capture: capture) {
                return CaptureNotificationPresentation(
                    title: past.notificationTitle,
                    subtitle: displayLabel(for: capture),
                    body: past.notificationBody,
                    targetPaths: targetPaths
                )
            }
            if let close = CapturePomodoroClosePresentation(capture: capture) {
                return singlePresentation(
                    title: close.notificationTitle,
                    subtitle: displayLabel(for: capture),
                    body: close.notificationBody,
                    capture: capture,
                    targetPaths: targetPaths
                )
            }
            if CapturePomodoroStartPresentation.isSessionStart(capture),
               let start = CapturePomodoroStartPresentation(capture: capture)
            {
                return CaptureNotificationPresentation(
                    title: start.notificationTitle,
                    subtitle: displayLabel(for: capture),
                    body: start.notificationBody,
                    targetPaths: targetPaths
                )
            }
            if let link = CapturePomodoroLinkPresentation(capture: capture) {
                return CaptureNotificationPresentation(
                    title: link.notificationTitle,
                    subtitle: link.routeDestinationLabel,
                    body: link.notificationBody,
                    targetPaths: targetPaths
                )
            }
            if let linkGuard = CaptureLinkGuardPresentation(capture: capture) {
                return CaptureNotificationPresentation(
                    title: linkGuard.notificationTitle,
                    subtitle: displayLabel(for: capture),
                    body: linkGuard.notificationBody,
                    targetPaths: targetPaths
                )
            }
            if let ref = CaptureRefPresentation(capture: capture) {
                return CaptureNotificationPresentation(
                    title: ref.notificationTitle,
                    subtitle: ref.destinationLabel,
                    body: ref.notificationBody,
                    targetPaths: targetPaths
                )
            }
            if let relationship = CaptureRelationshipPresentation(capture: capture).notification {
                return singlePresentation(
                    title: relationship.title,
                    subtitle: relationship.subtitle,
                    body: relationship.body,
                    capture: capture,
                    targetPaths: targetPaths
                )
            }
            if let transfer = CaptureTransferPresentation(capture: capture) {
                return singlePresentation(
                    title: transfer.notificationTitle,
                    subtitle: displayLabel(for: capture),
                    body: transfer.notificationBody,
                    capture: capture,
                    targetPaths: targetPaths
                )
            }
            if let mergeIn = CaptureMergeInPresentation(capture: capture) {
                return singlePresentation(
                    title: mergeIn.notificationTitle,
                    subtitle: displayLabel(for: capture),
                    body: mergeIn.notificationBody,
                    capture: capture,
                    targetPaths: targetPaths
                )
            }
            if let moves = CaptureProjectNoteMovePresentation(capture: capture) {
                return singlePresentation(
                    title: moves.notificationTitle,
                    subtitle: displayLabel(for: capture),
                    body: ([moves.notificationDetail, singleCaptureBody(capture)]
                        .filter { !$0.isEmpty }.joined(separator: "\n")),
                    capture: capture,
                    targetPaths: targetPaths
                )
            }
            if let notePull = capture.notePull,
               let presentation = CaptureNotePullPresentation(
                   notePull: notePull,
                   group: capture.pullIn?.groups.first(where: {
                       $0.group == "note_pull" && ($0.note == notePull.note || $0.note == nil)
                   })
               ),
               !presentation.notificationBody.isEmpty
            {
                return CaptureNotificationPresentation(
                    title: presentation.notificationTitle,
                    subtitle: displayLabel(for: capture),
                    body: presentation.notificationBody,
                    targetPaths: targetPaths
                )
            }
            if let summary = capture.recordNote,
               capture.kind == "record_note" || capture.kind == "record_update"
            {
                return singlePresentation(
                    title: CaptureRecordPreviewPresentation.notificationTitle(
                        for: summary
                    ),
                    subtitle: displayLabel(for: capture),
                    body: CaptureRecordPreviewPresentation.notificationBody(
                        for: summary
                    ),
                    capture: capture,
                    targetPaths: targetPaths
                )
            }
            if CaptureNotebookPresentation.isNotebook(capture) {
                return singlePresentation(
                    title: CaptureNotebookPresentation.notificationTitle(for: capture),
                    subtitle: displayLabel(for: capture),
                    body: CaptureNotebookPresentation.notificationBody(for: capture),
                    capture: capture,
                    targetPaths: targetPaths
                )
            }
            let kind = friendlyKindLabel(capture.kind)
            return singlePresentation(
                title: "\(kind) captured",
                // Adjustments and shifts are unrouted daily-note edits, so fall
                // back to the relative target (the day file) when there is no
                // route label rather than notifying with an empty subtitle.
                subtitle: displayLabel(for: capture),
                body: singleCaptureBody(capture),
                capture: capture,
                targetPaths: targetPaths
            )
        }

        if let globalDestination {
            return globalBatchPresentation(
                captures: nonemptyCaptures,
                globalDestination: globalDestination,
                targetPaths: targetPaths
            )
        }

        if let past = CapturePomodoroPastPresentation(captures: nonemptyCaptures),
            past.isHomogeneous
        {
            let summary = pulledInSummary(captures: nonemptyCaptures)
            let heldLines = batchHeldLines(for: nonemptyCaptures)
            return CaptureNotificationPresentation(
                title: past.notificationTitle,
                subtitle: summary,
                body: ([past.notificationBody, summary] + heldLines)
                    .filter { !$0.isEmpty }.joined(separator: "\n"),
                targetPaths: targetPaths
            )
        }

        if nonemptyCaptures.allSatisfy({ CaptureTaskCompletePresentation(capture: $0) != nil }) {
            let lines = nonemptyCaptures.enumerated().map { index, capture in
                let presentation = CaptureTaskCompletePresentation(capture: capture)
                let detail = presentation.map { "\($0.destinationLabel): \($0.transitionText)" } ?? batchLineText(capture)
                return "\(index + 1). \(detail)"
            }
            let summaryParts = [
                "\(nonemptyCaptures.count) completed tasks",
                pulledInSummary(captures: nonemptyCaptures),
            ].filter { !$0.isEmpty }
            let summary = summaryParts.joined(separator: " · ")
            let heldLines = batchHeldLines(for: nonemptyCaptures)
            return CaptureNotificationPresentation(
                title: "Completed \(nonemptyCaptures.count) tasks",
                subtitle: summary,
                body: ([summary] + lines + heldLines).filter { !$0.isEmpty }.joined(separator: "\n"),
                targetPaths: targetPaths
            )
        }

        let kindSummary = pluralSummary(
            labels: nonemptyCaptures.map { friendlyKindLabel($0.kind) }
        )
        let destinationSummary = destinationCountSummary(
            captures: nonemptyCaptures,
            targetPathCount: targetPaths.count
        )
        let kindDestinationSummary = [kindSummary, destinationSummary]
            .filter { !$0.isEmpty }
            .joined(separator: " across ")
        let summary = [kindDestinationSummary, pulledInSummary(captures: nonemptyCaptures)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let lines = nonemptyCaptures.enumerated().map { index, capture in
            let scheduled = capture.scheduled.map { " scheduled \($0)" } ?? ""
            let suffix = "\(scheduled)\(startedSuffix(for: capture))"
                + "\(adjustedSuffix(for: capture))\(shiftedSuffix(for: capture))\(resetSuffix(for: capture))\(closedSuffix(for: capture))"
            return "\(index + 1). \(friendlyKindLabel(capture.kind)) -> \(capture.routeLabel): "
                + "\(batchLineText(capture))\(suffix)"
        }
        let heldLines = batchHeldLines(for: nonemptyCaptures)
        return CaptureNotificationPresentation(
            title: "\(nonemptyCaptures.count) items captured",
            subtitle: summary,
            body: ([summary] + lines + heldLines).filter { !$0.isEmpty }.joined(separator: "\n"),
            targetPaths: targetPaths
        )
    }

    nonisolated private static func globalBatchPresentation(
        captures: [CaptureCommandSuccess],
        globalDestination: CaptureGlobalDestination,
        targetPaths: [String]
    ) -> CaptureNotificationPresentation {
        let kindSummary = pluralSummary(
            labels: captures.map { friendlyKindLabel($0.kind) }
        )
        let overrideCount = captures.filter {
            !captureUsesGlobalDestination($0, globalDestination)
        }.count
        let overrideSummary = overrideCount == 0
            ? ""
            : "\(overrideCount) local override\(overrideCount == 1 ? "" : "s")"
        let destinationLabel = globalDestination.destinationLabel
        let kindDestinationSummary = [kindSummary, destinationLabel, overrideSummary]
            .filter { !$0.isEmpty }
            .joined(separator: " \u{00b7} ")
        let summary = [kindDestinationSummary, pulledInSummary(captures: captures)]
            .filter { !$0.isEmpty }
            .joined(separator: " \u{00b7} ")
        let lines = captures.enumerated().map { index, capture in
            let scheduled = capture.scheduled.map { " scheduled \($0)" } ?? ""
            let override = captureUsesGlobalDestination(capture, globalDestination)
                ? ""
                : " \u{2192} \(displayLabel(for: capture))"
            let suffix = "\(scheduled)\(startedSuffix(for: capture))"
                + "\(adjustedSuffix(for: capture))\(shiftedSuffix(for: capture))\(resetSuffix(for: capture))\(closedSuffix(for: capture))"
            return "\(index + 1). \(batchLineText(capture))\(override)\(suffix)"
        }
        let heldLines = batchHeldLines(for: captures)
        return CaptureNotificationPresentation(
            title: "\(captures.count) items captured",
            subtitle: summary,
            body: ([summary] + lines + heldLines).filter { !$0.isEmpty }.joined(separator: "\n"),
            targetPaths: targetPaths
        )
    }

    nonisolated private static func singleCaptureBody(_ capture: CaptureCommandSuccess) -> String {
        if let reset = CapturePomodoroResetPresentation(capture: capture) {
            return reset.notificationBody
        }
        if let close = CapturePomodoroClosePresentation(capture: capture) {
            return close.notificationBody
        }
        let scheduled = capture.scheduled.map { "\nScheduled: \($0)" } ?? ""
        let started = CapturePomodoroStartPresentation(capture: capture)
            .map { "\n\($0.notificationDetail)" } ?? ""
        let adjusted = CapturePomodoroAdjustPresentation(capture: capture)
            .map { "\n\($0.notificationDetail)" } ?? ""
        let shifted = CapturePomodoroShiftPresentation(capture: capture)
            .map { "\n\($0.notificationDetail)" } ?? ""
        let projectNote = CaptureProjectNotePresentation(capture: capture)
            .map { "\n\($0.notificationDetail)" } ?? ""
        let typeSuffix: String = {
            if CapturePomodoroLinkPresentation(capture: capture) != nil
                || CaptureTogglePresentation(capture: capture) != nil
            {
                return ""
            }
            guard let change = capture.taskTheme,
                  change.action == "set" || change.action == "kept",
                  let name = change.theme?.name, !name.isEmpty
            else {
                return ""
            }
            return "\ntype \(name)"
        }()
        return "\(semanticText(capture))\(scheduled)\(started)\(adjusted)\(shifted)"
            + "\(projectNote)\(typeSuffix)"
    }

    nonisolated private static func startedSuffix(for capture: CaptureCommandSuccess) -> String {
        CapturePomodoroStartPresentation(capture: capture)
            .map(\.batchSuffix) ?? ""
    }

    nonisolated private static func adjustedSuffix(for capture: CaptureCommandSuccess) -> String {
        CapturePomodoroAdjustPresentation(capture: capture)
            .map { " (\($0.sessionText))" } ?? ""
    }

    nonisolated private static func shiftedSuffix(for capture: CaptureCommandSuccess) -> String {
        CapturePomodoroShiftPresentation(capture: capture)
            .map { " (\($0.sessionText))" } ?? ""
    }

    nonisolated private static func closedSuffix(for capture: CaptureCommandSuccess) -> String {
        CapturePomodoroClosePresentation(capture: capture)
            .map(\.batchSuffix) ?? ""
    }

    /// Bob-authored requirement receipts, once per opaque key so a batch
    /// root mirror never duplicates an item-level outcome.
    nonisolated private static func requirementOutcomeMessages(
        from captures: [CaptureCommandSuccess]
    ) -> [String] {
        var seen = Set<String>()
        var lines: [String] = []
        for capture in captures {
            for outcome in capture.allRequirementOutcomes {
                guard !outcome.message.isEmpty, seen.insert(outcome.key).inserted else {
                    continue
                }
                lines.append(outcome.message)
            }
        }
        return lines
    }

    nonisolated private static func pulledInSummary(captures: [CaptureCommandSuccess]) -> String {
        // Explicit `none` never reports picks, and unselected offers stay
        // silent via the `selected` gate. Opaque keys dedupe within each
        // capture result; a hand-off second reason lives only on its
        // primary row, so it never double-counts.
        let eligible = captures.filter { $0.pullIn?.choice != "none" }
        var unblockedSelectedTotal = 0
        var relationSelectedTotal = 0
        var relationSelectedRows: [TaskCompleteUnblocked] = []
        for capture in eligible {
            var seenKeys = Set<String>()
            for row in capture.allUnblockedRows where row.offer?.selected == true {
                if let key = row.offer?.key, !key.isEmpty {
                    guard seenKeys.insert(key).inserted else {
                        continue
                    }
                }
                unblockedSelectedTotal += 1
            }
            for row in capture.allRelationSuccessors where row.offer?.selected == true {
                if let key = row.offer?.key, !key.isEmpty {
                    guard seenKeys.insert(key).inserted else {
                        continue
                    }
                    relationSelectedRows.append(row)
                } else {
                    relationSelectedRows.append(row)
                }
                relationSelectedTotal += 1
            }
        }
        let count = eligible.reduce(into: 0) { total, capture in
            let rows = capture.allUnblockedRows + capture.allRelationSuccessors
                + capture.allKeepMovingRows + capture.allNotePullRows
            var selectedKeys = Set<String>()
            var unkeyedSelectedCount = 0
            for row in rows where row.offer?.selected == true {
                if let key = row.offer?.key, !key.isEmpty {
                    selectedKeys.insert(key)
                } else {
                    unkeyedSelectedCount += 1
                }
            }
            total += selectedKeys.count + unkeyedSelectedCount
        }
        guard count > 0 else { return "" }
        var noteNames: [String] = []
        var notePullCount = 0
        var notePullLines: [String] = []
        for capture in eligible {
            guard let notePull = capture.notePull else { continue }
            let selected = capture.allNotePullRows.filter { $0.offer?.selected == true }
            guard !selected.isEmpty else { continue }
            let name = CaptureNotePullPresentation.displayName(for: notePull)
            if !noteNames.contains(name) {
                noteNames.append(name)
            }
            notePullCount += selected.count
            notePullLines.append(contentsOf: selected.map { row in
                let destination = row.offer?.destination.entryName
                let suffix = destination.flatMap { $0.isEmpty ? nil : $0 }.map { " → \($0)" } ?? ""
                return "• \(row.text)\(suffix)"
            })
        }
        if notePullCount > 0 {
            let noteLabel = noteNames.count == 1
                ? "‹\(noteNames[0])›"
                : "\(noteNames.count) notes"
            let noteSummary = "📥 Pulled in \(notePullCount) from \(noteLabel)"
            if notePullCount == count {
                return ([noteSummary] + notePullLines).joined(separator: "\n")
            }
            return (["Pulled in \(count) successor offers", noteSummary] + notePullLines)
                .joined(separator: "\n")
        }
        let keepMovingRows: [TaskCompleteUnblocked] = eligible
            .flatMap(\.allKeepMovingRows)
            .filter { $0.offer?.selected == true }
        if !keepMovingRows.isEmpty {
            let movingKeys = Set(keepMovingRows.compactMap { row -> String? in
                guard let key = row.offer?.key, !key.isEmpty else { return nil }
                return key
            })
            let unkeyedMovingCount = keepMovingRows.filter {
                $0.offer?.key.isEmpty != false
            }.count
            let movingCount = movingKeys.count + unkeyedMovingCount
            var seen = Set<String>()
            let projects = keepMovingRows.compactMap { row -> String? in
                let path = row.offer?.project ?? row.notePath
                guard !path.isEmpty else { return nil }
                let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                return seen.insert(name).inserted ? name : nil
            }
            let projectText = projects.count == 1
                ? (projects.first ?? "the project")
                : "\(projects.count) projects"
            let otherCount = max(0, count - movingCount)
            if otherCount > 0 {
                let successorOffers =
                    "\(otherCount) successor offer\(otherCount == 1 ? "" : "s")"
                let movingOffers =
                    "\(movingCount) keep-moving offer\(movingCount == 1 ? "" : "s") for \(projectText)"
                return "⏭ Pulled in \(successorOffers) · \(movingOffers)"
            }
            return "⏭ Pulled in \(count) · keeps \(projectText) moving"
        }
        if relationSelectedTotal > 0, unblockedSelectedTotal == 0,
           let relationLine = SuccessorRows.relationPulledInLine(
               count: relationSelectedTotal,
               rows: relationSelectedRows
           )
        {
            return relationLine
        }
        return "Pulled in \(count) successor offer\(count == 1 ? "" : "s")"
    }

    /// Single-capture presentation with the shared picked summary appended
    /// once. Task/Pomodoro bodies already contain their picked line, so a
    /// body that mentions "Pulled in" never gains a second summary.
    /// Titles, dependency wording, keep-moving breakdowns, and note targets
    /// stay exactly as the underlying presentation built them. Explicit
    /// `none` and unselected offers stay silent via `pulledInSummary`.
    nonisolated private static func singlePresentation(
        title: String,
        subtitle: String,
        body: String,
        capture: CaptureCommandSuccess,
        targetPaths: [String]
    ) -> CaptureNotificationPresentation {
        let summary = pulledInSummary(captures: [capture])
        guard !summary.isEmpty, !body.contains("Pulled in") else {
            return CaptureNotificationPresentation(
                title: title,
                subtitle: subtitle,
                body: body,
                targetPaths: targetPaths
            )
        }
        return CaptureNotificationPresentation(
            title: title,
            subtitle: subtitle,
            body: ([body] + [summary]).filter { !$0.isEmpty }.joined(separator: "\n"),
            targetPaths: targetPaths
        )
    }

    /// Held/check lines for batch notifications, one shared gate per
    /// capture. A batch with offers in one item and held rows in another
    /// still surfaces the held-only item; a picker with offers suppresses
    /// only its own held rows. Ordered unique to avoid doubling a root
    /// that mirrors its first item.
    nonisolated private static func batchHeldLines(for captures: [CaptureCommandSuccess]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for capture in captures {
            for line in CaptureRelationHeldPresentation.lines(for: capture) {
                guard seen.insert(line).inserted else { continue }
                out.append(line)
            }
        }
        return out
    }

    nonisolated private static func resetSuffix(for capture: CaptureCommandSuccess) -> String {
        CapturePomodoroResetPresentation(capture: capture)
            .map(\.batchSuffix) ?? ""
    }

    // Batch lines name the link transition (`[ ] → [*]  Ready thing`) instead of
    // the raw post-image task line, which a `pomodoro_link` capture leaves empty
    // or Markdown-formatted. Every other kind keeps the semantic text.
    nonisolated private static func batchLineText(_ capture: CaptureCommandSuccess) -> String {
        if CaptureNotebookPresentation.isNotebook(capture) {
            return CaptureNotebookPresentation.batchLine(for: capture)
        }
        if let summary = capture.recordNote,
           capture.kind == "record_note" || capture.kind == "record_update"
        {
            return CaptureRecordPreviewPresentation.recordBatchLine(for: summary)
        }
        if let link = CapturePomodoroLinkPresentation(capture: capture) {
            return link.transitionText
        }
        if let linkGuard = CaptureLinkGuardPresentation(capture: capture) {
            return linkGuard.headline
        }
        if let complete = CaptureTaskCompletePresentation(capture: capture) {
            return complete.transitionText
        }
        if let ref = CaptureRefPresentation(capture: capture) {
            return "\(ref.destinationLabel): \(ref.detailText)"
        }
        return semanticText(capture)
    }

    nonisolated private static func semanticText(_ capture: CaptureCommandSuccess) -> String {
        if !capture.text.isEmpty {
            return capture.text
        }
        if let parentText = capture.parentText, !parentText.isEmpty {
            return parentText
        }
        return capture.taskLine
    }

    nonisolated private static func displayLabel(for capture: CaptureCommandSuccess) -> String {
        capture.routeLabel.isEmpty ? capture.relativeTarget : capture.routeLabel
    }

    nonisolated private static func friendlyKindLabel(_ kind: String) -> String {
        if let label = CaptureNotebookPresentation.friendlyKindLabel(kind) {
            return label
        }
        switch kind.lowercased() {
        case "pomodoro-close", "pomodoro_close":
            return "Close"
        case "task", "pomodoro-task", "pomodoro_task":
            return "Task"
        case "note", "bullet", "sub-bullet", "sub_bullet":
            return "Note"
        case "task-toggle", "task_toggle":
            return "Toggle"
        case "task-complete", "task_complete":
            return "Complete"
        case "pomodoro-link", "pomodoro_link":
            return "Link"
        case "pomodoro-adjust", "pomodoro_adjust":
            return "Adjustment"
        case "pomodoro-shift", "pomodoro_shift":
            return "Shift"
        case "pomodoro-start", "pomodoro_start":
            return "Start"
        case "pomodoro-past", "pomodoro_past":
            return "Past"
        case "project-note", "project_note":
            return "Project"
        case "note-pull", "note_pull":
            return "Pull from note"
        case "ref":
            return "Reference"
        case "record-note", "record_note":
            return "Record"
        case "record-update", "record_update":
            return "Record update"
        default:
            return kind
                .split { $0 == "-" || $0 == "_" || $0 == " " }
                .map { word in
                    guard let first = word.first else {
                        return ""
                    }
                    return first.uppercased() + word.dropFirst().lowercased()
                }
                .joined(separator: " ")
        }
    }

    nonisolated private static func pluralSummary(labels: [String]) -> String {
        let counts = labels.reduce(into: [String: Int]()) { result, label in
            result[label, default: 0] += 1
        }
        return counts.keys.sorted().map { label in
            let count = counts[label] ?? 0
            return "\(count) \(label.lowercased())\(count == 1 ? "" : "s")"
        }.joined(separator: ", ")
    }

    nonisolated private static func destinationCountSummary(
        captures: [CaptureCommandSuccess],
        targetPathCount: Int
    ) -> String {
        if targetPathCount > 0 {
            return "\(targetPathCount) destination\(targetPathCount == 1 ? "" : "s")"
        }
        let labels = Set(captures.map(\.routeLabel).filter { !$0.isEmpty })
        guard !labels.isEmpty else {
            return ""
        }
        return "\(labels.count) destination\(labels.count == 1 ? "" : "s")"
    }

    nonisolated private static func orderedUniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for path in paths where !path.isEmpty {
            if seen.insert(path).inserted {
                unique.append(path)
            }
        }
        return unique
    }
}

enum NotificationRoute: Equatable {
    case none
    case showCapture
    case showRefs
    case showRefsSelecting(notePath: String)
    case openURLs([URL])
    case openSnoozeWake(wakeID: String, urls: [URL])
}

private struct CaptureNotificationPresentation: Equatable {
    let title: String
    let subtitle: String
    let body: String
    let targetPaths: [String]
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Snooze records stay silent in the foreground: list-only, never a
        // banner, sound, or badge. Every other category keeps banner+sound.
        if notification.request.content.categoryIdentifier
            == Self.snoozeWakeCategoryIdentifier
        {
            completionHandler(Self.snoozeForegroundPresentationOptions)
        } else {
            completionHandler(Self.foregroundPresentationOptions)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            Self.execute(
                Self.route(
                    forActionIdentifier: actionIdentifier,
                    categoryIdentifier: categoryIdentifier,
                    userInfo: userInfo
                ),
                opener: self.opener,
                showCapture: self.showCapture,
                showRefs: self.showRefs,
                onSnoozeWakeOpened: { [weak self] wakeID in
                    self?.onSnoozeWakeOpened(wakeID)
                }
            )
        }
        completionHandler()
    }
}
