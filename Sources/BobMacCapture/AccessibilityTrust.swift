import AppKit
import ApplicationServices

/// The only home for Accessibility trust checks.
///
/// `isTrusted()` never prompts. Call `requestPrompt()` only from explicit user
/// gestures such as the Tabs permission card. Nothing calls either at launch.
enum AccessibilityTrust {
    /// Opens the macOS Accessibility privacy pane in System Settings.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Returns whether the app currently holds the Accessibility grant,
    /// without prompting.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
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
            return "Grants reset when an ad-hoc build is reinstalled. Re-add the app, or run `tccutil reset Accessibility org.bobs.bob-mac-capture`."
        }
        return "Already on in System Settings? Remove Bob Mac Capture there and add it again."
    }
}
