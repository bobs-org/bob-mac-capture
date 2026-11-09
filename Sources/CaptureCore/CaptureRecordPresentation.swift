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
public struct CaptureRecordField: Codable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let kind: String
    public let required: Bool
    public let list: Bool
    public let state: String
    public let value: CaptureRecordValue?
    public let display: String?
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
        case source
        case range
        case valueRanges = "value_ranges"
        case choices
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
public struct CaptureRecordRow: Equatable, Sendable {
    public let key: String
    public let label: String
    public let kind: String
    public let required: Bool
    public let list: Bool
    public let state: String
    public let display: String?
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
        self.source = source
        self.choices = choices
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
