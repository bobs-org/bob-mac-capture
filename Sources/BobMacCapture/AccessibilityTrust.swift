import ApplicationServices

/// The only home for Accessibility trust checks.
///
/// `isTrusted()` never prompts. Call `requestPrompt()` only from explicit user
/// gestures such as the Tabs permission card. Nothing calls either at launch.
enum AccessibilityTrust {
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

    /// The Settings › References "Highlights tabs" row value.
    static func statusText(isTrusted: Bool) -> String {
        isTrusted ? "Allowed" : "Not allowed"
    }

    /// The caption shown under the "Highlights tabs" row on ad-hoc builds,
    /// whose grants reset on every reinstall. Nil for stably signed builds.
    static func adHocCaption(isAdHocBuild: Bool) -> String? {
        isAdHocBuild ? "Grants reset when an ad-hoc build is reinstalled." : nil
    }
}
