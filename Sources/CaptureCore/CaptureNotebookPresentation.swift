import Foundation

/// Additive per-item summary returned for notebook capture results. Bob
/// owns route identity and all capture decisions; every field is optional
/// so an incomplete future payload cannot break an otherwise usable result.
public struct CaptureNotebookSummary: Codable, Equatable, Sendable {
    public let route: String?
    public let title: String?
    public let breadcrumb: [String]?
    public let section: String?
    public let sectionAction: String?
    public let blockID: String?
    public let parentBlockID: String?

    public init(
        route: String? = nil,
        title: String? = nil,
        breadcrumb: [String]? = nil,
        section: String? = nil,
        sectionAction: String? = nil,
        blockID: String? = nil,
        parentBlockID: String? = nil
    ) {
        self.route = route
        self.title = title
        self.breadcrumb = breadcrumb
        self.section = section
        self.sectionAction = sectionAction
        self.blockID = blockID
        self.parentBlockID = parentBlockID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        route = (try? container.decodeIfPresent(String.self, forKey: .route)) ?? nil
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil
        breadcrumb = (try? container.decodeIfPresent([String].self, forKey: .breadcrumb)) ?? nil
        section = (try? container.decodeIfPresent(String.self, forKey: .section)) ?? nil
        sectionAction =
            (try? container.decodeIfPresent(String.self, forKey: .sectionAction)) ?? nil
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? nil
        parentBlockID =
            (try? container.decodeIfPresent(String.self, forKey: .parentBlockID)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case route
        case title
        case breadcrumb
        case section
        case sectionAction = "section_action"
        case blockID = "block_id"
        case parentBlockID = "parent_block_id"
    }
}

/// Shared, portable copy and file pairing for notebook previews, success
/// status, batch summaries, notifications, and accessibility.
public enum CaptureNotebookPresentation {
    public struct NoteRun: Equatable, Sendable, Identifiable {
        public let route: String
        public let title: String
        /// Original indexes in the capture result array.
        public let itemIndexes: [Int]

        public var id: String { "\(route)-\(itemIndexes.first ?? -1)" }
        public var headline: String { "📓 \(itemIndexes.count) notes → \(title)" }
    }

    public static func isNotebook(_ item: CaptureCommandSuccess) -> Bool {
        isNotebookKind(item.kind)
    }

    public static func isNotebookKind(_ kind: String) -> Bool {
        ["notebook_note", "notebook_sub_note", "notebook_create"].contains(kind)
    }

    public static func friendlyKindLabel(_ kind: String) -> String? {
        switch kind {
        case "notebook_note", "notebook_sub_note":
            return "Notebook note"
        case "notebook_create":
            return "Notebook"
        default:
            return nil
        }
    }

    /// Human headline from Bob's decoded metadata. Route and path strings
    /// remain untouched for insertion and file identity.
    public static func headline(for item: CaptureCommandSuccess) -> String {
        let notebook = item.notebook
        let title = nonempty(notebook?.title)
            ?? nonempty(notebook?.route)
            ?? nonempty(item.routeLabel)
            ?? item.relativeTarget

        switch item.kind {
        case "notebook_create":
            let path = nonempty(item.relativeTarget) ?? item.routeLabel
            if let parent = creationParentContext(for: item) {
                return "📓 New notebook \(path) · in \(parent)"
            }
            return "📓 New notebook \(path)"
        case "notebook_sub_note":
            if let parent = nonempty(notebook?.parentBlockID) {
                return "📓 Note → \(title) › ^\(parent)"
            }
            return "📓 Note → \(title)"
        case "notebook_note":
            var label = "📓 Note → \(title)"
            if let section = nonempty(notebook?.section) {
                label += " › \(section)"
            }
            if let blockID = nonempty(notebook?.blockID) {
                label += " · ^\(blockID)"
            }
            return label
        default:
            return item.routeLabel.isEmpty ? item.relativeTarget : item.routeLabel
        }
    }

    public static func newSectionBadge(for item: CaptureCommandSuccess) -> String? {
        guard item.kind == "notebook_note",
              item.notebook?.sectionAction == "create",
              let section = nonempty(item.notebook?.section)
        else {
            return nil
        }
        return "New section · \(section)"
    }

    public static func destinationLine(for item: CaptureCommandSuccess) -> String {
        guard item.kind == "notebook_note",
              let section = nonempty(item.notebook?.section)
        else {
            return "· top"
        }
        return "› \(section)"
    }

    public static func groupedNewSectionLabel(for item: CaptureCommandSuccess) -> String? {
        guard item.kind == "notebook_note", item.notebook?.sectionAction == "create" else {
            return nil
        }
        return "New section"
    }

    public static func editorSectionHelp(
        parse: CaptureParseResponse,
        cursorUTF8: Int
    ) -> String? {
        guard let span = parse.spans.first(where: {
            $0.kind == "section" && $0.notebook == true
                && cursorUTF8 >= $0.start && cursorUTF8 <= $0.end
        }),
        let title = nonempty(span.title)
        else {
            return nil
        }
        return span.sectionAction == "create"
            ? "\(title), new section"
            : "\(title), existing section"
    }

    /// Consecutive notes to one notebook form a run. Missing metadata,
    /// route changes, notebook-creation items, sub-notes, and ordinary captures split runs.
    /// Single notes stay on the established per-item preview surface.
    public static func groupedNoteRuns(items: [CaptureCommandSuccess]) -> [NoteRun] {
        var runs: [NoteRun] = []
        var currentRoute: String?
        var currentTitle = ""
        var currentIndexes: [Int] = []

        func finishRun() {
            if currentIndexes.count > 1, let route = currentRoute {
                runs.append(NoteRun(
                    route: route,
                    title: currentTitle,
                    itemIndexes: currentIndexes
                ))
            }
            currentRoute = nil
            currentTitle = ""
            currentIndexes = []
        }

        for (index, item) in items.enumerated() {
            guard item.kind == "notebook_note",
                  let route = nonempty(item.notebook?.route)
            else {
                finishRun()
                continue
            }
            if currentRoute == route {
                currentIndexes.append(index)
            } else {
                finishRun()
                currentRoute = route
                currentTitle = nonempty(item.notebook?.title) ?? route
                currentIndexes = [index]
            }
        }
        finishRun()
        return runs
    }

    /// Bob supplies breadcrumb from owner through the new notebook title.
    /// The immediate parent is the penultimate component. Never infer a
    /// parent from a filename, route prefix, or the root owner.
    public static func creationParentContext(for item: CaptureCommandSuccess) -> String? {
        guard item.kind == "notebook_create",
              let breadcrumb = item.notebook?.breadcrumb,
              breadcrumb.count >= 2
        else {
            return nil
        }
        return nonempty(breadcrumb[breadcrumb.count - 2])
    }

    public static func contentText(for item: CaptureCommandSuccess) -> String {
        nonempty(item.text) ?? nonempty(item.taskLine) ?? ""
    }

    /// Creation items pair to the exact note_files path/action entry.
    /// Record rows retain their existing identity rule. Each file is
    /// consumed once in draft order, including mixed create-then-use drafts.
    public static func pairIndexed(
        files: [CaptureNoteFile],
        items: [CaptureCommandSuccess]
    ) -> [Int: CaptureNoteFile] {
        var remaining = files
        var pairs: [Int: CaptureNoteFile] = [:]
        for (index, item) in items.enumerated() {
            let expectedAction: String
            let shouldPair: Bool
            if item.kind == "notebook_create" {
                expectedAction = "create"
                shouldPair = true
            } else if item.kind == "record_note" || item.kind == "record_update" {
                if let action = item.recordNote?.action, !action.isEmpty {
                    expectedAction = action
                } else {
                    expectedAction = item.kind == "record_update" ? "update" : "create"
                }
                shouldPair = true
            } else {
                expectedAction = ""
                shouldPair = false
            }
            guard shouldPair,
                  let fileIndex = remaining.firstIndex(where: {
                      $0.path == item.relativeTarget && $0.action == expectedAction
                  })
            else {
                continue
            }
            pairs[index] = remaining.remove(at: fileIndex)
        }
        return pairs
    }

    public static func notificationTitle(for item: CaptureCommandSuccess) -> String {
        headline(for: item)
    }

    public static func notificationBody(
        for item: CaptureCommandSuccess,
        file: CaptureNoteFile? = nil
    ) -> String {
        if item.kind == "notebook_create", let body = nonempty(file?.body) {
            return body
        }
        return contentText(for: item)
    }

    public static func batchLine(for item: CaptureCommandSuccess) -> String {
        let content = contentText(for: item)
        return content.isEmpty ? headline(for: item) : "\(headline(for: item)) · \(content)"
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
