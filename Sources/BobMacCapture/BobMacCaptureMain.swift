import AppKit

// `@NSApplicationDelegateAdaptor` used to construct `AppDelegate`, retain it, and assign
// it to `NSApplication.delegate` under the SwiftUI app lifecycle. Now that `AppDelegate`
// is the entry point's only actor, this enum must perform those same three steps itself:
// `NSApplication.delegate` is `weak`, so without the `delegate` static property below
// holding a strong reference, `AppDelegate` would be deallocated immediately and
// `applicationWillFinishLaunching`/`applicationDidFinishLaunching` would never run.
@main
enum BobMacCaptureMain {
    @MainActor
    private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        application.delegate = appDelegate
        application.run()
    }
}
