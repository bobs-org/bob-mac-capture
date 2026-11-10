import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Rendered-image review for the event-note time rail: one PNG per
/// rail case at full and minimum widths, in both appearances.
/// `BOB_MAC_CAPTURE_RENDER_DIR` points at a writable directory; when
/// set, writes the PNGs at scale 2. Inspect the PNGs with an image
/// reader and check the hatched wings, capsule size, reason labels,
/// time sentence, clipping label, and contrast against the epic
/// plan's rail section. Follows `CaptureAgendaDesignTests`.
@MainActor
final class EventTimeRailDesignTests: XCTestCase {
    func testRenderEventNoteRailToPNG() throws {
        guard let renderDir = ProcessInfo.processInfo.environment[
            "BOB_MAC_CAPTURE_RENDER_DIR"
        ], !renderDir.isEmpty else {
            throw XCTSkip(
                "Set BOB_MAC_CAPTURE_RENDER_DIR to render the rail review images."
            )
        }
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let longBefore = String(repeating: "Drive to Deerwood via the long way ", count: 4)
        let longAfter = String(repeating: "Drive home past the lake ", count: 4)
        let cases: [(String, GcalNoteEffective, String?, Double?)] = try [
            ("both-wings", try effective(), "yes", nil),
            ("both-wings-active", try effective(), "yes", 585),
            (
                "long-reasons",
                try effective {
                    var buffer = $0["buffer"] as! [String: Any]
                    buffer["before_reason"] = longBefore
                    buffer["after_reason"] = longAfter
                    $0["buffer"] = buffer
                },
                "yes",
                nil
            ),
            ("absent-reasons", try effective(from: "series_scope"), "yes", nil),
            ("single-wing", try effective(from: "both_scopes"), "yes", nil),
            ("zero-wings", try effective(from: "series_scope"), "yes", nil),
            (
                "midnight-clipping",
                try effective {
                    $0["meeting"] = ["start": "23:00", "end": "23:30"]
                    $0["occupied"] = [
                        "start": "23:00", "end": "24:00", "clipped": true,
                    ]
                    var buffer = $0["buffer"] as! [String: Any]
                    buffer["before_minutes"] = 0
                    buffer["before_reason"] = nil
                    buffer["after_minutes"] = 45
                    buffer["after_reason"] = "Late train"
                    $0["buffer"] = buffer
                },
                "yes",
                nil
            ),
            (
                "off-clock",
                try effective { $0["clock"] = "off" },
                "yes",
                nil
            ),
            ("maybe", try effective(), "maybe", nil),
        ]
        for (base, effective, answer, now) in cases {
            try render(
                effective: effective,
                answer: answer,
                nowMinutes: now,
                base: "rail-\(base)"
            )
        }
        // Increased contrast must keep the hatch and outlines visible.
        for base in ["both-wings", "midnight-clipping", "off-clock", "maybe"] {
            let match = try XCTUnwrap(cases.first { $0.0 == base })
            try render(
                effective: match.1,
                answer: match.2,
                nowMinutes: match.3,
                base: "rail-\(base)-high-contrast",
                contrast: .increased
            )
        }
    }

    private func render(
        effective: GcalNoteEffective,
        answer: String?,
        nowMinutes: Double?,
        base: String,
        contrast: ColorSchemeContrast = .standard
    ) throws {
        for width in [480, 220] as [CGFloat] {
            let rail = EventNoteRailView(
                effective: effective,
                answer: answer,
                nowMinutes: nowMinutes
            )
            .padding(12)
            .environment(\._colorSchemeContrast, contrast)
            for appearance in [
                NSAppearance.Name.aqua,
                NSAppearance.Name.darkAqua,
            ] {
                try RenderFixtureWriter.write(
                    rail,
                    name: "event-\(base)-\(Int(width))",
                    width: width,
                    appearance: appearance
                )
            }
        }
    }

    private func effective(
        from fixture: String = "show",
        mutate: (inout [String: Any]) -> Void = { _ in }
    ) throws -> GcalNoteEffective {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("gcal-note", isDirectory: true)
            .appendingPathComponent("\(fixture).json")
        let document = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)) as! [String: Any]
        var resolved = try XCTUnwrap(document["effective"] as? [String: Any])
        mutate(&resolved)
        // A nil reason must vanish from the payload, the way an older
        // supporting Bob omits the field, rather than decode as null.
        if var buffer = resolved["buffer"] as? [String: Any] {
            for key in ["before_reason", "after_reason"] {
                if buffer[key] is NSNull {
                    buffer.removeValue(forKey: key)
                }
            }
            resolved["buffer"] = buffer
        }
        let data = try JSONSerialization.data(withJSONObject: resolved)
        return try JSONDecoder().decode(GcalNoteEffective.self, from: data)
    }
}
