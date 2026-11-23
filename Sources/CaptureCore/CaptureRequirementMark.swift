import Foundation

/// Display state supplied by Bob, never inferred from checkbox bytes or owner state.
public enum CaptureRequirementState: String, Codable, Hashable, Sendable, CaseIterable {
    case pending, met, moot, dropped, carried, excluded

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .pending
    }

    public var markOpacity: Double {
        switch self {
        case .pending, .carried: 0.9
        case .met: 0.62
        case .moot, .excluded: 0.42
        case .dropped: 0.55
        }
    }

    public var textIsMuted: Bool {
        switch self {
        case .met, .moot, .dropped, .excluded: true
        case .pending, .carried: false
        }
    }

    /// Default Met remains hollow until Bob reports that the close has landed.
    public static func staged(_ verdict: CaptureRequirementStagedVerdict?) -> Self {
        switch verdict {
        case .none: .pending
        case .drop: .dropped
        case .carry, .carryPulled: .carried
        }
    }
}

/// Additive `req: {depth, state}` on preview and agenda lines. Invalid objects
/// are discarded by their containing line, preserving older Bob's rendering.
public struct CaptureRequirementAnnotation: Codable, Hashable, Sendable {
    public let depth: Int
    public let state: CaptureRequirementState

    public init(depth: Int, state: CaptureRequirementState) {
        self.depth = depth
        self.state = state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        depth = try container.decode(Int.self, forKey: .depth)
        guard depth > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .depth, in: container,
                debugDescription: "Requirement depth must be positive")
        }
        state = try container.decode(CaptureRequirementState.self, forKey: .state)
    }

    public var accessibilityLabel: String {
        "Requirement · \(state.rawValue.capitalized) · level \(depth)"
    }

    /// Bob has already identified a requirement; this only removes its display
    /// prefix. A missing/unexpected prefix stays verbatim, never losing prose.
    public func agendaText(_ text: String) -> String {
        let prefix = Array(text.prefix(4))
        guard prefix.count == 4, prefix[0] == "[", prefix[2] == "]", prefix[3] == " " else {
            return text
        }
        return String(text.dropFirst(4))
    }

    private enum CodingKeys: String, CodingKey {
        case depth, state
    }
}
