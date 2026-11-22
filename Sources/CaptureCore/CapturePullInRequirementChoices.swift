import Foundation

/// One explicitly staged requirement choice. Met is the default and is
/// represented by the absence of a value in
/// `CapturePullInOutcomes.requirementChoices`; it is never stored.
public enum CaptureRequirementStagedVerdict: Equatable, Sendable {
    case drop(reason: String)
    case carry
    case carryPulled

    /// Every staged requirement choice takes its branch: descendants are
    /// folded and excluded from the Met count until restaged to Met.
    public var takesBranch: Bool { true }

    public var isDrop: Bool {
        if case .drop = self { return true }
        return false
    }

    public var reason: String {
        if case .drop(let reason) = self { return reason }
        return ""
    }
}

/// Overlap refusal when two staged structural choices share one branch.
/// The message uses Bob's frozen RV copy.
public struct CaptureRequirementOverlapError: Equatable, Sendable {
    public let ancestorKey: String
    public let ancestorText: String
    public let descendantKey: String

    public init(ancestorKey: String, ancestorText: String, descendantKey: String) {
        self.ancestorKey = ancestorKey
        self.ancestorText = ancestorText
        self.descendantKey = descendantKey
    }

    public var message: String {
        CaptureRequirementCopy.overlap(ancestorText)
    }
}

/// Frozen RV copy used by portable requirement staging.
public enum CaptureRequirementCopy {
    public static func overlap(_ ancestor: String) -> String {
        "“\(ancestor)” already takes this branch — restage it as met to choose here"
    }

    public static func nestedGoWithIt(_ count: Int) -> String {
        "· \(count) nested go with it"
    }

    public static func summary(met: Int, dropped: Int, carried: Int) -> String {
        "reqs ✓\(met) ⊘\(dropped) →\(carried)"
    }

    public static func accessibility(depth: Int, verb: String) -> String {
        "requirement, level \(depth), \(verb)"
    }

    public static func verb(for choice: CaptureRequirementStagedVerdict?) -> String {
        switch choice {
        case .none:
            return "will be met"
        case .drop:
            return "will be dropped"
        case .carry:
            return "will be its own task"
        case .carryPulled:
            return "will be its own task and pulled in"
        }
    }
}

/// Typed Pull-In row: an ordinary task offer or a requirement row.
/// Requirements never manufacture task status, block IDs, or destinations.
public enum CapturePullInTypedRow: Equatable, Sendable {
    case task(TaskCompleteUnblocked)
    case requirement(CaptureRequirementRow)

    public var key: String {
        switch self {
        case .task(let row):
            return row.offer?.key ?? ""
        case .requirement(let row):
            return row.offer.key
        }
    }

    public var number: Int {
        switch self {
        case .task(let row):
            return row.offer?.n ?? Int.max
        case .requirement(let row):
            return row.offer.n
        }
    }

    public var ownerKey: String? {
        switch self {
        case .task:
            return nil
        case .requirement(let row):
            return row.req.ownerKey
        }
    }
}

public enum CaptureRequirementBranch {
    /// Strict path-prefix ancestry within one owner. Component-wise, so
    /// `1` is an ancestor of `1.1` but never of `10`.
    public static func isStrictAncestor(
        ancestorPath: [Int],
        descendantPath: [Int]
    ) -> Bool {
        guard ancestorPath.count < descendantPath.count else { return false }
        return Array(descendantPath.prefix(ancestorPath.count)) == ancestorPath
    }

    public static func normalizedReason(_ reason: String) -> String {
        let collapsed = reason.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One folded requirement row for display.
public struct CaptureRequirementFold: Equatable, Sendable {
    public let key: String
    public let visible: Bool
    public let hiddenBy: String?
    public let nestedGoWithIt: Int?

    public init(key: String, visible: Bool, hiddenBy: String? = nil, nestedGoWithIt: Int? = nil) {
        self.key = key
        self.visible = visible
        self.hiddenBy = hiddenBy
        self.nestedGoWithIt = nestedGoWithIt
    }
}
