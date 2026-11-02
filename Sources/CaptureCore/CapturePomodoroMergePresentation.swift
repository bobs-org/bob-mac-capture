import Foundation

/// Presentation of Bob's resolved `pomodoro_merge` object. Swift does not
/// resolve selectors or infer which child lines move; it only words the result.
/// It never splits or parses `explicit`.
public struct CapturePomodoroMergePresentation: Equatable, Sendable {
    public struct AbsorbedRow: Equatable, Sendable {
        public let name: String
        public let fromLine: Int
        public let movedLines: Int
        public let droppedDuplicates: Int
        public let role: String?
        /// True when Bob implied this destination (`role == "next"`).
        public var isNext: Bool { role == "next" }
    }

    /// One segment of the teaching hint: example tokens carry the editor span
    /// category whose color they share, and prose carries `.neutral`.
    public struct HintToken: Equatable, Sendable {
        public let text: String
        public let category: CaptureSemanticCategory

        public init(text: String, category: CaptureSemanticCategory) {
            self.text = text
            self.category = category
        }
    }

    /// The teaching hint shown under the destination when Bob implied a pick:
    /// structured `tokens` for tinted rendering plus the joined `text`.
    public struct TeachingHint: Equatable, Sendable {
        public let tokens: [HintToken]
        public let text: String

        public init(tokens: [HintToken]) {
            self.tokens = tokens
            self.text = tokens.map(\.text).joined()
        }
    }

    public let isDryRun: Bool
    public let before: String
    public let after: String
    public let absorbedRows: [AbsorbedRow]
    public let destinationText: String?
    public let primaryActionTitle: String
    public let statusText: String
    public let notificationTitle: String
    public let notificationBody: String
    public let previewAccessibilitySummary: String
    /// True when Bob chose the source (`source_role` is `current` or
    /// `next_up`). Unknown values count as named.
    public let sourceIsImplied: Bool
    /// The fully spelled token Bob resolved this merge to, when present.
    public let explicitToken: String?
    /// Caption under the destination when anything was implied. Nil for a
    /// fully named merge and for older Bob that omits the new fields.
    public let teachingHint: TeachingHint?

    public init?(capture: CaptureCommandSuccess) {
        guard let merge = capture.pomodoroMerge else {
            return nil
        }
        isDryRun = capture.dryRun
        before = merge.before
        after = merge.after
        absorbedRows = merge.absorbed.map {
            AbsorbedRow(
                name: $0.name,
                fromLine: $0.fromLine,
                movedLines: $0.movedLines,
                droppedDuplicates: $0.droppedDuplicates,
                role: $0.role
            )
        }
        let path = merge.path.isEmpty ? capture.relativeTarget : merge.path
        destinationText = merge.entryLine > 0 ? "\(path) · line \(merge.entryLine)" : nil
        primaryActionTitle = "Merge"

        let names = absorbedRows.map(\.name).joined(separator: ", ")
        let verb = capture.dryRun ? "Would merge" : "Merged"
        statusText = "\(verb) \(names) into \(after)"
        notificationTitle = "\(capture.dryRun ? "Would merge" : "Merged") \(names)"
        var body = ["\(before) → \(after)"]
        if let destinationText {
            body.append(destinationText)
        }
        body.append(
            contentsOf: absorbedRows.map { row in
                let movedLineNoun = row.movedLines == 1 ? "line" : "lines"
                var detail = "\(row.name) · \(row.movedLines) \(movedLineNoun) moved"
                if row.droppedDuplicates > 0 {
                    let duplicate = row.droppedDuplicates == 1 ? "duplicate" : "duplicates"
                    detail += " · \(row.droppedDuplicates) \(duplicate) dropped"
                }
                return detail
            })
        notificationBody = body.joined(separator: "\n")

        let sourceRole = merge.sourceRole
        sourceIsImplied = sourceRole == "current" || sourceRole == "next_up"
        let trimmedExplicit = merge.explicit.flatMap { $0.isEmpty ? nil : $0 }
        explicitToken = trimmedExplicit
        let anyNext = absorbedRows.contains(where: \.isNext)
        if sourceIsImplied || anyNext {
            if let explicit = trimmedExplicit {
                var tokens = [
                    HintToken(text: "Same as ", category: .neutral),
                    HintToken(text: explicit, category: .pomodoroStart),
                ]
                if anyNext {
                    tokens += [
                        HintToken(text: " · Type ", category: .neutral),
                        HintToken(text: "#name", category: .section),
                        HintToken(
                            text: " to absorb a specific Pomodoro",
                            category: .neutral
                        ),
                    ]
                }
                teachingHint = TeachingHint(tokens: tokens)
            } else {
                teachingHint = TeachingHint(
                    tokens: [
                        HintToken(text: "Type ", category: .neutral),
                        HintToken(text: "#name", category: .section),
                        HintToken(
                            text: " to absorb a specific Pomodoro",
                            category: .neutral
                        ),
                    ]
                )
            }
        } else {
            teachingHint = nil
        }

        var spoken = body
        if sourceIsImplied {
            spoken.append("\(before) is the current Pomodoro")
        }
        spoken.append(
            contentsOf: absorbedRows.filter(\.isNext).map {
                "\($0.name) is the next planned Pomodoro"
            }
        )
        if let explicitToken {
            spoken.append("same as \(explicitToken)")
        }
        previewAccessibilitySummary = spoken.joined(separator: ", ")
    }
}
