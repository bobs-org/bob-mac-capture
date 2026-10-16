import Foundation

public struct CaptureSavedTemplatesResponse: Codable, Equatable, SchemaVersioned, Sendable {
  public let schemaVersion: Int
  public let capacity: Int
  public let saving: Bool
  public let file: String
  public let templates: [CaptureSavedTemplate]
  public let warnings: [String]

  public init(
    schemaVersion: Int = 1,
    capacity: Int = 0,
    saving: Bool = false,
    file: String = "",
    templates: [CaptureSavedTemplate] = [],
    warnings: [String] = []
  ) {
    self.schemaVersion = schemaVersion
    self.capacity = capacity
    self.saving = saving
    self.file = file
    self.templates = templates
    self.warnings = warnings
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = (try? container.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 0
    capacity = (try? container.decodeIfPresent(Int.self, forKey: .capacity)) ?? 0
    saving = (try? container.decodeIfPresent(Bool.self, forKey: .saving)) ?? false
    file = (try? container.decodeIfPresent(String.self, forKey: .file)) ?? ""
    templates =
      (try? container.decodeIfPresent([CaptureSavedTemplate].self, forKey: .templates)) ?? []
    warnings = (try? container.decodeIfPresent([String].self, forKey: .warnings)) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case capacity
    case saving
    case file
    case templates
    case warnings
  }
}

public struct CaptureSavedTemplate: Codable, Equatable, Identifiable, Sendable {
  public let index: Int
  public let id: String
  public let text: String
  public let draft: String
  public let cursor: Int
  public let fieldCount: Int
  public let lineCount: Int
  public let route: String?
  public let spans: [CaptureSpan]
  public let firstSavedAt: String?
  public let lastUsedAt: String?
  public let useCount: Int

  public init(
    index: Int = 0,
    id: String = "",
    text: String = "",
    draft: String = "",
    cursor: Int = 0,
    fieldCount: Int = 0,
    lineCount: Int = 0,
    route: String? = nil,
    spans: [CaptureSpan] = [],
    firstSavedAt: String? = nil,
    lastUsedAt: String? = nil,
    useCount: Int = 0
  ) {
    self.index = index
    self.id = id
    self.text = text
    self.draft = draft
    self.cursor = cursor
    self.fieldCount = fieldCount
    self.lineCount = lineCount
    self.route = route
    self.spans = spans
    self.firstSavedAt = firstSavedAt
    self.lastUsedAt = lastUsedAt
    self.useCount = useCount
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    index = (try? container.decodeIfPresent(Int.self, forKey: .index)) ?? 0
    id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? ""
    text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
    draft = (try? container.decodeIfPresent(String.self, forKey: .draft)) ?? ""
    cursor = (try? container.decodeIfPresent(Int.self, forKey: .cursor)) ?? 0
    fieldCount = (try? container.decodeIfPresent(Int.self, forKey: .fieldCount)) ?? 0
    lineCount = (try? container.decodeIfPresent(Int.self, forKey: .lineCount)) ?? 0
    route = (try? container.decodeIfPresent(String.self, forKey: .route)) ?? nil
    spans = (try? container.decodeIfPresent([CaptureSpan].self, forKey: .spans)) ?? []
    firstSavedAt = (try? container.decodeIfPresent(String.self, forKey: .firstSavedAt)) ?? nil
    lastUsedAt = (try? container.decodeIfPresent(String.self, forKey: .lastUsedAt)) ?? nil
    useCount = max(0, (try? container.decodeIfPresent(Int.self, forKey: .useCount)) ?? 0)
  }

  private enum CodingKeys: String, CodingKey {
    case index
    case id
    case text
    case draft
    case cursor
    case fieldCount = "field_count"
    case lineCount = "line_count"
    case route
    case spans
    case firstSavedAt = "first_saved_at"
    case lastUsedAt = "last_used_at"
    case useCount = "use_count"
  }
}

public enum CaptureTemplateSavedStatus: String, Codable, Equatable, Sendable {
  case new
  case updated
  case replaced
  case unknown

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self(rawValue: (try? container.decode(String.self)) ?? "") ?? .unknown
  }
}

public struct CaptureTemplateSavedSummary: Codable, Equatable, Sendable {
  public let id: String
  public let status: CaptureTemplateSavedStatus

  public init(id: String = "", status: CaptureTemplateSavedStatus = .unknown) {
    self.id = id
    self.status = status
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? ""
    status =
      (try? container.decodeIfPresent(CaptureTemplateSavedStatus.self, forKey: .status)) ?? .unknown
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case status
  }
}

public protocol CaptureTemplateProtocolResponse: Decodable {
  var ok: Bool { get }
  var error: String? { get }
}

public struct CaptureTemplateSaveResponse: Codable, Equatable, Sendable,
  CaptureTemplateProtocolResponse
{
  public let ok: Bool
  public let saved: CaptureTemplateSavedSummary?
  public let template: CaptureSavedTemplate?
  public let error: String?
  public let code: String?

  public init(
    ok: Bool = false,
    saved: CaptureTemplateSavedSummary? = nil,
    template: CaptureSavedTemplate? = nil,
    error: String? = nil,
    code: String? = nil
  ) {
    self.ok = ok
    self.saved = saved
    self.template = template
    self.error = error
    self.code = code
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ok = (try? container.decodeIfPresent(Bool.self, forKey: .ok)) ?? false
    saved =
      (try? container.decodeIfPresent(CaptureTemplateSavedSummary.self, forKey: .saved)) ?? nil
    template = (try? container.decodeIfPresent(CaptureSavedTemplate.self, forKey: .template)) ?? nil
    error = (try? container.decodeIfPresent(String.self, forKey: .error)) ?? nil
    code = (try? container.decodeIfPresent(String.self, forKey: .code)) ?? nil
  }

  private enum CodingKeys: String, CodingKey {
    case ok
    case saved
    case template
    case error
    case code
  }
}

public struct CaptureTemplateDeleteResponse: Codable, Equatable, Sendable,
  CaptureTemplateProtocolResponse
{
  public let ok: Bool
  public let deleted: [String]
  public let missing: [String]
  public let error: String?
  public let code: String?

  public init(
    ok: Bool = false, deleted: [String] = [], missing: [String] = [], error: String? = nil,
    code: String? = nil
  ) {
    self.ok = ok
    self.deleted = deleted
    self.missing = missing
    self.error = error
    self.code = code
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ok = (try? container.decodeIfPresent(Bool.self, forKey: .ok)) ?? false
    deleted = (try? container.decodeIfPresent([String].self, forKey: .deleted)) ?? []
    missing = (try? container.decodeIfPresent([String].self, forKey: .missing)) ?? []
    error = (try? container.decodeIfPresent(String.self, forKey: .error)) ?? nil
    code = (try? container.decodeIfPresent(String.self, forKey: .code)) ?? nil
  }

  private enum CodingKeys: String, CodingKey {
    case ok
    case deleted
    case missing
    case error
    case code
  }
}

public struct CaptureTemplateClearResponse: Codable, Equatable, Sendable,
  CaptureTemplateProtocolResponse
{
  public let ok: Bool
  public let cleared: Int
  public let error: String?
  public let code: String?

  public init(ok: Bool = false, cleared: Int = 0, error: String? = nil, code: String? = nil) {
    self.ok = ok
    self.cleared = cleared
    self.error = error
    self.code = code
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ok = (try? container.decodeIfPresent(Bool.self, forKey: .ok)) ?? false
    cleared = (try? container.decodeIfPresent(Int.self, forKey: .cleared)) ?? 0
    error = (try? container.decodeIfPresent(String.self, forKey: .error)) ?? nil
    code = (try? container.decodeIfPresent(String.self, forKey: .code)) ?? nil
  }

  private enum CodingKeys: String, CodingKey {
    case ok
    case cleared
    case error
    case code
  }
}

public struct CaptureSavedTemplateSegment: Equatable, Sendable {
  public let text: String
  public let category: CaptureSemanticCategory

  public init(text: String, category: CaptureSemanticCategory) {
    self.text = text
    self.category = category
  }
}

/// Portable row content for the Control-T picker. Bob's spans remain the
/// only source of syntax coloring; this builder only clips them to the two
/// lines the row displays.
public struct CaptureSavedTemplatePresentation: Equatable, Sendable {
  public let index: Int
  public let id: String
  public let parentLine: [CaptureSavedTemplateSegment]
  public let firstChildLine: [CaptureSavedTemplateSegment]?
  public let moreLinesCount: Int
  public let slotDotFields: [Int]
  public let slotOverflowCount: Int
  public let metadataText: String
  public let accessibilityLabel: String
  public let accessibilityHint: String

  public var parentText: String { parentLine.map(\.text).joined() }
  public var firstChildText: String? { firstChildLine?.map(\.text).joined() }

  public init(template: CaptureSavedTemplate, now: Date = Date()) {
    index = template.index
    id = template.id

    let lines = Self.lineBounds(in: template.text)
    let parentBounds = lines.first ?? 0..<0
    parentLine = Self.segments(for: parentBounds, text: template.text, spans: template.spans)
    if lines.count > 1 {
      firstChildLine = Self.segments(for: lines[1], text: template.text, spans: template.spans)
    } else {
      firstChildLine = nil
    }
    moreLinesCount = max(0, template.lineCount - 2)
    slotDotFields = Array(0..<min(max(template.fieldCount, 0), 6))
    slotOverflowCount = max(0, template.fieldCount - slotDotFields.count)

    let savedDate = Self.parseDate(
      template.useCount > 0 ? (template.lastUsedAt ?? template.firstSavedAt) : template.firstSavedAt
    )
    let shortAge =
      savedDate.map { CapturePickerHelpers.relativeAgeDescription(from: $0, to: now) } ?? "just now"
    var metadata = ["\(template.fieldCount) \(template.fieldCount == 1 ? "field" : "fields")"]
    if let route = template.route, !route.isEmpty {
      metadata.append(route)
    }
    if template.useCount > 0 {
      metadata.append("used \(template.useCount)×")
    } else {
      metadata.append("saved \(shortAge)")
    }
    if template.useCount > 0 {
      metadata.append(shortAge)
    }
    metadataText = metadata.joined(separator: " · ")

    let spokenAge =
      savedDate.map {
        CapturePickerHelpers.spokenRelativeAgeDescription(from: $0, to: now)
      } ?? "just now"
    var label = ["Template \(template.index)", parentLine.map(\.text).joined()]
    label.append("\(template.fieldCount) \(template.fieldCount == 1 ? "field" : "fields")")
    if let route = template.route, !route.isEmpty {
      label.append(route)
    }
    if template.useCount > 0 {
      label.append("used \(template.useCount) \(template.useCount == 1 ? "time" : "times")")
      label.append(spokenAge)
    } else {
      label.append("saved \(spokenAge)")
    }
    accessibilityLabel = label.joined(separator: ", ")
    let accelerator = CapturePickerHelpers.accelerator(for: max(0, template.index - 1)) ?? ""
    accessibilityHint =
      "Press \(accelerator) or Return to use this template. Press Delete twice to delete it."
  }

  private static func lineBounds(in text: String) -> [Range<Int>] {
    let bytes = Array(text.utf8)
    var starts = [0]
    for (index, byte) in bytes.enumerated() where byte == 10 {
      starts.append(index + 1)
    }
    return starts.enumerated().map { lineIndex, start in
      let end = lineIndex + 1 < starts.count ? starts[lineIndex + 1] - 1 : bytes.count
      return start..<end
    }
  }

  private static func segments(
    for bounds: Range<Int>,
    text: String,
    spans: [CaptureSpan]
  ) -> [CaptureSavedTemplateSegment] {
    guard !bounds.isEmpty else { return [] }
    let relevant =
      spans
      .filter { $0.end > bounds.lowerBound && $0.start < bounds.upperBound }
      .sorted { $0.start < $1.start }
    var byteCursor = bounds.lowerBound
    var segments: [CaptureSavedTemplateSegment] = []

    for span in relevant {
      let start = max(byteCursor, max(bounds.lowerBound, span.start))
      let end = min(bounds.upperBound, span.end)
      guard end > start,
        let range = stringRange(in: text, start: start, end: end)
      else { continue }

      if start > byteCursor,
        let plainRange = stringRange(in: text, start: byteCursor, end: start)
      {
        segments.append(
          CaptureSavedTemplateSegment(text: String(text[plainRange]), category: .neutral))
      }
      segments.append(
        CaptureSavedTemplateSegment(
          text: String(text[range]),
          category: captureSemanticCategory(forSpan: span)
        )
      )
      byteCursor = end
    }

    if byteCursor < bounds.upperBound,
      let range = stringRange(in: text, start: byteCursor, end: bounds.upperBound)
    {
      segments.append(CaptureSavedTemplateSegment(text: String(text[range]), category: .neutral))
    }
    return segments
  }

  private static func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}
