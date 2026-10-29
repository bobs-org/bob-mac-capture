import Foundation

/// One close effect a relation label can carry. Cancel labels and complete
/// labels together are closing labels: both close the source at commit, one
/// label carries at most one effect, and Swift never computes a verdict —
/// Bob authors every string and Swift only decides whether to show Bob's
/// capsule, dim the source, and pick the slot style.
public enum RelationSourceEffect: Equatable, Sendable {
    /// A cancel label (`relations.cancel_labels`): the source is cancelled.
    case cancel
    /// A complete label (`relations.complete_labels`): the source is done.
    case complete

    /// SF Symbol for the row capsule (`circle.slash` / `checkmark.circle`).
    public var symbolName: String {
        switch self {
        case .cancel:
            return "circle.slash"
        case .complete:
            return "checkmark.circle"
        }
    }

    /// Capsule and badge text (`cancels` / `completes`).
    public var capsuleText: String {
        switch self {
        case .cancel:
            return "cancels"
        case .complete:
            return "completes"
        }
    }

    /// Sentence verb for the dimmed source (`Cancels` / `Completes`).
    public var verb: String {
        switch self {
        case .cancel:
            return "Cancels"
        case .complete:
            return "Completes"
        }
    }

    /// The `relation_cancel` / `relation_complete` verdict that dims the
    /// live-sentence source (`cancels` / `completes`). Every other verdict
    /// renders muted.
    public var closingVerdict: String {
        switch self {
        case .cancel:
            return "cancels"
        case .complete:
            return "completes"
        }
    }
}

/// Shared thin-client logic for Bob's closing-label flags and strings,
/// parameterized by effect so the cancel and complete cues stay one design.
/// The cancel wrappers in `CaptureRelationCancelPresentation` and the
/// complete wrappers in `CaptureRelationCompletePresentation` keep their
/// own row/slot/warning types; this enum only answers the three questions
/// both ask: does the source dim, which slot shows, and which warnings show.
public enum CaptureRelationCloseEffect {
    /// Dim the live-sentence source only when the selected or typed label
    /// carries this effect and Bob's verdict is its closing verdict.
    public static func dimsSource(
        closesSource: Bool,
        verdict: String?,
        effect: RelationSourceEffect
    ) -> Bool {
        guard closesSource, let verdict else {
            return false
        }
        return verdict == effect.closingVerdict
    }

    /// Bob's `relation_cancel.message` / `relation_complete.message` when
    /// the active label would close or is refused, else the muted inverse
    /// `hint`. Returns the text plus whether it takes the closing tint
    /// (green/⊘) rather than muted. Nil when neither applies.
    public static func slot(
        closesSource: Bool,
        verdict: String?,
        message: String?,
        hint: String?
    ) -> (text: String, isClosing: Bool)? {
        guard let verdict else {
            return nil
        }
        if closesSource {
            switch verdict {
            case "cancels", "completes":
                guard let message, !message.isEmpty else {
                    return nil
                }
                return (message, true)
            case "already_closed", "recurring", "new_task":
                guard let message, !message.isEmpty else {
                    return nil
                }
                return (message, false)
            default:
                return nil
            }
        }
        if let hint, !hint.isEmpty {
            return (hint, false)
        }
        return nil
    }
}
