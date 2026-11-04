import Foundation

/// Bob-authored note-pull preview and notification copy. The client displays
/// the rows and destinations Bob resolved; it does not calculate eligibility.
public struct CaptureNotePullPresentation: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let number: Int
        public let text: String
        public let lane: String
        public let destination: String?

        public init(number: Int, text: String, lane: String, destination: String?) {
            self.number = number
            self.text = text
            self.lane = lane
            self.destination = destination
        }
    }

    public let noteName: String
    public let title: String
    public let tag: String
    public let rows: [Row]
    public let moreCount: Int
    public let foldLine: String?
    public let hintText: String
    public let notificationTitle: String
    public let notificationBody: String
    public let previewAccessibilitySummary: String

    public init?(notePull: CaptureNotePull, group: CapturePullInGroup? = nil) {
        guard !notePull.route.isEmpty || !notePull.note.isEmpty else {
            return nil
        }
        let path = notePull.note.isEmpty ? "\(notePull.route).md" : notePull.note
        noteName = Self.noteName(path)
        title = Self.nonempty(group?.copy?.title) ?? "Pull from ‹\(noteName)›"
        tag = Self.nonempty(group?.copy?.tag) ?? "ready in \(noteName)"
        foldLine = Self.nonempty(group?.copy?.fold) ?? notePull.folded.flatMap(Self.foldedText)
        let allRows = notePull.successors.map { offer in
            Row(
                number: offer.offer?.n ?? 0,
                text: offer.text,
                lane: Self.lane(for: offer.previousStatusSymbol, fallback: offer.previousStatusName),
                destination: Self.destination(for: offer.offer?.destination)
            )
        }
        rows = Array(allRows.prefix(5))
        moreCount = max(0, allRows.count - rows.count)
        hintText = "↩ choose what to pull in · ⇧↩ start a list"
        let picked = notePull.successors.filter { $0.offer?.selected == true }
        let count = picked.count
        let noun = count == 1 ? "task" : "tasks"
        notificationTitle = "📥 Pulled in \(count) \(noun) from ‹\(noteName)›"
        notificationBody = picked.map { offer in
            let destination = Self.destination(for: offer.offer?.destination)
            return "• \(offer.text)" + (destination.map { " \($0)" } ?? "")
        }.joined(separator: "\n")
        var summary = [title, tag]
        summary.append(contentsOf: allRows.map { row in
            ["\(row.number). \(row.text)", row.lane, row.destination]
                .compactMap { $0 }
                .joined(separator: " · ")
        })
        if moreCount > 0 {
            summary.append("+\(moreCount) more")
        }
        if let foldLine {
            summary.append(foldLine)
        }
        summary.append(hintText)
        previewAccessibilitySummary = summary.joined(separator: "; ")
    }

    public static func foldedText(_ folded: CapturePullInFolded) -> String? {
        var parts: [String] = []
        if folded.alreadyPlanned > 0 {
            parts.append("\(folded.alreadyPlanned) already planned")
        }
        if folded.blocked > 0 {
            parts.append("\(folded.blocked) blocked")
        }
        if folded.scheduled > 0 {
            parts.append("\(folded.scheduled) scheduled later")
        }
        if folded.hidden > 0 {
            parts.append("\(folded.hidden) hidden")
        }
        if folded.subProjects > 0 {
            parts.append(
                "\(folded.subProjects) sub-projects stay blocked until the next reconcile"
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public static func displayName(for note: CaptureNotePull) -> String {
        noteName(note.note.isEmpty ? "\(note.route).md" : note.note)
    }

    private static func noteName(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func lane(for symbol: String, fallback: String) -> String {
        switch symbol {
        case "/": return "Pending"
        case "*": return "Next"
        case " ": return "Ready"
        case "?": return "Blocked"
        default: return fallback
        }
    }

    private static func destination(for destination: TaskCompleteOfferDestination?) -> String? {
        guard let destination else { return nil }
        let name = destination.entryName.isEmpty ? destination.dayFile : destination.entryName
        guard !name.isEmpty else { return nil }
        if destination.entryRole == "created" || destination.entryRole == "new" {
            return "→ new \(name) session"
        }
        return "→ \(name)"
    }
}

/// Calm refusal card for Bob's `nothing_to_pull_in` response.
public struct CaptureNotePullEmptyPresentation: Equatable, Sendable {
    public let title: String
    public let foldLine: String?
    public let accessibilitySummary: String

    public init?(notePull: CaptureNotePull) {
        guard !notePull.route.isEmpty || !notePull.note.isEmpty else {
            return nil
        }
        let name = CaptureNotePullPresentation.displayName(for: notePull)
        title = "Nothing ready in ‹\(name)›"
        foldLine = notePull.folded.flatMap(CaptureNotePullPresentation.foldedText)
        accessibilitySummary = [title, foldLine].compactMap { $0 }.joined(separator: "; ")
    }
}
