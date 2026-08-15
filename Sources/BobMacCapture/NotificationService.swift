import AppKit
import CaptureCore
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
    nonisolated static let captureCategoryIdentifier = "org.bobs.bob-mac-capture.capture"
    nonisolated static let captureBatchCategoryIdentifier = "org.bobs.bob-mac-capture.capture-batch"
    nonisolated static let targetPathKey = "targetPath"
    nonisolated static let targetPathsKey = "targetPaths"
    nonisolated static let foregroundPresentationOptions: UNNotificationPresentationOptions = [
        .banner, .sound, .list,
    ]

    @Published private(set) var authorization = NotificationAuthorizationDisplay(status: .notDetermined)

    private let center: UNUserNotificationCenter
    private let opener: (URL) -> Void

    init(
        center: UNUserNotificationCenter = .current(),
        opener: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.center = center
        self.opener = opener
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

    func notifyCaptureSuccess(captures: [CaptureCommandSuccess]) {
        Task {
            try? await add(Self.successContent(captures: captures))
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
    nonisolated static func successContent(captures: [CaptureCommandSuccess]) -> UNMutableNotificationContent {
        let presentation = successPresentation(captures: captures)
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

    nonisolated static func captureCategories() -> Set<UNNotificationCategory> {
        [captureCategory(), captureBatchCategory()]
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
        captures: [CaptureCommandSuccess]
    ) -> CaptureNotificationPresentation {
        let nonemptyCaptures = captures.isEmpty ? [] : captures
        let targetPaths = orderedUniquePaths(nonemptyCaptures.map(\.target).filter { !$0.isEmpty })
        guard nonemptyCaptures.count != 1, !nonemptyCaptures.isEmpty else {
            guard let capture = nonemptyCaptures.first else {
                return CaptureNotificationPresentation(
                    title: "Captured",
                    subtitle: "",
                    body: "",
                    targetPaths: []
                )
            }
            let kind = friendlyKindLabel(capture.kind)
            return CaptureNotificationPresentation(
                title: "\(kind) captured",
                subtitle: capture.routeLabel,
                body: singleCaptureBody(capture),
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
            return "\(index + 1). \(friendlyKindLabel(capture.kind)) -> \(capture.routeLabel): \(semanticText(capture))\(scheduled)"
        }
        return CaptureNotificationPresentation(
            title: "\(nonemptyCaptures.count) items captured",
            subtitle: summary,
            body: ([summary] + lines).filter { !$0.isEmpty }.joined(separator: "\n"),
            targetPaths: targetPaths
        )
    }

    nonisolated private static func singleCaptureBody(_ capture: CaptureCommandSuccess) -> String {
        let scheduled = capture.scheduled.map { "\nScheduled: \($0)" } ?? ""
        return "\(semanticText(capture))\(scheduled)"
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

    nonisolated private static func friendlyKindLabel(_ kind: String) -> String {
        switch kind.lowercased() {
        case "task", "pomodoro-task", "pomodoro_task":
            return "Task"
        case "note", "bullet", "sub-bullet", "sub_bullet":
            return "Note"
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
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            for url in Self.targetURLs(forActionIdentifier: actionIdentifier, userInfo: userInfo) {
                self.opener(url)
            }
        }
        completionHandler()
    }
}
