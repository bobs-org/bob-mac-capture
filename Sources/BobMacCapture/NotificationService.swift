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
    nonisolated static let targetPathKey = "targetPath"
    nonisolated static let targetPathsKey = "targetPaths"
    nonisolated static let foregroundPresentationOptions: UNNotificationPresentationOptions = [
        .banner, .sound, .list,
    ]

    @Published private(set) var authorization = NotificationAuthorizationDisplay(status: .notDetermined)

    private let center: UNUserNotificationCenter
    private let opener: (URL) -> Void
    private let showCapture: () -> Void
    private let showRefs: () -> Void

    init(
        center: UNUserNotificationCenter = .current(),
        opener: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        showCapture: @escaping () -> Void = {},
        showRefs: @escaping () -> Void = {}
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
        globalDestination: CaptureGlobalDestination? = nil
    ) {
        Task {
            try? await add(Self.successContent(
                captures: captures,
                globalDestination: globalDestination
            ))
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

    func sendTestNotification() async throws {
        try await add(Self.testContent())
    }

    private func add(_ content: UNMutableNotificationContent) async throws {
        try await CaptureSignpost.measure("notification-schedule") {
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
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
        globalDestination: CaptureGlobalDestination? = nil
    ) -> UNMutableNotificationContent {
        let presentation = successPresentation(
            captures: captures,
            globalDestination: globalDestination
        )
        let content = UNMutableNotificationContent()
        content.title = presentation.title
        content.subtitle = presentation.subtitle
        content.body = presentation.body
        content.sound = .default
        if !presentation.targetPaths.isEmpty {
            content.categoryIdentifier = presentation.targetPaths.count == 1
                ? captureCategoryIdentifier
                : captureBatchCategoryIdentifier
            content.userInfo = [
                targetPathKey: presentation.targetPaths[0],
                targetPathsKey: presentation.targetPaths,
            ]
        }
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
        [
            captureCategory(),
            captureBatchCategory(),
            installRestartCategory(),
            refsScanCategory(),
        ]
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
    // Obsidian routing. Dismissal and mismatched category/action combinations are no-ops.
    // Takes plain values instead of a live UNNotificationResponse, which the SDK gives
    // no public initializer for, so this routing decision stays unit-testable.
    nonisolated static func route(
        forActionIdentifier actionIdentifier: String,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> NotificationRoute {
        if actionIdentifier == UNNotificationDismissActionIdentifier {
            return .none
        }
        if categoryIdentifier == refsScanCategoryIdentifier {
            guard
                actionIdentifier == UNNotificationDefaultActionIdentifier
                    || actionIdentifier == refsScanShowActionIdentifier
            else {
                return .none
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
        showRefs: () -> Void = {}
    ) {
        switch route {
        case .none:
            return
        case .showCapture:
            showCapture()
        case .showRefs:
            showRefs()
        case .openURLs(let urls):
            for url in urls {
                opener(url)
            }
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
        globalDestination: CaptureGlobalDestination?
    ) -> CaptureNotificationPresentation {
        let nonemptyCaptures = captures.isEmpty ? [] : captures
        let targetPaths = notificationTargetPaths(for: nonemptyCaptures)
        guard nonemptyCaptures.count != 1, !nonemptyCaptures.isEmpty else {
            guard let capture = nonemptyCaptures.first else {
                return CaptureNotificationPresentation(
                    title: "Captured",
                    subtitle: "",
                    body: "",
                    targetPaths: []
                )
            }
            if let toggle = CaptureTogglePresentation(capture: capture) {
                return CaptureNotificationPresentation(
                    title: toggle.notificationTitle,
                    subtitle: toggle.routeDestinationLabel,
                    body: toggle.notificationBody,
                    targetPaths: targetPaths
                )
            }
            if let complete = CaptureTaskCompletePresentation(capture: capture) {
                return CaptureNotificationPresentation(
                    title: complete.notificationTitle,
                    subtitle: complete.destinationLabel,
                    body: complete.notificationBody,
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
            if let close = CapturePomodoroClosePresentation(capture: capture) {
                return CaptureNotificationPresentation(
                    title: close.notificationTitle,
                    subtitle: displayLabel(for: capture),
                    body: close.notificationBody,
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
            if let ref = CaptureRefPresentation(capture: capture) {
                return CaptureNotificationPresentation(
                    title: ref.notificationTitle,
                    subtitle: ref.destinationLabel,
                    body: ref.notificationBody,
                    targetPaths: targetPaths
                )
            }
            let kind = friendlyKindLabel(capture.kind)
            return CaptureNotificationPresentation(
                title: "\(kind) captured",
                // Adjustments and shifts are unrouted daily-note edits, so fall
                // back to the relative target (the day file) when there is no
                // route label rather than notifying with an empty subtitle.
                subtitle: displayLabel(for: capture),
                body: singleCaptureBody(capture),
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

        if nonemptyCaptures.allSatisfy({ CaptureTaskCompletePresentation(capture: $0) != nil }) {
            let lines = nonemptyCaptures.enumerated().map { index, capture in
                let presentation = CaptureTaskCompletePresentation(capture: capture)
                let detail = presentation.map { "\($0.destinationLabel): \($0.transitionText)" } ?? batchLineText(capture)
                return "\(index + 1). \(detail)"
            }
            let summary = "\(nonemptyCaptures.count) completed tasks"
            return CaptureNotificationPresentation(
                title: "Completed \(nonemptyCaptures.count) tasks",
                subtitle: summary,
                body: ([summary] + lines).filter { !$0.isEmpty }.joined(separator: "\n"),
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
        let summary = [kindSummary, destinationSummary]
            .filter { !$0.isEmpty }
            .joined(separator: " across ")
        let lines = nonemptyCaptures.enumerated().map { index, capture in
            let scheduled = capture.scheduled.map { " scheduled \($0)" } ?? ""
            let suffix = "\(scheduled)\(startedSuffix(for: capture))"
                + "\(adjustedSuffix(for: capture))\(shiftedSuffix(for: capture))\(resetSuffix(for: capture))\(closedSuffix(for: capture))"
            return "\(index + 1). \(friendlyKindLabel(capture.kind)) -> \(capture.routeLabel): "
                + "\(batchLineText(capture))\(suffix)"
        }
        return CaptureNotificationPresentation(
            title: "\(nonemptyCaptures.count) items captured",
            subtitle: summary,
            body: ([summary] + lines).filter { !$0.isEmpty }.joined(separator: "\n"),
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
        let summary = [kindSummary, globalDestination.scopeSummary, overrideSummary]
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
        return CaptureNotificationPresentation(
            title: "\(captures.count) items captured",
            subtitle: summary,
            body: ([summary] + lines).filter { !$0.isEmpty }.joined(separator: "\n"),
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
        return "\(semanticText(capture))\(scheduled)\(started)\(adjusted)\(shifted)\(projectNote)"
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

    nonisolated private static func resetSuffix(for capture: CaptureCommandSuccess) -> String {
        CapturePomodoroResetPresentation(capture: capture)
            .map(\.batchSuffix) ?? ""
    }

    // Batch lines name the link transition (`[ ] → [*]  Ready thing`) instead of
    // the raw post-image task line, which a `pomodoro_link` capture leaves empty
    // or Markdown-formatted. Every other kind keeps the semantic text.
    nonisolated private static func batchLineText(_ capture: CaptureCommandSuccess) -> String {
        if let link = CapturePomodoroLinkPresentation(capture: capture) {
            return link.transitionText
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
        case "project-note", "project_note":
            return "Project"
        case "ref":
            return "Reference"
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

    // A toggle's or link's day file is only worth an "Open Note(s)" action when the
    // capture actually wrote to it (linked, unlinked, moved, started, or cleaned up
    // a duplicate) — matching the gate `CapturePanelModel.uniqueTargetURLs` uses for
    // Command-Return.
    nonisolated private static func notificationTargetPaths(
        for captures: [CaptureCommandSuccess]
    ) -> [String] {
        var paths: [String] = []
        for capture in captures {
            paths.append(capture.target)
            if let dayFile = capture.dayFile, dayFileChanged(for: capture) {
                paths.append(dayFile)
            }
        }
        return orderedUniquePaths(paths.filter { !$0.isEmpty })
    }

    nonisolated private static func dayFileChanged(for capture: CaptureCommandSuccess) -> Bool {
        if CapturePomodoroResetPresentation(capture: capture) != nil {
            return true
        }
        if CapturePomodoroClosePresentation(capture: capture) != nil {
            return true
        }
        if CapturePomodoroStartPresentation.isSessionStart(capture) {
            return true
        }
        if let toggle = CaptureTogglePresentation(capture: capture) {
            return toggle.dayFileChanged
        }
        if CaptureTaskCompletePresentation(capture: capture) != nil {
            return capture.taskComplete?.ledger != nil
        }
        if let link = CapturePomodoroLinkPresentation(capture: capture) {
            return link.dayFileChanged
        }
        if let note = capture.projectNote, !note.taskLinks.isEmpty {
            return true
        }
        return false
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
    case openURLs([URL])
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
        completionHandler(Self.foregroundPresentationOptions)
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
                showRefs: self.showRefs
            )
        }
        completionHandler()
    }
}
