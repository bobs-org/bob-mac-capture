import AppKit
import CaptureCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let notificationService = NotificationService()

    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var panelController: CapturePanelController?
    private var panelModel: CapturePanelModel?
    private var vaultWatcher: VaultTargetWatcher?
    private let targetsCache = CaptureTargetsCache()
    private var processClient: BobProcessClient?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureProcessClient()

        let model = CapturePanelModel(processClient: processClient, targetsCache: targetsCache)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.invalidate()
        vaultWatcher?.invalidate()
        processClient?.cancelActiveProcess()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Bob"
        item.button?.toolTip = "Bob Mac Capture"

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
                title: "Quit Bob Mac Capture",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )
        item.menu = menu
        statusItem = item
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
        panelModel?.refreshTargetCache()
        refreshTargetsWhenPossible()
    }

    @objc private func openCapturePanel() {
        showCapturePanel()
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate()
    }

    @objc private func recheckBob() {
        configureProcessClient()
        panelModel?.processClient = processClient
        registerHotKey()
        configureVaultWatcher()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
