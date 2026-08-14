import AppKit
import CaptureCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()

    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var panelController: CapturePanelController?
    private let targetsCache = CaptureTargetsCache()
    private var processClient: BobProcessClient?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureProcessClient()

        let model = CapturePanelModel()
        panelController = CapturePanelController(model: model)
        panelController?.prewarm()

        hotKeyManager = HotKeyManager { [weak self] in
            Task { @MainActor in
                self?.showCapturePanel()
            }
        }
        registerHotKey()
        refreshTargetsWhenPossible()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.invalidate()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Bob"

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
        } catch {
            processClient = nil
            settings.resolvedBobPath = "Not resolved"
            settings.diagnosticStatus = String(describing: error)
        }
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
            let snapshot = await targetsCache.refresh(using: processClient)
            await MainActor.run {
                if let error = snapshot.errorDescription {
                    settings.diagnosticStatus = "Target cache stale: \(error)"
                }
            }
        }
    }

    private func showCapturePanel() {
        panelController?.show()
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
        registerHotKey()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
