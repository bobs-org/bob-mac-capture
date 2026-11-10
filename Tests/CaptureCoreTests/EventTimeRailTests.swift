import Foundation
import XCTest

@testable import CaptureCore

/// Portable geometry and content for the shared event-note time rail:
/// Bob's `"HH:MM"` bounds become normalized day coordinates, and the
/// structured effective fields become labels, without parsing note text.
final class EventTimeRailTests: XCTestCase {
    private func jsonString(_ value: String?) -> String {
        guard let value else {
            return "null"
        }
        let encoded = try! JSONSerialization.data(
            withJSONObject: [value], options: [])
        let text = String(data: encoded, encoding: .utf8)!
        return String(text.dropFirst().dropLast())
    }

    private func bounds(
        meetingStart: String?,
        meetingEnd: String?,
        occupiedStart: String? = nil,
        occupiedEnd: String? = nil,
        clipped: Bool? = nil
    ) -> (GcalNoteTimeBounds, GcalNoteOccupiedBounds?) {
        let meeting = try! JSONDecoder().decode(
            GcalNoteTimeBounds.self,
            from: Data(
                """
                {"start":\(jsonString(meetingStart)),"end":\(jsonString(meetingEnd))}
                """.utf8)
        )
        let occupied: GcalNoteOccupiedBounds?
        if occupiedStart == nil && occupiedEnd == nil && clipped == nil {
            occupied = nil
        } else {
            let payload = "{\"start\":\(jsonString(occupiedStart)),"
                + "\"end\":\(jsonString(occupiedEnd)),"
                + "\"clipped\":\(clipped.map { $0 ? "true" : "false" } ?? "null")}"
            occupied = try! JSONDecoder().decode(
                GcalNoteOccupiedBounds.self,
                from: Data(payload.utf8)
            )
        }
        return (meeting, occupied)
    }

    private func effective(
        meetingStart: String? = "10:00",
        meetingEnd: String? = "12:00",
        occupiedStart: String? = "09:30",
        occupiedEnd: String? = "12:15",
        clipped: Bool = false,
        beforeMinutes: Int? = 30,
        afterMinutes: Int? = 15,
        beforeReason: String? = "Drive to Deerwood",
        afterReason: String? = "Drive home",
        hue: String? = "orange",
        clock: String? = nil
    ) -> GcalNoteEffective {
        func minutes(_ value: Int?) -> String {
            value.map(String.init) ?? "null"
        }
        let fields = [
            "\"root\":{\"value\":\"family\",\"hue\":\(jsonString(hue))}",
            "\"clock\":\(jsonString(clock))",
            "\"buffer\":{\"before_minutes\":\(minutes(beforeMinutes)),"
                + "\"after_minutes\":\(minutes(afterMinutes)),"
                + "\"before_reason\":\(jsonString(beforeReason)),"
                + "\"after_reason\":\(jsonString(afterReason))}",
            "\"meeting\":{\"start\":\(jsonString(meetingStart)),"
                + "\"end\":\(jsonString(meetingEnd))}",
            "\"occupied\":{\"start\":\(jsonString(occupiedStart)),"
                + "\"end\":\(jsonString(occupiedEnd)),"
                + "\"clipped\":\(clipped ? "true" : "false")}",
            "\"fields\":[]",
        ]
        return try! JSONDecoder().decode(
            GcalNoteEffective.self,
            from: Data("{\(fields.joined(separator: ","))}".utf8)
        )
    }

    // MARK: - Clock parsing

    func testClockParsesMidnightEdges() {
        XCTAssertEqual(EventTimeRailGeometry.minutes("00:00"), 0)
        XCTAssertEqual(EventTimeRailGeometry.minutes("24:00"), 1_440)
        XCTAssertEqual(EventTimeRailGeometry.minutes("09:30"), 570)
        XCTAssertEqual(EventTimeRailGeometry.minutes("9:30"), 570)
        XCTAssertNil(EventTimeRailGeometry.minutes(nil))
        XCTAssertNil(EventTimeRailGeometry.minutes("24:01"))
        XCTAssertNil(EventTimeRailGeometry.minutes("25:00"))
        XCTAssertNil(EventTimeRailGeometry.minutes("10:60"))
        XCTAssertNil(EventTimeRailGeometry.minutes("nope"))
    }

    // MARK: - Geometry

    func testBothWingsFromReportedBounds() throws {
        let (meeting, occupied) = bounds(
            meetingStart: "10:00",
            meetingEnd: "12:00",
            occupiedStart: "09:30",
            occupiedEnd: "12:15"
        )
        let geometry = try XCTUnwrap(
            EventTimeRailGeometry(meeting: meeting, occupied: occupied))
        XCTAssertEqual(geometry.meetingStart, 600)
        XCTAssertEqual(geometry.meetingEnd, 720)
        XCTAssertEqual(geometry.occupiedStart, 570)
        XCTAssertEqual(geometry.occupiedEnd, 735)
        XCTAssertFalse(geometry.clipped)
        XCTAssertTrue(geometry.hasBuffer)
        let leading = try XCTUnwrap(geometry.leadingWing)
        XCTAssertEqual(leading.start, 570.0 / 1_440, accuracy: 1e-9)
        XCTAssertEqual(leading.end, 600.0 / 1_440, accuracy: 1e-9)
        XCTAssertFalse(leading.active)
        let trailing = try XCTUnwrap(geometry.trailingWing)
        XCTAssertEqual(trailing.start, 720.0 / 1_440, accuracy: 1e-9)
        XCTAssertEqual(trailing.end, 735.0 / 1_440, accuracy: 1e-9)
    }

    func testZeroWingsWithoutBuffer() throws {
        let (meeting, occupied) = bounds(
            meetingStart: "09:15",
            meetingEnd: "10:00",
            occupiedStart: "09:15",
            occupiedEnd: "10:00"
        )
        let geometry = try XCTUnwrap(
            EventTimeRailGeometry(meeting: meeting, occupied: occupied))
        XCTAssertNil(geometry.leadingWing)
        XCTAssertNil(geometry.trailingWing)
        XCTAssertFalse(geometry.hasBuffer)
    }

    func testSingleTrailingWing() throws {
        let (meeting, occupied) = bounds(
            meetingStart: "09:00",
            meetingEnd: "10:00",
            occupiedStart: "09:00",
            occupiedEnd: "10:05"
        )
        let geometry = try XCTUnwrap(
            EventTimeRailGeometry(meeting: meeting, occupied: occupied))
        XCTAssertNil(geometry.leadingWing)
        XCTAssertNotNil(geometry.trailingWing)
        XCTAssertTrue(geometry.hasBuffer)
    }

    func testMissingOccupiedMeansNoWings() throws {
        let (meeting, occupied) = bounds(
            meetingStart: "10:00",
            meetingEnd: "12:00"
        )
        XCTAssertNil(occupied)
        let geometry = try XCTUnwrap(
            EventTimeRailGeometry(meeting: meeting, occupied: occupied))
        XCTAssertNil(geometry.leadingWing)
        XCTAssertNil(geometry.trailingWing)
        XCTAssertFalse(geometry.hasBuffer)
    }

    func testMissingMeetingHasNoGeometry() {
        let (meeting, occupied) = bounds(
            meetingStart: nil,
            meetingEnd: nil,
            occupiedStart: "09:30",
            occupiedEnd: "12:15"
        )
        XCTAssertNil(EventTimeRailGeometry(meeting: meeting, occupied: occupied))
    }

    func testDegenerateBoundsStayFinite() throws {
        let (meeting, occupied) = bounds(
            meetingStart: "12:00",
            meetingEnd: "10:00",
            occupiedStart: "bogus",
            occupiedEnd: "24:99"
        )
        let geometry = try XCTUnwrap(
            EventTimeRailGeometry(meeting: meeting, occupied: occupied))
        for value in [
            geometry.meetingStart, geometry.meetingEnd,
            geometry.occupiedStart, geometry.occupiedEnd,
        ] {
            XCTAssertTrue(value.isFinite)
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1_440)
        }
        XCTAssertLessThanOrEqual(geometry.meetingStart, geometry.meetingEnd)
        XCTAssertLessThanOrEqual(geometry.occupiedStart, geometry.meetingStart)
        XCTAssertLessThanOrEqual(geometry.meetingEnd, geometry.occupiedEnd)
    }

    func testViewMathNeverGoesNegativeOrNaN() {
        XCTAssertEqual(
            EventTimeRailGeometry.spanWidth(
                start: 0.5, end: 0.25, totalWidth: 760), 0)
        XCTAssertEqual(
            EventTimeRailGeometry.spanWidth(
                start: .nan, end: .infinity, totalWidth: 760), 0)
        XCTAssertEqual(EventTimeRailGeometry.x(.nan, totalWidth: 760), 0)
        XCTAssertEqual(EventTimeRailGeometry.x(2, totalWidth: 760), 760)
        XCTAssertEqual(EventTimeRailGeometry.x(0.5, totalWidth: 0), 0)
        XCTAssertEqual(
            EventTimeRailGeometry.spanWidth(start: 0, end: 1, totalWidth: -4),
            0)
    }

    func testWingsActivateAroundNow() throws {
        let (meeting, occupied) = bounds(
            meetingStart: "10:00",
            meetingEnd: "12:00",
            occupiedStart: "09:30",
            occupiedEnd: "12:15"
        )
        let leadIn = try XCTUnwrap(
            EventTimeRailGeometry(
                meeting: meeting, occupied: occupied, nowMinutes: 585))
        XCTAssertEqual(leadIn.leadingWing?.active, true)
        XCTAssertEqual(leadIn.trailingWing?.active, false)
        let leadOut = try XCTUnwrap(
            EventTimeRailGeometry(
                meeting: meeting, occupied: occupied, nowMinutes: 730))
        XCTAssertEqual(leadOut.leadingWing?.active, false)
        XCTAssertEqual(leadOut.trailingWing?.active, true)
    }

    // MARK: - Content

    func testContentFromStructuredEffectiveFields() {
        let content = EventTimeRailContent(
            effective: effective(), answer: "yes")
        XCTAssertEqual(content.hue, .orange)
        XCTAssertFalse(content.offClock)
        XCTAssertFalse(content.maybe)
        XCTAssertEqual(content.beforeReason, "Drive to Deerwood")
        XCTAssertEqual(content.afterReason, "Drive home")
        XCTAssertEqual(content.leadingReasonLabel, "−30m Drive to Deerwood")
        XCTAssertEqual(content.trailingReasonLabel, "+15m Drive home")
        XCTAssertEqual(
            content.timeSummary, "Meeting 10:00–12:00 · Occupied 09:30–12:15")
        XCTAssertNil(content.clippingText)
        XCTAssertTrue(content.voiceOverSummary.contains("10:00 to 12:00"))
        XCTAssertTrue(content.voiceOverSummary.contains("09:30 to 12:15"))
        XCTAssertTrue(content.voiceOverSummary.contains("Drive to Deerwood"))
        XCTAssertTrue(content.voiceOverSummary.contains("Drive home"))
    }

    func testMissingReasonsOmitLabels() {
        let content = EventTimeRailContent(
            effective: effective(beforeReason: nil, afterReason: nil))
        XCTAssertNil(content.leadingReasonLabel)
        XCTAssertNil(content.trailingReasonLabel)
        XCTAssertFalse(content.voiceOverSummary.contains("Before:"))
        XCTAssertFalse(content.voiceOverSummary.contains("After:"))
    }

    func testBlankReasonsOmitLabels() {
        let content = EventTimeRailContent(
            effective: effective(beforeReason: "  ", afterReason: ""))
        XCTAssertNil(content.leadingReasonLabel)
        XCTAssertNil(content.trailingReasonLabel)
    }

    func testMidnightClippingLabels() {
        let before = EventTimeRailContent(
            effective: effective(
                meetingStart: "00:30", meetingEnd: "01:30",
                occupiedStart: "00:00", occupiedEnd: "01:30",
                clipped: true, beforeMinutes: 45, afterMinutes: 0,
                beforeReason: "Early train", afterReason: nil))
        XCTAssertEqual(before.clippingText, "Clipped at 00:00")
        XCTAssertTrue(before.voiceOverSummary.contains("Clipped at 00:00"))

        let after = EventTimeRailContent(
            effective: effective(
                meetingStart: "23:00", meetingEnd: "23:30",
                occupiedStart: "23:00", occupiedEnd: "24:00",
                clipped: true, beforeMinutes: 0, afterMinutes: 45,
                beforeReason: nil, afterReason: "Late train"))
        XCTAssertEqual(after.clippingText, "Clipped at 24:00")
    }

    func testClockAndAnswerStates() {
        let off = EventTimeRailContent(
            effective: effective(clock: "off"), answer: "yes")
        XCTAssertTrue(off.offClock)
        XCTAssertFalse(off.maybe)
        XCTAssertTrue(off.voiceOverSummary.contains("Off-clock"))

        let maybe = EventTimeRailContent(
            effective: effective(), answer: "maybe")
        XCTAssertTrue(maybe.maybe)
        XCTAssertTrue(maybe.voiceOverSummary.contains("Maybe"))
    }

    func testUnknownHueDegradesNeutrally() {
        let content = EventTimeRailContent(
            effective: effective(hue: "chartreuse"))
        XCTAssertEqual(content.hue, .other("chartreuse"))
        let missing = EventTimeRailContent(effective: effective(hue: nil))
        XCTAssertNil(missing.hue)
    }

    func testMissingMeetingFallsBack() {
        let content = EventTimeRailContent(
            effective: effective(meetingStart: nil, meetingEnd: nil))
        XCTAssertEqual(content.timeSummary, "Meeting time unavailable")
        XCTAssertTrue(
            content.voiceOverSummary.contains("Meeting time unavailable"))
    }
}
