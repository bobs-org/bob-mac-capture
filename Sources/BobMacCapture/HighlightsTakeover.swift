import AppKit

/// Registers the Highlights-frontmost takeover key
/// (`.refsHighlightsOpen`) only while the frontmost app is Highlights —
/// or the Settings override app — and the takeover setting is not off.
/// Other apps never lose Command-O or Control-O. The panel is
/// non-activating, so Highlights stays frontmost while the panel is
/// visible and the same key closes it.
@MainActor
final class HighlightsTakeover {
    private let notificationCenter: NotificationCenter
    private let registry: HotKeyRegistry
    private let frontmostBundleID: () -> String?
    private let openKey: () -> RefsHighlightsOpenKey
    private let overrideBundleID: () -> String?
    private let onError: (String) -> Void
    private var tokens: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter,
        registry: HotKeyRegistry,
        frontmostBundleID: @escaping () -> String?,
        openKey: @escaping () -> RefsHighlightsOpenKey,
        overrideBundleID: @escaping () -> String?,
        onError: @escaping (String) -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.registry = registry
        self.frontmostBundleID = frontmostBundleID
        self.openKey = openKey
        self.overrideBundleID = overrideBundleID
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
                ) { [weak self] _ in
                    Task { @MainActor in self?.sync() }
                }
            )
        }
        sync()
    }

    func stop() {
        stopObserving()
        registry.unregister(.refsHighlightsOpen)
    }

    /// Registers the configured takeover key when Highlights (or the
    /// override app) is frontmost and the setting is not off, and
    /// unregisters otherwise. A registration failure is reported,
    /// never thrown.
    func sync() {
        guard let configuration = openKey().configuration else {
            registry.unregister(.refsHighlightsOpen)
            return
        }
        let expected = overrideBundleID() ?? HighlightsLocator.bundleIdentifier
        guard frontmostBundleID() == expected else {
            registry.unregister(.refsHighlightsOpen)
            return
        }
        do {
            try registry.register(
                .refsHighlightsOpen,
                configuration: configuration
            )
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
