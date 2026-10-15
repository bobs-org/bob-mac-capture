import CaptureCore
import Foundation

/// A JSON value kept for fields whose shape is owned by `bob` and may grow
/// additively, such as the write-flow commit report.
public enum RefsRenameJSONValue: Equatable, Sendable, Codable {
  case object([String: RefsRenameJSONValue])
  case array([RefsRenameJSONValue])
  case string(String)
  case integer(Int64)
  case number(Double)
  case bool(Bool)
  case null

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if try container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([RefsRenameJSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: RefsRenameJSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "unsupported JSON value in bob ref rename report"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}

/// A vault-relative old or new reference location from bob's rename report.
public struct RefsRenameLocation: Decodable, Equatable, Sendable {
  public let path: String?
  public let pdf: String?
  public let stem: String?

  public init(path: String? = nil, pdf: String? = nil, stem: String? = nil) {
    self.path = path
    self.pdf = pdf
    self.stem = stem
  }

  private enum CodingKeys: String, CodingKey {
    case path
    case pdf
    case stem
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decodeIfPresent(String.self, forKey: .path)
    pdf = try container.decodeIfPresent(String.self, forKey: .pdf)
    stem = try container.decodeIfPresent(String.self, forKey: .stem)
  }
}

/// One companion file move returned by bob.
public struct RefsRenameMove: Decodable, Equatable, Sendable {
  public let kind: String?
  public let from: String?
  public let to: String?

  public init(kind: String? = nil, from: String? = nil, to: String? = nil) {
    self.kind = kind
    self.from = from
    self.to = to
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case from
    case to
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    kind = try container.decodeIfPresent(String.self, forKey: .kind)
    from = try container.decodeIfPresent(String.self, forKey: .from)
    to = try container.decodeIfPresent(String.self, forKey: .to)
  }
}

/// Inbound-link counts and paths reported by bob's link rewriter.
public struct RefsRenameLinks: Decodable, Equatable, Sendable {
  public let rewritten: Int?
  public let files: [String]

  public init(rewritten: Int? = nil, files: [String] = []) {
    self.rewritten = rewritten
    self.files = files
  }

  private enum CodingKeys: String, CodingKey {
    case rewritten
    case files
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    rewritten = try container.decodeIfPresent(Int.self, forKey: .rewritten)
    files = try container.decodeIfPresent([String].self, forKey: .files) ?? []
  }
}

/// The typed `error` body in a bob ref rename error envelope.
public struct RefsRenameFailure: Decodable, Equatable, Sendable {
  public let code: String
  public let message: String
  public let hint: String?

  public init(code: String, message: String, hint: String? = nil) {
    self.code = code
    self.message = message
    self.hint = hint
  }

  private enum CodingKeys: String, CodingKey {
    case code
    case message
    case hint
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let code = try container.decodeIfPresent(String.self, forKey: .code),
      let message = try container.decodeIfPresent(String.self, forKey: .message)
    else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "bob ref rename error requires code and message"
        )
      )
    }
    self.code = code
    self.message = message
    hint = try container.decodeIfPresent(String.self, forKey: .hint)
  }
}

/// The small part of bob's pre/post sync report that Bob Refs needs.
public struct RefsRenameSync: Decodable, Equatable, Sendable {
  public let pre: String?
  public let post: String?

  public init(pre: String? = nil, post: String? = nil) {
    self.pre = pre
    self.post = post
  }

  private enum CodingKeys: String, CodingKey {
    case pre
    case post
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    pre = try container.decodeIfPresent(String.self, forKey: .pre)
    post = try container.decodeIfPresent(String.self, forKey: .post)
  }
}

/// The `bob ref rename -f json` envelope. Only `schema_version` is
/// mandatory; fields added by later bob versions and absent from older
/// output do not make the installed client fail to decode.
public struct RefsRenameResponse: Decodable, Equatable, Sendable, SchemaVersioned {
  public let schemaVersion: Int
  public let ok: Bool?
  public let from: RefsRenameLocation?
  public let to: RefsRenameLocation?
  public let moves: [RefsRenameMove]
  public let links: RefsRenameLinks?
  public let outcome: String?
  public let changed: Bool?
  public let commit: RefsRenameJSONValue?
  public let sync: RefsRenameSync?
  public let warnings: [String]
  public let error: RefsRenameFailure?

  public init(
    schemaVersion: Int = 1,
    ok: Bool? = nil,
    from: RefsRenameLocation? = nil,
    to: RefsRenameLocation? = nil,
    moves: [RefsRenameMove] = [],
    links: RefsRenameLinks? = nil,
    outcome: String? = nil,
    changed: Bool? = nil,
    commit: RefsRenameJSONValue? = nil,
    sync: RefsRenameSync? = nil,
    warnings: [String] = [],
    error: RefsRenameFailure? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.ok = ok
    self.from = from
    self.to = to
    self.moves = moves
    self.links = links
    self.outcome = outcome
    self.changed = changed
    self.commit = commit
    self.sync = sync
    self.warnings = warnings
    self.error = error
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case ok
    case from
    case to
    case moves
    case links
    case outcome
    case changed
    case commit
    case sync
    case warnings
    case error
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
    from = try container.decodeIfPresent(RefsRenameLocation.self, forKey: .from)
    to = try container.decodeIfPresent(RefsRenameLocation.self, forKey: .to)
    moves = try container.decodeIfPresent([RefsRenameMove].self, forKey: .moves) ?? []
    links = try container.decodeIfPresent(RefsRenameLinks.self, forKey: .links)
    outcome = try container.decodeIfPresent(String.self, forKey: .outcome)
    changed = try container.decodeIfPresent(Bool.self, forKey: .changed)
    commit = try container.decodeIfPresent(RefsRenameJSONValue.self, forKey: .commit)
    sync = try container.decodeIfPresent(RefsRenameSync.self, forKey: .sync)
    warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    error = try container.decodeIfPresent(RefsRenameFailure.self, forKey: .error)
  }
}

/// Maps transport failures to the same typed shape as bob's JSON error
/// envelope, so the card can render one consistent inline problem.
public enum RefsRenameProblemMapping {
  public static func responseProblem(_ response: RefsRenameResponse) -> RefsRenameFailure? {
    response.error
  }

  public static func transportProblem(for error: Error) -> RefsRenameFailure {
    if let clientError = error as? BobClientError {
      if case .timedOut = clientError {
        return RefsRenameFailure(
          code: "timed_out",
          message: "The reference rename took too long and was stopped.",
          hint: "Try the rename again after checking Bob's vault sync and locks."
        )
      }
      if case .processFailed(_, let exitStatus, _) = clientError, exitStatus == 2 {
        return RefsRenameFailure(
          code: "bob_too_old",
          message: "This bob can't rename references yet — update bob on this Mac"
        )
      }
    }
    return RefsRenameFailure(
      code: "transport",
      message: boundedProcessText(error.localizedDescription)
    )
  }
}

public enum RefsRenameKeyCommand: Equatable, Sendable {
  case submit
  case cancel
  /// A recognized card key that must not reach the editable text field.
  case ignore
}

/// Key handling for the rename field. Ordinary text and shortcuts return
/// nil so AppKit's text field can edit them normally.
public enum RefsRenameKeyMap {
  public static func command(
    keyCode: UInt16,
    modifiers: RefsCopyKeyModifiers,
    isRunning: Bool,
    hasMarkedText: Bool = false
  ) -> RefsRenameKeyCommand? {
    let flags = modifiers.subtracting([.capsLock, .numericPad, .function, .help])

    if keyCode == 36 || keyCode == 76, flags.isEmpty {
      return isRunning || hasMarkedText ? .ignore : .submit
    }
    if keyCode == 53, flags.isEmpty {
      return isRunning ? .ignore : .cancel
    }
    if keyCode == 33, flags == .control {
      return isRunning ? .ignore : .cancel
    }
    return nil
  }
}

public enum RefsRenamePhase: Equatable, Sendable {
  case idle
  case running
  case failed(message: String, hint: String?)
}

public enum RefsRenameCardEffect: Equatable, Sendable {
  case none
  case submit(name: String)
  case cancel
}

/// Pure state for Bob Refs' rename card. Bob owns rename semantics; this
/// value only freezes the selected row, edits the file stem, and reports
/// submit/cancel effects to the app layer.
public struct RefsRenameCard: Equatable, Sendable {
  public static let pdfSuffix = ".pdf"

  public let frozenItemID: String
  public let notePath: String
  public let title: String
  public private(set) var draftStem: String
  public private(set) var phase: RefsRenamePhase

  public init(item: RefItem) {
    frozenItemID = item.id
    notePath = item.id
    title = item.rawTitle
    draftStem = item.stem
    phase = .idle
  }

  public var fileName: String {
    draftStem + Self.pdfSuffix
  }

  public mutating func editDraftStem(_ stem: String) {
    guard phase != .running else { return }
    draftStem = stem
    if case .failed = phase {
      phase = .idle
    }
  }

  @discardableResult
  public mutating func handle(_ command: RefsRenameKeyCommand) -> RefsRenameCardEffect {
    switch command {
    case .submit:
      guard phase != .running else { return .none }
      phase = .running
      return .submit(name: draftStem)
    case .cancel:
      guard phase != .running else { return .none }
      return .cancel
    case .ignore:
      return .none
    }
  }

  public mutating func fail(message: String, hint: String?) {
    guard phase == .running else { return }
    phase = .failed(message: message, hint: hint)
  }
}

public enum RefsRenamePresentation {
  public static let caption = "Also renames the note and updates links. Keeps the reading task."
  public static let quietHint = "Close the PDF in Highlights first."

  public static func footerStatus(stem: String, rewrittenLinks: Int) -> String {
    let fileName = stem + RefsRenameCard.pdfSuffix
    guard rewrittenLinks > 0 else {
      return "Renamed → \(fileName) · no links updated"
    }
    let noun = rewrittenLinks == 1 ? "link" : "links"
    return "Renamed → \(fileName) · \(rewrittenLinks) \(noun) updated"
  }

  public static func announcement(stem: String) -> String {
    "Reference renamed to \(stem)\(RefsRenameCard.pdfSuffix)"
  }

  public static func notification(stem: String) -> (title: String, body: String) {
    (title: "Reference renamed", body: stem + RefsRenameCard.pdfSuffix)
  }
}
