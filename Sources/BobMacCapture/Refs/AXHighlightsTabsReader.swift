import AppKit
import ApplicationServices
import Foundation
import RefsCore

/// Reads and selects tabs from the configured Highlights process only.
/// Accessibility elements stay on one serial queue and tab names stay in memory.
final class AXHighlightsTabsReader: HighlightsTabsReading, @unchecked Sendable {
    private struct WindowRecord {
        let element: AXUIElement
        let tabButtons: [AXUIElement]
        let value: HighlightsTabsSnapshot.Window
    }

    private struct ReadFailure: Error {
        let reason: String
    }

    private let bundleIdentifier: @Sendable () -> String
    private let queue = DispatchQueue(label: "org.bobs.bob-mac-capture.highlights-tabs")
    private let messagingTimeout: Float = 0.4
    private let timeBudgetNanoseconds: UInt64 = 1_000_000_000

    /// Creates a reader for the resolved Highlights bundle identifier.
    init(bundleIdentifier: @escaping @Sendable () -> String = { HighlightsLocator.bundleIdentifier }) {
        self.bundleIdentifier = bundleIdentifier
    }

    /// Checks the app's Accessibility grant without prompting.
    func isTrusted() -> Bool {
        AccessibilityTrust.isTrusted()
    }

    /// Repairs a stale Accessibility grant and requests a fresh grant after an
    /// explicit user action, then opens the Accessibility pane if needed.
    func requestTrust() {
        guard !AccessibilityTrust.isTrusted() else {
            return
        }
        _ = AccessibilityTrust.resetGrant()
        if !AccessibilityTrust.requestPrompt() {
            AccessibilityTrust.openSettings()
        }
    }

    /// Reads one bounded snapshot from Highlights without launching it.
    func read() async -> HighlightsTabsReadResult {
        await onQueue { self.readOnQueue() }
    }

    /// Selects a tab only after locating and rechecking it in a fresh snapshot.
    func select(_ target: HighlightsTabTarget) async -> HighlightsTabSelectResult {
        await onQueue { self.selectOnQueue(target) }
    }

    private func onQueue<Value: Sendable>(_ operation: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: operation())
            }
        }
    }

    private func readOnQueue() -> HighlightsTabsReadResult {
        guard AccessibilityTrust.isTrusted() else {
            return .notTrusted
        }
        guard let application = runningHighlightsApplication() else {
            return .notRunning
        }
        do {
            let deadline = DispatchTime.now().uptimeNanoseconds + timeBudgetNanoseconds
            return .snapshot(try readSnapshot(application, deadline: deadline).snapshot)
        } catch let failure as ReadFailure {
            return .failed(failure.reason)
        } catch {
            return .failed("Couldn't read Highlights' tabs")
        }
    }

    private func selectOnQueue(_ target: HighlightsTabTarget) -> HighlightsTabSelectResult {
        guard AccessibilityTrust.isTrusted() else {
            return .notTrusted
        }
        guard let application = runningHighlightsApplication() else {
            return .notRunning
        }

        do {
            let deadline = DispatchTime.now().uptimeNanoseconds + timeBudgetNanoseconds
            let initial = try readSnapshot(application, deadline: deadline)
            guard let location = HighlightsTabLocator.locate(target, in: initial.snapshot),
                initial.windows.indices.contains(location.window),
                initial.windows[location.window].tabButtons.indices.contains(location.tab)
            else {
                return .notFound
            }

            let window = initial.windows[location.window]
            let button = window.tabButtons[location.tab]
            guard try title(of: button, deadline: deadline) == target.fileName else {
                return .notFound
            }

            setMessagingTimeout(on: button)
            try checkDeadline(deadline)
            guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
                return .failed("Couldn't switch to that tab in Highlights")
            }
            try checkDeadline(deadline)

            _ = application.activate(options: [])
            setMessagingTimeout(on: window.element)
            _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            try checkDeadline(deadline)

            let verified = try readSnapshot(application, deadline: deadline)
            guard let verifiedLocation = HighlightsTabLocator.locate(
                target,
                in: verified.snapshot
            ), verified.snapshot.windows[verifiedLocation.window]
                .tabs[verifiedLocation.tab].isSelected
            else {
                return .failed("Highlights didn't switch tabs")
            }
            return .selected
        } catch let failure as ReadFailure {
            return .failed(failure.reason)
        } catch {
            return .failed("Couldn't switch to that tab in Highlights")
        }
    }

    private func runningHighlightsApplication() -> NSRunningApplication? {
        let identifier = bundleIdentifier()
        guard !identifier.isEmpty else {
            return nil
        }
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: identifier)
            .first
    }

    private func readSnapshot(
        _ application: NSRunningApplication,
        deadline: UInt64
    ) throws -> (snapshot: HighlightsTabsSnapshot, windows: [WindowRecord]) {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        setMessagingTimeout(on: appElement)
        guard let rawWindows = try requiredAttribute(
            appElement,
            kAXWindowsAttribute as CFString,
            deadline: deadline
        ) as? [AXUIElement]
        else {
            throw ReadFailure(reason: "Couldn't read Highlights' windows")
        }

        var records: [WindowRecord] = []
        records.reserveCapacity(rawWindows.count)
        for window in rawWindows {
            try checkDeadline(deadline)
            setMessagingTimeout(on: window)
            let isMain = (try optionalAttribute(
                window,
                kAXMainAttribute as CFString,
                deadline: deadline
            ) as? NSNumber)?.boolValue ?? false
            let documentPath = documentPath(from: try optionalAttribute(
                window,
                kAXDocumentAttribute as CFString,
                deadline: deadline
            ))
            let windowTitle = try optionalAttribute(
                window,
                kAXTitleAttribute as CFString,
                deadline: deadline
            ) as? String
            let pageCaption = windowTitle.flatMap(HighlightsWindowTitle.pageCaption(fromTitle:))
            let tabGroup = try findTabGroup(in: window, depth: 0, deadline: deadline)
            let tabButtons: [AXUIElement] = try tabGroup.flatMap { group in
                setMessagingTimeout(on: group)
                return try optionalAttribute(group, "AXTabs" as CFString, deadline: deadline)
                    as? [AXUIElement]
            } ?? []

            let tabs: [HighlightsTabsSnapshot.Tab]
            if tabButtons.isEmpty {
                let fileName = fileName(from: documentPath)
                    ?? fileName(fromWindowTitle: windowTitle)
                if let fileName {
                    tabs = [
                        HighlightsTabsSnapshot.Tab(
                            fileName: fileName,
                            documentPath: documentPath,
                            isSelected: true
                        ),
                    ]
                } else {
                    tabs = []
                }
            } else {
                tabs = try tabButtons.map { button in
                    try checkDeadline(deadline)
                    setMessagingTimeout(on: button)
                    let title = try optionalAttribute(
                        button,
                        kAXTitleAttribute as CFString,
                        deadline: deadline
                    ) as? String
                    let selected = (try optionalAttribute(
                        button,
                        kAXValueAttribute as CFString,
                        deadline: deadline
                    ) as? NSNumber)?.intValue == 1
                    let fileName = title.flatMap(Self.nonEmpty)
                        ?? (selected ? fileName(from: documentPath) : nil)
                        ?? "Untitled"
                    return HighlightsTabsSnapshot.Tab(
                        fileName: fileName,
                        documentPath: selected ? documentPath : nil,
                        isSelected: selected
                    )
                }
            }

            records.append(
                WindowRecord(
                    element: window,
                    tabButtons: tabButtons,
                    value: HighlightsTabsSnapshot.Window(
                        isMain: isMain,
                        pageCaption: pageCaption,
                        tabs: tabs
                    )
                )
            )
        }

        return (
            HighlightsTabsSnapshot(
                windows: records.map(\.value),
                highlightsIsFrontmost: application.isActive
            ),
            records
        )
    }

    private func findTabGroup(
        in element: AXUIElement,
        depth: Int,
        deadline: UInt64
    ) throws -> AXUIElement? {
        guard depth < 3,
            let children = try optionalAttribute(
                element,
                kAXChildrenAttribute as CFString,
                deadline: deadline
            ) as? [AXUIElement]
        else {
            return nil
        }

        for child in children {
            try checkDeadline(deadline)
            setMessagingTimeout(on: child)
            let role = try optionalAttribute(
                child,
                kAXRoleAttribute as CFString,
                deadline: deadline
            ) as? String
            if role == (kAXTabGroupRole as String) {
                return child
            }
            guard role != (kAXScrollAreaRole as String),
                role != "AXWebArea",
                role != (kAXTextAreaRole as String),
                role != (kAXTableRole as String),
                role != (kAXOutlineRole as String)
            else {
                continue
            }
            if let found = try findTabGroup(in: child, depth: depth + 1, deadline: deadline) {
                return found
            }
        }
        return nil
    }

    private func requiredAttribute(
        _ element: AXUIElement,
        _ name: CFString,
        deadline: UInt64
    ) throws -> CFTypeRef? {
        try checkDeadline(deadline)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name, &value)
        guard result == .success else {
            if result == .cannotComplete {
                throw ReadFailure(reason: "Highlights didn't respond to the tab read")
            }
            throw ReadFailure(reason: "Couldn't read Highlights' windows")
        }
        try checkDeadline(deadline)
        return value
    }

    private func optionalAttribute(
        _ element: AXUIElement,
        _ name: CFString,
        deadline: UInt64
    ) throws -> CFTypeRef? {
        try checkDeadline(deadline)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name, &value)
        try checkDeadline(deadline)
        return result == .success ? value : nil
    }

    private func title(of element: AXUIElement, deadline: UInt64) throws -> String? {
        setMessagingTimeout(on: element)
        return try optionalAttribute(
            element,
            kAXTitleAttribute as CFString,
            deadline: deadline
        ) as? String
    }

    private func setMessagingTimeout(on element: AXUIElement) {
        _ = AXUIElementSetMessagingTimeout(element, messagingTimeout)
    }

    private func documentPath(from value: CFTypeRef?) -> String? {
        if let url = value as? URL, url.isFileURL {
            return url.path
        }
        guard let text = value as? String else {
            return nil
        }
        if let url = URL(string: text), url.isFileURL {
            return url.path
        }
        return text.hasPrefix("/") ? text : nil
    }

    private func fileName(from path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func fileName(fromWindowTitle title: String?) -> String? {
        guard let title = Self.nonEmpty(title) else {
            return nil
        }
        let suffix = try! NSRegularExpression(
            pattern: #"(?i)\s+[-–—]\s+page\s+\d+\s+of\s+\d+\s*$"#
        )
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        let stripped = suffix.stringByReplacingMatches(
            in: title,
            range: range,
            withTemplate: ""
        )
        return Self.nonEmpty(stripped)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private func checkDeadline(_ deadline: UInt64) throws {
        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            throw ReadFailure(reason: "Reading Highlights' tabs timed out")
        }
    }
}
