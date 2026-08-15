import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var canceledDraftStash: CanceledDraftStash
    @State private var launchStatus = LaunchAtLoginController().state()
    @State private var testNotificationStatus = ""
    @State private var isConfirmingStashClear = false

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

            Section("Canceled Draft Stash") {
                Stepper(
                    value: Binding(
                        get: { settings.canceledDraftStashCapacity },
                        set: { settings.canceledDraftStashCapacity = $0 }
                    ),
                    in: 0...CanceledDraftStash.maximumCapacity
                ) {
                    LabeledContent("Capacity", value: stashCapacityLabel)
                }
                .accessibilityHint("Set to zero to turn off canceled draft stashing.")

                LabeledContent("Retained", value: retainedDraftCountLabel)

                Text("Canceled draft text stays only in memory for this app session. Quitting or restarting clears it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Clear Stash...", role: .destructive) {
                    isConfirmingStashClear = true
                }
                .disabled(canceledDraftStash.isEmpty)
                .accessibilityHint("Permanently removes retained canceled drafts from this app session.")
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

            Section("Notifications") {
                LabeledContent("Authorization", value: notificationService.authorization.displayName)
                if notificationService.authorization.canRequestAuthorization {
                    Button("Enable Notifications") {
                        notificationService.requestAuthorization()
                    }
                }
                Button("Open System Notification Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Send Test Notification") {
                    Task {
                        do {
                            try await notificationService.sendTestNotification()
                            testNotificationStatus = "Test notification sent"
                        } catch {
                            testNotificationStatus = "Test notification failed: \(error)"
                        }
                    }
                }
                if !testNotificationStatus.isEmpty {
                    Text(testNotificationStatus)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Diagnostics") {
                Text(settings.diagnosticStatus)
                    .textSelection(.enabled)
                LabeledContent("Signing", value: settings.signingDiagnostic)
                if !settings.diagnosticHistory.isEmpty {
                    DisclosureGroup("Recent activity") {
                        ForEach(Array(settings.diagnosticHistory.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .confirmationDialog(
            "Clear canceled draft stash?",
            isPresented: $isConfirmingStashClear
        ) {
            Button("Clear Stash", role: .destructive) {
                canceledDraftStash.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes retained canceled drafts from this app session.")
        }
        .task {
            await notificationService.refreshAuthorizationStatus()
        }
    }

    private var stashCapacityLabel: String {
        settings.canceledDraftStashCapacity == 0 ? "Off" : "\(settings.canceledDraftStashCapacity)"
    }

    private var retainedDraftCountLabel: String {
        let count = canceledDraftStash.count
        return "\(count) \(count == 1 ? "draft" : "drafts")"
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
