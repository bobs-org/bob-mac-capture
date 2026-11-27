import AppKit
import SwiftUI

/// The Settings window. A titled, vertically-resizable panel that becomes
/// key — so keyboard input and Control-D/U reach it at once — without
/// activating the app. Activation requests from the status menu are
/// declined on macOS 26, so Settings is hosted here, like Capture and
/// Refs, instead of the SwiftUI `Settings` scene.
final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    /// Command-W closes Settings. Nothing else does: Esc, q, and Ctrl+[
    /// stay unbound here. The q/Ctrl+[/Esc mirror covers panels that Esc
    /// closes, and Settings is not one.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
            event.charactersIgnoringModifiers == "w"
        {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Owns the Settings panel: lazy creation, frame persistence, and an
/// idempotent `show()` that deminiaturizes when needed and orders the
/// panel front as the key window on the current Space. Never calls
/// `NSApp.activate()`: the non-activating panel takes focus on its own.
@MainActor
final class SettingsWindowController<Content: View> {
    static var autosaveName: String {
        "BobMacCaptureSettingsPanel"
    }

    private let makeContent: () -> Content
    private let bundleName: String
    private var panel: SettingsPanel?
    private var hostingController: NSHostingController<Content>?

    init(bundleName: String? = nil, makeContent: @escaping () -> Content) {
        self.bundleName =
            bundleName
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Bob Mac Capture"
        self.makeContent = makeContent
    }

    /// Shows the Settings panel, creating it on first use. Idempotent:
    /// calling it with the panel already open, buried behind other apps,
    /// or minimized brings that same panel forward with keyboard focus.
    @discardableResult
    func show() -> SettingsPanel {
        let panel = makePanelIfNeeded()
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        return panel
    }

    /// The panel title for a bundle name. One shape for production
    /// ("Bob Mac Capture Settings") and the Accept copy
    /// ("Bob Mac Capture Accept Settings").
    nonisolated static func settingsTitle(bundleName: String) -> String {
        "\(bundleName) Settings"
    }

    /// The first-show height: the scroll container's ideal height for the
    /// visible screen, between its 420 pt floor and 820 pt ceiling.
    nonisolated static func initialHeight(visibleHeight: CGFloat? = nil) -> CGFloat {
        let visible = visibleHeight ?? NSScreen.main?.visibleFrame.height ?? 900
        return max(
            SettingsScrollMetrics.minHeight,
            min(
                SettingsScrollMetrics.maxIdealHeight,
                visible - SettingsScrollMetrics.screenMargin
            )
        )
    }

    private func makePanelIfNeeded() -> SettingsPanel {
        if let panel {
            return panel
        }
        let created = SettingsPanel(
            contentRect: NSRect(
                x: 0, y: 0, width: SettingsScrollMetrics.fixedWidth,
                height: Self.initialHeight()),
            styleMask: [
                .titled, .closable, .miniaturizable, .resizable,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )
        created.title = Self.settingsTitle(bundleName: bundleName)
        created.isFloatingPanel = false
        created.level = .normal
        created.hidesOnDeactivate = false
        created.isReleasedWhenClosed = false
        created.becomesKeyOnlyIfNeeded = false
        created.collectionBehavior = [.moveToActiveSpace]
        created.contentMinSize = NSSize(
            width: SettingsScrollMetrics.fixedWidth,
            height: SettingsScrollMetrics.minHeight)
        let maxHeight =
            NSScreen.main?.visibleFrame.height ?? SettingsScrollMetrics.maxIdealHeight
        created.contentMaxSize = NSSize(
            width: SettingsScrollMetrics.fixedWidth, height: maxHeight)
        created.setFrameAutosaveName(Self.autosaveName)
        if !created.setFrameUsingName(Self.autosaveName), NSScreen.main != nil {
            created.center()
        }
        let hosting = NSHostingController(rootView: makeContent())
        hostingController = hosting
        created.contentViewController = hosting
        panel = created
        return created
    }
}
