import AppKit
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Rendered-image review for the Settings scroll container: top, middle,
/// and bottom viewports in both appearances. Uses `NSHostingView` plus
/// `cacheDisplay` because `ImageRenderer` cannot draw AppKit-backed
/// controls. Skips when the render directory is unset.
@available(macOS 26.0, *)
@MainActor
final class SettingsScrollDesignTests: XCTestCase {
    func testRenderSettingsScrollStatesToPNG() throws {
        guard
            let renderDir = ProcessInfo.processInfo.environment[
                "BOB_MAC_CAPTURE_RENDER_DIR"
            ],
            !renderDir.isEmpty
        else {
            throw XCTSkip(
                "Set BOB_MAC_CAPTURE_RENDER_DIR to render settings review images."
            )
        }
        _ = NSApplication.shared
        for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
            let window = makeWindow()
            defer { window.close() }
            settle(window)
            try render(window, base: "settings-scroll-top", appearance: appearance)
            page(window, times: 2)
            try render(
                window, base: "settings-scroll-middle", appearance: appearance
            )
            page(window, times: 40)
            try render(
                window, base: "settings-scroll-bottom", appearance: appearance
            )
            _ = renderDir
        }
    }

    private func makeWindow() -> NSWindow {
        let content = SettingsScrollContainer(scrollPerformer: instant()) {
            Form {
                Section("References") {
                    Picker(
                        "In Highlights, show open tabs with",
                        selection: .constant(0)
                    ) {
                        Text("Command-T").tag(0)
                        Text("Shift-Command-O").tag(1)
                    }
                    Toggle(
                        "Show today's Pomodoros when the draft is empty",
                        isOn: .constant(true)
                    )
                    Text(
                        "Runs `bob ref scan -a -w` once Highlights finishes"
                            + " saving. Uses the Accessibility grant shown"
                            + " under Highlights tabs, and Bob asks Highlights"
                            + " to save first while the scan settles."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Section("Snoozed Tasks") {
                    Toggle("Announce wakes", isOn: .constant(true))
                    Text(
                        "Off discards pending notices and clears the beacon"
                            + " and records, but keeps a healthy claim so auto"
                            + " never falls back to a desktop banner. The wake"
                            + " scheduler runs independently and applies live."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Toggle("Chime", isOn: .constant(true))
                    Text(
                        "One soft system chime exactly once on actual"
                            + " presentation. Applies live to every wake."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(0..<40) { index in
                    Section("Section \(index)") {
                        Toggle(
                            "Row \(index) toggle with a long label",
                            isOn: .constant(true)
                        )
                        Text("Caption \(index) that wraps fully in place.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.columns)
        }
        .frame(width: 620, height: 640)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: 620, height: 640)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        return window
    }

    private func instant() -> SettingsScrollPerform {
        { scrollView, target, flipped, completion in
            guard let documentView = scrollView.documentView else {
                completion()
                return
            }
            let clipView = scrollView.contentView
            let originY = RefsInspectorScrollGeometry.clipOriginY(
                forContentTopOffset: target,
                contentHeight: documentView.frame.height,
                viewportHeight: clipView.bounds.height,
                isFlipped: flipped
            )
            clipView.scroll(
                to: NSPoint(x: clipView.bounds.origin.x, y: originY)
            )
            scrollView.reflectScrolledClipView(clipView)
            completion()
        }
    }

    private func settle(_ window: NSWindow) {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
            if let scroll = anchorScroll(in: window),
                let documentView = scroll.documentView,
                documentView.frame.height > scroll.contentView.bounds.height + 40
            {
                return
            }
        }
    }

    private func page(_ window: NSWindow, times: Int) {
        guard
            let anchor = SettingsScrollKeyView.findAnchor(
                in: window.contentView
            )
        else {
            return
        }
        for _ in 0..<times {
            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .control,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "d",
                charactersIgnoringModifiers: "d",
                isARepeat: false,
                keyCode: 2
            )!
            _ = anchor.processKeyEvent(event)
        }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    private func anchorScroll(in window: NSWindow) -> NSScrollView? {
        SettingsScrollKeyView.findAnchor(in: window.contentView)?
            .enclosingScrollView
    }

    private func render(
        _ window: NSWindow,
        base: String,
        appearance: NSAppearance.Name
    ) throws {
        guard
            let renderDir = ProcessInfo.processInfo.environment[
                "BOB_MAC_CAPTURE_RENDER_DIR"
            ],
            !renderDir.isEmpty
        else {
            throw XCTSkip(
                "Set BOB_MAC_CAPTURE_RENDER_DIR to render settings fixtures."
            )
        }
        guard let contentView = window.contentView else {
            XCTFail("settings render host missing")
            return
        }
        let dark = appearance == .darkAqua
        window.appearance = NSAppearance(named: appearance)
        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bounds = contentView.bounds
        guard
            let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds)
        else {
            XCTFail("settings render bitmap missing")
            return
        }
        contentView.cacheDisplay(in: bounds, to: rep)
        guard
            let png = rep.representation(using: .png, properties: [:])
        else {
            XCTFail("settings render PNG missing")
            return
        }
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try png.write(
            to: directory.appendingPathComponent(
                "\(base)-\(dark ? "dark" : "light").png"
            )
        )
    }
}
