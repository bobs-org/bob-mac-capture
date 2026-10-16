import AppKit

/// Registers the Highlights-frontmost Refs keys only while Highlights or
/// the Settings override app is frontmost.
@MainActor
final class HighlightsTakeover {
    private let notificationCenter: NotificationCenter
    private let registry: HotKeyRegistry
    private let frontmostBundleID: () -> String?
    private let openKey: () -> RefsHighlightsOpenKey
    private let tabsKey: () -> RefsHighlightsTabsKey
    private let overrideBundleID: () -> String?
    private let deactivatedBundleID: (Notification) -> String?
    private let onHighlightsDeactivated: () -> Void
    private let onError: (String) -> Void
    private var tokens: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter,
        registry: HotKeyRegistry,
        frontmostBundleID: @escaping () -> String?,
        openKey: @escaping () -> RefsHighlightsOpenKey,
        tabsKey: @escaping () -> RefsHighlightsTabsKey = { .off },
        overrideBundleID: @escaping () -> String?,
        deactivatedBundleID: @escaping (Notification) -> String? = { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            return application?.bundleIdentifier
                ?? (notification.object as? NSRunningApplication)?.bundleIdentifier
        },
        onHighlightsDeactivated: @escaping () -> Void = {},
        onError: @escaping (String) -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.registry = registry
        self.frontmostBundleID = frontmostBundleID
        self.openKey = openKey
        self.tabsKey = tabsKey
        self.overrideBundleID = overrideBundleID
        self.deactivatedBundleID = deactivatedBundleID
        self.onHighlightsDeactivated = onHighlightsDeactivated
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
    }

    /// Syncs both takeover keys with the current settings.
    func sync() {
        sync(
            openKey: openKey(),
            tabsKey: tabsKey(),
            overrideBundleID: overrideBundleID()
        )
    }

    /// Re-syncs with explicit settings values from the `@Published` sinks.
    func sync(
        openKey: RefsHighlightsOpenKey,
        tabsKey: RefsHighlightsTabsKey,
        appPath: String
    ) {
        sync(
            openKey: openKey,
            tabsKey: tabsKey,
            overrideBundleID: AppDelegate.highlightsOverrideBundleID(path: appPath)
        )
    }

    private func sync(
        openKey: RefsHighlightsOpenKey,
        tabsKey: RefsHighlightsTabsKey,
        overrideBundleID: String?
    ) {
        let expected = overrideBundleID ?? HighlightsLocator.bundleIdentifier
        guard frontmostBundleID() == expected else {
            registry.unregister(.refsHighlightsOpen)
            registry.unregister(.refsHighlightsTabs)
            return
        }
        sync(action: .refsHighlightsOpen, configuration: openKey.configuration)
        sync(action: .refsHighlightsTabs, configuration: tabsKey.configuration)
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
        } catch {
            onError("Refs hotkey conflict: \(error)")
        }
    }

    private func stopObserving() {
        for token in tokens {
            notificationCenter.removeObserver(token)
        }
        tokens.removeAll()
    }
}
