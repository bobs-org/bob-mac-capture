import Foundation

/// Pure presentation model for recorded past Pomodoro stacks (`pomodoro_past`
/// present on `bob capture --format json` successes), built from Bob's
/// resolved objects so SwiftUI never recomputes windows or ledger effects.
/// Bob is the sole authority for grammar, names, windows, overlap repairs,
/// task effects, and vault writes; the app renders what Bob returns.
///
/// A stack is a maximal run of adjacent `kind == "pomodoro_past"` captures.
/// Grouping follows Bob's `stack.index`/`size`: a new group starts at index 1
/// and ends at a non-past item. Separate stacks never merge just because
/// their sizes or anchors match. Typed/member order is preserved as Bob
/// resolved it chronologically; clock strings are never sorted (midnight
/// would mishandle). Malformed group metadata degrades safely without losing
/// items.
public struct CapturePomodoroPastPresentation: Equatable, Sendable {
    public struct TrimRow: Equatable, Sendable {
        public let line: Int
        public let name: String
        public let before: String
        public let after: String
        public let minutes: Int
        public let clock: String
        public let calendar: Bool

        public var text: String {
            let gift = "\(minutes)m"
            let cal = calendar ? " (calendar)" : ""
            return "Trim \(name) \(before) → \(after) · gives \(gift)\(cal) · line \(line)"
        }

        public var accessibilityLabel: String {
            let cal = calendar ? ", calendar session" : ""
            return
                "Trim \(name), \(before) to \(after), gives \(minutes) minutes\(cal), line \(line)"
        }
    }

    public struct Member: Equatable, Sendable {
        public let capture: CaptureCommandSuccess
        public let past: PomodoroPastSummary
        public let displayName: String
        public let windowText: String
        public let durationMinutes: Int
        public let rangeText: String
        public let segmentLine: String?
        public let segmentAccessibilityLabel: String?
        public let cutNote: String?
        public let cutAccessibilityLabel: String?
        public let closePresentation: CapturePomodoroClosePresentation?

        public var taskRows: [CapturePomodoroClosePresentation.TaskRow] {
            closePresentation?.taskRows ?? []
        }

        public var accessibilityLabel: String {
            var parts = ["\(displayName), \(windowText), \(durationMinutes) minutes"]
            if let segmentAccessibilityLabel {
                parts.append(segmentAccessibilityLabel)
            }
            if let cutAccessibilityLabel {
                parts.append(cutAccessibilityLabel)
            }
            return parts.joined(separator: ", ")
        }
    }

    public struct Group: Equatable, Sendable {
        public let members: [Member]
        public let totalMinutes: Int
        public let timelineText: String
        public let trimRows: [TrimRow]
        public let isDryRun: Bool

        public var title: String { "Record past work" }

        public var headingText: String {
            "Record past work · \(totalMinutes)m"
        }

        public var statusText: String {
            let verb = isDryRun ? "Would record" : "Recorded"
            let names = members.map(\.displayName).joined(separator: " + ")
            let suffix = members.count > 1 ? " · \(members.count) sessions" : ""
            return "\(verb) \(names) · \(totalMinutes)m\(suffix)"
        }

        public var accessibilitySummary: String {
            var parts = ["Record past work, \(totalMinutes) minutes"]
            parts.append(timelineText)
            for member in members {
                parts.append(member.accessibilityLabel)
                if !member.taskRows.isEmpty {
                    parts.append("\(member.taskRows.count) task rows")
                }
            }
            for trim in trimRows {
                parts.append(trim.accessibilityLabel)
            }
            return parts.joined(separator: ", ")
        }
    }

    public let groups: [Group]
    public let isHomogeneous: Bool
    public let isDryRun: Bool

    public var title: String { "Record past work" }

    public var primaryActionTitle: String { "Record" }

    public var notificationTitle: String { "Recorded past Pomodoro" }

    public var notificationBody: String {
        groups.map(\.timelineText).joined(separator: "\n")
    }

    public init?(captures: [CaptureCommandSuccess]) {
        let groups = Self.groups(for: captures)
        guard !groups.isEmpty else {
            return nil
        }
        self.groups = groups
        isDryRun = captures.first?.dryRun ?? true
        isHomogeneous = !captures.isEmpty
            && captures.allSatisfy { $0.kind == "pomodoro_past" && $0.pomodoroPast != nil }
    }

    public init?(capture: CaptureCommandSuccess) {
        self.init(captures: capture.normalizedCaptures)
    }

    /// Group adjacent `pomodoro_past` captures using Bob's stack index/size.
    public static func groups(for captures: [CaptureCommandSuccess]) -> [Group] {
        var result: [Group] = []
        var current: [CaptureCommandSuccess] = []

        func flush() {
            guard !current.isEmpty else {
                return
            }
            result.append(makeGroup(members: current))
            current = []
        }

        for capture in captures {
            guard capture.kind == "pomodoro_past", capture.pomodoroPast != nil else {
                flush()
                continue
            }
            let index = capture.pomodoroPast?.stack.index ?? 0
            if index <= 1, !current.isEmpty {
                flush()
            }
            current.append(capture)
            let size = capture.pomodoroPast?.stack.size ?? 0
            if size > 0, current.count >= size {
                // Do not force-close on size alone when the next item is also
                // past: sizes can repeat across separate stacks, so only the
                // next non-past item or an index-1 boundary ends a group.
                // Peek is unavailable here; flush lazily on next iteration.
                continue
            }
        }
        flush()
        return result
    }

    private static func makeGroup(members captures: [CaptureCommandSuccess]) -> Group {
        let members: [Member] = captures.compactMap { capture in
            guard let past = capture.pomodoroPast else {
                return nil
            }
            let name = past.name
                ?? past.close.pomodoroName
                ?? past.close.closedName
                ?? "session"
            let minutes = past.window.minutes > 0 ? past.window.minutes : past.blocks * 5
            let rangeText = past.window.start.isEmpty || past.window.end.isEmpty
                ? ""
                : "\(past.window.start)-\(past.window.end)"
            let windowText = rangeText.isEmpty ? "\(minutes)m" : "\(rangeText) · \(minutes)m"
            let closePresentation = CapturePomodoroClosePresentation(
                summary: past.close,
                capture: capture
            )
            let segmentLine = Self.segmentLine(for: past.segment)
            let cutNote = Self.cutNote(for: past)
            return Member(
                capture: capture,
                past: past,
                displayName: name,
                windowText: windowText,
                durationMinutes: minutes,
                rangeText: rangeText,
                segmentLine: segmentLine,
                segmentAccessibilityLabel: segmentLine.map { "Placement: \($0)." },
                cutNote: cutNote,
                cutAccessibilityLabel: cutNote.map { "\($0)." },
                closePresentation: closePresentation
            )
        }
        let total = members.reduce(0) { $0 + $1.durationMinutes }
        let timeline = timelineText(for: members)
        let trims = dedupedTrims(for: members)
        let dryRun = captures.first?.dryRun ?? true
        return Group(
            members: members.isEmpty
                ? captures.compactMap { capture in
                    guard let past = capture.pomodoroPast else {
                        return nil
                    }
                    return Member(
                        capture: capture,
                        past: past,
                        displayName: past.name ?? "session",
                        windowText: "",
                        durationMinutes: past.blocks * 5,
                        rangeText: "",
                        segmentLine: Self.segmentLine(for: past.segment),
                        segmentAccessibilityLabel: Self.segmentLine(for: past.segment)
                            .map { "Placement: \($0)." },
                        cutNote: Self.cutNote(for: past),
                        cutAccessibilityLabel: Self.cutNote(for: past).map { "\($0)." },
                        closePresentation: nil
                    )
                } : members,
            totalMinutes: total,
            timelineText: timeline,
            trimRows: trims,
            isDryRun: dryRun
        )
    }

    private static func timelineText(for members: [Member]) -> String {
        guard let first = members.first else {
            return ""
        }
        var parts: [String] = []
        let start = first.past.window.start
        if !start.isEmpty {
            parts.append(start)
        }
        for member in members {
            parts.append("\(member.displayName) \(member.durationMinutes)m")
            if !member.past.window.end.isEmpty {
                parts.append(member.past.window.end)
            }
        }
        return parts.joined(separator: " ── ")
    }

    private static func segmentLine(for segment: PomodoroPastSegment?) -> String? {
        guard let segment else {
            return nil
        }
        let name = segment.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Pomodoro"
        switch segment.kind {
        case "tail":
            return "since \(name)"
        case "head":
            return "before \(name)"
        case "pomodoro", "gap":
            let edge = segment.edge == "end" ? "the end" : "the start"
            let segmentName = segment.kind == "gap" ? "gap" : name
            let suffix = segment.index.map { "~\($0) " } ?? ""
            let range = [segment.start, segment.end]
                .filter { !$0.isEmpty }
                .joined(separator: "–")
            let rangeText = range.isEmpty ? "" : " \(range)"
            return "at \(edge) of \(suffix)\(segmentName)\(rangeText)"
        default:
            return nil
        }
    }

    private static func cutNote(for past: PomodoroPastSummary) -> String? {
        guard let cut = past.window.cut else {
            return nil
        }
        let requested = past.window.requestedMinutes ?? past.blocks * 5
        guard requested > past.window.minutes else {
            return nil
        }
        return "\(past.window.minutes)m · \(requested)m cut at \(cut)"
    }

    private static func dedupedTrims(for members: [Member]) -> [TrimRow] {
        var seen = Set<String>()
        var rows: [TrimRow] = []
        for member in members {
            for trim in member.past.trims {
                let key = "\(trim.line)|\(trim.before)|\(trim.after)"
                guard seen.insert(key).inserted else {
                    continue
                }
                rows.append(TrimRow(
                    line: trim.line,
                    name: trim.name,
                    before: trim.before,
                    after: trim.after,
                    minutes: trim.minutes,
                    clock: trim.clock,
                    calendar: trim.calendar
                ))
            }
        }
        return rows
    }
}
