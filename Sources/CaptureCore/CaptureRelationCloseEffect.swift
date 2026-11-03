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
    /// A successor label (`relations.successor_labels`): the source is offered
    /// when the target is parked or done. This never closes or dims the source.
    case offers

    public var isClosing: Bool {
        self == .cancel || self == .complete
    }

    /// SF Symbol for the row capsule (`circle.slash` / `checkmark.circle`).
    public var symbolName: String {
        switch self {
        case .cancel:
            return "circle.slash"
        case .complete:
            return "checkmark.circle"
        case .offers:
            return "link"
        }
    }

    /// Capsule and badge text (`cancels` / `completes`).
    public var capsuleText: String {
        switch self {
        case .cancel:
            return "cancels"
        case .complete:
            return "completes"
        case .offers:
            return "offers"
        }
    }

    /// Sentence verb for the dimmed source (`Cancels` / `Completes`).
    public var verb: String {
        switch self {
        case .cancel:
            return "Cancels"
        case .complete:
            return "Completes"
        case .offers:
            return "Offers"
        }
    }

    /// The `relation_cancel` / `relation_complete` verdict that dims the
    /// live-sentence source (`cancels` / `completes`). Every other verdict
    /// renders muted.
    public var closingVerdict: String? {
        switch self {
        case .cancel:
            return "cancels"
        case .complete:
            return "completes"
        case .offers:
            return nil
        }
    }

    public var semanticCategory: CaptureSemanticCategory {
        switch self {
        case .cancel:
            return .relationCancelLabel
        case .complete:
            return .relationCompleteLabel
        case .offers:
            return .relationSuccessorLabel
        }
    }
}

/// Color role for Bob-authored relation-effect copy. Offer messages remain
/// neutral, released-source caveats are amber, and inverse hints are muted.
public enum RelationSourceSlotStyle: Equatable, Sendable {
    case cancel
    case complete
    case offers
    case caveat
    case muted
}

public struct RelationSourceSlot: Equatable, Sendable {
    public let text: String
    public let style: RelationSourceSlotStyle
    public let effect: RelationSourceEffect?

    public init(text: String, style: RelationSourceSlotStyle, effect: RelationSourceEffect?) {
        self.text = text
        self.style = style
        self.effect = effect
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
        guard effect.isClosing, closesSource, let verdict,
            let closingVerdict = effect.closingVerdict
        else {
            return false
        }
        return verdict == closingVerdict
    }

    /// Presents a Bob-authored cancel, complete, or successor consequence.
    /// The effect and matching candidate flag gate consequence messages;
    /// hints remain visible without a verdict, including inverse successor
    /// hints. No verdict is inferred from endpoint status.
    public static func slot(
        effect: RelationSourceEffect?,
        appliesToSource: Bool,
        verdict: String?,
        message: String?,
        hint: String?
    ) -> RelationSourceSlot? {
        if effect == .offers, appliesToSource {
            switch verdict {
            case "offers":
                return slot(text: message, style: .offers, effect: .offers)
            case "already_parked", "already_closed":
                return slot(text: message, style: .caveat, effect: .offers)
            default:
                return slot(text: hint, style: .muted, effect: .offers)
            }
        }

        if let effect, effect.isClosing, appliesToSource {
            switch verdict {
            case "cancels", "completes":
                guard verdict == effect.closingVerdict else {
                    return nil
                }
                return slot(
                    text: message,
                    style: effect == .cancel ? .cancel : .complete,
                    effect: effect
                )
            case "already_closed", "recurring", "new_task":
                return slot(text: message, style: .muted, effect: effect)
            default:
                return nil
            }
        }

        return slot(text: hint, style: .muted, effect: effect)
    }

    private static func slot(
        text: String?,
        style: RelationSourceSlotStyle,
        effect: RelationSourceEffect?
    ) -> RelationSourceSlot? {
        guard let text, !text.isEmpty else {
            return nil
        }
        return RelationSourceSlot(text: text, style: style, effect: effect)
    }
}
