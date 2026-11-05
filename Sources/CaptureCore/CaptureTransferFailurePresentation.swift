import Foundation

/// Bob's read-only context for a transfer whose destination is still being typed.
/// Older Bob versions omit this additive failure payload.
public struct CaptureTransferPending: Codable, Equatable, Sendable {
    public let item: Int
    public let need: String
    public let sources: [CaptureTransferPendingSource]
    public let forms: [CaptureTransferPendingForm]

    public init(
        item: Int = 0,
        need: String = "",
        sources: [CaptureTransferPendingSource] = [],
        forms: [CaptureTransferPendingForm] = []
    ) {
        self.item = item
        self.need = need
        self.sources = sources
        self.forms = forms
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        item = (try? container.decode(Int.self, forKey: .item)) ?? 0
        need = (try? container.decode(String.self, forKey: .need)) ?? ""
        sources =
            (try? container.decode(
                CaptureLossyArray<CaptureTransferPendingSource>.self, forKey: .sources))?
            .values ?? []
        forms =
            (try? container.decode(
                CaptureLossyArray<CaptureTransferPendingForm>.self, forKey: .forms))?
            .values ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case item
        case need
        case sources
        case forms
    }
}

public struct CaptureTransferPendingSourceError: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String = "", message: String = "") {
        self.code = code
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? container.decode(String.self, forKey: .code)) ?? ""
        message = (try? container.decode(String.self, forKey: .message)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }
}

public struct CaptureTransferPendingSource: Codable, Equatable, Sendable {
    public let marker: String
    public let blockID: String
    public let path: String?
    public let line: Int?
    public let title: String?
    public let statusSymbol: String?
    public let statusName: String?
    public let error: CaptureTransferPendingSourceError?

    public init(
        marker: String = "",
        blockID: String = "",
        path: String? = nil,
        line: Int? = nil,
        title: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        error: CaptureTransferPendingSourceError? = nil
    ) {
        self.marker = marker
        self.blockID = blockID
        self.path = path
        self.line = line
        self.title = title
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        marker = (try? container.decode(String.self, forKey: .marker)) ?? ""
        blockID = (try? container.decode(String.self, forKey: .blockID)) ?? ""
        path = try? container.decodeIfPresent(String.self, forKey: .path)
        line = try? container.decodeIfPresent(Int.self, forKey: .line)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        statusSymbol = try? container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try? container.decodeIfPresent(String.self, forKey: .statusName)
        error =
            (try? container.decodeIfPresent(CaptureTransferPendingSourceError.self, forKey: .error))
            ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case marker
        case blockID = "block_id"
        case path
        case line
        case title
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case error
    }
}

public struct CaptureTransferPendingForm: Codable, Equatable, Sendable {
    public let form: String
    public let verb: String
    public let text: String
    public let active: Bool

    public init(form: String = "", verb: String = "", text: String = "", active: Bool = false) {
        self.form = form
        self.verb = verb
        self.text = text
        self.active = active
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        form = (try? container.decode(String.self, forKey: .form)) ?? ""
        verb = (try? container.decode(String.self, forKey: .verb)) ?? ""
        text = (try? container.decode(String.self, forKey: .text)) ?? ""
        active = (try? container.decode(Bool.self, forKey: .active)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case form
        case verb
        case text
        case active
    }
}

/// Display-ready calm card data for Bob's `transfer_pending` failure field.
public struct CaptureTransferPendingPresentation: Equatable, Sendable {
    public enum FormPart: Equatable, Sendable {
        case route
        case blockID
        case section
        case plain
    }

    public struct FormSegment: Equatable, Sendable {
        public let range: Range<Int>
        public let part: FormPart
    }

    public struct SourceRow: Equatable, Sendable {
        public let title: TaskDisplayText?
        public let status: CapturePickerTaskStatus?
        public let statusName: String?
        public let locator: String
        public let errorMessage: TaskDisplayText?
    }

    public struct FormRow: Equatable, Sendable {
        public let form: String
        public let segments: [FormSegment]
        public let verb: String
        public let text: String
        public let active: Bool

        public var glyph: String {
            verb == "move" ? "arrow.right" : "arrow.triangle.merge"
        }
    }

    public let title: String
    public let sourceRows: [SourceRow]
    public let forms: [FormRow]
    public let accessibilitySummary: String

    public init?(pending: CaptureTransferPending) {
        let rows = pending.sources.compactMap(Self.sourceRow)
        let formRows = pending.forms.compactMap(Self.formRow)
        guard !rows.isEmpty, !formRows.isEmpty else {
            return nil
        }

        sourceRows = rows
        forms = formRows
        let count = rows.count
        title = "⇢ \(count) task\(count == 1 ? "" : "s") ready — finish the destination"

        var spokenRows = rows.map { row in
            if let title = row.title {
                var parts = [title.text]
                if let statusName = row.statusName, !statusName.isEmpty {
                    parts.append(statusName)
                }
                if !row.locator.isEmpty {
                    parts.append(row.locator)
                }
                return parts.joined(separator: ", ")
            }
            return row.errorMessage?.text ?? "Unresolved source"
        }
        spokenRows.append(
            contentsOf: formRows.map { row in
                "\(row.form), \(row.text)\(row.active ? ", active" : "")"
            })
        accessibilitySummary = ([title] + spokenRows).joined(separator: ". ")
    }

    private static func sourceRow(_ source: CaptureTransferPendingSource) -> SourceRow? {
        if let error = source.error, !error.message.isEmpty {
            return SourceRow(
                title: nil,
                status: nil,
                statusName: nil,
                locator: "",
                errorMessage: TaskDisplayText(parsing: error.message)
            )
        }
        guard let title = source.title, !title.isEmpty,
            let path = source.path, !path.isEmpty
        else {
            return nil
        }
        let status =
            source.statusSymbol == nil && source.statusName == nil
            ? nil
            : CapturePickerTaskStatus(symbol: source.statusSymbol, name: source.statusName)
        let filename = (path as NSString).lastPathComponent
        let pathLabel = filename.isEmpty ? path : filename
        return SourceRow(
            title: TaskDisplayText(parsing: title),
            status: status,
            statusName: source.statusName,
            locator: source.line.map { "\(pathLabel):\($0)" } ?? pathLabel,
            errorMessage: nil
        )
    }

    private static func formRow(_ form: CaptureTransferPendingForm) -> FormRow? {
        guard !form.form.isEmpty, !form.text.isEmpty else {
            return nil
        }
        return FormRow(
            form: form.form,
            segments: formSegments(form.form),
            verb: form.verb,
            text: form.text,
            active: form.active
        )
    }

    /// The form is a Bob-provided destination example, not user draft syntax.
    /// Split only its visible route, block-ID, and container parts for coloring.
    private static func formSegments(_ form: String) -> [FormSegment] {
        let characters = Array(form)
        guard !characters.isEmpty else {
            return []
        }
        let plus = characters.firstIndex(of: "+")
        let hash = characters.firstIndex(of: "#")
        var segments: [FormSegment] = []

        if let plus {
            if plus > 0 {
                segments.append(FormSegment(range: 0..<plus, part: .route))
            }
            let end = hash ?? characters.count
            if plus < end {
                segments.append(FormSegment(range: plus..<end, part: .blockID))
            }
            if let hash, hash < characters.count {
                segments.append(FormSegment(range: hash..<characters.count, part: .section))
            }
        } else if let hash {
            if hash > 0 {
                segments.append(FormSegment(range: 0..<hash, part: .route))
            }
            if hash < characters.count {
                segments.append(FormSegment(range: hash..<characters.count, part: .section))
            }
        } else {
            segments.append(FormSegment(range: 0..<characters.count, part: .route))
        }
        return segments
    }
}

/// Designed refusal content from a failed live transfer dry run.
public struct CaptureTransferRefusalPresentation: Equatable, Sendable {
    public enum Verb: Equatable, Sendable {
        case move
        case merge
        case transfer

        public var title: String {
            switch self {
            case .move: "Can't move"
            case .merge: "Can't merge"
            case .transfer: "Can't transfer"
            }
        }

        public var glyph: String {
            switch self {
            case .move: "arrow.right"
            case .merge: "arrow.triangle.merge"
            case .transfer: "arrow.left.arrow.right"
            }
        }
    }

    public let verb: Verb
    public let message: TaskDisplayText
    public let code: String?
    public let accessibilitySummary: String

    public init?(failure: CaptureCommandFailure, parseMode: String?) {
        let code = failure.code.flatMap { $0.isEmpty ? nil : $0 }
        guard let verb = Self.verb(code: code, parseMode: parseMode) else {
            return nil
        }
        self.verb = verb
        message = TaskDisplayText(parsing: failure.error)
        self.code = code
        accessibilitySummary = [verb.title, message.text, code]
            .compactMap { $0 }
            .joined(separator: ". ")
    }

    private static func verb(code: String?, parseMode: String?) -> Verb? {
        if parseMode == "task_move" { return .move }
        if parseMode == "task_merge" { return .merge }
        if code?.hasPrefix("merge_") == true { return .merge }
        if code?.hasPrefix("transfer_") == true { return .transfer }
        return nil
    }
}
