import Foundation

/// Wall-clock bounds for the event-note time rail.
///
/// Bob reports the meeting and occupied spans as `"HH:MM"` strings on the
/// note day (`effective.meeting` / `effective.occupied`), with `"24:00"`
/// for an end at midnight and `occupied.clipped` when the buffered span
/// runs past midnight. This type converts only those reported strings to
/// normalized display geometry; it never derives buffers or clipping from
/// typed note text.
public struct EventTimeRailGeometry: Hashable, Equatable, Sendable {
    /// One buffer wing fused to the meeting capsule, in normalized
    /// day coordinates. `active` while `now` sits inside the wing.
    public struct Wing: Hashable, Equatable, Sendable {
        public let start: Double
        public let end: Double
        public let active: Bool

        public init(start: Double, end: Double, active: Bool = false) {
            self.start = start
            self.end = end
            self.active = active
        }
    }

    /// Minutes in the rail's fixed `00:00`–`24:00` domain.
    public static let minutesPerDay: Double = 1_440

    public let meetingStart: Double
    public let meetingEnd: Double
    public let occupiedStart: Double
    public let occupiedEnd: Double
    public let clipped: Bool
    public let leadingWing: Wing?
    public let trailingWing: Wing?

    private init(
        meetingStart: Double,
        meetingEnd: Double,
        occupiedStart: Double,
        occupiedEnd: Double,
        clipped: Bool,
        nowMinutes: Double?
    ) {
        self.meetingStart = meetingStart
        self.meetingEnd = meetingEnd
        self.occupiedStart = occupiedStart
        self.occupiedEnd = occupiedEnd
        self.clipped = clipped
        if occupiedStart < meetingStart {
            self.leadingWing = Wing(
                start: occupiedStart / Self.minutesPerDay,
                end: meetingStart / Self.minutesPerDay,
                active: nowMinutes.map {
                    occupiedStart <= $0 && $0 < meetingStart
                } ?? false
            )
        } else {
            self.leadingWing = nil
        }
        if meetingEnd < occupiedEnd {
            self.trailingWing = Wing(
                start: meetingEnd / Self.minutesPerDay,
                end: occupiedEnd / Self.minutesPerDay,
                active: nowMinutes.map {
                    meetingEnd < $0 && $0 <= occupiedEnd
                } ?? false
            )
        } else {
            self.trailingWing = nil
        }
    }

    /// Geometry from Bob's reported bounds. Nil when the meeting bounds
    /// are missing or unparseable. A missing occupied span means no
    /// wings. Degenerate bounds collapse to a zero-width capsule at the
    /// meeting start: widths are never negative and never NaN.
    public init?(
        meeting: GcalNoteTimeBounds?,
        occupied: GcalNoteOccupiedBounds?,
        nowMinutes: Double? = nil
    ) {
        guard let start = Self.minutes(meeting?.start),
            let rawEnd = Self.minutes(meeting?.end)
        else {
            return nil
        }
        // A `"00:00"` end after a nonzero start closes at midnight.
        let end = rawEnd <= start && rawEnd == 0 ? Self.minutesPerDay : rawEnd
        let meetingEnd = max(start, min(end, Self.minutesPerDay))
        var occupiedStart = Self.minutes(occupied?.start) ?? start
        var occupiedEnd = Self.minutes(occupied?.end) ?? meetingEnd
        occupiedStart = min(max(occupiedStart, 0), start)
        occupiedEnd = max(min(occupiedEnd, Self.minutesPerDay), meetingEnd)
        self.init(
            meetingStart: start,
            meetingEnd: meetingEnd,
            occupiedStart: occupiedStart,
            occupiedEnd: occupiedEnd,
            clipped: occupied?.clipped ?? false,
            nowMinutes: nowMinutes.flatMap(Self.sanitizeMinutes)
        )
    }

    /// Minutes since midnight for a `"HH:MM"` string, accepting
    /// `"24:00"`. Nil for anything else.
    public static func minutes(_ raw: String?) -> Double? {
        guard let raw else {
            return nil
        }
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]),
            let minute = Int(parts[1]), minute >= 0, minute < 60
        else {
            return nil
        }
        if hour == 24 {
            return minute == 0 ? minutesPerDay : nil
        }
        guard hour >= 0, hour < 24 else {
            return nil
        }
        return Double(hour * 60 + minute)
    }

    /// Display x for a normalized position, clamped into the strip so
    /// narrow or degenerate widths stay finite and non-negative.
    public static func x(_ position: Double, totalWidth: Double) -> Double {
        guard totalWidth.isFinite, totalWidth > 0 else {
            return 0
        }
        let clamped = position.isFinite ? min(1, max(0, position)) : 0
        return clamped * totalWidth
    }

    /// Display width for a normalized span. Never negative, never NaN;
    /// the caller keeps its own minimum (the agenda keeps 2 pt).
    public static func spanWidth(
        start: Double,
        end: Double,
        totalWidth: Double
    ) -> Double {
        guard totalWidth.isFinite, totalWidth > 0 else {
            return 0
        }
        let width = (end.isFinite ? end : 0) - (start.isFinite ? start : 0)
        return max(0, width) * totalWidth
    }

    private static func sanitizeMinutes(_ value: Double) -> Double? {
        guard value.isFinite else {
            return nil
        }
        return min(max(value, 0), minutesPerDay)
    }
}

/// Textual content for the event-note rail, drawn only from Bob's
/// structured `effective` fields. Missing optional reason fields (an
/// older supporting Bob) omit the reason label; preview bullets are
/// never scraped.
public struct EventTimeRailContent: Hashable, Equatable, Sendable {
    public let hue: PomodoroHomeHue?
    public let offClock: Bool
    public let maybe: Bool
    public let beforeReason: String?
    public let afterReason: String?
    public let beforeMinutes: Int?
    public let afterMinutes: Int?
    public let meetingText: String?
    public let occupiedText: String?
    /// `"Meeting 10:00–12:00"`, plus `" · Occupied 09:30–12:15"` when
    /// the event reserves a buffer.
    public let timeSummary: String
    /// Explicit midnight-clipping label, nil when unclipped.
    public let clippingText: String?
    /// Spoken summary covering both spans and both reasons.
    public let voiceOverSummary: String

    /// - Parameters:
    ///   - effective: Bob's structured effective block.
    ///   - answer: the event's RSVP answer (`"yes"`/`"maybe"`/…); only
    ///     `"maybe"` changes styling.
    public init(effective: GcalNoteEffective?, answer: String? = nil) {
        hue = Self.hue(effective?.root?.hue)
        offClock = effective?.clock?.lowercased() == "off"
        maybe = answer?.lowercased() == "maybe"
        beforeReason = Self.nonBlank(effective?.buffer?.beforeReason)
        afterReason = Self.nonBlank(effective?.buffer?.afterReason)
        beforeMinutes = effective?.buffer?.beforeMinutes
        afterMinutes = effective?.buffer?.afterMinutes
        if let start = effective?.meeting?.start,
            let end = effective?.meeting?.end
        {
            meetingText = "\(start)–\(end)"
        } else {
            meetingText = nil
        }
        if let start = effective?.occupied?.start,
            let end = effective?.occupied?.end
        {
            occupiedText = "\(start)–\(end)"
        } else {
            occupiedText = nil
        }
        let geometry = EventTimeRailGeometry(
            meeting: effective?.meeting,
            occupied: effective?.occupied
        )
        if let meetingText {
            if let geometry, geometry.hasBuffer {
                timeSummary =
                    "Meeting \(meetingText) · Occupied \(geometry.occupiedLabel)"
            } else if let occupiedText, occupiedText != meetingText {
                timeSummary = "Meeting \(meetingText) · Occupied \(occupiedText)"
            } else {
                timeSummary = "Meeting \(meetingText)"
            }
        } else {
            timeSummary = "Meeting time unavailable"
        }
        clippingText = Self.clippingText(
            geometry: geometry,
            clipped: effective?.occupied?.clipped ?? false
        )
        var spoken: [String] = []
        if let meeting = effective?.meeting,
            let start = meeting.start, let end = meeting.end
        {
            spoken.append("Meeting \(start) to \(end)")
        } else {
            spoken.append("Meeting time unavailable")
        }
        if let geometry, geometry.hasBuffer {
            spoken.append("Occupied \(geometry.occupiedLabelSpoken)")
        }
        if let beforeReason {
            spoken.append("Before: \(beforeReason)")
        }
        if let afterReason {
            spoken.append("After: \(afterReason)")
        }
        if offClock {
            spoken.append("Off-clock")
        }
        if maybe {
            spoken.append("Maybe")
        }
        if let clippingText {
            spoken.append(clippingText)
        }
        voiceOverSummary = spoken.joined(separator: ". ") + "."
    }

    /// Label for the lead-in wing, nil when Bob reported no reason.
    public var leadingReasonLabel: String? {
        guard let beforeReason else {
            return nil
        }
        if let beforeMinutes, beforeMinutes > 0 {
            return "−\(beforeMinutes)m \(beforeReason)"
        }
        return beforeReason
    }

    /// Label for the lead-out wing, nil when Bob reported no reason.
    public var trailingReasonLabel: String? {
        guard let afterReason else {
            return nil
        }
        if let afterMinutes, afterMinutes > 0 {
            return "+\(afterMinutes)m \(afterReason)"
        }
        return afterReason
    }

    private static func nonBlank(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private static func hue(_ raw: String?) -> PomodoroHomeHue? {
        guard let raw else {
            return nil
        }
        switch raw {
        case "blue": return .blue
        case "orange": return .orange
        case "aqua": return .aqua
        case "yellow": return .yellow
        case "magenta": return .magenta
        case "green": return .green
        case "violet": return .violet
        case "red": return .red
        default: return .other(raw)
        }
    }

    private static func clippingText(
        geometry: EventTimeRailGeometry?,
        clipped: Bool
    ) -> String? {
        guard clipped, let geometry else {
            return nil
        }
        let before =
            geometry.occupiedStart <= 0 && geometry.meetingStart > 0
        let after =
            geometry.occupiedEnd >= EventTimeRailGeometry.minutesPerDay
            && geometry.meetingEnd < EventTimeRailGeometry.minutesPerDay
        switch (before, after) {
        case (true, true): return "Clipped at 00:00 and 24:00"
        case (true, false): return "Clipped at 00:00"
        case (false, true): return "Clipped at 24:00"
        case (false, false): return "Clipped at midnight"
        }
    }
}

extension EventTimeRailGeometry {
    /// True when the occupied span extends past the meeting on either side.
    public var hasBuffer: Bool {
        occupiedStart < meetingStart || meetingEnd < occupiedEnd
    }

    fileprivate var occupiedLabel: String {
        "\(Self.clock(occupiedStart))–\(Self.clock(occupiedEnd))"
    }

    fileprivate var occupiedLabelSpoken: String {
        "\(Self.clock(occupiedStart)) to \(Self.clock(occupiedEnd))"
    }

    private static func clock(_ minutes: Double) -> String {
        let clamped =
            minutes.isFinite
            ? Int(min(max(minutes.rounded(), 0), minutesPerDay)) : 0
        if clamped == Int(minutesPerDay) {
            return "24:00"
        }
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}
