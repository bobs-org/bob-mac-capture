import SwiftUI

@main
struct BobMacCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: appDelegate.settings, notificationService: appDelegate.notificationService)
        }
    }
}
