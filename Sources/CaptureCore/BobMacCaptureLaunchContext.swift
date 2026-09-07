import Foundation

// One-shot, process-scoped launch argument shared by BobMacCaptureInstallHelper and
// BobMacCapture. A process argument cannot survive a failed launch the way a marker
// file, UserDefaults key, or environment variable could, and it needs no cleanup.
public enum BobMacCaptureLaunchContext {
    public static let installRestartArgument = "--bob-mac-capture-install-restart"

    // True only when `arguments` contains the reserved token as an exact argv element.
    // Prefix, suffix, empty, and ordinary launch arguments do not opt in.
    public static func requestsInstallRestartNotification(_ arguments: [String]) -> Bool {
        arguments.contains(installRestartArgument)
    }
}
