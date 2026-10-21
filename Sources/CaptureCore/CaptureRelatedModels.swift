import Foundation

/// The schema-v1 draft response from `bob capture-related`. Bob owns matching
/// semantics and UTF-8 anchors; the Mac client only decodes and presents them.
public struct CaptureRelatedResponse: Decodable, Equatable, SchemaVersioned, Sendable {
  public let ok: Bool
  public let schemaVersion: Int
  public let warnings: [String]
  public let items: [CaptureRelatedItem]

  public init(
    ok: Bool = false,
    schemaVersion: Int = 1,
    warnings: [String] = [],
    items: [CaptureRelatedItem] = []
  ) {
    self.ok = ok
    self.schemaVersion = schemaVersion
    self.warnings = warnings
    self.items = items
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ok = (try? container.decodeIfPresent(Bool.self, forKey: .ok)) ?? false
    schemaVersion = (try? container.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 0
    warnings = (try? container.decodeIfPresent([String].self, forKey: .warnings)) ?? []
    items = (try? container.decodeIfPresent([CaptureRelatedItem].self, forKey: .items)) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case ok
    case schemaVersion = "schema_version"
    case warnings
    case items
  }
}

/// One task-creating item in the full draft. The byte ranges refer to the
/// submitted draft and must be thrown away after any edit.
public struct CaptureRelatedItem: Decodable, Equatable, Sendable {
  public let index: Int
  public let mode: String
  public let range: CaptureRange?
  public let markerAt: Int?
  public let routeRange: CaptureRange?
  public let discardRange: CaptureRange?
  public let matches: [CaptureRelatedMatch]
  public let linked: [CaptureRelatedLinked]

  public init(
    index: Int = 0,
    mode: String = "",
    range: CaptureRange? = nil,
    markerAt: Int? = nil,
    routeRange: CaptureRange? = nil,
    discardRange: CaptureRange? = nil,
    matches: [CaptureRelatedMatch] = [],
    linked: [CaptureRelatedLinked] = []
  ) {
    self.index = index
    self.mode = mode
    self.range = range
    self.markerAt = markerAt
    self.routeRange = routeRange
    self.discardRange = discardRange
    self.matches = matches
    self.linked = linked
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    index = (try? container.decodeIfPresent(Int.self, forKey: .index)) ?? 0
    mode = (try? container.decodeIfPresent(String.self, forKey: .mode)) ?? ""
    range = (try? container.decodeIfPresent(CaptureRange.self, forKey: .range)) ?? nil
    markerAt = (try? container.decodeIfPresent(Int.self, forKey: .markerAt)) ?? nil
    routeRange = (try? container.decodeIfPresent(CaptureRange.self, forKey: .routeRange)) ?? nil
    discardRange = (try? container.decodeIfPresent(CaptureRange.self, forKey: .discardRange)) ?? nil
    matches = (try? container.decodeIfPresent([CaptureRelatedMatch].self, forKey: .matches)) ?? []
    linked = (try? container.decodeIfPresent([CaptureRelatedLinked].self, forKey: .linked)) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case index
    case mode
    case range
    case markerAt = "marker_at"
    case routeRange = "route_range"
    case discardRange = "discard_range"
    case matches
    case linked
  }
}

/// Bob's band names are additive within schema v1. Keep unknown values so
/// callers can safely ignore a future band without rejecting the response.
public enum CaptureRelatedBand: Equatable, Sendable {
  case sameTitle
  case possibleDuplicate
  case similar
  case closedDuplicate
  case hold
  case unknown(String)

  public init(_ value: String) {
    switch value {
    case "same_title": self = .sameTitle
    case "possible_duplicate": self = .possibleDuplicate
    case "similar": self = .similar
    case "closed_duplicate": self = .closedDuplicate
    case "hold": self = .hold
    default: self = .unknown(value)
    }
  }

  public var wireValue: String {
    switch self {
    case .sameTitle: "same_title"
    case .possibleDuplicate: "possible_duplicate"
    case .similar: "similar"
    case .closedDuplicate: "closed_duplicate"
    case .hold: "hold"
    case .unknown(let value): value
    }
  }
}

extension CaptureRelatedBand: Decodable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init((try? container.decode(String.self)) ?? "")
  }
}

/// Bob-verified draft edits. Unknown actions are retained for forward-safe
/// decoding and omitted by the current UI.
public enum CaptureRelatedAction: Equatable, Sendable {
  case relate
  case note
  case needs
  case blocks
  case open
  case discard
  case unknown(String)

  public init(_ value: String) {
    switch value {
    case "relate": self = .relate
    case "note": self = .note
    case "needs": self = .needs
    case "blocks": self = .blocks
    case "open": self = .open
    case "discard": self = .discard
    default: self = .unknown(value)
    }
  }

  public var wireValue: String {
    switch self {
    case .relate: "relate"
    case .note: "note"
    case .needs: "needs"
    case .blocks: "blocks"
    case .open: "open"
    case .discard: "discard"
    case .unknown(let value): value
    }
  }
}

extension CaptureRelatedAction: Decodable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init((try? container.decode(String.self)) ?? "")
  }
}

public struct CaptureRelatedClosed: Decodable, Equatable, Sendable {
  public let status: String
  public let date: String
  public let daysAgo: Int

  public init(status: String = "", date: String = "", daysAgo: Int = 0) {
    self.status = status
    self.date = date
    self.daysAgo = daysAgo
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? ""
    date = (try? container.decodeIfPresent(String.self, forKey: .date)) ?? ""
    daysAgo = (try? container.decodeIfPresent(Int.self, forKey: .daysAgo)) ?? 0
  }

  private enum CodingKeys: String, CodingKey {
    case status
    case date
    case daysAgo = "days_ago"
  }
}

public enum CaptureRelatedLinkKind: Equatable, Sendable {
  case relation
  case dependency
  case blockedTask
  case parent
  case unknown(String)

  public init(_ value: String) {
    switch value {
    case "relation": self = .relation
    case "dependency": self = .dependency
    case "blocked_task": self = .blockedTask
    case "parent": self = .parent
    default: self = .unknown(value)
    }
  }

  public var wireValue: String {
    switch self {
    case .relation: "relation"
    case .dependency: "dependency"
    case .blockedTask: "blocked_task"
    case .parent: "parent"
    case .unknown(let value): value
    }
  }
}

extension CaptureRelatedLinkKind: Decodable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init((try? container.decode(String.self)) ?? "")
  }
}

public struct CaptureRelatedLinked: Decodable, Equatable, Sendable {
  public let key: String
  public let link: CaptureRelatedLinkKind

  public init(key: String = "", link: CaptureRelatedLinkKind = .unknown("")) {
    self.key = key
    self.link = link
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
    link = (try? container.decodeIfPresent(CaptureRelatedLinkKind.self, forKey: .link))
      ?? .unknown("")
  }

  private enum CodingKeys: String, CodingKey {
    case key
    case link
  }
}

public struct CaptureRelatedReplacements: Decodable, Equatable, Sendable {
  public let relationTo: String
  public let parent: String
  public let dependency: String
  public let blockedTask: String

  public init(
    relationTo: String = "",
    parent: String = "",
    dependency: String = "",
    blockedTask: String = ""
  ) {
    self.relationTo = relationTo
    self.parent = parent
    self.dependency = dependency
    self.blockedTask = blockedTask
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    relationTo = (try? container.decodeIfPresent(String.self, forKey: .relationTo)) ?? ""
    parent = (try? container.decodeIfPresent(String.self, forKey: .parent)) ?? ""
    dependency = (try? container.decodeIfPresent(String.self, forKey: .dependency)) ?? ""
    blockedTask = (try? container.decodeIfPresent(String.self, forKey: .blockedTask)) ?? ""
  }

  private enum CodingKeys: String, CodingKey {
    case relationTo = "relation_to"
    case parent
    case dependency
    case blockedTask = "blocked_task"
  }
}

public struct CaptureRelatedMatch: Decodable, Equatable, Sendable {
  public let key: String
  public let band: CaptureRelatedBand
  public let title: String
  public let matchedRanges: [CaptureRange]
  public let kind: String
  public let statusSymbol: String
  public let statusName: String
  public let statusType: String
  public let closed: CaptureRelatedClosed?
  public let route: String
  public let locator: String
  public let notePath: String
  public let target: String
  public let line: Int
  public let taskRef: String
  public let blockID: String?
  public let requiresBlockID: Bool
  public let blockIDSuggestions: [String]
  public let replacements: CaptureRelatedReplacements?
  public let actions: [CaptureRelatedAction]
  public let defaultAction: CaptureRelatedAction?

  public init(
    key: String = "",
    band: CaptureRelatedBand = .unknown(""),
    title: String = "",
    matchedRanges: [CaptureRange] = [],
    kind: String = "",
    statusSymbol: String = "",
    statusName: String = "",
    statusType: String = "",
    closed: CaptureRelatedClosed? = nil,
    route: String = "",
    locator: String = "",
    notePath: String = "",
    target: String = "",
    line: Int = 0,
    taskRef: String = "",
    blockID: String? = nil,
    requiresBlockID: Bool = false,
    blockIDSuggestions: [String] = [],
    replacements: CaptureRelatedReplacements? = nil,
    actions: [CaptureRelatedAction] = [],
    defaultAction: CaptureRelatedAction? = nil
  ) {
    self.key = key
    self.band = band
    self.title = title
    self.matchedRanges = matchedRanges
    self.kind = kind
    self.statusSymbol = statusSymbol
    self.statusName = statusName
    self.statusType = statusType
    self.closed = closed
    self.route = route
    self.locator = locator
    self.notePath = notePath
    self.target = target
    self.line = line
    self.taskRef = taskRef
    self.blockID = blockID
    self.requiresBlockID = requiresBlockID
    self.blockIDSuggestions = blockIDSuggestions
    self.replacements = replacements
    self.actions = actions
    self.defaultAction = defaultAction
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
    band = (try? container.decodeIfPresent(CaptureRelatedBand.self, forKey: .band))
      ?? .unknown("")
    title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
    let rawRanges = (try? container.decodeIfPresent([[Int]].self, forKey: .matchedRanges)) ?? []
    matchedRanges = rawRanges.compactMap { values in
      guard values.count == 2, values[0] <= values[1] else { return nil }
      return CaptureRange(start: values[0], end: values[1])
    }
    kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? ""
    statusSymbol = (try? container.decodeIfPresent(String.self, forKey: .statusSymbol)) ?? ""
    statusName = (try? container.decodeIfPresent(String.self, forKey: .statusName)) ?? ""
    statusType = (try? container.decodeIfPresent(String.self, forKey: .statusType)) ?? ""
    closed = (try? container.decodeIfPresent(CaptureRelatedClosed.self, forKey: .closed)) ?? nil
    route = (try? container.decodeIfPresent(String.self, forKey: .route)) ?? ""
    locator = (try? container.decodeIfPresent(String.self, forKey: .locator)) ?? ""
    notePath = (try? container.decodeIfPresent(String.self, forKey: .notePath)) ?? ""
    target = (try? container.decodeIfPresent(String.self, forKey: .target)) ?? ""
    line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
    taskRef = (try? container.decodeIfPresent(String.self, forKey: .taskRef)) ?? ""
    blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? nil
    requiresBlockID = (try? container.decodeIfPresent(Bool.self, forKey: .requiresBlockID)) ?? false
    blockIDSuggestions =
      (try? container.decodeIfPresent([String].self, forKey: .blockIDSuggestions)) ?? []
    replacements =
      (try? container.decodeIfPresent(CaptureRelatedReplacements.self, forKey: .replacements)) ?? nil
    actions = (try? container.decodeIfPresent([CaptureRelatedAction].self, forKey: .actions)) ?? []
    defaultAction =
      (try? container.decodeIfPresent(CaptureRelatedAction.self, forKey: .defaultAction)) ?? nil
  }

  private enum CodingKeys: String, CodingKey {
    case key
    case band
    case title
    case matchedRanges = "matched_ranges"
    case kind
    case statusSymbol = "status_symbol"
    case statusName = "status_name"
    case statusType = "status_type"
    case closed
    case route
    case locator
    case notePath = "note_path"
    case target
    case line
    case taskRef = "ref"
    case blockID = "block_id"
    case requiresBlockID = "requires_block_id"
    case blockIDSuggestions = "block_id_suggestions"
    case replacements
    case actions
    case defaultAction = "default_action"
  }
}
