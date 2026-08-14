import AppKit
import CaptureCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    // Lazy because NotificationService's default center is `UNUserNotificationCenter.current()`,
    // which raises NSInternalInconsistencyException in a process that has no app bundle. Eagerly
    // building it here made `AppDelegate()` unconstructible under `swift test`, aborting the whole
    // xctest process. Every real touch still happens at or after `applicationWillFinishLaunching`,
    // so the delegate is assigned before any authorization request exactly as before.
    lazy var notificationService = NotificationService()

    var settingsPresentation = SettingsPresentation()
    var relauncher = AppRelauncher()

    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var panelController: CapturePanelController?
    private var panelModel: CapturePanelModel?
    private var vaultWatcher: VaultTargetWatcher?
    private let targetsCache = CaptureTargetsCache()
    private var processClient: BobProcessClient?
    private var settingsSceneRepresentation: SettingsSceneRepresentation?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // No nib supplies a main menu under the explicit `BobMacCaptureMain` entry point,
        // so without this the app loses Cmd-X/C/V/A/Z and Cmd-Q even though it is not a
        // regular windowed app.
        NSApp.mainMenu = Self.makeMainMenu()

        let settings = settings
        let notificationService = notificationService
        let representation = NSHostingSceneRepresentation {
            BobSettingsScene(
                settings: settings,
                notificationService: notificationService
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

        let model = CapturePanelModel(processClient: processClient)
        model.notificationService = notificationService
        panelModel = model
        panelController = CapturePanelController(model: model)
        panelController?.prewarm()

        hotKeyManager = HotKeyManager { [weak self] in
            CaptureSignpost.event("hotkey-received")
            Task { @MainActor in
                self?.showCapturePanel()
            }
        }
        registerHotKey()
        configureVaultWatcher()
        refreshTargetsWhenPossible()
        settings.signingDiagnostic = BundleSigningInspector.currentBundleState().diagnosticText
        CaptureSignpost.event("launch-complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.invalidate()
        vaultWatcher?.invalidate()
        processClient?.cancelActiveProcess()
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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Bob"
        item.button?.toolTip = "Bob Mac Capture"
        item.menu = Self.makeStatusMenu()
        statusItem = item
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
        } catch {
            processClient = nil
            settings.resolvedBobPath = "Not resolved"
            settings.diagnosticStatus = String(describing: error)
            panelModel?.setProcessClient(nil)
        }
        updateStatusItemAppearance()
    }

    // The menu-bar glyph is the only always-visible surface for an `LSUIElement` app,
    // so it must reflect a broken bob resolution at a glance without opening Settings.
    private func updateStatusItemAppearance() {
        statusItem?.button?.title = processClient == nil ? "Bob \u{26A0}\u{FE0F}" : "Bob"
        statusItem?.button?.toolTip = processClient == nil
            ? "Bob Mac Capture — bob is not resolved. Check Settings."
            : "Bob Mac Capture"
    }

    private func registerHotKey() {
        do {
            try hotKeyManager?.register(configuration: settings.hotKeyConfiguration)
            settings.diagnosticStatus = "Hotkey registered: \(settings.hotKeyConfiguration.displayName)"
        } catch {
            settings.diagnosticStatus = "Hotkey conflict: \(error)"
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

    private func configureVaultWatcher() {
        vaultWatcher?.invalidate()
        let vaultPath = settings.bobDirectory.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("bob")
                .path
            : settings.bobDirectory

        vaultWatcher = VaultTargetWatcher(path: vaultPath) { [weak self] in
            Task { @MainActor in
                self?.refreshTargetsWhenPossible()
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
        panelController?.show()
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

    @objc func openSettings() {
        settingsPresentation.present()
    }

    @objc private func recheckBob() {
        configureProcessClient()
        panelModel?.processClient = processClient
        registerHotKey()
        configureVaultWatcher()
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

    var body: some Scene {
        Settings {
            SettingsView(settings: settings, notificationService: notificationService)
        }
    }
}
