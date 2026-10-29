import Foundation

/// The one-off warning slot's complete-label contents. Bob authors `text`;
/// Swift only chooses the ✓ tint versus muted from the verdict or hint.
public struct CaptureRelationCompleteSlot: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        /// Verdict `completes`: ✓ tint, never strikethrough.
        case completes
        /// A refused complete row, `already_closed`, or an inverse hint: muted.
        case muted
    }

    public let text: String
    public let style: Style

    public init(text: String, style: Style) {
        self.text = text
        self.style = style
    }
}

/// Thin-client helpers for Bob's complete-label flags and strings. Swift
/// never computes a verdict: it only decides whether to show Bob's
/// `completes_source` capsule, dim the source, and pick the slot style.
public enum CaptureRelationCompletePresentation {
    /// True when this row's key is a configured complete label.
    public static func completesSource(_ candidate: CaptureCompletionCandidate) -> Bool {
        candidate.completesSource
    }

    /// Dim the live-sentence source only when the selected or typed label
    /// completes and Bob's verdict is `completes`.
    public static func dimsSource(
        candidate: CaptureCompletionCandidate?,
        complete: CaptureCompletionRelationComplete?
    ) -> Bool {
        guard let candidate, let complete else {
            return false
        }
        return CaptureRelationCloseEffect.dimsSource(
            closesSource: candidate.completesSource,
            verdict: complete.verdict,
            effect: .complete
        )
    }

    /// Bob's `relation_complete.message` when the active complete label
    /// would complete or is refused, else the muted inverse `hint`.
    public static func slot(
        candidate: CaptureCompletionCandidate?,
        complete: CaptureCompletionRelationComplete?
    ) -> CaptureRelationCompleteSlot? {
        guard let complete else {
            return nil
        }
        let slot = CaptureRelationCloseEffect.slot(
            closesSource: candidate?.completesSource == true,
            verdict: complete.verdict,
            message: complete.message,
            hint: complete.hint
        )
        guard let slot else {
            return nil
        }
        return CaptureRelationCompleteSlot(
            text: slot.text,
            style: slot.isClosing ? .completes : .muted
        )
    }

    /// VoiceOver for a dimmed source: "Completes Sell stocks!".
    public static func sourceAccessibilityLabel(
        sourceText: String,
        dimsSource: Bool
    ) -> String {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard dimsSource, !trimmed.isEmpty else {
            return trimmed
        }
        return "Completes \(trimmed)"
    }

    /// Hide and leftover complete warnings for the preview stack. Skip
    /// `relation_completed_source` when `relation_completes[]` already
    /// shows Bob's message, so the ✓ row is never a green duplicate.
    public static func previewWarningRows(
        for capture: CaptureCommandSuccess
    ) -> [CapturePreviewWarningRow] {
        let skipCompletedSource = !capture.relationCompletes.isEmpty
        return capture.warnings.compactMap { warning in
            if warning.isThemeNotConfigured {
                return nil
            }
            if warning.isRelationCompletedSource {
                if skipCompletedSource {
                    return nil
                }
                return CapturePreviewWarningRow(
                    text: warning.message,
                    style: .completed,
                    accessibilityLabel: warning.message
                )
            }
            if warning.isRelationHideWarning {
                return CapturePreviewWarningRow(
                    text: warning.message,
                    style: .amber,
                    accessibilityLabel: "Warning: \(warning.message)"
                )
            }
            return nil
        }
    }

    /// Start-card warnings: every non-theme warning, with complete-source
    /// skipped when complete rows already show Bob's message, restyled by
    /// code otherwise.
    public static func startCardWarningRows(
        for capture: CaptureCommandSuccess
    ) -> [CapturePreviewWarningRow] {
        let skipCompletedSource = !capture.relationCompletes.isEmpty
        return capture.warnings.compactMap { warning in
            if warning.isThemeNotConfigured {
                return nil
            }
            if warning.isRelationCompletedSource {
                if skipCompletedSource {
                    return nil
                }
                return CapturePreviewWarningRow(
                    text: warning.message,
                    style: .completed,
                    accessibilityLabel: warning.message
                )
            }
            if warning.isRelationHideWarning {
                return CapturePreviewWarningRow(
                    text: warning.message,
                    style: .amber,
                    accessibilityLabel: "Warning: \(warning.message)"
                )
            }
            return CapturePreviewWarningRow(
                text: warning.message,
                style: .amber,
                accessibilityLabel: "Warning: \(warning.message)"
            )
        }
    }

    public static func completeCount(in captures: [CaptureCommandSuccess]) -> Int {
        captures.flatMap(\.normalizedCaptures).reduce(0) { $0 + $1.relationCompletes.count }
    }

    public static func submitHint(completeCount: Int) -> String? {
        guard completeCount > 0 else {
            return nil
        }
        let noun = completeCount == 1 ? "task" : "tasks"
        return "Capture & complete \(completeCount) \(noun)"
    }

    /// Mixed cancel-and-complete submit hint: `Capture & close N tasks`.
    /// Prefers the specific hint when only one effect is present.
    public static func submitHint(
        cancelCount: Int,
        completeCount: Int
    ) -> String? {
        if cancelCount > 0, completeCount > 0 {
            let total = cancelCount + completeCount
            let noun = total == 1 ? "task" : "tasks"
            return "Capture & close \(total) \(noun)"
        }
        if completeCount > 0 {
            return submitHint(completeCount: completeCount)
        }
        return CaptureRelationCancelPresentation.submitHint(cancelCount: cancelCount)
    }

    /// The `!` detail rows for one completed source: Bob's message is
    /// rendered by the caller as the ✓ row, and this presentation renders
    /// the same transition, ledger, and unblocked rows `!` would print.
    /// Built through `CaptureTaskCompletePresentation` so the wording stays
    /// byte-identical with the whole-item completion card.
    public static func detailPresentation(
        complete: CaptureRelationComplete,
        dryRun: Bool
    ) -> CaptureTaskCompletePresentation? {
        guard let summary = complete.taskComplete else {
            return nil
        }
        let success = CaptureCommandSuccess(
            ok: true,
            dryRun: dryRun,
            routed: false,
            routeLabel: "",
            relativeTarget: complete.source.path,
            target: complete.source.path,
            text: complete.source.text,
            taskLine: "",
            kind: "task_complete",
            created: "",
            placement: "",
            blockID: complete.source.blockID.isEmpty ? nil : complete.source.blockID,
            statusSymbol: "x",
            statusName: "Done",
            previousStatusSymbol: complete.previousStatus,
            previousStatusName: complete.previousStatusName,
            taskComplete: summary
        )
        return CaptureTaskCompletePresentation(capture: success)
    }
}
