import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Rendered-image review for Event note mode: picker, editor, invalid,
/// saving, saved/waiting, and unsupported, at full and minimum widths
/// in both appearances.
@MainActor
final class GcalNoteEditorDesignTests: XCTestCase {
    private var testsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func client(_ environment: [String: String] = [:]) -> BobProcessClient {
        BobProcessClient(
            executablePath: testsRoot.appendingPathComponent("Fixtures/fake-bob").path,
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"].merging(environment) {
                _, new in new
            }
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testRenderEventNoteSurfacesToPNG() async throws {
        guard ProcessInfo.processInfo.environment["BOB_MAC_CAPTURE_RENDER_DIR"] != nil else {
            throw XCTSkip(
                "Set BOB_MAC_CAPTURE_RENDER_DIR to render the event-note review images."
            )
        }

        let matchingPair = client([
            "FAKE_BOB_GCAL_NOTE_SHOW_FIXTURE": "gcal-note/show_preview_match.json",
            "FAKE_BOB_GCAL_NOTE_PREVIEW_FIXTURE": "gcal-note/preview_match.json",
        ])
        let picker = GcalNotePanelModel(processClient: matchingPair)
        picker.present()
        await waitUntil { picker.session?.phase == .listing }
        try render(picker, base: "picker")

        picker.openSelectedEvent()
        await waitUntil {
            picker.session?.phase == .editing
                && picker.session?.previewResponse?.input?.text
                    == picker.session?.editorText
        }
        XCTAssertFalse(picker.session?.isEditorDirty ?? true)
        try render(picker, base: "editor")

        let invalid = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_PREVIEW_FIXTURE": "gcal-note/invalid.json"
            ]))
        invalid.present()
        await waitUntil { invalid.session?.phase == .listing }
        invalid.openSelectedEvent()
        await waitUntil { invalid.session?.phase == .editing }
        invalid.session?.setEditorText("@famly")
        await waitUntil {
            invalid.session?.phase == .editing
                && invalid.session?.livePreview.isInvalid == true
        }
        try render(invalid, base: "invalid")

        let saving = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_DELAY_SECONDS": "1"
            ]))
        saving.present()
        await waitUntil { saving.session?.phase == .listing }
        saving.openSelectedEvent()
        await waitUntil { saving.session?.phase == .editing }
        saving.session?.setEditorText("@family")
        saving.save()
        await waitUntil { saving.session?.phase == .writing }
        try render(saving, base: "saving")
        await waitUntil { saving.session?.phase == .listing }

        let saved = GcalNotePanelModel(processClient: client())
        saved.present()
        await waitUntil { saved.session?.phase == .listing }
        saved.openSelectedEvent()
        await waitUntil { saved.session?.phase == .editing }
        saved.session?.setEditorText("@family")
        saved.save()
        await waitUntil { saved.session?.phase == .listing }
        try render(saved, base: "saved-waiting")

        let unsupported = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_UNSUPPORTED": "1"
            ]))
        unsupported.present()
        await waitUntil { unsupported.session?.phase == .unsupported }
        try render(unsupported, base: "unsupported")
    }

    private func render(_ model: GcalNotePanelModel, base: String) throws {
        let view = GcalNotePickerView(model: model)
            .padding(12)
        for width in [720, 480] as [CGFloat] {
            for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
                try renderHosted(
                    view,
                    name: "event-note-\(base)-\(Int(width))",
                    width: width,
                    height: 780,
                    appearance: appearance
                )
            }
        }
    }

    private func renderHosted<V: View>(
        _ view: V,
        name: String,
        width: CGFloat,
        height: CGFloat,
        appearance: NSAppearance.Name
    ) throws {
        guard
            let renderDir = ProcessInfo.processInfo.environment[
                "BOB_MAC_CAPTURE_RENDER_DIR"
            ],
            !renderDir.isEmpty
        else {
            throw XCTSkip("Set BOB_MAC_CAPTURE_RENDER_DIR to render event-note fixtures.")
        }
        _ = NSApplication.shared
        let dark = appearance == .darkAqua
        let host = NSHostingView(
            rootView:
                view
                .frame(width: width, height: height, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
        )
        host.appearance = NSAppearance(named: appearance)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(
            to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }
}
