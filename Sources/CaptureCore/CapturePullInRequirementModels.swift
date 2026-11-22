import Foundation

/// Positive requirement-card capability advertised by `pull_in.reqs`.
/// Older Bob executables omit this object entirely.
public struct CapturePullInRequirementCapability: Codable, Equatable, Sendable {
    public let supported: Bool
    public let pending: Int

    public init(supported: Bool = false, pending: Int = 0) {
        self.supported = supported
        self.pending = pending
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supported = (try? container.decodeIfPresent(Bool.self, forKey: .supported)) ?? false
        pending = (try? container.decodeIfPresent(Int.self, forKey: .pending)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case supported
        case pending
    }
}

/// Bob's snapshot-bound task identity for one requirement group owner.
public struct CaptureRequirementOwner: Codable, Equatable, Sendable {
    public let taskKey: String
    public let key: String
    public let path: String
    public let blockID: String
    public let line: Int
    public let text: String

    public init(
        taskKey: String = "",
        key: String = "",
        path: String = "",
        blockID: String = "",
        line: Int = 0,
        text: String = ""
    ) {
        self.taskKey = taskKey
        self.key = key
        self.path = path
        self.blockID = blockID
        self.line = line
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskKey = (try? container.decodeIfPresent(String.self, forKey: .taskKey)) ?? ""
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case taskKey = "task_key"
        case key
        case path
        case blockID = "block_id"
        case line
        case text
    }
}

/// The explicit sibling path Bob supplies for a requirement row. Its parsed
/// components are safe to compare as ancestry; row and owner keys remain opaque.
public struct CaptureRequirementSiblingPath: Codable, Equatable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public let components: [Int]

    public var description: String { rawValue }

    public init?(rawValue: String) {
        let pieces = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty else { return nil }
        var components: [Int] = []
        for piece in pieces {
            guard let component = Int(piece), component > 0 else { return nil }
            components.append(component)
        }
        self.rawValue = rawValue
        self.components = components
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let path = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a dot-separated positive sibling path"
            )
        }
        self = path
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Requirement-specific offer identity. It intentionally has no task status,
/// block ID, or destination fields.
public struct CaptureRequirementOffer: Codable, Equatable, Sendable {
    public let key: String
    public let n: Int
    public let group: String
    public let selected: Bool

    public init(key: String = "", n: Int = 0, group: String = "", selected: Bool = false) {
        self.key = key
        self.n = n
        self.group = group
        self.selected = selected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        n = (try? container.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        group = (try? container.decodeIfPresent(String.self, forKey: .group)) ?? ""
        selected = (try? container.decodeIfPresent(Bool.self, forKey: .selected)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case n
        case group
        case selected
    }
}

/// Bob's row-level requirement metadata from `pull_in.groups[].rows[].req`.
public struct CaptureRequirementDetail: Codable, Equatable, Sendable {
    public let ownerKey: String
    public let path: CaptureRequirementSiblingPath
    public let depth: Int
    public let parentKey: String?
    public let text: String
    public let line: Int
    public let state: String
    public let pendingDescendants: Int

    public var siblingPath: [Int] { path.components }

    public init(
        ownerKey: String = "",
        path: CaptureRequirementSiblingPath,
        depth: Int = 0,
        parentKey: String? = nil,
        text: String = "",
        line: Int = 0,
        state: String = "",
        pendingDescendants: Int = 0
    ) {
        self.ownerKey = ownerKey
        self.path = path
        self.depth = depth
        self.parentKey = parentKey
        self.text = text
        self.line = line
        self.state = state
        self.pendingDescendants = pendingDescendants
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ownerKey = (try? container.decodeIfPresent(String.self, forKey: .ownerKey)) ?? ""
        path = try container.decode(CaptureRequirementSiblingPath.self, forKey: .path)
        depth = try container.decode(Int.self, forKey: .depth)
        parentKey = try? container.decodeIfPresent(String.self, forKey: .parentKey)
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        state = (try? container.decodeIfPresent(String.self, forKey: .state)) ?? ""
        pendingDescendants =
            (try? container.decodeIfPresent(Int.self, forKey: .pendingDescendants)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case ownerKey = "owner"
        case path
        case depth
        case parentKey = "parent_key"
        case text
        case line
        case state
        case pendingDescendants = "pending_descendants"
    }
}

/// Bob-authored copy for the four requirement outcomes.
public struct CaptureRequirementConsequences: Codable, Equatable, Sendable {
    public let met: String
    public let drop: String
    public let carry: String
    public let carryPulled: String

    public init(met: String = "", drop: String = "", carry: String = "", carryPulled: String = "") {
        self.met = met
        self.drop = drop
        self.carry = carry
        self.carryPulled = carryPulled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        met = (try? container.decodeIfPresent(String.self, forKey: .met)) ?? ""
        drop = (try? container.decodeIfPresent(String.self, forKey: .drop)) ?? ""
        carry = (try? container.decodeIfPresent(String.self, forKey: .carry)) ?? ""
        carryPulled = (try? container.decodeIfPresent(String.self, forKey: .carryPulled)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case met
        case drop
        case carry
        case carryPulled = "carry_pulled"
    }
}

/// One actionable requirement row. Malformed rows are dropped independently
/// by the containing group's lossy row decoder.
public struct CaptureRequirementRow: Codable, Equatable, Sendable {
    public let offer: CaptureRequirementOffer
    public let req: CaptureRequirementDetail
    public let consequences: CaptureRequirementConsequences

    public var requirement: CaptureRequirementDetail { req }

    public var isSelectable: Bool {
        !offer.key.isEmpty && !req.ownerKey.isEmpty && req.depth > 0
            && req.depth == req.path.components.count && !req.text.isEmpty
    }

    public init(
        offer: CaptureRequirementOffer = CaptureRequirementOffer(),
        req: CaptureRequirementDetail,
        consequences: CaptureRequirementConsequences = CaptureRequirementConsequences()
    ) {
        self.offer = offer
        self.req = req
        self.consequences = consequences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        offer = try container.decode(CaptureRequirementOffer.self, forKey: .offer)
        req = try container.decode(CaptureRequirementDetail.self, forKey: .req)
        consequences = try container.decode(
            CaptureRequirementConsequences.self, forKey: .consequences)
    }

    private enum CodingKeys: String, CodingKey {
        case offer
        case req
        case consequences
    }
}

/// A newly carried task's Bob-issued identity in a requirement receipt.
public struct CaptureRequirementCarriedTask: Codable, Equatable, Sendable {
    public let path: String
    public let blockID: String
    public let line: Int

    public init(path: String = "", blockID: String = "", line: Int = 0) {
        self.path = path
        self.blockID = blockID
        self.line = line
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case blockID = "block_id"
        case line
    }
}

/// Bob-authored receipt returned for a requirement verdict or a Met owner.
public struct CaptureRequirementOutcome: Codable, Equatable, Sendable {
    public let n: Int
    public let key: String
    public let ownerKey: String
    public let ownerTaskKey: String
    public let path: String
    public let text: String
    public let verdict: String
    public let reason: String?
    public let carried: CaptureRequirementCarriedTask?
    public let pulled: Bool
    public let message: String

    public init(
        n: Int = 0,
        key: String = "",
        ownerKey: String = "",
        ownerTaskKey: String = "",
        path: String = "",
        text: String = "",
        verdict: String = "",
        reason: String? = nil,
        carried: CaptureRequirementCarriedTask? = nil,
        pulled: Bool = false,
        message: String = ""
    ) {
        self.n = n
        self.key = key
        self.ownerKey = ownerKey
        self.ownerTaskKey = ownerTaskKey
        self.path = path
        self.text = text
        self.verdict = verdict
        self.reason = reason
        self.carried = carried
        self.pulled = pulled
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        n = (try? container.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        ownerKey = (try? container.decodeIfPresent(String.self, forKey: .ownerKey)) ?? ""
        ownerTaskKey = (try? container.decodeIfPresent(String.self, forKey: .ownerTaskKey)) ?? ""
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        verdict = (try? container.decodeIfPresent(String.self, forKey: .verdict)) ?? ""
        reason = try? container.decodeIfPresent(String.self, forKey: .reason)
        carried = try? container.decodeIfPresent(
            CaptureRequirementCarriedTask.self, forKey: .carried)
        pulled = (try? container.decodeIfPresent(Bool.self, forKey: .pulled)) ?? false
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case n
        case key
        case ownerKey = "owner_key"
        case ownerTaskKey = "owner_task_key"
        case path
        case text
        case verdict
        case reason
        case carried
        case pulled
        case message
    }
}

/// Current requirement groups and numbered rows returned by a stale-key refusal.
public struct CaptureRequirementCurrent: Codable, Equatable, Sendable {
    public let groups: [CapturePullInGroup]
    public let rows: [CaptureRequirementCurrentRow]

    public init(groups: [CapturePullInGroup] = [], rows: [CaptureRequirementCurrentRow] = []) {
        self.groups = groups
        self.rows = rows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups =
            (try? container.decode(CaptureLossyArray<CapturePullInGroup>.self, forKey: .groups))?
            .values ?? []
        rows =
            (try? container.decode(
                CaptureLossyArray<CaptureRequirementCurrentRow>.self, forKey: .rows))?
            .values ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case groups
        case rows
    }
}

public struct CaptureRequirementCurrentRow: Codable, Equatable, Sendable {
    public let key: String
    public let n: Int
    public let kind: String

    public init(key: String = "", n: Int = 0, kind: String = "") {
        self.key = key
        self.n = n
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        n = (try? container.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case n
        case kind
    }
}

/// One final requirement verdict to encode in a single `bob capture` call.
public enum CaptureRequirementVerdictSubmission: Equatable, Sendable {
    case met(key: String)
    case drop(key: String, reason: String)
    case carry(key: String)
    case carryAndPull(key: String)

    public var key: String {
        switch self {
        case .met(let key), .carry(let key), .carryAndPull(let key): return key
        case .drop(let key, _): return key
        }
    }
}

/// Typed requirement verdicts passed separately from ordinary offer answers.
public struct CaptureRequirementSubmission: Equatable, Sendable {
    public let verdicts: [CaptureRequirementVerdictSubmission]

    public init(verdicts: [CaptureRequirementVerdictSubmission] = []) {
        self.verdicts = verdicts
    }

    public var isEmpty: Bool { verdicts.isEmpty }
}

/// Proof that the current Bob executable advertised requirement-choice support.
/// Only BobProcessClient creates proofs from a decoded positive capability.
public struct CaptureRequirementCapabilityProof: Equatable, Sendable {
    let executableIdentity: String

    func applies(to identity: String) -> Bool {
        executableIdentity == identity
    }
}

extension CapturePullInGroup {
    /// Bob has used `kind` for the requirement group; older grouped payloads
    /// may provide only `group`.
    public var effectiveKind: String {
        guard let kind, !kind.isEmpty else { return group }
        return kind
    }

    public var isRequirementGroup: Bool { effectiveKind == "requirements" }

    public var requirementOwnerKey: String? {
        if let owner, !owner.key.isEmpty {
            return owner.key
        }
        let keys = Set(rows.map(\.req.ownerKey).filter { !$0.isEmpty })
        return keys.count == 1 ? keys.first : nil
    }

    func replacingRequirementRows(_ rows: [CaptureRequirementRow]) -> CapturePullInGroup {
        CapturePullInGroup(
            group: group,
            kind: kind,
            owner: owner,
            project: project,
            note: note,
            after: after,
            label: label,
            event: event,
            folded: folded,
            rows: rows,
            copy: copy
        )
    }
}

extension CaptureCommandFailure {
    /// Fresh Bob-authored requirement groups carried by a stale keyed refusal.
    public var currentRequirementGroups: [CapturePullInGroup] {
        CaptureCommandSuccess.canonicalRequirementGroups(current?.groups ?? [])
    }
}
