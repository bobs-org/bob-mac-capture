import Foundation

/// Pure presentation model for a reference item (`kind == "ref"` with a `ref`
/// object), built once from `CaptureCommandSuccess` so the SwiftUI/AppKit
/// layer never branches on reference-specific JSON fields or spells a
/// reading-queue string literal itself. Works equally for a dry-run live
/// preview and a committed capture — `isDryRun` is the only thing that changes
/// the tense of `headline` and `statusText`; every other field describes the
/// same queued or already-known link.
///
/// `detailText` is byte-identical to bob's dim detail line in
/// `print_human_ref_item_success` (`src/native/capture/output.rs`), so the
/// panel's card and the CLI's `--dry-run` output describe the same link the
/// same way. All other wording is the panel's own: bob says "queued" /
/// "would queue", the card says "Queued for reading" / "Save to reading
/// queue".
public struct CaptureRefPresentation: Equatable, Sendable {
    public let isDryRun: Bool
    public let isQueued: Bool
    /// `"Save to reading queue"` in a dry run, `"Queued for reading"` on a
    /// real run; `"Already in your library"`, `"Already queued"`,
    /// `"Already clipping"`, or `"Duplicate link"` for the unchanged verdicts.
    public let headline: String
    /// The display URL, or the library path when the link is already known.
    public let destinationLabel: String
    /// Byte-identical to bob's dim detail line.
    public let detailText: String
    /// The route hint (`"Article"`, `"PDF"`, `"arXiv"`) when queued; the
    /// capitalized reading state when in the library; empty otherwise.
    public let chips: [String]
    /// `"If clipping fails, it becomes a task in <fallback.relative_target>."`
    /// on queued items with a fallback; nil otherwise.
    public let fallbackHint: String?
    /// `"Queue"` for a queued single item, `"Done"` for an unchanged one.
    /// Batches keep today's footer title.
    public let primaryActionTitle: String
    public let statusText: String
    public let notificationTitle: String
    public let notificationBody: String
    public let previewAccessibilitySummary: String
    /// The absolute vault path Command-Return opens, or nil when bob reported
    /// no target. Bob fills `target` only for `in_library` and `in_intake`,
    /// so a queued link opens nothing.
    public let openTargetPath: String?

    public init?(capture: CaptureCommandSuccess) {
        guard normalizedRefKind(capture.kind) == "ref",
              let ref = capture.ref,
              !ref.isEmpty
        else {
            return nil
        }

        isDryRun = capture.dryRun
        isQueued = capture.placement == "queued"
        let verdict = ref.library.verdict

        if isQueued {
            headline = capture.dryRun ? "Save to reading queue" : "Queued for reading"
        } else {
            headline = Self.unchangedHeadline(verdict: verdict)
        }

        if !isQueued, let path = ref.library.path, !path.isEmpty {
            destinationLabel = path
        } else {
            destinationLabel = ref.display
        }

        detailText = Self.detailText(ref: ref, isDryRun: capture.dryRun)

        chips = Self.chips(ref: ref, isQueued: isQueued)

        if isQueued, let fallback = ref.fallback, !fallback.relativeTarget.isEmpty {
            fallbackHint = "If clipping fails, it becomes a task in \(fallback.relativeTarget)."
        } else {
            fallbackHint = nil
        }

        primaryActionTitle = isQueued ? "Queue" : "Done"

        statusText = Self.statusText(
            ref: ref,
            isQueued: isQueued,
            isDryRun: capture.dryRun,
            destinationLabel: destinationLabel
        )

        let notification = Self.notification(
            ref: ref,
            isQueued: isQueued,
            destinationLabel: destinationLabel
        )
        notificationTitle = notification.title
        notificationBody = notification.body

        var summaryParts = ["\(headline): \(destinationLabel)", detailText]
        if let fallbackHint {
            summaryParts.append(fallbackHint)
        }
        previewAccessibilitySummary = summaryParts.joined(separator: ", ")

        openTargetPath = capture.target.isEmpty ? nil : capture.target
    }

    private static func unchangedHeadline(verdict: String) -> String {
        switch verdict {
        case "in_library":
            return "Already in your library"
        case "in_intake":
            return "Already queued"
        case "clipping":
            return "Already clipping"
        case "duplicate":
            return "Duplicate link"
        default:
            return "Queued for reading"
        }
    }

    /// Mirrors `print_human_ref_item_success`'s detail match in
    /// `src/native/capture/output.rs`, without color.
    private static func detailText(ref: CaptureRef, isDryRun: Bool) -> String {
        let library = ref.library
        switch library.verdict {
        case "in_library":
            if let title = library.title, !title.isEmpty {
                if let state = library.readingState, !state.isEmpty {
                    return "\(title) · \(state)"
                }
                return title
            }
            return library.path ?? ref.display
        case "in_intake":
            return "waiting for bob ref scan"
        case "clipping":
            return "a pending ref job has this link · bob ref jobs"
        case "duplicate":
            return library.message ?? "same link as an earlier item"
        case "legacy":
            return "in your library as a legacy note (\(library.path ?? "?")) · a fresh copy will be clipped"
        case "unknown":
            return "library check unavailable: \(library.message ?? "unknown error") · the clip still dedupes"
        default:
            if isDryRun {
                return "new to your library · clips in the background"
            }
            return "clipping in the background · bob ref jobs"
        }
    }

    private static func chips(ref: CaptureRef, isQueued: Bool) -> [String] {
        if isQueued, !ref.routeHint.isEmpty {
            return [routeHintChip(ref.routeHint)]
        }
        if let state = ref.library.readingState, !state.isEmpty,
           ref.library.verdict == "in_library"
        {
            return [capitalizedWord(state)]
        }
        return []
    }

    private static func routeHintChip(_ hint: String) -> String {
        switch hint.lowercased() {
        case "pdf":
            return "PDF"
        case "arxiv":
            return "arXiv"
        default:
            return capitalizedWord(hint)
        }
    }

    private static func capitalizedWord(_ value: String) -> String {
        guard let first = value.first else {
            return value
        }
        return String(first).uppercased() + value.dropFirst()
    }

    private static func statusText(
        ref: CaptureRef,
        isQueued: Bool,
        isDryRun: Bool,
        destinationLabel: String
    ) -> String {
        let library = ref.library
        switch library.verdict {
        case "in_library":
            return "Already in your library: \(libraryTitle(ref: ref, destinationLabel: destinationLabel))"
        case "in_intake":
            return "Already queued: \(destinationLabel)"
        case "clipping":
            return "Already clipping: \(ref.display)"
        case "duplicate":
            return "Duplicate link: \(ref.display)"
        case "legacy":
            return "Legacy note \(library.path ?? "?"): a fresh copy will be clipped"
        case "unknown":
            return "Library check unavailable: \(library.message ?? "unknown error")"
        default:
            if isDryRun {
                return "Would queue for clipping → reading queue"
            }
            return "Queued for clipping → reading queue"
        }
    }

    private static func libraryTitle(ref: CaptureRef, destinationLabel: String) -> String {
        if let title = ref.library.title, !title.isEmpty {
            return title
        }
        return destinationLabel
    }

    private static func notification(
        ref: CaptureRef,
        isQueued: Bool,
        destinationLabel: String
    ) -> (title: String, body: String) {
        let library = ref.library
        switch library.verdict {
        case "in_library":
            return ("Already in your library", libraryTitle(ref: ref, destinationLabel: destinationLabel))
        case "in_intake":
            return ("Already queued", destinationLabel)
        case "clipping":
            return ("Already clipping", ref.display)
        case "duplicate":
            return ("Duplicate link", ref.display)
        default:
            return ("Queued for reading", "\(ref.display) → reading queue")
        }
    }
}

private func normalizedRefKind(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
}
