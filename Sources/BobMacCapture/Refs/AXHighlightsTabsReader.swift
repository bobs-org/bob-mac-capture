import AppKit
import ApplicationServices
import Foundation
import RefsCore

/// Reads, selects, and closes tabs from the configured Highlights process only.
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

    private struct CloseNotFound: Error {}

    private let bundleIdentifier: @Sendable () -> String
    private let queue = DispatchQueue(label: "org.bobs.bob-mac-capture.highlights-tabs")
    private let messagingTimeout: Float = 0.4
    private let timeBudgetNanoseconds: UInt64 = 1_000_000_000
    private let closeBudgetNanoseconds: UInt64 = 2_000_000_000
    private let pollInterval: TimeInterval = 0.05

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

    /// Closes a tab through the window-close ladder and verifies it is gone.
    func close(_ target: HighlightsTabTarget) async -> HighlightsTabCloseResult {
        await onQueue { self.closeOnQueue(target) }
    }

    /// Quits Highlights only after a fresh read shows no documents remain.
    func quitIfNoDocuments() async -> Bool {
        await onQueue { self.quitIfNoDocumentsOnQueue() }
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

    private func closeOnQueue(_ target: HighlightsTabTarget) -> HighlightsTabCloseResult {
        guard AccessibilityTrust.isTrusted() else {
            return .notTrusted
        }
        guard let application = runningHighlightsApplication() else {
            return .notRunning
        }

        do {
            let deadline = DispatchTime.now().uptimeNanoseconds + closeBudgetNanoseconds
            let initial = try readSnapshot(application, deadline: deadline)
            let beforeCount = titleCount(target.fileName, in: initial.snapshot)
            if let location = HighlightsTabLocator.locate(target, in: initial.snapshot),
                initial.windows.indices.contains(location.window),
                initial.windows[location.window].value.tabs.indices.contains(location.tab)
            {
                let restoreTitle = try closeLocatedTab(
                    target,
                    at: location,
                    in: initial,
                    application: application,
                    deadline: deadline
                )
                if let verified = verifyClosed(
                    target: target,
                    fileName: target.fileName,
                    beforeCount: beforeCount,
                    application: application,
                    deadline: deadline
                ) {
                    if CloseLadder.shouldRestore(after: verified), let restoreTitle {
                        let restoreDeadline = DispatchTime.now().uptimeNanoseconds + timeBudgetNanoseconds
                        restoreTab(
                            titled: restoreTitle,
                            application: application,
                            deadline: restoreDeadline
                        )
                        if let fresh = try? readSnapshot(application, deadline: restoreDeadline),
                            titleCount(target.fileName, in: fresh.snapshot) < beforeCount
                        {
                            return .closed(fresh.snapshot)
                        }
                    }
                    return verified
                }
                return needsAttentionOrFailed(
                    target: target,
                    application: application,
                    deadline: deadline
                )
            }

            if beforeCount == 0 {
                return .notFound
            }
            return .failed("That tab's name is ambiguous")
        } catch is CloseNotFound {
            return .notFound
        } catch let failure as ReadFailure {
            if highlightsExited(application) {
                return .closed(emptySnapshot())
            }
            return .failed(failure.reason)
        } catch {
            if highlightsExited(application) {
                return .closed(emptySnapshot())
            }
            return .failed("Highlights didn't close that tab")
        }
    }

    private func closeLocatedTab(
        _ target: HighlightsTabTarget,
        at location: (window: Int, tab: Int),
        in initial: (snapshot: HighlightsTabsSnapshot, windows: [WindowRecord]),
        application: NSRunningApplication,
        deadline: UInt64
    ) throws -> String? {
        let window = initial.windows[location.window]
        let tab = window.value.tabs[location.tab]
        let hasTabButton = window.tabButtons.indices.contains(location.tab)
        if hasTabButton {
            guard try title(of: window.tabButtons[location.tab], deadline: deadline) == target.fileName else {
                throw CloseNotFound()
            }
        }

        switch CloseLadder.rung(hasTabButton: hasTabButton, isSelected: tab.isSelected) {
        case .windowCloseButton:
            CaptureSignpost.event("refs-tabs-close-window-button")
            try pressWindowClose(window.element, deadline: deadline)
            return nil
        case .selectThenWindowClose:
            let rememberedTitle = window.value.tabs.first(where: \.isSelected)?.fileName
            try closeBySelecting(
                target: target,
                tabButton: window.tabButtons[location.tab],
                application: application,
                deadline: deadline
            )
            return rememberedTitle
        }
    }

    private func closeBySelecting(
        target: HighlightsTabTarget,
        tabButton: AXUIElement,
        application: NSRunningApplication,
        deadline: UInt64
    ) throws {
        CaptureSignpost.event("refs-tabs-close-select-fallback")
        guard try press(tabButton, deadline: deadline) else {
            throw ReadFailure(reason: "Highlights didn't close that tab")
        }

        var selectedWindow: AXUIElement?
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if highlightsExited(application) {
                return
            }
            let current = try readSnapshot(application, deadline: deadline)
            if let loc = HighlightsTabLocator.locate(target, in: current.snapshot),
                current.windows.indices.contains(loc.window),
                current.snapshot.windows[loc.window].tabs.indices.contains(loc.tab),
                current.snapshot.windows[loc.window].tabs[loc.tab].isSelected
            {
                selectedWindow = current.windows[loc.window].element
                break
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }

        guard let selectedWindow else {
            throw ReadFailure(reason: "Highlights didn't close that tab")
        }
        try pressWindowClose(selectedWindow, deadline: deadline)
    }

    private func restoreTab(
        titled remembered: String?,
        application: NSRunningApplication,
        deadline: UInt64
    ) {
        guard let remembered,
            DispatchTime.now().uptimeNanoseconds < deadline,
            !highlightsExited(application)
        else {
            return
        }
        guard let current = try? readSnapshot(application, deadline: deadline) else {
            return
        }
        for window in current.windows {
            for (index, tab) in window.value.tabs.enumerated() where tab.fileName == remembered {
                guard window.tabButtons.indices.contains(index) else {
                    continue
                }
                setMessagingTimeout(on: window.tabButtons[index])
                _ = AXUIElementPerformAction(
                    window.tabButtons[index],
                    kAXPressAction as CFString
                )
                return
            }
        }
    }

    private func verifyClosed(
        target: HighlightsTabTarget,
        fileName: String,
        beforeCount: Int,
        application: NSRunningApplication,
        deadline: UInt64
    ) -> HighlightsTabCloseResult? {
        var latestSheetWindow: AXUIElement?
        return CloseVerification.run(
            beforeCount: beforeCount,
            deadline: deadline,
            now: { DispatchTime.now().uptimeNanoseconds },
            hasExited: { [weak application] in
                guard let application else { return true }
                return self.highlightsExited(application)
            },
            read: {
                let current = try self.readSnapshot(application, deadline: deadline)
                let count = self.titleCount(fileName, in: current.snapshot)
                if count < beforeCount {
                    latestSheetWindow = nil
                    return (current.snapshot, count, false)
                }
                let sheetWindow: AXUIElement?
                if let location = HighlightsTabLocator.locate(target, in: current.snapshot),
                   current.windows.indices.contains(location.window),
                   try self.windowHasSheet(
                       current.windows[location.window].element,
                       deadline: deadline
                   )
                {
                    sheetWindow = current.windows[location.window].element
                } else {
                    sheetWindow = try self.firstWindowWithSheet(
                        in: current.windows,
                        deadline: deadline
                    )
                }
                latestSheetWindow = sheetWindow
                return (current.snapshot, count, sheetWindow != nil)
            },
            onNeedsAttention: {
                guard let sheetWindow = latestSheetWindow else { return }
                CaptureSignpost.event("refs-tabs-close-needs-attention")
                _ = application.activate(options: [])
                self.setMessagingTimeout(on: sheetWindow)
                _ = AXUIElementPerformAction(sheetWindow, kAXRaiseAction as CFString)
            },
            sleep: { Thread.sleep(forTimeInterval: self.pollInterval) },
            emptySnapshot: { self.emptySnapshot() }
        )
    }

    private func needsAttentionOrFailed(
        target: HighlightsTabTarget,
        application: NSRunningApplication,
        deadline: UInt64
    ) -> HighlightsTabCloseResult {
        if highlightsExited(application) {
            return .closed(emptySnapshot())
        }
        do {
            let current = try readSnapshot(application, deadline: deadline)
            let sheetWindow: AXUIElement?
            if let location = HighlightsTabLocator.locate(target, in: current.snapshot),
                current.windows.indices.contains(location.window),
                try windowHasSheet(
                    current.windows[location.window].element,
                    deadline: deadline
                )
            {
                sheetWindow = current.windows[location.window].element
            } else {
                sheetWindow = try firstWindowWithSheet(
                    in: current.windows,
                    deadline: deadline
                )
            }

            if let sheetWindow {
                CaptureSignpost.event("refs-tabs-close-needs-attention")
                _ = application.activate(options: [])
                setMessagingTimeout(on: sheetWindow)
                _ = AXUIElementPerformAction(sheetWindow, kAXRaiseAction as CFString)
                return .needsAttention
            }
        } catch {
            if highlightsExited(application) {
                return .closed(emptySnapshot())
            }
        }
        CaptureSignpost.event("refs-tabs-close-unverified")
        return .failed("Highlights didn't close that tab")
    }

    private func quitIfNoDocumentsOnQueue() -> Bool {
        guard let application = runningHighlightsApplication() else {
            return true
        }
        guard AccessibilityTrust.isTrusted() else {
            return false
        }

        do {
            let deadline = DispatchTime.now().uptimeNanoseconds + closeBudgetNanoseconds
            let snapshot = try readSnapshot(application, deadline: deadline).snapshot
            guard snapshot.documentCount == 0 else {
                return false
            }
            _ = application.terminate()
            let quitDeadline = DispatchTime.now().uptimeNanoseconds + closeBudgetNanoseconds
            while DispatchTime.now().uptimeNanoseconds < quitDeadline {
                if application.isTerminated {
                    return true
                }
                Thread.sleep(forTimeInterval: pollInterval)
            }
            return application.isTerminated
        } catch {
            return false
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
            let pageNumber = windowTitle.flatMap(HighlightsWindowTitle.pageNumber(fromTitle:))
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
                        pageNumber: pageNumber,
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

    private func pressWindowClose(_ window: AXUIElement, deadline: UInt64) throws {
        setMessagingTimeout(on: window)
        guard let closeButton = axElement(
            from: try optionalAttribute(
                window,
                kAXCloseButtonAttribute as CFString,
                deadline: deadline
            )
        ) else {
            throw ReadFailure(reason: "Highlights didn't close that tab")
        }
        guard try press(closeButton, deadline: deadline) else {
            throw ReadFailure(reason: "Highlights didn't close that tab")
        }
    }

    private func axElement(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func press(_ element: AXUIElement, deadline: UInt64) throws -> Bool {
        try checkDeadline(deadline)
        setMessagingTimeout(on: element)
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private func windowHasSheet(_ window: AXUIElement, deadline: UInt64) throws -> Bool {
        setMessagingTimeout(on: window)
        guard let children = try optionalAttribute(
            window,
            kAXChildrenAttribute as CFString,
            deadline: deadline
        ) as? [AXUIElement]
        else {
            return false
        }
        for child in children {
            try checkDeadline(deadline)
            setMessagingTimeout(on: child)
            let role = try optionalAttribute(
                child,
                kAXRoleAttribute as CFString,
                deadline: deadline
            ) as? String
            if role == (kAXSheetRole as String) {
                return true
            }
        }
        return false
    }

    private func firstWindowWithSheet(
        in records: [WindowRecord],
        deadline: UInt64
    ) throws -> AXUIElement? {
        for record in records {
            if try windowHasSheet(record.element, deadline: deadline) {
                return record.element
            }
        }
        return nil
    }

    private func titleCount(_ fileName: String, in snapshot: HighlightsTabsSnapshot) -> Int {
        snapshot.windows.reduce(0) { partial, window in
            partial + window.tabs.filter { $0.fileName == fileName }.count
        }
    }

    private func emptySnapshot() -> HighlightsTabsSnapshot {
        HighlightsTabsSnapshot(windows: [], highlightsIsFrontmost: false)
    }

    private func highlightsExited(_ application: NSRunningApplication) -> Bool {
        application.isTerminated || runningHighlightsApplication() == nil
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

enum CloseLadder {
    enum Rung: Equatable {
        /// Press the window's close button; the target is its visible tab.
        case windowCloseButton
        /// Select the background target, then press its window's close button.
        case selectThenWindowClose
    }

    /// Uses the window close button because Highlights' per-tab close control
    /// accepts AXPress without closing the tab.
    static func rung(hasTabButton: Bool, isSelected: Bool) -> Rung {
        hasTabButton && !isSelected ? .selectThenWindowClose : .windowCloseButton
    }

    /// The per-tab control accepts AXPress without closing, so background closes
    /// select the target first. Restore only after verified success with documents left.
    static func shouldRestore(after result: HighlightsTabCloseResult?) -> Bool {
        guard case .closed(let snapshot)? = result else {
            return false
        }
        return snapshot.documentCount > 0
    }
}

/// The bounded close-verification loop, factored so tests inject
/// scripted reads, time, and sheet effects while production passes
/// the real Accessibility closures. Polls about every 50 ms within
/// the same ~2 s total budget: verified title-count decrease wins,
/// a save sheet yields needsAttention with one activate/raise, an
/// exited app yields an empty closed snapshot, and anything else
/// reaches a bounded failure without pressing close again.
enum CloseVerification {
    static func run(
        beforeCount: Int,
        deadline: UInt64,
        now: () -> UInt64,
        hasExited: () -> Bool,
        read: () throws -> (
            snapshot: HighlightsTabsSnapshot, titleCount: Int, hasSheet: Bool
        ),
        onNeedsAttention: () -> Void,
        sleep: () -> Void,
        emptySnapshot: () -> HighlightsTabsSnapshot
    ) -> HighlightsTabCloseResult? {
        while now() < deadline {
            if hasExited() {
                return .closed(emptySnapshot())
            }
            do {
                let current = try read()
                if current.titleCount < beforeCount {
                    return .closed(current.snapshot)
                }
                if current.hasSheet {
                    onNeedsAttention()
                    return .needsAttention
                }
            } catch {
                if hasExited() {
                    return .closed(emptySnapshot())
                }
            }
            sleep()
        }
        return nil
    }
}
