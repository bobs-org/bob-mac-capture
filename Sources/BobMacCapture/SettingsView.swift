import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var launchStatus = LaunchAtLoginController().state()

    var body: some View {
        Form {
            Section("Bob") {
                TextField("Executable override", text: $settings.bobExecutableOverride)
                TextField("Vault path", text: $settings.bobDirectory)
                LabeledContent("Resolved path", value: settings.resolvedBobPath)
            }

            Section("Hotkey") {
                Toggle("Use production Control-Shift-Command-I", isOn: $settings.useProductionHotkey)
                LabeledContent("Active binding", value: settings.hotKeyConfiguration.displayName)
            }

            Section("Launch") {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { launchStatus.enabled },
                        set: { enabled in
                            do {
                                try LaunchAtLoginController().setEnabled(enabled)
                            } catch {
                                settings.diagnosticStatus = String(describing: error)
                            }
                            launchStatus = LaunchAtLoginController().state()
                        }
                    )
                )
                LabeledContent("Status", value: launchStatus.displayName)
            }

            Section("Diagnostics") {
                Text(settings.diagnosticStatus)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

struct LaunchAtLoginController {
    func state() -> LaunchAtLoginState {
        LaunchAtLoginState(status: SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

struct LaunchAtLoginState: Equatable {
    let enabled: Bool
    let displayName: String

    init(status: SMAppService.Status) {
        switch status {
        case .enabled:
            enabled = true
            displayName = "Enabled"
        case .requiresApproval:
            enabled = false
            displayName = "Requires approval in System Settings"
        case .notRegistered:
            enabled = false
            displayName = "Not registered"
        case .notFound:
            enabled = false
            displayName = "App bundle not found"
        @unknown default:
            enabled = false
            displayName = "Unknown"
        }
    }
}
