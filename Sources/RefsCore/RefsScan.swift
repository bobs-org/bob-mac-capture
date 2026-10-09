import CaptureCore
import Foundation

/// Decoding, outcome, and presentation for `bob ref scan -w -f json`.
///
/// The wire contract is owned by bob: a versioned envelope naming every
/// created and updated note. Every field except `schema_version` decodes
/// with `decodeIfPresent`, unknown fields are ignored, and `notes` and
/// `failures` decode element by element — an entry missing its required
/// keys is skipped instead of failing the whole response.
public struct RefsScanResponse: Decodable, Equatable, Sendable, SchemaVersioned {
    public var ok: Bool
    public var schemaVersion: Int
    public var mode: String?
    public var writePDFs: Bool
    public var intake: [RefsScanIntakeMove]
    public var summary: RefsScanSummary
    public var notes: [RefsScanNote]
    public var failures: [RefsScanFailure]
    public var error: RefsScanProblem?

    public init(
        ok: Bool = false,
        schemaVersion: Int = 1,
        mode: String? = nil,
        writePDFs: Bool = false,
        intake: [RefsScanIntakeMove] = [],
        summary: RefsScanSummary = RefsScanSummary(),
        notes: [RefsScanNote] = [],
        failures: [RefsScanFailure] = [],
        error: RefsScanProblem? = nil
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.writePDFs = writePDFs
        self.intake = intake
        self.summary = summary
        self.notes = notes
        self.failures = failures
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case mode
        case writePDFs = "write_pdfs"
        case intake
        case summary
        case notes
        case failures
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        writePDFs = try container.decodeIfPresent(Bool.self, forKey: .writePDFs) ?? false
        intake = try container.decodeIfPresent([RefsScanIntakeMove].self, forKey: .intake) ?? []
        summary = try container.decodeIfPresent(RefsScanSummary.self, forKey: .summary)
            ?? RefsScanSummary()
        let noteRows = try container.decodeIfPresent([LossyScanNote].self, forKey: .notes) ?? []
        notes = noteRows.compactMap(\.note)
        let failureRows = try container.decodeIfPresent([LossyScanFailure].self, forKey: .failures)
            ?? []
        failures = failureRows.compactMap(\.failure)
        error = try container.decodeIfPresent(RefsScanProblem.self, forKey: .error)
    }
}

private struct LossyScanNote: Decodable {
    let note: RefsScanNote?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        note = try? container.decode(RefsScanNote.self)
    }
}

private struct LossyScanFailure: Decodable {
    let failure: RefsScanFailure?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        failure = try? container.decode(RefsScanFailure.self)
    }
}

/// One PDF intake move, vault-relative `from` and `to`, in move order.
public struct RefsScanIntakeMove: Codable, Equatable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// The same counts the human summary line prints, with the same semantics.
public struct RefsScanSummary: Codable, Equatable, Sendable {
    public var pdfs: Int
    public var created: Int
    public var updated: Int
    public var unchanged: Int
    public var markers: Int
    public var tasks: Int
    public var failures: Int

    public init(
        pdfs: Int = 0,
        created: Int = 0,
        updated: Int = 0,
        unchanged: Int = 0,
        markers: Int = 0,
        tasks: Int = 0,
        failures: Int = 0
    ) {
        self.pdfs = pdfs
        self.created = created
        self.updated = updated
        self.unchanged = unchanged
        self.markers = markers
        self.tasks = tasks
        self.failures = failures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pdfs = try container.decodeIfPresent(Int.self, forKey: .pdfs) ?? 0
        created = try container.decodeIfPresent(Int.self, forKey: .created) ?? 0
        updated = try container.decodeIfPresent(Int.self, forKey: .updated) ?? 0
        unchanged = try container.decodeIfPresent(Int.self, forKey: .unchanged) ?? 0
        markers = try container.decodeIfPresent(Int.self, forKey: .markers) ?? 0
        tasks = try container.decodeIfPresent(Int.self, forKey: .tasks) ?? 0
        failures = try container.decodeIfPresent(Int.self, forKey: .failures) ?? 0
    }
}

/// One created or updated reference note, in scan order. `action` and
/// `path` are required; a note without either is skipped.
public struct RefsScanNote: Codable, Equatable, Sendable {
    public var action: String
    public var path: String
    public var title: String?
    public var refType: String?
    public var sourcePDF: String?
    public var marker: Bool

    public init(
        action: String,
        path: String,
        title: String? = nil,
        refType: String? = nil,
        sourcePDF: String? = nil,
        marker: Bool = false
    ) {
        self.action = action
        self.path = path
        self.title = title
        self.refType = refType
        self.sourcePDF = sourcePDF
        self.marker = marker
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case path
        case title
        case refType = "ref_type"
        case sourcePDF = "source_pdf"
        case marker
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let action = try container.decodeIfPresent(String.self, forKey: .action),
            let path = try container.decodeIfPresent(String.self, forKey: .path)
        else {
            throw DecodingError.valueNotFound(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "RefsScanNote requires action and path"
                )
            )
        }
        self.action = action
        self.path = path
        title = try container.decodeIfPresent(String.self, forKey: .title)
        refType = try container.decodeIfPresent(String.self, forKey: .refType)
        sourcePDF = try container.decodeIfPresent(String.self, forKey: .sourcePDF)
        marker = try container.decodeIfPresent(Bool.self, forKey: .marker) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(refType, forKey: .refType)
        try container.encodeIfPresent(sourcePDF, forKey: .sourcePDF)
        try container.encode(marker, forKey: .marker)
    }
}

/// One per-PDF failure: the vault-relative `pdf`, the `stage`
/// (`"plan"` or `"write"`), and bob's message. A failure without `pdf`
/// or `message` is skipped.
public struct RefsScanFailure: Codable, Equatable, Sendable {
    public var pdf: String
    public var stage: String?
    public var message: String

    public init(pdf: String, stage: String? = nil, message: String) {
        self.pdf = pdf
        self.stage = stage
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let pdf = try container.decodeIfPresent(String.self, forKey: .pdf),
            let message = try container.decodeIfPresent(String.self, forKey: .message)
        else {
            throw DecodingError.valueNotFound(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "RefsScanFailure requires pdf and message"
                )
            )
        }
        self.pdf = pdf
        self.message = message
        stage = try container.decodeIfPresent(String.self, forKey: .stage)
    }
}

/// A hard scan failure: bob's `code`, `message`, an optional `hint`,
/// and the vault-relative `paths` involved (possibly empty).
public struct RefsScanProblem: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var hint: String?
    public var paths: [String]

    public init(code: String, message: String, hint: String? = nil, paths: [String] = []) {
        self.code = code
        self.message = message
        self.hint = hint
        self.paths = paths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let code = try container.decodeIfPresent(String.self, forKey: .code),
            let message = try container.decodeIfPresent(String.self, forKey: .message)
        else {
            throw DecodingError.valueNotFound(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "RefsScanProblem requires code and message"
                )
            )
        }
        self.code = code
        self.message = message
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
        paths = try container.decodeIfPresent([String].self, forKey: .paths) ?? []
    }
}

/// What one scan means for the panel: its kind, the notes it created,
/// the counts the footer reports, and the diagnostic Copy Diagnostic
/// copies. `problem` is set exactly when `kind` is `.failed`.
public struct RefsScanOutcome: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case succeeded
        case partial
        case failed
    }

    public var kind: Kind
    public var finishedAt: Date
    public var created: [RefsScanNote]
    public var syncedNoteCount: Int
    public var intakeCount: Int
    public var failures: [RefsScanFailure]
    public var problem: RefsScanProblem?
    public var diagnostic: String

    public init(response: RefsScanResponse, finishedAt: Date) {
        if response.error != nil {
            kind = .failed
        } else if !response.failures.isEmpty || !response.ok {
            kind = .partial
        } else {
            kind = .succeeded
        }
        self.finishedAt = finishedAt
        created = response.notes.filter { $0.action == "create" }
        syncedNoteCount = response.notes.filter { $0.action == "update" }.count
        intakeCount = response.intake.count
        failures = response.failures
        problem = response.error
        diagnostic = Self.diagnostic(
            kind: kind,
            problem: response.error,
            failures: response.failures
        )
    }

    public init(problem: RefsScanProblem, finishedAt: Date) {
        kind = .failed
        self.finishedAt = finishedAt
        created = []
        syncedNoteCount = 0
        intakeCount = 0
        failures = []
        self.problem = problem
        diagnostic = Self.diagnostic(kind: kind, problem: problem, failures: [])
    }

    private static func diagnostic(
        kind: Kind,
        problem: RefsScanProblem?,
        failures: [RefsScanFailure]
    ) -> String {
        var lines = ["bob ref scan -w -f json"]
        switch kind {
        case .succeeded:
            lines.append("kind: succeeded")
        case .partial:
            lines.append("kind: partial")
        case .failed:
            lines.append("kind: failed")
        }
        if let problem {
            lines.append("\(problem.code): \(problem.message)")
            if let hint = problem.hint {
                lines.append("hint: \(hint)")
            }
            if !problem.paths.isEmpty {
                lines.append("paths: \(problem.paths.joined(separator: ", "))")
            }
        }
        for failure in failures {
            if let stage = failure.stage {
                lines.append("\(failure.pdf) [\(stage)]: \(failure.message)")
            } else {
                lines.append("\(failure.pdf): \(failure.message)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// The exact strings the panel shows for a scan (§8). Titles come from
/// `TaskDisplayText(parsing:)`; a missing title falls back to the note
/// stem (the last path component without `.md`). Singular forms apply
/// exactly when the count is 1.
public enum RefsScanPresentation {
    public static func scanningText(elapsed: TimeInterval) -> String {
        guard elapsed >= 5 else {
            return "Scanning library…"
        }
        return "Scanning library… \(Int(elapsed)) s"
    }

    public static func footerText(_ outcome: RefsScanOutcome, searchMode: Bool) -> String {
        switch outcome.kind {
        case .succeeded:
            if !outcome.created.isEmpty {
                let text = "Added \(referenceCount(outcome.created.count))"
                return searchMode ? "\(text) · esc shows them" : text
            }
            if outcome.syncedNoteCount > 0 {
                let synced = noteCount(outcome.syncedNoteCount, singular: "note", plural: "notes")
                return "No new references · \(synced) synced"
            }
            return "No new references"
        case .partial:
            if !outcome.created.isEmpty {
                return "Added \(outcome.created.count) · \(pdfFailedCount(outcome.failures.count))"
            }
            return "\(pdfScanFailedCount(outcome.failures.count))"
        case .failed:
            return "Scan failed · ⌘S to retry"
        }
    }

    /// Nil when the scan succeeded: success is quiet (the section plus
    /// the footer); banners are only for problems.
    public static func bannerMessage(_ outcome: RefsScanOutcome) -> String? {
        switch outcome.kind {
        case .succeeded:
            return nil
        case .partial:
            let count = outcome.failures.count
            var lines = ["\(pdfCouldNotCount(count)) couldn't be scanned."]
            if let first = outcome.failures.first {
                lines.append(failureLine(first))
            }
            let rest = count - 1
            if rest > 0 {
                lines.append("+\(rest) more · Copy Diagnostic lists them all")
            }
            return lines.joined(separator: "\n")
        case .failed:
            guard let problem = outcome.problem else {
                return "Bob couldn't scan your library."
            }
            var lines = ["Bob couldn't scan your library.", problem.message]
            if !problem.paths.isEmpty {
                lines.append(joinedPaths(problem.paths))
            }
            if let hint = problem.hint {
                lines.append(hint)
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Nil when there is nothing to notify about: a visible panel
    /// already reports, and "nothing new" while hidden is noise.
    public static func notification(_ outcome: RefsScanOutcome) -> (title: String, body: String)? {
        switch outcome.kind {
        case .succeeded:
            guard !outcome.created.isEmpty else {
                return nil
            }
            return (
                title: "Added \(referenceCount(outcome.created.count))",
                body: joinedTitles(outcome.created)
            )
        case .partial:
            guard let first = outcome.failures.first else {
                return (
                    title: "Added \(referenceCount(outcome.created.count))",
                    body: joinedTitles(outcome.created)
                )
            }
            if !outcome.created.isEmpty {
                let count = outcome.failures.count
                let failed = count == 1 ? "1 PDF failed" : "\(count) PDFs failed"
                return (
                    title: "Added \(referenceCount(outcome.created.count)) · \(failed)",
                    body: failureLine(first)
                )
            }
            return (title: "\(pdfCouldNotCount(outcome.failures.count)) couldn't be scanned",
                body: failureLine(first))
        case .failed:
            guard let problem = outcome.problem else {
                return (title: "Bob Refs scan failed", body: "Bob couldn't scan your library.")
            }
            return (title: "Bob Refs scan failed", body: problem.message)
        }
    }

    public static func announcement(_ outcome: RefsScanOutcome) -> String {
        switch outcome.kind {
        case .succeeded:
            if !outcome.created.isEmpty {
                return "Scan added \(referenceCount(outcome.created.count))"
            }
            return "No new references"
        case .partial:
            if !outcome.created.isEmpty {
                let count = outcome.failures.count
                let failed = count == 1 ? "1 PDF failed" : "\(count) PDFs failed"
                return "Scan added \(referenceCount(outcome.created.count)); \(failed)"
            }
            return pdfScanFailedCount(outcome.failures.count)
        case .failed:
            return "Scan failed"
        }
    }

    /// The display title for a scanned note: bob's title through
    /// `TaskDisplayText`, or the note stem when the title is missing.
    public static func displayTitle(for note: RefsScanNote) -> String {
        if let title = note.title, !title.isEmpty {
            return TaskDisplayText(parsing: title).text
        }
        return stem(of: note.path)
    }

    static func stem(of path: String) -> String {
        let last = path.split(separator: "/").last.map(String.init) ?? path
        guard last.hasSuffix(".md") else {
            return last
        }
        return String(last.dropLast(3))
    }

    private static func referenceCount(_ count: Int) -> String {
        count == 1 ? "1 reference" : "\(count) references"
    }

    private static func noteCount(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }

    private static func pdfFailedCount(_ count: Int) -> String {
        count == 1 ? "1 PDF failed" : "\(count) PDFs failed"
    }

    private static func pdfScanFailedCount(_ count: Int) -> String {
        count == 1 ? "1 PDF failed to scan" : "\(count) PDFs failed to scan"
    }

    private static func pdfCouldNotCount(_ count: Int) -> String {
        count == 1 ? "1 PDF" : "\(count) PDFs"
    }

    private static func failureLine(_ failure: RefsScanFailure) -> String {
        "\(failure.pdf) — \(failure.message)"
    }

    private static func joinedTitles(_ notes: [RefsScanNote]) -> String {
        let shown = notes.prefix(3).map { displayTitle(for: $0) }
        var body = shown.joined(separator: " · ")
        let rest = notes.count - shown.count
        if rest > 0 {
            body += " · +\(rest) more"
        }
        return body
    }

    private static func joinedPaths(_ paths: [String]) -> String {
        let shown = paths.prefix(3).joined(separator: ", ")
        let rest = paths.count - 3
        guard rest > 0 else {
            return shown
        }
        return "\(shown), +\(rest) more"
    }
}
