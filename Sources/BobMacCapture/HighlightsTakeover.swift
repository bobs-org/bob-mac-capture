import AppKit

struct HotKeyConflict: Equatable {
    let action: HotKeyAction
    let configuration: HotKeyConfiguration
    let error: String

    var diagnosticMessage: String {
        "Refs hotkey conflict: \(configuration.displayName) (\(action.purpose)) is already in use by another app — change it in Settings › References (\(error))"
    }

    var toastTitle: String {
        "\(configuration.displayName.replacingOccurrences(of: "Command-", with: "⌘")) is taken by another app"
    }

    var toastValue: String {
        switch action {
        case .refsHighlightsOpen: "Opening Bob Refs in Highlights won't work"
        case .refsHighlightsTabs: "Showing open tabs in Highlights won't work"
        case .refsHighlightsCopy: "Opening the Copy card in Highlights won't work"
        case .refsHighlightsCode: "Copy code in Highlights won't work"
        case .refsHighlightsLinks: "Copy link in Highlights won't work"
        case .capture, .captureAlias, .refs, .refsAlias: "Opening Bob Refs won't work"
        }
    }

    var toastDetail: String {
        "Change it in Bob Settings › References"
    }

    var accessibilityAnnouncement: String {
        "\(toastTitle). \(toastValue). \(toastDetail)."
    }
}

/// Registers the Highlights-frontmost Refs keys only while Highlights or
/// the Settings override app is frontmost. A key shared with the visible
/// Refs panel steps aside so the panel can handle it.
@MainActor
final class HighlightsTakeover {
    private let notificationCenter: NotificationCenter
    private let registry: HotKeyRegistry
    private let frontmostBundleID: () -> String?
    private let openKey: () -> RefsHighlightsOpenKey
    private let tabsKey: () -> RefsHighlightsTabsKey
    private let copyKey: () -> RefsHighlightsCopyKey
    private let codeKey: () -> RefsHighlightsCodeKey
    private let linkKey: () -> RefsHighlightsLinkKey
    private let isRefsVisible: () -> Bool
    private let overrideBundleID: () -> String?
    private let deactivatedBundleID: (Notification) -> String?
    private let onHighlightsDeactivated: () -> Void
    private let onError: (String) -> Void
    private let onConflict: (HotKeyConflict) -> Void
    private var tokens: [NSObjectProtocol] = []
    private var reportedConflicts: Set<ConflictIdentity> = []
    private var lastSettings: SettingsSnapshot?

    private struct ConflictIdentity: Hashable {
        let action: HotKeyAction
        let configuration: HotKeyConfiguration
    }

    private struct SettingsSnapshot: Equatable {
        let openKey: RefsHighlightsOpenKey
        let tabsKey: RefsHighlightsTabsKey
        let copyKey: RefsHighlightsCopyKey
        let codeKey: RefsHighlightsCodeKey
        let linkKey: RefsHighlightsLinkKey
        let appPath: String
    }

    init(
        notificationCenter: NotificationCenter,
        registry: HotKeyRegistry,
        frontmostBundleID: @escaping () -> String?,
        openKey: @escaping () -> RefsHighlightsOpenKey,
        tabsKey: @escaping () -> RefsHighlightsTabsKey = { .off },
        copyKey: @escaping () -> RefsHighlightsCopyKey = { .off },
        codeKey: @escaping () -> RefsHighlightsCodeKey = { .off },
        linkKey: @escaping () -> RefsHighlightsLinkKey = { .off },
        isRefsVisible: @escaping () -> Bool = { false },
        overrideBundleID: @escaping () -> String?,
        deactivatedBundleID: @escaping (Notification) -> String? = { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            return application?.bundleIdentifier
                ?? (notification.object as? NSRunningApplication)?.bundleIdentifier
        },
        onHighlightsDeactivated: @escaping () -> Void = {},
        onConflict: @escaping (HotKeyConflict) -> Void = { _ in },
        onError: @escaping (String) -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.registry = registry
        self.frontmostBundleID = frontmostBundleID
        self.openKey = openKey
        self.tabsKey = tabsKey
        self.copyKey = copyKey
        self.codeKey = codeKey
        self.linkKey = linkKey
        self.isRefsVisible = isRefsVisible
        self.overrideBundleID = overrideBundleID
        self.deactivatedBundleID = deactivatedBundleID
        self.onHighlightsDeactivated = onHighlightsDeactivated
        self.onConflict = onConflict
        self.onError = onError
    }

    /// Starts observing frontmost-app changes and syncs once, so a launch
    /// with Highlights already frontmost registers immediately.
    func start() {
        stopObserving()
        let names = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            // Synchronous delivery: workspace notifications already post
            // on the main thread, and tests drive this center directly.
            tokens.append(
                notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: nil
                ) { [weak self] notification in
                    Task { @MainActor in
                        guard let self else { return }
                        if name == NSWorkspace.didDeactivateApplicationNotification,
                            self.deactivatedBundleID(notification) == self.expectedBundleID
                        {
                            self.onHighlightsDeactivated()
                        }
                        self.sync()
                    }
                }
            )
        }
        sync()
    }

    func stop() {
        stopObserving()
        registry.unregister(.refsHighlightsOpen)
        registry.unregister(.refsHighlightsTabs)
        registry.unregister(.refsHighlightsCopy)
        registry.unregister(.refsHighlightsCode)
        registry.unregister(.refsHighlightsLinks)
    }

    /// Syncs each Highlights takeover key with the current settings.
    func sync() {
        sync(
            openKey: openKey(),
            tabsKey: tabsKey(),
            copyKey: copyKey(),
            codeKey: codeKey(),
            linkKey: linkKey(),
            overrideBundleID: overrideBundleID()
        )
    }

    /// Re-syncs with explicit settings values from the `@Published` sinks.
    func sync(
        openKey: RefsHighlightsOpenKey,
        tabsKey: RefsHighlightsTabsKey,
        copyKey: RefsHighlightsCopyKey,
        codeKey: RefsHighlightsCodeKey = .off,
        linkKey: RefsHighlightsLinkKey = .off,
        appPath: String
    ) {
        sync(
            openKey: openKey,
            tabsKey: tabsKey,
            copyKey: copyKey,
            codeKey: codeKey,
            linkKey: linkKey,
            overrideBundleID: AppDelegate.highlightsOverrideBundleID(path: appPath)
        )
    }

    private func sync(
        openKey: RefsHighlightsOpenKey,
        tabsKey: RefsHighlightsTabsKey,
        copyKey: RefsHighlightsCopyKey,
        codeKey: RefsHighlightsCodeKey,
        linkKey: RefsHighlightsLinkKey,
        overrideBundleID: String?
    ) {
        let settings = SettingsSnapshot(
            openKey: openKey,
            tabsKey: tabsKey,
            copyKey: copyKey,
            codeKey: codeKey,
            linkKey: linkKey,
            appPath: overrideBundleID ?? ""
        )
        if let lastSettings {
            if lastSettings.openKey != settings.openKey {
                clearReportedConflicts(for: .refsHighlightsOpen)
            }
            if lastSettings.tabsKey != settings.tabsKey {
                clearReportedConflicts(for: .refsHighlightsTabs)
            }
            if lastSettings.copyKey != settings.copyKey {
                clearReportedConflicts(for: .refsHighlightsCopy)
            }
            if lastSettings.codeKey != settings.codeKey {
                clearReportedConflicts(for: .refsHighlightsCode)
            }
            if lastSettings.linkKey != settings.linkKey {
                clearReportedConflicts(for: .refsHighlightsLinks)
            }
            if lastSettings.appPath != settings.appPath {
                reportedConflicts.removeAll()
            }
        }
        lastSettings = settings

        let expected = overrideBundleID ?? HighlightsLocator.bundleIdentifier
        guard frontmostBundleID() == expected else {
            registry.unregister(.refsHighlightsOpen)
            registry.unregister(.refsHighlightsTabs)
            registry.unregister(.refsHighlightsCopy)
            registry.unregister(.refsHighlightsCode)
            registry.unregister(.refsHighlightsLinks)
            return
        }
        sync(action: .refsHighlightsOpen, configuration: openKey.configuration)
        let tabsConfiguration = tabsKey.yieldsToVisiblePanel && isRefsVisible()
            ? nil
            : tabsKey.configuration
        sync(action: .refsHighlightsTabs, configuration: tabsConfiguration)
        // Command-Y always yields while Refs is visible so the panel's
        // own Command-Y can open the Copy card.
        let copyConfiguration = isRefsVisible() ? nil : copyKey.configuration
        sync(action: .refsHighlightsCopy, configuration: copyConfiguration)
        let codeConfiguration = isRefsVisible() ? nil : codeKey.configuration
        sync(action: .refsHighlightsCode, configuration: codeConfiguration)
        let linkConfiguration = isRefsVisible() ? nil : linkKey.configuration
        sync(action: .refsHighlightsLinks, configuration: linkConfiguration)
    }

    private var expectedBundleID: String {
        overrideBundleID() ?? HighlightsLocator.bundleIdentifier
    }

    private func sync(action: HotKeyAction, configuration: HotKeyConfiguration?) {
        guard let configuration else {
            registry.unregister(action)
            return
        }
        do {
            try registry.register(action, configuration: configuration)
            clearReportedConflicts(for: action)
        } catch {
            let conflict = HotKeyConflict(
                action: action,
                configuration: configuration,
                error: String(describing: error)
            )
            onError(conflict.diagnosticMessage)
            let identity = ConflictIdentity(action: action, configuration: configuration)
            if reportedConflicts.insert(identity).inserted {
                onConflict(conflict)
            }
        }
    }

    private func clearReportedConflicts(for action: HotKeyAction) {
        reportedConflicts = reportedConflicts.filter { $0.action != action }
    }

    private func stopObserving() {
        for token in tokens {
            notificationCenter.removeObserver(token)
        }
        tokens.removeAll()
    }
}
