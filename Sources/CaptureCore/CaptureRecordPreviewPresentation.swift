import Foundation

/// Portable record-result wire types and presentation for Bob's committed
/// note preview and inline refusals.
///
/// Bob owns capture grammar, field order, validation, and note bytes
/// (`decisions:mac-capture-is-a-thin-client`). The Mac only decodes what
/// Bob returns and presents it. Every type here decodes tolerantly so
/// absent, null, malformed, or unknown optional metadata can never break
/// an otherwise usable legacy response; an unusable entry falls back to
/// the existing generic preview instead of an invented empty note.

/// One schema property on a planned record file (`note_files[]` entry or
/// per-item `record_note` summary). Canonical `value` and human `display`
/// stay separate; empty optional fields omit both.
public struct CaptureNoteFileProperty: Codable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let value: CaptureRecordValue?
    public let display: String?
    public let source: String?
    public let before: CaptureRecordValue?
    public let beforeDisplay: String?

    public init(
        key: String = "",
        label: String = "",
        value: CaptureRecordValue? = nil,
        display: String? = nil,
        source: String? = nil,
        before: CaptureRecordValue? = nil,
        beforeDisplay: String? = nil
    ) {
        self.key = key
        self.label = label
        self.value = value
        self.display = display
        self.source = source
        self.before = before
        self.beforeDisplay = beforeDisplay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? key
        value = (try? container.decodeIfPresent(CaptureRecordValue.self, forKey: .value)) ?? nil
        display = (try? container.decodeIfPresent(String.self, forKey: .display)) ?? nil
        source = (try? container.decodeIfPresent(String.self, forKey: .source)) ?? nil
        before =
            (try? container.decodeIfPresent(CaptureRecordValue.self, forKey: .before)) ?? nil
        beforeDisplay =
            (try? container.decodeIfPresent(String.self, forKey: .beforeDisplay)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case label
        case value
        case display
        case source
        case before
        case beforeDisplay = "before_display"
    }

    /// Human value for the property sheet. Bob's `display` wins; otherwise
    /// a readable canonical value. Meaningful zero/false values are kept;
    /// absent optional values stay nil.
    public var resolvedDisplay: String? {
        Self.resolvedDisplay(display: display, value: value)
    }

    /// Human value of the previous property, using the same display-then
    /// canonical fallback as `resolvedDisplay`.
    public var resolvedBeforeDisplay: String? {
        Self.resolvedDisplay(display: beforeDisplay, value: before)
    }

    /// True when the before display differs from the after display.
    public var displayChanged: Bool {
        (resolvedBeforeDisplay ?? "") != (resolvedDisplay ?? "")
    }

    /// True when Bob filled this value from the type default.
    public var isDefault: Bool {
        source == "default"
    }

    private static func resolvedDisplay(display: String?, value: CaptureRecordValue?) -> String? {
        if let display, !display.isEmpty {
            return display
        }
        if let value, let text = value.displayString, !text.isEmpty {
            return text
        }
        return nil
    }
}

/// One appended-note line on an updated record file.
public struct CaptureNoteFileLine: Codable, Equatable, Sendable {
    public let text: String
    public let depth: Int
    public let change: String?

    public init(text: String = "", depth: Int = 0, change: String? = nil) {
        self.text = text
        self.depth = depth
        self.change = change
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        depth = (try? container.decodeIfPresent(Int.self, forKey: .depth)) ?? 0
        change = (try? container.decodeIfPresent(String.self, forKey: .change)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case depth
        case change
    }
}

/// One planned record file in top-level `note_files`, in item order.
public struct CaptureNoteFile: Codable, Equatable, Sendable {
    public let path: String
    public let action: String
    public let recordType: String
    public let properties: [CaptureNoteFileProperty]
    public let body: String
    public let markdown: String
    /// Planned line diff. `nil` when older Bob omitted the key.
    public let lines: [CaptureNoteFileLine]?

    public init(
        path: String = "",
        action: String = "",
        recordType: String = "",
        properties: [CaptureNoteFileProperty] = [],
        body: String = "",
        markdown: String = "",
        lines: [CaptureNoteFileLine]? = nil
    ) {
        self.path = path
        self.action = action
        self.recordType = recordType
        self.properties = properties
        self.body = body
        self.markdown = markdown
        self.lines = lines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        action = (try? container.decodeIfPresent(String.self, forKey: .action)) ?? ""
        recordType =
            (try? container.decodeIfPresent(String.self, forKey: .recordType)) ?? ""
        properties =
            (try? container.decode(
                CaptureLossyArray<CaptureNoteFileProperty>.self,
                forKey: .properties
            ))?.values ?? []
        body = (try? container.decodeIfPresent(String.self, forKey: .body)) ?? ""
        markdown =
            (try? container.decodeIfPresent(String.self, forKey: .markdown)) ?? ""
        if container.contains(.lines) {
            lines =
                (try? container.decode(
                    CaptureLossyArray<CaptureNoteFileLine>.self,
                    forKey: .lines
                ))?.values
        } else {
            lines = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case action
        case recordType = "record_type"
        case properties
        case body
        case markdown
        case lines
    }

    /// True when Bob sent enough to render: a destination plus the exact
    /// Markdown. Otherwise the caller keeps the generic preview.
    public var isUsable: Bool {
        !path.isEmpty && !markdown.isEmpty
    }

    /// Properties whose before display differs from the after display.
    public var changedProperties: [CaptureNoteFileProperty] {
        properties.filter(\.displayChanged)
    }

    /// Planned body lines whose `change` is not `unchanged`. `nil` when
    /// older Bob omitted the `lines` key, so callers can fall back to
    /// today's body rendering instead of an invented empty diff.
    public var changedLines: [CaptureNoteFileLine]? {
        guard let lines else {
            return nil
        }
        return lines.filter { $0.change != "unchanged" }
    }
}

/// Committed metadata for one record item, without the full Markdown.
/// The exact bytes stay in the matching `note_files` entry.
public struct CaptureRecordNoteSummary: Codable, Equatable, Sendable {
    public let action: String
    public let label: String
    public let emoji: String?
    public let path: String
    public let notes: Int
    public let properties: [CaptureNoteFileProperty]

    public init(
        action: String = "",
        label: String = "",
        emoji: String? = nil,
        path: String = "",
        notes: Int = 0,
        properties: [CaptureNoteFileProperty] = []
    ) {
        self.action = action
        self.label = label
        self.emoji = emoji
        self.path = path
        self.notes = notes
        self.properties = properties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = (try? container.decodeIfPresent(String.self, forKey: .action)) ?? ""
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? ""
        emoji = (try? container.decodeIfPresent(String.self, forKey: .emoji)) ?? nil
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        notes = (try? container.decodeIfPresent(Int.self, forKey: .notes)) ?? 0
        properties =
            (try? container.decode(
                CaptureLossyArray<CaptureNoteFileProperty>.self,
                forKey: .properties
            ))?.values ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case label
        case emoji
        case path
        case notes
        case properties
    }
}

/// One invalid field on a record refusal.
public struct CaptureRecordInvalidField: Codable, Equatable, Sendable {
    public let field: String
    public let code: String?
    public let message: String

    public init(field: String = "", code: String? = nil, message: String = "") {
        self.field = field
        self.code = code
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        field = (try? container.decodeIfPresent(String.self, forKey: .field)) ?? ""
        code = (try? container.decodeIfPresent(String.self, forKey: .code)) ?? nil
        message =
            (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case field
        case code
        case message
    }
}

/// Structured record refusal payload. Missing-field refusals may carry no
/// `code`; the ready-to-copy `draft` can contain ellipses and choice
/// hints, so it is never applied silently.
public struct CaptureRecordRefusal: Equatable, Sendable {
    public let draft: String?
    public let missing: [String]
    public let invalid: [CaptureRecordInvalidField]

    public init(
        draft: String? = nil,
        missing: [String] = [],
        invalid: [CaptureRecordInvalidField] = []
    ) {
        self.draft = draft
        self.missing = missing
        self.invalid = invalid
    }

    /// True when Bob returned the structured ready-to-copy payload.
    public var hasStructuredPayload: Bool {
        draft != nil || !missing.isEmpty || !invalid.isEmpty
    }
}

/// Inline refusal derived from Bob's structured failure payload: the
/// error message, missing/invalid field details, and the selectable
/// ready-to-copy draft. Nil unless Bob returned the structured payload,
/// so unrelated failures and older Bob keep their existing presentation.
/// The draft can contain ellipses and choice hints and is never applied
/// silently; the user keeps the entire original draft.
public struct CaptureRecordRefusalPresentation: Equatable, Sendable {
    public let message: TaskDisplayText
    public let missing: [String]
    public let invalid: [CaptureRecordInvalidField]
    public let draft: String?
    public let fieldLabels: [String: String]
    public let accessibilitySummary: String

    public init?(failure: CaptureCommandFailure, fieldLabels: [String: String] = [:]) {
        guard let refusal = failure.recordRefusal else {
            return nil
        }
        message = TaskDisplayText(parsing: failure.error)
        missing = refusal.missing
        invalid = refusal.invalid
        draft = refusal.draft
        self.fieldLabels = fieldLabels
        var parts = [message.text]
        if !missing.isEmpty {
            let names = missing.map { fieldLabels[$0] ?? $0 }
            parts.append("Missing: \(names.joined(separator: ", "))")
        }
        for row in invalid {
            let label = fieldLabels[row.field] ?? row.field
            parts.append("\(label): \(row.message)")
        }
        accessibilitySummary = parts.joined(separator: ". ")
    }

    /// Human label for a refused field key, from the live parse when known.
    public func displayLabel(for key: String) -> String {
        fieldLabels[key] ?? key
    }
}

/// Portable derivation of the committed success line and property detail
/// from Bob's per-item `record_note` object. Panel status, accessibility,
/// and notifications share this so the copy stays identical.
public enum CaptureRecordPreviewPresentation {
    /// Headline such as "🍽️ new restaurant  eat/ramen_nagi.md".
    /// Built from Bob's emoji/label/path, never the cleared editor.
    public static func headline(for summary: CaptureRecordNoteSummary) -> String {
        let kind = summary.label.lowercased()
        let verb = summary.action == "update" ? "updated" : "new"
        let name = kind.isEmpty ? verb : "\(verb) \(kind)"
        if let emoji = summary.emoji, !emoji.isEmpty {
            return "\(emoji) \(name)  \(summary.path)"
        }
        return "\(name)  \(summary.path)"
    }

    /// Detail from Bob's ordered nonempty property displays plus the note
    /// count, such as "💚 Liked · Ramen · Clark · with Kelly · 1 note".
    /// The `companions` list reads as "with …"; every other configured
    /// field stays generic so new types need no client change.
    public static func detail(for summary: CaptureRecordNoteSummary) -> String {
        var parts: [String] = []
        for property in summary.properties {
            guard let display = property.resolvedDisplay else {
                continue
            }
            if property.key == "companions" {
                parts.append("with \(display)")
            } else {
                parts.append(display)
            }
        }
        parts.append(noteCountText(summary.notes))
        return parts.joined(separator: " · ")
    }

    /// Pairs each normalized record item with its `note_files` entry.
    /// Matching follows Bob's path/action identity in item order and
    /// consumes each file once, so multiple operations on the same path
    /// never collapse onto the first file.
    public static func pair(
        files: [CaptureNoteFile],
        items: [CaptureCommandSuccess]
    ) -> [(item: CaptureCommandSuccess, file: CaptureNoteFile)] {
        var remaining = files
        var pairs: [(item: CaptureCommandSuccess, file: CaptureNoteFile)] = []
        for item in items {
            guard item.kind == "record_note" || item.kind == "record_update" else {
                continue
            }
            let action: String
            if let summaryAction = item.recordNote?.action, !summaryAction.isEmpty {
                action = summaryAction
            } else if item.kind == "record_update" {
                action = "update"
            } else {
                action = "create"
            }
            guard
                let index = remaining.firstIndex(where: {
                    $0.path == item.relativeTarget && $0.action == action
                })
            else {
                continue
            }
            pairs.append((item: item, file: remaining.remove(at: index)))
        }
        return pairs
    }

    /// Notification title for one committed record, mirroring the panel
    /// headline so both surfaces read identically.
    public static func notificationTitle(for summary: CaptureRecordNoteSummary) -> String {
        headline(for: summary)
    }

    /// Notification body for one committed record: the same detail line
    /// the panel status shows.
    public static func notificationBody(for summary: CaptureRecordNoteSummary) -> String {
        detail(for: summary)
    }

    /// One batch notification line per committed record, used for mixed
    /// batches so each record appears exactly once.
    public static func recordBatchLine(for summary: CaptureRecordNoteSummary) -> String {
        "\(headline(for: summary)) · \(detail(for: summary))"
    }

    /// Index-keyed variant of `pair(files:items:)` for view stacks that
    /// iterate normalized captures by offset.
    public static func pairIndexed(
        files: [CaptureNoteFile],
        items: [CaptureCommandSuccess]
    ) -> [Int: CaptureNoteFile] {
        var remaining = files
        var map: [Int: CaptureNoteFile] = [:]
        for (index, item) in items.enumerated() {
            guard item.kind == "record_note" || item.kind == "record_update" else {
                continue
            }
            let action: String
            if let summaryAction = item.recordNote?.action, !summaryAction.isEmpty {
                action = summaryAction
            } else if item.kind == "record_update" {
                action = "update"
            } else {
                action = "create"
            }
            guard
                let fileIndex = remaining.firstIndex(where: {
                    $0.path == item.relativeTarget && $0.action == action
                })
            else {
                continue
            }
            map[index] = remaining.remove(at: fileIndex)
        }
        return map
    }

    /// "no notes", "1 note", or "N notes".
    public static func noteCountText(_ count: Int) -> String {
        switch count {
        case 0:
            return "no notes"
        case 1:
            return "1 note"
        default:
            return "\(count) notes"
        }
    }

    /// Changed lines for the Record Card's live update section. Nil unless
    /// the ready preview belongs to this draft, the paired file is an
    /// update for `path`, and at least one line changed. Loading, stale,
    /// or empty diffs omit the section so old data never flashes.
    public static func liveUpdateChangedLines(
        path: String?,
        previewDraft: String?,
        plainDraft: String,
        isPreviewing: Bool,
        preview: CaptureCommandSuccess?
    ) -> [CaptureNoteFileLine]? {
        guard !isPreviewing,
            let path, !path.isEmpty,
            let previewDraft, previewDraft == plainDraft,
            let preview
        else {
            return nil
        }
        let paired = pair(files: preview.noteFiles, items: preview.normalizedCaptures)
            .first { $0.file.path == path && $0.file.action == "update" }?
            .file
        let file =
            paired
            ?? preview.noteFiles.first { $0.path == path && $0.action == "update" }
        guard let file, let lines = file.changedLines, !lines.isEmpty else {
            return nil
        }
        return lines
    }
}
