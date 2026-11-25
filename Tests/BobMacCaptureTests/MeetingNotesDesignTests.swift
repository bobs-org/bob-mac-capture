import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Rendered-image review for Meeting Notes: chooser, parent/replace,
/// preview, and filed/queued receipts at 720 and 480 in both appearances.
@available(macOS 26.0, *)
@MainActor
final class MeetingNotesDesignTests: XCTestCase {
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

    func testRenderMeetingNotesSurfacesToPNG() async throws {
        guard ProcessInfo.processInfo.environment["BOB_MAC_CAPTURE_RENDER_DIR"] != nil else {
            throw XCTSkip(
                "Set BOB_MAC_CAPTURE_RENDER_DIR to render the meeting-notes review images."
            )
        }

        let preview = MeetingNotesPanelModel(processClient: client())
        preview.present()
        await waitUntil { preview.session?.state == .previewReady }
        try render(preview, base: "preview")

        preview.showChooser()
        await waitUntil { preview.session?.state == .choosingMeeting }
        try render(preview, base: "chooser")

        let parent = MeetingNotesPanelModel(
            processClient: client([
                "FAKE_BOB_MEETING_NOTES_PREVIEW_FIXTURE": "meeting-notes/needs-parent.json"
            ])
        )
        parent.present(eventRef: "20261124#^spruce-sync")
        await waitUntil { parent.session?.state == .choosingParent }
        try render(parent, base: "parent")

        let replace = MeetingNotesPanelModel(
            processClient: client([
                "FAKE_BOB_MEETING_NOTES_PREVIEW_FIXTURE": "meeting-notes/already-filed.json"
            ])
        )
        replace.present(eventRef: "20261124#^spruce-sync")
        await waitUntil { replace.session?.state == .confirmingReplace }
        try render(replace, base: "replace")

        let filed = MeetingNotesPanelModel(
            processClient: client()
        )
        filed.present()
        await waitUntil { filed.session?.state == .previewReady }
        filed.file()
        await waitUntil { filed.session?.state == .filed }
        try render(filed, base: "filed")

        let queued = MeetingNotesPanelModel(
            processClient: client([
                "FAKE_BOB_MEETING_NOTES_WRITE_FIXTURE": "meeting-notes/queued.json"
            ])
        )
        queued.present()
        await waitUntil { queued.session?.state == .previewReady }
        queued.file()
        await waitUntil { queued.session?.state == .queued }
        try render(queued, base: "queued")
    }

    private func render(_ model: MeetingNotesPanelModel, base: String) throws {
        let view = MeetingNotesPanelView(model: model)
            .padding(12)
        for width in [720, 480] as [CGFloat] {
            for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
                try renderHosted(
                    view,
                    name: "meeting-notes-\(base)-\(Int(width))",
                    width: width,
                    height: 520,
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
            throw XCTSkip("Set BOB_MAC_CAPTURE_RENDER_DIR to render meeting-notes fixtures.")
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
