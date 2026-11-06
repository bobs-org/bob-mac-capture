import Foundation

/// Tolerant merge-in wire types for Bob's `<` capture syntax.
///
/// Bob owns syntax, source eligibility, merge effects, and copy; the Mac
/// only decodes and presents what Bob returns
/// (`decisions:mac-capture-is-a-thin-client`). Every field decodes
/// tolerantly so missing or malformed additive metadata can never break
/// an unrelated capture. Source order and UTF-8 byte offsets are preserved
/// exactly as Bob reports them.

/// Half-open UTF-8 byte range of Bob's `<` arrow in the exact draft.
public struct CaptureMergeInArrow: Codable, Equatable, Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int = 0, end: Int = 0) {
        self.start = start
        self.end = end
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = (try? container.decodeIfPresent(Int.self, forKey: .start)) ?? 0
        end = (try? container.decodeIfPresent(Int.self, forKey: .end)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
    }
}

/// One complete `<` merge-in source with absolute UTF-8 byte offsets.
public struct CaptureMergeInSource: Codable, Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let marker: String
    public let route: String
    public let blockID: String

    public init(
        start: Int = 0,
        end: Int = 0,
        marker: String = "",
        route: String = "",
        blockID: String = ""
    ) {
        self.start = start
        self.end = end
        self.marker = marker
        self.route = route
        self.blockID = blockID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = (try? container.decodeIfPresent(Int.self, forKey: .start)) ?? 0
        end = (try? container.decodeIfPresent(Int.self, forKey: .end)) ?? 0
        marker = (try? container.decodeIfPresent(String.self, forKey: .marker)) ?? ""
        route = (try? container.decodeIfPresent(String.self, forKey: .route)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case marker
        case route
        case blockID = "block_id"
    }
}

/// Complete `<` merge-in clause: the arrow plus ordered sources.
/// Present only when the line carries a `<` clause; pending clauses carry
/// an arrow with empty sources.
public struct CaptureMergeIn: Codable, Equatable, Sendable {
    public let arrow: CaptureMergeInArrow
    public let sources: [CaptureMergeInSource]

    public init(
        arrow: CaptureMergeInArrow = CaptureMergeInArrow(),
        sources: [CaptureMergeInSource] = []
    ) {
        self.arrow = arrow
        self.sources = sources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arrow =
            (try? container.decodeIfPresent(CaptureMergeInArrow.self, forKey: .arrow))
            ?? CaptureMergeInArrow()
        sources =
            (try? container.decodeIfPresent([CaptureMergeInSource].self, forKey: .sources))
            ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case arrow
        case sources
    }
}

/// Bob-authored explicit rewrite attached to a `capture-parse` diagnostic.
/// Ranges are half-open UTF-8 offsets into the exact draft. The app applies
/// it only through an explicit button action, never on Return.
public struct CaptureDiagnosticRewrite: Codable, Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let replacement: String
    public let label: String

    public init(
        start: Int = 0,
        end: Int = 0,
        replacement: String = "",
        label: String = ""
    ) {
        self.start = start
        self.end = end
        self.replacement = replacement
        self.label = label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = (try? container.decodeIfPresent(Int.self, forKey: .start)) ?? 0
        end = (try? container.decodeIfPresent(Int.self, forKey: .end)) ?? 0
        replacement = (try? container.decodeIfPresent(String.self, forKey: .replacement)) ?? ""
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case replacement
        case label
    }
}

/// Source-level error inside a `merge_in_pending` source row.
public struct CaptureMergeInPendingSourceError: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String = "", message: String = "") {
        self.code = code
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? container.decodeIfPresent(String.self, forKey: .code)) ?? ""
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }
}

/// One read-only source row inside `merge_in_pending`: resolved location
/// plus mergeability, or a source-level error. Mirrors the transfer pending
/// shape where it really matches, with additive mergeability verdicts.
public struct CaptureMergeInPendingSource: Codable, Equatable, Sendable {
    public let marker: String
    public let blockID: String
    public let path: String?
    public let line: Int?
    public let title: String?
    public let statusSymbol: String?
    public let statusName: String?
    public let mergeable: Bool?
    public let mergeableCode: String?
    public let mergeableMessage: String?
    public let error: CaptureMergeInPendingSourceError?

    public init(
        marker: String = "",
        blockID: String = "",
        path: String? = nil,
        line: Int? = nil,
        title: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        mergeable: Bool? = nil,
        mergeableCode: String? = nil,
        mergeableMessage: String? = nil,
        error: CaptureMergeInPendingSourceError? = nil
    ) {
        self.marker = marker
        self.blockID = blockID
        self.path = path
        self.line = line
        self.title = title
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.mergeable = mergeable
        self.mergeableCode = mergeableCode
        self.mergeableMessage = mergeableMessage
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        marker = (try? container.decodeIfPresent(String.self, forKey: .marker)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        path = try? container.decodeIfPresent(String.self, forKey: .path)
        line = try? container.decodeIfPresent(Int.self, forKey: .line)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        statusSymbol = try? container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try? container.decodeIfPresent(String.self, forKey: .statusName)
        mergeable = try? container.decodeIfPresent(Bool.self, forKey: .mergeable)
        mergeableCode = try? container.decodeIfPresent(String.self, forKey: .mergeableCode)
        mergeableMessage = try? container.decodeIfPresent(String.self, forKey: .mergeableMessage)
        error =
            (try? container.decodeIfPresent(
                CaptureMergeInPendingSourceError.self,
                forKey: .error
            )) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case marker
        case blockID = "block_id"
        case path
        case line
        case title
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case mergeable
        case mergeableCode = "mergeable_code"
        case mergeableMessage = "mergeable_message"
        case error
    }
}

/// Read-only resolved source context for a merge-in whose sources are still
/// being typed. Older Bob omits this additive failure payload; malformed
/// rows are dropped independently so one bad source cannot hide the rest.
public struct CaptureMergeInPending: Codable, Equatable, Sendable {
    public let item: Int
    public let need: String
    public let sources: [CaptureMergeInPendingSource]

    public init(
        item: Int = 0,
        need: String = "",
        sources: [CaptureMergeInPendingSource] = []
    ) {
        self.item = item
        self.need = need
        self.sources = sources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        item = (try? container.decodeIfPresent(Int.self, forKey: .item)) ?? 0
        need = (try? container.decodeIfPresent(String.self, forKey: .need)) ?? ""
        sources =
            (try? container.decode(
                CaptureLossyArray<CaptureMergeInPendingSource>.self,
                forKey: .sources
            ))?.values ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case item
        case need
        case sources
    }
}
