import AppKit
import ApplicationServices
import Foundation

/// The only home for Accessibility trust checks and gesture-only grant repair.
///
/// `isTrusted()` never prompts. Call `resetGrant()` and `requestPrompt()` only
/// from an explicit user gesture while untrusted, such as the Tabs permission
/// card. Nothing calls them at launch.
enum AccessibilityTrust {
    static let bundleIdentifier = "org.bobs.bob-mac-capture"
    static let resetArguments = ["reset", "Accessibility", bundleIdentifier]

    /// Opens the macOS Accessibility privacy pane in System Settings.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Returns whether the app currently holds the Accessibility grant,
    /// without prompting.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Clears a stale Accessibility grant. Call only from an explicit user
    /// gesture, and only while the app is untrusted.
    @discardableResult
    static func resetGrant() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = resetArguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Re-checks trust with a system prompt when the grant is missing.
    /// Returns the post-prompt trust state.
    @discardableResult
    static func requestPrompt() -> Bool {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens Accessibility settings when the system prompt did not grant trust.
    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    /// The Settings › References "Highlights tabs" row value.
    static func statusText(isTrusted: Bool) -> String {
        isTrusted ? "Allowed" : "Not allowed"
    }

    /// The caption shown under the "Highlights tabs" row on ad-hoc builds,
    /// whose grants reset on every reinstall. Nil for stably signed builds.
    static func adHocCaption(isAdHocBuild: Bool) -> String? {
        isAdHocBuild ? "Grants reset when an ad-hoc build is reinstalled." : nil
    }

    /// Explains how to recover a missing or stale Accessibility grant.
    static func permissionHint(isAdHocBuild: Bool) -> String {
        if isAdHocBuild {
            return "Grants reset when an ad-hoc build is reinstalled. Open Accessibility Settings clears the stale grant; then switch Bob Mac Capture on."
        }
        return "Open Accessibility Settings clears any stale grant; then switch Bob Mac Capture on."
    }
}
