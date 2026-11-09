import Foundation

/// Compact execution summary for a declared bulk template. Older Bob omits
/// the object, so clients can safely treat nil as an ordinary capture.
public struct CaptureTemplateSummary: Codable, Equatable, Sendable {
    public let line: Int
    public let fieldCount: Int
    public let rowCount: Int
    /// Result of bob's best-effort save after a successful template capture.
    /// Absent on older bob and on dry-run previews.
    public let saved: CaptureTemplateSavedSummary?
    /// Best-effort shelf failure, present only when bob attempted and could
    /// not save the template. It never changes capture success.
    public let notSaved: String?

    public init(
        line: Int = 0,
        fieldCount: Int = 0,
        rowCount: Int = 0,
        saved: CaptureTemplateSavedSummary? = nil,
        notSaved: String? = nil
    ) {
        self.line = line
        self.fieldCount = fieldCount
        self.rowCount = rowCount
        self.saved = saved
        self.notSaved = notSaved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        fieldCount = (try? container.decodeIfPresent(Int.self, forKey: .fieldCount)) ?? 0
        rowCount = (try? container.decodeIfPresent(Int.self, forKey: .rowCount)) ?? 0
        saved =
            (try? container.decodeIfPresent(CaptureTemplateSavedSummary.self, forKey: .saved)) ?? nil
        notSaved = (try? container.decodeIfPresent(String.self, forKey: .notSaved)) ?? nil
    }

    public var previewChipTitle: String {
        "Template · \(rowCount) \(rowCount == 1 ? "row" : "rows")"
    }

    public var previewAccessibilityLabel: String {
        "\(rowCount) capture items from a template"
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case fieldCount = "field_count"
        case rowCount = "row_count"
        case saved
        case notSaved = "not_saved"
    }
}

/// One row field from Bob's template-aware editor parse. Ranges are UTF-8
/// byte offsets into the typed draft, including quotes where present.
public struct CaptureTemplateField: Codable, Equatable, Sendable {
    public let field: Int
    public let value: String
    public let range: CaptureRange

    public init(
        field: Int = 0, value: String = "", range: CaptureRange = CaptureRange(start: 0, end: 0)
    ) {
        self.field = field
        self.value = value
        self.range = range
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        field = (try? container.decodeIfPresent(Int.self, forKey: .field)) ?? 0
        value = (try? container.decodeIfPresent(String.self, forKey: .value)) ?? ""
        range =
            (try? container.decodeIfPresent(CaptureRange.self, forKey: .range))
            ?? CaptureRange(start: 0, end: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case field
        case value
        case range
    }
}

/// A template row as returned by `capture-parse` and `capture`. Parse-only
/// details are optional so the same type decodes execution's compact
/// `{row,line}` object without rejecting older or partial payloads.
public struct CaptureTemplateRow: Codable, Equatable, Sendable {
    public let row: Int
    public let line: Int
    public let range: CaptureRange?
    public let mode: String?
    public let body: String?
    public let fields: [CaptureTemplateField]

    public init(
        row: Int = 0,
        line: Int = 0,
        range: CaptureRange? = nil,
        mode: String? = nil,
        body: String? = nil,
        fields: [CaptureTemplateField] = []
    ) {
        self.row = row
        self.line = line
        self.range = range
        self.mode = mode
        self.body = body
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        row = (try? container.decodeIfPresent(Int.self, forKey: .row)) ?? 0
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        range = (try? container.decodeIfPresent(CaptureRange.self, forKey: .range)) ?? nil
        mode = (try? container.decodeIfPresent(String.self, forKey: .mode)) ?? nil
        body = (try? container.decodeIfPresent(String.self, forKey: .body)) ?? nil
        fields = (try? container.decodeIfPresent([CaptureTemplateField].self, forKey: .fields)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case row
        case line
        case range
        case mode
        case body
        case fields
    }
}

/// The `%t` directive that marks a draft's first item as a template. Bob reports its
/// source range and 1-based line as `template.directive`.
public struct CaptureTemplateDirective: Codable, Equatable {
    public let range: CaptureRange
    public let line: Int

    public init(range: CaptureRange = CaptureRange(start: 0, end: 0), line: Int = 0) {
        self.range = range
        self.line = line
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range =
            (try? container.decodeIfPresent(CaptureRange.self, forKey: .range))
            ?? CaptureRange(start: 0, end: 0)
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case line
    }
}

/// Template-specific parse metadata. Row ranges and field ranges index the
/// original editor draft; the expanded instance is only used for preview.
public struct CaptureParseTemplate: Codable, Equatable {
    public let directive: CaptureTemplateDirective
    public let range: CaptureRange
    public let lineStart: Int
    public let lineEnd: Int
    public let fieldCount: Int
    public let rows: [CaptureTemplateRow]

    public init(
        directive: CaptureTemplateDirective = CaptureTemplateDirective(),
        range: CaptureRange = CaptureRange(start: 0, end: 0),
        lineStart: Int = 0,
        lineEnd: Int = 0,
        fieldCount: Int = 0,
        rows: [CaptureTemplateRow] = []
    ) {
        self.directive = directive
        self.range = range
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.fieldCount = fieldCount
        self.rows = rows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        directive =
            (try? container.decodeIfPresent(CaptureTemplateDirective.self, forKey: .directive))
            ?? CaptureTemplateDirective()
        range =
            (try? container.decodeIfPresent(CaptureRange.self, forKey: .range))
            ?? CaptureRange(start: 0, end: 0)
        lineStart = (try? container.decodeIfPresent(Int.self, forKey: .lineStart)) ?? 0
        lineEnd = (try? container.decodeIfPresent(Int.self, forKey: .lineEnd)) ?? 0
        fieldCount = (try? container.decodeIfPresent(Int.self, forKey: .fieldCount)) ?? 0
        rows = (try? container.decodeIfPresent([CaptureTemplateRow].self, forKey: .rows)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case directive
        case range
        case lineStart = "line_start"
        case lineEnd = "line_end"
        case fieldCount = "field_count"
        case rows
    }
}

public struct CaptureParseResponse: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    /// Top-level capture-language revision. Grammar 5 adds whole-item
    /// Pomodoro split/merge syntax. A Bob that predates the field omits it.
    /// Missing or mistyped values stay nil, never a guessed revision, so the
    /// compatibility gate can tell "older than grammar" from "grammar 1".
    public let grammar: Int?
    public let input: String
    public let body: String
    public let mode: String
    public let route: String?
    public let section: String?
    public let blockID: String?
    public let needs: [String]
    public let refParent: CaptureParseRefParent?
    /// Additive schema-version-1 listen intent; older Bob payloads default false.
    public let refListen: Bool
    /// Additive top-level `relation_grammar: 1` whenever the draft contains a `~`
    /// byte. Older Bob omits the key; missing decodes as nil so the capability
    /// warning can distinguish a predating Bob from a draft without relations.
    public let relationGrammar: Int?
    public let spans: [CaptureSpan]
    public let diagnostics: [CaptureDiagnostic]
    public let globalDestination: CaptureGlobalDestination?
    // Additive to schema version 1: `bob capture-parse` omits these keys entirely when
    // a draft has no authored sub-bullets, and older bob versions omit depths even when
    // they provide bodies. Decode both tolerantly and synthesize depth 1 for older bob
    // responses rather than letting clients index mismatched arrays.
    public let subBullets: [String]
    public let subBulletDepths: [Int]
    public let items: [CaptureParseItem]
    // Additive `=<X>` start suffix on a `@<route>:<block-id>[#<name>]` marker.
    // Omitted for every older marker shape, so older bob output decodes as nil.
    public let pomodoroStart: PomodoroStartSpec?
    // Additive whole-item `+N`/`-N` adjustment spec. Omitted for every
    // non-adjustment mode, so older bob output decodes as nil.
    public let pomodoroAdjust: PomodoroAdjustSpec?
    // Additive whole-item `++N`/`--N` shift spec. Omitted for every
    // non-shift mode, so older bob output decodes as nil.
    public let pomodoroShift: PomodoroShiftSpec?
    // Additive whole-item `x` close or `=x` close suffix on a `@`/`^` link item.
    // Omitted for every non-close mode, so older bob output decodes as nil.
    public let pomodoroClose: PomodoroCloseSpec?
    // Additive text-only `x=` past object on `pomodoro_past` responses and
    // items. Omitted for every non-past mode and by older Bob; malformed
    // optional metadata degrades to nil so the rest still decodes.
    public let pomodoroPast: PomodoroPastSpec?
    // Additive `&` / `*` markers and the owner they hang on. Older Bob
    // omits them; missing decodes as empty / nil.
    public let dependencies: [CaptureParseRelationshipMarker]
    public let blockedTasks: [CaptureParseRelationshipMarker]
    /// Additive `~` / `~~` relation markers. Older Bob omits the array.
    public let relations: [CaptureParseRelationshipMarker]
    public let dependencyTarget: DependencyOwner?
    /// Additive template parse contract; absent in older Bob and for ordinary drafts.
    public let template: CaptureParseTemplate?
    /// Additive first-item `<` merge-in clause, when the first item carries
    /// one. Older Bob omits the key; missing or malformed decodes as nil.
    public let mergeIn: CaptureMergeIn?
    /// Additive record creation metadata. Present on record drafts and
    /// absent otherwise; older Bob omits it entirely.
    public let record: CaptureRecord?

    public init(
        ok: Bool,
        schemaVersion: Int,
        grammar: Int? = 2,
        input: String,
        body: String,
        mode: String,
        route: String? = nil,
        section: String? = nil,
        blockID: String? = nil,
        needs: [String] = [],
        refParent: CaptureParseRefParent? = nil,
        refListen: Bool = false,
        relationGrammar: Int? = nil,
        spans: [CaptureSpan] = [],
        diagnostics: [CaptureDiagnostic] = [],
        globalDestination: CaptureGlobalDestination? = nil,
        subBullets: [String] = [],
        subBulletDepths: [Int]? = nil,
        items: [CaptureParseItem] = [],
        pomodoroStart: PomodoroStartSpec? = nil,
        pomodoroAdjust: PomodoroAdjustSpec? = nil,
        pomodoroShift: PomodoroShiftSpec? = nil,
        pomodoroClose: PomodoroCloseSpec? = nil,
        pomodoroPast: PomodoroPastSpec? = nil,
        dependencies: [CaptureParseRelationshipMarker] = [],
        blockedTasks: [CaptureParseRelationshipMarker] = [],
        relations: [CaptureParseRelationshipMarker] = [],
        dependencyTarget: DependencyOwner? = nil,
        template: CaptureParseTemplate? = nil,
        mergeIn: CaptureMergeIn? = nil,
        record: CaptureRecord? = nil
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.grammar = grammar
        self.input = input
        self.body = body
        self.mode = mode
        self.route = route
        self.section = section
        self.blockID = blockID
        self.needs = needs
        self.refParent = refParent
        self.refListen = refListen
        self.relationGrammar = relationGrammar
        self.spans = spans
        self.diagnostics = diagnostics
        self.globalDestination = globalDestination
        self.subBullets = subBullets
        self.subBulletDepths = Self.normalizedSubBulletDepths(
            subBulletDepths,
            bodyCount: subBullets.count
        )
        self.items = items
        self.pomodoroStart = pomodoroStart
        self.pomodoroAdjust = pomodoroAdjust
        self.pomodoroShift = pomodoroShift
        self.pomodoroClose = pomodoroClose
        self.pomodoroPast = pomodoroPast
        self.dependencies = dependencies
        self.blockedTasks = blockedTasks
        self.relations = relations
        self.dependencyTarget = dependencyTarget
        self.template = template
        self.mergeIn = mergeIn
        self.record = record
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        grammar = (try? container.decodeIfPresent(Int.self, forKey: .grammar)) ?? nil
        input = try container.decode(String.self, forKey: .input)
        body = try container.decode(String.self, forKey: .body)
        mode = try container.decode(String.self, forKey: .mode)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        section = try container.decodeIfPresent(String.self, forKey: .section)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        needs = try container.decodeIfPresent([String].self, forKey: .needs) ?? []
        refParent =
            (try? container.decodeIfPresent(CaptureParseRefParent.self, forKey: .refParent)) ?? nil
        refListen = (try? container.decodeIfPresent(Bool.self, forKey: .refListen)) ?? false
        relationGrammar = (try? container.decodeIfPresent(Int.self, forKey: .relationGrammar)) ?? nil
        spans = try container.decodeIfPresent([CaptureSpan].self, forKey: .spans) ?? []
        diagnostics =
            try container.decodeIfPresent([CaptureDiagnostic].self, forKey: .diagnostics) ?? []
        globalDestination = try container.decodeIfPresent(
            CaptureGlobalDestination.self,
            forKey: .globalDestination
        )
        subBullets = try container.decodeIfPresent([String].self, forKey: .subBullets) ?? []
        let decodedDepths = try container.decodeIfPresent(
            [Int].self,
            forKey: .subBulletDepths
        )
        subBulletDepths = Self.normalizedSubBulletDepths(
            decodedDepths,
            bodyCount: subBullets.count
        )
        items = try container.decodeIfPresent([CaptureParseItem].self, forKey: .items) ?? []
        pomodoroStart = try container.decodeIfPresent(PomodoroStartSpec.self, forKey: .pomodoroStart)
        pomodoroAdjust = try container.decodeIfPresent(
            PomodoroAdjustSpec.self,
            forKey: .pomodoroAdjust
        )
        pomodoroShift = try container.decodeIfPresent(
            PomodoroShiftSpec.self,
            forKey: .pomodoroShift
        )
        pomodoroClose = try container.decodeIfPresent(
            PomodoroCloseSpec.self,
            forKey: .pomodoroClose
        )
        pomodoroPast = (try? container.decodeIfPresent(
            PomodoroPastSpec.self,
            forKey: .pomodoroPast
        )) ?? nil
        dependencies =
            try container.decodeIfPresent(
                [CaptureParseRelationshipMarker].self,
                forKey: .dependencies
            ) ?? []
        blockedTasks =
            try container.decodeIfPresent(
                [CaptureParseRelationshipMarker].self,
                forKey: .blockedTasks
            ) ?? []
        relations =
            (try? container.decodeIfPresent(
                [CaptureParseRelationshipMarker].self,
                forKey: .relations
            )) ?? []
        dependencyTarget = try container.decodeIfPresent(
            DependencyOwner.self,
            forKey: .dependencyTarget
        )
        template = (try? container.decodeIfPresent(CaptureParseTemplate.self, forKey: .template)) ?? nil
        mergeIn = (try? container.decodeIfPresent(CaptureMergeIn.self, forKey: .mergeIn)) ?? nil
        record = (try? container.decodeIfPresent(CaptureRecord.self, forKey: .record)) ?? nil
    }

    private static func normalizedSubBulletDepths(
        _ depths: [Int]?,
        bodyCount: Int
    ) -> [Int] {
        guard bodyCount > 0 else {
            return []
        }
        guard let depths,
            depths.count == bodyCount,
            depths.allSatisfy({ $0 == 1 || $0 == 2 })
        else {
            return Array(repeating: 1, count: bodyCount)
        }
        return depths
    }

    /// True when Bob reported a `%c` directive span for this draft. A bare
    /// `%` carries no directive value and escaped or literal `%c` text has no
    /// directive span at all, so neither authorizes a clipboard read. Bob
    /// stays authoritative: Swift never infers `%c` from the draft text.
    public var reportsClipDirective: Bool {
        spans.contains { $0.kind == "directive" && $0.directive == "clip" }
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case grammar
        case input
        case body
        case mode
        case route
        case section
        case blockID = "block_id"
        case needs
        case refParent = "ref_parent"
        case refListen = "ref_listen"
        case relationGrammar = "relation_grammar"
        case spans
        case diagnostics
        case globalDestination = "global_destination"
        case subBullets = "sub_bullets"
        case subBulletDepths = "sub_bullet_depths"
        case items
        case pomodoroStart = "pomodoro_start"
        case pomodoroAdjust = "pomodoro_adjust"
        case pomodoroShift = "pomodoro_shift"
        case pomodoroClose = "pomodoro_close"
        case pomodoroPast = "pomodoro_past"
        case dependencies
        case blockedTasks = "blocked_tasks"
        case relations
        case dependencyTarget = "dependency_target"
        case template
        case mergeIn = "merge_in"
        case record
    }
}

/// Additive `ref_parent` on a `ref` parse item or response: the lexical
/// parent token (explicit route, inherited global route, or `mac_inbox`)
/// plus its source (`explicit`|`global`|`default`). Bob reports it outside
/// `needs` so a bare URL stays submittable while the client knows to offer
/// a parent picker. Older Bob omits it; missing decodes as nil.
public struct CaptureParseRefParent: Codable, Equatable, Sendable {
    public let token: String
    public let source: String

    public init(token: String = "", source: String = "") {
        self.token = token
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case token
        case source
    }
}

public struct CaptureParseItem: Codable, Equatable {
    public let index: Int
    public let range: CaptureRange
    public let lineStart: Int
    public let lineEnd: Int
    public let body: String
    public let mode: String
    public let route: String?
    public let section: String?
    public let blockID: String?
    public let needs: [String]
    public let refParent: CaptureParseRefParent?
    /// Per-item additive listen intent; omitted by older Bob versions.
    public let refListen: Bool
    public let subBullets: [String]
    public let subBulletDepths: [Int]
    // Per-item additive `=<X>` start suffix. Omitted for items without one.
    public let pomodoroStart: PomodoroStartSpec?
    // Per-item additive whole-item `+N`/`-N` adjustment spec. Omitted for
    // items without one.
    public let pomodoroAdjust: PomodoroAdjustSpec?
    // Per-item additive whole-item `++N`/`--N` shift spec. Omitted for
    // items without one.
    public let pomodoroShift: PomodoroShiftSpec?
    // Per-item additive whole-item `x` close or `=x` link suffix. Omitted for
    // items without one.
    public let pomodoroClose: PomodoroCloseSpec?
    // Per-item additive `x=` past object. Omitted for items without one and
    // by older Bob; malformed metadata degrades to nil.
    public let pomodoroPast: PomodoroPastSpec?
    public let dependencies: [CaptureParseRelationshipMarker]
    public let blockedTasks: [CaptureParseRelationshipMarker]
    public let relations: [CaptureParseRelationshipMarker]
    public let dependencyTarget: DependencyOwner?
    /// Additive row metadata for template parse items; omitted by older Bob.
    public let templateRow: CaptureTemplateRow?
    /// Additive `<` merge-in clause for this item, when claimed. Older Bob
    /// omits the key; missing or malformed decodes as nil.
    public let mergeIn: CaptureMergeIn?
    /// Additive record creation metadata for this item, when claimed.
    /// Older Bob omits the key; missing or malformed decodes as nil.
    public let record: CaptureRecord?

    public init(
        index: Int,
        range: CaptureRange,
        lineStart: Int,
        lineEnd: Int,
        body: String,
        mode: String,
        route: String? = nil,
        section: String? = nil,
        blockID: String? = nil,
        needs: [String] = [],
        refParent: CaptureParseRefParent? = nil,
        refListen: Bool = false,
        subBullets: [String] = [],
        subBulletDepths: [Int] = [],
        pomodoroStart: PomodoroStartSpec? = nil,
        pomodoroAdjust: PomodoroAdjustSpec? = nil,
        pomodoroShift: PomodoroShiftSpec? = nil,
        pomodoroClose: PomodoroCloseSpec? = nil,
        pomodoroPast: PomodoroPastSpec? = nil,
        dependencies: [CaptureParseRelationshipMarker] = [],
        blockedTasks: [CaptureParseRelationshipMarker] = [],
        relations: [CaptureParseRelationshipMarker] = [],
        dependencyTarget: DependencyOwner? = nil,
        templateRow: CaptureTemplateRow? = nil,
        mergeIn: CaptureMergeIn? = nil,
        record: CaptureRecord? = nil
    ) {
        self.index = index
        self.range = range
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.body = body
        self.mode = mode
        self.route = route
        self.section = section
        self.blockID = blockID
        self.needs = needs
        self.refParent = refParent
        self.refListen = refListen
        self.subBullets = subBullets
        self.subBulletDepths = subBulletDepths
        self.pomodoroStart = pomodoroStart
        self.pomodoroAdjust = pomodoroAdjust
        self.pomodoroShift = pomodoroShift
        self.pomodoroClose = pomodoroClose
        self.pomodoroPast = pomodoroPast
        self.dependencies = dependencies
        self.blockedTasks = blockedTasks
        self.relations = relations
        self.dependencyTarget = dependencyTarget
        self.templateRow = templateRow
        self.mergeIn = mergeIn
        self.record = record
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        range = try container.decode(CaptureRange.self, forKey: .range)
        lineStart = try container.decode(Int.self, forKey: .lineStart)
        lineEnd = try container.decode(Int.self, forKey: .lineEnd)
        body = try container.decode(String.self, forKey: .body)
        mode = try container.decode(String.self, forKey: .mode)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        section = try container.decodeIfPresent(String.self, forKey: .section)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        needs = try container.decodeIfPresent([String].self, forKey: .needs) ?? []
        refParent =
            (try? container.decodeIfPresent(CaptureParseRefParent.self, forKey: .refParent)) ?? nil
        refListen = (try? container.decodeIfPresent(Bool.self, forKey: .refListen)) ?? false
        subBullets = try container.decodeIfPresent([String].self, forKey: .subBullets) ?? []
        subBulletDepths = try container.decodeIfPresent([Int].self, forKey: .subBulletDepths) ?? []
        pomodoroStart = try container.decodeIfPresent(PomodoroStartSpec.self, forKey: .pomodoroStart)
        pomodoroAdjust = try container.decodeIfPresent(
            PomodoroAdjustSpec.self,
            forKey: .pomodoroAdjust
        )
        pomodoroShift = try container.decodeIfPresent(
            PomodoroShiftSpec.self,
            forKey: .pomodoroShift
        )
        pomodoroClose = try container.decodeIfPresent(
            PomodoroCloseSpec.self,
            forKey: .pomodoroClose
        )
        pomodoroPast = (try? container.decodeIfPresent(
            PomodoroPastSpec.self,
            forKey: .pomodoroPast
        )) ?? nil
        dependencies =
            try container.decodeIfPresent(
                [CaptureParseRelationshipMarker].self,
                forKey: .dependencies
            ) ?? []
        blockedTasks =
            try container.decodeIfPresent(
                [CaptureParseRelationshipMarker].self,
                forKey: .blockedTasks
            ) ?? []
        relations =
            (try? container.decodeIfPresent(
                [CaptureParseRelationshipMarker].self,
                forKey: .relations
            )) ?? []
        dependencyTarget = try container.decodeIfPresent(
            DependencyOwner.self,
            forKey: .dependencyTarget
        )
        templateRow =
            (try? container.decodeIfPresent(CaptureTemplateRow.self, forKey: .templateRow)) ?? nil
        mergeIn =
            (try? container.decodeIfPresent(CaptureMergeIn.self, forKey: .mergeIn)) ?? nil
        record = (try? container.decodeIfPresent(CaptureRecord.self, forKey: .record)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case range
        case lineStart = "line_start"
        case lineEnd = "line_end"
        case body
        case mode
        case route
        case section
        case blockID = "block_id"
        case needs
        case refParent = "ref_parent"
        case refListen = "ref_listen"
        case subBullets = "sub_bullets"
        case subBulletDepths = "sub_bullet_depths"
        case pomodoroStart = "pomodoro_start"
        case pomodoroAdjust = "pomodoro_adjust"
        case pomodoroShift = "pomodoro_shift"
        case pomodoroClose = "pomodoro_close"
        case pomodoroPast = "pomodoro_past"
        case dependencies
        case blockedTasks = "blocked_tasks"
        case relations
        case dependencyTarget = "dependency_target"
        case templateRow = "template_row"
        case mergeIn = "merge_in"
        case record
    }
}

/// One typed `&`, `*`, `~`, or `~~` marker from `capture-parse`. Unresolvable
/// entries keep `raw` / `note` / `block_id`. Older Bob omits the array.
/// Relation markers add `direction` (`to`/`from`), `label`, `label_range`,
/// and `hidden` (true for the `||` spelling; omitted otherwise).
public struct CaptureParseRelationshipMarker: Codable, Equatable, Sendable {
    public let raw: String
    public let note: String?
    public let blockID: String?
    public let quoted: Bool
    public let range: CaptureRange?
    /// `to` or `from` on a relation marker; nil for `&` / `*`.
    public let direction: String?
    public let label: String?
    public let labelRange: CaptureRange?
    /// True when the draft spells this relation `||` (one-off). Bob omits
    /// the key otherwise, so missing decodes as false.
    public let hidden: Bool

    public init(
        raw: String,
        note: String? = nil,
        blockID: String? = nil,
        quoted: Bool = false,
        range: CaptureRange? = nil,
        direction: String? = nil,
        label: String? = nil,
        labelRange: CaptureRange? = nil,
        hidden: Bool = false
    ) {
        self.raw = raw
        self.note = note
        self.blockID = blockID
        self.quoted = quoted
        self.range = range
        self.direction = direction
        self.label = label
        self.labelRange = labelRange
        self.hidden = hidden
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        quoted = try container.decodeIfPresent(Bool.self, forKey: .quoted) ?? false
        range = try container.decodeIfPresent(CaptureRange.self, forKey: .range)
        direction = (try? container.decodeIfPresent(String.self, forKey: .direction)) ?? nil
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? nil
        labelRange = (try? container.decodeIfPresent(CaptureRange.self, forKey: .labelRange)) ?? nil
        hidden = (try? container.decodeIfPresent(Bool.self, forKey: .hidden)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case note
        case blockID = "block_id"
        case quoted
        case range
        case direction
        case label
        case labelRange = "label_range"
        case hidden
    }
}

/// One typed Work Log entry from Bob's `pomodoro_close.log`: the 1-based
/// task index plus its literal entry text, in typed order. `index` is nil
/// for an unnumbered bullet (`- foo`) under a close without `<N>`/`*<P>`,
/// which `bob capture` resolves against the running session at execution;
/// `bob capture-parse` omits the key there. Additive: an older Bob that
/// omits `log` decodes as empty. `details` holds the nested detail lines
/// typed under the entry (`  - …` bullets), in typed order; an older Bob
/// that omits `details` decodes as empty.
public struct PomodoroCloseLogEntry: Codable, Equatable, Sendable {
    public let index: Int?
    public let text: String
    public let details: [String]

    public init(index: Int?, text: String, details: [String] = []) {
        self.index = index
        self.text = text
        self.details = details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        details = try container.decodeIfPresent([String].self, forKey: .details) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case text
        case details
    }
}

/// The typed close token from `bob capture-parse`: whole-item closes use
/// `x[…]` including the `x*`/`x!` forms, while link and task suffixes use
/// `=x[…]`. `raw` preserves exactly what was typed (for example `"x"`,
/// `"x1!2"`, `"x1~2"`, `"x*2"`, `"x*"`, `"x!"`, or `"=x1!2"`).
/// `inProgress` is the sorted
/// `in_progress` list, or nil when `<N>` was omitted (plain `x` leaves
/// unlisted links at their ledger outcome unless `*<P>` is present, which
/// activates selection mode like `<N>`); `parkAll`/`completeAll` preserve a
/// present-but-empty `*`/`!` group until Bob resolves the current lineup;
/// `park` and `complete` carry only concrete numbers.
/// `drop` is the sorted `~<K>` list, empty when no `~` list was typed.
/// Present on whole-item closes and on link and body-bearing items carrying
/// the close suffix. Older Bob binaries omit all four lists; they decode as
/// none/empty so the card is exactly today's.
public struct PomodoroCloseSpec: Codable, Equatable, Sendable {
    public let raw: String
    public let inProgress: [Int]?
    public let park: [Int]
    public let parkAll: Bool
    public let complete: [Int]
    public let completeAll: Bool
    public let drop: [Int]
    public let log: [PomodoroCloseLogEntry]

    public init(
        raw: String, inProgress: [Int]? = nil, park: [Int] = [], parkAll: Bool = false,
        complete: [Int] = [], completeAll: Bool = false, drop: [Int] = [],
        log: [PomodoroCloseLogEntry] = []
    ) {
        self.raw = raw
        self.inProgress = inProgress
        self.park = park
        self.parkAll = parkAll
        self.complete = complete
        self.completeAll = completeAll
        self.drop = drop
        self.log = log
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        inProgress = try container.decodeIfPresent([Int].self, forKey: .inProgress)
        park = try container.decodeIfPresent([Int].self, forKey: .park) ?? []
        parkAll = try container.decodeIfPresent(Bool.self, forKey: .parkAll) ?? false
        complete = try container.decodeIfPresent([Int].self, forKey: .complete) ?? []
        completeAll = try container.decodeIfPresent(Bool.self, forKey: .completeAll) ?? false
        drop = try container.decodeIfPresent([Int].self, forKey: .drop) ?? []
        log = try container.decodeIfPresent([PomodoroCloseLogEntry].self, forKey: .log) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case inProgress = "in_progress"
        case park
        case parkAll = "park_all"
        case complete
        case completeAll = "complete_all"
        case drop
        case log
    }
}

/// Stack position of one `x=` member inside its past stack, in typed order.
/// `index` is 1-based, `size` is the stack length, and `offsetBlocks` is the
/// sum of blocks of every later member. Purely lexical; Bob is the sole
/// authority for the numbers.
public struct PomodoroPastStackSpec: Codable, Equatable, Sendable {
    public let index: Int
    public let size: Int
    public let offsetBlocks: Int

    public init(index: Int = 0, size: Int = 0, offsetBlocks: Int = 0) {
        self.index = index
        self.size = size
        self.offsetBlocks = offsetBlocks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        offsetBlocks = try container.decodeIfPresent(Int.self, forKey: .offsetBlocks) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case size
        case offsetBlocks = "offset_blocks"
    }
}

/// Text-only `pomodoro_past` object from `bob capture-parse`, on the response
/// and on each `pomodoro_past` item. `raw` preserves exactly what was typed,
/// `name` is nil when unnamed, `blocks` defaults to 5, `minutes` is
/// `blocks * 5`, `repair` is the trailing `!`, `stack` is the typed position,
/// and `close` is the existing close-spec shape. Older Bob omits the whole
/// object; malformed optional metadata degrades to nil at the call site.
public struct PomodoroPastSpec: Codable, Equatable, Sendable {
    public let raw: String
    public let name: String?
    public let nameIsLiteral: Bool
    public let blocks: Int
    public let minutes: Int
    public let repair: Bool
    public let stack: PomodoroPastStackSpec
    public let close: PomodoroCloseSpec

    public init(
        raw: String = "",
        name: String? = nil,
        nameIsLiteral: Bool = false,
        blocks: Int = 5,
        minutes: Int = 25,
        repair: Bool = false,
        stack: PomodoroPastStackSpec = PomodoroPastStackSpec(),
        close: PomodoroCloseSpec = PomodoroCloseSpec(raw: "")
    ) {
        self.raw = raw
        self.name = name
        self.nameIsLiteral = nameIsLiteral
        self.blocks = blocks
        self.minutes = minutes
        self.repair = repair
        self.stack = stack
        self.close = close
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
        nameIsLiteral = try container.decodeIfPresent(Bool.self, forKey: .nameIsLiteral) ?? false
        blocks = try container.decodeIfPresent(Int.self, forKey: .blocks) ?? 5
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes) ?? (blocks * 5)
        repair = try container.decodeIfPresent(Bool.self, forKey: .repair) ?? false
        stack =
            (try? container.decodeIfPresent(
                PomodoroPastStackSpec.self,
                forKey: .stack
            )) ?? PomodoroPastStackSpec()
        close =
            (try? container.decodeIfPresent(
                PomodoroCloseSpec.self,
                forKey: .close
            )) ?? PomodoroCloseSpec(raw: "")
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case name
        case nameIsLiteral = "name_is_literal"
        case blocks
        case minutes
        case repair
        case stack
        case close
    }
}

/// One trimmed closed edge from Bob's recorded past session: the span rewrite
/// staged before any member recorded. `minutes` is the old span minus the new
/// one (what the whole stack took); `calendar` flags MEET rows. Decodes
/// tolerantly so a partial trim still previews instead of failing the capture.
public struct PomodoroPastTrim: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String
    public let before: String
    public let after: String
    public let minutes: Int
    public let clock: String
    public let calendar: Bool

    public init(
        line: Int = 0,
        name: String = "",
        before: String = "",
        after: String = "",
        minutes: Int = 0,
        clock: String = "",
        calendar: Bool = false
    ) {
        self.line = line
        self.name = name
        self.before = before
        self.after = after
        self.minutes = minutes
        self.clock = clock
        self.calendar = calendar
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        before = try container.decodeIfPresent(String.self, forKey: .before) ?? ""
        after = try container.decodeIfPresent(String.self, forKey: .after) ?? ""
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        clock = try container.decodeIfPresent(String.self, forKey: .clock) ?? ""
        calendar = try container.decodeIfPresent(Bool.self, forKey: .calendar) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case before
        case after
        case minutes
        case clock
        case calendar
    }
}

/// Record target of one past Pomodoro: the source placeholder's line before
/// the record and how Bob resolved it (`placeholder`, `again`, `created`).
public struct PomodoroPastTarget: Codable, Equatable, Sendable {
    public let source: String
    public let line: Int

    public init(source: String = "", line: Int = 0) {
        self.source = source
        self.line = line
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case line
    }
}

/// Stack identity of one recorded past session, in typed order.
public struct PomodoroPastStack: Codable, Equatable, Sendable {
    public let index: Int
    public let size: Int
    /// Placement direction for grammar-14 segment suffixes. Older Bob omits it.
    public let pin: String?

    public init(index: Int = 0, size: Int = 0, pin: String? = nil) {
        self.index = index
        self.size = size
        self.pin = pin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        pin = try container.decodeIfPresent(String.self, forKey: .pin)
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case size
        case pin
    }
}

/// Bob's resolved segment for a grammar-14 past-Pomodoro placement. Older
/// Bob omits this object; missing fields inside an additive object remain nil.
public struct PomodoroPastSegment: Codable, Equatable, Sendable {
    public let kind: String
    public let index: Int?
    public let edge: String
    public let start: String
    public let end: String
    public let name: String?
    public let line: Int?

    public init(
        kind: String = "",
        index: Int? = nil,
        edge: String = "",
        start: String = "",
        end: String = "",
        name: String? = nil,
        line: Int? = nil
    ) {
        self.kind = kind
        self.index = index
        self.edge = edge
        self.start = start
        self.end = end
        self.name = name
        self.line = line
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        edge = try container.decodeIfPresent(String.self, forKey: .edge) ?? ""
        start = try container.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case index
        case edge
        case start
        case end
        case name
        case line
    }
}

/// Window one recorded past session occupies, half-open `[start, end)`.
/// An end of `0000` is midnight, rendered faithfully from Bob's window.
public struct PomodoroPastWindow: Codable, Equatable, Sendable {
    public let start: String
    public let end: String
    public let minutes: Int
    public let requestedMinutes: Int?
    public let cut: String?

    public init(
        start: String = "",
        end: String = "",
        minutes: Int = 0,
        requestedMinutes: Int? = nil,
        cut: String? = nil
    ) {
        self.start = start
        self.end = end
        self.minutes = minutes
        self.requestedMinutes = requestedMinutes
        self.cut = cut
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        requestedMinutes = try container.decodeIfPresent(Int.self, forKey: .requestedMinutes)
        cut = try container.decodeIfPresent(String.self, forKey: .cut)
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case minutes
        case requestedMinutes = "requested_minutes"
        case cut
    }
}

/// Recorded past session from `bob capture --format json`: the authoritative
/// past contract in `src/native/capture/output.rs`. The nested `close` uses
/// the existing `PomodoroCloseSummary` shape. Bob intentionally omits a
/// top-level `pomodoro_close` for this operation. Malformed optional past
/// metadata degrades to nil at the call site so older successes still decode.
public struct PomodoroPastSummary: Codable, Equatable, Sendable {
    public let raw: String
    public let name: String?
    public let target: PomodoroPastTarget
    public let blocks: Int
    public let repair: Bool
    public let stack: PomodoroPastStack
    public let segment: PomodoroPastSegment?
    public let anchor: String
    public let window: PomodoroPastWindow
    public let closedAt: String
    public let line: Int
    public let trims: [PomodoroPastTrim]
    public let close: PomodoroCloseSummary

    public init(
        raw: String = "",
        name: String? = nil,
        target: PomodoroPastTarget = PomodoroPastTarget(),
        blocks: Int = 5,
        repair: Bool = false,
        stack: PomodoroPastStack = PomodoroPastStack(),
        segment: PomodoroPastSegment? = nil,
        anchor: String = "",
        window: PomodoroPastWindow = PomodoroPastWindow(),
        closedAt: String = "",
        line: Int = 0,
        trims: [PomodoroPastTrim] = [],
        close: PomodoroCloseSummary = PomodoroCloseSummary(raw: "")
    ) {
        self.raw = raw
        self.name = name
        self.target = target
        self.blocks = blocks
        self.repair = repair
        self.stack = stack
        self.segment = segment
        self.anchor = anchor
        self.window = window
        self.closedAt = closedAt
        self.line = line
        self.trims = trims
        self.close = close
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
        target =
            (try? container.decodeIfPresent(
                PomodoroPastTarget.self,
                forKey: .target
            )) ?? PomodoroPastTarget()
        blocks = try container.decodeIfPresent(Int.self, forKey: .blocks) ?? 5
        repair = try container.decodeIfPresent(Bool.self, forKey: .repair) ?? false
        stack =
            (try? container.decodeIfPresent(
                PomodoroPastStack.self,
                forKey: .stack
            )) ?? PomodoroPastStack()
        segment = (try? container.decodeIfPresent(
            PomodoroPastSegment.self,
            forKey: .segment
        )) ?? nil
        anchor = try container.decodeIfPresent(String.self, forKey: .anchor) ?? ""
        window =
            (try? container.decodeIfPresent(
                PomodoroPastWindow.self,
                forKey: .window
            )) ?? PomodoroPastWindow()
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        trims = (try? container.decodeIfPresent(
            [PomodoroPastTrim].self,
            forKey: .trims
        )) ?? []
        close = try container.decode(PomodoroCloseSummary.self, forKey: .close)
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case name
        case target
        case blocks
        case repair
        case stack
        case segment
        case anchor
        case window
        case closedAt = "closed_at"
        case line
        case trims
        case close
    }
}

public struct CaptureSpan: Codable, Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let kind: String
    /// Slot index on additive `template_placeholder` and `template_field` spans.
    public let field: Int?
    /// Theme refs for `pomodoro_name` and `task_toggle_pomodoro_name`
    /// spans. Bob omits the array for every other span kind and older
    /// Bob omits it entirely; both decode as empty.

    public let themes: [CapturePomodoroThemeRef]
    /// Additive `cancels_source` on `relation_label` spans. Bob omits it
    /// when false, and older Bob omits it entirely; both decode as false.
    public let cancelsSource: Bool
    /// Additive `completes_source` on `relation_label` spans. Bob omits it
    /// when false, and older Bob omits it entirely; both decode as false.
    /// Never set alongside `cancelsSource`: one label carries at most one
    /// close effect.
    public let completesSource: Bool
    /// Additive `offers_source` cue on successor relation labels. Bob omits
    /// it when false, and older Bob omits it entirely.
    public let offersSource: Bool
    /// Additive `project_note` modifier (`"create"` or `"offer"`) that Bob puts
    /// on every span of a sealed project-note marker: route, separator, block
    /// ID, seal, and any placeholder standing in for a missing piece. Bob omits
    /// it on every other span, and older Bob omits it entirely; both decode as
    /// nil. A value this client does not know still decodes, so the marker
    /// keeps its wash even when the modifier is newer than the app.
    public let projectNote: String?
    /// Named `%` directive on a `directive` span: `clip`, `note`, `template`, or
    /// `listen`. A bare `%` is still a `directive` span but carries no value, and an
    /// unknown token (`%x`) does not either. A value this client does not know still
    /// decodes. Other span kinds and an older Bob omit it.
    public let directive: String?
    /// History count for `%c<N>` when N is at least 2, on a `directive` span. Bob omits it
    /// for `%c`, `%c1`, and every other span.
    public let count: Int?
    /// Decoded Gmail thread hex on a `gmail_url` span. Present when Bob
    /// decoded or already knew the thread; omitted for unresolvable or
    /// refused URLs and by older Bob.
    public let key: String?
    /// Saved-thread label on a `gmail_url` span. Present only when the
    /// thread is already saved (`verdict == "known"`); omitted otherwise
    /// and by older Bob.
    public let title: String?
    /// Offline verdict for a `gmail_url` span (`known` | `decoded` |
    /// `search` | `unresolved` | `refused`), plus an optional RFC 3339
    /// date hint. Omitted for every other span kind and by older Bob.
    public let gmail: CaptureGmailSpanMetadata?

    public init(
        start: Int,
        end: Int,
        kind: String,
        field: Int? = nil,
        themes: [CapturePomodoroThemeRef] = [],
        cancelsSource: Bool = false,
        completesSource: Bool = false,
        offersSource: Bool = false,
        projectNote: String? = nil,
        directive: String? = nil,
        count: Int? = nil,
        key: String? = nil,
        title: String? = nil,
        gmail: CaptureGmailSpanMetadata? = nil
    ) {
        self.start = start
        self.end = end
        self.kind = kind
        self.field = field
        self.themes = themes
        self.cancelsSource = cancelsSource
        self.completesSource = completesSource
        self.offersSource = offersSource
        self.projectNote = projectNote
        self.directive = directive
        self.count = count
        self.key = key
        self.title = title
        self.gmail = gmail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(Int.self, forKey: .start)
        end = try container.decode(Int.self, forKey: .end)
        kind = try container.decode(String.self, forKey: .kind)
        field = (try? container.decodeIfPresent(Int.self, forKey: .field)) ?? nil
        themes =
            (try? container.decodeIfPresent(
                [CapturePomodoroThemeRef].self,
                forKey: .themes
            )) ?? []
        cancelsSource = (try? container.decodeIfPresent(Bool.self, forKey: .cancelsSource)) ?? false
        completesSource = (try? container.decodeIfPresent(Bool.self, forKey: .completesSource)) ?? false
        offersSource = (try? container.decodeIfPresent(Bool.self, forKey: .offersSource)) ?? false
        projectNote = (try? container.decodeIfPresent(String.self, forKey: .projectNote)) ?? nil
        directive = (try? container.decodeIfPresent(String.self, forKey: .directive)) ?? nil
        count = (try? container.decodeIfPresent(Int.self, forKey: .count)) ?? nil
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? nil
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil
        gmail =
            (try? container.decodeIfPresent(CaptureGmailSpanMetadata.self, forKey: .gmail)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case kind
        case field
        case themes
        case cancelsSource = "cancels_source"
        case completesSource = "completes_source"
        case offersSource = "offers_source"
        case projectNote = "project_note"
        case directive
        case count
        case key
        case title
        case gmail
    }
}

/// Offline verdict Bob attaches to a `gmail_url` capture-parse span.
/// `verdict` is one of `known` | `decoded` | `search` | `unresolved` |
/// `refused`; `dateHint` is Bob's RFC 3339 thread-date hint, present only
/// when Bob decoded a thread id. Unknown verdict strings still decode so a
/// newer Bob never breaks the parse.
public struct CaptureGmailSpanMetadata: Codable, Equatable, Sendable {
    public let verdict: String
    public let dateHint: String?

    public init(verdict: String = "", dateHint: String? = nil) {
        self.verdict = verdict
        self.dateHint = dateHint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verdict = (try? container.decodeIfPresent(String.self, forKey: .verdict)) ?? ""
        dateHint = (try? container.decodeIfPresent(String.self, forKey: .dateHint)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case verdict
        case dateHint = "date_hint"
    }
}

/// One Gmail URL Bob found in a capture item's dry-run text. `message` is
/// the ready-made human line the item preview shows; a settled
/// `bob gmail peek` may replace it with the live subject and sender.
/// `threadID`, `note`, `link`, and `dateHint` are present per Bob's
/// verdict; unknown verdicts still decode so a newer Bob never breaks
/// the preview.
public struct CaptureGmailPreview: Codable, Equatable, Sendable {
    public let url: String
    public let verdict: String
    public let threadID: String?
    public let note: String?
    public let link: String?
    public let dateHint: String?
    public let message: String

    public init(
        url: String = "",
        verdict: String = "",
        threadID: String? = nil,
        note: String? = nil,
        link: String? = nil,
        dateHint: String? = nil,
        message: String = ""
    ) {
        self.url = url
        self.verdict = verdict
        self.threadID = threadID
        self.note = note
        self.link = link
        self.dateHint = dateHint
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = (try? container.decodeIfPresent(String.self, forKey: .url)) ?? ""
        verdict = (try? container.decodeIfPresent(String.self, forKey: .verdict)) ?? ""
        threadID = (try? container.decodeIfPresent(String.self, forKey: .threadID)) ?? nil
        note = (try? container.decodeIfPresent(String.self, forKey: .note)) ?? nil
        link = (try? container.decodeIfPresent(String.self, forKey: .link)) ?? nil
        dateHint = (try? container.decodeIfPresent(String.self, forKey: .dateHint)) ?? nil
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case verdict
        case threadID = "thread_id"
        case note
        case link
        case dateHint = "date_hint"
        case message
    }
}

public struct CaptureDiagnostic: Codable, Equatable {
    public let severity: String
    public let code: String
    public let message: String
    public let range: CaptureRange?
    /// Additive explicit rewrite Bob authors for merge-in diagnostics
    /// (`merge_in_extra_text`, `merge_in_arrow_spacing`,
    /// `merge_in_needs_new_task`). Omitted otherwise; malformed values
    /// degrade to nil so the diagnostic itself still decodes.
    public let rewrite: CaptureDiagnosticRewrite?

    public init(
        severity: String,
        code: String,
        message: String,
        range: CaptureRange? = nil,
        rewrite: CaptureDiagnosticRewrite? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.range = range
        self.rewrite = rewrite
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decode(String.self, forKey: .severity)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        // Bob serializes diagnostic ranges as a nullable `[start, end]` pair, while
        // older fixtures use the `{"start":..,"end":..}` object. Accept both so an
        // `invalid_pomodoro_start` diagnostic never breaks parse decoding.
        // `decodeIfPresent` returns an optional and `try?` adds a second layer, so
        // flatten (`?? nil`) before binding: `if let` unwraps only one layer.
        let objectRange: CaptureRange? =
            (try? container.decodeIfPresent(CaptureRange.self, forKey: .range)) ?? nil
        if let objectRange {
            range = objectRange
        } else {
            let pairRange: [Int]? =
                (try? container.decodeIfPresent([Int].self, forKey: .range)) ?? nil
            if let pairRange, pairRange.count == 2 {
                range = CaptureRange(start: pairRange[0], end: pairRange[1])
            } else {
                range = nil
            }
        }
        rewrite =
            (try? container.decodeIfPresent(CaptureDiagnosticRewrite.self, forKey: .rewrite)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case severity
        case code
        case message
        case range
        case rewrite
    }
}

public struct CaptureRange: Codable, Equatable, Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

/// Validated additive `@<route>:<block-id>[#<name>]=<X>` start suffix from
/// `bob capture-parse`, and the whole-item `=`/`=<X>` start token's spec: the
/// raw `<X>` text plus its 5-minute duration/offset units. Omitted for every
/// older marker shape, so decoding stays backward compatible.
public struct PomodoroStartSpec: Codable, Equatable, Sendable {
    public let raw: String
    public let durationUnits: Int
    public let offsetUnits: Int
    /// The typed `~<K>` drop list, ascending. Omitted (decodes as empty) when
    /// no drop list was typed or the Bob build predates start drops.
    public let drop: [Int]

    public init(
        raw: String, durationUnits: Int = 0, offsetUnits: Int = 0, drop: [Int] = []
    ) {
        self.raw = raw
        self.durationUnits = durationUnits
        self.offsetUnits = offsetUnits
        self.drop = drop
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        durationUnits = try container.decodeIfPresent(Int.self, forKey: .durationUnits) ?? 0
        offsetUnits = try container.decodeIfPresent(Int.self, forKey: .offsetUnits) ?? 0
        drop = try container.decodeIfPresent([Int].self, forKey: .drop) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case durationUnits = "duration_units"
        case offsetUnits = "offset_units"
        case drop
    }
}

/// One queued Task Link row on a started Pomodoro, following the close row's
/// explicit-null convention: unresolved rows carry nil text/symbols and a
/// `warning` instead of failing the start. Every field decodes tolerantly so a
/// partial object still yields a (neutral, unresolved) row instead of failing
/// the whole capture.
public struct PomodoroStartTask: Codable, Equatable, Sendable {
    public let blockLink: String
    public let embedded: Bool
    public let ledgerLine: Int
    public let resolved: Bool
    public let relativeTarget: String?
    public let blockID: String
    public let text: String?
    public let statusSymbol: String?
    public let statusName: String?
    public let warning: String?
    /// The 1-based lineup number Bob assigned this row, or nil for unnumbered
    /// rows (older Bob). Dropped rows carry their own lineup number too.
    public let index: Int?
    /// Non-blank descendant lines removed with a dropped link. Omitted
    /// (decodes as zero) on kept rows and when there were none.
    public let nestedLines: Int

    public init(
        blockLink: String,
        embedded: Bool = false,
        ledgerLine: Int = 0,
        resolved: Bool = false,
        relativeTarget: String? = nil,
        blockID: String = "",
        text: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        warning: String? = nil,
        index: Int? = nil,
        nestedLines: Int = 0
    ) {
        self.blockLink = blockLink
        self.embedded = embedded
        self.ledgerLine = ledgerLine
        self.resolved = resolved
        self.relativeTarget = relativeTarget
        self.blockID = blockID
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.warning = warning
        self.index = index
        self.nestedLines = nestedLines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockLink = try container.decodeIfPresent(String.self, forKey: .blockLink) ?? ""
        embedded = try container.decodeIfPresent(Bool.self, forKey: .embedded) ?? false
        ledgerLine = try container.decodeIfPresent(Int.self, forKey: .ledgerLine) ?? 0
        resolved = try container.decodeIfPresent(Bool.self, forKey: .resolved) ?? false
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text)
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
        warning = try container.decodeIfPresent(String.self, forKey: .warning)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        nestedLines = try container.decodeIfPresent(Int.self, forKey: .nestedLines) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case blockLink = "block_link"
        case embedded
        case ledgerLine = "ledger_line"
        case resolved
        case relativeTarget = "relative_target"
        case blockID = "block_id"
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case warning
        case index
        case nestedLines = "nested_lines"
    }
}

/// The running session in the pre-image of a `=` override: its name (omitted
/// when unnamed), 1-based ledger line, and `HHMM` range plus duration.
/// `overdue` is true when `now` is at or after that session's end; omitted
/// (decodes as false) when false or on older Bob. Every field decodes
/// tolerantly so a partial object still previews instead of failing the
/// whole capture.
public struct PomodoroStartPrevious: Codable, Equatable, Sendable {
    public let pomodoroName: String?
    public let pomodoroLine: Int
    public let start: String
    public let end: String
    public let durationMinutes: Int
    public let timeRange: String
    public let overdue: Bool
    /// Derived R9 homes for an unnamed running session (surfaces phase
    /// adds it; named sessions omit it). Older bob omits it; decode as nil.
    public let homes: CaptureAgendaHomes?

    public init(
        pomodoroName: String? = nil,
        pomodoroLine: Int = 0,
        start: String = "",
        end: String = "",
        durationMinutes: Int = 0,
        timeRange: String = "",
        overdue: Bool = false,
        homes: CaptureAgendaHomes? = nil
    ) {
        self.pomodoroName = pomodoroName
        self.pomodoroLine = pomodoroLine
        self.start = start
        self.end = end
        self.durationMinutes = durationMinutes
        self.timeRange = timeRange
        self.overdue = overdue
        self.homes = homes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        pomodoroLine = try container.decodeIfPresent(Int.self, forKey: .pomodoroLine) ?? 0
        start = try container.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange) ?? ""
        overdue = try container.decodeIfPresent(Bool.self, forKey: .overdue) ?? false
        homes = try container.decodeIfPresent(CaptureAgendaHomes.self, forKey: .homes)
    }

    private enum CodingKeys: String, CodingKey {
        case pomodoroName = "pomodoro_name"
        case pomodoroLine = "pomodoro_line"
        case start
        case end
        case durationMinutes = "duration_minutes"
        case timeRange = "time_range"
        case overdue
        case homes
    }
}

/// The swapped-out session in the post-image of a `=#name` swap: its name,
/// 1-based ledger line, final entry line, direct-child Task Link count, and
/// whether it kept stand-alone notes. Decodes tolerantly like its sibling.
public struct PomodoroStartDemoted: Codable, Equatable, Sendable {
    public let pomodoroName: String?
    public let pomodoroLine: Int
    public let entryLine: String
    public let taskLinks: Int
    public let hasNotes: Bool
    /// Derived R9 homes for an unnamed demoted session. Older bob omits it.
    public let homes: CaptureAgendaHomes?

    public init(
        pomodoroName: String? = nil,
        pomodoroLine: Int = 0,
        entryLine: String = "",
        taskLinks: Int = 0,
        hasNotes: Bool = false,
        homes: CaptureAgendaHomes? = nil
    ) {
        self.pomodoroName = pomodoroName
        self.pomodoroLine = pomodoroLine
        self.entryLine = entryLine
        self.taskLinks = taskLinks
        self.hasNotes = hasNotes
        self.homes = homes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        pomodoroLine = try container.decodeIfPresent(Int.self, forKey: .pomodoroLine) ?? 0
        entryLine = try container.decodeIfPresent(String.self, forKey: .entryLine) ?? ""
        taskLinks = try container.decodeIfPresent(Int.self, forKey: .taskLinks) ?? 0
        hasNotes = try container.decodeIfPresent(Bool.self, forKey: .hasNotes) ?? false
        homes = try container.decodeIfPresent(CaptureAgendaHomes.self, forKey: .homes)
    }

    private enum CodingKeys: String, CodingKey {
        case pomodoroName = "pomodoro_name"
        case pomodoroLine = "pomodoro_line"
        case entryLine = "entry_line"
        case taskLinks = "task_links"
        case hasNotes = "has_notes"
        case homes
    }
}

/// Override outcome for a whole-item `=` start that restarted or swapped a
/// running session (`restart`, `swap`). Older Bob may still send `"start"`
/// when nothing was running; the presentation treats that as a plain start.
/// `ledger` is `kept` for a swap that took over the running ledger
/// byte-for-byte, `fresh` otherwise. `previous` is the running session in
/// the pre-image; `demoted` is swaps only. `closeFirst` is Bob's draft
/// spelling that closes the running session first (`x =`, `x =#bugs`);
/// omitted (decodes as nil) on older Bob. Decodes tolerantly; the summary
/// keeps the three known actions so an older `"start"` still previews.
public struct PomodoroStartOverride: Codable, Equatable, Sendable {
    public let action: String
    public let ledger: String
    public let previous: PomodoroStartPrevious?
    public let demoted: PomodoroStartDemoted?
    public let closeFirst: String?

    public init(
        action: String = "",
        ledger: String = "",
        previous: PomodoroStartPrevious? = nil,
        demoted: PomodoroStartDemoted? = nil,
        closeFirst: String? = nil
    ) {
        self.action = action
        self.ledger = ledger
        self.previous = previous
        self.demoted = demoted
        self.closeFirst = closeFirst
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
        ledger = try container.decodeIfPresent(String.self, forKey: .ledger) ?? ""
        previous = try container.decodeIfPresent(PomodoroStartPrevious.self, forKey: .previous)
        demoted = try container.decodeIfPresent(PomodoroStartDemoted.self, forKey: .demoted)
        closeFirst = try container.decodeIfPresent(String.self, forKey: .closeFirst)
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case ledger
        case previous
        case demoted
        case closeFirst = "close_first"
    }
}

/// One Event Task used to form an event run for a MEET start.
public struct PomodoroEventRunEvent: Codable, Equatable, Sendable {
    public let index: Int
    public let title: String
    public let timeRange: String
    public let line: Int
    public let blockID: String?
    public let offClock: Bool
    /// The event's pre/post-event buffer; nil on an older bob and when
    /// the event carries none. A malformed buffer decodes as nil.
    public let buffer: CaptureEventBuffer?

    public init(
        index: Int = 0,
        title: String = "",
        timeRange: String = "",
        line: Int = 0,
        blockID: String? = nil,
        offClock: Bool = false,
        buffer: CaptureEventBuffer? = nil
    ) {
        self.index = index
        self.title = title
        self.timeRange = timeRange
        self.line = line
        self.blockID = blockID
        self.offClock = offClock
        self.buffer = buffer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        offClock = try container.decodeIfPresent(Bool.self, forKey: .offClock)
            ?? legacy.decodeIfPresent(Bool.self, forKey: .untracked) ?? false
        buffer = (try? container.decodeIfPresent(CaptureEventBuffer.self, forKey: .buffer)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case title
        case timeRange = "time_range"
        case line
        case blockID = "block_id"
        case offClock = "off_clock"
        case buffer
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case untracked
    }
}

/// The calendar run Bob used to plan a MEET session. The app presents these
/// returned facts and never resolves event links or calculates the span.
public struct PomodoroEventRun: Codable, Equatable, Sendable {
    public let timeRange: String
    public let start: String
    public let end: String
    public let offClock: Bool
    public let source: String
    public let events: [PomodoroEventRunEvent]

    public init(
        timeRange: String = "",
        start: String = "",
        end: String = "",
        offClock: Bool = false,
        source: String = "",
        events: [PomodoroEventRunEvent] = []
    ) {
        self.timeRange = timeRange
        self.start = start
        self.end = end
        self.offClock = offClock
        self.source = source
        self.events = events
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange) ?? ""
        start = try container.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        offClock = try container.decodeIfPresent(Bool.self, forKey: .offClock)
            ?? legacy.decodeIfPresent(Bool.self, forKey: .untracked) ?? false
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        events = try container.decodeIfPresent([PomodoroEventRunEvent].self, forKey: .events) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case timeRange = "time_range"
        case start
        case end
        case offClock = "off_clock"
        case source
        case events
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case untracked
    }
}

/// Event Task details attached to a non-MEET session that runs past it.
public struct PomodoroEventConflictEvent: Codable, Equatable, Sendable {
    public let title: String
    public let timeRange: String
    public let line: Int
    public let offClock: Bool
    /// The event's pre/post-event buffer; nil on an older bob and when
    /// the event carries none. A malformed buffer decodes as nil.
    public let buffer: CaptureEventBuffer?

    public init(
        title: String = "",
        timeRange: String = "",
        line: Int = 0,
        offClock: Bool = false,
        buffer: CaptureEventBuffer? = nil
    ) {
        self.title = title
        self.timeRange = timeRange
        self.line = line
        self.offClock = offClock
        self.buffer = buffer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        offClock = try container.decodeIfPresent(Bool.self, forKey: .offClock)
            ?? legacy.decodeIfPresent(Bool.self, forKey: .untracked) ?? false
        buffer = (try? container.decodeIfPresent(CaptureEventBuffer.self, forKey: .buffer)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case timeRange = "time_range"
        case line
        case offClock = "off_clock"
        case buffer
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case untracked
    }
}

public struct PomodoroEventConflict: Codable, Equatable, Sendable {
    public let event: PomodoroEventConflictEvent
    public let overlapMinutes: Int
    public let more: Int
    public let fit: String?
    /// Which buffered side the overlap sits wholly inside (`before` /
    /// `after`); nil when the overlap reaches the meeting or the event
    /// has no buffer. A malformed value decodes as nil.
    public let bufferPart: CaptureBufferPart?

    public init(
        event: PomodoroEventConflictEvent = PomodoroEventConflictEvent(),
        overlapMinutes: Int = 0,
        more: Int = 0,
        fit: String? = nil,
        bufferPart: CaptureBufferPart? = nil
    ) {
        self.event = event
        self.overlapMinutes = overlapMinutes
        self.more = more
        self.fit = fit
        self.bufferPart = bufferPart
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event =
            try container.decodeIfPresent(
                PomodoroEventConflictEvent.self,
                forKey: .event
            )
            ?? PomodoroEventConflictEvent()
        overlapMinutes = try container.decodeIfPresent(Int.self, forKey: .overlapMinutes) ?? 0
        more = try container.decodeIfPresent(Int.self, forKey: .more) ?? 0
        fit = try container.decodeIfPresent(String.self, forKey: .fit)
        bufferPart =
            (try? container.decodeIfPresent(CaptureBufferPart.self, forKey: .bufferPart)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case event
        case overlapMinutes = "overlap_minutes"
        case more
        case fit
        case bufferPart = "buffer_part"
    }
}

/// Resolved atomic start from `bob capture --format json`: the 5-minute-rounded
/// `start`/`end` clock times, duration, destination ledger line, and whether Bob
/// created the entry. Omitted when the draft carries no `=<X>` suffix, so older
/// bob binaries decode as nil. Every field decodes tolerantly (strings default
/// to empty, numbers to zero) so a partial object still previews instead of
/// failing the whole capture. `tasks` is present — possibly empty — only for a
/// whole-item `=`/`=<X>` start; link and task starts omit it and decode as nil.
public struct PomodoroStartSummary: Codable, Equatable, Sendable {
    public let start: String
    public let end: String
    public let durationMinutes: Int
    public let offsetUnits: Int
    public let pomodoroName: String?
    public let pomodoroLine: Int
    public let createdPomodoro: Bool
    public let timeRange: String
    public let tasks: [PomodoroStartTask]?
    /// The typed `~<K>` drop list, ascending. Omitted (decodes as empty) when
    /// no drop list was typed or the Bob build predates start drops.
    public let drop: [Int]
    /// Rows removed by `~<K>`, in lineup order. Omitted (decodes as empty)
    /// when nothing was dropped.
    public let dropped: [PomodoroStartTask]
    /// Override outcome for a whole-item `=` start that restarted or swapped
    /// a running session. Omitted (decodes as nil) on a plain start and on
    /// older Bob builds; an unknown action decodes as nil so a future
    /// outcome previews as a plain start instead of failing the whole capture.
    public let overrideOutcome: PomodoroStartOverride?
    /// Additive calendar context Bob used to choose this MEET span.
    public let eventRun: PomodoroEventRun?
    /// Additive conflict details for a non-MEET start that crosses an event.
    public let eventConflict: PomodoroEventConflict?

    public init(
        start: String,
        end: String,
        durationMinutes: Int,
        offsetUnits: Int,
        pomodoroName: String? = nil,
        pomodoroLine: Int,
        createdPomodoro: Bool,
        timeRange: String,
        tasks: [PomodoroStartTask]? = nil,
        drop: [Int] = [],
        dropped: [PomodoroStartTask] = [],
        overrideOutcome: PomodoroStartOverride? = nil,
        eventRun: PomodoroEventRun? = nil,
        eventConflict: PomodoroEventConflict? = nil
    ) {
        self.start = start
        self.end = end
        self.durationMinutes = durationMinutes
        self.offsetUnits = offsetUnits
        self.pomodoroName = pomodoroName
        self.pomodoroLine = pomodoroLine
        self.createdPomodoro = createdPomodoro
        self.timeRange = timeRange
        self.tasks = tasks
        self.drop = drop
        self.dropped = dropped
        self.overrideOutcome = overrideOutcome
        self.eventRun = eventRun
        self.eventConflict = eventConflict
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        offsetUnits = try container.decodeIfPresent(Int.self, forKey: .offsetUnits) ?? 0
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        pomodoroLine = try container.decodeIfPresent(Int.self, forKey: .pomodoroLine) ?? 0
        createdPomodoro = try container.decodeIfPresent(Bool.self, forKey: .createdPomodoro) ?? false
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange) ?? ""
        tasks = try container.decodeIfPresent([PomodoroStartTask].self, forKey: .tasks)
        drop = try container.decodeIfPresent([Int].self, forKey: .drop) ?? []
        dropped = try container.decodeIfPresent([PomodoroStartTask].self, forKey: .dropped) ?? []
        let rawOverride = try container.decodeIfPresent(
            PomodoroStartOverride.self, forKey: .overrideOutcome)
        if let rawOverride, ["restart", "swap", "start"].contains(rawOverride.action) {
            overrideOutcome = rawOverride
        } else {
            overrideOutcome = nil
        }
        eventRun = (try? container.decodeIfPresent(PomodoroEventRun.self, forKey: .eventRun)) ?? nil
        eventConflict =
            (try? container.decodeIfPresent(
                PomodoroEventConflict.self,
                forKey: .eventConflict
            )) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case durationMinutes = "duration_minutes"
        case offsetUnits = "offset_units"
        case pomodoroName = "pomodoro_name"
        case pomodoroLine = "pomodoro_line"
        case createdPomodoro = "created_pomodoro"
        case timeRange = "time_range"
        case tasks
        case drop
        case dropped
        case overrideOutcome = "override"
        case eventRun = "event_run"
        case eventConflict = "event_conflict"
    }
}

/// Validated whole-item `+N`/`-N` adjustment spec from `bob capture-parse`: the
/// trimmed signed token plus its sign and 5-minute unit count (`+5` is five
/// units, 25 minutes). Omitted for every non-adjustment mode, so decoding stays
/// backward compatible.
public struct PomodoroAdjustSpec: Codable, Equatable, Sendable {
    public let raw: String
    public let plus: Bool
    public let units: Int

    public init(raw: String, plus: Bool, units: Int) {
        self.raw = raw
        self.plus = plus
        self.units = units
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case plus
        case units
    }
}

/// Resolved duration adjustment from `bob capture --format json`: the requested
/// direction/units, the actual applied delta (which differs when subtraction
/// clamps at zero), before/after start/end/duration, destination ledger line,
/// and rendered new range. Omitted when the draft carries no adjustment, so
/// older bob binaries decode as nil.
public struct PomodoroAdjustSummary: Codable, Equatable, Sendable {
    public let direction: String
    public let requestedUnits: Int
    public let requestedMinutes: Int
    public let deltaMinutes: Int
    public let beforeStart: String
    public let beforeEnd: String
    public let beforeDurationMinutes: Int
    public let afterStart: String
    public let afterEnd: String
    public let afterDurationMinutes: Int
    public let pomodoroLine: Int
    public let pomodoroName: String?
    public let timeRange: String
    public let clamped: Bool
    public let eventConflict: PomodoroEventConflict?

    public init(
        direction: String,
        requestedUnits: Int,
        requestedMinutes: Int,
        deltaMinutes: Int,
        beforeStart: String,
        beforeEnd: String,
        beforeDurationMinutes: Int,
        afterStart: String,
        afterEnd: String,
        afterDurationMinutes: Int,
        pomodoroLine: Int,
        pomodoroName: String? = nil,
        timeRange: String,
        clamped: Bool,
        eventConflict: PomodoroEventConflict? = nil
    ) {
        self.direction = direction
        self.requestedUnits = requestedUnits
        self.requestedMinutes = requestedMinutes
        self.deltaMinutes = deltaMinutes
        self.beforeStart = beforeStart
        self.beforeEnd = beforeEnd
        self.beforeDurationMinutes = beforeDurationMinutes
        self.afterStart = afterStart
        self.afterEnd = afterEnd
        self.afterDurationMinutes = afterDurationMinutes
        self.pomodoroLine = pomodoroLine
        self.pomodoroName = pomodoroName
        self.timeRange = timeRange
        self.clamped = clamped
        self.eventConflict = eventConflict
    }

    private enum CodingKeys: String, CodingKey {
        case direction
        case requestedUnits = "requested_units"
        case requestedMinutes = "requested_minutes"
        case deltaMinutes = "delta_minutes"
        case beforeStart = "before_start"
        case beforeEnd = "before_end"
        case beforeDurationMinutes = "before_duration_minutes"
        case afterStart = "after_start"
        case afterEnd = "after_end"
        case afterDurationMinutes = "after_duration_minutes"
        case pomodoroLine = "pomodoro_line"
        case pomodoroName = "pomodoro_name"
        case timeRange = "time_range"
        case clamped
        case eventConflict = "event_conflict"
    }
}

/// Validated whole-item `++N`/`--N` shift spec from `bob capture-parse`: the
/// trimmed doubled-sign token plus its direction and 5-minute unit count
/// (`++3` is three units, 15 minutes). Omitted for every non-shift mode, so
/// decoding stays backward compatible. Older Bob output decodes as nil.
public struct PomodoroShiftSpec: Codable, Equatable, Sendable {
    public let raw: String
    public let later: Bool
    public let units: Int

    public init(raw: String, later: Bool, units: Int) {
        self.raw = raw
        self.later = later
        self.units = units
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case later
        case units
    }
}

/// Resolved whole-session shift from `bob capture --format json`: the requested
/// direction/units, the signed applied delta, before/after start/end, unchanged
/// duration, destination ledger line, and rendered new range. Omitted when the
/// draft carries no shift, so older bob binaries decode as nil.
public struct PomodoroShiftSummary: Codable, Equatable, Sendable {
    public let direction: String
    public let requestedUnits: Int
    public let deltaMinutes: Int
    public let beforeStart: String
    public let beforeEnd: String
    public let afterStart: String
    public let afterEnd: String
    public let durationMinutes: Int
    public let pomodoroLine: Int
    public let pomodoroName: String?
    public let timeRange: String
    public let eventConflict: PomodoroEventConflict?

    public init(
        direction: String,
        requestedUnits: Int,
        deltaMinutes: Int,
        beforeStart: String,
        beforeEnd: String,
        afterStart: String,
        afterEnd: String,
        durationMinutes: Int,
        pomodoroLine: Int,
        pomodoroName: String? = nil,
        timeRange: String,
        eventConflict: PomodoroEventConflict? = nil
    ) {
        self.direction = direction
        self.requestedUnits = requestedUnits
        self.deltaMinutes = deltaMinutes
        self.beforeStart = beforeStart
        self.beforeEnd = beforeEnd
        self.afterStart = afterStart
        self.afterEnd = afterEnd
        self.durationMinutes = durationMinutes
        self.pomodoroLine = pomodoroLine
        self.pomodoroName = pomodoroName
        self.timeRange = timeRange
        self.eventConflict = eventConflict
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direction = try container.decodeIfPresent(String.self, forKey: .direction) ?? ""
        requestedUnits = try container.decodeIfPresent(Int.self, forKey: .requestedUnits) ?? 0
        deltaMinutes = try container.decodeIfPresent(Int.self, forKey: .deltaMinutes) ?? 0
        beforeStart = try container.decodeIfPresent(String.self, forKey: .beforeStart) ?? ""
        beforeEnd = try container.decodeIfPresent(String.self, forKey: .beforeEnd) ?? ""
        afterStart = try container.decodeIfPresent(String.self, forKey: .afterStart) ?? ""
        afterEnd = try container.decodeIfPresent(String.self, forKey: .afterEnd) ?? ""
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        pomodoroLine = try container.decodeIfPresent(Int.self, forKey: .pomodoroLine) ?? 0
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange) ?? ""
        eventConflict =
            (try? container.decodeIfPresent(
                PomodoroEventConflict.self,
                forKey: .eventConflict
            )) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case direction
        case requestedUnits = "requested_units"
        case deltaMinutes = "delta_minutes"
        case beforeStart = "before_start"
        case beforeEnd = "before_end"
        case afterStart = "after_start"
        case afterEnd = "after_end"
        case durationMinutes = "duration_minutes"
        case pomodoroLine = "pomodoro_line"
        case pomodoroName = "pomodoro_name"
        case timeRange = "time_range"
        case eventConflict = "event_conflict"
    }
}

/// One Pomodoro block in its final after-state from Bob's additive
/// batch-level `pomodoro_blocks` key: a Pomodoro the capture touches,
/// creates, or reports, with every line of its block and a per-line diff
/// against the pre-capture ledger. `line` is the 1-based headline line in
/// the final staged day file; `created` marks an entry that did not exist
/// before the batch; `roles` is informational first-touch order the app
/// never depends on. Every field decodes tolerantly so a partial object
/// still yields a block instead of failing the whole capture.
public struct CapturePomodoroBlock: Codable, Equatable, Sendable {
    public let relativeTarget: String
    public let line: Int
    public let name: String?
    public let timeRange: String?
    public let status: CapturePomodoroBlockStatus
    public let created: Bool
    /// True when capture deleted the whole session after consuming its last
    /// task link. Older Bob omits this additive field.
    public let removed: Bool
    public let roles: [String]
    public let lines: [CapturePomodoroBlockLine]

    public init(
        relativeTarget: String,
        line: Int,
        name: String? = nil,
        timeRange: String? = nil,
        status: CapturePomodoroBlockStatus = .other,
        created: Bool = false,
        removed: Bool = false,
        roles: [String] = [],
        lines: [CapturePomodoroBlockLine] = []
    ) {
        self.relativeTarget = relativeTarget
        self.line = line
        self.name = name
        self.timeRange = timeRange
        self.status = status
        self.created = created
        self.removed = removed
        self.roles = roles
        self.lines = lines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        status =
            try container.decodeIfPresent(
                CapturePomodoroBlockStatus.self,
                forKey: .status
            ) ?? .other
        created = try container.decodeIfPresent(Bool.self, forKey: .created) ?? false
        removed = (try? container.decodeIfPresent(Bool.self, forKey: .removed)) ?? false
        roles = try container.decodeIfPresent([String].self, forKey: .roles) ?? []
        lines =
            try container.decodeIfPresent(
                [CapturePomodoroBlockLine].self,
                forKey: .lines
            ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case relativeTarget = "relative_target"
        case line
        case name
        case timeRange = "time_range"
        case status
        case created
        case removed
        case roles
        case lines
    }
}

/// Whether Bob's Pomodoro entry is open with a time range (`running`), open
/// without one (`queued`), or done (`completed`). Unknown values decode to
/// `.other` so a newer Bob never breaks the panel.
public enum CapturePomodoroBlockStatus: String, Equatable, Sendable {
    case running
    case queued
    case completed
    case other

    public init(wireValue: String?) {
        self = (wireValue.flatMap(CapturePomodoroBlockStatus.init(rawValue:)) ?? .other)
    }
}

extension CapturePomodoroBlockStatus: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(String.self)
        self.init(wireValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One verbatim line of a Pomodoro block: `text` never carries a
/// terminator, and `before` holds the old text only on `changed` rows.
/// Unknown `change` values decode to `.unchanged` so a newer Bob never
/// breaks the panel.
public struct CapturePomodoroBlockLine: Codable, Equatable, Sendable {
    public let text: String
    public let depth: Int
    public let change: CapturePomodoroBlockChange
    public let before: String?
    /// `"unblocked"` on added lines that are surviving successor links
    /// (`docs/task-dependencies.md` §12.5). Older Bob omits it; a malformed
    /// value decodes as nil so one bad line cannot wipe every block.
    public let reason: String?
    /// Additive merge origin: `"<relative_path>#^<block_id>"` naming the
    /// merge source this row landed under. Present only on rows a `<` or
    /// `>` merge in this capture wrote; omitted elsewhere. Older Bob omits
    /// it entirely.
    public let origin: String?

    public init(
        text: String,
        depth: Int = 0,
        change: CapturePomodoroBlockChange = .unchanged,
        before: String? = nil,
        reason: String? = nil,
        origin: String? = nil
    ) {
        self.text = text
        self.depth = depth
        self.change = change
        self.before = before
        self.reason = reason
        self.origin = origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        depth = try container.decodeIfPresent(Int.self, forKey: .depth) ?? 0
        change =
            try container.decodeIfPresent(
                CapturePomodoroBlockChange.self,
                forKey: .change
            ) ?? .unchanged
        before = try container.decodeIfPresent(String.self, forKey: .before)
        reason = (try? container.decodeIfPresent(String.self, forKey: .reason)) ?? nil
        origin = (try? container.decodeIfPresent(String.self, forKey: .origin)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case depth
        case change
        case before
        case reason
        case origin
    }
}

/// How a block line differs from the pre-capture ledger: `changed` rows
/// carry the old text in `before`, and removed lines are interleaved where
/// they used to be. Unknown values decode to `.unchanged`.
public enum CapturePomodoroBlockChange: String, Equatable, Sendable {
    case unchanged
    case added
    case removed
    case changed

    public init(wireValue: String?) {
        self = (wireValue.flatMap(CapturePomodoroBlockChange.init(rawValue:)) ?? .unchanged)
    }
}

extension CapturePomodoroBlockChange: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(String.self)
        self.init(wireValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Neutral alias for one verbatim line of any batch-level block diff, so new
/// block kinds share the Pomodoro line shape without a Pomodoro name.
public typealias CaptureBlockLine = CapturePomodoroBlockLine

/// Source locator Bob returns for a task moved by a capture transfer.
public struct CaptureTaskBlockMovedFrom: Codable, Equatable, Sendable {
    public let relativeTarget: String
    public let line: Int

    public init(relativeTarget: String = "", line: Int = 0) {
        self.relativeTarget = relativeTarget
        self.line = line
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativeTarget = (try? container.decode(String.self, forKey: .relativeTarget)) ?? ""
        line = (try? container.decode(Int.self, forKey: .line)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case relativeTarget = "relative_target"
        case line
    }
}

/// Batch-level `task_blocks` entry: a parent task a sub-bullet capture wrote
/// under, in its final after-state, with every line of its block and a
/// per-line cumulative diff against the note before the capture. `line` is
/// the 1-based task line in the final staged note; `blockID` is the parent's
/// trailing block ID, nil when it has none (a picker task-ref parent);
/// `created` marks a parent that did not exist before the batch (every row
/// then reads `added`); `roles` is informational first-touch order the app
/// never depends on. Every field decodes tolerantly so a partial object
/// still yields a block instead of failing the whole capture.
public struct CaptureTaskBlock: Codable, Equatable, Sendable {
    public let relativeTarget: String
    public let route: String
    public let line: Int
    public let blockID: String?
    public let text: String
    public let statusSymbol: String
    public let statusName: String
    public let created: Bool
    public let roles: [String]
    public let lines: [CaptureBlockLine]
    /// Bob's source locator for a transfer move. Older Bob omits it.
    public let movedFrom: CaptureTaskBlockMovedFrom?

    /// Bob's additive task-block role for relation successor changes.
    public var hasRelationSuccessorRole: Bool { roles.contains("relation_successor") }

    /// Transfer roles must keep Bob's first-touch order in the landing area.
    public var hasTransferRole: Bool {
        roles.contains("merge_target") || roles.contains("merge_source") || roles.contains("moved")
    }

    public init(
        relativeTarget: String,
        route: String,
        line: Int,
        blockID: String? = nil,
        text: String = "",
        statusSymbol: String = "",
        statusName: String = "",
        created: Bool = false,
        roles: [String] = [],
        lines: [CaptureBlockLine] = [],
        movedFrom: CaptureTaskBlockMovedFrom? = nil
    ) {
        self.relativeTarget = relativeTarget
        self.route = route
        self.line = line
        self.blockID = blockID
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.created = created
        self.roles = roles
        self.lines = lines
        self.movedFrom = movedFrom
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget) ?? ""
        route = try container.decodeIfPresent(String.self, forKey: .route) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol) ?? ""
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName) ?? ""
        created = try container.decodeIfPresent(Bool.self, forKey: .created) ?? false
        roles = try container.decodeIfPresent([String].self, forKey: .roles) ?? []
        lines =
            try container.decodeIfPresent(
                [CaptureBlockLine].self,
                forKey: .lines
            ) ?? []
        movedFrom =
            (try? container.decodeIfPresent(
                CaptureTaskBlockMovedFrom.self,
                forKey: .movedFrom
            )) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case relativeTarget = "relative_target"
        case route
        case line
        case blockID = "block_id"
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case created
        case roles
        case lines
        case movedFrom = "moved_from"
    }
}

/// Batch-level section target from a capture merge. Its lines are Bob's exact
/// section after-image and diff, shared with task and Pomodoro block rows.
public struct CaptureSectionBlock: Codable, Equatable, Sendable {
    public let relativeTarget: String
    public let route: String
    public let line: Int
    public let heading: String
    public let created: Bool
    public let roles: [String]
    public let lines: [CaptureBlockLine]

    public init(
        relativeTarget: String = "",
        route: String = "",
        line: Int = 0,
        heading: String = "",
        created: Bool = false,
        roles: [String] = [],
        lines: [CaptureBlockLine] = []
    ) {
        self.relativeTarget = relativeTarget
        self.route = route
        self.line = line
        self.heading = heading
        self.created = created
        self.roles = roles
        self.lines = lines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativeTarget = (try? container.decode(String.self, forKey: .relativeTarget)) ?? ""
        route = (try? container.decode(String.self, forKey: .route)) ?? ""
        line = (try? container.decode(Int.self, forKey: .line)) ?? 0
        heading = (try? container.decode(String.self, forKey: .heading)) ?? ""
        created = (try? container.decode(Bool.self, forKey: .created)) ?? false
        roles = (try? container.decode([String].self, forKey: .roles)) ?? []
        lines = (try? container.decode([CaptureBlockLine].self, forKey: .lines)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case relativeTarget = "relative_target"
        case route
        case line
        case heading
        case created
        case roles
        case lines
    }
}

/// One timing value from Bob's additive `pomodoro_close` result. Every field
/// decodes tolerantly so a partial or older-bob object still yields a row.
public struct PomodoroCloseTiming: Codable, Equatable, Sendable {
    public let start: String
    public let end: String
    public let durationMinutes: Int
    public let timeRange: String

    public init(
        start: String,
        end: String,
        durationMinutes: Int,
        timeRange: String
    ) {
        self.start = start
        self.end = end
        self.durationMinutes = durationMinutes
        self.timeRange = timeRange
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case durationMinutes = "duration_minutes"
        case timeRange = "time_range"
    }
}

/// One numbered Task Link in Bob's `pomodoro_close.task_links` lineup: the
/// 1-based `index` shown as the row badge, the pre-image `ledgerLine`, the
/// link's pre-selection `marker` (`plain`, `deferred`, `embedded`), the
/// `outcome` the selection gives it (`in_progress`, `deferred`, `complete`),
/// and the `source` saying why (`ledger`, `listed`, `unlisted`). Every field
/// decodes tolerantly so older-bob objects without `task_links` still decode;
/// unknown marker/outcome/source strings are preserved verbatim and degrade
/// to neutral presentation.
public struct PomodoroCloseTaskLink: Codable, Equatable, Sendable {
    public let index: Int
    public let ledgerLine: Int
    public let blockLink: String
    public let blockID: String
    public let marker: String
    public let outcome: String
    public let source: String

    public init(
        index: Int,
        ledgerLine: Int = 0,
        blockLink: String = "",
        blockID: String = "",
        marker: String = "plain",
        outcome: String = "deferred",
        source: String = "ledger"
    ) {
        self.index = index
        self.ledgerLine = ledgerLine
        self.blockLink = blockLink
        self.blockID = blockID
        self.marker = marker
        self.outcome = outcome
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        ledgerLine = try container.decodeIfPresent(Int.self, forKey: .ledgerLine) ?? 0
        blockLink = try container.decodeIfPresent(String.self, forKey: .blockLink) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        marker = try container.decodeIfPresent(String.self, forKey: .marker) ?? "plain"
        outcome = try container.decodeIfPresent(String.self, forKey: .outcome) ?? "deferred"
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "ledger"
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case ledgerLine = "ledger_line"
        case blockLink = "block_link"
        case blockID = "block_id"
        case marker
        case outcome
        case source
    }
}

/// A task or block-link effect Bob resolved while closing a Pomodoro. Every
/// field decodes tolerantly: booleans default to false, arrays to empty, and
/// `ledgerLine` stays decodable when absent, so older-bob and partial objects
/// still yield a (neutral, unresolved) row instead of failing the whole
/// capture. `index` is the number of the numbered line that produced the row,
/// or nil for unnumbered rows (struck, mentioned, subtask, Work-Log-only);
/// older Bob omits it and it decodes as nil. Unknown `role` strings are
/// preserved here and degrade to a neutral row in
/// `CapturePomodoroClosePresentation`.
public struct PomodoroCloseTask: Codable, Equatable, Sendable {
    public let role: String
    public let blockLink: String
    public let ledgerLine: Int
    public let index: Int?
    public let resolved: Bool
    public let relativeTarget: String?
    public let blockID: String
    public let text: String?
    public let previousStatusSymbol: String?
    public let previousStatusName: String?
    public let statusSymbol: String?
    public let statusName: String?
    public let statusChanged: Bool
    public let carried: Bool
    public let workLog: [String]
    public let workLogCreated: Bool
    public let typedWorkLog: [String]
    /// Detail lines written under each typed entry, aligned 1:1 with
    /// `typedWorkLog`: element _i_ lists the detail lines under typed entry
    /// _i_. Additive: an older Bob that omits `typed_work_log_details`
    /// decodes as empty, and a missing element counts as empty.
    public let typedWorkLogDetails: [[String]]
    public let warning: String?

    public init(
        role: String,
        blockLink: String,
        ledgerLine: Int = 0,
        index: Int? = nil,
        resolved: Bool = false,
        relativeTarget: String? = nil,
        blockID: String = "",
        text: String? = nil,
        previousStatusSymbol: String? = nil,
        previousStatusName: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        statusChanged: Bool = false,
        carried: Bool = false,
        workLog: [String] = [],
        workLogCreated: Bool = false,
        typedWorkLog: [String] = [],
        typedWorkLogDetails: [[String]] = [],
        warning: String? = nil
    ) {
        self.role = role
        self.blockLink = blockLink
        self.ledgerLine = ledgerLine
        self.index = index
        self.resolved = resolved
        self.relativeTarget = relativeTarget
        self.blockID = blockID
        self.text = text
        self.previousStatusSymbol = previousStatusSymbol
        self.previousStatusName = previousStatusName
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.statusChanged = statusChanged
        self.carried = carried
        self.workLog = workLog
        self.workLogCreated = workLogCreated
        self.typedWorkLog = typedWorkLog
        self.typedWorkLogDetails = typedWorkLogDetails
        self.warning = warning
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "unknown"
        blockLink = try container.decodeIfPresent(String.self, forKey: .blockLink) ?? ""
        ledgerLine = try container.decodeIfPresent(Int.self, forKey: .ledgerLine) ?? 0
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        resolved = try container.decodeIfPresent(Bool.self, forKey: .resolved) ?? false
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text)
        previousStatusSymbol = try container.decodeIfPresent(
            String.self,
            forKey: .previousStatusSymbol
        )
        previousStatusName = try container.decodeIfPresent(
            String.self,
            forKey: .previousStatusName
        )
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
        statusChanged = try container.decodeIfPresent(Bool.self, forKey: .statusChanged) ?? false
        carried = try container.decodeIfPresent(Bool.self, forKey: .carried) ?? false
        workLog = try container.decodeIfPresent([String].self, forKey: .workLog) ?? []
        workLogCreated =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .workLogCreated
            ) ?? false
        typedWorkLog = try container.decodeIfPresent([String].self, forKey: .typedWorkLog) ?? []
        typedWorkLogDetails =
            try container.decodeIfPresent(
                [[String]].self,
                forKey: .typedWorkLogDetails
            ) ?? []
        warning = try container.decodeIfPresent(String.self, forKey: .warning)
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case blockLink = "block_link"
        case ledgerLine = "ledger_line"
        case index
        case resolved
        case relativeTarget = "relative_target"
        case blockID = "block_id"
        case text
        case previousStatusSymbol = "previous_status_symbol"
        case previousStatusName = "previous_status_name"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case statusChanged = "status_changed"
        case carried
        case workLog = "work_log"
        case workLogCreated = "work_log_created"
        case typedWorkLog = "typed_work_log"
        case typedWorkLogDetails = "typed_work_log_details"
        case warning
    }
}

public struct PomodoroCloseCarriedItem: Codable, Equatable, Sendable {
    public let kind: String
    public let text: String

    public init(kind: String, text: String) {
        self.kind = kind
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "unknown"
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
    }
}

public struct PomodoroCloseNext: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String?
    public let timeRange: String?
    public let created: Bool
    /// True when Bob moved the created MEET continuation after the last
    /// open Pomodoro below the closed entry. Older Bob omits this
    /// additive field.
    public let placedLast: Bool
    /// Type components Bob removed from the carried session name. Older Bob
    /// omits this additive field.
    public let shed: [CapturePomodoroThemeRef]

    public init(
        line: Int,
        name: String? = nil,
        timeRange: String? = nil,
        created: Bool = false,
        placedLast: Bool = false,
        shed: [CapturePomodoroThemeRef] = []
    ) {
        self.line = line
        self.name = name
        self.timeRange = timeRange
        self.created = created
        self.placedLast = placedLast
        self.shed = shed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        created = try container.decodeIfPresent(Bool.self, forKey: .created) ?? false
        placedLast =
            try container.decodeIfPresent(Bool.self, forKey: .placedLast) ?? false
        shed =
            (try? container.decodeIfPresent(
                [CapturePomodoroThemeRef].self,
                forKey: .shed
            )) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case timeRange = "time_range"
        case created
        case placedLast = "placed_last"
        case shed
    }
}

/// One new Pomodoro entry Bob created while splitting a merged session.
/// Additive to capture schema v1; every field decodes with a safe fallback.
public struct PomodoroSplitCreated: Codable, Equatable, Sendable {
    public let typeRef: CapturePomodoroThemeRef
    public let line: Int
    public let name: String
    public let movedLinks: Int

    public init(
        typeRef: CapturePomodoroThemeRef,
        line: Int = 0,
        name: String = "",
        movedLinks: Int = 0
    ) {
        self.typeRef = typeRef
        self.line = line
        self.name = name
        self.movedLinks = movedLinks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        typeRef =
            (try? container.decode(CapturePomodoroThemeRef.self, forKey: .typeRef))
            ?? CapturePomodoroThemeRef(key: "", name: "")
        line = (try? container.decode(Int.self, forKey: .line)) ?? 0
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        movedLinks = (try? container.decode(Int.self, forKey: .movedLinks)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case typeRef = "type"
        case line
        case name
        case movedLinks = "moved_links"
    }
}

/// Bob's resolved preview for `=/`: the source block after splitting and each
/// created entry, in Bob's type order. Older Bob omits the whole object.
public struct PomodoroSplitSummary: Codable, Equatable, Sendable {
    public let path: String
    public let entryLine: Int
    public let before: String
    public let after: String
    public let base: CapturePomodoroThemeRef
    public let created: [PomodoroSplitCreated]
    public let stayedLinks: Int

    public init(
        path: String = "",
        entryLine: Int = 0,
        before: String = "",
        after: String = "",
        base: CapturePomodoroThemeRef = CapturePomodoroThemeRef(key: "", name: ""),
        created: [PomodoroSplitCreated] = [],
        stayedLinks: Int = 0
    ) {
        self.path = path
        self.entryLine = entryLine
        self.before = before
        self.after = after
        self.base = base
        self.created = created
        self.stayedLinks = stayedLinks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decode(String.self, forKey: .path)) ?? ""
        entryLine = (try? container.decode(Int.self, forKey: .entryLine)) ?? 0
        before = (try? container.decode(String.self, forKey: .before)) ?? ""
        after = (try? container.decode(String.self, forKey: .after)) ?? ""
        base =
            (try? container.decode(CapturePomodoroThemeRef.self, forKey: .base))
            ?? CapturePomodoroThemeRef(key: "", name: "")
        created = (try? container.decode([PomodoroSplitCreated].self, forKey: .created)) ?? []
        stayedLinks = (try? container.decode(Int.self, forKey: .stayedLinks)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case entryLine = "entry_line"
        case before
        case after
        case base
        case created
        case stayedLinks = "stayed_links"
    }
}

/// One source entry absorbed by Bob's resolved `=*` merge.
public struct PomodoroMergeAbsorbed: Codable, Equatable, Sendable {
    public let name: String
    public let fromLine: Int
    public let movedLines: Int
    public let droppedDuplicates: Int
    /// `"named"` or `"next"`. Older Bob omits it; decode as nil.
    public let role: String?

    public init(
        name: String = "",
        fromLine: Int = 0,
        movedLines: Int = 0,
        droppedDuplicates: Int = 0,
        role: String? = nil
    ) {
        self.name = name
        self.fromLine = fromLine
        self.movedLines = movedLines
        self.droppedDuplicates = droppedDuplicates
        self.role = role
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        fromLine = (try? container.decode(Int.self, forKey: .fromLine)) ?? 0
        movedLines = (try? container.decode(Int.self, forKey: .movedLines)) ?? 0
        droppedDuplicates = (try? container.decode(Int.self, forKey: .droppedDuplicates)) ?? 0
        role = try container.decodeIfPresent(String.self, forKey: .role)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case fromLine = "from_line"
        case movedLines = "moved_lines"
        case droppedDuplicates = "dropped_duplicates"
        case role
    }
}

/// Bob's resolved preview for `=*`: the survivor and absorbed planned entries.
public struct PomodoroMergeSummary: Codable, Equatable, Sendable {
    public let path: String
    public let entryLine: Int
    public let before: String
    public let after: String
    public let absorbed: [PomodoroMergeAbsorbed]
    /// `"current"`, `"next_up"`, or `"named"`. Older Bob omits it; decode as nil.
    public let sourceRole: String?
    /// Fully spelled token this merge resolved to, when an implied pick round-trips.
    /// Older Bob omits it; decode as nil. Swift never splits or parses this string.
    public let explicit: String?

    public init(
        path: String = "",
        entryLine: Int = 0,
        before: String = "",
        after: String = "",
        absorbed: [PomodoroMergeAbsorbed] = [],
        sourceRole: String? = nil,
        explicit: String? = nil
    ) {
        self.path = path
        self.entryLine = entryLine
        self.before = before
        self.after = after
        self.absorbed = absorbed
        self.sourceRole = sourceRole
        self.explicit = explicit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decode(String.self, forKey: .path)) ?? ""
        entryLine = (try? container.decode(Int.self, forKey: .entryLine)) ?? 0
        before = (try? container.decode(String.self, forKey: .before)) ?? ""
        after = (try? container.decode(String.self, forKey: .after)) ?? ""
        absorbed = (try? container.decode([PomodoroMergeAbsorbed].self, forKey: .absorbed)) ?? []
        sourceRole = try container.decodeIfPresent(String.self, forKey: .sourceRole)
        explicit = try container.decodeIfPresent(String.self, forKey: .explicit)
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case entryLine = "entry_line"
        case before
        case after
        case absorbed
        case sourceRole = "source_role"
        case explicit
    }
}

/// Bob's complete, resolved preview for a Pomodoro close. Every value is additive
/// to capture schema v1 and absent on older Bob binaries. Every field decodes
/// tolerantly (booleans default to false, arrays to empty, lines to zero) so a
/// partial object still previews instead of failing the whole capture.
/// `inProgress`/`park`/`complete`/`drop` report concrete selections;
/// `parkAll`/`completeAll` preserve wildcard intent after Bob expands it over
/// the resolved lineup. `taskLinks` is that numbered lineup, possibly empty.
/// Older Bob omits the additive flags and they decode as false.
public struct PomodoroCloseSummary: Codable, Equatable, Sendable {
    public let raw: String
    public let inProgress: [Int]?
    public let park: [Int]
    public let parkAll: Bool
    public let complete: [Int]
    public let completeAll: Bool
    public let drop: [Int]
    public let log: [PomodoroCloseLogEntry]
    public let pomodoroLine: Int
    public let pomodoroName: String?
    /// Name Bob assigned to the just-closed entry after narrowing its types.
    /// Older Bob omits this additive field.
    public let closedName: String?
    public let dayRelative: String?
    public let entryLine: String
    public let planned: PomodoroCloseTiming
    public let closed: PomodoroCloseTiming
    public let closedAt: String
    public let remainingMinutes: Int
    public let decrementedMinutes: Int
    public let tasks: [PomodoroCloseTask]
    public let taskLinks: [PomodoroCloseTaskLink]
    public let carried: [PomodoroCloseCarriedItem]
    public let notes: [String]
    public let nextPomodoro: PomodoroCloseNext?
    public let unblocked: [TaskCompleteUnblocked]
    public let keepMoving: [TaskCompleteUnblocked]
    public let relationSuccessors: [TaskCompleteUnblocked]
    public let relationHeld: [CaptureRelationHeld]
    public let relationCheck: String?
    public let stillBlocked: [TaskCompleteStillBlocked]
    public let unblockedCheck: String?

    public init(
        raw: String,
        inProgress: [Int]? = nil,
        park: [Int] = [],
        parkAll: Bool = false,
        complete: [Int] = [],
        completeAll: Bool = false,
        drop: [Int] = [],
        log: [PomodoroCloseLogEntry] = [],
        pomodoroLine: Int = 0,
        pomodoroName: String? = nil,
        closedName: String? = nil,
        dayRelative: String? = nil,
        entryLine: String = "",
        planned: PomodoroCloseTiming = PomodoroCloseTiming(
            start: "",
            end: "",
            durationMinutes: 0,
            timeRange: ""
        ),
        closed: PomodoroCloseTiming = PomodoroCloseTiming(
            start: "",
            end: "",
            durationMinutes: 0,
            timeRange: ""
        ),
        closedAt: String = "",
        remainingMinutes: Int = 0,
        decrementedMinutes: Int = 0,
        tasks: [PomodoroCloseTask] = [],
        taskLinks: [PomodoroCloseTaskLink] = [],
        carried: [PomodoroCloseCarriedItem] = [],
        notes: [String] = [],
        nextPomodoro: PomodoroCloseNext? = nil,
        unblocked: [TaskCompleteUnblocked] = [],
        keepMoving: [TaskCompleteUnblocked] = [],
        relationSuccessors: [TaskCompleteUnblocked] = [],
        relationHeld: [CaptureRelationHeld] = [],
        relationCheck: String? = nil,
        stillBlocked: [TaskCompleteStillBlocked] = [],
        unblockedCheck: String? = nil
    ) {
        self.raw = raw
        self.inProgress = inProgress
        self.park = park
        self.parkAll = parkAll
        self.complete = complete
        self.completeAll = completeAll
        self.drop = drop
        self.log = log
        self.pomodoroLine = pomodoroLine
        self.pomodoroName = pomodoroName
        self.closedName = closedName
        self.dayRelative = dayRelative
        self.entryLine = entryLine
        self.planned = planned
        self.closed = closed
        self.closedAt = closedAt
        self.remainingMinutes = remainingMinutes
        self.decrementedMinutes = decrementedMinutes
        self.tasks = tasks
        self.taskLinks = taskLinks
        self.carried = carried
        self.notes = notes
        self.nextPomodoro = nextPomodoro
        self.unblocked = unblocked
        self.keepMoving = keepMoving
        self.relationSuccessors = relationSuccessors
        self.relationHeld = relationHeld
        self.relationCheck = relationCheck
        self.stillBlocked = stillBlocked
        self.unblockedCheck = unblockedCheck
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        inProgress = try container.decodeIfPresent([Int].self, forKey: .inProgress)
        park = try container.decodeIfPresent([Int].self, forKey: .park) ?? []
        parkAll = try container.decodeIfPresent(Bool.self, forKey: .parkAll) ?? false
        complete = try container.decodeIfPresent([Int].self, forKey: .complete) ?? []
        completeAll = try container.decodeIfPresent(Bool.self, forKey: .completeAll) ?? false
        drop = try container.decodeIfPresent([Int].self, forKey: .drop) ?? []
        log = try container.decodeIfPresent([PomodoroCloseLogEntry].self, forKey: .log) ?? []
        pomodoroLine = try container.decodeIfPresent(Int.self, forKey: .pomodoroLine) ?? 0
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        closedName = try container.decodeIfPresent(String.self, forKey: .closedName)
        dayRelative = try container.decodeIfPresent(String.self, forKey: .dayRelative)
        entryLine = try container.decodeIfPresent(String.self, forKey: .entryLine) ?? ""
        planned =
            try container.decodeIfPresent(
                PomodoroCloseTiming.self,
                forKey: .planned
            ) ?? PomodoroCloseTiming(start: "", end: "", durationMinutes: 0, timeRange: "")
        closed =
            try container.decodeIfPresent(
                PomodoroCloseTiming.self,
                forKey: .closed
            ) ?? PomodoroCloseTiming(start: "", end: "", durationMinutes: 0, timeRange: "")
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt) ?? ""
        remainingMinutes =
            try container.decodeIfPresent(
                Int.self,
                forKey: .remainingMinutes
            ) ?? 0
        decrementedMinutes =
            try container.decodeIfPresent(
                Int.self,
                forKey: .decrementedMinutes
            ) ?? 0
        tasks = try container.decodeIfPresent([PomodoroCloseTask].self, forKey: .tasks) ?? []
        taskLinks =
            try container.decodeIfPresent(
                [PomodoroCloseTaskLink].self,
                forKey: .taskLinks
            ) ?? []
        carried =
            try container.decodeIfPresent(
                [PomodoroCloseCarriedItem].self,
                forKey: .carried
            ) ?? []
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        nextPomodoro = try container.decodeIfPresent(
            PomodoroCloseNext.self,
            forKey: .nextPomodoro
        )
        // The close summary itself decodes with a plain `try`, so every new
        // successor value decodes on its own: a malformed field degrades to
        // empty instead of failing the whole capture decode.
        unblocked =
            (try? container.decodeIfPresent(
                [TaskCompleteUnblocked].self,
                forKey: .unblocked
            )) ?? []
        keepMoving =
            (try? container.decodeIfPresent(
                [TaskCompleteUnblocked].self,
                forKey: .keepMoving
            )) ?? []
        relationSuccessors =
            (try? container.decodeIfPresent(
                [TaskCompleteUnblocked].self,
                forKey: .relationSuccessors
            )) ?? []
        relationHeld =
            (try? container.decodeIfPresent(
                [CaptureRelationHeld].self,
                forKey: .relationHeld
            )) ?? []
        relationCheck =
            (try? container.decodeIfPresent(String.self, forKey: .relationCheck)) ?? nil
        stillBlocked =
            (try? container.decodeIfPresent(
                [TaskCompleteStillBlocked].self,
                forKey: .stillBlocked
            )) ?? []
        unblockedCheck =
            (try? container.decodeIfPresent(
                String.self,
                forKey: .unblockedCheck
            )) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case inProgress = "in_progress"
        case park
        case parkAll = "park_all"
        case complete
        case completeAll = "complete_all"
        case drop
        case log
        case pomodoroLine = "pomodoro_line"
        case pomodoroName = "pomodoro_name"
        case closedName = "closed_name"
        case dayRelative = "day_relative"
        case entryLine = "entry_line"
        case planned
        case closed
        case closedAt = "closed_at"
        case remainingMinutes = "remaining_minutes"
        case decrementedMinutes = "decremented_minutes"
        case tasks
        case taskLinks = "task_links"
        case carried
        case notes
        case nextPomodoro = "next_pomodoro"
        case unblocked
        case keepMoving = "keep_moving"
        case relationSuccessors = "relation_successors"
        case relationHeld = "relation_held"
        case relationCheck = "relation_check"
        case stillBlocked = "still_blocked"
        case unblockedCheck = "unblocked_check"
    }
}

/// One note-free `x0` reset from Bob's additive `pomodoro_reset` result:
/// the current Pomodoro returned to the front of the future queue with its
/// session ledger cleared. Reset and `pomodoro_close` are mutually exclusive.
/// Older Bob binaries omit the key entirely; decode as nil.
public struct PomodoroResetSummary: Codable, Equatable, Sendable {
    public let raw: String
    public let dayRelative: String
    public let pomodoroName: String?
    public let previousPomodoroLine: Int
    public let pomodoroLine: Int
    public let previousEntryLine: String
    public let entryLine: String
    public let previousTimeRange: String
    public let timeRange: String?
    public let createdPomodoro: Bool
    public let moved: Bool

    public init(
        raw: String,
        dayRelative: String,
        pomodoroName: String? = nil,
        previousPomodoroLine: Int = 0,
        pomodoroLine: Int = 0,
        previousEntryLine: String = "",
        entryLine: String = "",
        previousTimeRange: String = "",
        timeRange: String? = nil,
        createdPomodoro: Bool = false,
        moved: Bool = false
    ) {
        self.raw = raw
        self.dayRelative = dayRelative
        self.pomodoroName = pomodoroName
        self.previousPomodoroLine = previousPomodoroLine
        self.pomodoroLine = pomodoroLine
        self.previousEntryLine = previousEntryLine
        self.entryLine = entryLine
        self.previousTimeRange = previousTimeRange
        self.timeRange = timeRange
        self.createdPomodoro = createdPomodoro
        self.moved = moved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        dayRelative = try container.decodeIfPresent(String.self, forKey: .dayRelative) ?? ""
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        previousPomodoroLine =
            try container.decodeIfPresent(Int.self, forKey: .previousPomodoroLine) ?? 0
        pomodoroLine = try container.decodeIfPresent(Int.self, forKey: .pomodoroLine) ?? 0
        previousEntryLine = try container.decodeIfPresent(String.self, forKey: .previousEntryLine) ?? ""
        entryLine = try container.decodeIfPresent(String.self, forKey: .entryLine) ?? ""
        previousTimeRange = try container.decodeIfPresent(String.self, forKey: .previousTimeRange) ?? ""
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        createdPomodoro = try container.decodeIfPresent(Bool.self, forKey: .createdPomodoro) ?? false
        moved = try container.decodeIfPresent(Bool.self, forKey: .moved) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case dayRelative = "day_relative"
        case pomodoroName = "pomodoro_name"
        case previousPomodoroLine = "previous_pomodoro_line"
        case pomodoroLine = "pomodoro_line"
        case previousEntryLine = "previous_entry_line"
        case entryLine = "entry_line"
        case previousTimeRange = "previous_time_range"
        case timeRange = "time_range"
        case createdPomodoro = "created_pomodoro"
        case moved
    }
}

public struct CaptureRewriteResponse: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let input: String
    public let text: String
    public let changed: Bool
    public let cursor: Int?
    public let rule: String?
    public let edits: [CaptureRewriteEdit]
    public let summary: String?
    public let notices: [String]

    public init(
        ok: Bool,
        schemaVersion: Int,
        input: String,
        text: String,
        changed: Bool,
        cursor: Int? = nil,
        rule: String? = nil,
        edits: [CaptureRewriteEdit] = [],
        summary: String? = nil,
        notices: [String] = []
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.input = input
        self.text = text
        self.changed = changed
        self.cursor = cursor
        self.rule = rule
        self.edits = edits
        self.summary = summary
        self.notices = notices
    }

    /// Combines Bob's sorted edits into one replacement suitable for a native
    /// text view. Returns nil unless every range is valid, the edits do not
    /// overlap, and applying them reproduces `text` byte-for-byte.
    public func coveringEdit(in draft: String) -> CaptureRewriteEdit? {
        guard let first = edits.first, let last = edits.last else {
            return nil
        }

        var applied = ""
        var inputCursor = 0
        var previousEnd = 0
        for edit in edits {
            let start = edit.range.start
            let end = edit.range.end
            guard start >= previousEnd,
                let unchanged = stringRange(in: draft, start: inputCursor, end: start),
                stringRange(in: draft, start: start, end: end) != nil
            else {
                return nil
            }
            applied.append(contentsOf: draft[unchanged])
            applied.append(contentsOf: edit.replacement)
            inputCursor = end
            previousEnd = end
        }
        guard
            let trailing = stringRange(
                in: draft,
                start: inputCursor,
                end: draft.utf8.count
            )
        else {
            return nil
        }
        applied.append(contentsOf: draft[trailing])
        guard applied.utf8.elementsEqual(text.utf8) else {
            return nil
        }

        var replacement = ""
        var coveringCursor = first.range.start
        for edit in edits {
            guard
                let unchanged = stringRange(
                    in: draft,
                    start: coveringCursor,
                    end: edit.range.start
                )
            else {
                return nil
            }
            replacement.append(contentsOf: draft[unchanged])
            replacement.append(contentsOf: edit.replacement)
            coveringCursor = edit.range.end
        }
        guard
            let trailingReplacement = stringRange(
                in: draft,
                start: coveringCursor,
                end: last.range.end
            )
        else {
            return nil
        }
        replacement.append(contentsOf: draft[trailingReplacement])

        return CaptureRewriteEdit(
            range: CaptureRange(start: first.range.start, end: last.range.end),
            replacement: replacement
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        input = try container.decode(String.self, forKey: .input)
        text = try container.decode(String.self, forKey: .text)
        changed = try container.decode(Bool.self, forKey: .changed)
        cursor = try container.decodeIfPresent(Int.self, forKey: .cursor)
        rule = try container.decodeIfPresent(String.self, forKey: .rule)
        edits = try container.decodeIfPresent([CaptureRewriteEdit].self, forKey: .edits) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        notices = try container.decodeIfPresent([String].self, forKey: .notices) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case input
        case text
        case changed
        case cursor
        case rule
        case edits
        case summary
        case notices
    }
}

public struct CaptureRewriteEdit: Codable, Equatable {
    public let range: CaptureRange
    public let replacement: String

    public init(range: CaptureRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}

/// A `@@<route>` global destination. It is route-only: Bob reports where the declaration
/// sits (`range`, 1-based `line`), the chosen `route`, and any `needs` still open (a bare
/// `@@` needs `route`). It carries no mode or block ID.
public struct CaptureGlobalDestination: Codable, Equatable, Sendable {
    public let range: CaptureRange?
    public let line: Int?
    public let route: String?
    public let needs: [String]

    public init(
        range: CaptureRange? = nil,
        line: Int? = nil,
        route: String? = nil,
        needs: [String] = []
    ) {
        self.range = range
        self.line = line
        self.route = route
        self.needs = needs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decodeIfPresent(CaptureRange.self, forKey: .range)
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? nil
        route = try container.decodeIfPresent(String.self, forKey: .route)
        needs = try container.decodeIfPresent([String].self, forKey: .needs) ?? []
    }

    public var destinationLabel: String {
        route.map { "\($0).md" } ?? "global destination"
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case line
        case route
        case needs
    }
}

// `bob capture --format json` has no schema_version: success and failure are
// distinguished only by `ok`, and a failure keeps `error` as its sole other field.
// Bob may omit empty collections and nil scalars, so collection fields decoded from bob
// use `decodeIfPresent(...) ?? []` while optional scalars stay optional.
public enum CaptureCommandResponse: Equatable, Decodable {
    case success(CaptureCommandSuccess)
    case failure(CaptureCommandFailure)

    public var ok: Bool {
        switch self {
        case .success(let value):
            return value.ok
        case .failure(let value):
            return value.ok
        }
    }

    private enum DiscriminatorKeys: String, CodingKey {
        case ok
    }

    public init(from decoder: Decoder) throws {
        let discriminator = try decoder.container(keyedBy: DiscriminatorKeys.self)
        if try discriminator.decode(Bool.self, forKey: .ok) {
            self = .success(try CaptureCommandSuccess(from: decoder))
        } else {
            self = .failure(try CaptureCommandFailure(from: decoder))
        }
    }
}

public struct PomodoroLinkEndpoint: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String?
    public let timeRange: String?
    // Additive plan-budget destination role: `current` (the running timed
    // entry), `next_up` (implicitly chosen and not running), `named` (an
    // existing entry matched by `#NAME`), or `created` (a new entry).
    // Older Bob omits it and it decodes as nil; unknown values are
    // preserved verbatim and degrade to neutral presentation.
    public let role: String?
    // Additive D7 typed-placement record: the task's effective type, the
    // cascade source, and the human label (`from dev`, `default type`).
    // Set only on destinations Bob placed by type; legacy and named
    // destinations leave this unset. Older Bob omits the whole object and
    // it decodes as nil.
    public let placedType: CapturePlacedType?
    /// Additive R2 report when landing merged a task type into this name.
    /// Older Bob omits it; malformed values degrade to nil.
    public let merged: PomodoroLinkMerge?

    public init(
        line: Int,
        name: String? = nil,
        timeRange: String? = nil,
        role: String? = nil,
        placedType: CapturePlacedType? = nil,
        merged: PomodoroLinkMerge? = nil
    ) {
        self.line = line
        self.name = name
        self.timeRange = timeRange
        self.role = role
        self.placedType = placedType
        self.merged = merged
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        placedType =
            (try? container.decodeIfPresent(
                CapturePlacedType.self, forKey: .placedType)) ?? nil
        merged =
            (try? container.decodeIfPresent(
                PomodoroLinkMerge.self,
                forKey: .merged
            )) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case timeRange = "time_range"
        case role
        case placedType = "type"
        case merged
    }
}

/// Bob's additive link-landing merge report: the name before and after
/// landing, plus the newly added type components.
public struct PomodoroLinkMerge: Codable, Equatable, Sendable {
    public let before: String
    public let after: String
    public let added: [CapturePomodoroThemeRef]

    public init(before: String = "", after: String = "", added: [CapturePomodoroThemeRef] = []) {
        self.before = before
        self.after = after
        self.added = added
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        before = (try? container.decode(String.self, forKey: .before)) ?? ""
        after = (try? container.decode(String.self, forKey: .after)) ?? ""
        added = (try? container.decode([CapturePomodoroThemeRef].self, forKey: .added)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case before
        case after
        case added
    }
}

/// Additive D7 typed-placement record on a link destination (D10): the
/// task's effective type, the cascade source, and the human label Bob
/// appends to its destination row (`→ new Pomodoro CHORE · default type`).
/// Bob omits the whole object when it did not place by type; malformed
/// values decode as nil so they can never fail the capture decode.
public struct CapturePlacedType: Codable, Equatable, Sendable {
    public let theme: CapturePomodoroThemeRef
    public let source: String
    public let label: String

    public init(
        theme: CapturePomodoroThemeRef = CapturePomodoroThemeRef(key: "", name: ""),
        source: String = "",
        label: String = ""
    ) {
        self.theme = theme
        self.source = source
        self.label = label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme =
            (try? container.decodeIfPresent(
                CapturePomodoroThemeRef.self, forKey: .theme))
            ?? CapturePomodoroThemeRef(key: "", name: "")
        source = (try? container.decodeIfPresent(String.self, forKey: .source)) ?? ""
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case theme
        case source
        case label
    }
}

/// One cap warning inside `plan_budget`: only the theme and link caps ever
/// fire here, and only while growing past the cap. Every field decodes
/// tolerantly so a partial object still yields a row instead of failing
/// the whole capture.
public struct CapturePlanBudgetWarning: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }
}

/// A before/after meter inside `plan_budget`. `before` is the pre-batch
/// count; it is optional because older Bob binaries omit it.
public struct CapturePlanBudgetMeter: Codable, Equatable, Sendable {
    public let count: Int
    public let cap: Int
    public let over: Bool
    public let before: Int?

    public init(count: Int, cap: Int, over: Bool, before: Int? = nil) {
        self.count = count
        self.cap = cap
        self.over = over
        self.before = before
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        cap = try container.decodeIfPresent(Int.self, forKey: .cap) ?? 0
        over = try container.decodeIfPresent(Bool.self, forKey: .over) ?? false
        before = try container.decodeIfPresent(Int.self, forKey: .before)
    }

    private enum CodingKeys: String, CodingKey {
        case count
        case cap
        case over
        case before
    }
}

/// Top-level `plan_budget` on a capture preview/submission or idle agenda
/// snapshot. The daily plan caps Task Links only. An older Bob also sends a
/// `themes` meter and `added_themes`; they decode as unknown keys and are
/// ignored, so a retired type cap never reaches the UI. Older Bob omits the
/// whole object and it decodes as nil.
public struct CapturePlanBudget: Codable, Equatable, Sendable {
    public let status: String
    public let links: CapturePlanBudgetMeter
    /// Hue refs for the Pomodoro names a capture adds, so preview pills wear
    /// Bob's hues without a second spawn. Absent on an older Bob and on one
    /// that adds none; it decodes as empty.
    public let addedThemeRefs: [CapturePomodoroThemeRef]
    public let warnings: [CapturePlanBudgetWarning]

    public init(
        status: String,
        links: CapturePlanBudgetMeter,
        addedThemeRefs: [CapturePomodoroThemeRef] = [],
        warnings: [CapturePlanBudgetWarning] = []
    ) {
        self.status = status
        self.links = links
        self.addedThemeRefs = addedThemeRefs
        self.warnings = warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        links =
            try container.decodeIfPresent(
                CapturePlanBudgetMeter.self,
                forKey: .links
            ) ?? CapturePlanBudgetMeter(count: 0, cap: 0, over: false)
        addedThemeRefs =
            (try? container.decodeIfPresent(
                [CapturePomodoroThemeRef].self,
                forKey: .addedThemeRefs
            )) ?? []
        warnings =
            try container.decodeIfPresent(
                [CapturePlanBudgetWarning].self,
                forKey: .warnings
            ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case links
        case addedThemeRefs = "added_theme_refs"
        case warnings
    }
}

/// One named project task Bob linked into the Pomodoro: the block ID, the
/// `[[<stem>#^<id>]]` link, the task text, and the rendered `[*]`/`[?]` line.
/// `bob capture --format json` reports these in source order inside
/// `project_note.task_links`; older Bob binaries omit the whole object.
public struct CaptureProjectTaskLink: Codable, Equatable, Sendable {
    public let blockID: String
    public let blockLink: String
    public let text: String
    public let taskLine: String

    public init(blockID: String, blockLink: String, text: String, taskLine: String) {
        self.blockID = blockID
        self.blockLink = blockLink
        self.text = text
        self.taskLine = taskLine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        blockLink = try container.decodeIfPresent(String.self, forKey: .blockLink) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        taskLine = try container.decodeIfPresent(String.self, forKey: .taskLine) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case blockLink = "block_link"
        case text
        case taskLine = "task_line"
    }
}

/// The additive `project_note` object on a `project_note` capture result:
/// the new note's identity, any Task Links written into the Pomodoro, and
/// (for the offer form) the successor rows Bob offers for an explicit pick.
/// Older Bob binaries omit the whole object and decode as nil.
/// One task Bob moved from the parent note into the new project note, in
/// draft order. `draftRange` is the UTF-8 byte range of the `^id` / `:id`
/// token in the submitted TEXT; the editor draws the ghost title after the
/// line holding it. Every field decodes tolerantly so one malformed row
/// never drops its siblings.
public struct CaptureProjectNoteMovedTask: Codable, Equatable, Sendable {
    /// `"^"` or `":"`.
    public let via: String?
    public let sigil: String
    /// UTF-8 byte range of the sigil+ID token in the submitted TEXT.
    public let draftRange: [Int]
    /// 1-based physical line holding the move bullet.
    public let itemLine: Int
    public let source: String
    public let sourceLine: Int
    /// 1-based landing line in the new note.
    public let line: Int
    public let blockID: String
    public let text: String
    public let previousStatusSymbol: String
    public let previousStatusName: String
    public let statusSymbol: String
    public let statusName: String
    public let fresh: String?
    public let planned: CaptureProjectNotePlannedLink?
    public let link: CaptureProjectTaskLink?
    public let notLinked: String?
    /// Bob-authored row suffix (`WORK link follows`,
    /// `becomes Next · links under ADMIN`); nil when the move stays unlinked.
    public let detail: String?

    public init(
        via: String? = nil,
        sigil: String = "",
        draftRange: [Int] = [],
        itemLine: Int = 0,
        source: String = "",
        sourceLine: Int = 0,
        line: Int = 0,
        blockID: String = "",
        text: String = "",
        previousStatusSymbol: String = "",
        previousStatusName: String = "",
        statusSymbol: String = "",
        statusName: String = "",
        fresh: String? = nil,
        planned: CaptureProjectNotePlannedLink? = nil,
        link: CaptureProjectTaskLink? = nil,
        notLinked: String? = nil,
        detail: String? = nil
    ) {
        self.via = via
        self.sigil = sigil
        self.draftRange = draftRange
        self.itemLine = itemLine
        self.source = source
        self.sourceLine = sourceLine
        self.line = line
        self.blockID = blockID
        self.text = text
        self.previousStatusSymbol = previousStatusSymbol
        self.previousStatusName = previousStatusName
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.fresh = fresh
        self.planned = planned
        self.link = link
        self.notLinked = notLinked
        self.detail = detail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        via = try? container.decodeIfPresent(String.self, forKey: .via)
        sigil = (try? container.decodeIfPresent(String.self, forKey: .sigil)) ?? ""
        draftRange =
            (try? container.decodeIfPresent([Int].self, forKey: .draftRange)) ?? []
        itemLine = (try? container.decodeIfPresent(Int.self, forKey: .itemLine)) ?? 0
        source = (try? container.decodeIfPresent(String.self, forKey: .source)) ?? ""
        sourceLine = (try? container.decodeIfPresent(Int.self, forKey: .sourceLine)) ?? 0
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        previousStatusSymbol =
            (try? container.decodeIfPresent(String.self, forKey: .previousStatusSymbol)) ?? ""
        previousStatusName =
            (try? container.decodeIfPresent(String.self, forKey: .previousStatusName)) ?? ""
        statusSymbol =
            (try? container.decodeIfPresent(String.self, forKey: .statusSymbol)) ?? ""
        statusName = (try? container.decodeIfPresent(String.self, forKey: .statusName)) ?? ""
        fresh = try? container.decodeIfPresent(String.self, forKey: .fresh)
        planned =
            try? container.decodeIfPresent(
                CaptureProjectNotePlannedLink.self,
                forKey: .planned
            )
        link =
            try? container.decodeIfPresent(CaptureProjectTaskLink.self, forKey: .link)
        notLinked = try? container.decodeIfPresent(String.self, forKey: .notLinked)
        detail = try? container.decodeIfPresent(String.self, forKey: .detail)
    }

    private enum CodingKeys: String, CodingKey {
        case via
        case sigil
        case draftRange = "draft_range"
        case itemLine = "item_line"
        case source
        case sourceLine = "source_line"
        case line
        case blockID = "block_id"
        case text
        case previousStatusSymbol = "previous_status_symbol"
        case previousStatusName = "previous_status_name"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case fresh
        case planned
        case link
        case notLinked = "not_linked"
        case detail
    }
}

/// Where a moved task's Task Link landed in the day file, when one followed.
public struct CaptureProjectNotePlannedLink: Codable, Equatable, Sendable {
    public let entryName: String
    public let entryLine: Int

    public init(entryName: String = "", entryLine: Int = 0) {
        self.entryName = entryName
        self.entryLine = entryLine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryName = (try? container.decodeIfPresent(String.self, forKey: .entryName)) ?? ""
        entryLine = (try? container.decodeIfPresent(Int.self, forKey: .entryLine)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case entryName = "entry_name"
        case entryLine = "entry_line"
    }
}

/// Totals for one batch of project-note moves: the parent file, how many
/// tasks moved, and how many vault links Bob repaired for them.
public struct CaptureProjectNoteMoveSummary: Codable, Equatable, Sendable {
    public let parent: String
    public let moved: Int
    public let repairedLinks: Int
    public let repairedNotes: Int
    public let needsReconcile: Bool

    public init(
        parent: String = "",
        moved: Int = 0,
        repairedLinks: Int = 0,
        repairedNotes: Int = 0,
        needsReconcile: Bool = false
    ) {
        self.parent = parent
        self.moved = moved
        self.repairedLinks = repairedLinks
        self.repairedNotes = repairedNotes
        self.needsReconcile = needsReconcile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parent = (try? container.decodeIfPresent(String.self, forKey: .parent)) ?? ""
        moved = (try? container.decodeIfPresent(Int.self, forKey: .moved)) ?? 0
        repairedLinks =
            (try? container.decodeIfPresent(Int.self, forKey: .repairedLinks)) ?? 0
        repairedNotes =
            (try? container.decodeIfPresent(Int.self, forKey: .repairedNotes)) ?? 0
        needsReconcile =
            (try? container.decodeIfPresent(Bool.self, forKey: .needsReconcile)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case parent
        case moved
        case repairedLinks = "repaired_links"
        case repairedNotes = "repaired_notes"
        case needsReconcile = "needs_reconcile"
    }
}

/// One vault file Bob repaired links in for a project-note move.
public struct CaptureProjectNoteRepairedFile: Codable, Equatable, Sendable {
    public let path: String
    public let linkCount: Int
    public let dependencyTokenCount: Int

    public init(path: String = "", linkCount: Int = 0, dependencyTokenCount: Int = 0) {
        self.path = path
        self.linkCount = linkCount
        self.dependencyTokenCount = dependencyTokenCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        linkCount = (try? container.decodeIfPresent(Int.self, forKey: .linkCount)) ?? 0
        dependencyTokenCount =
            (try? container.decodeIfPresent(Int.self, forKey: .dependencyTokenCount)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case linkCount = "link_count"
        case dependencyTokenCount = "dependency_token_count"
    }
}

/// Discoverability hint for a project-note draft with no move bullets whose
/// parent still has movable open tasks. Present only then; older Bob
/// binaries never send it.
public struct CaptureProjectNoteMoveHint: Codable, Equatable, Sendable {
    public let parent: String
    public let openCount: Int

    public init(parent: String = "", openCount: Int = 0) {
        self.parent = parent
        self.openCount = openCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parent = (try? container.decodeIfPresent(String.self, forKey: .parent)) ?? ""
        openCount = (try? container.decodeIfPresent(Int.self, forKey: .openCount)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case parent
        case openCount = "open_count"
    }
}

public struct CaptureProjectNoteSummary: Codable, Equatable, Sendable {
    public let basename: String
    public let parentRoute: String
    public let parentLink: String
    public let tasks: Int
    public let sections: [String]
    public let taskLinks: [CaptureProjectTaskLink]
    /// `"offer"` only for `@route:id@`; absent means the create form.
    public let form: String?
    /// Open task offers from the new project; absent on the create form.
    public let successors: [TaskCompleteUnblocked]
    /// Moved tasks in draft order; empty when the draft has no move bullets.
    public let movedTasks: [CaptureProjectNoteMovedTask]
    /// Move totals; present only when the draft moved at least one task.
    public let moveSummary: CaptureProjectNoteMoveSummary?
    /// Files Bob repaired move links in; present only with a move summary.
    public let repairedFiles: [CaptureProjectNoteRepairedFile]?
    /// Discoverability hint; present only with no moves and a movable parent.
    public let moveHint: CaptureProjectNoteMoveHint?

    public init(
        basename: String,
        parentRoute: String = "",
        parentLink: String = "",
        tasks: Int = 0,
        sections: [String] = [],
        taskLinks: [CaptureProjectTaskLink] = [],
        form: String? = nil,
        successors: [TaskCompleteUnblocked] = [],
        movedTasks: [CaptureProjectNoteMovedTask] = [],
        moveSummary: CaptureProjectNoteMoveSummary? = nil,
        repairedFiles: [CaptureProjectNoteRepairedFile]? = nil,
        moveHint: CaptureProjectNoteMoveHint? = nil
    ) {
        self.basename = basename
        self.parentRoute = parentRoute
        self.parentLink = parentLink
        self.tasks = tasks
        self.sections = sections
        self.taskLinks = taskLinks
        self.form = form
        self.successors = successors
        self.movedTasks = movedTasks
        self.moveSummary = moveSummary
        self.repairedFiles = repairedFiles
        self.moveHint = moveHint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        basename = try container.decodeIfPresent(String.self, forKey: .basename) ?? ""
        parentRoute = try container.decodeIfPresent(String.self, forKey: .parentRoute) ?? ""
        parentLink = try container.decodeIfPresent(String.self, forKey: .parentLink) ?? ""
        tasks = try container.decodeIfPresent(Int.self, forKey: .tasks) ?? 0
        sections = try container.decodeIfPresent([String].self, forKey: .sections) ?? []
        taskLinks =
            try container.decodeIfPresent(
                [CaptureProjectTaskLink].self,
                forKey: .taskLinks
            ) ?? []
        form = (try? container.decodeIfPresent(String.self, forKey: .form)) ?? nil
        successors =
            (try? container.decodeIfPresent(
                [TaskCompleteUnblocked].self,
                forKey: .successors
            )) ?? []
        movedTasks =
            (try? container.decodeIfPresent(
                [CaptureProjectNoteMovedTask].self,
                forKey: .movedTasks
            )) ?? []
        moveSummary =
            try? container.decodeIfPresent(
                CaptureProjectNoteMoveSummary.self,
                forKey: .moveSummary
            )
        repairedFiles =
            try? container.decodeIfPresent(
                [CaptureProjectNoteRepairedFile].self,
                forKey: .repairedFiles
            )
        moveHint =
            try? container.decodeIfPresent(
                CaptureProjectNoteMoveHint.self,
                forKey: .moveHint
            )
    }

    private enum CodingKeys: String, CodingKey {
        case basename
        case parentRoute = "parent_route"
        case parentLink = "parent_link"
        case tasks
        case sections
        case taskLinks = "task_links"
        case form
        case successors
        case movedTasks = "moved_tasks"
        case moveSummary = "move_summary"
        case repairedFiles = "repaired_files"
        case moveHint = "move_hint"
    }
}

/// The offline library verdict on a reference item: one of `not_found`,
/// `in_library`, `in_intake`, `clipping`, `duplicate`, `legacy`, or `unknown`.
/// Every field decodes tolerantly so a malformed verdict degrades to defaults
/// instead of failing the capture decode.
public struct CaptureRefLibrary: Codable, Equatable, Sendable {
    public let verdict: String
    public let path: String?
    public let title: String?
    public let readingState: String?
    public let message: String?

    public init(
        verdict: String = "",
        path: String? = nil,
        title: String? = nil,
        readingState: String? = nil,
        message: String? = nil
    ) {
        self.verdict = verdict
        self.path = path
        self.title = title
        self.readingState = readingState
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verdict = try container.decodeIfPresent(String.self, forKey: .verdict) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        readingState = try container.decodeIfPresent(String.self, forKey: .readingState)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case verdict
        case path
        case title
        case readingState = "reading_state"
        case message
    }
}

/// The staged ref job on a real run that queued the link. Present only when
/// the run queued a job; dry runs and unchanged items omit it.
public struct CaptureRefJob: Codable, Equatable, Sendable {
    public let id: String
    public let state: String

    public init(id: String = "", state: String = "") {
        self.id = id
        self.state = state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case state
    }
}

/// The inbox fallback on a queued reference item: where the task goes when the
/// background clip fails. Present only on queued items.
public struct CaptureRefFallback: Codable, Equatable, Sendable {
    public let relativeTarget: String
    public let taskLine: String

    public init(relativeTarget: String = "", taskLine: String = "") {
        self.relativeTarget = relativeTarget
        self.taskLine = taskLine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget) ?? ""
        taskLine = try container.decodeIfPresent(String.self, forKey: .taskLine) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case relativeTarget = "relative_target"
        case taskLine = "task_line"
    }
}

/// The canonical resolved reference parent on a reference capture result:
/// the route, its label, its kind, how the input token was selected
/// (`explicit`|`global`|`default`), and the matched alias (or null). Every
/// field decodes tolerantly so a malformed parent degrades to nil on the
/// owning `ref` object instead of failing the capture decode.
public struct CaptureRefParent: Codable, Equatable, Sendable {
    public let route: String
    public let label: String
    public let kind: String
    public let source: String
    public let alias: String?

    public init(
        route: String = "",
        label: String = "",
        kind: String = "",
        source: String = "",
        alias: String? = nil
    ) {
        self.route = route
        self.label = label
        self.kind = kind
        self.source = source
        self.alias = alias
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        route = try container.decodeIfPresent(String.self, forKey: .route) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
    }

    private enum CodingKeys: String, CodingKey {
        case route
        case label
        case kind
        case source
        case alias
    }
}

/// The additive `ref` object on a reference (`kind == "ref"`) capture result:
/// the classified URL, its offline library verdict, the canonical resolved
/// parent, the staged job (real runs that queued only), and the inbox
/// fallback (queued items only). Older Bob binaries omit `parent` entirely;
/// a mistyped parent degrades to nil so it can never fail the capture
/// decode. A malformed value decodes as nil so it can never fail the
/// capture decode.
public struct CaptureRef: Codable, Equatable, Sendable {
    public let url: String
    public let cleanedURL: String
    public let dedupeKey: String
    public let display: String
    public let routeHint: String
    /// True when Bob queued this reference with companion audio requested.
    public let listen: Bool
    /// Bob's explicit retry command when a listen request finds an unchanged ref.
    public let listenHint: String?
    public let library: CaptureRefLibrary
    public let parent: CaptureRefParent?
    public let job: CaptureRefJob?
    public let fallback: CaptureRefFallback?

    public init(
        url: String = "",
        cleanedURL: String = "",
        dedupeKey: String = "",
        display: String = "",
        routeHint: String = "",
        listen: Bool = false,
        listenHint: String? = nil,
        library: CaptureRefLibrary = CaptureRefLibrary(),
        parent: CaptureRefParent? = nil,
        job: CaptureRefJob? = nil,
        fallback: CaptureRefFallback? = nil
    ) {
        self.url = url
        self.cleanedURL = cleanedURL
        self.dedupeKey = dedupeKey
        self.display = display
        self.routeHint = routeHint
        self.listen = listen
        self.listenHint = listenHint
        self.library = library
        self.parent = parent
        self.job = job
        self.fallback = fallback
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        cleanedURL = try container.decodeIfPresent(String.self, forKey: .cleanedURL) ?? ""
        dedupeKey = try container.decodeIfPresent(String.self, forKey: .dedupeKey) ?? ""
        display = try container.decodeIfPresent(String.self, forKey: .display) ?? ""
        routeHint = try container.decodeIfPresent(String.self, forKey: .routeHint) ?? ""
        listen = (try? container.decodeIfPresent(Bool.self, forKey: .listen)) ?? false
        listenHint = (try? container.decodeIfPresent(String.self, forKey: .listenHint)) ?? nil
        library =
            try container.decodeIfPresent(CaptureRefLibrary.self, forKey: .library)
            ?? CaptureRefLibrary()
        parent = (try? container.decodeIfPresent(CaptureRefParent.self, forKey: .parent)) ?? nil
        job = try container.decodeIfPresent(CaptureRefJob.self, forKey: .job)
        fallback = try container.decodeIfPresent(CaptureRefFallback.self, forKey: .fallback)
    }

    /// Whether the object carries no identity at all: every field defaulted,
    /// as from `{"ref": {"raw": 42}}`. Such an object presents as nothing.
    public var isEmpty: Bool {
        url.isEmpty && display.isEmpty && dedupeKey.isEmpty && library.verdict.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case cleanedURL = "cleaned_url"
        case dedupeKey = "dedupe_key"
        case display
        case routeHint = "route_hint"
        case listen
        case listenHint = "listen_hint"
        case library
        case parent
        case job
        case fallback
    }
}

/// One prerequisite Bob dropped from a task's Depends-On line
/// (`dropped_dependencies` on a capture success). Additive: older Bob
/// omits the array entirely, and a missing or partial object still
/// decodes rather than failing the capture.
public struct CaptureDroppedDependency: Codable, Equatable, Sendable {
    public let notePath: String
    public let blockID: String
    public let link: String
    public let text: String
    public let statusSymbol: String
    public let statusName: String

    public init(
        notePath: String,
        blockID: String,
        link: String,
        text: String,
        statusSymbol: String,
        statusName: String
    ) {
        self.notePath = notePath
        self.blockID = blockID
        self.link = link
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol) ?? ""
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName) ?? ""
    }

    /// Chip wording for the link, toggle, Ensure Next, and close
    /// presentations. One prerequisite names its display text; several
    /// collapse to a count. Mirrors bob's human `dropped …` line without
    /// the chain emoji or dry-run tense.
    public static func chip(from dropped: [CaptureDroppedDependency]) -> String? {
        switch dropped.count {
        case 0:
            return nil
        case 1:
            let label = dropped[0].text.isEmpty ? dropped[0].link : dropped[0].text
            return "dropped dependency on \(label)"
        default:
            return "dropped \(dropped.count) dependencies"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case notePath = "note_path"
        case blockID = "block_id"
        case link
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
    }
}

/// Why a link gesture left its target unlinked (`link_guard` on a
/// capture success). Additive: older Bob omits it entirely.
public struct CaptureLinkGuard: Codable, Equatable, Sendable {
    public let reasons: [String]
    public let promoted: [String]
    public let detail: String?
    public let dropRefused: String?

    public init(
        reasons: [String] = [],
        promoted: [String] = [],
        detail: String? = nil,
        dropRefused: String? = nil
    ) {
        self.reasons = reasons
        self.promoted = promoted
        self.detail = detail
        self.dropRefused = dropRefused
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reasons = try container.decodeIfPresent([String].self, forKey: .reasons) ?? []
        promoted = try container.decodeIfPresent([String].self, forKey: .promoted) ?? []
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        dropRefused = try container.decodeIfPresent(String.self, forKey: .dropRefused)
    }

    private enum CodingKeys: String, CodingKey {
        case reasons
        case promoted
        case detail
        case dropRefused = "drop_refused"
    }
}

/// One capture warning. Plain strings keep every older draft's JSON
/// byte-identical; structured variants let machines discriminate by `code`
/// while clients render the bob-authored `message`. A newer Bob sends
/// `{code: "hides_existing_relation_label", ...}` objects when a `||`
/// capture hides a visible label; older Bob sends only strings.
public enum CaptureWarning: Codable, Equatable, Sendable {
    case text(String)
    case structured(StructuredCaptureWarning)

    /// The bob-authored human rendering, for preview rows and notifications.
    public var message: String {
        switch self {
        case .text(let message):
            return message
        case .structured(let warning):
            return warning.message
        }
    }

    /// True for the `hides_existing_relation_label` warning, which the
    /// relation card and the capture preview render as an amber row.
    public var isRelationHideWarning: Bool {
        if case .structured(let warning) = self {
            return warning.code == "hides_existing_relation_label"
        }
        return false
    }

    /// True for `relation_cancelled_source`, rendered in the ⊘ style and
    /// skipped when `relation_cancels[]` already shows Bob's message.
    public var isRelationCancelledSource: Bool {
        if case .structured(let warning) = self {
            return warning.code == "relation_cancelled_source"
        }
        return false
    }

    /// True for `relation_completed_source`, rendered in the ✓ style and
    /// skipped when `relation_completes[]` already shows Bob's message.
    public var isRelationCompletedSource: Bool {
        if case .structured(let warning) = self {
            return warning.code == "relation_completed_source"
        }
        return false
    }

    /// True for `theme_not_configured`, rendered once in every settled
    /// capture preview (not post-submit notifications).
    public var isThemeNotConfigured: Bool {
        if case .structured(let warning) = self {
            return warning.code == CaptureUnconfiguredThemePresentation.warningCode
        }
        return false
    }

    /// A mixed lineup stays worked in full; the start preview surfaces
    /// Bob's structured explanation in its warning style.
    public var isPomodoroClockMixed: Bool {
        if case .structured(let warning) = self {
            return warning.code == "pomodoro_clock_mixed"
        }
        return false
    }

    /// A non-MEET start whose written start sits inside an open meeting.
    public var isPomodoroStartsDuringEvent: Bool {
        if case .structured(let warning) = self {
            return warning.code == "pomodoro_starts_during_event"
        }
        return false
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let message = try? container.decode(String.self) {
            self = .text(message)
            return
        }
        self = .structured(try container.decode(StructuredCaptureWarning.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let message):
            try container.encode(message)
        case .structured(let warning):
            try container.encode(warning)
        }
    }
}

/// A machine-readable capture warning: `code` selects the handling,
/// `message` is the bob-authored rendering, and `label`/`count` carry the
/// pre-capture catalog facts for `hides_existing_relation_label`.
public struct StructuredCaptureWarning: Codable, Equatable, Sendable {
    public let code: String
    public let label: String?
    public let count: Int?
    public let message: String

    public init(code: String, label: String? = nil, count: Int? = nil, message: String) {
        self.code = code
        self.label = label
        self.count = count
        self.message = message
    }
}

/// One `relation_label_hides[]` entry on a capture dry-run or commit: the
/// label a `||` capture will hide (or already left hidden) from relation
/// suggestions. Older Bob omits the array; missing decodes as empty.
public struct CaptureRelationLabelHide: Codable, Equatable, Sendable {
    public let label: String
    public let key: String
    public let existingCount: Int
    public let wasHidden: Bool
    public let action: String

    public init(
        label: String,
        key: String,
        existingCount: Int = 0,
        wasHidden: Bool = false,
        action: String
    ) {
        self.label = label
        self.key = key
        self.existingCount = existingCount
        self.wasHidden = wasHidden
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case key
        case existingCount = "existing_count"
        case wasHidden = "was_hidden"
        case action
    }
}

/// One row of `bob relations list -f json`: the display spelling, usage
/// count, hidden state, optional inverse phrase, every spelling with its
/// count, and both insertion forms. Older Bob has no `relations` group.
public struct CaptureRelationLabelInfo: Codable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let count: Int
    public let hidden: Bool
    public let inverse: String?
    public let replacement: String
    public let hideReplacement: String

    public init(
        key: String,
        name: String,
        count: Int = 0,
        hidden: Bool = false,
        inverse: String? = nil,
        replacement: String,
        hideReplacement: String
    ) {
        self.key = key
        self.name = name
        self.count = count
        self.hidden = hidden
        self.inverse = inverse
        self.replacement = replacement
        self.hideReplacement = hideReplacement
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case name
        case count
        case hidden
        case inverse
        case replacement
        case hideReplacement = "hide_replacement"
    }
}

/// Decoded `bob relations list -f json`: label/link/hidden totals plus one
/// row per label. `renamedReappeared` names OLD keys a host rewrote offline.
public struct CaptureRelationLabelsResponse: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let ok: Bool
    public let labelCount: Int
    public let linkCount: Int
    public let hiddenCount: Int
    public let labels: [CaptureRelationLabelInfo]
    public let renamedReappeared: [String]

    public init(
        schemaVersion: Int = 1,
        ok: Bool = true,
        labelCount: Int = 0,
        linkCount: Int = 0,
        hiddenCount: Int = 0,
        labels: [CaptureRelationLabelInfo] = [],
        renamedReappeared: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.ok = ok
        self.labelCount = labelCount
        self.linkCount = linkCount
        self.hiddenCount = hiddenCount
        self.labels = labels
        self.renamedReappeared = renamedReappeared
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        let counts = try container.decodeIfPresent(Counts.self, forKey: .counts)
        labelCount = counts?.labels ?? 0
        linkCount = counts?.links ?? 0
        hiddenCount = counts?.hidden ?? 0
        labels = try container.decodeIfPresent([CaptureRelationLabelInfo].self, forKey: .labels) ?? []
        renamedReappeared =
            try container.decodeIfPresent([String].self, forKey: .renamedReappeared) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(ok, forKey: .ok)
        try container.encode(
            Counts(labels: labelCount, links: linkCount, hidden: hiddenCount),
            forKey: .counts
        )
        try container.encode(labels, forKey: .labels)
        try container.encode(renamedReappeared, forKey: .renamedReappeared)
    }

    private struct Counts: Codable {
        let labels: Int?
        let links: Int?
        let hidden: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case counts
        case labels
        case renamedReappeared = "renamed_reappeared"
    }
}

/// Decoded `bob relations rename -f json`: the previewed (`-d`) or applied
/// rename. Bob reports refusals (`unknown_label`, `label_exists`, …) as
/// `ok: false` with a `code` and `message`, which
/// `BobProcessClient.renameRelationLabel` surfaces as
/// `RelationRenameResult.refused` instead of this shape.
public struct CaptureRelationRenameResponse: Decodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let ok: Bool
    /// `dry_run` for a preview, `write` once bob commits.
    public let mode: String
    public let fromKey: String
    public let fromName: String
    public let toKey: String
    public let toName: String
    public let merge: Bool
    public let files: [CaptureRelationRenameFile]
    public let links: Int
    public let notes: Int
    public let mirrors: Int
    public let doneLinks: Int
    public let doneNotes: Int
    public let hiddenNote: String
    public let inverseNote: String
    /// Bob's insertion for NEW (`|…`); the draft fix-up splices its label
    /// part into each matching `|OLD` relation.
    public let replacement: String
    /// Bob's insertion for NEW (`||…`); the draft fix-up splices its label
    /// part into each matching `||OLD` relation.
    public let hideReplacement: String
    /// Present only on a write: the one commit bob made.
    public let commitSubject: String?
    /// `not_run` on a preview; `ok`, `skipped`, or `failed` on a write.
    /// A failed post-sync still renamed everything: the card reports
    /// "· sync pending" instead of failing.
    public let syncPost: String

    public init(
        schemaVersion: Int = 1,
        ok: Bool = true,
        mode: String = "dry_run",
        fromKey: String = "",
        fromName: String = "",
        toKey: String = "",
        toName: String = "",
        merge: Bool = false,
        files: [CaptureRelationRenameFile] = [],
        links: Int = 0,
        notes: Int = 0,
        mirrors: Int = 0,
        doneLinks: Int = 0,
        doneNotes: Int = 0,
        hiddenNote: String = "",
        inverseNote: String = "",
        replacement: String = "",
        hideReplacement: String = "",
        commitSubject: String? = nil,
        syncPost: String = "not_run"
    ) {
        self.schemaVersion = schemaVersion
        self.ok = ok
        self.mode = mode
        self.fromKey = fromKey
        self.fromName = fromName
        self.toKey = toKey
        self.toName = toName
        self.merge = merge
        self.files = files
        self.links = links
        self.notes = notes
        self.mirrors = mirrors
        self.doneLinks = doneLinks
        self.doneNotes = doneNotes
        self.hiddenNote = hiddenNote
        self.inverseNote = inverseNote
        self.replacement = replacement
        self.hideReplacement = hideReplacement
        self.commitSubject = commitSubject
        self.syncPost = syncPost
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "dry_run"
        let from = try container.decodeIfPresent(RenameEndpoint.self, forKey: .from)
        fromKey = from?.key ?? ""
        fromName = from?.name ?? ""
        let to = try container.decodeIfPresent(RenameEndpoint.self, forKey: .to)
        toKey = to?.key ?? ""
        toName = to?.name ?? ""
        merge = try container.decodeIfPresent(Bool.self, forKey: .merge) ?? false
        files = try container.decodeIfPresent([CaptureRelationRenameFile].self, forKey: .files) ?? []
        let counts = try container.decodeIfPresent(RenameCounts.self, forKey: .counts)
        links = counts?.links ?? 0
        notes = counts?.notes ?? 0
        mirrors = counts?.mirrors ?? 0
        doneLinks = counts?.doneLinks ?? 0
        doneNotes = counts?.doneNotes ?? 0
        let state = try container.decodeIfPresent(RenameNote.self, forKey: .state)
        hiddenNote = state?.note ?? ""
        let inverse = try container.decodeIfPresent(RenameNote.self, forKey: .inverse)
        inverseNote = inverse?.note ?? ""
        replacement = try container.decodeIfPresent(String.self, forKey: .replacement) ?? ""
        hideReplacement = try container.decodeIfPresent(String.self, forKey: .hideReplacement) ?? ""
        let commit = try container.decodeIfPresent([String: String].self, forKey: .commit)
        commitSubject = commit?["subject"]
        let sync = try container.decodeIfPresent(RenameSync.self, forKey: .sync)
        syncPost = sync?.post ?? "not_run"
    }

    private struct RenameEndpoint: Codable {
        let key: String?
        let name: String?
    }

    private struct RenameCounts: Codable {
        let links: Int?
        let notes: Int?
        let mirrors: Int?
        let doneLinks: Int?
        let doneNotes: Int?

        private enum CodingKeys: String, CodingKey {
            case links
            case notes
            case mirrors
            case doneLinks = "done_links"
            case doneNotes = "done_notes"
        }
    }

    private struct RenameNote: Codable {
        let note: String?
    }

    private struct RenameSync: Codable {
        let post: String?
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case mode
        case from
        case to
        case merge
        case files
        case counts
        case state
        case inverse
        case replacement
        case hideReplacement = "hide_replacement"
        case commit
        case sync
    }
}

/// One rewritten note in a `bob relations rename` preview or write.
public struct CaptureRelationRenameFile: Decodable, Equatable, Sendable {
    public let path: String
    public let links: Int
    public let mirrors: Int
    public let lines: [CaptureRelationRenameLine]

    public init(path: String, links: Int = 0, mirrors: Int = 0, lines: [CaptureRelationRenameLine] = []) {
        self.path = path
        self.links = links
        self.mirrors = mirrors
        self.lines = lines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        links = try container.decodeIfPresent(Int.self, forKey: .links) ?? 0
        mirrors = try container.decodeIfPresent(Int.self, forKey: .mirrors) ?? 0
        lines = try container.decodeIfPresent([CaptureRelationRenameLine].self, forKey: .lines) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case links
        case mirrors
        case lines
    }
}

/// One relabeled LINKS or LINKED FROM line: the before and after text.
public struct CaptureRelationRenameLine: Decodable, Equatable, Sendable {
    public let line: Int
    public let kind: String
    public let before: String
    public let after: String

    public init(line: Int, kind: String = "", before: String = "", after: String = "") {
        self.line = line
        self.kind = kind
        self.before = before
        self.after = after
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        before = try container.decodeIfPresent(String.self, forKey: .before) ?? ""
        after = try container.decodeIfPresent(String.self, forKey: .after) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case kind
        case before
        case after
    }
}

public struct CaptureCommandSuccess: Codable, Equatable, Sendable {
    public let ok: Bool
    public let dryRun: Bool
    public let routed: Bool
    public let route: String?
    public let routeLabel: String
    public let relativeTarget: String
    public let target: String
    public let text: String
    public let taskLine: String
    public let kind: String
    public let created: String
    public let scheduled: String?
    public let priority: String?
    public let priorityLabel: String?
    public let placement: String
    // Additive: `bob capture` omits this key entirely when a draft has no authored
    // sub-bullets, so decoding must tolerate its absence. These are the exact rendered
    // Markdown child lines (including target-selected indentation), unlike
    // `CaptureParseResponse.subBullets`'s normalized semantic bodies.
    public let subBullets: [String]
    public let clip: CaptureClipOutput?
    public let scheduleLog: CaptureScheduleLog?
    public let blockID: String?
    public let dayFile: String?
    public let blockLink: String?
    public let pomodoroLinkPlacement: String?
    public let parentLine: Int?
    public let parentText: String?
    /// Additive per-item drawer a sub-bullet landed in, with `created` true
    /// when the commit adds the drawer's header line. Null for plain
    /// `@route+id` children and absent from older Bob.
    public let drawer: CaptureDrawerSummary?
    /// Additive multi-note details on a note-less `@route+id` item. Older Bob
    /// and single-note captures omit the field; a present empty array remains
    /// distinguishable from an older response.
    public let notes: [CaptureNoteSummary]?
    /// Drawers touched by a multi-note item, in first-touch order. Older Bob
    /// and ordinary single-note captures omit this field.
    public let drawers: [CaptureDrawerSummary]?
    public let parentStatusSymbol: String?
    public let parentStatusName: String?
    // Additive: only present when `kind == "task_toggle"`. Bob always populates every
    // one of these together, so a decoded toggle response either has all of them or
    // none; `removedScheduled`, `scheduleLog`, and `pomodoroName` stay legitimately
    // optional per-toggle depending on what the toggle actually did.
    public let toggleDirection: String?
    public let previousTaskLine: String?
    public let statusSymbol: String?
    public let statusName: String?
    public let previousStatusSymbol: String?
    public let previousStatusName: String?
    public let pomodoroName: String?
    public let createsPomodoro: Bool?
    public let pomodoroAlreadyLinked: Bool?
    public let removedPomodoroLinks: Int?
    public let removedScheduled: String?
    public let pomodoroSelectorUnused: Bool?
    // Additive to schema version 1 for Bob's ensure-Next task-toggle behavior. Older
    // Bob binaries and two-way toggles omit these keys; missing values preserve
    // compatibility.
    public let toggleBehavior: String?
    public let statusChanged: Bool?
    public let pomodoroLinkAction: String?
    public let pomodoroLinkSource: PomodoroLinkEndpoint?
    public let pomodoroLinkDestination: PomodoroLinkEndpoint?
    // Additive atomic-start summary for `@<route>:<block-id>[#<name>]=<X>`
    // and whole-item `=`/`=<X>` starts. Older bob binaries omit it entirely;
    // decode as nil.
    public let pomodoroStart: PomodoroStartSummary?
    // Additive adjustment summary for whole-item `+N`/`-N`.
    // Older bob binaries omit it entirely; decode as nil.
    public let pomodoroAdjust: PomodoroAdjustSummary?
    // Additive shift summary for whole-item `++N`/`--N`.
    // Older bob binaries omit it entirely; decode as nil.
    public let pomodoroShift: PomodoroShiftSummary?
    // Additive session-close result for whole-item `x` and task-link `=x` closes. Older Bob
    // binaries omit it entirely; decode as nil.
    public let pomodoroClose: PomodoroCloseSummary?
    // Additive recorded past session for `x=` items. Older Bob binaries omit
    // it entirely; a malformed value degrades to nil so the rest still previews.
    // Bob intentionally omits a top-level `pomodoro_close` for this operation.
    public let pomodoroPast: PomodoroPastSummary?
    /// Additive `=/` split result. Older Bob binaries omit it; malformed
    /// values are ignored so the rest of capture still previews.
    public let pomodoroSplit: PomodoroSplitSummary?
    /// Additive `=*` merge result. Older Bob binaries omit it; malformed
    /// values are ignored so the rest of capture still previews.
    public let pomodoroMerge: PomodoroMergeSummary?
    // Additive note-free `x0` reset result. Mutually exclusive with
    // `pomodoroClose`. Older Bob binaries omit it entirely; decode as nil.
    public let pomodoroReset: PomodoroResetSummary?
    // Additive dependency summary for captures that add prerequisites:
    // dependent identity and text, added/already-present counts,
    // prerequisite summaries, open prerequisite count, and resulting
    // dependent status. Older Bob omits it entirely; decode as nil.
    public let dependencyUpdate: DependencyUpdateSummary?
    /// Additive per-item dependency effects. If an older Bob omits the array,
    /// normalize the legacy singular update to a one-element list.
    public let dependencyUpdates: [DependencyUpdateSummary]
    /// Task Links consumed from today's Pomodoros by dependency captures.
    /// Malformed additive data is ignored so the rest of capture still shows.
    public let consumedLinks: [CaptureConsumedLink]
    /// Newly minted identity for a task that blocks another task (`*`).
    public let mintedBlockerBlockID: CaptureMintedBlockID?
    /// Additive per-item `~` / `~~` writes (Rule 12). Older Bob omits each key;
    /// missing decodes as empty so the rest of capture still shows.
    public let relationUpdates: [CaptureRelationUpdate]
    /// Additive per-item cancel-label effects. Older Bob omits the key;
    /// missing decodes as empty so the rest of capture still shows.
    public let relationCancels: [CaptureRelationCancel]
    /// Additive per-item complete-label effects. Older Bob omits the key;
    /// missing decodes as empty so the rest of capture still shows.
    public let relationCompletes: [CaptureRelationComplete]
    /// Additive item-level relation successors from a Pending task toggle.
    /// Older Bob omits these fields; arrays default empty and check state stays nil.
    public let relationSuccessors: [TaskCompleteUnblocked]
    public let relationHeld: [CaptureRelationHeld]
    public let relationCheck: String?
    public let linkedFromLineUpdates: [CaptureBlocksLineUpdate]
    public let mintedRelationBlockIDs: [CaptureMintedRelationBlockID]
    public let mirrorSkipped: [CaptureMirrorSkipped]
    // Additive `task_complete` object on a whole-item `!note:block-id`
    // completion. Older Bob binaries omit it entirely; decode as nil, and a
    // malformed value decodes as nil so it can never fail the capture decode.
    public let taskComplete: CaptureTaskComplete?
    // Additive `project_note` object (including `task_links`) on a
    // `project_note` capture. Older Bob binaries omit it entirely; decode
    // as nil.
    public let projectNote: CaptureProjectNoteSummary?
    /// Additive move records for a capture `>` transfer to a bare note.
    /// Older Bob binaries omit them; malformed rows are ignored.
    public let moves: [CaptureTransferMove]
    /// Additive merge records for a capture `>` transfer into a task,
    /// drawer, or section. Older Bob binaries omit them; malformed rows are ignored.
    public let merges: [CaptureTransferMerge]
    /// Additive merge hand-off offers for a capture `>` transfer. Older Bob
    /// binaries omit them; malformed rows are dropped independently.
    public let mergeOffers: [TaskCompleteUnblocked]
    /// Files Bob repaired while moving transferred tasks. Absent from older Bob.
    public let repairedFiles: [CaptureTransferRepairedFile]
    /// Additive note-pull result. Older Bob binaries omit it; malformed
    /// values degrade to nil so the rest of capture still previews.
    public let notePull: CaptureNotePull?
    // Additive `ref` object on a `ref` capture. Older Bob binaries omit it
    // entirely; decode as nil, and a malformed value decodes as nil so it
    // can never fail the capture decode.
    public let ref: CaptureRef?
    /// Additive per-item Gmail previews (`gmail[]`) on a dry-run capture.
    /// One entry per Gmail URL Bob found in the item text, carrying the
    /// ready-made `message` line the item preview shows. Older Bob omits
    /// the key; decode as empty so the rest of capture still shows.
    public let gmail: [CaptureGmailPreview]
    // Additive top-level `plan_budget`: present only when the batch changed
    // today's Pomodoros section. It is not per item. Older Bob omits it
    // entirely; decode as nil.
    public let planBudget: CapturePlanBudget?
    /// Additive batch-level successor-choice capability and grouped offers.
    /// Older Bob binaries omit this field.
    public let pullIn: CapturePullIn?
    /// Additive receipts for offer rows resolved during this capture.
    /// Older Bob binaries omit the field; malformed rows are ignored.
    public let offerCloses: [CaptureOfferClose]
    /// Additive batch-level inbox-route capability, candidates, and
    /// destinations. Older Bob binaries omit this field; a malformed value
    /// decodes as nil so it can never fail the capture decode.
    public let inboxRoute: CaptureInboxRoute?
    /// Additive batch-level parent-task move choices. Older Bob binaries omit
    /// this field; malformed data degrades to nil so it cannot fail capture.
    public let moveChoice: CaptureMoveChoice?
    // Additive batch-level `pomodoro_blocks`: every Pomodoro the capture
    // touches, creates, or reports, in its final after-state. Older Bob
    // omits it entirely, and a malformed value decodes as empty so it can
    // never fail the capture decode.
    public let pomodoroBlocks: [CapturePomodoroBlock]
    // Additive batch-level `task_blocks`: every parent task a sub-bullet
    // capture wrote under, in its final after-state. Older Bob omits it
    // entirely, and a malformed value decodes as empty so it can never
    // fail the capture decode.
    public let taskBlocks: [CaptureTaskBlock]
    /// Additive batch-level section targets from transfer merges. Older Bob
    /// omits the key, and malformed rows are dropped independently.
    public let sectionBlocks: [CaptureSectionBlock]
    // Additive `dropped_dependencies`: prerequisites removed from a
    // Blocked task's Depends-On line before a capture link gesture.
    // Older Bob omits the key; decode as empty.
    public let droppedDependencies: [CaptureDroppedDependency]
    // Additive `link_guard`: present when a link gesture left its target
    // unlinked (§13.5). Older Bob omits it; decode as nil.
    public let linkGuard: CaptureLinkGuard?
    public let captures: [CaptureCommandSuccess]
    public let globalDestination: CaptureGlobalDestination?
    /// Capture warnings: plain strings from older Bob, or structured
    /// `{code, message, ...}` objects (for example the `||` hide warning).
    /// Older Bob omits the key; decode as empty.
    public let warnings: [CaptureWarning]
    /// Additive per-item `||` hides: one entry per distinct hidden key in a
    /// dry run or commit. Older Bob omits the key; decode as empty.
    public let relationLabelHides: [CaptureRelationLabelHide]
    /// Additive template execution summary and row metadata.
    public let template: CaptureTemplateSummary?
    public let templateRow: CaptureTemplateRow?
    /// Additive batch-level open destinations. Nil means an older Bob; an empty
    /// array is an explicit instruction to open nothing.
    public let openNotes: [CaptureOpenNote]?
    /// Additive per-item task-theme change from an explicit named capture.
    /// Older Bob omits it; malformed values decode as nil. `action` is
    /// `set`, `cleared`, or `kept`.
    public let taskTheme: CaptureTaskThemeChange?
    /// Additive ledger relocation so a retyped existing task's live Task
    /// Link agrees with its new type. Older Bob omits it; malformed values
    /// decode as nil.
    public let typeRelocation: CaptureTypeRelocation?
    /// Additive list membership for a bullet filed under a lone `@file` or
    /// `@file#section` header: its kind, route, section, header line, position,
    /// and the list's bullet count. Older Bob and non-list results omit it.
    public let list: CaptureListContext?

    public init(
        ok: Bool,
        dryRun: Bool,
        routed: Bool,
        route: String? = nil,
        routeLabel: String,
        relativeTarget: String,
        target: String,
        text: String,
        taskLine: String,
        kind: String,
        created: String,
        scheduled: String? = nil,
        priority: String? = nil,
        priorityLabel: String? = nil,
        placement: String,
        subBullets: [String] = [],
        clip: CaptureClipOutput? = nil,
        scheduleLog: CaptureScheduleLog? = nil,
        blockID: String? = nil,
        dayFile: String? = nil,
        blockLink: String? = nil,
        pomodoroLinkPlacement: String? = nil,
        parentLine: Int? = nil,
        parentText: String? = nil,
        drawer: CaptureDrawerSummary? = nil,
        notes: [CaptureNoteSummary]? = nil,
        drawers: [CaptureDrawerSummary]? = nil,
        parentStatusSymbol: String? = nil,
        parentStatusName: String? = nil,
        toggleDirection: String? = nil,
        previousTaskLine: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        previousStatusSymbol: String? = nil,
        previousStatusName: String? = nil,
        pomodoroName: String? = nil,
        createsPomodoro: Bool? = nil,
        pomodoroAlreadyLinked: Bool? = nil,
        removedPomodoroLinks: Int? = nil,
        removedScheduled: String? = nil,
        pomodoroSelectorUnused: Bool? = nil,
        toggleBehavior: String? = nil,
        statusChanged: Bool? = nil,
        pomodoroLinkAction: String? = nil,
        pomodoroLinkSource: PomodoroLinkEndpoint? = nil,
        pomodoroLinkDestination: PomodoroLinkEndpoint? = nil,
        pomodoroStart: PomodoroStartSummary? = nil,
        pomodoroAdjust: PomodoroAdjustSummary? = nil,
        pomodoroShift: PomodoroShiftSummary? = nil,
        pomodoroClose: PomodoroCloseSummary? = nil,
        pomodoroPast: PomodoroPastSummary? = nil,
        pomodoroSplit: PomodoroSplitSummary? = nil,
        pomodoroMerge: PomodoroMergeSummary? = nil,
        pomodoroReset: PomodoroResetSummary? = nil,
        dependencyUpdate: DependencyUpdateSummary? = nil,
        dependencyUpdates: [DependencyUpdateSummary]? = nil,
        consumedLinks: [CaptureConsumedLink] = [],
        mintedBlockerBlockID: CaptureMintedBlockID? = nil,
        relationUpdates: [CaptureRelationUpdate] = [],
        relationCancels: [CaptureRelationCancel] = [],
        relationCompletes: [CaptureRelationComplete] = [],
        relationSuccessors: [TaskCompleteUnblocked] = [],
        relationHeld: [CaptureRelationHeld] = [],
        relationCheck: String? = nil,
        linkedFromLineUpdates: [CaptureBlocksLineUpdate] = [],
        mintedRelationBlockIDs: [CaptureMintedRelationBlockID] = [],
        mirrorSkipped: [CaptureMirrorSkipped] = [],
        taskComplete: CaptureTaskComplete? = nil,
        projectNote: CaptureProjectNoteSummary? = nil,
        moves: [CaptureTransferMove] = [],
        merges: [CaptureTransferMerge] = [],
        mergeOffers: [TaskCompleteUnblocked] = [],
        repairedFiles: [CaptureTransferRepairedFile] = [],
        notePull: CaptureNotePull? = nil,
        ref: CaptureRef? = nil,
        gmail: [CaptureGmailPreview] = [],
        planBudget: CapturePlanBudget? = nil,
        pullIn: CapturePullIn? = nil,
        offerCloses: [CaptureOfferClose] = [],
        inboxRoute: CaptureInboxRoute? = nil,
        moveChoice: CaptureMoveChoice? = nil,
        captures: [CaptureCommandSuccess] = [],
        globalDestination: CaptureGlobalDestination? = nil,
        warnings: [CaptureWarning] = [],
        relationLabelHides: [CaptureRelationLabelHide] = [],
        pomodoroBlocks: [CapturePomodoroBlock] = [],
        taskBlocks: [CaptureTaskBlock] = [],
        sectionBlocks: [CaptureSectionBlock] = [],
        droppedDependencies: [CaptureDroppedDependency] = [],
        linkGuard: CaptureLinkGuard? = nil,
        template: CaptureTemplateSummary? = nil,
        templateRow: CaptureTemplateRow? = nil,
        openNotes: [CaptureOpenNote]? = nil,
        taskTheme: CaptureTaskThemeChange? = nil,
        typeRelocation: CaptureTypeRelocation? = nil,
        list: CaptureListContext? = nil
    ) {
        self.ok = ok
        self.dryRun = dryRun
        self.routed = routed
        self.route = route
        self.routeLabel = routeLabel
        self.relativeTarget = relativeTarget
        self.target = target
        self.text = text
        self.taskLine = taskLine
        self.kind = kind
        self.created = created
        self.scheduled = scheduled
        self.priority = priority
        self.priorityLabel = priorityLabel
        self.placement = placement
        self.subBullets = subBullets
        self.clip = clip
        self.scheduleLog = scheduleLog
        self.blockID = blockID
        self.dayFile = dayFile
        self.blockLink = blockLink
        self.pomodoroLinkPlacement = pomodoroLinkPlacement
        self.parentLine = parentLine
        self.parentText = parentText
        self.drawer = drawer
        self.notes = notes
        self.drawers = drawers
        self.parentStatusSymbol = parentStatusSymbol
        self.parentStatusName = parentStatusName
        self.toggleDirection = toggleDirection
        self.previousTaskLine = previousTaskLine
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.previousStatusSymbol = previousStatusSymbol
        self.previousStatusName = previousStatusName
        self.pomodoroName = pomodoroName
        self.createsPomodoro = createsPomodoro
        self.pomodoroAlreadyLinked = pomodoroAlreadyLinked
        self.removedPomodoroLinks = removedPomodoroLinks
        self.removedScheduled = removedScheduled
        self.pomodoroSelectorUnused = pomodoroSelectorUnused
        self.toggleBehavior = toggleBehavior
        self.statusChanged = statusChanged
        self.pomodoroLinkAction = pomodoroLinkAction
        self.pomodoroLinkSource = pomodoroLinkSource
        self.pomodoroLinkDestination = pomodoroLinkDestination
        self.pomodoroStart = pomodoroStart
        self.pomodoroAdjust = pomodoroAdjust
        self.pomodoroShift = pomodoroShift
        self.pomodoroClose = pomodoroClose
        self.pomodoroPast = pomodoroPast
        self.pomodoroSplit = pomodoroSplit
        self.pomodoroMerge = pomodoroMerge
        self.pomodoroReset = pomodoroReset
        self.dependencyUpdate = dependencyUpdate
        self.dependencyUpdates = dependencyUpdates ?? dependencyUpdate.map { [$0] } ?? []
        self.consumedLinks = consumedLinks
        self.mintedBlockerBlockID = mintedBlockerBlockID
        self.relationUpdates = relationUpdates
        self.relationCancels = relationCancels
        self.relationCompletes = relationCompletes
        self.relationSuccessors = relationSuccessors
        self.relationHeld = relationHeld
        self.relationCheck = relationCheck
        self.linkedFromLineUpdates = linkedFromLineUpdates
        self.mintedRelationBlockIDs = mintedRelationBlockIDs
        self.mirrorSkipped = mirrorSkipped
        self.taskComplete = taskComplete
        self.projectNote = projectNote
        self.moves = moves
        self.merges = merges
        self.mergeOffers = mergeOffers
        self.repairedFiles = repairedFiles
        self.notePull = notePull
        self.ref = ref
        self.gmail = gmail
        self.planBudget = planBudget
        self.pullIn = pullIn
        self.offerCloses = offerCloses
        self.inboxRoute = inboxRoute
        self.moveChoice = moveChoice
        self.pomodoroBlocks = pomodoroBlocks
        self.taskBlocks = taskBlocks
        self.sectionBlocks = sectionBlocks
        self.droppedDependencies = droppedDependencies
        self.linkGuard = linkGuard
        self.captures = captures
        self.globalDestination = globalDestination
        self.warnings = warnings
        self.relationLabelHides = relationLabelHides
        self.template = template
        self.templateRow = templateRow
        self.openNotes = openNotes?.filter { $0.path.hasPrefix("/") && !$0.path.isEmpty }
        self.taskTheme = taskTheme
        self.typeRelocation = typeRelocation
        self.list = list
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        dryRun = try container.decode(Bool.self, forKey: .dryRun)
        routed = try container.decode(Bool.self, forKey: .routed)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        routeLabel = try container.decode(String.self, forKey: .routeLabel)
        relativeTarget = try container.decode(String.self, forKey: .relativeTarget)
        target = try container.decode(String.self, forKey: .target)
        text = try container.decode(String.self, forKey: .text)
        taskLine = try container.decode(String.self, forKey: .taskLine)
        kind = try container.decode(String.self, forKey: .kind)
        created = try container.decode(String.self, forKey: .created)
        scheduled = try container.decodeIfPresent(String.self, forKey: .scheduled)
        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        priorityLabel = try container.decodeIfPresent(String.self, forKey: .priorityLabel)
        placement = try container.decode(String.self, forKey: .placement)
        subBullets = try container.decodeIfPresent([String].self, forKey: .subBullets) ?? []
        clip = try container.decodeIfPresent(CaptureClipOutput.self, forKey: .clip)
        scheduleLog = try container.decodeIfPresent(CaptureScheduleLog.self, forKey: .scheduleLog)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        dayFile = try container.decodeIfPresent(String.self, forKey: .dayFile)
        blockLink = try container.decodeIfPresent(String.self, forKey: .blockLink)
        pomodoroLinkPlacement = try container.decodeIfPresent(
            String.self, forKey: .pomodoroLinkPlacement)
        parentLine = try container.decodeIfPresent(Int.self, forKey: .parentLine)
        parentText = try container.decodeIfPresent(String.self, forKey: .parentText)
        drawer = (try? container.decodeIfPresent(CaptureDrawerSummary.self, forKey: .drawer)) ?? nil
        notes = (try? container.decodeIfPresent([CaptureNoteSummary].self, forKey: .notes)) ?? nil
        drawers = (try? container.decodeIfPresent([CaptureDrawerSummary].self, forKey: .drawers)) ?? nil
        parentStatusSymbol = try container.decodeIfPresent(String.self, forKey: .parentStatusSymbol)
        parentStatusName = try container.decodeIfPresent(String.self, forKey: .parentStatusName)
        toggleDirection = try container.decodeIfPresent(String.self, forKey: .toggleDirection)
        previousTaskLine = try container.decodeIfPresent(String.self, forKey: .previousTaskLine)
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
        previousStatusSymbol = try container.decodeIfPresent(String.self, forKey: .previousStatusSymbol)
        previousStatusName = try container.decodeIfPresent(String.self, forKey: .previousStatusName)
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        createsPomodoro = try container.decodeIfPresent(Bool.self, forKey: .createsPomodoro)
        pomodoroAlreadyLinked = try container.decodeIfPresent(Bool.self, forKey: .pomodoroAlreadyLinked)
        removedPomodoroLinks = try container.decodeIfPresent(Int.self, forKey: .removedPomodoroLinks)
        removedScheduled = try container.decodeIfPresent(String.self, forKey: .removedScheduled)
        pomodoroSelectorUnused = try container.decodeIfPresent(
            Bool.self, forKey: .pomodoroSelectorUnused)
        toggleBehavior = try container.decodeIfPresent(String.self, forKey: .toggleBehavior)
        statusChanged = try container.decodeIfPresent(Bool.self, forKey: .statusChanged)
        pomodoroLinkAction = try container.decodeIfPresent(String.self, forKey: .pomodoroLinkAction)
        pomodoroLinkSource = try container.decodeIfPresent(
            PomodoroLinkEndpoint.self,
            forKey: .pomodoroLinkSource
        )
        pomodoroLinkDestination = try container.decodeIfPresent(
            PomodoroLinkEndpoint.self,
            forKey: .pomodoroLinkDestination
        )
        pomodoroStart = try container.decodeIfPresent(
            PomodoroStartSummary.self,
            forKey: .pomodoroStart
        )
        pomodoroAdjust = try container.decodeIfPresent(
            PomodoroAdjustSummary.self,
            forKey: .pomodoroAdjust
        )
        pomodoroShift = try container.decodeIfPresent(
            PomodoroShiftSummary.self,
            forKey: .pomodoroShift
        )
        pomodoroClose = try container.decodeIfPresent(
            PomodoroCloseSummary.self,
            forKey: .pomodoroClose
        )
        pomodoroPast = (try? container.decodeIfPresent(
            PomodoroPastSummary.self,
            forKey: .pomodoroPast
        )) ?? nil
        pomodoroSplit =
            (try? container.decodeIfPresent(
                PomodoroSplitSummary.self,
                forKey: .pomodoroSplit
            )) ?? nil
        pomodoroMerge =
            (try? container.decodeIfPresent(
                PomodoroMergeSummary.self,
                forKey: .pomodoroMerge
            )) ?? nil
        pomodoroReset = try container.decodeIfPresent(
            PomodoroResetSummary.self,
            forKey: .pomodoroReset
        )
        dependencyUpdate =
            (try? container.decodeIfPresent(
                DependencyUpdateSummary.self,
                forKey: .dependencyUpdate
            )) ?? nil
        let decodedDependencyUpdates = try? container.decode(
            [DependencyUpdateSummary].self,
            forKey: .dependencyUpdates
        )
        dependencyUpdates =
            decodedDependencyUpdates
            ?? dependencyUpdate.map { [$0] }
            ?? []
        consumedLinks =
            (try? container.decode(
                [CaptureConsumedLink].self,
                forKey: .consumedLinks
            )) ?? []
        mintedBlockerBlockID =
            (try? container.decodeIfPresent(
                CaptureMintedBlockID.self,
                forKey: .mintedBlockerBlockID
            )) ?? nil
        relationUpdates =
            (try? container.decodeIfPresent(
                [CaptureRelationUpdate].self,
                forKey: .relationUpdates
            )) ?? []
        relationCancels =
            (try? container.decodeIfPresent(
                [CaptureRelationCancel].self,
                forKey: .relationCancels
            )) ?? []
        relationCompletes =
            (try? container.decodeIfPresent(
                [CaptureRelationComplete].self,
                forKey: .relationCompletes
            )) ?? []
        relationSuccessors =
            (try? container.decodeIfPresent(
                [TaskCompleteUnblocked].self,
                forKey: .relationSuccessors
            )) ?? []
        relationHeld =
            (try? container.decodeIfPresent(
                [CaptureRelationHeld].self,
                forKey: .relationHeld
            )) ?? []
        relationCheck =
            (try? container.decodeIfPresent(String.self, forKey: .relationCheck)) ?? nil
        linkedFromLineUpdates =
            (try? container.decodeIfPresent(
                [CaptureBlocksLineUpdate].self,
                forKey: .linkedFromLineUpdates
            )) ?? []
        mintedRelationBlockIDs =
            (try? container.decodeIfPresent(
                [CaptureMintedRelationBlockID].self,
                forKey: .mintedRelationBlockIDs
            )) ?? []
        mirrorSkipped =
            (try? container.decodeIfPresent(
                [CaptureMirrorSkipped].self,
                forKey: .mirrorSkipped
            )) ?? []
        taskComplete =
            (try? container.decodeIfPresent(
                CaptureTaskComplete.self,
                forKey: .taskComplete
            )) ?? nil
        projectNote = try container.decodeIfPresent(
            CaptureProjectNoteSummary.self,
            forKey: .projectNote
        )
        moves =
            (try? container.decode(CaptureLossyArray<CaptureTransferMove>.self, forKey: .moves))?
            .values ?? []
        merges =
            (try? container.decode(CaptureLossyArray<CaptureTransferMerge>.self, forKey: .merges))?
            .values ?? []
        mergeOffers =
            (try? container.decode(CaptureLossyArray<TaskCompleteUnblocked>.self, forKey: .mergeOffers))?
            .values ?? []
        repairedFiles =
            (try? container.decode([CaptureTransferRepairedFile].self, forKey: .repairedFiles)) ?? []
        notePull = (try? container.decodeIfPresent(CaptureNotePull.self, forKey: .notePull)) ?? nil
        ref = (try? container.decodeIfPresent(CaptureRef.self, forKey: .ref)) ?? nil
        gmail =
            (try? container.decodeIfPresent([CaptureGmailPreview].self, forKey: .gmail)) ?? []
        planBudget = try container.decodeIfPresent(
            CapturePlanBudget.self,
            forKey: .planBudget
        )
        pullIn = (try? container.decodeIfPresent(CapturePullIn.self, forKey: .pullIn)) ?? nil
        offerCloses =
            (try? container.decodeIfPresent([CaptureOfferClose].self, forKey: .offerCloses)) ?? []
        inboxRoute =
            (try? container.decodeIfPresent(CaptureInboxRoute.self, forKey: .inboxRoute)) ?? nil
        moveChoice =
            (try? container.decodeIfPresent(CaptureMoveChoice.self, forKey: .moveChoice)) ?? nil
        pomodoroBlocks =
            (try? container.decodeIfPresent(
                [CapturePomodoroBlock].self,
                forKey: .pomodoroBlocks
            )) ?? []
        taskBlocks =
            (try? container.decodeIfPresent(
                [CaptureTaskBlock].self,
                forKey: .taskBlocks
            )) ?? []
        sectionBlocks =
            (try? container.decode(
                CaptureLossyArray<CaptureSectionBlock>.self,
                forKey: .sectionBlocks
            ))?.values ?? []
        droppedDependencies =
            (try? container.decodeIfPresent(
                [CaptureDroppedDependency].self,
                forKey: .droppedDependencies
            )) ?? []
        linkGuard = try container.decodeIfPresent(
            CaptureLinkGuard.self,
            forKey: .linkGuard
        )
        captures = try container.decodeIfPresent([CaptureCommandSuccess].self, forKey: .captures) ?? []
        globalDestination = try container.decodeIfPresent(
            CaptureGlobalDestination.self,
            forKey: .globalDestination
        )
        warnings =
            (try? container.decodeIfPresent([CaptureWarning].self, forKey: .warnings)) ?? []
        relationLabelHides =
            (try? container.decodeIfPresent(
                [CaptureRelationLabelHide].self,
                forKey: .relationLabelHides
            )) ?? []
        template =
            (try? container.decodeIfPresent(CaptureTemplateSummary.self, forKey: .template)) ?? nil
        templateRow =
            (try? container.decodeIfPresent(CaptureTemplateRow.self, forKey: .templateRow)) ?? nil
        taskTheme =
            (try? container.decodeIfPresent(CaptureTaskThemeChange.self, forKey: .taskTheme)) ?? nil
        typeRelocation =
            (try? container.decodeIfPresent(CaptureTypeRelocation.self, forKey: .typeRelocation))
            ?? nil
        list = (try? container.decodeIfPresent(CaptureListContext.self, forKey: .list)) ?? nil
        if container.contains(.openNotes) {
            if try container.decodeNil(forKey: .openNotes) {
                openNotes = []
            } else {
                var unkeyed = try container.nestedUnkeyedContainer(forKey: .openNotes)
                var notes: [CaptureOpenNote] = []
                while !unkeyed.isAtEnd {
                    let wrapper = try unkeyed.decode(LossyOpenNote.self)
                    if let note = wrapper.note {
                        notes.append(note)
                    }
                }
                openNotes = notes.filter { $0.path.hasPrefix("/") && !$0.path.isEmpty }
            }
        } else {
            openNotes = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case dryRun = "dry_run"
        case routed
        case route
        case routeLabel = "route_label"
        case relativeTarget = "relative_target"
        case target
        case text
        case taskLine = "task_line"
        case kind
        case created
        case scheduled
        case priority
        case priorityLabel = "priority_label"
        case placement
        case subBullets = "sub_bullets"
        case clip
        case scheduleLog = "schedule_log"
        case blockID = "block_id"
        case dayFile = "day_file"
        case blockLink = "block_link"
        case pomodoroLinkPlacement = "pomodoro_link_placement"
        case parentLine = "parent_line"
        case parentText = "parent_text"
        case drawer
        case notes
        case drawers
        case parentStatusSymbol = "parent_status_symbol"
        case parentStatusName = "parent_status_name"
        case toggleDirection = "toggle_direction"
        case previousTaskLine = "previous_task_line"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case previousStatusSymbol = "previous_status_symbol"
        case previousStatusName = "previous_status_name"
        case pomodoroName = "pomodoro_name"
        case createsPomodoro = "creates_pomodoro"
        case pomodoroAlreadyLinked = "pomodoro_already_linked"
        case removedPomodoroLinks = "removed_pomodoro_links"
        case removedScheduled = "removed_scheduled"
        case pomodoroSelectorUnused = "pomodoro_selector_unused"
        case toggleBehavior = "toggle_behavior"
        case statusChanged = "status_changed"
        case pomodoroLinkAction = "pomodoro_link_action"
        case pomodoroLinkSource = "pomodoro_link_source"
        case pomodoroLinkDestination = "pomodoro_link_destination"
        case pomodoroStart = "pomodoro_start"
        case pomodoroAdjust = "pomodoro_adjust"
        case pomodoroShift = "pomodoro_shift"
        case pomodoroClose = "pomodoro_close"
        case pomodoroPast = "pomodoro_past"
        case pomodoroSplit = "pomodoro_split"
        case pomodoroMerge = "pomodoro_merge"
        case pomodoroReset = "pomodoro_reset"
        case dependencyUpdate = "dependency_update"
        case dependencyUpdates = "dependency_updates"
        case consumedLinks = "consumed_links"
        case mintedBlockerBlockID = "minted_blocker_block_id"
        case relationUpdates = "relation_updates"
        case relationCancels = "relation_cancels"
        case relationCompletes = "relation_completes"
        case relationSuccessors = "relation_successors"
        case relationHeld = "relation_held"
        case relationCheck = "relation_check"
        case linkedFromLineUpdates = "linked_from_line_updates"
        case mintedRelationBlockIDs = "minted_relation_block_ids"
        case mirrorSkipped = "mirror_skipped"
        case taskComplete = "task_complete"
        case projectNote = "project_note"
        case moves
        case merges
        case mergeOffers = "merge_offers"
        case repairedFiles = "repaired_files"
        case notePull = "note_pull"
        case ref
        case gmail
        case planBudget = "plan_budget"
        case pullIn = "pull_in"
        case offerCloses = "offer_closes"
        case inboxRoute = "inbox_route"
        case moveChoice = "move_choice"
        case pomodoroBlocks = "pomodoro_blocks"
        case taskBlocks = "task_blocks"
        case sectionBlocks = "section_blocks"
        case droppedDependencies = "dropped_dependencies"
        case linkGuard = "link_guard"
        case captures
        case globalDestination = "global_destination"
        case warnings
        case relationLabelHides = "relation_label_hides"
        case template
        case templateRow = "template_row"
        case openNotes = "open_notes"
        case taskTheme = "task_theme"
        case typeRelocation = "type_relocation"
        case list
    }

    /// The exact Markdown block `bob capture` writes beneath the destination, in the
    /// same order the CLI renders and prints it: the captured parent line, the authored
    /// children, the clipboard children, then the priority-roll schedule log. Every line
    /// already carries the target note's own child indentation, so preview must render
    /// them verbatim rather than re-deriving nesting.
    ///
    /// Continuous live preview passes `--no-clip` unless the draft's accepted
    /// parse reported a `%c` directive span, in which case Bob reads the
    /// clipboard through the same path the capture will use and `clip` is
    /// present here. The explicit Preview and Capture paths always resolve
    /// the clipboard and therefore mirror the full block.
    public var previewBlockLines: [String] {
        var lines = [taskLine]
        lines.append(contentsOf: subBullets)
        if let clip {
            lines.append(contentsOf: clip.lines)
        }
        if let scheduleLog {
            lines.append(contentsOf: scheduleLog.lines)
        }
        return lines
    }

    /// Bob preserves the legacy top-level success fields for one capture and for the
    /// first item of a multi-capture response. New callers should use this normalized
    /// collection so single and batch presentation share one code path.
    public var normalizedCaptures: [CaptureCommandSuccess] {
        captures.isEmpty ? [self] : captures
    }
}

public func captureUsesGlobalDestination(
    _ capture: CaptureCommandSuccess,
    _ globalDestination: CaptureGlobalDestination
) -> Bool {
    guard let globalRoute = globalDestination.route, !globalRoute.isEmpty else {
        return false
    }

    let routeMatches =
        capture.route == globalRoute
        || capture.routeLabel == "\(globalRoute).md"
        || capture.relativeTarget == "\(globalRoute).md"
    guard routeMatches else {
        return false
    }
    // A route-only destination has no block, so a capture that landed under a block ID
    // overrode it.
    return capture.blockID == nil
}

/// One prerequisite in Bob's `dependency_update` preview detail: the exact
/// note identity, block ID, canonical `[[note#^id]]` link, status, text,
/// and whether it still blocks the dependent. Closed prerequisites do not
/// block. Older Bob omits the whole object; decode tolerantly.
public struct DependencyPrerequisite: Codable, Equatable, Sendable {
    public let note: String
    public let blockID: String
    public let link: String
    public let statusSymbol: String
    public let statusName: String
    public let text: String
    public let isOpen: Bool
    /// Present on newer Bob; omitted when this prerequisite was not already
    /// on the Depends-On line. Older Bob omits the key entirely.
    public let alreadyPresent: Bool?
    /// Present only when this write changed the prerequisite's status.
    public let previousStatus: String?
    public let previousStatusName: String?

    public init(
        note: String,
        blockID: String,
        link: String,
        statusSymbol: String,
        statusName: String,
        text: String,
        isOpen: Bool,
        alreadyPresent: Bool? = nil,
        previousStatus: String? = nil,
        previousStatusName: String? = nil
    ) {
        self.note = note
        self.blockID = blockID
        self.link = link
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.text = text
        self.isOpen = isOpen
        self.alreadyPresent = alreadyPresent
        self.previousStatus = previousStatus
        self.previousStatusName = previousStatusName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol) ?? ""
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        isOpen = try container.decodeIfPresent(Bool.self, forKey: .isOpen) ?? false
        alreadyPresent = try container.decodeIfPresent(Bool.self, forKey: .alreadyPresent)
        previousStatus = try container.decodeIfPresent(String.self, forKey: .previousStatus)
        previousStatusName = try container.decodeIfPresent(String.self, forKey: .previousStatusName)
    }

    private enum CodingKeys: String, CodingKey {
        case note
        case blockID = "block_id"
        case link
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case text
        case isOpen = "open"
        case alreadyPresent = "already_present"
        case previousStatus = "previous_status"
        case previousStatusName = "previous_status_name"
    }
}

/// Optional `dependency_update` execution/preview detail on a capture that
/// adds prerequisites: dependent identity and text, added/already-present
/// counts, prerequisite summaries, open prerequisite count, resulting
/// dependent status, and whether the capture created the dependent.
public struct DependencyUpdateSummary: Codable, Equatable, Sendable {
    /// `dependent` for an `&` update, `blocked_task` for a `*` target.
    public let role: String
    public let dependentNote: String
    public let dependentBlockID: String?
    public let dependentText: String
    public let isNewTask: Bool
    public let added: Int
    public let alreadyPresent: Int
    public let openPrerequisites: Int
    public let prerequisites: [DependencyPrerequisite]
    public let dependentStatus: String
    public let dependentStatusName: String
    public let statusChanged: Bool
    public let previousStatus: String
    public let previousStatusName: String
    public let blockedResidents: Int

    public init(
        dependentNote: String,
        dependentText: String,
        isNewTask: Bool,
        added: Int,
        alreadyPresent: Int,
        openPrerequisites: Int,
        prerequisites: [DependencyPrerequisite] = [],
        dependentStatus: String,
        dependentStatusName: String,
        statusChanged: Bool,
        role: String = "dependent",
        dependentBlockID: String? = nil,
        previousStatus: String = "",
        previousStatusName: String = "",
        blockedResidents: Int = 0
    ) {
        self.role = role
        self.dependentNote = dependentNote
        self.dependentBlockID = dependentBlockID
        self.dependentText = dependentText
        self.isNewTask = isNewTask
        self.added = added
        self.alreadyPresent = alreadyPresent
        self.openPrerequisites = openPrerequisites
        self.prerequisites = prerequisites
        self.dependentStatus = dependentStatus
        self.dependentStatusName = dependentStatusName
        self.statusChanged = statusChanged
        self.previousStatus = previousStatus
        self.previousStatusName = previousStatusName
        self.blockedResidents = blockedResidents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = (try? container.decodeIfPresent(String.self, forKey: .role)) ?? "dependent"
        dependentNote = try container.decodeIfPresent(String.self, forKey: .dependentNote) ?? ""
        dependentBlockID =
            (try? container.decodeIfPresent(String.self, forKey: .dependentBlockID)) ?? nil
        dependentText = try container.decodeIfPresent(String.self, forKey: .dependentText) ?? ""
        isNewTask = try container.decodeIfPresent(Bool.self, forKey: .isNewTask) ?? false
        added = try container.decodeIfPresent(Int.self, forKey: .added) ?? 0
        alreadyPresent = try container.decodeIfPresent(Int.self, forKey: .alreadyPresent) ?? 0
        openPrerequisites = try container.decodeIfPresent(Int.self, forKey: .openPrerequisites) ?? 0
        prerequisites =
            try container.decodeIfPresent(
                [DependencyPrerequisite].self,
                forKey: .prerequisites
            ) ?? []
        dependentStatus = try container.decodeIfPresent(String.self, forKey: .dependentStatus) ?? ""
        dependentStatusName =
            try container.decodeIfPresent(String.self, forKey: .dependentStatusName) ?? ""
        statusChanged = try container.decodeIfPresent(Bool.self, forKey: .statusChanged) ?? false
        previousStatus = (try? container.decodeIfPresent(String.self, forKey: .previousStatus)) ?? ""
        previousStatusName =
            (try? container.decodeIfPresent(String.self, forKey: .previousStatusName)) ?? ""
        blockedResidents = (try? container.decodeIfPresent(Int.self, forKey: .blockedResidents)) ?? 0
    }

    /// Preview headline: `New task · depends on …` for created dependents,
    /// `Add dependency to "…"` for existing ones. Never "Create task" for a
    /// dependency-only action.
    public var headline: String {
        if isNewTask {
            return
                "New task · depends on \(prerequisites.count == 1 ? "1 task" : "\(prerequisites.count) tasks")"
        }
        return "Add dependency to \u{201C}\(dependentText)\u{201D}"
    }

    /// The resulting managed child line, from Bob's canonical prerequisite
    /// links in typed order.
    public var managedLineText: String {
        let links = prerequisites.map { $0.link }.joined(separator: " ")
        return "**DEPENDS ON:** \(links)"
    }

    /// Waiting count plus the Blocked/closed distinction, straight from Bob:
    /// open prerequisites block, closed ones do not.
    public var waitingText: String {
        if openPrerequisites == 0 {
            return "No open prerequisites · \(dependentStatusName)"
        }
        let waiting =
            openPrerequisites == 1
            ? "Waiting on 1 open prerequisite" : "Waiting on \(openPrerequisites) open prerequisites"
        return "\(waiting) · \(dependentStatusName)"
    }

    /// VoiceOver summary for the dependency preview section.
    public var previewAccessibilitySummary: String {
        var parts = [headline, managedLineText, waitingText]
        if alreadyPresent > 0 {
            parts.append(alreadyPresent == 1 ? "1 already present" : "\(alreadyPresent) already present")
        }
        return parts.joined(separator: ". ") + "."
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case dependentNote = "dependent_note"
        case dependentBlockID = "dependent_block_id"
        case dependentText = "dependent_text"
        case isNewTask = "new_task"
        case added
        case alreadyPresent = "already_present"
        case openPrerequisites = "open_prerequisites"
        case prerequisites
        case dependentStatus = "dependent_status"
        case dependentStatusName = "dependent_status_name"
        case statusChanged = "status_changed"
        case previousStatus = "previous_status"
        case previousStatusName = "previous_status_name"
        case blockedResidents = "blocked_residents"
    }
}

/// One capture-consumed Task Link and the Pomodoro it came from. Every field
/// is additive to schema version 1, so malformed rows are dropped by the
/// enclosing capture decoder instead of hiding the capture preview.
public struct CaptureConsumedLink: Codable, Equatable, Sendable {
    public let dayFile: String
    public let line: Int
    public let link: String
    public let note: String
    public let blockID: String
    public let text: String
    /// `removed`, `token_removed`, or `notes_kept`; retained as a string so a
    /// future Bob action remains displayable without breaking decoding.
    public let action: String
    public let pomodoro: CaptureConsumedLinkPomodoro

    public init(
        dayFile: String = "",
        line: Int = 0,
        link: String = "",
        note: String = "",
        blockID: String = "",
        text: String = "",
        action: String = "removed",
        pomodoro: CaptureConsumedLinkPomodoro = CaptureConsumedLinkPomodoro()
    ) {
        self.dayFile = dayFile
        self.line = line
        self.link = link
        self.note = note
        self.blockID = blockID
        self.text = text
        self.action = action
        self.pomodoro = pomodoro
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayFile = (try? container.decodeIfPresent(String.self, forKey: .dayFile)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        link = (try? container.decodeIfPresent(String.self, forKey: .link)) ?? ""
        note = (try? container.decodeIfPresent(String.self, forKey: .note)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        action = (try? container.decodeIfPresent(String.self, forKey: .action)) ?? "removed"
        pomodoro =
            (try? container.decodeIfPresent(CaptureConsumedLinkPomodoro.self, forKey: .pomodoro))
            ?? CaptureConsumedLinkPomodoro()
    }

    /// Mirrors §5's human output. The server's session name, time range,
    /// status, and removal flag are the only inputs to this copy.
    public func previewText(dryRun: Bool) -> String {
        let name = pomodoro.name.flatMap { $0.isEmpty ? nil : $0 } ?? "line \(pomodoro.line)"
        let range = pomodoro.timeRange.flatMap { $0.isEmpty ? nil : " \($0)" } ?? ""
        let status = pomodoro.status.lowercased()
        if action == "notes_kept" {
            return "− \(dryRun ? "would keep" : "kept") its notes under \(name)\(range) as plain text"
        }
        let verb = dryRun ? "would remove" : "removed"
        var line = "− \(verb) its Task Link from \(name)\(range) (\(status))"
        if pomodoro.removed {
            line += " · \(dryRun ? "would delete" : "deleted") the empty Pomodoro"
        }
        return line
    }

    private enum CodingKeys: String, CodingKey {
        case dayFile = "day_file"
        case line
        case link
        case note
        case blockID = "block_id"
        case text
        case action
        case pomodoro
    }
}

public struct CaptureConsumedLinkPomodoro: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String?
    public let timeRange: String?
    public let status: String
    public let removed: Bool

    public init(
        line: Int = 0,
        name: String? = nil,
        timeRange: String? = nil,
        status: String = "queued",
        removed: Bool = false
    ) {
        self.line = line
        self.name = name
        self.timeRange = timeRange
        self.status = status
        self.removed = removed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        timeRange = (try? container.decodeIfPresent(String.self, forKey: .timeRange)) ?? nil
        status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? "queued"
        removed = (try? container.decodeIfPresent(Bool.self, forKey: .removed)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case timeRange = "time_range"
        case status
        case removed
    }
}

/// The ID Bob minted for the task that becomes another task's prerequisite.
public struct CaptureMintedBlockID: Codable, Equatable, Sendable {
    public let path: String
    public let line: Int
    public let blockID: String

    public init(path: String = "", line: Int = 0, blockID: String = "") {
        self.path = path
        self.line = line
        self.blockID = blockID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case line
        case blockID = "block_id"
    }
}

/// One endpoint of a `~` / `~~` relation edge. Every field decodes tolerantly
/// so a partial object still yields a row instead of failing the capture.
public struct CaptureRelationEndpoint: Codable, Equatable, Sendable {
    public let path: String
    public let line: Int
    public let blockID: String
    public let text: String
    public let archived: Bool?

    public init(
        path: String = "",
        line: Int = 0,
        blockID: String = "",
        text: String = "",
        archived: Bool? = nil
    ) {
        self.path = path
        self.line = line
        self.blockID = blockID
        self.text = text
        self.archived = archived
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        archived = (try? container.decodeIfPresent(Bool.self, forKey: .archived)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case line
        case blockID = "block_id"
        case text
        case archived
    }
}

/// One `~` / `~~` edge this item wrote or confirmed. `direction` is `to` or
/// `from`, `action` is `added`, `relabeled`, or `unchanged`. Older Bob omits
/// the array entirely; missing decodes as empty.
public struct CaptureRelationUpdate: Codable, Equatable, Sendable {
    public let direction: String
    public let source: CaptureRelationEndpoint
    public let target: CaptureRelationEndpoint
    public let label: String?
    public let previousLabel: String?
    public let action: String
    /// Additive cancel-label effect on this edge: `cancelled` or
    /// `already_closed`. Older Bob and non-cancel labels omit it.
    public let cancelEffect: String?
    /// Additive complete-label effect on this edge: `completed` or
    /// `already_closed`. Older Bob and non-complete labels omit it.
    public let completeEffect: String?

    public init(
        direction: String = "to",
        source: CaptureRelationEndpoint = CaptureRelationEndpoint(),
        target: CaptureRelationEndpoint = CaptureRelationEndpoint(),
        label: String? = nil,
        previousLabel: String? = nil,
        action: String = "added",
        cancelEffect: String? = nil,
        completeEffect: String? = nil
    ) {
        self.direction = direction
        self.source = source
        self.target = target
        self.label = label
        self.previousLabel = previousLabel
        self.action = action
        self.cancelEffect = cancelEffect
        self.completeEffect = completeEffect
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direction = (try? container.decodeIfPresent(String.self, forKey: .direction)) ?? "to"
        source =
            (try? container.decodeIfPresent(CaptureRelationEndpoint.self, forKey: .source))
            ?? CaptureRelationEndpoint()
        target =
            (try? container.decodeIfPresent(CaptureRelationEndpoint.self, forKey: .target))
            ?? CaptureRelationEndpoint()
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? nil
        previousLabel = (try? container.decodeIfPresent(String.self, forKey: .previousLabel)) ?? nil
        action = (try? container.decodeIfPresent(String.self, forKey: .action)) ?? "added"
        cancelEffect = (try? container.decodeIfPresent(String.self, forKey: .cancelEffect)) ?? nil
        completeEffect = (try? container.decodeIfPresent(String.self, forKey: .completeEffect)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case direction
        case source
        case target
        case label
        case previousLabel = "previous_label"
        case action
        case cancelEffect = "cancel_effect"
        case completeEffect = "complete_effect"
    }
}

/// One cancel-label source this item retired or left closed. Bob authors
/// `message`; Swift renders it and computes no verdict.
public struct CaptureRelationCancel: Codable, Equatable, Sendable {
    public let source: CaptureRelationCancelEndpoint
    public let target: CaptureRelationCancelEndpoint
    public let labels: [String]
    public let action: String
    public let previousStatus: String
    public let previousStatusName: String
    public let projectOpenTasks: Int?
    public let cancelLog: String
    public let pomodoroLinksRemoved: Int
    public let recovered: [CaptureRelationCancelRecovered]
    public let message: String

    public init(
        source: CaptureRelationCancelEndpoint = CaptureRelationCancelEndpoint(),
        target: CaptureRelationCancelEndpoint = CaptureRelationCancelEndpoint(),
        labels: [String] = [],
        action: String = "added",
        previousStatus: String = "",
        previousStatusName: String = "",
        projectOpenTasks: Int? = nil,
        cancelLog: String = "none",
        pomodoroLinksRemoved: Int = 0,
        recovered: [CaptureRelationCancelRecovered] = [],
        message: String = ""
    ) {
        self.source = source
        self.target = target
        self.labels = labels
        self.action = action
        self.previousStatus = previousStatus
        self.previousStatusName = previousStatusName
        self.projectOpenTasks = projectOpenTasks
        self.cancelLog = cancelLog
        self.pomodoroLinksRemoved = pomodoroLinksRemoved
        self.recovered = recovered
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source =
            (try? container.decodeIfPresent(
                CaptureRelationCancelEndpoint.self,
                forKey: .source
            )) ?? CaptureRelationCancelEndpoint()
        target =
            (try? container.decodeIfPresent(
                CaptureRelationCancelEndpoint.self,
                forKey: .target
            )) ?? CaptureRelationCancelEndpoint()
        labels = (try? container.decodeIfPresent([String].self, forKey: .labels)) ?? []
        action = (try? container.decodeIfPresent(String.self, forKey: .action)) ?? "added"
        previousStatus =
            (try? container.decodeIfPresent(String.self, forKey: .previousStatus)) ?? ""
        previousStatusName =
            (try? container.decodeIfPresent(String.self, forKey: .previousStatusName)) ?? ""
        projectOpenTasks =
            (try? container.decodeIfPresent(Int.self, forKey: .projectOpenTasks)) ?? nil
        cancelLog = (try? container.decodeIfPresent(String.self, forKey: .cancelLog)) ?? "none"
        pomodoroLinksRemoved =
            (try? container.decodeIfPresent(Int.self, forKey: .pomodoroLinksRemoved)) ?? 0
        recovered =
            (try? container.decodeIfPresent(
                [CaptureRelationCancelRecovered].self,
                forKey: .recovered
            )) ?? []
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case target
        case labels
        case action
        case previousStatus = "previous_status"
        case previousStatusName = "previous_status_name"
        case projectOpenTasks = "project_open_tasks"
        case cancelLog = "cancel_log"
        case pomodoroLinksRemoved = "pomodoro_links_removed"
        case recovered
        case message
    }
}

/// One complete-label source this item completed. Bob authors `message`
/// and the nested `task_complete` (the same object `!note:id` reports);
/// Swift renders them and computes no verdict. Already-closed sources
/// keep `effect: AlreadyClosed` for the human line and are omitted from
/// the JSON `relation_completes[]`, so they never decode here.
public struct CaptureRelationComplete: Codable, Equatable, Sendable {
    public let source: CaptureRelationCancelEndpoint
    public let target: CaptureRelationCancelEndpoint
    public let labels: [String]
    public let action: String
    public let previousStatus: String
    public let previousStatusName: String
    public let projectOpenTasks: Int?
    public let taskComplete: CaptureTaskComplete?
    public let message: String

    public init(
        source: CaptureRelationCancelEndpoint = CaptureRelationCancelEndpoint(),
        target: CaptureRelationCancelEndpoint = CaptureRelationCancelEndpoint(),
        labels: [String] = [],
        action: String = "added",
        previousStatus: String = "",
        previousStatusName: String = "",
        projectOpenTasks: Int? = nil,
        taskComplete: CaptureTaskComplete? = nil,
        message: String = ""
    ) {
        self.source = source
        self.target = target
        self.labels = labels
        self.action = action
        self.previousStatus = previousStatus
        self.previousStatusName = previousStatusName
        self.projectOpenTasks = projectOpenTasks
        self.taskComplete = taskComplete
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source =
            (try? container.decodeIfPresent(
                CaptureRelationCancelEndpoint.self,
                forKey: .source
            )) ?? CaptureRelationCancelEndpoint()
        target =
            (try? container.decodeIfPresent(
                CaptureRelationCancelEndpoint.self,
                forKey: .target
            )) ?? CaptureRelationCancelEndpoint()
        labels = (try? container.decodeIfPresent([String].self, forKey: .labels)) ?? []
        action = (try? container.decodeIfPresent(String.self, forKey: .action)) ?? "added"
        previousStatus =
            (try? container.decodeIfPresent(String.self, forKey: .previousStatus)) ?? ""
        previousStatusName =
            (try? container.decodeIfPresent(String.self, forKey: .previousStatusName)) ?? ""
        projectOpenTasks =
            (try? container.decodeIfPresent(Int.self, forKey: .projectOpenTasks)) ?? nil
        taskComplete =
            (try? container.decodeIfPresent(CaptureTaskComplete.self, forKey: .taskComplete))
            ?? nil
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case target
        case labels
        case action
        case previousStatus = "previous_status"
        case previousStatusName = "previous_status_name"
        case projectOpenTasks = "project_open_tasks"
        case taskComplete = "task_complete"
        case message
    }
}

/// Source, target, or recovered endpoint of a `relation_cancels[]` row.
/// `line` is omitted on the surviving target.
public struct CaptureRelationCancelEndpoint: Codable, Equatable, Sendable {
    public let path: String
    public let line: Int?
    public let blockID: String
    public let text: String

    public init(
        path: String = "",
        line: Int? = nil,
        blockID: String = "",
        text: String = ""
    ) {
        self.path = path
        self.line = line
        self.blockID = blockID
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? nil
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case line
        case blockID = "block_id"
        case text
    }
}

/// One dependent a cancel-label source recovered, in vault order.
public struct CaptureRelationCancelRecovered: Codable, Equatable, Sendable {
    public let path: String
    public let line: Int
    public let blockID: String
    public let text: String

    public init(
        path: String = "",
        line: Int = 0,
        blockID: String = "",
        text: String = ""
    ) {
        self.path = path
        self.line = line
        self.blockID = blockID
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case line
        case blockID = "block_id"
        case text
    }
}

/// One courtesy LINKED FROM mirror write staged by a relation capture. Same
/// shape as Bob's `blocks_line_updates`; decoded tolerantly so a partial
/// object never fails the capture decode.
public struct CaptureBlocksLineUpdate: Codable, Equatable, Sendable {
    public let path: String
    public let line: Int
    public let task: String
    public let kind: String
    public let added: [String]
    public let removed: [String]

    public init(
        path: String = "",
        line: Int = 0,
        task: String = "",
        kind: String = "",
        added: [String] = [],
        removed: [String] = []
    ) {
        self.path = path
        self.line = line
        self.task = task
        self.kind = kind
        self.added = added
        self.removed = removed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        task = (try? container.decodeIfPresent(String.self, forKey: .task)) ?? ""
        kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        added = (try? container.decodeIfPresent([String].self, forKey: .added)) ?? []
        removed = (try? container.decodeIfPresent([String].self, forKey: .removed)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case line
        case task
        case kind
        case added
        case removed
    }
}

/// One block id Bob minted so a relation edge can name the source or the
/// `~~` target. `role` is `source` or `target`.
public struct CaptureMintedRelationBlockID: Codable, Equatable, Sendable {
    public let path: String
    public let line: Int
    public let blockID: String
    public let role: String

    public init(path: String = "", line: Int = 0, blockID: String = "", role: String = "source") {
        self.path = path
        self.line = line
        self.blockID = blockID
        self.role = role
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        role = (try? container.decodeIfPresent(String.self, forKey: .role)) ?? "source"
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case line
        case blockID = "block_id"
        case role
    }
}

/// One LINKED FROM courtesy write a relation capture skipped. `reason` is
/// `archived_target`, `previous_daily_target`, `malformed_line`, or
/// `disabled`.
public struct CaptureMirrorSkipped: Codable, Equatable, Sendable {
    public let path: String
    public let blockID: String
    public let reason: String

    public init(path: String = "", blockID: String = "", reason: String = "") {
        self.path = path
        self.blockID = blockID
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        reason = (try? container.decodeIfPresent(String.self, forKey: .reason)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case blockID = "block_id"
        case reason
    }
}

/// One embedded subtask closed by a whole-item `!note:block-id` completion.
/// Every field decodes tolerantly so a partial object still yields a row
/// instead of failing the whole capture.
public struct TaskCompleteSubtask: Codable, Equatable, Sendable {
    public let notePath: String
    public let blockID: String
    public let line: Int
    public let text: String
    public let previousStatusSymbol: String
    public let previousStatusName: String
    public let statusSymbol: String
    public let statusName: String

    public init(
        notePath: String = "",
        blockID: String = "",
        line: Int = 0,
        text: String = "",
        previousStatusSymbol: String = "",
        previousStatusName: String = "",
        statusSymbol: String = "",
        statusName: String = ""
    ) {
        self.notePath = notePath
        self.blockID = blockID
        self.line = line
        self.text = text
        self.previousStatusSymbol = previousStatusSymbol
        self.previousStatusName = previousStatusName
        self.statusSymbol = statusSymbol
        self.statusName = statusName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        previousStatusSymbol =
            try container.decodeIfPresent(String.self, forKey: .previousStatusSymbol) ?? ""
        previousStatusName =
            try container.decodeIfPresent(String.self, forKey: .previousStatusName) ?? ""
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol) ?? ""
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case notePath = "note_path"
        case blockID = "block_id"
        case line
        case text
        case previousStatusSymbol = "previous_status_symbol"
        case previousStatusName = "previous_status_name"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
    }
}

/// One descendant left open by a whole-item `!note:block-id` completion.
/// `reason` is `blocked`, `recurring`, `unknown_status`, or `cap`.
public struct TaskCompleteLeftOpen: Codable, Equatable, Sendable {
    public let notePath: String
    public let blockID: String
    public let line: Int
    public let text: String
    public let statusSymbol: String
    public let statusName: String
    public let reason: String

    public init(
        notePath: String = "",
        blockID: String = "",
        line: Int = 0,
        text: String = "",
        statusSymbol: String = "",
        statusName: String = "",
        reason: String = ""
    ) {
        self.notePath = notePath
        self.blockID = blockID
        self.line = line
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol) ?? ""
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName) ?? ""
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case notePath = "note_path"
        case blockID = "block_id"
        case line
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case reason
    }
}

/// One ledger endpoint for a `task_complete` move: 1-based line, short
/// entry name, and entry status.
public struct TaskCompleteLedgerEndpoint: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String
    public let status: String

    public init(line: Int = 0, name: String = "", status: String = "") {
        self.line = line
        self.name = name
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case status
    }
}

/// One moved bullet's source and destination ledger entries.
public struct TaskCompleteLedgerMove: Codable, Equatable, Sendable {
    public let from: TaskCompleteLedgerEndpoint
    public let to: TaskCompleteLedgerEndpoint

    public init(
        from: TaskCompleteLedgerEndpoint = TaskCompleteLedgerEndpoint(),
        to: TaskCompleteLedgerEndpoint = TaskCompleteLedgerEndpoint()
    ) {
        self.from = from
        self.to = to
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from =
            try container.decodeIfPresent(
                TaskCompleteLedgerEndpoint.self,
                forKey: .from
            ) ?? TaskCompleteLedgerEndpoint()
        to =
            try container.decodeIfPresent(
                TaskCompleteLedgerEndpoint.self,
                forKey: .to
            ) ?? TaskCompleteLedgerEndpoint()
    }

    private enum CodingKeys: String, CodingKey {
        case from
        case to
    }
}

/// One placeholder removed by a `task_complete` item.
public struct TaskCompleteRemovedPlaceholder: Codable, Equatable, Sendable {
    public let name: String

    public init(name: String = "") {
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case name
    }
}

/// Ledger retirement for a `task_complete` item, omitted when today's
/// ledger was untouched. `struckIn` and `dropped` are nil on older Bob
/// payloads that predate them, so the presentation can keep the
/// count-based wording as a fallback; new Bob always sends both arrays
/// (possibly empty) whenever `ledger` is present.
public struct TaskCompleteLedger: Codable, Equatable, Sendable {
    public let dayFile: String
    public let struck: Int
    public let struckIn: [TaskCompleteLedgerEndpoint]?
    public let moved: [TaskCompleteLedgerMove]
    public let deduplicated: Int
    public let dropped: [TaskCompleteLedgerMove]?
    public let removedPlaceholders: [TaskCompleteRemovedPlaceholder]

    public init(
        dayFile: String = "",
        struck: Int = 0,
        struckIn: [TaskCompleteLedgerEndpoint]? = nil,
        moved: [TaskCompleteLedgerMove] = [],
        deduplicated: Int = 0,
        dropped: [TaskCompleteLedgerMove]? = nil,
        removedPlaceholders: [TaskCompleteRemovedPlaceholder] = []
    ) {
        self.dayFile = dayFile
        self.struck = struck
        self.struckIn = struckIn
        self.moved = moved
        self.deduplicated = deduplicated
        self.dropped = dropped
        self.removedPlaceholders = removedPlaceholders
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayFile = try container.decodeIfPresent(String.self, forKey: .dayFile) ?? ""
        struck = try container.decodeIfPresent(Int.self, forKey: .struck) ?? 0
        struckIn = try container.decodeIfPresent(
            [TaskCompleteLedgerEndpoint].self,
            forKey: .struckIn
        )
        moved =
            try container.decodeIfPresent(
                [TaskCompleteLedgerMove].self,
                forKey: .moved
            ) ?? []
        deduplicated = try container.decodeIfPresent(Int.self, forKey: .deduplicated) ?? 0
        dropped = try container.decodeIfPresent(
            [TaskCompleteLedgerMove].self,
            forKey: .dropped
        )
        removedPlaceholders =
            try container.decodeIfPresent(
                [TaskCompleteRemovedPlaceholder].self,
                forKey: .removedPlaceholders
            ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case dayFile = "day_file"
        case struck
        case struckIn = "struck_in"
        case moved
        case deduplicated
        case dropped
        case removedPlaceholders = "removed_placeholders"
    }
}

/// One predecessor behind an unblocked row: the closed task whose
/// completion helped unblock the dependent. Every field decodes
/// tolerantly so one malformed cause never drops its row.
public struct TaskCompleteUnblockedCause: Codable, Equatable, Sendable {
    public let notePath: String
    public let blockID: String
    public let text: String

    public init(notePath: String = "", blockID: String = "", text: String = "") {
        self.notePath = notePath
        self.blockID = blockID
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notePath = (try? container.decodeIfPresent(String.self, forKey: .notePath)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case notePath = "note_path"
        case blockID = "block_id"
        case text
    }
}

/// Placement of one linked successor: the day-file bullet this gesture
/// inserted (`docs/task-dependencies.md` §12.5). Lines are 1-based in the
/// day text after the gesture. Every field decodes tolerantly so a
/// malformed link degrades its row to recovered instead of dropping it.
public struct TaskCompleteSuccessorLink: Codable, Equatable, Sendable {
    public let dayFile: String
    public let entryName: String
    public let entryLine: Int
    public let entryCreated: Bool
    public let nextUp: Bool
    public let line: Int
    public let blockLink: String
    public let blockIDCreated: Bool

    public init(
        dayFile: String = "",
        entryName: String = "",
        entryLine: Int = 0,
        entryCreated: Bool = false,
        nextUp: Bool = false,
        line: Int = 0,
        blockLink: String = "",
        blockIDCreated: Bool = false
    ) {
        self.dayFile = dayFile
        self.entryName = entryName
        self.entryLine = entryLine
        self.entryCreated = entryCreated
        self.nextUp = nextUp
        self.line = line
        self.blockLink = blockLink
        self.blockIDCreated = blockIDCreated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayFile = (try? container.decodeIfPresent(String.self, forKey: .dayFile)) ?? ""
        entryName = (try? container.decodeIfPresent(String.self, forKey: .entryName)) ?? ""
        entryLine = (try? container.decodeIfPresent(Int.self, forKey: .entryLine)) ?? 0
        entryCreated = (try? container.decodeIfPresent(Bool.self, forKey: .entryCreated)) ?? false
        nextUp = (try? container.decodeIfPresent(Bool.self, forKey: .nextUp)) ?? false
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        blockLink = (try? container.decodeIfPresent(String.self, forKey: .blockLink)) ?? ""
        blockIDCreated =
            (try? container.decodeIfPresent(
                Bool.self,
                forKey: .blockIDCreated
            )) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case dayFile = "day_file"
        case entryName = "entry_name"
        case entryLine = "entry_line"
        case entryCreated = "entry_created"
        case nextUp = "next_up"
        case line
        case blockLink = "block_link"
        case blockIDCreated = "block_id_created"
    }
}

/// A destination selected by Bob's successor-offer planner. Values remain
/// opaque presentation metadata; the client does not derive eligibility.
public struct TaskCompleteOfferDestination: Codable, Equatable, Sendable {
    public let dayFile: String
    public let entryName: String
    public let entryRole: String
    public let fallback: Bool

    public init(
        dayFile: String = "",
        entryName: String = "",
        entryRole: String = "",
        fallback: Bool = false
    ) {
        self.dayFile = dayFile
        self.entryName = entryName
        self.entryRole = entryRole
        self.fallback = fallback
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayFile = (try? container.decodeIfPresent(String.self, forKey: .dayFile)) ?? ""
        entryName = (try? container.decodeIfPresent(String.self, forKey: .entryName)) ?? ""
        entryRole = (try? container.decodeIfPresent(String.self, forKey: .entryRole)) ?? ""
        fallback = (try? container.decodeIfPresent(Bool.self, forKey: .fallback)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case dayFile = "day_file"
        case entryName = "entry_name"
        case entryRole = "entry_role"
        case fallback
    }
}

/// Bob-issued opaque identity for one successor candidate. Never parse or
/// reconstruct `key`; it may contain separators or digest suffixes.
public struct TaskCompleteOfferClose: Codable, Equatable, Sendable {
    public let complete: Bool
    public let cancel: Bool
    public let why: String?
    public let completeConsequence: String?
    public let cancelConsequence: String?
    public let scopeNote: String?
    public let unblocks: Int

    public init(
        complete: Bool = false,
        cancel: Bool = false,
        why: String? = nil,
        completeConsequence: String? = nil,
        cancelConsequence: String? = nil,
        scopeNote: String? = nil,
        unblocks: Int = 0
    ) {
        self.complete = complete
        self.cancel = cancel
        self.why = why
        self.completeConsequence = completeConsequence
        self.cancelConsequence = cancelConsequence
        self.scopeNote = scopeNote
        self.unblocks = unblocks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        complete = (try? container.decodeIfPresent(Bool.self, forKey: .complete)) ?? false
        cancel = (try? container.decodeIfPresent(Bool.self, forKey: .cancel)) ?? false
        why = try? container.decodeIfPresent(String.self, forKey: .why)
        completeConsequence =
            try? container.decodeIfPresent(String.self, forKey: .completeConsequence)
        cancelConsequence = try? container.decodeIfPresent(String.self, forKey: .cancelConsequence)
        scopeNote = try? container.decodeIfPresent(String.self, forKey: .scopeNote)
        unblocks = (try? container.decodeIfPresent(Int.self, forKey: .unblocks)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case complete
        case cancel
        case why
        case completeConsequence = "complete_consequence"
        case cancelConsequence = "cancel_consequence"
        case scopeNote = "scope_note"
        case unblocks
    }
}

/// One dependent Bob recovered while applying an offer verdict.
public struct CaptureOfferCloseRecovered: Codable, Equatable, Sendable {
    public let notePath: String
    public let blockID: String
    public let text: String
    public let previousStatusName: String
    public let statusName: String
    public let unblockedStamped: Bool

    public init(
        notePath: String = "",
        blockID: String = "",
        text: String = "",
        previousStatusName: String = "",
        statusName: String = "",
        unblockedStamped: Bool = false
    ) {
        self.notePath = notePath
        self.blockID = blockID
        self.text = text
        self.previousStatusName = previousStatusName
        self.statusName = statusName
        self.unblockedStamped = unblockedStamped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notePath = (try? container.decodeIfPresent(String.self, forKey: .notePath)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        previousStatusName =
            (try? container.decodeIfPresent(String.self, forKey: .previousStatusName)) ?? ""
        statusName = (try? container.decodeIfPresent(String.self, forKey: .statusName)) ?? ""
        unblockedStamped =
            (try? container.decodeIfPresent(Bool.self, forKey: .unblockedStamped)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case notePath = "note_path"
        case blockID = "block_id"
        case text
        case previousStatusName = "previous_status_name"
        case statusName = "status_name"
        case unblockedStamped = "unblocked_stamped"
    }
}

/// Bob's exact receipt for one offer row resolved as Done or Cancel.
public struct CaptureOfferClose: Codable, Equatable, Sendable {
    public let n: Int
    public let key: String
    public let outcome: String
    public let reason: String?
    public let notePath: String
    public let line: Int
    public let blockID: String
    public let text: String
    public let previousStatus: String
    public let previousStatusName: String
    public let cancelLog: String?
    public let recovered: [CaptureOfferCloseRecovered]
    public let message: String

    public init(
        n: Int = 0,
        key: String = "",
        outcome: String = "",
        reason: String? = nil,
        notePath: String = "",
        line: Int = 0,
        blockID: String = "",
        text: String = "",
        previousStatus: String = "",
        previousStatusName: String = "",
        cancelLog: String? = nil,
        recovered: [CaptureOfferCloseRecovered] = [],
        message: String = ""
    ) {
        self.n = n
        self.key = key
        self.outcome = outcome
        self.reason = reason
        self.notePath = notePath
        self.line = line
        self.blockID = blockID
        self.text = text
        self.previousStatus = previousStatus
        self.previousStatusName = previousStatusName
        self.cancelLog = cancelLog
        self.recovered = recovered
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        n = (try? container.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        outcome = (try? container.decodeIfPresent(String.self, forKey: .outcome)) ?? ""
        reason = try? container.decodeIfPresent(String.self, forKey: .reason)
        notePath = (try? container.decodeIfPresent(String.self, forKey: .notePath)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        previousStatus =
            (try? container.decodeIfPresent(String.self, forKey: .previousStatus)) ?? ""
        previousStatusName =
            (try? container.decodeIfPresent(String.self, forKey: .previousStatusName)) ?? ""
        cancelLog = try? container.decodeIfPresent(String.self, forKey: .cancelLog)
        recovered =
            (try? container.decodeIfPresent(
                [CaptureOfferCloseRecovered].self,
                forKey: .recovered
            )) ?? []
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case n
        case key
        case outcome
        case reason
        case notePath = "note_path"
        case line
        case blockID = "block_id"
        case text
        case previousStatus = "previous_status"
        case previousStatusName = "previous_status_name"
        case cancelLog = "cancel_log"
        case recovered
        case message
    }
}

/// The refused row returned with `offer_close_refused`.
public struct CaptureOfferCloseRefused: Codable, Equatable, Sendable {
    public let key: String
    public let n: Int
    public let outcome: String?
    public let why: String?

    public init(key: String = "", n: Int = 0, outcome: String? = nil, why: String? = nil) {
        self.key = key
        self.n = n
        self.outcome = outcome
        self.why = why
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        n = (try? container.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        outcome = try? container.decodeIfPresent(String.self, forKey: .outcome)
        why = try? container.decodeIfPresent(String.self, forKey: .why)
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case n
        case outcome
        case why
    }
}

public struct TaskCompleteOffer: Codable, Equatable, Sendable {
    public let key: String
    public let n: Int
    public let group: String
    public let project: String?
    /// Opaque target identity used to join relation rows to their group.
    public let after: String?
    public let destination: TaskCompleteOfferDestination
    public let selected: Bool
    public let blockIDNeeded: Bool
    /// Source parent for a moved project offer (`cash.md` on a `^`/`:` row).
    /// Absent on every other offer; older Bob binaries never send it.
    public let movedFrom: String?
    /// Requested source note of a note-pull offer (`work.md`). A later move in
    /// the same draft changes the row's `note_path`, never this. Absent on
    /// other offers and from older Bob binaries.
    public let note: String?
    /// Source task that was merged when this hand-off was offered.
    /// Absent on other offers and from older Bob binaries.
    public let mergedFrom: String?
    /// Bob's row-specific eligibility and consequence copy. Missing on older Bob.
    public let close: TaskCompleteOfferClose?
    /// `done` or `cancelled` when this commit resolves the row instead of pulling it in.
    public let verdict: String?

    public init(
        key: String = "",
        n: Int = 0,
        group: String = "",
        project: String? = nil,
        after: String? = nil,
        destination: TaskCompleteOfferDestination = TaskCompleteOfferDestination(),
        selected: Bool = false,
        blockIDNeeded: Bool = false,
        movedFrom: String? = nil,
        note: String? = nil,
        mergedFrom: String? = nil,
        close: TaskCompleteOfferClose? = nil,
        verdict: String? = nil
    ) {
        self.key = key
        self.n = n
        self.group = group
        self.project = project
        self.after = after
        self.destination = destination
        self.selected = selected
        self.blockIDNeeded = blockIDNeeded
        self.movedFrom = movedFrom
        self.note = note
        self.mergedFrom = mergedFrom
        self.close = close
        self.verdict = verdict
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        n = (try? container.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        group = (try? container.decodeIfPresent(String.self, forKey: .group)) ?? ""
        project = try? container.decodeIfPresent(String.self, forKey: .project)
        after = try? container.decodeIfPresent(String.self, forKey: .after)
        destination =
            (try? container.decode(
                TaskCompleteOfferDestination.self,
                forKey: .destination
            )) ?? TaskCompleteOfferDestination()
        selected = (try? container.decodeIfPresent(Bool.self, forKey: .selected)) ?? false
        blockIDNeeded = (try? container.decodeIfPresent(Bool.self, forKey: .blockIDNeeded)) ?? false
        movedFrom = try? container.decodeIfPresent(String.self, forKey: .movedFrom)
        note = try? container.decodeIfPresent(String.self, forKey: .note)
        mergedFrom = try? container.decodeIfPresent(String.self, forKey: .mergedFrom)
        close = try? container.decodeIfPresent(TaskCompleteOfferClose.self, forKey: .close)
        verdict = try? container.decodeIfPresent(String.self, forKey: .verdict)
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case n
        case group
        case project
        case after
        case destination
        case selected
        case blockIDNeeded = "block_id_needed"
        case movedFrom = "moved_from"
        case note
        case mergedFrom = "merged_from"
        case close
        case verdict
    }
}

public struct CapturePullInFolded: Codable, Equatable, Sendable {
    public let blocked: Int
    public let scheduled: Int
    public let alreadyStarted: Int
    public let waitsFor: Int
    public let hidden: Int
    public let alreadyPlanned: Int
    public let subProjects: Int

    public init(
        blocked: Int = 0,
        scheduled: Int = 0,
        alreadyStarted: Int = 0,
        waitsFor: Int = 0,
        hidden: Int = 0,
        alreadyPlanned: Int = 0,
        subProjects: Int = 0
    ) {
        self.blocked = blocked
        self.scheduled = scheduled
        self.alreadyStarted = alreadyStarted
        self.waitsFor = waitsFor
        self.hidden = hidden
        self.alreadyPlanned = alreadyPlanned
        self.subProjects = subProjects
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blocked = (try? container.decodeIfPresent(Int.self, forKey: .blocked)) ?? 0
        scheduled = (try? container.decodeIfPresent(Int.self, forKey: .scheduled)) ?? 0
        alreadyStarted = (try? container.decodeIfPresent(Int.self, forKey: .alreadyStarted)) ?? 0
        waitsFor = (try? container.decodeIfPresent(Int.self, forKey: .waitsFor)) ?? 0
        hidden = (try? container.decodeIfPresent(Int.self, forKey: .hidden)) ?? 0
        alreadyPlanned = (try? container.decodeIfPresent(Int.self, forKey: .alreadyPlanned)) ?? 0
        subProjects = (try? container.decodeIfPresent(Int.self, forKey: .subProjects)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case blocked
        case scheduled
        case alreadyStarted = "already_started"
        case waitsFor = "waits_for"
        case hidden
        case alreadyPlanned = "already_planned"
        case subProjects = "sub_projects"
    }
}

public struct CapturePullInGroup: Codable, Equatable, Sendable {
    public let group: String
    public let project: String?
    /// Note path for `note_pull` sections. Older groups omit it.
    public let note: String?
    public let after: CapturePullInAfter?
    public let label: String?
    public let event: String?
    public let folded: CapturePullInFolded?
    public let copy: CapturePullInGroupCopy?

    public init(
        group: String = "",
        project: String? = nil,
        note: String? = nil,
        after: CapturePullInAfter? = nil,
        label: String? = nil,
        event: String? = nil,
        folded: CapturePullInFolded? = nil,
        copy: CapturePullInGroupCopy? = nil
    ) {
        self.group = group
        self.project = project
        self.note = note
        self.after = after
        self.label = label
        self.event = event
        self.folded = folded
        self.copy = copy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        group = (try? container.decodeIfPresent(String.self, forKey: .group)) ?? ""
        project = try? container.decodeIfPresent(String.self, forKey: .project)
        note = try? container.decodeIfPresent(String.self, forKey: .note)
        after = try? container.decodeIfPresent(CapturePullInAfter.self, forKey: .after)
        label = try? container.decodeIfPresent(String.self, forKey: .label)
        event = try? container.decodeIfPresent(String.self, forKey: .event)
        folded = try? container.decodeIfPresent(CapturePullInFolded.self, forKey: .folded)
        copy = try? container.decodeIfPresent(CapturePullInGroupCopy.self, forKey: .copy)
    }

    private enum CodingKeys: String, CodingKey {
        case group
        case project
        case note
        case after
        case label
        case event
        case folded
        case copy
    }
}

/// Additive capability and result counts for capture offer verdicts.
public struct CapturePullInClose: Codable, Equatable, Sendable {
    public let supported: Bool
    public let doneCount: Int
    public let cancelledCount: Int

    public init(supported: Bool = false, doneCount: Int = 0, cancelledCount: Int = 0) {
        self.supported = supported
        self.doneCount = doneCount
        self.cancelledCount = cancelledCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supported = (try? container.decodeIfPresent(Bool.self, forKey: .supported)) ?? false
        doneCount = (try? container.decodeIfPresent(Int.self, forKey: .doneCount)) ?? 0
        cancelledCount = (try? container.decodeIfPresent(Int.self, forKey: .cancelledCount)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case supported
        case doneCount = "done_count"
        case cancelledCount = "cancelled_count"
    }
}

public struct CapturePullIn: Codable, Equatable, Sendable {
    public let supported: Bool
    public let offerCount: Int
    public let choice: String?
    public let pickedCount: Int
    public let groups: [CapturePullInGroup]
    public let copy: CapturePullInCopy?
    /// Missing on older Bob; this nested capability gates offer-verdict argv.
    public let close: CapturePullInClose?

    public init(
        supported: Bool = false,
        offerCount: Int = 0,
        choice: String? = nil,
        pickedCount: Int = 0,
        groups: [CapturePullInGroup] = [],
        copy: CapturePullInCopy? = nil,
        close: CapturePullInClose? = nil
    ) {
        self.supported = supported
        self.offerCount = offerCount
        self.choice = choice
        self.pickedCount = pickedCount
        self.groups = groups
        self.copy = copy
        self.close = close
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supported = (try? container.decodeIfPresent(Bool.self, forKey: .supported)) ?? false
        offerCount = (try? container.decodeIfPresent(Int.self, forKey: .offerCount)) ?? 0
        choice = try? container.decodeIfPresent(String.self, forKey: .choice)
        pickedCount = (try? container.decodeIfPresent(Int.self, forKey: .pickedCount)) ?? 0
        groups = (try? container.decodeIfPresent([CapturePullInGroup].self, forKey: .groups)) ?? []
        copy = try? container.decodeIfPresent(CapturePullInCopy.self, forKey: .copy)
        close = try? container.decodeIfPresent(CapturePullInClose.self, forKey: .close)
    }

    private enum CodingKeys: String, CodingKey {
        case supported
        case offerCount = "offer_count"
        case choice
        case pickedCount = "picked_count"
        case groups
        case copy
        case close
    }
}

/// Bob's note-pull result or refusal payload. The same tolerant shape is
/// used for successful offers and `nothing_to_pull_in` failures.
public struct CaptureNotePull: Codable, Equatable, Sendable {
    public let note: String
    public let route: String
    public let successors: [TaskCompleteUnblocked]
    public let folded: CapturePullInFolded?

    public init(
        note: String = "",
        route: String = "",
        successors: [TaskCompleteUnblocked] = [],
        folded: CapturePullInFolded? = nil
    ) {
        self.note = note
        self.route = route
        self.successors = successors
        self.folded = folded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        note = (try? container.decodeIfPresent(String.self, forKey: .note)) ?? ""
        route = (try? container.decodeIfPresent(String.self, forKey: .route)) ?? ""
        successors = (try? container.decodeIfPresent([TaskCompleteUnblocked].self, forKey: .successors)) ?? []
        folded = (try? container.decodeIfPresent(CapturePullInFolded.self, forKey: .folded)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case note
        case route
        case successors
        case folded
    }
}

/// One dependent unblocked by a `task_complete` item: linked into its
/// predecessor's slot (`link` non-nil), or recovered with the reason it
/// was not linked (`notLinked`). The successor-link fields are additive
/// under schema version 1; each decodes individually and tolerantly so a
/// malformed field degrades the row instead of failing the capture.
public struct TaskCompleteUnblocked: Codable, Equatable, Sendable {
    public let notePath: String
    public let blockID: String
    public let line: Int
    public let text: String
    public let previousStatusSymbol: String
    public let previousStatusName: String
    public let statusSymbol: String
    public let statusName: String
    public let inbox: Bool
    public let unblockedBy: [TaskCompleteUnblockedCause]
    public let link: TaskCompleteSuccessorLink?
    public let notLinked: String?
    public let offer: TaskCompleteOffer?
    public let trigger: String?
    public let hideRemoved: Bool
    /// Bob's relation reason, either the winning group or a secondary reason.
    public let relation: CaptureRelationMetadata?

    public init(
        notePath: String = "",
        blockID: String = "",
        line: Int = 0,
        text: String = "",
        previousStatusSymbol: String = "",
        previousStatusName: String = "",
        statusSymbol: String = "",
        statusName: String = "",
        inbox: Bool = false,
        unblockedBy: [TaskCompleteUnblockedCause] = [],
        link: TaskCompleteSuccessorLink? = nil,
        notLinked: String? = nil,
        offer: TaskCompleteOffer? = nil,
        trigger: String? = nil,
        hideRemoved: Bool = false,
        relation: CaptureRelationMetadata? = nil
    ) {
        self.notePath = notePath
        self.blockID = blockID
        self.line = line
        self.text = text
        self.previousStatusSymbol = previousStatusSymbol
        self.previousStatusName = previousStatusName
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.inbox = inbox
        self.unblockedBy = unblockedBy
        self.link = link
        self.notLinked = notLinked
        self.offer = offer
        self.trigger = trigger
        self.hideRemoved = hideRemoved
        self.relation = relation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notePath = (try? container.decodeIfPresent(String.self, forKey: .notePath)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        previousStatusSymbol =
            (try? container.decodeIfPresent(
                String.self,
                forKey: .previousStatusSymbol
            )) ?? ""
        previousStatusName =
            (try? container.decodeIfPresent(
                String.self,
                forKey: .previousStatusName
            )) ?? ""
        statusSymbol = (try? container.decodeIfPresent(String.self, forKey: .statusSymbol)) ?? ""
        statusName = (try? container.decodeIfPresent(String.self, forKey: .statusName)) ?? ""
        inbox = (try? container.decodeIfPresent(Bool.self, forKey: .inbox)) ?? false
        unblockedBy =
            (try? container.decodeIfPresent(
                [TaskCompleteUnblockedCause].self,
                forKey: .unblockedBy
            )) ?? []
        link =
            (try? container.decodeIfPresent(
                TaskCompleteSuccessorLink.self,
                forKey: .link
            )) ?? nil
        notLinked = (try? container.decodeIfPresent(String.self, forKey: .notLinked)) ?? nil
        offer = (try? container.decodeIfPresent(TaskCompleteOffer.self, forKey: .offer)) ?? nil
        trigger = try? container.decodeIfPresent(String.self, forKey: .trigger)
        hideRemoved = (try? container.decodeIfPresent(Bool.self, forKey: .hideRemoved)) ?? false
        relation = try? container.decodeIfPresent(CaptureRelationMetadata.self, forKey: .relation)
    }

    private enum CodingKeys: String, CodingKey {
        case notePath = "note_path"
        case blockID = "block_id"
        case line
        case text
        case previousStatusSymbol = "previous_status_symbol"
        case previousStatusName = "previous_status_name"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case inbox
        case unblockedBy = "unblocked_by"
        case link
        case notLinked = "not_linked"
        case offer
        case trigger
        case hideRemoved = "hide_removed"
        case relation
    }
}

/// One open dependent of the completed tasks that stays blocked: it
/// still waits on other prerequisites (`waits_on`) or on a future
/// `scheduled` date. Every field decodes tolerantly so one malformed
/// row never drops its siblings.
public struct TaskCompleteStillBlocked: Codable, Equatable, Sendable {
    public let notePath: String
    public let blockID: String
    public let line: Int
    public let text: String
    public let statusSymbol: String
    public let statusName: String
    public let reason: String
    public let waitsOn: Int
    public let scheduled: String?
    public let project: String?
    public let trigger: String?

    public init(
        notePath: String = "",
        blockID: String = "",
        line: Int = 0,
        text: String = "",
        statusSymbol: String = "",
        statusName: String = "",
        reason: String = "",
        waitsOn: Int = 0,
        scheduled: String? = nil,
        project: String? = nil,
        trigger: String? = nil
    ) {
        self.notePath = notePath
        self.blockID = blockID
        self.line = line
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.reason = reason
        self.waitsOn = waitsOn
        self.scheduled = scheduled
        self.project = project
        self.trigger = trigger
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notePath = (try? container.decodeIfPresent(String.self, forKey: .notePath)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        statusSymbol = (try? container.decodeIfPresent(String.self, forKey: .statusSymbol)) ?? ""
        statusName = (try? container.decodeIfPresent(String.self, forKey: .statusName)) ?? ""
        reason = (try? container.decodeIfPresent(String.self, forKey: .reason)) ?? ""
        waitsOn = (try? container.decodeIfPresent(Int.self, forKey: .waitsOn)) ?? 0
        scheduled = (try? container.decodeIfPresent(String.self, forKey: .scheduled)) ?? nil
        project = try? container.decodeIfPresent(String.self, forKey: .project)
        trigger = try? container.decodeIfPresent(String.self, forKey: .trigger)
    }

    private enum CodingKeys: String, CodingKey {
        case notePath = "note_path"
        case blockID = "block_id"
        case line
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case reason
        case waitsOn = "waits_on"
        case scheduled
        case project
        case trigger
    }
}

/// Bob's resolved preview for a whole-item `!note:block-id` completion.
/// Additive to capture schema v1 and absent on older Bob binaries. Every
/// field decodes tolerantly so a partial object still previews instead of
/// failing the whole capture. `subtasks`, `subtasks_left_open`, and
/// `unblocked` are always present (possibly empty) on a real Bob response;
/// `ledger` is omitted when today's ledger was untouched and
/// `completion_date` is omitted when `action` is `already_done`.
public struct CaptureTaskComplete: Codable, Equatable, Sendable {
    public let raw: String
    public let note: String
    public let notePath: String
    public let blockID: String
    public let action: String
    public let completionDate: String?
    /// Clean display text for the root task from Bob (configured global
    /// filter, inline fields, and trailing block ID stripped). Empty on
    /// older Bob payloads, which omit the key.
    public let text: String
    public let subtasks: [TaskCompleteSubtask]
    public let subtasksLeftOpen: [TaskCompleteLeftOpen]
    public let ledger: TaskCompleteLedger?
    public let unblocked: [TaskCompleteUnblocked]
    public let keepMoving: [TaskCompleteUnblocked]
    public let relationSuccessors: [TaskCompleteUnblocked]
    public let relationHeld: [CaptureRelationHeld]
    public let relationCheck: String?
    public let stillBlocked: [TaskCompleteStillBlocked]
    public let unblockedCheck: String?

    public init(
        raw: String = "",
        note: String = "",
        notePath: String = "",
        blockID: String = "",
        action: String = "",
        completionDate: String? = nil,
        text: String = "",
        subtasks: [TaskCompleteSubtask] = [],
        subtasksLeftOpen: [TaskCompleteLeftOpen] = [],
        ledger: TaskCompleteLedger? = nil,
        unblocked: [TaskCompleteUnblocked] = [],
        keepMoving: [TaskCompleteUnblocked] = [],
        relationSuccessors: [TaskCompleteUnblocked] = [],
        relationHeld: [CaptureRelationHeld] = [],
        relationCheck: String? = nil,
        stillBlocked: [TaskCompleteStillBlocked] = [],
        unblockedCheck: String? = nil
    ) {
        self.raw = raw
        self.note = note
        self.notePath = notePath
        self.blockID = blockID
        self.action = action
        self.completionDate = completionDate
        self.text = text
        self.subtasks = subtasks
        self.subtasksLeftOpen = subtasksLeftOpen
        self.ledger = ledger
        self.unblocked = unblocked
        self.keepMoving = keepMoving
        self.relationSuccessors = relationSuccessors
        self.relationHeld = relationHeld
        self.relationCheck = relationCheck
        self.stillBlocked = stillBlocked
        self.unblockedCheck = unblockedCheck
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
        completionDate = try container.decodeIfPresent(String.self, forKey: .completionDate)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        subtasks =
            try container.decodeIfPresent(
                [TaskCompleteSubtask].self,
                forKey: .subtasks
            ) ?? []
        subtasksLeftOpen =
            try container.decodeIfPresent(
                [TaskCompleteLeftOpen].self,
                forKey: .subtasksLeftOpen
            ) ?? []
        ledger = try container.decodeIfPresent(TaskCompleteLedger.self, forKey: .ledger)
        // Each successor array decodes on its own: one malformed row must
        // never drop the whole completion card (the outer `taskComplete`
        // decode already tolerates a malformed object, but a malformed
        // element would otherwise wipe every sibling row).
        unblocked =
            (try? container.decodeIfPresent(
                [TaskCompleteUnblocked].self,
                forKey: .unblocked
            )) ?? []
        keepMoving =
            (try? container.decodeIfPresent(
                [TaskCompleteUnblocked].self,
                forKey: .keepMoving
            )) ?? []
        relationSuccessors =
            (try? container.decodeIfPresent(
                [TaskCompleteUnblocked].self,
                forKey: .relationSuccessors
            )) ?? []
        relationHeld =
            (try? container.decodeIfPresent(
                [CaptureRelationHeld].self,
                forKey: .relationHeld
            )) ?? []
        relationCheck =
            (try? container.decodeIfPresent(String.self, forKey: .relationCheck)) ?? nil
        stillBlocked =
            (try? container.decodeIfPresent(
                [TaskCompleteStillBlocked].self,
                forKey: .stillBlocked
            )) ?? []
        unblockedCheck =
            (try? container.decodeIfPresent(
                String.self,
                forKey: .unblockedCheck
            )) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case note
        case notePath = "note_path"
        case blockID = "block_id"
        case action
        case completionDate = "completion_date"
        case text
        case subtasks
        case subtasksLeftOpen = "subtasks_left_open"
        case ledger
        case unblocked
        case keepMoving = "keep_moving"
        case relationSuccessors = "relation_successors"
        case relationHeld = "relation_held"
        case relationCheck = "relation_check"
        case stillBlocked = "still_blocked"
        case unblockedCheck = "unblocked_check"
    }
}

public struct CaptureCommandFailure: Codable, Equatable {
    public let ok: Bool
    public let error: String
    // Additive machine-readable failure code for refusals Bob classifies, such as the
    // incomplete or unknown `%` and `#` markers (`incomplete_directive`, `type_marker_needs_task`,
    // `unknown_directive`). Other failures and older Bob omit it, and it decodes as nil.
    public let code: String?
    public let pullIn: CapturePullIn?
    /// Additive payload for `nothing_to_pull_in`; absent on older Bob and
    /// on other refusal codes.
    public let notePull: CaptureNotePull?
    /// Read-only resolved source context for an unfinished capture transfer.
    /// Older Bob omits it; malformed additive data degrades to nil.
    public let transferPending: CaptureTransferPending?
    /// Read-only resolved source context for an unfinished merge-in whose
    /// sources are still being typed (`incomplete_merge_in`). Older Bob
    /// omits it; malformed additive data degrades to nil.
    public let mergeInPending: CaptureMergeInPending?
    public let offers: [TaskCompleteUnblocked]
    /// Additive batch-level inbox-route payload on
    /// `inbox_route_choice_required`, `inbox_route_refused`, and
    /// `inbox_route_stale`. Older Bob omits it; a malformed value decodes
    /// as nil so it can never fail the failure decode.
    public let inboxRoute: CaptureInboxRoute?
    /// Additive batch-level move-choice payload on `move_choice_*`
    /// refusals. Older Bob omits it; malformed data degrades to nil.
    public let moveChoice: CaptureMoveChoice?
    /// Additive refused-route detail on `inbox_route_refused` (`key`, `n`,
    /// `destination`, `message`). Older Bob omits it; malformed decodes as
    /// nil.
    public let refused: CaptureInboxRouteRefused?
    /// Refused offer-close row, when this failure's code is
    /// `offer_close_refused`.
    public var offerCloseRefused: CaptureOfferCloseRefused? {
        guard code == "offer_close_refused", let refused else {
            return nil
        }
        return CaptureOfferCloseRefused(
            key: refused.key,
            n: refused.n,
            outcome: refused.outcome,
            why: refused.why
        )
    }

    public init(
        ok: Bool = false,
        error: String,
        code: String? = nil,
        pullIn: CapturePullIn? = nil,
        notePull: CaptureNotePull? = nil,
        transferPending: CaptureTransferPending? = nil,
        mergeInPending: CaptureMergeInPending? = nil,
        offers: [TaskCompleteUnblocked] = [],
        inboxRoute: CaptureInboxRoute? = nil,
        moveChoice: CaptureMoveChoice? = nil,
        refused: CaptureInboxRouteRefused? = nil
    ) {
        self.ok = ok
        self.error = error
        self.code = code
        self.pullIn = pullIn
        self.notePull = notePull
        self.transferPending = transferPending
        self.mergeInPending = mergeInPending
        self.offers = offers
        self.inboxRoute = inboxRoute
        self.moveChoice = moveChoice
        self.refused = refused
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        error = try container.decodeIfPresent(String.self, forKey: .error) ?? ""
        code = try container.decodeIfPresent(String.self, forKey: .code)
        pullIn = (try? container.decodeIfPresent(CapturePullIn.self, forKey: .pullIn)) ?? nil
        notePull = (try? container.decodeIfPresent(CaptureNotePull.self, forKey: .notePull)) ?? nil
        transferPending =
            (try? container.decodeIfPresent(CaptureTransferPending.self, forKey: .transferPending))
            ?? nil
        mergeInPending =
            (try? container.decodeIfPresent(CaptureMergeInPending.self, forKey: .mergeInPending))
            ?? nil
        offers = (try? container.decodeIfPresent([TaskCompleteUnblocked].self, forKey: .offers)) ?? []
        inboxRoute =
            (try? container.decodeIfPresent(CaptureInboxRoute.self, forKey: .inboxRoute)) ?? nil
        moveChoice =
            (try? container.decodeIfPresent(CaptureMoveChoice.self, forKey: .moveChoice)) ?? nil
        refused =
            (try? container.decodeIfPresent(CaptureInboxRouteRefused.self, forKey: .refused)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case error
        case code
        case pullIn = "pull_in"
        case notePull = "note_pull"
        case transferPending = "transfer_pending"
        case mergeInPending = "merge_in_pending"
        case offers
        case inboxRoute = "inbox_route"
        case moveChoice = "move_choice"
        case refused
    }
}

public enum CaptureTaskIDResponse: Equatable, Decodable {
    case success(CaptureTaskIDSuccess)
    case failure(CaptureCommandFailure)

    public var ok: Bool {
        switch self {
        case .success(let value):
            return value.ok
        case .failure(let value):
            return value.ok
        }
    }

    private enum DiscriminatorKeys: String, CodingKey {
        case ok
    }

    public init(from decoder: Decoder) throws {
        let discriminator = try decoder.container(keyedBy: DiscriminatorKeys.self)
        if try discriminator.decode(Bool.self, forKey: .ok) {
            self = .success(try CaptureTaskIDSuccess(from: decoder))
        } else {
            self = .failure(try CaptureCommandFailure(from: decoder))
        }
    }
}

public struct CaptureTaskIDSuccess: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let dryRun: Bool
    public let route: String
    public let relativeTarget: String
    public let blockID: String
    public let line: Int
    public let taskRef: String
    public let task: CaptureTaskIDTask
    /// Exact vault-relative note path including extension, present in
    /// `--note-path` mode so the app can resume the picker without losing
    /// quoting or case. Older Bob omits it; decode as nil.
    public let notePath: String?
    /// Backend-formatted `&note:id` (quoted when the locator needs it) to
    /// splice on a successful explicit ID assignment. Older Bob omits it;
    /// decode as nil.
    public let dependencyReplacement: String?
    /// Backend-formatted `@route+id` to splice on a successful vault-wide
    /// parent-task ID assignment. Older Bob omits it; decode as nil.
    public let parentReplacement: String?
    /// Backend-formatted `!note:id` (quoted when the locator needs it) to
    /// splice on a successful Complete picker ID assignment. Older Bob
    /// omits it; decode as nil.
    public let completeReplacement: String?
    /// Backend-formatted `*note:id` for a successful Blocks picker ID assignment.
    public let blockedTaskReplacement: String?
    /// Backend-formatted `~note:id` for a successful links-to ID assignment.
    /// Older Bob omits it; decode as nil.
    public let relationToReplacement: String?
    /// Backend-formatted `~~note:id` for a successful linked-from ID assignment.
    /// Older Bob omits it; decode as nil.
    public let relationFromReplacement: String?
    /// Backend-formatted `[[target#^id]]` for a successful Task Wikilink
    /// (`((`) ID assignment. Older Bob omits it; decode as nil.
    public let wikilinkReplacement: String?

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        dryRun: Bool,
        route: String,
        relativeTarget: String,
        blockID: String,
        line: Int,
        taskRef: String,
        task: CaptureTaskIDTask,
        notePath: String? = nil,
        dependencyReplacement: String? = nil,
        parentReplacement: String? = nil,
        completeReplacement: String? = nil,
        blockedTaskReplacement: String? = nil,
        relationToReplacement: String? = nil,
        relationFromReplacement: String? = nil,
        wikilinkReplacement: String? = nil
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.dryRun = dryRun
        self.route = route
        self.relativeTarget = relativeTarget
        self.blockID = blockID
        self.line = line
        self.taskRef = taskRef
        self.task = task
        self.notePath = notePath
        self.dependencyReplacement = dependencyReplacement
        self.parentReplacement = parentReplacement
        self.completeReplacement = completeReplacement
        self.blockedTaskReplacement = blockedTaskReplacement
        self.relationToReplacement = relationToReplacement
        self.relationFromReplacement = relationFromReplacement
        self.wikilinkReplacement = wikilinkReplacement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
        // `--note-path` responses omit `route`; the exact path is the
        // identity there, so a missing route decodes as empty.
        route = try container.decodeIfPresent(String.self, forKey: .route) ?? ""
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        taskRef = try container.decodeIfPresent(String.self, forKey: .taskRef) ?? ""
        task = try container.decode(CaptureTaskIDTask.self, forKey: .task)
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath)
        dependencyReplacement = try container.decodeIfPresent(
            String.self, forKey: .dependencyReplacement)
        parentReplacement = try container.decodeIfPresent(String.self, forKey: .parentReplacement)
        completeReplacement = try container.decodeIfPresent(String.self, forKey: .completeReplacement)
        blockedTaskReplacement =
            (try? container.decodeIfPresent(String.self, forKey: .blockedTaskReplacement)) ?? nil
        relationToReplacement =
            (try? container.decodeIfPresent(String.self, forKey: .relationToReplacement)) ?? nil
        relationFromReplacement =
            (try? container.decodeIfPresent(String.self, forKey: .relationFromReplacement)) ?? nil
        wikilinkReplacement =
            (try? container.decodeIfPresent(String.self, forKey: .wikilinkReplacement)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case dryRun = "dry_run"
        case route
        case relativeTarget = "relative_target"
        case blockID = "block_id"
        case line
        case taskRef = "ref"
        case task
        case notePath = "note_path"
        case dependencyReplacement = "dependency_replacement"
        case parentReplacement = "parent_replacement"
        case completeReplacement = "complete_replacement"
        case blockedTaskReplacement = "blocked_task_replacement"
        case relationToReplacement = "relation_to_replacement"
        case relationFromReplacement = "relation_from_replacement"
        case wikilinkReplacement = "wikilink_replacement"
    }
}

public struct CaptureTaskIDTask: Codable, Equatable {
    public let taskRef: String
    public let line: Int
    public let blockID: String
    public let statusSymbol: String
    public let statusName: String
    public let statusType: String
    public let text: String
    public let section: String?
    public let depth: Int
    public let childCount: Int

    public init(
        taskRef: String,
        line: Int,
        blockID: String,
        statusSymbol: String,
        statusName: String,
        statusType: String,
        text: String,
        section: String? = nil,
        depth: Int,
        childCount: Int
    ) {
        self.taskRef = taskRef
        self.line = line
        self.blockID = blockID
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.statusType = statusType
        self.text = text
        self.section = section
        self.depth = depth
        self.childCount = childCount
    }

    private enum CodingKeys: String, CodingKey {
        case taskRef = "ref"
        case line
        case blockID = "block_id"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case statusType = "status_type"
        case text
        case section
        case depth
        case childCount = "child_count"
    }
}

public enum CapturePomodoroNameResponse: Equatable, Decodable {
    case success(CapturePomodoroNameSuccess)
    case failure(CaptureCommandFailure)

    public var ok: Bool {
        switch self {
        case .success(let value):
            return value.ok
        case .failure(let value):
            return value.ok
        }
    }

    private enum DiscriminatorKeys: String, CodingKey {
        case ok
    }

    public init(from decoder: Decoder) throws {
        let discriminator = try decoder.container(keyedBy: DiscriminatorKeys.self)
        if try discriminator.decode(Bool.self, forKey: .ok) {
            self = .success(try CapturePomodoroNameSuccess(from: decoder))
        } else {
            self = .failure(try CaptureCommandFailure(from: decoder))
        }
    }
}

public struct CapturePomodoroNameSuccess: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let dryRun: Bool
    public let dayFile: String
    public let relativeDayFile: String
    public let name: String
    public let slug: String
    public let line: Int
    public let pomodoroRef: String
    public let pomodoro: CapturePomodoroEntry
    /// Structured `theme_not_configured` warnings when the name is outside
    /// the configured vocabulary. Older Bob omits the key; decode as empty.
    public let warnings: [CaptureWarning]

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        dryRun: Bool,
        dayFile: String,
        relativeDayFile: String,
        name: String,
        slug: String,
        line: Int,
        pomodoroRef: String,
        pomodoro: CapturePomodoroEntry,
        warnings: [CaptureWarning] = []
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.dryRun = dryRun
        self.dayFile = dayFile
        self.relativeDayFile = relativeDayFile
        self.name = name
        self.slug = slug
        self.line = line
        self.pomodoroRef = pomodoroRef
        self.pomodoro = pomodoro
        self.warnings = warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        dryRun = try container.decode(Bool.self, forKey: .dryRun)
        dayFile = try container.decode(String.self, forKey: .dayFile)
        relativeDayFile = try container.decode(String.self, forKey: .relativeDayFile)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decode(String.self, forKey: .slug)
        line = try container.decode(Int.self, forKey: .line)
        pomodoroRef = try container.decode(String.self, forKey: .pomodoroRef)
        pomodoro = try container.decode(CapturePomodoroEntry.self, forKey: .pomodoro)
        warnings =
            (try? container.decodeIfPresent([CaptureWarning].self, forKey: .warnings)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case dryRun = "dry_run"
        case dayFile = "day_file"
        case relativeDayFile = "relative_day_file"
        case name
        case slug
        case line
        case pomodoroRef = "ref"
        case pomodoro
        case warnings
    }
}

public struct CapturePomodoroEntry: Codable, Equatable {
    public let pomodoroRef: String
    public let line: Int
    public let state: String
    public let statusSymbol: String
    public let name: String?
    public let slug: String
    public let selectable: Bool
    public let timeRange: String?
    public let placeholder: Bool
    public let isCurrent: Bool
    public let childCount: Int
    /// Bob's canonical named-start spelling (`=bugs`, `=#deep-work`).
    /// Nil on an older Bob that omits `start_token`.
    public let startToken: String?

    public init(
        pomodoroRef: String,
        line: Int,
        state: String,
        statusSymbol: String,
        name: String? = nil,
        slug: String,
        selectable: Bool,
        timeRange: String? = nil,
        placeholder: Bool,
        isCurrent: Bool,
        childCount: Int,
        startToken: String? = nil
    ) {
        self.pomodoroRef = pomodoroRef
        self.line = line
        self.state = state
        self.statusSymbol = statusSymbol
        self.name = name
        self.slug = slug
        self.selectable = selectable
        self.timeRange = timeRange
        self.placeholder = placeholder
        self.isCurrent = isCurrent
        self.childCount = childCount
        self.startToken = startToken
    }

    private enum CodingKeys: String, CodingKey {
        case pomodoroRef = "ref"
        case line
        case state
        case statusSymbol = "status_symbol"
        case name
        case slug
        case selectable
        case timeRange = "time_range"
        case placeholder
        case isCurrent = "is_current"
        case childCount = "child_count"
        case startToken = "start_token"
    }
}

/// The `clip` object on a capture reply. A `%c` that Bob read has `status: "read"`, a
/// `mode` (`inline`, `lines`, `attachments`, `snippet`, or `history`), and the rendered
/// child `lines`, `attachments`, optional `snippet`, and history `entries` (each entry is
/// itself a read clip object). A `%c` that Bob was told not to read has only
/// `status: "not_read"` and the requested `count`: no mode and no collections.
///
/// `status` is required and never defaulted, and a read clip must carry its `mode`, so a
/// reply that predates this contract fails to decode instead of looking like a clip that
/// was read. Collections tolerate omission and decode as empty.
public struct CaptureClipOutput: Codable, Equatable, Sendable {
    /// `read` or `not_read`. A value this client does not know still decodes.
    public let status: String
    /// The requested entry count (`%c` is 1). Present only when `status == "not_read"`.
    public let count: Int?
    /// Present exactly when `status == "read"`.
    public let mode: String?
    public let lines: [String]
    public let attachments: [CaptureAttachmentOutput]
    public let snippet: String?
    public let entries: [CaptureClipOutput]
    /// `%c<N>` provenance (`clip.history`): which clipboard manager supplied
    /// the entries plus per-entry ages and apps. Nil for a single `%c`, for an
    /// older bob that omits `history`, and for a malformed value, which never
    /// breaks clip decoding.
    public let history: CaptureClipHistory?

    public static let readStatus = "read"
    public static let notReadStatus = "not_read"

    public var wasRead: Bool { status == Self.readStatus }

    public init(
        status: String = CaptureClipOutput.readStatus,
        count: Int? = nil,
        mode: String? = nil,
        lines: [String] = [],
        attachments: [CaptureAttachmentOutput] = [],
        snippet: String? = nil,
        entries: [CaptureClipOutput] = [],
        history: CaptureClipHistory? = nil
    ) {
        self.status = status
        self.count = count
        self.mode = mode
        self.lines = lines
        self.attachments = attachments
        self.snippet = snippet
        self.entries = entries
        self.history = history
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        count = (try? container.decodeIfPresent(Int.self, forKey: .count)) ?? nil
        if status == Self.notReadStatus {
            mode = nil
        } else {
            mode = try container.decode(String.self, forKey: .mode)
        }
        lines = try container.decodeIfPresent([String].self, forKey: .lines) ?? []
        attachments =
            try container.decodeIfPresent([CaptureAttachmentOutput].self, forKey: .attachments) ?? []
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        entries = try container.decodeIfPresent([CaptureClipOutput].self, forKey: .entries) ?? []
        history = try? container.decodeIfPresent(CaptureClipHistory.self, forKey: .history)
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case count
        case mode
        case lines
        case attachments
        case snippet
        case entries
        case history
    }
}

/// Provenance for a `%c<N>` history read: the clipboard manager that supplied
/// the entries (`alfred`, `clipy`, `command`, or a future provider key) plus
/// per-entry ages and apps aligned with the aggregate clip's `entries`.
public struct CaptureClipHistory: Codable, Equatable, Sendable {
    public let provider: String
    public let entries: [CaptureClipHistoryEntry]

    public init(provider: String, entries: [CaptureClipHistoryEntry] = []) {
        self.provider = provider
        self.entries = entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        entries =
            try container.decodeIfPresent(
                [CaptureClipHistoryEntry].self, forKey: .entries) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case entries
    }
}

/// One `%c<N>` provenance entry: seconds since the row was copied
/// (`age_seconds`, nil when the provider stores no timestamp) and the source
/// app (`app`, nil when unknown).
public struct CaptureClipHistoryEntry: Codable, Equatable, Sendable {
    public let ageSeconds: Int?
    public let app: String?

    public init(ageSeconds: Int? = nil, app: String? = nil) {
        self.ageSeconds = ageSeconds
        self.app = app
    }

    private enum CodingKeys: String, CodingKey {
        case ageSeconds = "age_seconds"
        case app
    }
}

public struct CaptureAttachmentOutput: Codable, Equatable, Sendable {
    public let source: String
    public let saved: String
    public let kind: String
    public let reused: Bool

    public init(source: String, saved: String, kind: String, reused: Bool) {
        self.source = source
        self.saved = saved
        self.kind = kind
        self.reused = reused
    }
}

public struct CaptureScheduleLog: Codable, Equatable, Sendable {
    public let reason: String
    public let lines: [String]

    public init(reason: String, lines: [String]) {
        self.reason = reason
        self.lines = lines
    }
}

public struct CaptureTargetsResponse: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let bobDirectory: String?
    public let count: Int?
    public let targets: [CaptureTarget]

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        bobDirectory: String? = nil,
        count: Int? = nil,
        targets: [CaptureTarget]
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.bobDirectory = bobDirectory
        self.count = count
        self.targets = targets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        bobDirectory = try container.decodeIfPresent(String.self, forKey: .bobDirectory)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        targets = try container.decodeIfPresent([CaptureTarget].self, forKey: .targets) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case bobDirectory = "bob_dir"
        case count
        case targets
    }
}

public struct CaptureTarget: Codable, Equatable, Identifiable {
    public let route: String
    public let name: String
    public let label: String
    public let kind: String
    public let isDefault: Bool
    public let status: String?
    public let relativePath: String
    /// Frontmatter `project_name_aliases` on the area or project note. Bob
    /// omits the key for older builds and sends `[]` when the note has no
    /// aliases; a mistyped value decodes as empty so it can never fail the
    /// targets decode.
    public let projectNameAliases: [String]
    /// Record type id, present only on configured record-folder rows.
    /// Older Bob omits it; missing decodes as nil.
    public let recordType: String?
    /// Record type emoji, present only on configured record-folder rows.
    public let emoji: String?
    /// Indexed note count, present only on configured record-folder rows.
    public let count: Int?

    public var id: String { route }

    public init(
        route: String,
        name: String,
        label: String,
        kind: String,
        isDefault: Bool = false,
        status: String? = nil,
        relativePath: String,
        projectNameAliases: [String] = [],
        recordType: String? = nil,
        emoji: String? = nil,
        count: Int? = nil
    ) {
        self.route = route
        self.name = name
        self.label = label
        self.kind = kind
        self.isDefault = isDefault
        self.status = status
        self.relativePath = relativePath
        self.projectNameAliases = projectNameAliases
        self.recordType = recordType
        self.emoji = emoji
        self.count = count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        route = try container.decode(String.self, forKey: .route)
        name = try container.decode(String.self, forKey: .name)
        label = try container.decode(String.self, forKey: .label)
        kind = try container.decode(String.self, forKey: .kind)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        status = try container.decodeIfPresent(String.self, forKey: .status)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        let decodedAliases: [String]?? =
            try? container.decodeIfPresent([String].self, forKey: .projectNameAliases)
        switch decodedAliases {
        case .some(.some(let aliases)):
            projectNameAliases = aliases
        default:
            projectNameAliases = []
        }
        recordType = (try? container.decodeIfPresent(String.self, forKey: .recordType)) ?? nil
        emoji = (try? container.decodeIfPresent(String.self, forKey: .emoji)) ?? nil
        count = (try? container.decodeIfPresent(Int.self, forKey: .count)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(route, forKey: .route)
        try container.encode(name, forKey: .name)
        try container.encode(label, forKey: .label)
        try container.encode(kind, forKey: .kind)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(projectNameAliases, forKey: .projectNameAliases)
        try container.encodeIfPresent(recordType, forKey: .recordType)
        try container.encodeIfPresent(emoji, forKey: .emoji)
        try container.encodeIfPresent(count, forKey: .count)
    }

    private enum CodingKeys: String, CodingKey {
        case route
        case name
        case label
        case kind
        case isDefault = "is_default"
        case status
        case relativePath = "relative_path"
        case projectNameAliases = "project_name_aliases"
        case recordType = "type"
        case emoji
        case count
    }
}

public struct CaptureTargetSection: Codable, Equatable, Identifiable {
    public let name: String
    public let anchor: String?

    public var id: String { anchor ?? name }

    public init(name: String, anchor: String? = nil) {
        self.name = name
        self.anchor = anchor
    }
}

/// The running session a `=#` name field would override, from Bob's
/// additive top-level `override` object on a `pomodoro_start_name`
/// completion. `pomodoroName` is absent for an unnamed running session;
/// `line` is the 1-based day-file line and `timeRange` the ledger span the
/// swap keeps (`0920-0945`). Older Bob omits the whole object.
public struct CaptureCompleteOverrideRunning: Codable, Equatable, Sendable {
    public let pomodoroName: String?
    public let line: Int?
    public let timeRange: String?
    /// Derived homes for an unnamed running session. Older Bob omits this field.
    public let homes: CaptureAgendaHomes?

    public init(
        pomodoroName: String? = nil,
        line: Int? = nil,
        timeRange: String? = nil,
        homes: CaptureAgendaHomes? = nil
    ) {
        self.pomodoroName = pomodoroName
        self.line = line
        self.timeRange = timeRange
        self.homes = homes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        homes = try container.decodeIfPresent(CaptureAgendaHomes.self, forKey: .homes)
    }

    private enum CodingKeys: String, CodingKey {
        case pomodoroName = "pomodoro_name"
        case line
        case timeRange = "time_range"
        case homes
    }
}

/// Additive override context for a `pomodoro_start_name` field when exactly
/// one session runs and no earlier item is a whole-item session operator.
/// Present for `=#` (and counted `=3#`) while a session runs. `keepsLedger`
/// is true when the `<X>` suffix is empty (a swap takes over the running
/// ledger byte-for-byte); `running` is always set when the object is
/// present. Older Bob omits it, so missing decodes as nil.
public struct CaptureCompleteOverride: Codable, Equatable, Sendable {
    public let keepsLedger: Bool
    public let running: CaptureCompleteOverrideRunning?

    public init(keepsLedger: Bool, running: CaptureCompleteOverrideRunning? = nil) {
        self.keepsLedger = keepsLedger
        self.running = running
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keepsLedger = try container.decodeIfPresent(Bool.self, forKey: .keepsLedger) ?? false
        running = try container.decodeIfPresent(CaptureCompleteOverrideRunning.self, forKey: .running)
    }

    private enum CodingKeys: String, CodingKey {
        case keepsLedger = "keeps_ledger"
        case running
    }
}

/// Additive relation token metadata on Bob's `relation_label` completion.
/// Ranges are UTF-8 byte offsets into the original draft.
public struct CaptureCompletionRelation: Codable, Equatable {
    public let direction: String
    public let range: CaptureRange

    public init(direction: String, range: CaptureRange) {
        self.direction = direction
        self.range = range
    }
}

public struct CaptureCompletionResponse: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    /// Top-level capture-language revision; see `CaptureParseResponse.grammar`. A Bob that
    /// predates the field omits it, and that stays nil rather than a guessed revision.
    public let grammar: Int?
    public let cursor: Int
    public let replacement: CaptureRange
    public let context: String?
    public let candidates: [CaptureCompletionCandidate]
    public let warnings: [String]
    /// Additive `initial_selection`. Bob sends `none` for a bare `%` or `#` menu that opens
    /// with nothing selected, in every completion context. Omission keeps the existing
    /// first-row, best-match, or suggested-row selection; see `opensWithoutSelection`.
    public let initialSelection: String?
    /// Additive top-level `override` object, present when the name field is
    /// a `=#` start while a session runs. Older Bob omits it; then the rows
    /// and picker status read as a plain start.
    public let overrideInfo: CaptureCompleteOverride?
    /// Additive top-level `block_id` object, present exactly when the context
    /// is `pomodoro_block_id` or `task_block_id`. Older Bob binaries omit it;
    /// the Block ID picker treats that as Link intent without New ID rows.
    public let blockID: CaptureBlockIDField?
    /// Decoded `task_dependency` or `blocked_task` query (sigil stripped,
    /// one opening quote stripped, `\"`/`\\` resolved), so the app never
    /// parses quoted note components itself. Omitted elsewhere and by older
    /// Bob payloads.
    public let query: String?
    /// Lexical owner of the `task_dependency` or `blocked_task` modifier
    /// under the cursor (the capture-parse `dependency_target` for the
    /// cursor's item), or the owner of a `relation_label` field.
    public let owner: DependencyOwner?
    /// Additive `relation_label` token metadata. Older Bob omits it; clients
    /// can then use their legacy relation-token fallback.
    public let relation: CaptureCompletionRelation?
    /// Additive parent-task picker descriptor on `task` and `task_parent`
    /// responses. Older Bob omits it; scoped `task` without one keeps the
    /// inline parent-task list.
    public let picker: CapturePickerDescriptor?
    /// Additive move-picker header on `project_task_move` responses.
    /// Older Bob omits it; missing decodes as nil so old builds stay calm.
    public let projectTaskMove: CaptureProjectTaskMoveHeader?
    /// Additive `relation_label` hidden count: how many catalog labels are
    /// hidden from suggestions in this context. Present (possibly 0) on
    /// `relation_label` responses; older Bob omits it.
    public let hiddenCount: Int?
    /// Additive `relation_label` one-off flag: true when the probe sits in a
    /// `||` label. Omitted from every other context and from `|` probes.
    public let oneOff: Bool?
    /// Additive cancel-label consequence for the token under the cursor.
    /// Present only when at least one cancel label is configured. Older Bob
    /// omits it; missing decodes as nil so the card stays inert.
    public let relationCancel: CaptureCompletionRelationCancel?
    /// Additive complete-label consequence for the token under the cursor.
    /// Present only when at least one complete label is configured. Older
    /// Bob omits it; missing decodes as nil so the card stays inert.
    public let relationComplete: CaptureCompletionRelationComplete?
    /// Additive Bob-authored successor-label consequence or inverse hint.
    /// Inverse hints can omit `verdict`; the client preserves both as sent.
    public let relationSuccessor: CaptureCompletionRelationSuccessor?
    /// Additive task-theme suggestion for the `pomodoro_name` context.
    /// `Some(null)` (no suggestion) and a missing key both decode as nil.
    /// Older Bob omits it; missing keeps today's default.
    public let themeSuggestion: CaptureThemeSuggestion?
    /// Additive `task_type` subject: `new` or `existing`. Older Bob omits
    /// it; missing decodes as nil so other contexts stay unchanged.
    public let subject: String?
    /// Additive `drawer` target: the task whose drawers the menu lists. Present
    /// on every `drawer` response, with or without rows, so the header can name
    /// the task. Older Bob and every other context omit it.
    public let target: CaptureDrawerTarget?
    /// Additive record metadata on `record_field`/`record_value` responses.
    /// Older Bob and every other context omit it.
    public let record: CaptureRecordCompletionMeta?

    /// Whether Bob asked for this menu to open with no selected row. Any other value,
    /// including a future one this client does not know, keeps the default selection.
    public var opensWithoutSelection: Bool { initialSelection == "none" }

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        grammar: Int? = nil,
        cursor: Int,
        replacement: CaptureRange,
        context: String?,
        candidates: [CaptureCompletionCandidate],
        warnings: [String] = [],
        initialSelection: String? = nil,
        blockID: CaptureBlockIDField? = nil,
        query: String? = nil,
        owner: DependencyOwner? = nil,
        relation: CaptureCompletionRelation? = nil,
        picker: CapturePickerDescriptor? = nil,
        overrideInfo: CaptureCompleteOverride? = nil,
        hiddenCount: Int? = nil,
        oneOff: Bool? = nil,
        relationCancel: CaptureCompletionRelationCancel? = nil,
        relationComplete: CaptureCompletionRelationComplete? = nil,
        relationSuccessor: CaptureCompletionRelationSuccessor? = nil,
        themeSuggestion: CaptureThemeSuggestion? = nil,
        subject: String? = nil,
        target: CaptureDrawerTarget? = nil,
        projectTaskMove: CaptureProjectTaskMoveHeader? = nil,
        record: CaptureRecordCompletionMeta? = nil
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.grammar = grammar
        self.cursor = cursor
        self.replacement = replacement
        self.context = context
        self.candidates = candidates
        self.warnings = warnings
        self.initialSelection = initialSelection
        self.blockID = blockID
        self.query = query
        self.owner = owner
        self.relation = relation
        self.picker = picker
        self.overrideInfo = overrideInfo
        self.hiddenCount = hiddenCount
        self.oneOff = oneOff
        self.relationCancel = relationCancel
        self.relationComplete = relationComplete
        self.relationSuccessor = relationSuccessor
        self.themeSuggestion = themeSuggestion
        self.subject = subject
        self.target = target
        self.projectTaskMove = projectTaskMove
        self.record = record
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        grammar = (try? container.decodeIfPresent(Int.self, forKey: .grammar)) ?? nil
        cursor = try container.decode(Int.self, forKey: .cursor)
        replacement = try container.decode(CaptureRange.self, forKey: .replacement)
        context = try container.decodeIfPresent(String.self, forKey: .context)
        candidates =
            try container.decodeIfPresent([CaptureCompletionCandidate].self, forKey: .candidates) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        initialSelection =
            (try? container.decodeIfPresent(String.self, forKey: .initialSelection)) ?? nil
        blockID = try container.decodeIfPresent(CaptureBlockIDField.self, forKey: .blockID)
        query = try container.decodeIfPresent(String.self, forKey: .query)
        owner = try container.decodeIfPresent(DependencyOwner.self, forKey: .owner)
        relation = try container.decodeIfPresent(CaptureCompletionRelation.self, forKey: .relation)
        picker = try container.decodeIfPresent(CapturePickerDescriptor.self, forKey: .picker)
        overrideInfo = try container.decodeIfPresent(
            CaptureCompleteOverride.self, forKey: .overrideInfo)
        hiddenCount = (try? container.decodeIfPresent(Int.self, forKey: .hiddenCount)) ?? nil
        oneOff = (try? container.decodeIfPresent(Bool.self, forKey: .oneOff)) ?? nil
        relationCancel =
            (try? container.decodeIfPresent(
                CaptureCompletionRelationCancel.self,
                forKey: .relationCancel
            )) ?? nil
        relationComplete =
            (try? container.decodeIfPresent(
                CaptureCompletionRelationComplete.self,
                forKey: .relationComplete
            )) ?? nil
        relationSuccessor =
            (try? container.decodeIfPresent(
                CaptureCompletionRelationSuccessor.self,
                forKey: .relationSuccessor
            )) ?? nil
        themeSuggestion =
            (try? container.decodeIfPresent(
                CaptureThemeSuggestion.self,
                forKey: .themeSuggestion
            )) ?? nil
        subject = (try? container.decodeIfPresent(String.self, forKey: .subject)) ?? nil
        target = (try? container.decodeIfPresent(CaptureDrawerTarget.self, forKey: .target)) ?? nil
        projectTaskMove = (try? container.decodeIfPresent(CaptureProjectTaskMoveHeader.self, forKey: .projectTaskMove)) ?? nil
        record = (try? container.decodeIfPresent(CaptureRecordCompletionMeta.self, forKey: .record)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case grammar
        case cursor
        case replacement
        case context
        case candidates
        case warnings
        case initialSelection = "initial_selection"
        case blockID = "block_id"
        case query
        case owner
        case relation
        case picker
        case overrideInfo = "override"
        case hiddenCount = "hidden_count"
        case oneOff = "one_off"
        case relationCancel = "relation_cancel"
        case relationComplete = "relation_complete"
        case relationSuccessor = "relation_successor"
        case themeSuggestion = "theme_suggestion"
        case subject
        case target
        case projectTaskMove = "project_task_move"
        case record
    }

}

/// The task a `drawer` completion menu lists drawers for. `route` is Bob's
/// route label (`foo.md`), `blockID` is nil when the task has no ID, and
/// `text` is the task description (empty when the task did not resolve).
public struct CaptureDrawerTarget: Codable, Equatable, Sendable {
    public let route: String
    public let blockID: String?
    public let text: String

    public init(route: String, blockID: String? = nil, text: String = "") {
        self.route = route
        self.blockID = blockID
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        route = try container.decode(String.self, forKey: .route)
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? nil
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case route
        case blockID = "block_id"
        case text
    }
}

/// The drawer a sub-bullet capture lands in, from Bob's per-item `drawer`
/// object. `created` is true when the commit adds the drawer's header line.
public struct CaptureDrawerSummary: Codable, Equatable, Sendable {
    public let title: String
    public let key: String
    public let created: Bool

    public init(title: String, key: String = "", created: Bool = false) {
        self.title = title
        self.key = key.isEmpty ? title : key
        self.created = created
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? title
        created = (try? container.decodeIfPresent(Bool.self, forKey: .created)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case key
        case created
    }
}

/// One authored note from the additive multi-note capture output. The drawer
/// summary is nil for a plain note and populated when the note was filed into a
/// drawer.
public struct CaptureNoteSummary: Codable, Equatable, Sendable {
    public let text: String
    public let taskLine: String
    public let subBullets: [String]
    public let drawer: CaptureDrawerSummary?

    public init(
        text: String,
        taskLine: String = "",
        subBullets: [String] = [],
        drawer: CaptureDrawerSummary? = nil
    ) {
        self.text = text
        self.taskLine = taskLine
        self.subBullets = subBullets
        self.drawer = drawer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        taskLine = try container.decodeIfPresent(String.self, forKey: .taskLine) ?? ""
        subBullets = try container.decodeIfPresent([String].self, forKey: .subBullets) ?? []
        drawer = (try? container.decodeIfPresent(CaptureDrawerSummary.self, forKey: .drawer)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case taskLine = "task_line"
        case subBullets = "sub_bullets"
        case drawer
    }
}

/// The cancel consequence of the `relation_label` token under the cursor.
/// Present only when at least one cancel label is configured. Swift
/// renders `message` and `hint` and computes no verdict.
public struct CaptureCompletionRelationCancel: Codable, Equatable, Sendable {
    public let source: CaptureCompletionRelationCancelSource
    /// `cancels` | `already_closed` | `recurring` | `new_task`.
    public let verdict: String
    public let message: String
    public let hint: String?

    public init(
        source: CaptureCompletionRelationCancelSource = CaptureCompletionRelationCancelSource(),
        verdict: String = "",
        message: String = "",
        hint: String? = nil
    ) {
        self.source = source
        self.verdict = verdict
        self.message = message
        self.hint = hint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source =
            (try? container.decodeIfPresent(
                CaptureCompletionRelationCancelSource.self,
                forKey: .source
            )) ?? CaptureCompletionRelationCancelSource()
        verdict = (try? container.decodeIfPresent(String.self, forKey: .verdict)) ?? ""
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
        hint = (try? container.decodeIfPresent(String.self, forKey: .hint)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case verdict
        case message
        case hint
    }
}

/// The relation source a cancel label would cancel. `block_id` is omitted
/// for ID-less owners; `project_open_tasks` counts open tasks when the
/// source is a `^prj`. `status_symbol` is a one-character JSON string.
public struct CaptureCompletionRelationCancelSource: Codable, Equatable, Sendable {
    public let path: String
    public let blockID: String?
    public let text: String
    public let statusSymbol: String
    public let statusName: String
    public let projectOpenTasks: Int?

    public init(
        path: String = "",
        blockID: String? = nil,
        text: String = "",
        statusSymbol: String = "",
        statusName: String = "",
        projectOpenTasks: Int? = nil
    ) {
        self.path = path
        self.blockID = blockID
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.projectOpenTasks = projectOpenTasks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? nil
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        statusSymbol = (try? container.decodeIfPresent(String.self, forKey: .statusSymbol)) ?? ""
        statusName = (try? container.decodeIfPresent(String.self, forKey: .statusName)) ?? ""
        projectOpenTasks =
            (try? container.decodeIfPresent(Int.self, forKey: .projectOpenTasks)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case blockID = "block_id"
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case projectOpenTasks = "project_open_tasks"
    }
}

/// The complete consequence of the `relation_label` token under the cursor.
/// Present only when at least one complete label is configured. Swift
/// renders `message` and `hint` and computes no verdict.
public struct CaptureCompletionRelationComplete: Codable, Equatable, Sendable {
    public let source: CaptureCompletionRelationCompleteSource
    /// `completes` | `already_closed` | `recurring` | `new_task`.
    public let verdict: String
    public let message: String
    public let hint: String?

    public init(
        source: CaptureCompletionRelationCompleteSource = CaptureCompletionRelationCompleteSource(),
        verdict: String = "",
        message: String = "",
        hint: String? = nil
    ) {
        self.source = source
        self.verdict = verdict
        self.message = message
        self.hint = hint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source =
            (try? container.decodeIfPresent(
                CaptureCompletionRelationCompleteSource.self,
                forKey: .source
            )) ?? CaptureCompletionRelationCompleteSource()
        verdict = (try? container.decodeIfPresent(String.self, forKey: .verdict)) ?? ""
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
        hint = (try? container.decodeIfPresent(String.self, forKey: .hint)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case verdict
        case message
        case hint
    }
}

/// The relation source a complete label would complete. `block_id` is
/// omitted for ID-less owners; `project_open_tasks` counts open tasks when
/// the source is a `^prj`. `status_symbol` is a one-character JSON string.
public struct CaptureCompletionRelationCompleteSource: Codable, Equatable, Sendable {
    public let path: String
    public let blockID: String?
    public let text: String
    public let statusSymbol: String
    public let statusName: String
    public let projectOpenTasks: Int?

    public init(
        path: String = "",
        blockID: String? = nil,
        text: String = "",
        statusSymbol: String = "",
        statusName: String = "",
        projectOpenTasks: Int? = nil
    ) {
        self.path = path
        self.blockID = blockID
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.projectOpenTasks = projectOpenTasks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? nil
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        statusSymbol = (try? container.decodeIfPresent(String.self, forKey: .statusSymbol)) ?? ""
        statusName = (try? container.decodeIfPresent(String.self, forKey: .statusName)) ?? ""
        projectOpenTasks =
            (try? container.decodeIfPresent(Int.self, forKey: .projectOpenTasks)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case blockID = "block_id"
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case projectOpenTasks = "project_open_tasks"
    }
}

/// Additive server-authored picker lifecycle metadata for parent-task
/// completion. All ranges are half-open UTF-8 byte offsets into the draft.
/// Older Bob omits the whole object, so missing decodes as nil.
public struct CapturePickerDescriptor: Codable, Equatable, Sendable {
    public let kind: String
    public let scope: String
    public let scopeToken: String
    public let noteTarget: String?
    public let markerRange: CaptureRange
    public let triggerRemovalRange: CaptureRange
    public let actionContinuationKeys: [String]
    /// Additive alias map for operator-continuation keys (for example
    /// `{".": "^"}` on `- ^` or `{",": "+"}` on a lone `+`). Older Bob omits it.
    public let actionContinuationAliases: [String: String]
    /// Additive owner-mode descriptor on `+` / `@route+` pickers inside a
    /// relationship draft. Older Bob omits it.
    public let relationship: CapturePickerRelationship?
    /// Additive move-picker destination (`cash_goog_exit.md`). Only the
    /// `project_task_move` descriptor sends it; older Bob omits it.
    public let destination: String?
    /// Additive accept-and-continue suffix (for example `"\n- ^"` or
    /// `" +"`). Move and eligible Parent Task descriptors send it; older Bob
    /// omits it.
    public let continuation: String?

    public init(
        kind: String,
        scope: String,
        scopeToken: String,
        noteTarget: String? = nil,
        markerRange: CaptureRange,
        triggerRemovalRange: CaptureRange,
        actionContinuationKeys: [String] = [],
        actionContinuationAliases: [String: String] = [:],
        relationship: CapturePickerRelationship? = nil,
        destination: String? = nil,
        continuation: String? = nil
    ) {
        self.kind = kind
        self.scope = scope
        self.scopeToken = scopeToken
        self.noteTarget = noteTarget
        self.markerRange = markerRange
        self.triggerRemovalRange = triggerRemovalRange
        self.actionContinuationKeys = actionContinuationKeys
        self.actionContinuationAliases = actionContinuationAliases
        self.relationship = relationship
        self.destination = destination
        self.continuation = continuation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        scope = try container.decodeIfPresent(String.self, forKey: .scope) ?? ""
        scopeToken = try container.decodeIfPresent(String.self, forKey: .scopeToken) ?? ""
        noteTarget = try container.decodeIfPresent(String.self, forKey: .noteTarget)
        markerRange =
            try container.decodeIfPresent(CaptureRange.self, forKey: .markerRange)
            ?? CaptureRange(start: 0, end: 0)
        triggerRemovalRange =
            try container.decodeIfPresent(
                CaptureRange.self,
                forKey: .triggerRemovalRange
            ) ?? markerRange
        actionContinuationKeys =
            try container.decodeIfPresent(
                [String].self,
                forKey: .actionContinuationKeys
            ) ?? []
        actionContinuationAliases =
            try container.decodeIfPresent(
                [String: String].self,
                forKey: .actionContinuationAliases
            ) ?? [:]
        relationship = try container.decodeIfPresent(
            CapturePickerRelationship.self,
            forKey: .relationship
        )
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
        continuation = try container.decodeIfPresent(String.self, forKey: .continuation)
    }

    /// True when this descriptor is the parent-task picker contract.
    public var isParentTask: Bool {
        kind == "parent_task"
    }

    /// True when this descriptor is the Complete (`!`) picker contract.
    public var isTaskComplete: Bool {
        kind == "task_complete"
    }

    /// True when this descriptor is the Task Wikilink (`((`) picker contract.
    public var isWikilinkTask: Bool {
        kind == "wikilink_task"
    }

    /// True when this descriptor is the move (`project_task_move`) picker contract.
    public var isProjectTaskMove: Bool {
        kind == "project_task_move"
    }

    public var parentTaskContext: ParentTaskPickerContext? {
        guard isParentTask, let scope = ParentTaskPickerScope(rawValue: scope) else {
            return nil
        }
        return ParentTaskPickerContext(
            scope: scope,
            scopeToken: scopeToken,
            noteTarget: noteTarget,
            markerRange: markerRange,
            triggerRemovalRange: triggerRemovalRange,
            actionContinuationKeys: actionContinuationKeys,
            actionContinuationAliases: actionContinuationAliases,
            continuation: continuation,
            relationship: relationship
        )
    }

    public var projectTaskMoveContext: ProjectTaskMovePickerContext? {
        guard isProjectTaskMove else {
            return nil
        }
        return ProjectTaskMovePickerContext(
            scopeToken: scopeToken,
            noteTarget: noteTarget,
            destination: destination,
            continuation: continuation,
            markerRange: markerRange,
            triggerRemovalRange: triggerRemovalRange,
            actionContinuationKeys: actionContinuationKeys,
            actionContinuationAliases: actionContinuationAliases
        )
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case scope
        case scopeToken = "scope_token"
        case noteTarget = "note_target"
        case markerRange = "marker_range"
        case triggerRemovalRange = "trigger_removal_range"
        case actionContinuationKeys = "action_continuation_keys"
        case actionContinuationAliases = "action_continuation_aliases"
        case relationship
        case destination
        case continuation
    }
}

/// Bob-authored parent and destination metadata for one active move picker.
/// Every field decodes tolerantly so an older Bob that omits the object
/// leaves the picker header empty rather than failing the completion decode.
public struct CaptureProjectTaskMoveHeader: Codable, Equatable, Sendable {
    public let parent: String?
    public let parentRoute: String?
    public let destination: String?
    public let sigil: String?
    public let openCount: Int
    public let pomodoroName: String?

    public init(
        parent: String? = nil,
        parentRoute: String? = nil,
        destination: String? = nil,
        sigil: String? = nil,
        openCount: Int = 0,
        pomodoroName: String? = nil
    ) {
        self.parent = parent
        self.parentRoute = parentRoute
        self.destination = destination
        self.sigil = sigil
        self.openCount = openCount
        self.pomodoroName = pomodoroName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        parentRoute = try container.decodeIfPresent(String.self, forKey: .parentRoute)
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
        sigil = try container.decodeIfPresent(String.self, forKey: .sigil)
        openCount = (try? container.decodeIfPresent(Int.self, forKey: .openCount)) ?? 0
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
    }

    private enum CodingKeys: String, CodingKey {
        case parent
        case parentRoute = "parent_route"
        case destination
        case sigil
        case openCount = "open_count"
        case pomodoroName = "pomodoro_name"
    }
}

/// Additive `picker.relationship` on a parent-task completion: the complete
/// `&` / `*` modifiers on the cursor's item. Unresolvable entries omit `text`.
public struct CapturePickerRelationship: Codable, Equatable, Sendable {
    public let dependencies: [CapturePickerRelationshipEntry]
    public let blockedTasks: [CapturePickerRelationshipEntry]
    /// Additive typed `~` / `~~` relations on the cursor's item. Older Bob
    /// omits the array.
    public let relations: [CapturePickerRelationEntry]

    public init(
        dependencies: [CapturePickerRelationshipEntry] = [],
        blockedTasks: [CapturePickerRelationshipEntry] = [],
        relations: [CapturePickerRelationEntry] = []
    ) {
        self.dependencies = dependencies
        self.blockedTasks = blockedTasks
        self.relations = relations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dependencies =
            try container.decodeIfPresent(
                [CapturePickerRelationshipEntry].self,
                forKey: .dependencies
            ) ?? []
        blockedTasks =
            try container.decodeIfPresent(
                [CapturePickerRelationshipEntry].self,
                forKey: .blockedTasks
            ) ?? []
        relations =
            (try? container.decodeIfPresent(
                [CapturePickerRelationEntry].self,
                forKey: .relations
            )) ?? []
    }

    public var isEmpty: Bool {
        dependencies.isEmpty && blockedTasks.isEmpty && relations.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case dependencies
        case blockedTasks = "blocked_tasks"
        case relations
    }
}

/// One typed relation on a parent-task `picker.relationship.relations[]`
/// entry: `direction` is `to` or `from`, and `text` is the resolved
/// target/source task name.
public struct CapturePickerRelationEntry: Codable, Equatable, Sendable {
    public let direction: String
    public let text: String

    public init(direction: String, text: String) {
        self.direction = direction
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direction = try container.decodeIfPresent(String.self, forKey: .direction) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case direction
        case text
    }
}

public struct CapturePickerRelationshipEntry: Codable, Equatable, Sendable {
    public let raw: String
    public let notePath: String
    public let blockID: String
    public let text: String?

    public init(raw: String, notePath: String, blockID: String, text: String? = nil) {
        self.raw = raw
        self.notePath = notePath
        self.blockID = blockID
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text)
    }

    /// Resolved task text, else the `note:block-id` locator.
    public var displayName: String {
        if let text, !text.isEmpty {
            return text
        }
        var note = notePath
        if note.hasSuffix(".md") {
            note = String(note.dropLast(3))
        }
        if !blockID.isEmpty {
            return note.isEmpty ? blockID : "\(note):\(blockID)"
        }
        return note.isEmpty ? raw : note
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case notePath = "note_path"
        case blockID = "block_id"
        case text
    }
}

/// Lexical owner of the `task_dependency` modifier under the cursor: the
/// capture-parse `dependency_target` for the cursor's item. `new_task` means
/// the capture will create the dependent; `existing_task` carries the exact
/// `@route+block-id` parent the dependency belongs to. Absent when the draft
/// names no dependent yet. Unknown kinds keep their raw value and the header
/// falls back to the ownerless prompt, so a newer Bob never breaks the picker.
public struct DependencyOwner: Codable, Equatable, Sendable {
    public let kind: String
    public let route: String?
    public let blockID: String?
    public let text: String?
    public let notePath: String?
    public let statusSymbol: String?
    public let statusName: String?

    public init(
        kind: String,
        route: String? = nil,
        blockID: String? = nil,
        text: String? = nil,
        notePath: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil
    ) {
        self.kind = kind
        self.route = route
        self.blockID = blockID
        self.text = text
        self.notePath = notePath
        self.statusSymbol = statusSymbol
        self.statusName = statusName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        route = try container.decodeIfPresent(String.self, forKey: .route)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath)
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
    }

    /// True for an explicitly selected existing parent task.
    public var isExistingTask: Bool {
        kind == "existing_task"
    }

    public var isNewTask: Bool {
        kind == "new_task"
    }

    /// Short owner description for the picker header (`@route+id`,
    /// `new task`, or nil when ownerless).
    public var headerText: String? {
        if isExistingTask, let route, let blockID {
            return "@\(route)+\(blockID)"
        }
        if kind == "new_task" {
            return nil
        }
        return nil
    }

    /// Token fallback when Bob sent no owner text (`@body+excercise`).
    public var tokenHeader: String? {
        headerText
    }

    /// Subtitle for an existing owner: `body.md ^excercise · In Progress`.
    public var locationSubtitle: String? {
        guard isExistingTask else {
            return nil
        }
        var parts: [String] = []
        if let notePath, !notePath.isEmpty, let blockID, !blockID.isEmpty {
            parts.append("\(notePath) ^\(blockID)")
        } else if let notePath, !notePath.isEmpty {
            parts.append(notePath)
        } else if let route, let blockID {
            parts.append("\(route).md ^\(blockID)")
        }
        if let statusName, !statusName.isEmpty {
            parts.append(statusName)
        }
        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case route
        case blockID = "block_id"
        case text
        case notePath = "note_path"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
    }
}

/// Queued-task annotation on an `active_task` completion candidate: the first open
/// Pomodoro entry holding the task's dedicated `[[route#^id]]` link, or `nil` when
/// the task is not queued. Older `bob` binaries predate `active_task` completion
/// and omit the whole object, so candidates decode it tolerantly.
public struct ActiveTaskPomodoro: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String?
    public let timeRange: String?
    public let isCurrent: Bool

    public init(
        line: Int,
        name: String? = nil,
        timeRange: String? = nil,
        isCurrent: Bool = false
    ) {
        self.line = line
        self.name = name
        self.timeRange = timeRange
        self.isCurrent = isCurrent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decode(Int.self, forKey: .line)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case timeRange = "time_range"
        case isCurrent = "is_current"
    }
}

/// Today's Task Link placement for a `task_complete` candidate: the winning
/// role, its entry, and how many distinct Pomodoros link the task today.
/// `noted` rows carry no entry. Older Bob omits the whole object, so
/// missing decodes as nil.
public struct TaskCompleteTodayPomodoro: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String?
    public let timeRange: String?
    public let status: String

    public init(line: Int, name: String? = nil, timeRange: String? = nil, status: String = "queued") {
        self.line = line
        self.name = name
        self.timeRange = timeRange
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decode(Int.self, forKey: .line)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "queued"
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case timeRange = "time_range"
        case status
    }
}

public struct TaskCompleteToday: Codable, Equatable, Sendable {
    public let role: String
    public let pomodoro: TaskCompleteTodayPomodoro?
    public let sessions: Int

    public init(role: String, pomodoro: TaskCompleteTodayPomodoro? = nil, sessions: Int = 0) {
        self.role = role
        self.pomodoro = pomodoro
        self.sessions = sessions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "noted"
        pomodoro = try container.decodeIfPresent(TaskCompleteTodayPomodoro.self, forKey: .pomodoro)
        sessions = try container.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case pomodoro
        case sessions
    }
}

/// A Pomodoro theme reference returned by Bob. Hues and identity are
/// Bob-owned; clients only decode these values for presentation.
public struct CapturePomodoroThemeRef: Codable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let hue: PomodoroHomeHue?
    public let hueSource: String?
    /// Bob omits `known` for catalogued themes and sends `false` only for an
    /// unknown typed name.
    public let known: Bool
    /// Present only when a `themes:` block is configured. `false` means
    /// the name is outside the vocabulary; absent means no opinion.
    public let configured: Bool?
    public let start: Int?
    public let end: Int?

    public var isUnconfigured: Bool { configured == false }

    public init(
        key: String,
        name: String,
        hue: PomodoroHomeHue? = nil,
        hueSource: String? = nil,
        known: Bool = true,
        configured: Bool? = nil,
        start: Int? = nil,
        end: Int? = nil
    ) {
        self.key = key
        self.name = name
        self.hue = hue
        self.hueSource = hueSource
        self.known = known
        self.configured = configured
        self.start = start
        self.end = end
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        hue = try container.decodeIfPresent(PomodoroHomeHue.self, forKey: .hue)
        hueSource = try container.decodeIfPresent(String.self, forKey: .hueSource)
        known = try container.decodeIfPresent(Bool.self, forKey: .known) ?? true
        configured = try container.decodeIfPresent(Bool.self, forKey: .configured)
        start = try container.decodeIfPresent(Int.self, forKey: .start)
        end = try container.decodeIfPresent(Int.self, forKey: .end)
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case name
        case hue
        case hueSource = "hue_source"
        case known
        case configured
        case start
        case end
    }
}

/// The note origin behind a task-theme suggestion (`source == "note"`).
/// Bob owns the chain and hue; Swift only decodes them for presentation.
public struct CaptureThemeSuggestionFrom: Codable, Equatable, Sendable {
    public let path: String
    public let stem: String
    public let kind: String
    public let hue: PomodoroHomeHue?
    public let chain: [String]

    public init(
        path: String = "",
        stem: String = "",
        kind: String = "",
        hue: PomodoroHomeHue? = nil,
        chain: [String] = []
    ) {
        self.path = path
        self.stem = stem
        self.kind = kind
        self.hue = hue
        self.chain = chain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        stem = (try? container.decodeIfPresent(String.self, forKey: .stem)) ?? ""
        kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        hue = (try? container.decodeIfPresent(PomodoroHomeHue.self, forKey: .hue)) ?? nil
        chain = (try? container.decodeIfPresent([String].self, forKey: .chain)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case stem
        case kind
        case hue
        case chain
    }
}

/// One task-theme suggestion from Bob's PT12 rule. This is the flattened
/// `ThemeSuggestion` plus the additive `MenuSuggestion` menu state
/// (`fallback`/`create`). Older Bob omits the whole object; missing decodes
/// as nil so clients keep today's behavior.
public struct CaptureThemeSuggestion: Codable, Equatable, Sendable {
    public let theme: CapturePomodoroThemeRef
    public let source: String
    public let label: String
    public let from: CaptureThemeSuggestionFrom?
    public let inherited: CaptureThemeSuggestionBox?
    public let repair: String?
    /// `unknown_theme` | `creation_blocked` | `strict_cap` | `already_queued`.
    /// Absent when a row is preselected or a create row is offered.
    public let fallback: String?
    /// True when no open bucket matches and Bob offers a new bucket.
    public let create: Bool

    public init(
        theme: CapturePomodoroThemeRef = CapturePomodoroThemeRef(key: "", name: ""),
        source: String = "",
        label: String = "",
        from: CaptureThemeSuggestionFrom? = nil,
        inherited: CaptureThemeSuggestionBox? = nil,
        repair: String? = nil,
        fallback: String? = nil,
        create: Bool = false
    ) {
        self.theme = theme
        self.source = source
        self.label = label
        self.from = from
        self.inherited = inherited
        self.repair = repair
        self.fallback = fallback
        self.create = create
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme =
            (try? container.decodeIfPresent(CapturePomodoroThemeRef.self, forKey: .theme))
            ?? CapturePomodoroThemeRef(key: "", name: "")
        source = (try? container.decodeIfPresent(String.self, forKey: .source)) ?? ""
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? ""
        from =
            (try? container.decodeIfPresent(
                CaptureThemeSuggestionFrom.self, forKey: .from)) ?? nil
        inherited =
            (try? container.decodeIfPresent(CaptureThemeSuggestionBox.self, forKey: .inherited))
            ?? nil
        repair = (try? container.decodeIfPresent(String.self, forKey: .repair)) ?? nil
        fallback = (try? container.decodeIfPresent(String.self, forKey: .fallback)) ?? nil
        create = (try? container.decodeIfPresent(Bool.self, forKey: .create)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case theme
        case source
        case label
        case from
        case inherited
        case repair
        case fallback
        case create
    }
}

/// Reference box for the recursive `inherited` suggestion. A class breaks
/// the value-type cycle (`CaptureThemeSuggestion` contains the box, the box
/// holds a `CaptureThemeSuggestion`). An explicit JSON null decodes as nil
/// (no inherited default), matching the display rule.
public final class CaptureThemeSuggestionBox: Codable, Equatable, Sendable {
    public let value: CaptureThemeSuggestion

    public init(_ value: CaptureThemeSuggestion) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Explicit null has no value; treat it as absent.
        if (try? container.decodeNil()) == true {
            throw DecodingError.valueNotFound(
                CaptureThemeSuggestion.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "null inherited"))
        }
        value = try container.decode(CaptureThemeSuggestion.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public static func == (
        lhs: CaptureThemeSuggestionBox, rhs: CaptureThemeSuggestionBox
    ) -> Bool {
        lhs.value == rhs.value
    }
}

/// The task-theme field change made by one explicit named capture choice.
/// Bob omits `task_theme` when nothing changed; malformed values decode as
/// nil so they can never fail the capture decode.
public struct CaptureTaskThemeChange: Codable, Equatable, Sendable {
    /// `set` | `cleared` | `kept`. Typed captures report `kept` when the
    /// chosen type already matches the subject's field or inherited default.
    public let action: String
    public let theme: CapturePomodoroThemeRef?
    public let previous: CapturePomodoroThemeRef?
    public let inherited: CaptureThemeSuggestion?

    public init(
        action: String = "",
        theme: CapturePomodoroThemeRef? = nil,
        previous: CapturePomodoroThemeRef? = nil,
        inherited: CaptureThemeSuggestion? = nil
    ) {
        self.action = action
        self.theme = theme
        self.previous = previous
        self.inherited = inherited
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = (try? container.decodeIfPresent(String.self, forKey: .action)) ?? ""
        theme =
            (try? container.decodeIfPresent(CapturePomodoroThemeRef.self, forKey: .theme)) ?? nil
        previous =
            (try? container.decodeIfPresent(CapturePomodoroThemeRef.self, forKey: .previous)) ?? nil
        inherited =
            (try? container.decodeIfPresent(CaptureThemeSuggestion.self, forKey: .inherited)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case theme
        case previous
        case inherited
    }
}

/// Additive ledger relocation so a retyped existing task's live Task Link
/// agrees with its new type. Older Bob omits it; malformed values decode
/// as nil so they can never fail the capture decode.
public struct CaptureTypeRelocation: Codable, Equatable, Sendable {
    /// `rename_entry` | `append_component` | `move_to` |
    /// `rename_placeholder` | `create_below`.
    public let outcome: String
    public let from: String?
    public let to: String

    public init(outcome: String = "", from: String? = nil, to: String = "") {
        self.outcome = outcome
        self.from = from
        self.to = to
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outcome = (try? container.decodeIfPresent(String.self, forKey: .outcome)) ?? ""
        self.from = (try? container.decodeIfPresent(String.self, forKey: .from)) ?? nil
        to = (try? container.decodeIfPresent(String.self, forKey: .to)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case outcome
        case from
        case to
    }
}

/// One entry in Bob's read-only `themes list` catalog response.
public struct CapturePomodoroTheme: Codable, Equatable, Identifiable, Sendable {
    public let key: String
    public let name: String
    public let hue: PomodoroHomeHue?
    public let hueSource: String?
    public let hidden: Bool
    /// Present only when a `themes:` block is configured.
    public let configured: Bool?
    public let lastUsed: String?
    public let daysUsed: Int?

    public var id: String { key }

    public var isUnconfigured: Bool { configured == false }

    public init(
        key: String,
        name: String,
        hue: PomodoroHomeHue? = nil,
        hueSource: String? = nil,
        hidden: Bool = false,
        configured: Bool? = nil,
        lastUsed: String? = nil,
        daysUsed: Int? = nil
    ) {
        self.key = key
        self.name = name
        self.hue = hue
        self.hueSource = hueSource
        self.hidden = hidden
        self.configured = configured
        self.lastUsed = lastUsed
        self.daysUsed = daysUsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        name = try container.decode(String.self, forKey: .name)
        hue = try container.decodeIfPresent(PomodoroHomeHue.self, forKey: .hue)
        hueSource = try container.decodeIfPresent(String.self, forKey: .hueSource)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        configured = try container.decodeIfPresent(Bool.self, forKey: .configured)
        lastUsed = try container.decodeIfPresent(String.self, forKey: .lastUsed)
        daysUsed = try container.decodeIfPresent(Int.self, forKey: .daysUsed)
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case name
        case hue
        case hueSource = "hue_source"
        case hidden
        case configured
        case lastUsed = "last_used"
        case daysUsed = "days_used"
    }
}

/// One entry in Bob's additive `configured_themes` array, in config order.
/// `color` is a palette slot, or `null` for configured `auto`.
public struct CaptureConfiguredTheme: Codable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let color: PomodoroHomeHue?

    public init(key: String, name: String, color: PomodoroHomeHue? = nil) {
        self.key = key
        self.name = name
        self.color = color
    }
}

/// Additive schema-versioned response used by the Mac Capture Name it prompt.
public struct CapturePomodoroThemesResponse: Codable, Equatable, SchemaVersioned, Sendable {
    public let schemaVersion: Int
    public let themes: [CapturePomodoroTheme]
    /// Present only when a `themes:` block is configured. Older Bob omits it.
    public let configuredThemes: [CaptureConfiguredTheme]?

    public init(
        schemaVersion: Int,
        themes: [CapturePomodoroTheme] = [],
        configuredThemes: [CaptureConfiguredTheme]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.themes = themes
        self.configuredThemes = configuredThemes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        themes = try container.decodeIfPresent([CapturePomodoroTheme].self, forKey: .themes) ?? []
        configuredThemes = try container.decodeIfPresent(
            [CaptureConfiguredTheme].self,
            forKey: .configuredThemes
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case themes
        case configuredThemes = "configured_themes"
    }
}

public struct CaptureCompletionCandidate: Codable, Equatable, Identifiable {
    public let replacement: String
    /// Additive `directive` row fields: the literal `%` token, a one-line `summary`,
    /// and an optional explanatory `detail`. Directive rows have no route, kind, or
    /// label; their `name` is the directive's display name. Bob authors every one of
    /// them, including the `disabled_reason` of a row that cannot be used here (its
    /// `replacement` is then empty). Every other context omits all three.
    public let token: String?
    public let summary: String?
    public let detail: String?
    public let route: String?
    public let label: String?
    public let kind: String?
    public let status: String?
    public let title: String?
    public let level: Int?
    public let taskRef: String?
    /// Absolute note path for read-only `task_goto` candidates. Older Bob
    /// versions and every other completion context omit it.
    public let target: String?
    public let blockID: String?
    public let requiresBlockID: Bool
    public let statusSymbol: String?
    public let statusName: String?
    public let statusType: String?
    public let text: String?
    public let section: String?
    public let depth: Int?
    public let childCount: Int?
    public let cursorAfter: Int?
    /// Additive `wikilink_task` display-only link target: the exact text
    /// Bob would put before `#^` (`sase_cleanup` or a full path). Older
    /// Bob omits it; decode as nil.
    public let linkTarget: String?
    public let path: String?
    public let name: String?
    public let alias: String?
    public let matchKind: String?
    public let heading: String?
    public let preview: String?
    public let requiresName: Bool
    public let line: Int?
    public let state: String?
    public let timeRange: String?
    /// Resolved `pomodoro_past_segment` picker row bounds and duration. Older
    /// Bob and every other completion context omit these values.
    public let start: String?
    public let end: String?
    public let minutes: Int?
    public let needsRepair: Bool
    public let placeholder: Bool
    public let isCurrent: Bool
    public let matchCount: Int?
    public let createsPomodoro: Bool
    /// Component refs and history metadata for the `pomodoro_name` menu.
    /// Older Bob versions omit these fields, leaving existing rows unchanged.
    public let themes: [CapturePomodoroThemeRef]
    public let origin: String?
    public let lastUsed: String?
    public let daysUsed: Int?
    public let similarTo: [String]
    // Additive `next_up` marker on `pomodoro_start_name` rows: true for the
    // entry a bare `=` would start. Omitted when false, and older Bob never
    // sends it, so missing decodes as false.
    public let nextUp: Bool
    public let pomodoro: ActiveTaskPomodoro?
    // Additive `task_link` fields from Bob's linkable-task scanner: the
    // note kind (`inbox`/`area`/`project`), ID suggestions for ID-less
    // tasks, the group (`queued`/`in_progress`/`next`/`note`), the
    // raw `YYYY-MM-DD` schedule, and whether linking pulls it forward.
    // Older Bob never sends them, so missing decodes to nil/empty/false.
    public let noteKind: String?
    public let blockIDSuggestions: [String]
    public let group: String?
    public let scheduled: String?
    public let pullsForward: Bool
    /// Additive completion date for closed `task_goto` rows. Older Bob and
    /// every other completion context omit it.
    public let closed: String?
    // Additive `task_dependency` fields from Bob's vault-wide prerequisite
    // scanner: the exact vault-relative note path including extension (never
    // the lowercased display route), the short human locator, whether the
    // row is already on the dependent's managed line, why a guarded row
    // cannot be used directly, and whether a `#hide` task renders subdued.
    // Older Bob and every other context omit them, so missing decodes to
    // nil/nil/false/nil/false.
    public let notePath: String?
    public let locator: String?
    public let alreadyDependency: Bool
    /// Additive `blocked_task` state: the candidate is already on the
    /// owner's Depends-On line. Missing means false for older Bob.
    public let alreadyBlocked: Bool
    /// Additive `relation_to` / `relation_from` state: the candidate is already
    /// on the owner's LINKS line. Missing means false for older Bob.
    public let alreadyLinked: Bool
    /// Existing relation label when `already_linked` is true.
    public let existingLabel: String?
    /// True when the candidate is also a prerequisite of the owner.
    public let alsoPrerequisite: Bool
    public let disabledReason: String?
    public let hidden: Bool
    // Additive `task_complete` fields from Bob's completable-task scanner:
    // whether capture refuses the row as recurring, whether another `!`
    // item in the draft already names it, and today's Task Link placement.
    // Older Bob and every other context omit them, so missing decodes to
    // false/false/nil.
    public let recurring: Bool
    public let alreadySelected: Bool
    public let today: TaskCompleteToday?
    // Additive reading-task marker from Bob's task scanners: `"ref"` on
    // candidates whose line is a `#task #ref` reading task. Omitted
    // otherwise, so older Bob decodes as nil and rows render as before.
    public let taskKind: String?
    /// Additive `relation_label` suggestion count: how many LINKS lines use
    /// this label. Bob sends `count`; older payloads omit it.
    public let count: Int?
    /// Additive `relation_label` typed row: true on Bob's canonical spelling
    /// of the typed label. Missing means false for older Bob.
    public let typed: Bool
    /// Additive `relation_label` canonical key: the writer-normalized,
    /// lowercased label. Older Bob payloads omit it; then the display label
    /// folds locally as before.
    public let key: String?
    /// Additive `relation_label` display-only inverse phrase
    /// (`merged into` → `merged from`). Omitted when Bob knows none.
    public let inverse: String?
    /// Additive `relation_label` insertion for a pending one-off: always the
    /// `||` form, so the app never builds either token itself. Omitted by
    /// older Bob.
    public let hideReplacement: String?
    /// Additive `relation_label` typed row: whether the typed text already
    /// names a catalog label. Omitted on suggestion rows and by older Bob.
    public let existing: Bool?
    /// Additive `relation_label` cancel flag: true when the row's key is a
    /// configured cancel label. Omitted when false, so older Bob and
    /// ordinary labels decode as false.
    public let cancelsSource: Bool
    /// Additive `relation_label` complete flag: true when the row's key is
    /// a configured complete label. Omitted when false, so older Bob and
    /// ordinary labels decode as false. Never set alongside
    /// `cancelsSource`: one label carries at most one close effect.
    public let completesSource: Bool
    /// Additive `relation_label` overlay flag: true on zero-use rows
    /// synthesized from config. Omitted when false.
    public let configured: Bool
    /// Additive `offers_source` flag for successor-label candidates. Missing means false.
    public let offersSource: Bool
    /// Task-aware menu row selected by the shared PT12 preselection rule.
    /// Older Bob omits both; missing decodes as false/nil.
    public let suggested: Bool
    public let suggestionLabel: String?
    /// Additive `task_type` flag: true when this row is the subject's
    /// current effective type. Distinct from Pomodoro `is_current`.
    public let current: Bool
    /// Additive `task_type` flag: true when this row is the inherited type.
    public let inherited: Bool
    /// Additive `task_type` effect: `set`, `clear`, or `keep`. Older Bob
    /// and every other context omit it.
    public let effect: String?
    /// Additive `task_type` refusal: `type_not_configured` when the typed
    /// row is refused. Warn-policy rows and older Bob omit it. On a `drawer`
    /// row it is Bob's one-line reason the commit would refuse (a reserved
    /// name, a near-duplicate of a drawer used elsewhere).
    public let refused: String?
    /// Additive `drawer` task row: how many entries the drawer already holds.
    public let entryCount: Int?
    /// Additive `drawer` Recent row: distinct notes that use the drawer key.
    public let noteCount: Int?
    /// Additive `drawer` Recent row: Unix seconds of the newest use. Bob turns
    /// it into `detail`; the app never formats it.
    public let lastSeen: Int?
    /// Additive `drawer` row: true when accepting creates the drawer (Recent
    /// and New rows). Omitted when false.
    public let creates: Bool
    /// Additive `drawer` row: Bob-authored consequence of choosing this row,
    /// such as `Adds after "2 GB RAM" in REQUIREMENTS`. The menu footer
    /// shows it for the selected row.
    public let consequence: String?
    /// Additive record `value` candidate display string (`display`).
    /// Older Bob and every other context omit it.
    public let display: String?
    /// Additive record value (`value`) on `record_value` rows.
    public let recordValue: String?
    /// Additive record type id (`type`) on record route/create/value rows.
    public let recordType: String?
    /// Additive record type emoji on route/create/completion metadata rows.
    public let emoji: String?
    /// Additive record field flags on `record_field` rows. Missing decodes
    /// as false so ordinary rows stay unchanged.
    public let recordRequired: Bool
    public let recordList: Bool
    public let recordDefaulted: Bool
    /// Additive follow-up request Bob authors on an accepted record row.
    /// Distinct from the generic picker `continuation` string.
    public let recordContinuation: CaptureRecordContinuation?

    public var id: String {
        [
            replacement,
            token,
            route,
            notePath,
            locator,
            title,
            taskRef,
            blockID,
            text,
            path,
            alias,
            heading,
            preview,
            line.map(String.init),
            timeRange,
            createsPomodoro ? "create" : nil,
            creates ? "creates" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: "\u{1f}")
    }

    public init(
        replacement: String,
        token: String? = nil,
        summary: String? = nil,
        detail: String? = nil,
        route: String? = nil,
        label: String? = nil,
        kind: String? = nil,
        status: String? = nil,
        title: String? = nil,
        level: Int? = nil,
        taskRef: String? = nil,
        target: String? = nil,
        blockID: String? = nil,
        requiresBlockID: Bool = false,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        statusType: String? = nil,
        text: String? = nil,
        section: String? = nil,
        depth: Int? = nil,
        childCount: Int? = nil,
        cursorAfter: Int? = nil,
        linkTarget: String? = nil,
        path: String? = nil,
        name: String? = nil,
        alias: String? = nil,
        matchKind: String? = nil,
        heading: String? = nil,
        preview: String? = nil,
        requiresName: Bool = false,
        line: Int? = nil,
        state: String? = nil,
        timeRange: String? = nil,
        start: String? = nil,
        end: String? = nil,
        minutes: Int? = nil,
        needsRepair: Bool = false,
        placeholder: Bool = false,
        isCurrent: Bool = false,
        matchCount: Int? = nil,
        createsPomodoro: Bool = false,
        themes: [CapturePomodoroThemeRef] = [],
        origin: String? = nil,
        lastUsed: String? = nil,
        daysUsed: Int? = nil,
        similarTo: [String] = [],
        nextUp: Bool = false,
        pomodoro: ActiveTaskPomodoro? = nil,
        noteKind: String? = nil,
        blockIDSuggestions: [String] = [],
        group: String? = nil,
        scheduled: String? = nil,
        pullsForward: Bool = false,
        closed: String? = nil,
        notePath: String? = nil,
        locator: String? = nil,
        alreadyDependency: Bool = false,
        alreadyBlocked: Bool = false,
        alreadyLinked: Bool = false,
        existingLabel: String? = nil,
        alsoPrerequisite: Bool = false,
        disabledReason: String? = nil,
        hidden: Bool = false,
        recurring: Bool = false,
        alreadySelected: Bool = false,
        today: TaskCompleteToday? = nil,
        taskKind: String? = nil,
        count: Int? = nil,
        typed: Bool = false,
        key: String? = nil,
        inverse: String? = nil,
        hideReplacement: String? = nil,
        existing: Bool? = nil,
        cancelsSource: Bool = false,
        completesSource: Bool = false,
        configured: Bool = false,
        offersSource: Bool = false,
        suggested: Bool = false,
        suggestionLabel: String? = nil,
        current: Bool = false,
        inherited: Bool = false,
        effect: String? = nil,
        refused: String? = nil,
        entryCount: Int? = nil,
        noteCount: Int? = nil,
        lastSeen: Int? = nil,
        creates: Bool = false,
        consequence: String? = nil,
        display: String? = nil,
        recordValue: String? = nil,
        recordType: String? = nil,
        emoji: String? = nil,
        recordRequired: Bool = false,
        recordList: Bool = false,
        recordDefaulted: Bool = false,
        recordContinuation: CaptureRecordContinuation? = nil
    ) {
        self.replacement = replacement
        self.token = token
        self.summary = summary
        self.detail = detail
        self.route = route
        self.label = label
        self.kind = kind
        self.status = status
        self.title = title
        self.level = level
        self.taskRef = taskRef
        self.target = target
        self.blockID = blockID
        self.requiresBlockID = requiresBlockID
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.statusType = statusType
        self.text = text
        self.section = section
        self.depth = depth
        self.childCount = childCount
        self.cursorAfter = cursorAfter
        self.linkTarget = linkTarget
        self.path = path
        self.name = name
        self.alias = alias
        self.matchKind = matchKind
        self.heading = heading
        self.preview = preview
        self.requiresName = requiresName
        self.line = line
        self.state = state
        self.timeRange = timeRange
        self.start = start
        self.end = end
        self.minutes = minutes
        self.needsRepair = needsRepair
        self.placeholder = placeholder
        self.isCurrent = isCurrent
        self.matchCount = matchCount
        self.createsPomodoro = createsPomodoro
        self.themes = themes
        self.origin = origin
        self.lastUsed = lastUsed
        self.daysUsed = daysUsed
        self.similarTo = similarTo
        self.nextUp = nextUp
        self.pomodoro = pomodoro
        self.noteKind = noteKind
        self.blockIDSuggestions = blockIDSuggestions
        self.group = group
        self.scheduled = scheduled
        self.pullsForward = pullsForward
        self.closed = closed
        self.notePath = notePath
        self.locator = locator
        self.alreadyDependency = alreadyDependency
        self.alreadyBlocked = alreadyBlocked
        self.alreadyLinked = alreadyLinked
        self.existingLabel = existingLabel
        self.alsoPrerequisite = alsoPrerequisite
        self.disabledReason = disabledReason
        self.hidden = hidden
        self.recurring = recurring
        self.alreadySelected = alreadySelected
        self.today = today
        self.taskKind = taskKind
        self.count = count
        self.typed = typed
        self.key = key
        self.inverse = inverse
        self.hideReplacement = hideReplacement
        self.existing = existing
        self.cancelsSource = cancelsSource
        self.completesSource = completesSource
        self.configured = configured
        self.offersSource = offersSource
        self.suggested = suggested
        self.suggestionLabel = suggestionLabel
        self.current = current
        self.inherited = inherited
        self.effect = effect
        self.refused = refused
        self.entryCount = entryCount
        self.noteCount = noteCount
        self.lastSeen = lastSeen
        self.creates = creates
        self.consequence = consequence
        self.display = display
        self.recordValue = recordValue
        self.recordType = recordType
        self.emoji = emoji
        self.recordRequired = recordRequired
        self.recordList = recordList
        self.recordDefaulted = recordDefaulted
        self.recordContinuation = recordContinuation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        replacement = try container.decode(String.self, forKey: .replacement)
        token = (try? container.decodeIfPresent(String.self, forKey: .token)) ?? nil
        summary = (try? container.decodeIfPresent(String.self, forKey: .summary)) ?? nil
        detail = (try? container.decodeIfPresent(String.self, forKey: .detail)) ?? nil
        route = try container.decodeIfPresent(String.self, forKey: .route)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        level = try container.decodeIfPresent(Int.self, forKey: .level)
        taskRef = try container.decodeIfPresent(String.self, forKey: .taskRef)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        requiresBlockID = try container.decodeIfPresent(Bool.self, forKey: .requiresBlockID) ?? false
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
        statusType = try container.decodeIfPresent(String.self, forKey: .statusType)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        section = try container.decodeIfPresent(String.self, forKey: .section)
        depth = try container.decodeIfPresent(Int.self, forKey: .depth)
        childCount = try container.decodeIfPresent(Int.self, forKey: .childCount)
        cursorAfter = try container.decodeIfPresent(Int.self, forKey: .cursorAfter)
        linkTarget = (try? container.decodeIfPresent(String.self, forKey: .linkTarget)) ?? nil
        path = try container.decodeIfPresent(String.self, forKey: .path)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        matchKind = try container.decodeIfPresent(String.self, forKey: .matchKind)
        heading = try container.decodeIfPresent(String.self, forKey: .heading)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        requiresName = try container.decodeIfPresent(Bool.self, forKey: .requiresName) ?? false
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        start = try container.decodeIfPresent(String.self, forKey: .start)
        end = try container.decodeIfPresent(String.self, forKey: .end)
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
        needsRepair = try container.decodeIfPresent(Bool.self, forKey: .needsRepair) ?? false
        placeholder = try container.decodeIfPresent(Bool.self, forKey: .placeholder) ?? false
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        matchCount = try container.decodeIfPresent(Int.self, forKey: .matchCount)
        createsPomodoro = try container.decodeIfPresent(Bool.self, forKey: .createsPomodoro) ?? false
        themes = try container.decodeIfPresent([CapturePomodoroThemeRef].self, forKey: .themes) ?? []
        origin = try container.decodeIfPresent(String.self, forKey: .origin)
        lastUsed = try container.decodeIfPresent(String.self, forKey: .lastUsed)
        daysUsed = try container.decodeIfPresent(Int.self, forKey: .daysUsed)
        similarTo = try container.decodeIfPresent([String].self, forKey: .similarTo) ?? []
        nextUp = try container.decodeIfPresent(Bool.self, forKey: .nextUp) ?? false
        pomodoro = try container.decodeIfPresent(ActiveTaskPomodoro.self, forKey: .pomodoro)
        noteKind = try container.decodeIfPresent(String.self, forKey: .noteKind)
        blockIDSuggestions =
            try container.decodeIfPresent([String].self, forKey: .blockIDSuggestions) ?? []
        group = try container.decodeIfPresent(String.self, forKey: .group)
        scheduled = try container.decodeIfPresent(String.self, forKey: .scheduled)
        pullsForward = try container.decodeIfPresent(Bool.self, forKey: .pullsForward) ?? false
        closed = try container.decodeIfPresent(String.self, forKey: .closed)
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath)
        locator = try container.decodeIfPresent(String.self, forKey: .locator)
        alreadyDependency =
            try container.decodeIfPresent(Bool.self, forKey: .alreadyDependency) ?? false
        alreadyBlocked = (try? container.decodeIfPresent(Bool.self, forKey: .alreadyBlocked)) ?? false
        alreadyLinked = (try? container.decodeIfPresent(Bool.self, forKey: .alreadyLinked)) ?? false
        existingLabel = (try? container.decodeIfPresent(String.self, forKey: .existingLabel)) ?? nil
        alsoPrerequisite =
            (try? container.decodeIfPresent(Bool.self, forKey: .alsoPrerequisite)) ?? false
        disabledReason = try container.decodeIfPresent(String.self, forKey: .disabledReason)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        recurring = try container.decodeIfPresent(Bool.self, forKey: .recurring) ?? false
        alreadySelected = try container.decodeIfPresent(Bool.self, forKey: .alreadySelected) ?? false
        today = try container.decodeIfPresent(TaskCompleteToday.self, forKey: .today)
        taskKind = try container.decodeIfPresent(String.self, forKey: .taskKind)
        count = (try? container.decodeIfPresent(Int.self, forKey: .count)) ?? nil
        typed = (try? container.decodeIfPresent(Bool.self, forKey: .typed)) ?? false
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? nil
        inverse = (try? container.decodeIfPresent(String.self, forKey: .inverse)) ?? nil
        hideReplacement =
            (try? container.decodeIfPresent(String.self, forKey: .hideReplacement)) ?? nil
        existing = (try? container.decodeIfPresent(Bool.self, forKey: .existing)) ?? nil
        cancelsSource = (try? container.decodeIfPresent(Bool.self, forKey: .cancelsSource)) ?? false
        completesSource = (try? container.decodeIfPresent(Bool.self, forKey: .completesSource)) ?? false
        configured = (try? container.decodeIfPresent(Bool.self, forKey: .configured)) ?? false
        offersSource = (try? container.decodeIfPresent(Bool.self, forKey: .offersSource)) ?? false
        suggested = (try? container.decodeIfPresent(Bool.self, forKey: .suggested)) ?? false
        suggestionLabel =
            (try? container.decodeIfPresent(String.self, forKey: .suggestionLabel)) ?? nil
        current = (try? container.decodeIfPresent(Bool.self, forKey: .current)) ?? false
        inherited = (try? container.decodeIfPresent(Bool.self, forKey: .inherited)) ?? false
        effect = (try? container.decodeIfPresent(String.self, forKey: .effect)) ?? nil
        refused = (try? container.decodeIfPresent(String.self, forKey: .refused)) ?? nil
        entryCount = (try? container.decodeIfPresent(Int.self, forKey: .entryCount)) ?? nil
        noteCount = (try? container.decodeIfPresent(Int.self, forKey: .noteCount)) ?? nil
        lastSeen = (try? container.decodeIfPresent(Int.self, forKey: .lastSeen)) ?? nil
        creates = (try? container.decodeIfPresent(Bool.self, forKey: .creates)) ?? false
        consequence = (try? container.decodeIfPresent(String.self, forKey: .consequence)) ?? nil
        display = (try? container.decodeIfPresent(String.self, forKey: .display)) ?? nil
        recordValue = (try? container.decodeIfPresent(String.self, forKey: .recordValue)) ?? nil
        recordType = (try? container.decodeIfPresent(String.self, forKey: .recordType)) ?? nil
        emoji = (try? container.decodeIfPresent(String.self, forKey: .emoji)) ?? nil
        recordRequired = (try? container.decodeIfPresent(Bool.self, forKey: .recordRequired)) ?? false
        recordList = (try? container.decodeIfPresent(Bool.self, forKey: .recordList)) ?? false
        recordDefaulted =
            (try? container.decodeIfPresent(Bool.self, forKey: .recordDefaulted)) ?? false
        recordContinuation =
            (try? container.decodeIfPresent(
                CaptureRecordContinuation.self,
                forKey: .recordContinuation
            )) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case replacement
        case token
        case summary
        case detail
        case route
        case label
        case kind
        case status
        case title
        case level
        case taskRef = "ref"
        case target
        case blockID = "block_id"
        case requiresBlockID = "requires_block_id"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case statusType = "status_type"
        case text
        case section
        case depth
        case childCount = "child_count"
        case cursorAfter = "cursor_after"
        case linkTarget = "link_target"
        case path
        case name
        case alias
        case matchKind = "match_kind"
        case heading
        case preview
        case requiresName = "requires_name"
        case line
        case state
        case timeRange = "time_range"
        case start
        case end
        case minutes
        case needsRepair = "needs_repair"
        case placeholder
        case isCurrent = "is_current"
        case matchCount = "match_count"
        case createsPomodoro = "creates_pomodoro"
        case themes
        case origin
        case lastUsed = "last_used"
        case daysUsed = "days_used"
        case similarTo = "similar_to"
        case nextUp = "next_up"
        case pomodoro
        case noteKind = "note_kind"
        case blockIDSuggestions = "block_id_suggestions"
        case group
        case scheduled
        case pullsForward = "pulls_forward"
        case closed
        case notePath = "note_path"
        case locator
        case alreadyDependency = "already_dependency"
        case alreadyBlocked = "already_blocked"
        case alreadyLinked = "already_linked"
        case existingLabel = "existing_label"
        case alsoPrerequisite = "also_prerequisite"
        case disabledReason = "disabled_reason"
        case hidden
        case recurring
        case alreadySelected = "already_selected"
        case today
        case taskKind = "task_kind"
        case count
        case typed
        case key
        case inverse
        case hideReplacement = "hide_replacement"
        case existing
        case cancelsSource = "cancels_source"
        case completesSource = "completes_source"
        case configured
        case offersSource = "offers_source"
        case suggested
        case suggestionLabel = "suggestion_label"
        case current
        case inherited
        case effect
        case refused
        case entryCount = "entry_count"
        case noteCount = "note_count"
        case lastSeen = "last_seen"
        case creates
        case consequence
        case display
        case recordValue = "value"
        case recordType = "type"
        case emoji
        case recordRequired = "required"
        case recordList = "list"
        case recordDefaulted = "defaulted"
        case recordContinuation = "continuation"
    }
}

/// What the person can mean on the right-hand side of `@route:`/`@route^`:
/// `link` references an existing task, `new` mints an unused ID, and
/// `project_note` names a new project note. Unknown values decode to `link`
/// so a newer Bob never breaks the picker.
public enum CaptureBlockIDIntent: String, Equatable, Sendable {
    case link
    case new
    case projectNote = "project_note"

    public init(wireValue: String?) {
        self = (wireValue.flatMap(CaptureBlockIDIntent.init(rawValue:)) ?? .link)
    }
}

extension CaptureBlockIDIntent: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(String.self)
        self.init(wireValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One ID already in the routed note, found by the exact scanner Bob's
/// duplicate check uses. Task lines carry their status and description;
/// other lines carry the trimmed line as text with null status fields.
public struct CaptureUsedBlockID: Codable, Equatable, Sendable {
    public let id: String
    public let line: Int
    public let isTask: Bool
    public let statusSymbol: String?
    public let statusName: String?
    public let text: String

    public init(
        id: String,
        line: Int,
        isTask: Bool,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        text: String
    ) {
        self.id = id
        self.line = line
        self.isTask = isTask
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        isTask = try container.decodeIfPresent(Bool.self, forKey: .isTask) ?? false
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case line
        case isTask = "task"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case text
    }
}

/// The additive top-level `block_id` object Bob sends exactly for
/// `pomodoro_block_id` and `task_block_id` contexts. Every field decodes
/// tolerantly: missing arrays are empty, strings are "", booleans are
/// false, the marker range is nil, and the intent falls back to `link`.
public struct CaptureBlockIDField: Codable, Equatable, Sendable {
    public let route: String
    public let relativeTarget: String
    public let noteExists: Bool
    public let marker: String
    public let markerRange: CaptureRange?
    public let intent: CaptureBlockIDIntent
    public let body: String
    public let allowedCharacter: String
    public let allowedDescription: String
    public let suggestions: [String]
    public let used: [CaptureUsedBlockID]
    /// Additive 1-based draft line of the task that owns the ID. A prompt on a
    /// nested line of a list or project-note task names its owner here; older
    /// Bob omits it.
    public let ownerLine: Int?
    /// Additive edit that puts the accepted ID on the owning line, so a prompt
    /// opened on a nested line still writes the ID where the task ends. Older
    /// Bob omits it and the accept falls back to the `replacement` range.
    public let splice: CaptureBlockIDSplice?

    public init(
        route: String,
        relativeTarget: String,
        noteExists: Bool = true,
        marker: String,
        markerRange: CaptureRange? = nil,
        intent: CaptureBlockIDIntent,
        body: String = "",
        allowedCharacter: String,
        allowedDescription: String,
        suggestions: [String] = [],
        used: [CaptureUsedBlockID] = [],
        ownerLine: Int? = nil,
        splice: CaptureBlockIDSplice? = nil
    ) {
        self.route = route
        self.relativeTarget = relativeTarget
        self.noteExists = noteExists
        self.marker = marker
        self.markerRange = markerRange
        self.intent = intent
        self.body = body
        self.allowedCharacter = allowedCharacter
        self.allowedDescription = allowedDescription
        self.suggestions = suggestions
        self.used = used
        self.ownerLine = ownerLine
        self.splice = splice
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        route = try container.decodeIfPresent(String.self, forKey: .route) ?? ""
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget) ?? ""
        noteExists = try container.decodeIfPresent(Bool.self, forKey: .noteExists) ?? false
        marker = try container.decodeIfPresent(String.self, forKey: .marker) ?? ""
        markerRange = try container.decodeIfPresent(CaptureRange.self, forKey: .markerRange)
        intent = try container.decodeIfPresent(CaptureBlockIDIntent.self, forKey: .intent) ?? .link
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        allowedCharacter = try container.decodeIfPresent(String.self, forKey: .allowedCharacter) ?? ""
        allowedDescription =
            try container.decodeIfPresent(String.self, forKey: .allowedDescription) ?? ""
        suggestions = try container.decodeIfPresent([String].self, forKey: .suggestions) ?? []
        used = try container.decodeIfPresent([CaptureUsedBlockID].self, forKey: .used) ?? []
        ownerLine = (try? container.decodeIfPresent(Int.self, forKey: .ownerLine)) ?? nil
        // A malformed splice must never break the picker: it decodes as nil and
        // the accept falls back to the ID-only `replacement` range.
        splice = (try? container.decodeIfPresent(CaptureBlockIDSplice.self, forKey: .splice)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case route
        case relativeTarget = "relative_target"
        case noteExists = "note_exists"
        case marker
        case markerRange = "marker_range"
        case intent
        case body
        case allowedCharacter = "allowed_character"
        case allowedDescription = "allowed_description"
        case suggestions
        case used
        case ownerLine = "owner_line"
        case splice
    }
}

/// Versioned `bob capture-pomodoros --format json` response. Only the
/// current entry's numbered Task Link count matters to the editor; every
/// other field decodes tolerantly so an older bob without
/// `task_link_count`, `day_file`, `ref`, or `state` still decodes with
/// nil / `.other` defaults.
public struct CapturePomodorosResponse: Decodable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let dayFile: String?
    public let pomodoros: [CapturePomodorosListEntry]

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        pomodoros: [CapturePomodorosListEntry] = [],
        dayFile: String? = nil
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.dayFile = dayFile
        self.pomodoros = pomodoros
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        dayFile = try container.decodeIfPresent(String.self, forKey: .dayFile)
        pomodoros =
            try container.decodeIfPresent(
                [CapturePomodorosListEntry].self,
                forKey: .pomodoros
            ) ?? []
    }

    /// The `isCurrent` entry's `taskLinkCount`, or nil when there is no
    /// current entry or the field is absent (older bob).
    public var currentTaskLinkCount: Int? {
        pomodoros.first(where: { $0.isCurrent })?.taskLinkCount
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case dayFile = "day_file"
        case pomodoros
    }
}

/// Wire `state` on a `capture-pomodoros` entry. Unknown values decode to
/// `.other` so a newer bob never breaks the panel.
public enum CapturePomodorosEntryState: Equatable, Sendable {
    case open
    case completed
    case other

    public init(wireValue: String?) {
        switch wireValue {
        case "open":
            self = .open
        case "completed":
            self = .completed
        default:
            self = .other
        }
    }
}

extension CapturePomodorosEntryState: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(String.self)
        self.init(wireValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .open:
            try container.encode("open")
        case .completed:
            try container.encode("completed")
        case .other:
            try container.encode("other")
        }
    }
}

/// Minimal `capture-pomodoros` entry: the fields the close-comma assist
/// and Command-\ today-Pomodoro landing need. `taskLinkCount` is the size
/// of the numbered Task Link lineup a plain `x` close indexes; it is an
/// integer only on the `isCurrent` entry and null elsewhere. Older bob
/// binaries omit `task_link_count`, `ref`, and `state`.
public struct CapturePomodorosListEntry: Decodable, Equatable {
    public let line: Int
    public let name: String?
    public let isCurrent: Bool
    public let taskLinkCount: Int?
    public let ref: String?
    public let state: CapturePomodorosEntryState

    public init(
        line: Int = 0,
        name: String? = nil,
        isCurrent: Bool = false,
        taskLinkCount: Int? = nil,
        ref: String? = nil,
        state: CapturePomodorosEntryState = .other
    ) {
        self.line = line
        self.name = name
        self.isCurrent = isCurrent
        self.taskLinkCount = taskLinkCount
        self.ref = ref
        self.state = state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        taskLinkCount = try container.decodeIfPresent(Int.self, forKey: .taskLinkCount)
        ref = try container.decodeIfPresent(String.self, forKey: .ref)
        state =
            try container.decodeIfPresent(
                CapturePomodorosEntryState.self,
                forKey: .state
            ) ?? .other
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case isCurrent = "is_current"
        case taskLinkCount = "task_link_count"
        case ref
        case state
    }
}

// MARK: - Inbox routing (`bob capture --inbox-route`)

/// One routable area or open project `bob capture` reports in
/// `inbox_route.destinations`. Mirrors `TaskMoveDestination` in
/// `src/native/task_move/plan.rs`; the list never offers another inbox.
/// Every field uses `decodeIfPresent`, so a malformed row degrades to its
/// defaults instead of failing the capture decode. Keys stay opaque.
public struct CaptureInboxRouteDestination: Codable, Equatable, Sendable {
    public let relativePath: String
    public let route: String
    public let label: String
    public let kind: String
    public let status: String?
    public let parent: String?
    public let blocked: Bool

    public init(
        relativePath: String = "",
        route: String = "",
        label: String = "",
        kind: String = "",
        status: String? = nil,
        parent: String? = nil,
        blocked: Bool = false
    ) {
        self.relativePath = relativePath
        self.route = route
        self.label = label
        self.kind = kind
        self.status = status
        self.parent = parent
        self.blocked = blocked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativePath = (try? container.decodeIfPresent(String.self, forKey: .relativePath)) ?? ""
        route = (try? container.decodeIfPresent(String.self, forKey: .route)) ?? ""
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? ""
        kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        parent = try? container.decodeIfPresent(String.self, forKey: .parent)
        blocked = (try? container.decodeIfPresent(Bool.self, forKey: .blocked)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case relativePath = "relative_path"
        case route
        case label
        case kind
        case status
        case parent
        case blocked
    }
}

/// The stored answer on one inbox-route candidate: keep it in its inbox,
/// or move it to a destination. Mirrors `InboxRouteAnswer` in
/// `src/native/capture/inbox_route.rs`.
public struct CaptureInboxRouteAnswer: Codable, Equatable, Sendable {
    public let action: String
    public let destination: String?

    public init(action: String = "", destination: String? = nil) {
        self.action = action
        self.destination = destination
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = (try? container.decodeIfPresent(String.self, forKey: .action)) ?? ""
        destination = try? container.decodeIfPresent(String.self, forKey: .destination)
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case destination
    }
}

/// The post-move landing `bob capture` reports on a moved candidate.
/// `fresh` is the stamped `[fresh::]` date, or nil when the moved task is
/// closed and was never stamped.
public struct CaptureInboxRouteMoved: Codable, Equatable, Sendable {
    public let destination: String
    public let line: Int
    public let blockID: String
    public let previousBlockID: String
    public let fresh: String?

    public init(
        destination: String = "",
        line: Int = 0,
        blockID: String = "",
        previousBlockID: String = "",
        fresh: String? = nil
    ) {
        self.destination = destination
        self.line = line
        self.blockID = blockID
        self.previousBlockID = previousBlockID
        self.fresh = fresh
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        destination = (try? container.decodeIfPresent(String.self, forKey: .destination)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        previousBlockID = (try? container.decodeIfPresent(String.self, forKey: .previousBlockID)) ?? ""
        fresh = try? container.decodeIfPresent(String.self, forKey: .fresh)
    }

    private enum CodingKeys: String, CodingKey {
        case destination
        case line
        case blockID = "block_id"
        case previousBlockID = "previous_block_id"
        case fresh
    }
}

/// One inbox task whose checkbox a capture changed. `key` is Bob's opaque
/// identity (`path#^id`, or `path@<sha8>[~ordinal]` for an id-less task);
/// never parse or reconstruct it. `outcome` is `pending`, `kept`, or
/// `moved`. Mirrors `InboxRouteCandidate` in
/// `src/native/capture/inbox_route.rs`.
public struct CaptureInboxRouteCandidate: Codable, Equatable, Sendable {
    public let key: String
    public let n: Int
    public let notePath: String
    public let inbox: String
    public let blockID: String
    public let line: Int
    public let text: String
    public let previousStatusSymbol: String
    public let previousStatusName: String
    public let statusSymbol: String
    public let statusName: String
    public let answer: CaptureInboxRouteAnswer?
    public let outcome: String
    public let moved: CaptureInboxRouteMoved?

    public init(
        key: String = "",
        n: Int = 0,
        notePath: String = "",
        inbox: String = "",
        blockID: String = "",
        line: Int = 0,
        text: String = "",
        previousStatusSymbol: String = "",
        previousStatusName: String = "",
        statusSymbol: String = "",
        statusName: String = "",
        answer: CaptureInboxRouteAnswer? = nil,
        outcome: String = "",
        moved: CaptureInboxRouteMoved? = nil
    ) {
        self.key = key
        self.n = n
        self.notePath = notePath
        self.inbox = inbox
        self.blockID = blockID
        self.line = line
        self.text = text
        self.previousStatusSymbol = previousStatusSymbol
        self.previousStatusName = previousStatusName
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.answer = answer
        self.outcome = outcome
        self.moved = moved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        n = (try? container.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        notePath = (try? container.decodeIfPresent(String.self, forKey: .notePath)) ?? ""
        inbox = (try? container.decodeIfPresent(String.self, forKey: .inbox)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        previousStatusSymbol =
            (try? container.decodeIfPresent(String.self, forKey: .previousStatusSymbol)) ?? ""
        previousStatusName =
            (try? container.decodeIfPresent(String.self, forKey: .previousStatusName)) ?? ""
        statusSymbol = (try? container.decodeIfPresent(String.self, forKey: .statusSymbol)) ?? ""
        statusName = (try? container.decodeIfPresent(String.self, forKey: .statusName)) ?? ""
        answer = (try? container.decodeIfPresent(CaptureInboxRouteAnswer.self, forKey: .answer)) ?? nil
        outcome = (try? container.decodeIfPresent(String.self, forKey: .outcome)) ?? ""
        moved = (try? container.decodeIfPresent(CaptureInboxRouteMoved.self, forKey: .moved)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case n
        case notePath = "note_path"
        case inbox
        case blockID = "block_id"
        case line
        case text
        case previousStatusSymbol = "previous_status_symbol"
        case previousStatusName = "previous_status_name"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case answer
        case outcome
        case moved
    }
}

/// One vault-wide repaired file `bob capture` reports once a route is
/// applied.
public struct CaptureInboxRouteRepairedFile: Codable, Equatable, Sendable {
    public let path: String
    public let linkCount: Int
    public let dependencyTokenCount: Int

    public init(path: String = "", linkCount: Int = 0, dependencyTokenCount: Int = 0) {
        self.path = path
        self.linkCount = linkCount
        self.dependencyTokenCount = dependencyTokenCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        linkCount = (try? container.decodeIfPresent(Int.self, forKey: .linkCount)) ?? 0
        dependencyTokenCount =
            (try? container.decodeIfPresent(Int.self, forKey: .dependencyTokenCount)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case linkCount = "link_count"
        case dependencyTokenCount = "dependency_token_count"
    }
}

/// One block-ID collision rename `bob capture` reports once a route is
/// applied.
public struct CaptureInboxRouteRename: Codable, Equatable, Sendable {
    public let path: String
    public let oldBlockID: String
    public let newBlockID: String

    public init(path: String = "", oldBlockID: String = "", newBlockID: String = "") {
        self.path = path
        self.oldBlockID = oldBlockID
        self.newBlockID = newBlockID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        oldBlockID = (try? container.decodeIfPresent(String.self, forKey: .oldBlockID)) ?? ""
        newBlockID = (try? container.decodeIfPresent(String.self, forKey: .newBlockID)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case oldBlockID = "old_block_id"
        case newBlockID = "new_block_id"
    }
}

/// Batch-level `inbox_route` object on every successful capture JSON.
/// `destinations` is present only when `candidateCount > 0`; `repairedFiles`,
/// `renamedBlockIDs`, and `needsReconcile` are present only once a move is
/// applied. Mirrors `InboxRouteReport` in
/// `src/native/capture/inbox_route.rs`.
public struct CaptureInboxRoute: Codable, Equatable, Sendable {
    public let supported: Bool
    public let candidateCount: Int
    public let routedCount: Int
    public let keptCount: Int
    public let candidates: [CaptureInboxRouteCandidate]
    public let destinations: [CaptureInboxRouteDestination]?
    public let repairedFiles: [CaptureInboxRouteRepairedFile]?
    public let renamedBlockIDs: [CaptureInboxRouteRename]?
    public let needsReconcile: Bool?

    public init(
        supported: Bool = false,
        candidateCount: Int = 0,
        routedCount: Int = 0,
        keptCount: Int = 0,
        candidates: [CaptureInboxRouteCandidate] = [],
        destinations: [CaptureInboxRouteDestination]? = nil,
        repairedFiles: [CaptureInboxRouteRepairedFile]? = nil,
        renamedBlockIDs: [CaptureInboxRouteRename]? = nil,
        needsReconcile: Bool? = nil
    ) {
        self.supported = supported
        self.candidateCount = candidateCount
        self.routedCount = routedCount
        self.keptCount = keptCount
        self.candidates = candidates
        self.destinations = destinations
        self.repairedFiles = repairedFiles
        self.renamedBlockIDs = renamedBlockIDs
        self.needsReconcile = needsReconcile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supported = (try? container.decodeIfPresent(Bool.self, forKey: .supported)) ?? false
        candidateCount = (try? container.decodeIfPresent(Int.self, forKey: .candidateCount)) ?? 0
        routedCount = (try? container.decodeIfPresent(Int.self, forKey: .routedCount)) ?? 0
        keptCount = (try? container.decodeIfPresent(Int.self, forKey: .keptCount)) ?? 0
        candidates =
            (try? container.decodeIfPresent([CaptureInboxRouteCandidate].self, forKey: .candidates)) ?? []
        destinations = try? container.decodeIfPresent(
            [CaptureInboxRouteDestination].self,
            forKey: .destinations
        )
        repairedFiles = try? container.decodeIfPresent(
            [CaptureInboxRouteRepairedFile].self,
            forKey: .repairedFiles
        )
        renamedBlockIDs = try? container.decodeIfPresent(
            [CaptureInboxRouteRename].self,
            forKey: .renamedBlockIDs
        )
        needsReconcile = try? container.decodeIfPresent(Bool.self, forKey: .needsReconcile)
    }

    private enum CodingKeys: String, CodingKey {
        case supported
        case candidateCount = "candidate_count"
        case routedCount = "routed_count"
        case keptCount = "kept_count"
        case candidates
        case destinations
        case repairedFiles = "repaired_files"
        case renamedBlockIDs = "renamed_block_ids"
        case needsReconcile = "needs_reconcile"
    }
}

/// Batch-level `move_choice` report on capture success and refusal JSON.
/// Bob adds this object to supported builds, then supplies one slot for each
/// `- ^^` marker. Older Bob omits it and malformed additive rows degrade
/// individually instead of failing the capture response.
public struct CaptureMoveChoice: Codable, Equatable, Sendable {
    public let supported: Bool
    public let slots: [CaptureMoveChoiceSlot]

    public init(supported: Bool = false, slots: [CaptureMoveChoiceSlot] = []) {
        self.supported = supported
        self.slots = slots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supported = (try? container.decodeIfPresent(Bool.self, forKey: .supported)) ?? false
        slots = (try? container.decodeIfPresent([CaptureMoveChoiceSlot].self, forKey: .slots)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case supported
        case slots
    }
}

/// Bob's staged parent and candidate rows for one `- ^^` draft slot.
public struct CaptureMoveChoiceSlot: Codable, Equatable, Sendable {
    public let item: Int
    public let itemLine: Int
    /// Half-open UTF-8 byte range of the `^^` token in the draft.
    public let draftRange: [Int]
    public let parent: String
    public let destination: String
    public let pomodoroName: String?
    public let nameNeedsLink: Bool
    public let openCount: Int
    public let answered: Bool
    public let movedCount: Int
    public let linkedCount: Int
    public let copy: CaptureMoveChoiceCopy?
    public let rows: [CaptureMoveChoiceRow]

    public init(
        item: Int = 0,
        itemLine: Int = 0,
        draftRange: [Int] = [],
        parent: String = "",
        destination: String = "",
        pomodoroName: String? = nil,
        nameNeedsLink: Bool = false,
        openCount: Int = 0,
        answered: Bool = false,
        movedCount: Int = 0,
        linkedCount: Int = 0,
        copy: CaptureMoveChoiceCopy? = nil,
        rows: [CaptureMoveChoiceRow] = []
    ) {
        self.item = item
        self.itemLine = itemLine
        self.draftRange = draftRange
        self.parent = parent
        self.destination = destination
        self.pomodoroName = pomodoroName
        self.nameNeedsLink = nameNeedsLink
        self.openCount = openCount
        self.answered = answered
        self.movedCount = movedCount
        self.linkedCount = linkedCount
        self.copy = copy
        self.rows = rows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        item = (try? container.decodeIfPresent(Int.self, forKey: .item)) ?? 0
        itemLine = (try? container.decodeIfPresent(Int.self, forKey: .itemLine)) ?? 0
        draftRange = (try? container.decodeIfPresent([Int].self, forKey: .draftRange)) ?? []
        parent = (try? container.decodeIfPresent(String.self, forKey: .parent)) ?? ""
        destination = (try? container.decodeIfPresent(String.self, forKey: .destination)) ?? ""
        pomodoroName = try? container.decodeIfPresent(String.self, forKey: .pomodoroName)
        nameNeedsLink = (try? container.decodeIfPresent(Bool.self, forKey: .nameNeedsLink)) ?? false
        openCount = (try? container.decodeIfPresent(Int.self, forKey: .openCount)) ?? 0
        answered = (try? container.decodeIfPresent(Bool.self, forKey: .answered)) ?? false
        movedCount = (try? container.decodeIfPresent(Int.self, forKey: .movedCount)) ?? 0
        linkedCount = (try? container.decodeIfPresent(Int.self, forKey: .linkedCount)) ?? 0
        copy = try? container.decodeIfPresent(CaptureMoveChoiceCopy.self, forKey: .copy)
        rows = (try? container.decodeIfPresent([CaptureMoveChoiceRow].self, forKey: .rows)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case item
        case itemLine = "item_line"
        case draftRange = "draft_range"
        case parent
        case destination
        case pomodoroName = "pomodoro_name"
        case nameNeedsLink = "name_needs_link"
        case openCount = "open_count"
        case answered
        case movedCount = "moved_count"
        case linkedCount = "linked_count"
        case copy
        case rows
    }
}

/// Bob-authored card and preview copy for a move-choice slot.
public struct CaptureMoveChoiceCopy: Codable, Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let slot: String
    public let leave: String
    public let ghost: String
    public let band: String
    public let then: String?

    public init(
        title: String = "",
        subtitle: String = "",
        slot: String = "",
        leave: String = "",
        ghost: String = "",
        band: String = "",
        then: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.slot = slot
        self.leave = leave
        self.ghost = ghost
        self.band = band
        self.then = then
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        subtitle = (try? container.decodeIfPresent(String.self, forKey: .subtitle)) ?? ""
        slot = (try? container.decodeIfPresent(String.self, forKey: .slot)) ?? ""
        leave = (try? container.decodeIfPresent(String.self, forKey: .leave)) ?? ""
        ghost = (try? container.decodeIfPresent(String.self, forKey: .ghost)) ?? ""
        band = (try? container.decodeIfPresent(String.self, forKey: .band)) ?? ""
        then = try? container.decodeIfPresent(String.self, forKey: .then)
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case slot
        case leave
        case ghost
        case band
        case then
    }
}

/// One Bob-ranked parent task and its planner-true move consequences.
public struct CaptureMoveChoiceRow: Codable, Equatable, Sendable {
    public let key: String
    public let n: Int
    public let line: Int
    public let section: String?
    public let blockID: String?
    public let mint: String?
    public let text: String
    public let statusSymbol: String
    public let statusName: String
    public let hidden: Bool
    public let scheduled: String?
    public let pomodoro: CaptureMoveChoicePomodoro?
    public let choices: [CaptureMoveChoiceOption]
    public let locked: CaptureMoveChoiceLock?
    public let disabledReason: String?
    /// `^`, `:`, or nil after Bob has resolved a submitted answer.
    public let answer: String?

    public init(
        key: String = "",
        n: Int = 0,
        line: Int = 0,
        section: String? = nil,
        blockID: String? = nil,
        mint: String? = nil,
        text: String = "",
        statusSymbol: String = "",
        statusName: String = "",
        hidden: Bool = false,
        scheduled: String? = nil,
        pomodoro: CaptureMoveChoicePomodoro? = nil,
        choices: [CaptureMoveChoiceOption] = [],
        locked: CaptureMoveChoiceLock? = nil,
        disabledReason: String? = nil,
        answer: String? = nil
    ) {
        self.key = key
        self.n = n
        self.line = line
        self.section = section
        self.blockID = blockID
        self.mint = mint
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.hidden = hidden
        self.scheduled = scheduled
        self.pomodoro = pomodoro
        self.choices = choices
        self.locked = locked
        self.disabledReason = disabledReason
        self.answer = answer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        n = (try? container.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        section = try? container.decodeIfPresent(String.self, forKey: .section)
        blockID = try? container.decodeIfPresent(String.self, forKey: .blockID)
        mint = try? container.decodeIfPresent(String.self, forKey: .mint)
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        statusSymbol = (try? container.decodeIfPresent(String.self, forKey: .statusSymbol)) ?? ""
        statusName = (try? container.decodeIfPresent(String.self, forKey: .statusName)) ?? ""
        hidden = (try? container.decodeIfPresent(Bool.self, forKey: .hidden)) ?? false
        scheduled = try? container.decodeIfPresent(String.self, forKey: .scheduled)
        pomodoro = try? container.decodeIfPresent(CaptureMoveChoicePomodoro.self, forKey: .pomodoro)
        choices =
            (try? container.decodeIfPresent([CaptureMoveChoiceOption].self, forKey: .choices)) ?? []
        locked = try? container.decodeIfPresent(CaptureMoveChoiceLock.self, forKey: .locked)
        disabledReason = try? container.decodeIfPresent(String.self, forKey: .disabledReason)
        answer = try? container.decodeIfPresent(String.self, forKey: .answer)
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case n
        case line
        case section
        case blockID = "block_id"
        case mint
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case hidden
        case scheduled
        case pomodoro
        case choices
        case locked
        case disabledReason = "disabled_reason"
        case answer
    }
}

public struct CaptureMoveChoiceOption: Codable, Equatable, Sendable {
    public let sigil: String
    public let consequence: String
    public let addsLink: Bool

    public init(sigil: String = "", consequence: String = "", addsLink: Bool = false) {
        self.sigil = sigil
        self.consequence = consequence
        self.addsLink = addsLink
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sigil = (try? container.decodeIfPresent(String.self, forKey: .sigil)) ?? ""
        consequence = (try? container.decodeIfPresent(String.self, forKey: .consequence)) ?? ""
        addsLink = (try? container.decodeIfPresent(Bool.self, forKey: .addsLink)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case sigil
        case consequence
        case addsLink = "adds_link"
    }
}

public struct CaptureMoveChoiceLock: Codable, Equatable, Sendable {
    public let sigil: String
    public let itemLine: Int

    public init(sigil: String = "", itemLine: Int = 0) {
        self.sigil = sigil
        self.itemLine = itemLine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sigil = (try? container.decodeIfPresent(String.self, forKey: .sigil)) ?? ""
        itemLine = (try? container.decodeIfPresent(Int.self, forKey: .itemLine)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case sigil
        case itemLine = "item_line"
    }
}

public struct CaptureMoveChoicePomodoro: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String?

    public init(line: Int = 0, name: String? = nil) {
        self.line = line
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        name = try? container.decodeIfPresent(String.self, forKey: .name)
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
    }
}

/// Refused-route detail beside `inbox_route` on `inbox_route_refused`.
public struct CaptureInboxRouteRefused: Codable, Equatable, Sendable {
    public let key: String
    public let n: Int
    public let destination: String
    public let message: String
    /// Offer-close refusal variant carried in the same top-level `refused`
    /// slot; nil for inbox-route refusals and older Bob.
    public let outcome: String?
    public let why: String?

    public init(
        key: String = "",
        n: Int = 0,
        destination: String = "",
        message: String = "",
        outcome: String? = nil,
        why: String? = nil
    ) {
        self.key = key
        self.n = n
        self.destination = destination
        self.message = message
        self.outcome = outcome
        self.why = why
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        n = (try? container.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        destination = (try? container.decodeIfPresent(String.self, forKey: .destination)) ?? ""
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
        outcome = try? container.decodeIfPresent(String.self, forKey: .outcome)
        why = try? container.decodeIfPresent(String.self, forKey: .why)
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case n
        case destination
        case message
        case outcome
        case why
    }
}
