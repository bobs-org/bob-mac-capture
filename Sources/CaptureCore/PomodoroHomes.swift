import Foundation

/// Additive R9 `homes` object on a Pomodoro entry. bob owns every fact;
/// the app only decodes and draws. Unknown enum strings land on `.other`
/// instead of failing the snapshot. A missing object is `nil`.
public struct CaptureAgendaHomes: Decodable, Equatable, Sendable {
    public let state: CaptureAgendaHomesState
    public let kind: CaptureAgendaHomesKind
    public let label: String
    public let chip: String?
    public let hue: PomodoroHomeHue?
    public let parts: [CaptureAgendaHomePart]

    public init(
        state: CaptureAgendaHomesState = .other(""),
        kind: CaptureAgendaHomesKind = .other(""),
        label: String = "",
        chip: String? = nil,
        hue: PomodoroHomeHue? = nil,
        parts: [CaptureAgendaHomePart] = []
    ) {
        self.state = state
        self.kind = kind
        self.label = label
        self.chip = chip
        self.hue = hue
        self.parts = parts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decodeIfPresent(
            CaptureAgendaHomesState.self,
            forKey: .state
        ) ?? .other("")
        kind = try container.decodeIfPresent(
            CaptureAgendaHomesKind.self,
            forKey: .kind
        ) ?? .other("")
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        chip = try container.decodeIfPresent(String.self, forKey: .chip)
        hue = try container.decodeIfPresent(PomodoroHomeHue.self, forKey: .hue)
        parts = try container.decodeIfPresent(
            [CaptureAgendaHomePart].self,
            forKey: .parts
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case kind
        case label
        case chip
        case hue
        case parts
    }
}

/// One home share inside `homes.parts`.
public struct CaptureAgendaHomePart: Decodable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let kind: CaptureAgendaHomePartKind
    public let area: String?
    public let areaLabel: String?
    public let hue: PomodoroHomeHue?
    public let tasks: Int
    public let share: Int
    public let minutes: Int?

    public init(
        key: String = "",
        label: String = "",
        kind: CaptureAgendaHomePartKind = .other(""),
        area: String? = nil,
        areaLabel: String? = nil,
        hue: PomodoroHomeHue? = nil,
        tasks: Int = 0,
        share: Int = 0,
        minutes: Int? = nil
    ) {
        self.key = key
        self.label = label
        self.kind = kind
        self.area = area
        self.areaLabel = areaLabel
        self.hue = hue
        self.tasks = tasks
        self.share = share
        self.minutes = minutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        kind = try container.decodeIfPresent(
            CaptureAgendaHomePartKind.self,
            forKey: .kind
        ) ?? .other("")
        area = try container.decodeIfPresent(String.self, forKey: .area)
        areaLabel = try container.decodeIfPresent(String.self, forKey: .areaLabel)
        hue = try container.decodeIfPresent(PomodoroHomeHue.self, forKey: .hue)
        tasks = try container.decodeIfPresent(Int.self, forKey: .tasks) ?? 0
        share = try container.decodeIfPresent(Int.self, forKey: .share) ?? 0
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case label
        case kind
        case area
        case areaLabel = "area_label"
        case hue
        case tasks
        case share
        case minutes
    }
}

/// `homes.state`. Unknown strings decode to `.other`.
public enum CaptureAgendaHomesState: Hashable, Sendable, Decodable {
    case attributed
    case forecast
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "attributed":
            self = .attributed
        case "forecast":
            self = .forecast
        default:
            self = .other(raw)
        }
    }
}

/// `homes.kind`. Unknown strings decode to `.other`.
public enum CaptureAgendaHomesKind: Hashable, Sendable, Decodable {
    case work
    case review
    case unlinked
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "work":
            self = .work
        case "review":
            self = .review
        case "unlinked":
            self = .unlinked
        default:
            self = .other(raw)
        }
    }
}

/// A part's `kind`. Unknown strings decode to `.other`.
public enum CaptureAgendaHomePartKind: Hashable, Sendable, Decodable {
    case project
    case area
    case bucket
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "project":
            self = .project
        case "area":
            self = .area
        case "bucket":
            self = .bucket
        default:
            self = .other(raw)
        }
    }
}

/// R8 area-hue slots. Unknown strings decode to `.other`. Hex values
/// match `docs/pomodoro-homes.md`; views pick light or dark by appearance.
public enum PomodoroHomeHue: Hashable, Sendable, Decodable {
    case blue
    case orange
    case aqua
    case yellow
    case magenta
    case green
    case violet
    case red
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "blue":
            self = .blue
        case "orange":
            self = .orange
        case "aqua":
            self = .aqua
        case "yellow":
            self = .yellow
        case "magenta":
            self = .magenta
        case "green":
            self = .green
        case "violet":
            self = .violet
        case "red":
            self = .red
        default:
            self = .other(raw)
        }
    }

    /// Light-appearance hex, or nil for an unknown slot.
    public var lightHex: String? {
        switch self {
        case .blue: return "#2a78d6"
        case .orange: return "#eb6834"
        case .aqua: return "#1baf7a"
        case .yellow: return "#eda100"
        case .magenta: return "#e87ba4"
        case .green: return "#008300"
        case .violet: return "#6250d6"
        case .red: return "#e34948"
        case .other: return nil
        }
    }

    /// Dark-appearance hex, or nil for an unknown slot.
    public var darkHex: String? {
        switch self {
        case .blue: return "#3987e5"
        case .orange: return "#d95926"
        case .aqua: return "#199e70"
        case .yellow: return "#c98500"
        case .magenta: return "#d55181"
        case .green: return "#008300"
        case .violet: return "#9085e9"
        case .red: return "#e66767"
        case .other: return nil
        }
    }
}

/// Shared copy for unnamed Pomodoros: derived home label, else Untitled.
public enum PomodoroHomesPresentation {
    public static let untitled = "Untitled Pomodoro"

    public static func displayName(authored: String?, homes: CaptureAgendaHomes?) -> String {
        if let authored, !authored.isEmpty {
            return authored
        }
        if let label = homes?.label, !label.isEmpty {
            return label
        }
        return untitled
    }

    public static func nameIsDerived(authored: String?, homes: CaptureAgendaHomes?) -> Bool {
        if let authored, !authored.isEmpty {
            return false
        }
        if let label = homes?.label, !label.isEmpty {
            return true
        }
        return false
    }

    public static func namedChip(authored: String?, homes: CaptureAgendaHomes?) -> String? {
        guard let authored, !authored.isEmpty else {
            return nil
        }
        guard let chip = homes?.chip, !chip.isEmpty else {
            return nil
        }
        return chip
    }

    /// Spoken name for accessibility: derived labels read "for sase".
    public static func accessibilityName(authored: String?, homes: CaptureAgendaHomes?) -> String {
        let name = displayName(authored: authored, homes: homes)
        if nameIsDerived(authored: authored, homes: homes) {
            return "for \(name)"
        }
        if let chip = namedChip(authored: authored, homes: homes) {
            return "\(name), for \(chip)"
        }
        return name
    }
}
