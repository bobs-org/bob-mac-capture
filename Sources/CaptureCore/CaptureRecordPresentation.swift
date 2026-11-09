import Foundation

/// Portable Record Card wire types and presentation for Bob's record notes.
///
/// Bob owns capture grammar, field order, validation, insertion points, and
/// replacement bytes (`decisions:mac-capture-is-a-thin-client`). The Mac only
/// decodes what Bob returns and presents it. Every field here decodes
/// tolerantly so missing or malformed additive metadata can never break an
/// otherwise usable ordinary response, and unknown states/kinds stay readable
/// and neutral. Schema-version rejection is unchanged.

/// One `value`/`label` choice Bob offers for a choice-kind record field.
public struct CaptureRecordChoice: Codable, Equatable, Sendable {
    public let value: String
    public let label: String

    public init(value: String = "", label: String = "") {
        self.value = value
        self.label = label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = (try? container.decodeIfPresent(String.self, forKey: .value)) ?? ""
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? value
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case label
    }
}

/// Typed field value Bob reports. Preserves numbers, strings, lists, null,
/// and meaningful false/zero values; never forced into a string dictionary.
public enum CaptureRecordValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case list([CaptureRecordValue])
    case null

    public var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    public var displayString: String? {
        switch self {
        case .string(let text):
            return text
        case .number(let number):
            if number.truncatingRemainder(dividingBy: 1) == 0 {
                return String(Int(number))
            }
            return String(number)
        case .bool(let flag):
            return flag ? "true" : "false"
        case .list(let items):
            let parts = items.compactMap(\.displayString)
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        case .null:
            return nil
        }
    }
}

extension CaptureRecordValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
            return
        }
        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }
        if let text = try? container.decode(String.self) {
            self = .string(text)
            return
        }
        if let items = try? container.decode([CaptureRecordValue].self) {
            self = .list(items)
            return
        }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text):
            try container.encode(text)
        case .number(let number):
            try container.encode(number)
        case .bool(let flag):
            try container.encode(flag)
        case .list(let items):
            try container.encode(items)
        case .null:
            try container.encodeNil()
        }
    }
}

/// One declared record field from `capture-parse`.
/// Update items carry Bob's snapshot `before`/`before_display` alongside
/// the planned `value`/`display`; create items omit them.
public struct CaptureRecordField: Codable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let kind: String
    public let required: Bool
    public let list: Bool
    public let state: String
    public let value: CaptureRecordValue?
    public let display: String?
    public let before: CaptureRecordValue?
    public let beforeDisplay: String?
    public let source: String?
    public let range: CaptureRange?
    public let valueRanges: [CaptureRange]
    public let choices: [CaptureRecordChoice]

    public init(
        key: String = "",
        label: String = "",
        kind: String = "",
        required: Bool = false,
        list: Bool = false,
        state: String = "",
        value: CaptureRecordValue? = nil,
        display: String? = nil,
        before: CaptureRecordValue? = nil,
        beforeDisplay: String? = nil,
        source: String? = nil,
        range: CaptureRange? = nil,
        valueRanges: [CaptureRange] = [],
        choices: [CaptureRecordChoice] = []
    ) {
        self.key = key
        self.label = label
        self.kind = kind
        self.required = required
        self.list = list
        self.state = state
        self.value = value
        self.display = display
        self.before = before
        self.beforeDisplay = beforeDisplay
        self.source = source
        self.range = range
        self.valueRanges = valueRanges
        self.choices = choices
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? key
        kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        required = (try? container.decodeIfPresent(Bool.self, forKey: .required)) ?? false
        list = (try? container.decodeIfPresent(Bool.self, forKey: .list)) ?? false
        state = (try? container.decodeIfPresent(String.self, forKey: .state)) ?? ""
        value = (try? container.decodeIfPresent(CaptureRecordValue.self, forKey: .value)) ?? nil
        display = (try? container.decodeIfPresent(String.self, forKey: .display)) ?? nil
        before =
            (try? container.decodeIfPresent(CaptureRecordValue.self, forKey: .before)) ?? nil
        beforeDisplay =
            (try? container.decodeIfPresent(String.self, forKey: .beforeDisplay)) ?? nil
        source = (try? container.decodeIfPresent(String.self, forKey: .source)) ?? nil
        range = (try? container.decodeIfPresent(CaptureRange.self, forKey: .range)) ?? nil
        valueRanges =
            (try? container.decodeIfPresent([CaptureRange].self, forKey: .valueRanges)) ?? []
        choices =
            (try? container.decodeIfPresent([CaptureRecordChoice].self, forKey: .choices)) ?? []
    }

    /// True for `set`, `default`, `missing`, and `invalid` display states.
    public var isVisibleRow: Bool {
        if required { return true }
        return state != "none"
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case label
        case kind
        case required
        case list
        case state
        case value
        case display
        case before
        case beforeDisplay = "before_display"
        case source
        case range
        case valueRanges = "value_ranges"
        case choices
    }

    /// Resolved current value for an update row. Bob's `before_display`
    /// wins; otherwise the canonical value. Nil when Bob sent neither.
    public var resolvedBeforeDisplay: String? {
        if let beforeDisplay, !beforeDisplay.isEmpty {
            return beforeDisplay
        }
        if let before, let text = before.displayString, !text.isEmpty {
            return text
        }
        return nil
    }
}

/// Record creation metadata from `capture-parse` (top-level and per-item).
public struct CaptureRecord: Codable, Equatable, Sendable {
    public let action: String
    public let recordType: String
    public let label: String
    public let emoji: String?
    public let dir: String
    public let path: String?
    public let stem: String?
    public let stemSource: String?
    public let title: String
    public let missing: [String]
    public let notes: Int
    public let fields: [CaptureRecordField]
    public let assistVersion: Int?

    public init(
        action: String = "",
        recordType: String = "",
        label: String = "",
        emoji: String? = nil,
        dir: String = "",
        path: String? = nil,
        stem: String? = nil,
        stemSource: String? = nil,
        title: String = "",
        missing: [String] = [],
        notes: Int = 0,
        fields: [CaptureRecordField] = [],
        assistVersion: Int? = nil
    ) {
        self.action = action
        self.recordType = recordType
        self.label = label
        self.emoji = emoji
        self.dir = dir
        self.path = path
        self.stem = stem
        self.stemSource = stemSource
        self.title = title
        self.missing = missing
        self.notes = notes
        self.fields = fields
        self.assistVersion = assistVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = (try? container.decodeIfPresent(String.self, forKey: .action)) ?? ""
        recordType = (try? container.decodeIfPresent(String.self, forKey: .recordType)) ?? ""
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? ""
        emoji = (try? container.decodeIfPresent(String.self, forKey: .emoji)) ?? nil
        dir = (try? container.decodeIfPresent(String.self, forKey: .dir)) ?? ""
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? nil
        stem = (try? container.decodeIfPresent(String.self, forKey: .stem)) ?? nil
        stemSource = (try? container.decodeIfPresent(String.self, forKey: .stemSource)) ?? nil
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        missing = (try? container.decodeIfPresent([String].self, forKey: .missing)) ?? []
        notes = (try? container.decodeIfPresent(Int.self, forKey: .notes)) ?? 0
        fields =
            (try? container.decodeIfPresent([CaptureRecordField].self, forKey: .fields)) ?? []
        assistVersion = (try? container.decodeIfPresent(Int.self, forKey: .assistVersion)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case recordType = "type"
        case label
        case emoji
        case dir
        case path
        case stem
        case stemSource = "stem_source"
        case title
        case missing
        case notes
        case fields
        case assistVersion = "assist_version"
    }
}

/// Follow-up request Bob authors on an accepted record candidate.
/// Distinct from the generic picker `continuation` string.
public struct CaptureRecordContinuation: Codable, Equatable, Sendable {
    public let cursor: Int
    public let nextMissingField: Bool

    public init(cursor: Int = 0, nextMissingField: Bool = false) {
        self.cursor = cursor
        self.nextMissingField = nextMissingField
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = (try? container.decodeIfPresent(Int.self, forKey: .cursor)) ?? 0
        nextMissingField =
            (try? container.decodeIfPresent(Bool.self, forKey: .nextMissingField)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case cursor
        case nextMissingField = "next_missing_field"
    }
}

/// Explicit "edit in draft" action Bob authors on a named-field request.
/// Never auto-advances; its continuation is ordinary value completion.
public struct CaptureRecordEdit: Codable, Equatable, Sendable {
    public let replacementRange: CaptureRange
    public let replacement: String
    public let cursorAfter: Int
    public let continuation: CaptureRecordContinuation

    public init(
        replacementRange: CaptureRange = CaptureRange(start: 0, end: 0),
        replacement: String = "",
        cursorAfter: Int = 0,
        continuation: CaptureRecordContinuation = CaptureRecordContinuation()
    ) {
        self.replacementRange = replacementRange
        self.replacement = replacement
        self.cursorAfter = cursorAfter
        self.continuation = continuation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        replacementRange =
            (try? container.decodeIfPresent(CaptureRange.self, forKey: .replacementRange))
            ?? CaptureRange(start: 0, end: 0)
        replacement = (try? container.decodeIfPresent(String.self, forKey: .replacement)) ?? ""
        cursorAfter = (try? container.decodeIfPresent(Int.self, forKey: .cursorAfter)) ?? 0
        continuation =
            (try? container.decodeIfPresent(
                CaptureRecordContinuation.self,
                forKey: .continuation
            )) ?? CaptureRecordContinuation()
    }

    private enum CodingKeys: String, CodingKey {
        case replacementRange = "replacement_range"
        case replacement
        case cursorAfter = "cursor_after"
        case continuation
    }
}

/// Record metadata Bob attaches to `record_field`/`record_value` completion.
public struct CaptureRecordCompletionMeta: Codable, Equatable, Sendable {
    public let recordType: String
    public let dir: String
    public let label: String
    public let emoji: String?
    public let field: String?
    public let title: String?
    public let assistVersion: Int?
    public let edit: CaptureRecordEdit?

    public init(
        recordType: String = "",
        dir: String = "",
        label: String = "",
        emoji: String? = nil,
        field: String? = nil,
        title: String? = nil,
        assistVersion: Int? = nil,
        edit: CaptureRecordEdit? = nil
    ) {
        self.recordType = recordType
        self.dir = dir
        self.label = label
        self.emoji = emoji
        self.field = field
        self.title = title
        self.assistVersion = assistVersion
        self.edit = edit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordType = (try? container.decodeIfPresent(String.self, forKey: .recordType)) ?? ""
        dir = (try? container.decodeIfPresent(String.self, forKey: .dir)) ?? ""
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? ""
        emoji = (try? container.decodeIfPresent(String.self, forKey: .emoji)) ?? nil
        field = (try? container.decodeIfPresent(String.self, forKey: .field)) ?? nil
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil
        assistVersion = (try? container.decodeIfPresent(Int.self, forKey: .assistVersion)) ?? nil
        edit = (try? container.decodeIfPresent(CaptureRecordEdit.self, forKey: .edit)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case recordType = "type"
        case dir
        case label
        case emoji
        case field
        case title
        case assistVersion = "assist_version"
        case edit
    }
}

// MARK: - Portable Record Card presentation and focus reducer

/// One projected card row in Bob's schema order.
/// Update rows keep Bob's snapshot `beforeDisplay` so the card can show
/// `before → after` for changed fields and the current value otherwise.
public struct CaptureRecordRow: Equatable, Sendable {
    public let key: String
    public let label: String
    public let kind: String
    public let required: Bool
    public let list: Bool
    public let state: String
    public let display: String?
    public let beforeDisplay: String?
    public let source: String?
    public let choices: [CaptureRecordChoice]

    public init(field: CaptureRecordField) {
        key = field.key
        label = field.label
        kind = field.kind
        required = field.required
        list = field.list
        state = field.state
        display = field.display
        beforeDisplay = field.resolvedBeforeDisplay
        source = field.source
        choices = field.choices
    }

    public init(
        key: String,
        label: String,
        kind: String = "",
        required: Bool = false,
        list: Bool = false,
        state: String = "",
        display: String? = nil,
        beforeDisplay: String? = nil,
        source: String? = nil,
        choices: [CaptureRecordChoice] = []
    ) {
        self.key = key
        self.label = label
        self.kind = kind
        self.required = required
        self.list = list
        self.state = state
        self.display = display
        self.beforeDisplay = beforeDisplay
        self.source = source
        self.choices = choices
    }

    /// True when Bob sent both sides and they differ. Unchanged update
    /// rows and create rows keep the single-value presentation.
    public var isChanged: Bool {
        guard let before = beforeDisplay, !before.isEmpty,
            let after = display, !after.isEmpty
        else {
            return false
        }
        return before != after
    }

    /// `before → after` for changed rows, else the single display value.
    public var changeText: String? {
        if isChanged {
            return "\(beforeDisplay ?? "") → \(display ?? "")"
        }
        return display
    }

    public var stateLabel: String {
        switch state {
        case "set": return "set"
        case "default": return "default"
        case "missing": return "missing"
        case "invalid": return "invalid"
        default: return "none"
        }
    }

    public var isOptionalHidden: Bool {
        !required && state == "none"
    }

    /// VoiceOver identity, for example `Status, required, missing` or
    /// `Status, Liked to Not liked`. State is never color alone.
    public var accessibilityLabel: String {
        let requirement = required ? "required" : "optional"
        if isChanged {
            return "\(label), \(beforeDisplay ?? "") to \(display ?? "")"
        }
        if let display, !display.isEmpty {
            return "\(label), \(display), \(requirement), \(stateLabel)"
        }
        return "\(label), \(requirement), \(stateLabel)"
    }

    /// SF Symbol for the persistent state mark. Color is supplemental.
    public var stateSymbolName: String {
        switch state {
        case "set":
            return "checkmark.circle.fill"
        case "default":
            return "checkmark.circle"
        case "missing":
            return required ? "circle.inset.filled" : "circle"
        case "invalid":
            return "exclamationmark.circle.fill"
        default:
            return "circle.dashed"
        }
    }
}

/// Portable card state derived from Bob's parse. Schema order is preserved;
/// validity is never judged locally.
public struct CaptureRecordPresentation: Equatable, Sendable {
    public let record: CaptureRecord
    public let itemIndex: Int?
    public let rows: [CaptureRecordRow]
    public let activeFieldKey: String?
    public let selectedRowKey: String?
    public let showsMore: Bool

    public init(
        record: CaptureRecord,
        itemIndex: Int? = nil,
        rows: [CaptureRecordRow]? = nil,
        activeFieldKey: String? = nil,
        selectedRowKey: String? = nil,
        showsMore: Bool = false
    ) {
        self.record = record
        self.itemIndex = itemIndex
        let projected = rows ?? record.fields.map(CaptureRecordRow.init(field:))
        self.rows = projected
        self.activeFieldKey = activeFieldKey
        self.selectedRowKey = selectedRowKey
        self.showsMore = showsMore
    }

    /// Selects the caret's parsed item; falls back to the top-level record
    /// only when item data is absent. Never scans capture syntax.
    public static func make(
        parse: CaptureParseResponse,
        cursor: Int,
        showsMore: Bool = false,
        selectedRowKey: String? = nil
    ) -> CaptureRecordPresentation? {
        if parse.items.isEmpty {
            guard let record = parse.record else { return nil }
            let rows = record.fields.map(CaptureRecordRow.init(field:))
            let active = activeField(for: record, cursorFieldKey: nil)
            return CaptureRecordPresentation(
                record: record,
                itemIndex: nil,
                rows: rows,
                activeFieldKey: active,
                selectedRowKey: selectedRowKey,
                showsMore: showsMore
            )
        }
        guard let item = itemContaining(cursor: cursor, in: parse.items) else {
            return nil
        }
        guard let record = item.record else { return nil }
        let rows = record.fields.map(CaptureRecordRow.init(field:))
        let cursorKey = fieldKeyContaining(cursor: cursor, fields: record.fields)
        let active = activeField(for: record, cursorFieldKey: cursorKey)
        let index = parse.items.firstIndex(where: { $0.index == item.index })
        return CaptureRecordPresentation(
            record: record,
            itemIndex: index,
            rows: rows,
            activeFieldKey: active,
            selectedRowKey: selectedRowKey ?? cursorKey ?? active,
            showsMore: showsMore
        )
    }

    private static func itemContaining(
        cursor: Int,
        in items: [CaptureParseItem]
    ) -> CaptureParseItem? {
        for item in items {
            if cursor >= item.range.start && cursor <= item.range.end {
                return item
            }
        }
        return nil
    }

    private static func fieldKeyContaining(
        cursor: Int,
        fields: [CaptureRecordField]
    ) -> String? {
        for field in fields {
            if let range = field.range, cursor >= range.start && cursor <= range.end {
                return field.key
            }
            for valueRange in field.valueRanges
            where cursor >= valueRange.start && cursor <= valueRange.end {
                return field.key
            }
        }
        return nil
    }

    private static func activeField(
        for record: CaptureRecord,
        cursorFieldKey: String?
    ) -> String? {
        if let cursorFieldKey { return cursorFieldKey }
        return record.missing.first
    }

    /// Required, set, default, invalid, and missing rows stay visible.
    /// Unset optional (`none`) rows hide under More.
    public var visibleRows: [CaptureRecordRow] {
        rows.filter { !$0.isOptionalHidden }
    }

    public var hiddenOptionalRows: [CaptureRecordRow] {
        rows.filter(\.isOptionalHidden)
    }

    public var displayedRows: [CaptureRecordRow] {
        showsMore ? rows : visibleRows
    }

    /// First missing field key in schema order, if any.
    public var firstMissingFieldKey: String? {
        record.missing.first
    }

    /// Intent for plain Tab with no open list: first missing field, if any.
    public var tabIntent: CaptureRecordIntent? {
        guard let key = firstMissingFieldKey else { return nil }
        return .requestField(key: key, nextMissing: true)
    }

    /// Intent for Return with no open list: submit when complete, else first
    /// missing field with a human "Needs <label>" hint.
    public var returnIntent: CaptureRecordIntent {
        if record.missing.isEmpty {
            return .submit
        }
        let key = record.missing[0]
        let label = rows.first(where: { $0.key == key })?.label ?? key
        return .requestField(key: key, nextMissing: false, needsLabel: label)
    }

    /// Named-field intent for Shift-Tab backward navigation.
    public func shiftTabIntent(from key: String) -> CaptureRecordIntent? {
        let order = record.missing
        guard let position = order.firstIndex(of: key), position > 0 else {
            return nil
        }
        return .requestField(key: order[position - 1], nextMissing: false)
    }

    /// Header title from Bob's action and label. Never invents a filename.
    public var headerTitle: String {
        let label = record.label.isEmpty ? "record" : record.label
        if record.action == "create" {
            return "New \(label.lowercased())"
        }
        return label
    }

    /// Bob's path when known. Empty when Bob omitted it; never derived.
    public var headerPath: String? {
        guard let path = record.path, !path.isEmpty else {
            return nil
        }
        return path
    }

    /// True for `@dir/stem` updates. Bob's `notes` counts the new dated
    /// notes this draft appends.
    public var isUpdate: Bool {
        record.action == "update"
    }

    /// Changed rows in schema order. Unchanged update rows keep their
    /// single-value presentation.
    public var changedRows: [CaptureRecordRow] {
        rows.filter(\.isChanged)
    }

    public var notesLabel: String {
        if isUpdate {
            switch record.notes {
            case 0:
                return "no new notes"
            case 1:
                return "+1 note"
            default:
                return "+\(record.notes) notes"
            }
        }
        return record.notes == 1 ? "1 note" : "\(record.notes) notes"
    }

    /// More disclosure, listing hidden optional keys.
    public var moreLabel: String {
        let keys = hiddenOptionalRows.map(\.key)
        if keys.isEmpty {
            return "More"
        }
        return "More (\(keys.joined(separator: ", ")))"
    }

    /// Footer copy from Bob's missing-field order and readiness. A caller
    /// may replace this with Bob's diagnostic or status text.
    public var footerHint: String {
        if let key = firstMissingFieldKey {
            let label = rows.first(where: { $0.key == key })?.label ?? key
            return "⇥ next field · ⏎ Needs \(label) · Esc back to draft"
        }
        let action = record.action == "create" ? "create" : "accept"
        return "⇥ next field · ⏎ \(action) · Esc back to draft"
    }

    /// Record whose item range contains `span`. Falls back to the top-level
    /// record only when item data is absent. Never uses the first record
    /// globally when items exist.
    public static func record(
        matching span: CaptureSpan,
        in parse: CaptureParseResponse
    ) -> CaptureRecord? {
        if !parse.items.isEmpty {
            return parse.items.first { item in
                span.start >= item.range.start && span.start <= item.range.end
            }?.record
        }
        return parse.record
    }

    /// Field Bob associated with this span, by `key` or by range overlap.
    public static func field(
        matching span: CaptureSpan,
        in record: CaptureRecord
    ) -> CaptureRecordField? {
        if let key = span.key, !key.isEmpty {
            return record.fields.first { $0.key == key }
        }
        return record.fields.first { field in
            if let range = field.range, span.start >= range.start, span.end <= range.end {
                return true
            }
            return field.valueRanges.contains {
                span.start >= $0.start && span.end <= $0.end
            }
        }
    }
}

/// Card intent without invented text: every field request names a
/// server-provided missing key.
public enum CaptureRecordIntent: Equatable, Sendable {
    case requestField(key: String, nextMissing: Bool, needsLabel: String? = nil)
    case submit
}

/// Focus retained by item and field key across a same-draft refresh.
/// Stale generations and sequences are rejected so an older reply can never
/// steal focus or reopen a dismissed list.
public struct CaptureRecordFocusState: Equatable, Sendable {
    public let draft: String
    public let generation: UInt64
    public let sequence: UInt64
    public let clientIdentity: String
    public let itemIndex: Int?
    public let fieldKey: String?
    public let showsMore: Bool
    public let selectedRowKey: String?

    public init(
        draft: String = "",
        generation: UInt64 = 0,
        sequence: UInt64 = 0,
        clientIdentity: String = "",
        itemIndex: Int? = nil,
        fieldKey: String? = nil,
        showsMore: Bool = false,
        selectedRowKey: String? = nil
    ) {
        self.draft = draft
        self.generation = generation
        self.sequence = sequence
        self.clientIdentity = clientIdentity
        self.itemIndex = itemIndex
        self.fieldKey = fieldKey
        self.showsMore = showsMore
        self.selectedRowKey = selectedRowKey
    }

    /// Whether an incoming response may update this state. Rejects older
    /// generations, older sequences, and other process clients. Item switches
    /// are accepted; they re-key focus rather than sharing field state.
    public func accepts(
        draft: String,
        generation: UInt64,
        sequence: UInt64,
        clientIdentity: String
    ) -> Bool {
        guard clientIdentity == self.clientIdentity else { return false }
        if generation != self.generation {
            return generation > self.generation && draft != self.draft
                ? true : generation > self.generation
        }
        if draft != self.draft { return false }
        return sequence >= self.sequence
    }

    /// Refreshes focus for the same draft: keeps the field key when the field
    /// still exists, otherwise falls to the presentation's active field.
    /// Field removal clears the retained key rather than pointing at a gone
    /// row. Item switches re-key by item identity.
    public func refreshed(
        with presentation: CaptureRecordPresentation?,
        draft: String,
        generation: UInt64,
        sequence: UInt64,
        clientIdentity: String
    ) -> CaptureRecordFocusState? {
        guard let presentation else { return nil }
        guard
            accepts(
                draft: draft,
                generation: generation,
                sequence: sequence,
                clientIdentity: clientIdentity
            )
        else { return nil }
        let sameItem = itemIndex == presentation.itemIndex
        let sameDraft = draft == self.draft
        let stillExists = sameItem && sameDraft
            && presentation.rows.contains(where: { $0.key == fieldKey })
        let nextKey: String? =
            if let fieldKey, stillExists {
                fieldKey
            } else {
                presentation.activeFieldKey
            }
        let nextSelected: String? =
            if sameItem, sameDraft, let selectedRowKey,
                presentation.rows.contains(where: { $0.key == selectedRowKey })
            {
                selectedRowKey
            } else {
                nextKey
            }
        // Keep the disclosure state with this item; a different item starts
        // from its presentation default even when it shares the record type.
        return CaptureRecordFocusState(
            draft: draft,
            generation: generation,
            sequence: sequence,
            clientIdentity: clientIdentity,
            itemIndex: presentation.itemIndex,
            fieldKey: nextKey,
            showsMore: sameItem && sameDraft ? showsMore : presentation.showsMore,
            selectedRowKey: nextSelected
        )
    }
}

// MARK: - Cached route-completion preservation

public enum CaptureRecordRouteCache {
    /// Insertion text for a cached target. Record rows keep Bob's trailing
    /// space; ordinary rows keep the bare route so a cache never turns a
    /// record row into an ordinary note row.
    public static func insertion(for target: CaptureTarget) -> String {
        if target.kind == "record" {
            return target.route + " "
        }
        return target.route
    }

    /// Bob's route-menu label for a cached record target. Ordinary rows keep
    /// their target label.
    public static func label(for target: CaptureTarget) -> String {
        guard target.kind == "record" else {
            return target.label
        }
        let base = target.label.lowercased()
        let count = target.count ?? 0
        if let emoji = target.emoji, !emoji.isEmpty {
            return "\(emoji) New \(base) · \(count)"
        }
        return "New \(base) · \(count)"
    }

    /// Follow-up request for a cached record row. Ordinary rows have none.
    public static func continuation(
        for target: CaptureTarget,
        replacementStart: Int
    ) -> CaptureRecordContinuation? {
        guard target.kind == "record" else {
            return nil
        }
        let insertion = insertion(for: target)
        return CaptureRecordContinuation(
            cursor: replacementStart + insertion.utf8.count,
            nextMissingField: true
        )
    }
}

// MARK: - Completion surface and editor route adornments

/// Where a current record completion may be accepted. Card value/field
/// lists render on the Record Card; every other current record context
/// (especially `record_target`) uses the generic completion list so Tab
/// cannot silently accept a hidden existing-record row.
public enum CaptureRecordCompletionSurface: Equatable, Sendable {
    case none
    case cardValue
    case cardField
    case genericFallback

    public static func make(
        context: String?,
        candidateCount: Int,
        snapshotCurrent: Bool,
        isRecordCompletion: Bool
    ) -> CaptureRecordCompletionSurface {
        guard snapshotCurrent, candidateCount > 0, isRecordCompletion else {
            return .none
        }
        switch context {
        case "record_value":
            return .cardValue
        case "record_field":
            return .cardField
        default:
            return .genericFallback
        }
    }

    public var listVisibleOnCard: Bool {
        self == .cardValue || self == .cardField
    }

    public var showsGenericFallback: Bool {
        self == .genericFallback
    }
}

/// Ordinary panel status that must not replace the Record Card footer hint
/// or paint as a refusal. Bob diagnostics and other nonempty status stay
/// blocking.
public enum CaptureRecordFooterMessage: Equatable, Sendable {
    public static func isOrdinaryStatus(_ text: String) -> Bool {
        if text.isEmpty { return true }
        if text == "Ready" { return true }
        if text == "Target cache stale" { return true }
        if text.hasSuffix("\u{2026}") { return true }
        return false
    }

    public static func isSupersedable(_ text: String) -> Bool {
        if isOrdinaryStatus(text) { return true }
        if text.hasPrefix("Needs ") { return true }
        if text.hasSuffix(" is stale") { return true }
        return false
    }

    public static func copy(
        statusText: String,
        errorDiagnostic: String?,
        footerHint: String
    ) -> (text: String, isRefusal: Bool) {
        if !isOrdinaryStatus(statusText) {
            return (statusText, true)
        }
        if let errorDiagnostic {
            return (errorDiagnostic, true)
        }
        return (footerHint, false)
    }
}

/// Presentation-only type emoji for a `record_route` span. Never inserted
/// into the draft; the editor overlays it at the route-start glyph.
public struct CaptureRecordRouteAdornment: Equatable, Sendable, Identifiable {
    public let start: Int
    public let end: Int
    public let emoji: String

    public var id: Int { start }

    public init(start: Int, end: Int, emoji: String) {
        self.start = start
        self.end = end
        self.emoji = emoji
    }

    /// One adornment per `record_route` whose owning item reports an emoji.
    /// Absent metadata yields no overlay. Two record types in one draft
    /// yield two adornments.
    public static func all(in parse: CaptureParseResponse) -> [CaptureRecordRouteAdornment] {
        parse.spans.compactMap { span in
            guard span.kind == "record_route" else {
                return nil
            }
            guard let emoji = CaptureRecordPresentation.record(matching: span, in: parse)?.emoji,
                !emoji.isEmpty
            else {
                return nil
            }
            return CaptureRecordRouteAdornment(start: span.start, end: span.end, emoji: emoji)
        }
    }
}

/// Wrapping monospace (line, column) for a UTF-8 byte offset, used to
/// place route-emoji overlays without mutating the draft.
public struct CaptureMonospaceGlyphOrigin: Equatable, Sendable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    /// Walks whole characters so a mid-character offset returns nil.
    public static func wrappingOrigin(
        utf8Offset: Int,
        in draft: String,
        charsPerLine: Int
    ) -> CaptureMonospaceGlyphOrigin? {
        guard utf8Offset >= 0, charsPerLine > 0 else {
            return nil
        }
        var remaining = utf8Offset
        var line = 0
        var column = 0
        var index = draft.startIndex
        while remaining > 0, index < draft.endIndex {
            let character = draft[index]
            let width = String(character).utf8.count
            guard width <= remaining else {
                return nil
            }
            remaining -= width
            if character == "\n" {
                line += 1
                column = 0
            } else {
                column += 1
                if column >= charsPerLine {
                    line += 1
                    column = 0
                }
            }
            index = draft.index(after: index)
        }
        return remaining == 0 ? CaptureMonospaceGlyphOrigin(line: line, column: column) : nil
    }
}
