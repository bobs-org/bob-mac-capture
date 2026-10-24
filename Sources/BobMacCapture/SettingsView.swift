import AppKit
import CaptureCore
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var canceledDraftStash: CanceledDraftStash
    @ObservedObject var savedTemplateShelf: SavedTemplateShelf
    var onResetOpenHistory: (() -> Void)? = nil
    @State private var launchStatus = LaunchAtLoginController().state()
    @State private var testNotificationStatus = ""
    @State private var isConfirmingStashClear = false
    @State private var isConfirmingTemplateClear = false
    @State private var isClearingTemplates = false
    @State private var templateClearStatus = ""
    @State private var isConfirmingRefsReset = false
    @State private var highlightsTabsAllowed = false
    @State private var isAdHocBuild = false

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

            Section("References") {
                Toggle(
                    "Open Bob Refs with Control-Shift-Command-O",
                    isOn: $settings.refsHotkeyEnabled
                )
                Stepper(
                    value: Binding(
                        get: { settings.refsInspectorNotesPageSize },
                        set: { settings.refsInspectorNotesPageSize = $0 }
                    ),
                    in: 1...20
                ) {
                    LabeledContent(
                        "Preview highlights per page",
                        value: "\(settings.refsInspectorNotesPageSize)"
                    )
                }
                Text(
                    "The preview shows this many highlights at first; "
                        + "Control-D at the bottom of the preview shows this many more."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Picker(
                    "In Highlights, open Bob Refs with",
                    selection: $settings.refsHighlightsOpenKey
                ) {
                    Text(RefsHighlightsOpenKey.off.displayName)
                        .tag(RefsHighlightsOpenKey.off)
                    Text(RefsHighlightsOpenKey.cmdO.displayName)
                        .tag(RefsHighlightsOpenKey.cmdO)
                    Text(RefsHighlightsOpenKey.ctrlO.displayName)
                        .tag(RefsHighlightsOpenKey.ctrlO)
                }
                Picker(
                    "In Highlights, show open tabs with",
                    selection: $settings.refsHighlightsTabsKey
                ) {
                    Text(RefsHighlightsTabsKey.cmdT.displayName)
                        .tag(RefsHighlightsTabsKey.cmdT)
                    Text(RefsHighlightsTabsKey.shiftCmdO.displayName)
                        .tag(RefsHighlightsTabsKey.shiftCmdO)
                    Text(RefsHighlightsTabsKey.cmdE.displayName)
                        .tag(RefsHighlightsTabsKey.cmdE)
                    Text(RefsHighlightsTabsKey.off.displayName)
                        .tag(RefsHighlightsTabsKey.off)
                }
                LabeledContent("Highlights app", value: highlightsAppDescription)
                HStack {
                    Button("Choose…") {
                        chooseHighlightsApp()
                    }
                    Button("Use Default") {
                        settings.refsHighlightsAppPath = ""
                    }
                }
                Toggle(
                    "Tell me when Bob updates an open PDF",
                    isOn: $settings.refsNotifyOpenPDFUpdates
                )
                HStack {
                    Toggle(
                        "Scan after ⌘S in Highlights",
                        isOn: $settings.refsScanOnHighlightsSave
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    if settings.refsScanOnHighlightsSave && !highlightsTabsAllowed {
                        Text("Needs Accessibility")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(
                    "Runs `bob ref scan -a -w` once Highlights finishes saving. Uses the Accessibility grant shown under Highlights tabs."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(
                    "Bob asks Highlights to save your unsaved highlights first; Highlights then reloads the PDF in place."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                LabeledContent(
                    "Highlights tabs",
                    value: AccessibilityTrust.statusText(isTrusted: highlightsTabsAllowed)
                )
                if let caption = AccessibilityTrust.adHocCaption(isAdHocBuild: isAdHocBuild) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Reset Open History…", role: .destructive) {
                    isConfirmingRefsReset = true
                }
                .disabled(onResetOpenHistory == nil)
                .accessibilityHint("Clears recently-opened rows and frecency.")
            }

            Section("Agenda") {
                Toggle(
                    "Show today's Pomodoros when the draft is empty",
                    isOn: $settings.agendaEnabled
                )
                if !settings.agendaDiagnostic.isEmpty {
                    Text(settings.agendaDiagnostic)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            "Agenda status, \(settings.agendaDiagnostic)"
                        )
                }
            }

            Section("Similar Tasks") {
                Toggle(
                    "Show similar tasks while capturing",
                    isOn: $settings.similarTasksEnabled
                )
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

                Text("Canceled drafts are stored on disk and survive quitting or restarting. Setting capacity to 0 or using Clear Stash... deletes the file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Clear Stash...", role: .destructive) {
                    isConfirmingStashClear = true
                }
                .disabled(canceledDraftStash.isEmpty)
                .accessibilityHint("Permanently removes retained canceled drafts.")
            }

            Section("Saved Templates") {
                switch savedTemplateShelf.availability {
                case .unknown:
                    Text("Loading saved templates…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .unsupported:
                    Text("Update bob to use saved templates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .available:
                    LabeledContent(
                        "Saved",
                        value: "\(savedTemplateShelf.count) \(savedTemplateShelf.count == 1 ? "template" : "templates") · up to \(savedTemplateShelf.capacity)"
                    )
                    if !savedTemplateShelf.saving {
                        Text("Saving is off (capture.max_saved_templates: 0)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !savedTemplateShelf.file.isEmpty {
                        HStack(alignment: .firstTextBaseline) {
                            Text("File")
                                .foregroundStyle(.secondary)
                            Text(savedTemplateShelf.file)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([
                                    URL(fileURLWithPath: savedTemplateShelf.file)
                                ])
                            }
                        }
                    }
                }

                Text("bob saves the template block after each successful @@template: capture. Rows are never saved. Type @@@ at the start of a draft to begin one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Clear Templates…", role: .destructive) {
                    isConfirmingTemplateClear = true
                }
                .disabled(
                    savedTemplateShelf.count == 0
                        || savedTemplateShelf.isUnsupported
                        || isClearingTemplates
                )
                .accessibilityHint("Permanently removes saved templates and their quarantine copy.")
                if !templateClearStatus.isEmpty {
                    Text(templateClearStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            Text("This removes retained canceled drafts.")
        }
        .confirmationDialog(
            "Clear saved templates?",
            isPresented: $isConfirmingTemplateClear
        ) {
            Button("Clear Templates", role: .destructive) {
                clearSavedTemplates()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved template and its quarantine copy.")
        }
        .confirmationDialog(
            "Reset Bob Refs open history?",
            isPresented: $isConfirmingRefsReset
        ) {
            Button("Reset History", role: .destructive) {
                onResetOpenHistory?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears recently-opened rows and frecency.")
        }
        .task {
            refreshHighlightsTabsStatus()
            await notificationService.refreshAuthorizationStatus()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            refreshHighlightsTabsStatus()
        }
    }

    /// Re-reads the Accessibility grant and the ad-hoc build state for the
    /// "Highlights tabs" row. Never prompts.
    private func refreshHighlightsTabsStatus() {
        highlightsTabsAllowed = AccessibilityTrust.isTrusted()
        isAdHocBuild = BundleSigningInspector.currentBundleState() == .adHoc
    }

    private func clearSavedTemplates() {
        guard !isClearingTemplates else {
            return
        }
        isClearingTemplates = true
        templateClearStatus = ""
        Task { @MainActor in
            defer { isClearingTemplates = false }
            do {
                guard let response = try await savedTemplateShelf.clearSavedTemplates() else {
                    templateClearStatus = "Bob is not resolved"
                    return
                }
                templateClearStatus = response.ok
                    ? "Templates cleared"
                    : (response.error ?? "Templates could not be cleared")
            } catch let error as BobClientError {
                if case .unsupportedCommand = error {
                    savedTemplateShelf.refresh(reason: .recheck)
                    templateClearStatus = "Update bob to use saved templates"
                } else {
                    templateClearStatus = error.description
                }
            } catch {
                templateClearStatus = String(describing: error)
            }
        }
    }

    /// The resolved Highlights app's name, version, and path, or
    /// "Not found" when neither the override path nor the bundle id
    /// resolves.
    private var highlightsAppDescription: String {
        let path = settings.refsHighlightsAppPath
        let locator = HighlightsLocator(overridePath: { path })
        guard let url = locator.highlightsAppURL() else {
            return "Not found"
        }
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let versionKey = "CFBundleShortVersionString"
        let version = (bundle?.object(forInfoDictionaryKey: versionKey) as? String)
            .map { " \($0)" } ?? ""
        return "\(name)\(version)\n\(url.path)"
    }

    private func chooseHighlightsApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        settings.refsHighlightsAppPath = url.path
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
