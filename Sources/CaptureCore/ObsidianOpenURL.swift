import Foundation

// Bob returns absolute filesystem `target` paths, not `obsidian://open` URLs.
// The app builds that URL for note opens and uses the dedicated read-only
// `bob-goto-task` protocol for the `/` Go To picker and Command-\ today-
// Pomodoro landing.
public enum ObsidianOpenURL {
    public static func url(forAbsolutePath path: String) -> URL? {
        guard !path.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }

    /// Builds the read-only task navigation URL. The protocol contract keeps
    /// path slashes literal and percent-encodes every other non-unreserved
    /// UTF-8 byte, including `+` so query parsers cannot turn it into a space.
    /// A nil `ref` omits the `ref=` query item (note-top and line-only
    /// landings). A non-nil invalid `ref` still returns nil.
    public static func taskGotoURL(
        path: String,
        line: Int,
        ref: String?,
        blockID: String? = nil
    ) -> URL? {
        guard path.hasPrefix("/"), line > 0 else {
            return nil
        }
        if let ref, !isValidTaskRef(ref) {
            return nil
        }
        if let blockID, !isValidBlockID(blockID) {
            return nil
        }

        var query = [
            "path=\(percentEncodeTaskGotoValue(path))",
            "line=\(line)",
        ]
        if let ref {
            query.append("ref=\(percentEncodeTaskGotoValue(ref))")
        }
        if let blockID {
            query.append("block=\(percentEncodeTaskGotoValue(blockID))")
        }
        return URL(string: "obsidian://bob-goto-task?\(query.joined(separator: "&"))")
    }

    /// Builds the single versioned URL used to open a capture's notes.
    public static func openNotesURL(for plan: CaptureOpenPlan) -> URL? {
        guard !plan.isEmpty else { return nil }
        let notes = Array(plan.notes.prefix(8))
        var query = ["count=\(notes.count)"]
        for (offset, note) in notes.enumerated() {
            let index = offset + 1
            query.append("path\(index)=\(percentEncodeTaskGotoValue(note.path))")
            if let line = note.line, line > 0 {
                query.append("line\(index)=\(line)")
                if let ref = note.ref, isValidTaskRef(ref) {
                    query.append("ref\(index)=\(percentEncodeTaskGotoValue(ref))")
                }
            }
            if let blockID = note.blockID, isValidBlockID(blockID) {
                query.append("block\(index)=\(percentEncodeTaskGotoValue(blockID))")
            }
        }
        if plan.notes.count > notes.count {
            query.append("total=\(plan.notes.count)")
        }
        return URL(string: "obsidian://bob-open-notes?\(query.joined(separator: "&"))")
    }

    static func isValidTaskRef(_ ref: String) -> Bool {
        let parts = ref.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let line = Int(parts[0]),
              line > 0,
              String(line) == parts[0],
              parts[1].count == 8
        else {
            return false
        }
        return parts[1].utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    static func isValidBlockID(_ blockID: String) -> Bool {
        !blockID.isEmpty && blockID.utf8.allSatisfy {
            (48...57).contains($0)
                || (65...90).contains($0)
                || (97...122).contains($0)
                || $0 == 45
        }
    }

    private static func percentEncodeTaskGotoValue(_ value: String) -> String {
        var encoded = ""
        for byte in value.utf8 {
            let isUnreserved = (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || byte == 45 || byte == 46 || byte == 95 || byte == 126
            if isUnreserved || byte == 47 {
                encoded.append(Character(UnicodeScalar(byte)))
            } else {
                encoded += String(format: "%%%02X", byte)
            }
        }
        return encoded
    }
}
