import Foundation

/// Portable presentation helpers for the Meeting Notes sheet.
/// Bob owns meeting resolution and filing; these helpers only format
/// Bob's JSON for display and never parse notes or infer matching.
public enum MeetingNotesPresentation {
    public static func title(for meeting: MeetingNotesMeeting?) -> String {
        guard let meeting else { return "Meeting notes" }
        return meeting.title.isEmpty ? "Meeting notes" : meeting.title
    }

    public static func dateSpan(for meeting: MeetingNotesMeeting?) -> String {
        guard let meeting else { return "" }
        var parts: [String] = []
        if !meeting.date.isEmpty {
            parts.append(meeting.date)
        }
        let span = [meeting.start, meeting.end]
            .filter { !$0.isEmpty }
            .joined(separator: "–")
        if !span.isEmpty {
            parts.append(span)
        }
        return parts.joined(separator: " · ")
    }

    public static func destination(for response: MeetingNotesResponse?) -> String {
        guard let filing = response?.filing else { return "" }
        if filing.note.isEmpty { return filing.parent }
        return filing.note
    }

    public static func effectiveStatus(for response: MeetingNotesResponse?) -> String {
        response?.filing?.task.status ?? ""
    }

    public static func warnings(for response: MeetingNotesResponse?) -> [String] {
        response?.warnings ?? []
    }

    public static func outlineSummary(for response: MeetingNotesResponse?) -> (tldr: String, nextSteps: [String], sections: [String]) {
        guard let outline = response?.notes?.outline else {
            return ("", [], [])
        }
        let steps = outline.nextSteps.map { step in
            if let owner = step.owner, !owner.isEmpty {
                return "\(owner): \(step.action)"
            }
            return step.action
        }
        let sections = outline.sections.map { section in
            if let heading = section.heading, !heading.isEmpty {
                return "\(heading) (\(section.items))"
            }
            return "Section (\(section.items))"
        }
        return (outline.tldr, steps, sections)
    }

    public static func transcriptDisposition(for response: MeetingNotesResponse?) -> String? {
        response?.notes?.shape.flatMap { shape in
            shape.isEmpty ? nil : shape
        }
    }

    public static func filedRowMark(for meeting: MeetingNotesMeeting) -> Bool {
        meeting.notes != nil
    }
}
