import AppKit
import Combine
import CaptureCore
import RefsCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    lazy var canceledDraftStash = CanceledDraftStash(
        capacity: settings.canceledDraftStashCapacity,
        store: Self.makeCanceledDraftStashStore(settings: settings)
    )
    // Lazy because NotificationService's default center is `UNUserNotificationCenter.current()`,
    // which raises NSInternalInconsistencyException in a process that has no app bundle. Eagerly
    // building it here made `AppDelegate()` unconstructible under `swift test`, aborting the whole
    // xctest process. Every real touch still happens at or after `applicationWillFinishLaunching`,
    // so the delegate is assigned before any authorization request exactly as before.
    lazy var notificationService = NotificationService(
        showCapture: { [weak self] in
            self?.showCapturePanel()
        },
        showRefs: { [weak self] in
            self?.panelCoordinator?.showRefs()
        }
    )

    var settingsPresentation = SettingsPresentation()
    var relauncher = AppRelauncher()

    private var statusItem: NSStatusItem?
    var hotKeyRegistry: HotKeyRegistry?
    private var panelController: CapturePanelController?
    private var panelModel: CapturePanelModel?
    private var agendaStore: CaptureAgendaStore?
    private var agendaCancellables: Set<AnyCancellable> = []
    private var vaultWatcher: VaultTargetWatcher?
    private let targetsCache = CaptureTargetsCache()
    private var processClient: BobProcessClient?
    private var settingsSceneRepresentation: SettingsSceneRepresentation?
    private var settingsCancellables: Set<AnyCancellable> = []
    private var statusItemController: StatusItemController?
    private var statusItemCancellables: Set<AnyCancellable> = []
    var refsLibrary: RefsLibrary?
    private var refsPanelModel: RefsPanelModel?
    private var refsPanelController: RefsPanelController?
    private var panelCoordinator: BobPanelCoordinator?
    var highlightsTakeover: HighlightsTakeover?
    private var refsCancellables: Set<AnyCancellable> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // No nib supplies a main menu under the explicit `BobMacCaptureMain` entry point,
        // so without this the app loses Cmd-X/C/V/A/Z and Cmd-Q even though it is not a
        // regular windowed app.
        NSApp.mainMenu = Self.makeMainMenu()

        let settings = settings
        let notificationService = notificationService
        let canceledDraftStash = canceledDraftStash
        observeCanceledDraftStashCapacity()
        let representation = NSHostingSceneRepresentation {
            BobSettingsScene(
                settings: settings,
                notificationService: notificationService,
                canceledDraftStash: canceledDraftStash,
                onResetOpenHistory: { [weak self] in self?.refsLibrary?.resetOpenHistory() }
            )
        }

        NSApplication.shared.addSceneRepresentation(representation)
        settingsSceneRepresentation = representation
        settingsPresentation = SettingsPresentation {
            representation.environment.openSettings()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureProcessClient()

        let model = CapturePanelModel(
            processClient: processClient,
            canceledDraftStash: canceledDraftStash
        )
        model.notificationService = notificationService
        panelModel = model
        let agendaStore = CaptureAgendaStore(
            processClient: processClient,
            vaultRootPath: Self.vaultRootURL(bobDirectory: settings.bobDirectory).path
        )
        self.agendaStore = agendaStore
        model.agendaStore = agendaStore
        // The Agenda toggle applies live: the store keeps refreshing
        // for the close-comma count while the model stops measuring,
        // planning, and showing.
        model.agendaEnabled = settings.agendaEnabled
        settings.$agendaEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak model] enabled in
                model?.agendaEnabled = enabled
            }
            .store(in: &agendaCancellables)
        // The Agenda diagnostic follows the store live, so Settings
        // shows the last refresh time, the refresh failure, or the
        // old-bob upgrade hint without polling.
        settings.agendaDiagnostic = agendaStore.diagnosticLine()
        agendaStore.$status
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.settings.agendaDiagnostic = self.agendaStore?.diagnosticLine() ?? ""
            }
            .store(in: &agendaCancellables)
        agendaStore.$lastRefreshedAt
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.settings.agendaDiagnostic = self.agendaStore?.diagnosticLine() ?? ""
            }
            .store(in: &agendaCancellables)
        panelController = CapturePanelController(model: model)
        panelController?.prewarm()
        // Prefetch after prewarm so the first hotkey after login already
        // has agenda data without slowing the show path.
        agendaStore.refresh(reason: .launch)
        // A capture-landed pulse per successful submit, plus a Today
        // refresh with the snapshot marked stale so the next Refs open
        // re-reads it. A dedicated set: the stash-capacity observer guards
        // on `settingsCancellables` being empty.
        model.$successAnnouncementTick
            .dropFirst()
            .sink { [weak self] _ in
                self?.statusItemController?.playCaptureLandedPulse()
                self?.handleCaptureSuccess()
            }
            .store(in: &statusItemCancellables)

        hotKeyRegistry = HotKeyRegistry { [weak self] action in
            switch action {
            case .capture:
                CaptureSignpost.event("hotkey-received")
                Task { @MainActor in
                    self?.showCapturePanel()
                }
            case .refs, .refsHighlightsOpen:
                CaptureSignpost.event("refs-hotkey-received")
                Task { @MainActor in
                    self?.panelCoordinator?.toggleRefs()
                }
            }
        }
        registerHotKey()
        configureRefsStack()
        configureVaultWatcher()
        observeBobSettings()
        refreshTargetsWhenPossible()
        settings.signingDiagnostic = BundleSigningInspector.currentBundleState().diagnosticText
        CaptureSignpost.event("launch-complete")
        if BobMacCaptureLaunchContext.requestsInstallRestartNotification(
            ProcessInfo.processInfo.arguments
        ) {
            CaptureSignpost.event("install-restart-notification-requested")
            notificationService.notifyInstallComplete()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The canceled-draft stash is write-through on every mutation, so there is
        // nothing to flush here. A terminate-only save would drop drafts on force
        // quit, crash, logout SIGKILL, or a just install that replaces the bundle.
        hotKeyRegistry?.invalidate()
        highlightsTakeover?.stop()
        refsLibrary?.stop()
        vaultWatcher?.invalidate()
        processClient?.cancelActiveProcess()
    }

    private static func makeCanceledDraftStashStore(settings: AppSettings) -> CanceledDraftStashStoring? {
        do {
            let fileURL = try FileCanceledDraftStashStore.defaultFileURL()
            return FileCanceledDraftStashStore(
                fileURL: fileURL,
                onError: { message in
                    Task { @MainActor in
                        settings.diagnosticStatus = message
                    }
                }
            )
        } catch {
            settings.diagnosticStatus = FileCanceledDraftStashStore.saveFailureMessage(for: error)
            return nil
        }
    }

    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = makeAppMenu()
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = makeEditMenu()
        mainMenu.addItem(editMenuItem)

        return mainMenu
    }

    private static func makeAppMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Hide Bob Mac Capture",
                action: #selector(NSApplication.hide(_:)),
                keyEquivalent: "h"
            )
        )
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(
            NSMenuItem(
                title: "Show All",
                action: #selector(NSApplication.unhideAllApplications(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Bob Mac Capture",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        return menu
    }

    // Most Edit menu actions have no Swift-visible declaring class of their own; they
    // are standard first-responder messages (`NSText`, `NSTextView`, `UndoManager`) that
    // AppKit forwards along the responder chain. Paste deliberately targets an
    // AppDelegate selector so Cmd-V reads only the pasteboard's plain-text flavor before
    // falling back to native paste for pasteboards without text.
    private static func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Cut", action: Selector(("cut:")), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy", action: Selector(("copy:")), keyEquivalent: "c"))
        menu.addItem(
            NSMenuItem(
                title: "Paste",
                action: #selector(AppDelegate.pastePlainText(_:)),
                keyEquivalent: "v"
            )
        )
        menu.addItem(NSMenuItem(title: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a"))
        return menu
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.imagePosition = .imageOnly
        item.button?.title = ""
        let menu = Self.makeStatusMenu()
        item.menu = menu
        statusItem = item
        let controller = StatusItemController(
            render: { [weak item] frame in
                item?.button?.image = StatusItemGlyph.image(
                    for: frame.glyphState,
                    bulletRadius: frame.bulletRadius
                )
                item?.button?.toolTip = frame.toolTip
                item?.button?.setAccessibilityLabel(frame.accessibilityLabel)
            },
            menu: menu
        )
        statusItemController = controller
        // Render Ready immediately; configureProcessClient() runs right after
        // and corrects the state when bob is unresolved.
        controller.update(isBobResolved: true)
    }

    private func observeCanceledDraftStashCapacity() {
        guard settingsCancellables.isEmpty else {
            return
        }
        settings.$canceledDraftStashCapacity
            .sink { [weak self] capacity in
                self?.canceledDraftStash.updateCapacity(capacity)
            }
            .store(in: &settingsCancellables)
    }

    static func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Capture",
                action: #selector(openCapturePanel),
                keyEquivalent: ""
            )
        )
        let refsItem = NSMenuItem(
            title: "Bob Refs…",
            action: #selector(openRefsPanel),
            keyEquivalent: "o"
        )
        // Display only: the global Control-Shift-Command-O hotkey toggles
        // the panel when the menu is closed; this equivalent labels the row.
        refsItem.keyEquivalentModifierMask = [.command, .control, .shift]
        menu.addItem(refsItem)
        menu.addItem(
            NSMenuItem(
                title: "Settings",
                action: #selector(openSettings),
                keyEquivalent: ","
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Recheck Bob",
                action: #selector(recheckBob),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Restart Bob Mac Capture",
                action: #selector(restartApp),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Quit Bob Mac Capture",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )
        return menu
    }

    private func configureProcessClient() {
        do {
            let override = settings.bobExecutableOverride.isEmpty ? nil : settings.bobExecutableOverride
            let resolved = try BobExecutableResolver().resolve(configuredOverride: override)
            let bobDirectory = settings.bobDirectory.isEmpty ? nil : settings.bobDirectory
            let environment = BobEnvironmentBuilder(bobDirectory: bobDirectory).build()
            processClient = BobProcessClient(executablePath: resolved, environment: environment)
            settings.resolvedBobPath = resolved
            settings.diagnosticStatus = "Ready"
            panelModel?.setProcessClient(processClient)
            if let processClient {
                refsLibrary?.setFetcher(BobRefsFetcher(client: processClient))
            }
        } catch {
            processClient = nil
            settings.resolvedBobPath = "Not resolved"
            settings.diagnosticStatus = String(describing: error)
            panelModel?.setProcessClient(nil)
            refsLibrary?.setFetcher(nil)
        }
        updateStatusItemAppearance()
    }

    // The menu-bar glyph is the only always-visible surface for an `LSUIElement` app,
    // so it must reflect a broken bob resolution at a glance without opening Settings.
    private func updateStatusItemAppearance() {
        statusItemController?.update(isBobResolved: processClient != nil)
    }

    private func registerHotKey() {
        do {
            try hotKeyRegistry?.register(
                .capture,
                configuration: settings.hotKeyConfiguration
            )
            settings.diagnosticStatus = "Hotkey registered: \(settings.hotKeyConfiguration.displayName)"
        } catch {
            settings.diagnosticStatus = "Hotkey conflict: \(error)"
        }
        registerRefsHotKey()
    }

    /// Registers the global Refs hotkey when its setting is on. Success
    /// extends the launch status line so Diagnostics shows both bindings;
    /// a failure is reported as a Refs conflict. Capture's hotkey stays
    /// re-registered only at launch and on Recheck Bob, as before. The
    /// settings sink passes the value it receives, because `@Published`
    /// emits before the property itself changes.
    private func registerRefsHotKey(enabled: Bool? = nil) {
        guard let hotKeyRegistry else {
            return
        }
        let registered = RefsHotkeyRegistration.sync(
            registry: hotKeyRegistry,
            enabled: enabled ?? settings.refsHotkeyEnabled
        ) { [weak self] message in
            self?.settings.diagnosticStatus = message
        }
        guard registered else {
            return
        }
        if hotKeyRegistry.isRegistered(.capture) {
            settings.diagnosticStatus =
                "Hotkey registered: \(settings.hotKeyConfiguration.displayName); "
                + "Refs hotkey registered: \(HotKeyConfiguration.refs.displayName)"
        } else {
            settings.diagnosticStatus =
                "Refs hotkey registered: \(HotKeyConfiguration.refs.displayName)"
        }
    }

    private func refreshTargetsWhenPossible() {
        guard let processClient else {
            return
        }

        Task {
            let snapshot = await CaptureSignpost.measure("targets") {
                await targetsCache.refresh(using: processClient)
            }
            await MainActor.run {
                self.panelModel?.updateTargetCacheSnapshot(snapshot)
                if let error = snapshot.errorDescription {
                    self.settings.diagnosticStatus = "Target cache stale: \(error)"
                }
            }
        }
    }

    /// The vault root: the Settings override, or `~/bob` when it is
    /// empty. Capture and Refs share this helper so both watchers and
    /// both fetchers point at the same vault.
    static func vaultRootURL(bobDirectory: String) -> URL {
        if bobDirectory.isEmpty {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("bob")
        }
        return URL(fileURLWithPath: bobDirectory)
    }

    /// The live Settings override path for Highlights, read straight from
    /// defaults: AppSettings persists every change, so this is always
    /// current. A plain defaults read keeps the Sendable locator closure
    /// off MainActor state.
    nonisolated static func storedHighlightsAppPath() -> String {
        UserDefaults.standard.string(forKey: AppSettings.refsHighlightsAppPathKey) ?? ""
    }

    /// The bundle id of the Settings override Highlights app, or nil when
    /// no override is set or it is not an app bundle. The takeover matches
    /// the override app's id so a moved copy still takes over.
    static func highlightsOverrideBundleID(path: String) -> String? {
        guard !path.isEmpty else {
            return nil
        }
        return Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
    }

    /// Builds the Refs stack after Capture's panel: the stores, the fetcher
    /// sharing the existing process client, the library, the panel model
    /// and controller, the one-panel coordinator, and the Highlights
    /// takeover. Launch never blocks — the library refreshes in the
    /// background — and stays healthy when `bob` is absent: a nil fetcher
    /// paints the cached snapshot with a "Bob is not available" footer.
    private func configureRefsStack() {
        let snapshotStore: RefsSnapshotStore
        let openLogStore: RefsOpenLogStore
        do {
            snapshotStore = RefsSnapshotStore(
                fileURL: try RefsSnapshotStore.defaultFileURL(),
                onError: { [weak self] message in
                    Task { @MainActor in
                        self?.settings.diagnosticStatus = message
                    }
                }
            )
            openLogStore = RefsOpenLogStore(
                fileURL: try RefsOpenLogStore.defaultFileURL(),
                onError: { [weak self] message in
                    Task { @MainActor in
                        self?.settings.diagnosticStatus = message
                    }
                }
            )
        } catch {
            settings.diagnosticStatus = "Bob Refs unavailable: \(error)"
            return
        }
        guard let hotKeyRegistry else {
            settings.diagnosticStatus = "Bob Refs unavailable: no hotkey registry"
            return
        }

        let settings = settings
        let fetcher: RefsFetching? = processClient.map {
            BobRefsFetcher(client: $0)
        }
        let library = RefsLibrary(
            fetcher: fetcher,
            snapshotStore: snapshotStore,
            openLogStore: openLogStore,
            vaultRoot: { Self.vaultRootURL(bobDirectory: settings.bobDirectory) },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            spotlight: SpotlightRefsSignals(),
            now: { Date() }
        )
        let model = RefsPanelModel(
            library: library,
            opener: WorkspaceRefsOpener(),
            highlights: HighlightsLocator(overridePath: Self.storedHighlightsAppPath)
        )
        model.settingsPresenter = { [weak self] in self?.openSettings() }
        // Hidden-panel scan outcomes notify through the coordinator's
        // showRefs, so a visible Capture draft is retained on click.
        model.scanNotifier = { [weak self] outcome in
            self?.notificationService.notifyRefsScan(outcome)
        }
        let controller = RefsPanelController(model: model)
        refsLibrary = library
        refsPanelModel = model
        refsPanelController = controller
        controller.prewarm()
        library.start()

        panelCoordinator = BobPanelCoordinator(
            isCaptureVisible: { [weak self] in self?.panelController?.isVisible == true },
            isRefsVisible: { [weak self] in self?.refsPanelController?.isVisible == true },
            closeCaptureRetainingDraft: { [weak self] in self?.panelModel?.closeRetainingDraft() },
            presentCapture: { [weak self] in self?.panelController?.show() },
            presentRefs: { [weak self] in self?.refsPanelController?.show() },
            presentRefsPreservingState: { [weak self] in
                self?.refsPanelController?.represent()
            },
            hideRefs: { [weak self] in self?.refsPanelController?.hide() }
        )
        // Open-error re-shows keep the panel state and go through the
        // coordinator, so a visible Capture draft is retained.
        model.panelRepresenter = { [weak self] in self?.panelCoordinator?.representRefs() }

        let takeover = HighlightsTakeover(
            notificationCenter: NSWorkspace.shared.notificationCenter,
            registry: hotKeyRegistry,
            frontmostBundleID: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
            openKey: { settings.refsHighlightsOpenKey },
            overrideBundleID: {
                Self.highlightsOverrideBundleID(path: settings.refsHighlightsAppPath)
            },
            onError: { [weak self] message in self?.settings.diagnosticStatus = message }
        )
        highlightsTakeover = takeover
        takeover.start()

        observeRefsSettings()
        registerRefsHotKey()
    }

    /// Re-registers the Refs hotkeys live when the References settings
    /// change. Capture's hotkey is untouched here: it re-registers only at
    /// launch and on Recheck Bob, as before. Each sink applies the value
    /// it receives: `@Published` emits before the property changes, so
    /// re-reading settings here would always see the old value.
    func observeRefsSettings() {
        settings.$refsHotkeyEnabled
            .sink { [weak self] enabled in self?.registerRefsHotKey(enabled: enabled) }
            .store(in: &refsCancellables)
        settings.$refsHighlightsOpenKey
            .combineLatest(settings.$refsHighlightsAppPath)
            .sink { [weak self] key, path in
                self?.highlightsTakeover?.sync(key: key, appPath: path)
            }
            .store(in: &refsCancellables)
    }

    /// A capture success refreshes Today now and marks the snapshot
    /// stale, so the next Refs open re-reads it. The agenda refreshes
    /// too, before the next show, so the new ledger state is cached.
    func handleCaptureSuccess() {
        refsLibrary?.refreshToday(reason: .captureSuccess)
        refsLibrary?.markStale()
        agendaStore?.refresh(reason: .submit)
    }

    /// Recheck Bob's Refs half: re-pointing the fetcher happens in
    /// `configureProcessClient`, and this restarts the watcher and
    /// refreshes the snapshot alongside the capture ones.
    func refreshRefsForRecheck() {
        refsLibrary?.restartWatcher()
        refsLibrary?.refresh(reason: .recheck)
    }

    private func configureVaultWatcher() {
        vaultWatcher?.invalidate()
        let vaultPath = Self.vaultRootURL(bobDirectory: settings.bobDirectory).path
        agendaStore?.vaultRootPath = vaultPath

        vaultWatcher = VaultTargetWatcher(path: vaultPath) { [weak self] in
            Task { @MainActor in
                self?.refreshTargetsWhenPossible()
            }
        } onBatch: { [weak self] batch in
            Task { @MainActor in
                self?.agendaStore?.vaultDidChange(batch)
            }
        } onFailure: { [weak self] message in
            Task { @MainActor in
                guard let self else {
                    return
                }
                let snapshot = await self.targetsCache.markStale(errorDescription: message)
                self.panelModel?.updateTargetCacheSnapshot(snapshot)
                self.settings.diagnosticStatus = "Target watcher stale: \(message)"
            }
        }

        vaultWatcher?.start()
    }

    private func showCapturePanel() {
        // Through the coordinator so showing Capture hides a visible Refs
        // panel: only one Bob panel is ever on screen.
        if let panelCoordinator {
            panelCoordinator.showCapture()
        } else {
            panelController?.show()
        }
        // One refresh updates both the shared cache and the panel snapshot. Starting
        // the model refresh as well would launch two `capture-targets` processes in
        // the same cancellation lane every time the panel opens.
        refreshTargetsWhenPossible()
    }

    @objc func pastePlainText(_ sender: Any?) {
        let inserted = PlainTextPaste.insert(
            into: NSApp.keyWindow?.firstResponder,
            from: .general,
            willInsert: { [weak self] in self?.panelModel?.dismissCompletion() }
        )
        guard !inserted else {
            return
        }
        NSApp.sendAction(Selector(("paste:")), to: nil, from: sender)
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(AppDelegate.pastePlainText(_:)) else {
            return true
        }
        guard CapturePanelController.editableTextView(NSApp.keyWindow?.firstResponder) != nil else {
            return false
        }
        return PlainTextPaste.plainText(from: .general) != nil
    }

    @objc private func openCapturePanel() {
        showCapturePanel()
    }

    @objc private func openRefsPanel() {
        panelCoordinator?.toggleRefs()
    }

    @objc func openSettings() {
        settingsPresentation.present()
    }

    /// Resets the agenda store when the bob executable or vault root
    /// setting changes, so a new executable retries `--tasks` and a new
    /// vault never shows the old vault's agenda.
    func observeBobSettings() {
        settings.$bobDirectory
            .dropFirst()
            .removeDuplicates()
            .combineLatest(
                settings.$bobExecutableOverride.dropFirst().removeDuplicates()
            )
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.agendaStore?.reset()
            }
            .store(in: &agendaCancellables)
    }

    @objc private func recheckBob() {
        configureProcessClient()
        panelModel?.processClient = processClient
        agendaStore?.processClient = processClient
        agendaStore?.reset()
        registerHotKey()
        configureVaultWatcher()
        // Recheck re-points the Refs fetcher (via configureProcessClient)
        // and restarts its watcher for the current vault root, plus a
        // snapshot refresh.
        refreshRefsForRecheck()
    }

    @objc private func restartApp() {
        CaptureSignpost.event("restart-requested")
        do {
            try relauncher.restart()
        } catch {
            let message = (error as? AppRelaunchError)?.message ?? String(describing: error)
            settings.diagnosticStatus = "Restart failed: \(message)"
            notificationService.notifyRestartFailure(message: message)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
struct SettingsPresentation {
    var openSettings: () -> Void
    var activateApplication: () -> Void

    init(
        openSettings: @escaping () -> Void = {},
        activateApplication: @escaping () -> Void = {
            NSApplication.shared.activate()
        }
    ) {
        self.openSettings = openSettings
        self.activateApplication = activateApplication
    }

    func present() {
        openSettings()
        activateApplication()
    }
}

private typealias SettingsSceneRepresentation = NSHostingSceneRepresentation<BobSettingsScene>

@MainActor
private struct BobSettingsScene: Scene {
    let settings: AppSettings
    let notificationService: NotificationService
    let canceledDraftStash: CanceledDraftStash
    let onResetOpenHistory: (() -> Void)?

    var body: some Scene {
        Settings {
            SettingsView(
                settings: settings,
                notificationService: notificationService,
                canceledDraftStash: canceledDraftStash,
                onResetOpenHistory: onResetOpenHistory
            )
        }
    }
}
