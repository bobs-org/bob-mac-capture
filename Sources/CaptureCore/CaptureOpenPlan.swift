import Foundation

/// One destination reported by `bob capture --format json`.
public struct CaptureOpenNote: Codable, Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case note
        case day
        case other(String)

        fileprivate var rawValue: String {
            switch self {
            case .note: "note"
            case .day: "day"
            case .other(let value): value
            }
        }

        fileprivate init(rawValue: String) {
            switch rawValue {
            case "note": self = .note
            case "day": self = .day
            default: self = .other(rawValue)
            }
        }
    }

    public let path: String
    public let relativePath: String
    public let role: Role
    public let label: String
    public let line: Int?
    public let ref: String?
    public let blockID: String?

    public init(
        path: String,
        relativePath: String,
        role: Role,
        label: String,
        line: Int? = nil,
        ref: String? = nil,
        blockID: String? = nil
    ) {
        self.path = path
        self.relativePath = relativePath
        self.role = role
        self.label = label
        self.line = line.flatMap { $0 > 0 ? $0 : nil }
        self.ref = ref.flatMap { ObsidianOpenURL.isValidTaskRef($0) ? $0 : nil }
        self.blockID = blockID.flatMap { ObsidianOpenURL.isValidBlockID($0) ? $0 : nil }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        path = try values.decode(String.self, forKey: .path)
        relativePath = try values.decodeIfPresent(String.self, forKey: .relativePath) ?? path
        role = Role(rawValue: try values.decodeIfPresent(String.self, forKey: .role) ?? "other")
        label = try values.decodeIfPresent(String.self, forKey: .label) ?? relativePath
        let decodedLine = try? values.decode(Int.self, forKey: .line)
        line = decodedLine.flatMap { $0 > 0 ? $0 : nil }
        let decodedRef = try? values.decode(String.self, forKey: .ref)
        ref = decodedRef.flatMap { ObsidianOpenURL.isValidTaskRef($0) ? $0 : nil }
        let decodedBlockID = try? values.decode(String.self, forKey: .blockID)
        blockID = decodedBlockID.flatMap { ObsidianOpenURL.isValidBlockID($0) ? $0 : nil }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(path, forKey: .path)
        try values.encode(relativePath, forKey: .relativePath)
        try values.encode(role.rawValue, forKey: .role)
        try values.encode(label, forKey: .label)
        try values.encodeIfPresent(line, forKey: .line)
        try values.encodeIfPresent(ref, forKey: .ref)
        try values.encodeIfPresent(blockID, forKey: .blockID)
    }

    fileprivate var notificationDictionary: [String: Any] {
        var value: [String: Any] = [
            "path": path,
            "relative_path": relativePath,
            "role": role.rawValue,
            "label": label,
        ]
        if let line { value["line"] = line }
        if let ref { value["ref"] = ref }
        if let blockID { value["block_id"] = blockID }
        return value
    }

    fileprivate init?(notificationDictionary: [String: Any]) {
        guard let path = notificationDictionary["path"] as? String else { return nil }
        let relativePath = notificationDictionary["relative_path"] as? String ?? path
        let role = Role(rawValue: notificationDictionary["role"] as? String ?? "other")
        let label = notificationDictionary["label"] as? String ?? relativePath
        let line = notificationDictionary["line"] as? Int
        let ref = notificationDictionary["ref"] as? String
        let blockID = notificationDictionary["block_id"] as? String
        self.init(
            path: path,
            relativePath: relativePath,
            role: role,
            label: label,
            line: line,
            ref: ref,
            blockID: blockID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case relativePath = "relative_path"
        case role
        case label
        case line
        case ref
        case blockID = "block_id"
    }
}

/// The portable, normalized decision about which notes a capture should open.
public struct CaptureOpenPlan: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case bob
        case legacy
    }

    public let notes: [CaptureOpenNote]
    public let source: Source
    public var isEmpty: Bool { notes.isEmpty }

    public init(openNotes: [CaptureOpenNote]?, captures: [CaptureCommandSuccess]) {
        if let openNotes {
            notes = Self.unique(openNotes.filter { !$0.path.isEmpty && $0.path.hasPrefix("/") })
            source = .bob
        } else {
            notes = Self.legacyNotes(captures: captures)
            source = .legacy
        }
    }

    /// Property-list-safe representation for notification `userInfo`.
    public var notificationPayload: [[String: Any]] {
        notes.map(\.notificationDictionary)
    }

    public init?(notificationPayload: [[String: Any]]) {
        let decoded = notificationPayload.compactMap(CaptureOpenNote.init(notificationDictionary:))
        guard decoded.count == notificationPayload.count else { return nil }
        notes = Self.unique(decoded)
        source = .bob
    }

    private static func unique(_ notes: [CaptureOpenNote]) -> [CaptureOpenNote] {
        var seen = Set<String>()
        return notes.filter { seen.insert($0.path).inserted }
    }

    private static func legacyNotes(captures: [CaptureCommandSuccess]) -> [CaptureOpenNote] {
        var notes: [CaptureOpenNote] = []
        var seen = Set<String>()
        func append(_ note: CaptureOpenNote) {
            if seen.insert(note.path).inserted { notes.append(note) }
        }

        for capture in captures {
            let label = capture.routeLabel.isEmpty ? capture.relativeTarget : capture.routeLabel
            if !capture.target.isEmpty, capture.target.hasPrefix("/") {
                append(CaptureOpenNote(
                    path: capture.target,
                    relativePath: capture.relativeTarget,
                    role: .note,
                    label: label
                ))
            }
            guard let dayFile = capture.dayFile, dayFile.hasPrefix("/"),
                  legacyCaptureWroteDayFile(capture)
            else { continue }
            append(CaptureOpenNote(
                path: dayFile,
                relativePath: dayFile,
                role: .day,
                label: label
            ))
        }
        return notes
    }

    private static func legacyCaptureWroteDayFile(_ capture: CaptureCommandSuccess) -> Bool {
        if CapturePomodoroResetPresentation(capture: capture) != nil { return true }
        if CapturePomodoroClosePresentation(capture: capture) != nil { return true }
        if CapturePomodoroStartPresentation.isSessionStart(capture) { return true }
        if let toggle = CaptureTogglePresentation(capture: capture) { return toggle.dayFileChanged }
        if CaptureTaskCompletePresentation(capture: capture) != nil {
            guard let summary = capture.taskComplete else { return false }
            return summary.ledger != nil || summary.unblocked.contains { $0.link != nil }
        }
        if let link = CapturePomodoroLinkPresentation(capture: capture) { return link.dayFileChanged }
        if let note = capture.projectNote, !note.taskLinks.isEmpty { return true }
        return false
    }
}
