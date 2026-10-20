import CaptureCore
import Foundation

/// The `bob ref show <path> -f json` envelope (schema version 1) the
/// inspector hydrates from. Only the note path, the parsed annotations,
/// the `## Tasks` lines, and the annotations status matter here; every
/// other key is ignored. All three inspector fields are lossy and use
/// `decodeIfPresent`, and undecodable rows are skipped instead of
/// failing the whole response. The inspector still projects
/// `inspectorHighlights` as one HIGHLIGHTS section in note order; the
/// Copy card's H picker reads the unfiltered annotation list.
public struct RefsShowResponse: Decodable, Equatable, Sendable, SchemaVersioned {
    public let schemaVersion: Int
    public let refs: [RefsShowRow]

    public init(schemaVersion: Int, refs: [RefsShowRow] = []) {
        self.schemaVersion = schemaVersion
        self.refs = refs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case refs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let rows = try container.decodeIfPresent(
            [LossyShowRow].self,
            forKey: .refs
        ) ?? []
        refs = rows.compactMap(\.row)
    }
}

/// One shown reference row: the note path plus its content. `path` falls
/// back to empty so a malformed row degrades instead of failing the
/// envelope; callers match rows by path and ignore empty ones.
public struct RefsShowRow: Decodable, Equatable, Sendable {
    public let path: String
    public let annotations: [RefsShowAnnotation]
    public let tasks: [RefsShowTask]
    public let annotationsStatus: String?
    public let ownNotes: String

    public init(
        path: String,
        annotations: [RefsShowAnnotation] = [],
        tasks: [RefsShowTask] = [],
        annotationsStatus: String? = nil,
        ownNotes: String = ""
    ) {
        self.path = path
        self.annotations = annotations
        self.tasks = tasks
        self.annotationsStatus = annotationsStatus
        self.ownNotes = ownNotes
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case annotations
        case tasks
        case annotationsStatus = "annotations_status"
        case ownNotes = "own_notes"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        annotations = try container.decodeIfPresent(
            [RefsShowAnnotation].self,
            forKey: .annotations
        ) ?? []
        tasks = try container.decodeIfPresent(
            [RefsShowTask].self,
            forKey: .tasks
        ) ?? []
        annotationsStatus = try container.decodeIfPresent(
            String.self,
            forKey: .annotationsStatus
        )
        ownNotes = try container.decodeIfPresent(String.self, forKey: .ownNotes) ?? ""
    }

    /// Every commented highlight, in note order. The Copy card's
    /// numbered note rows and A copy use these; the inspector no
    /// longer pages them as their own block. Images and standalone
    /// notes never appear here.
    public var commentedHighlights: [RefsShowAnnotation] {
        annotations.filter(\.hasComment)
    }

    /// Every highlight the inspector's one HIGHLIGHTS section shows, in
    /// note order: a highlight with a non-empty quote or a comment.
    /// Images, standalone notes, and empty quotes with no comment never
    /// appear here.
    public var inspectorHighlights: [RefsShowAnnotation] {
        annotations.filter(\.isInspectorHighlight)
    }

    /// Every annotation shown in the inspector's generalized preview
    /// feed, in note order. This extends the highlight-only feed with
    /// image highlights and standalone notes without changing the
    /// Copy card's existing projections.
    public var inspectorEntries: [RefsShowAnnotation] {
        annotations.filter(\.isInspectorEntry)
    }

    /// Standalone user notes in annotation order. Blank notes are ignored.
    public var standaloneNotes: [RefsShowAnnotation] {
        annotations.filter(\.isStandaloneNote)
    }

    /// Notes shown by the Copy card, preserving the source order.
    public var yourNotes: [RefsShowAnnotation] {
        annotations.filter { $0.hasComment || $0.isStandaloneNote }
    }

    /// Highlights and standalone notes the H picker can copy, in stored
    /// order. Images and empty highlights are excluded.
    public var highlightPickerEntries: [RefsShowAnnotation] {
        annotations.filter(\.isHighlightPickerEntry)
    }

    /// Open `## Tasks` lines, for the "N open" fact.
    public var openTasks: [RefsShowTask] {
        tasks.filter { !$0.checked }
    }
}

/// One parsed annotation: the author's words (`quote`) and the user's
/// words (`comment`) travel in separate fields, exactly as `bob ref
/// show` keeps them.
public struct RefsShowAnnotation: Decodable, Equatable, Sendable {
    public let pageLabel: String?
    public let kind: String
    public let quote: String?
    public let comment: String?
    public let blockID: String?
    public let link: String?
    public let asset: String?
    public let images: [String]
    public let unresolvedImages: [String]

    public init(
        pageLabel: String? = nil,
        kind: String = "highlight",
        quote: String? = nil,
        comment: String? = nil,
        blockID: String? = nil,
        link: String? = nil,
        asset: String? = nil,
        images: [String] = [],
        unresolvedImages: [String] = []
    ) {
        self.pageLabel = pageLabel
        self.kind = kind
        self.quote = quote
        self.comment = comment
        self.blockID = blockID
        self.link = link
        self.asset = Self.trimmedNonEmpty(asset)
        self.images = Self.cleaned(images)
        self.unresolvedImages = Self.cleaned(unresolvedImages)
    }

    private enum CodingKeys: String, CodingKey {
        case pageLabel = "page_label"
        case kind
        case quote
        case comment
        case blockID = "block_id"
        case link
        case asset
        case images
        case unresolvedImages = "unresolved_images"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageLabel = try container.decodeIfPresent(String.self, forKey: .pageLabel)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "highlight"
        quote = try container.decodeIfPresent(String.self, forKey: .quote)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        link = try container.decodeIfPresent(String.self, forKey: .link)
        let decodedAsset = (try? container.decodeIfPresent(String.self, forKey: .asset)) ?? nil
        asset = Self.trimmedNonEmpty(decodedAsset)
        let decodedImages = (try? container.decodeIfPresent([String].self, forKey: .images)) ?? nil
        images = Self.cleaned(decodedImages ?? [])
        let decodedUnresolved = (try? container.decodeIfPresent(
            [String].self,
            forKey: .unresolvedImages
        )) ?? nil
        unresolvedImages = Self.cleaned(decodedUnresolved ?? [])
    }

    /// Membership in the inspector's one HIGHLIGHTS section: a
    /// highlight with a non-empty trimmed quote or a comment. A
    /// whitespace-only comment counts as no comment, so the entry
    /// shows as a plain highlight.
    public var isInspectorHighlight: Bool {
        guard kind == "highlight" else {
            return false
        }
        return hasNonEmptyQuote || hasComment
    }

    /// Membership in the generalized inspector feed. Image highlights
    /// need a resolvable asset; ordinary highlights can carry text or
    /// note images; standalone notes follow the selected include
    /// decision and need at least one piece of content.
    public var isInspectorEntry: Bool {
        switch kind {
        case "highlight":
            return hasNonEmptyQuote || hasComment || !images.isEmpty || !unresolvedImages.isEmpty
        case "image":
            return Self.trimmedNonEmpty(asset) != nil
        case "note":
            return isStandaloneNote || !images.isEmpty || !unresolvedImages.isEmpty
        default:
            return false
        }
    }

    /// A highlight carrying a user comment: the inspector shows a note
    /// card under that highlight's quote.
    public var hasComment: Bool {
        guard kind == "highlight" else {
            return false
        }
        guard let comment, !comment.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return false
        }
        return true
    }

    public var isStandaloneNote: Bool {
        guard kind == "note" else {
            return false
        }
        guard let comment, !comment.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return false
        }
        return true
    }

    /// A highlight with a non-empty quote or comment, or a standalone
    /// note. The Copy card's H picker uses this; images never qualify.
    public var isHighlightPickerEntry: Bool {
        if isStandaloneNote {
            return true
        }
        guard kind == "highlight" else {
            return false
        }
        return hasNonEmptyQuote || hasComment
    }

    private var hasNonEmptyQuote: Bool {
        guard let quote else {
            return false
        }
        return !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cleaned(_ values: [String]) -> [String] {
        values.compactMap(trimmedNonEmpty)
    }

    /// The page label as the inspector shows it: nil for nil or blank;
    /// as-is when it already starts with `page`, `p.`, `p `, or the
    /// plural `pp.` continuation-group form (case-insensitive, the
    /// same prefixes as bob's `is_sidecar_page_label` plus the
    /// renderer-emitted `pp.` range); otherwise `Page <label>`.
    public var displayPageLabel: String? {
        guard let raw = pageLabel?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !raw.isEmpty else {
            return nil
        }
        let lowered = raw.lowercased()
        if lowered.hasPrefix("page") || lowered.hasPrefix("pp.")
            || lowered.hasPrefix("p.") || lowered.hasPrefix("p ")
        {
            return raw
        }
        return "Page \(raw)"
    }
}

/// How many of the inspector's notes show at once, and how many more
/// each Ctrl+D at the bottom reveals. Value-driven: the view reads
/// `visibleCount(total:)` and the model stores one per selection.
public struct RefsNotesPage: Equatable, Sendable {
    /// The first page size, and the fallback when settings are missing.
    public static let defaultSize = 5
    /// The allowed page-size range, shared with Settings.
    public static let sizeRange = 1...20

    /// Clamps a page size into `sizeRange`.
    public static func clampedSize(_ size: Int) -> Int {
        min(max(size, sizeRange.lowerBound), sizeRange.upperBound)
    }

    /// Notes shown on the first page, and revealed per page after.
    public let size: Int
    /// How many notes the current selection has revealed so far.
    public private(set) var shown: Int
    /// The first index of the latest revealed page, for the follow-tail
    /// scroll anchor. Nil until the first reveal.
    public private(set) var batchStart: Int?
    /// Increases by one per reveal, so the controller's follow task can
    /// tell a stale reveal from the current one.
    public private(set) var generation: Int

    public init(size: Int) {
        let clamped = Self.clampedSize(size)
        self.size = clamped
        shown = clamped
        batchStart = nil
        generation = 0
    }

    /// Notes visible for a total count, capped at the total so a total
    /// that shrank never leaves a gap.
    public func visibleCount(total: Int) -> Int {
        min(max(total, 0), shown)
    }

    /// Notes still hidden for a total count.
    public func hiddenCount(total: Int) -> Int {
        max(max(total, 0) - visibleCount(total: total), 0)
    }

    /// Notes the next reveal would show for a total count.
    public func nextBatchCount(total: Int) -> Int {
        min(size, hiddenCount(total: total))
    }

    /// Reveals the next page for a total count: nil when nothing is
    /// hidden, otherwise the revealed range. The start uses
    /// `visibleCount` (not the stored `shown`) so a total that shrank
    /// never leaves a gap.
    @discardableResult
    public mutating func reveal(total: Int) -> Range<Int>? {
        let safeTotal = max(total, 0)
        let start = visibleCount(total: safeTotal)
        guard safeTotal - start > 0 else {
            return nil
        }
        let end = min(safeTotal, shown + size)
        guard end > start else {
            return nil
        }
        shown = end
        batchStart = start
        generation += 1
        return start..<end
    }

    /// The disclosure-row text for hidden notes, or nil when none are
    /// hidden.
    public static func moreText(hidden: Int, nextBatch: Int) -> String? {
        guard hidden > 0 else {
            return nil
        }
        if hidden == 1 {
            return "+1 more · ⌃D shows it"
        }
        if hidden > nextBatch {
            return "+\(hidden) more · ⌃D shows \(nextBatch) more"
        }
        return "+\(hidden) more · ⌃D shows the rest"
    }
}

/// The inspector's HIGHLIGHTS feed: highlights, image highlights, and
/// standalone notes in annotation order. Entries with user notes or
/// attached images show a note card. `availableImages` is the set of
/// vault-relative paths whose metrics were prefetched successfully.
public struct RefsInspectorFeed: Equatable, Sendable {
    public let highlights: [RefsShowAnnotation]
    public let availableImages: Set<String>

    public var total: Int { highlights.count }

    /// How many entries in the feed carry a note card.
    public var notedCount: Int { entries(visible: total).filter(\.hasNoteCard).count }

    public init(
        highlights: [RefsShowAnnotation],
        availableImages: Set<String> = []
    ) {
        self.highlights = highlights
        self.availableImages = availableImages
    }

    public struct Entry: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case highlight
            case image
            case note
        }

        public let index: Int
        public let annotation: RefsShowAnnotation
        public let showsPageLabel: Bool
        public let availableImages: Set<String>

        public var kind: Kind {
            switch annotation.kind {
            case "image": .image
            case "note": .note
            default: .highlight
            }
        }

        /// The image-highlight crop. Ordinary annotations have no
        /// primary image; their image paths are in `attachedImages`.
        public var imagePath: String? {
            kind == .image ? annotation.asset : nil
        }

        public var attachedImages: [String] { annotation.images }
        public var unresolvedImages: [String] { annotation.unresolvedImages }

        public var hasNoteCard: Bool {
            if kind == .note {
                return true
            }
            return hasCommentText || !attachedImages.isEmpty || !unresolvedImages.isEmpty
        }

        /// Kept for existing view callers; note cards now include
        /// comments, attached images, unresolved images, and standalone
        /// note entries.
        public var hasNote: Bool { hasNoteCard }

        /// VoiceOver label for this entry. The page is always included
        /// when `displayPageLabel` is non-nil, even when the visual
        /// label is grouped into a run. `**` delimiters are stripped
        /// through `RefsQuoteEmphasis`; the comment is trimmed.
        public var accessibilityLabel: String {
            let quote = displayedQuote
            let comment = annotation.comment?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
            let page = annotation.displayPageLabel
            var label: String
            switch kind {
            case .highlight:
                if hasNoteCard {
                    let prefix = page.map { "Highlight with note, \($0)" }
                        ?? "Highlight with note"
                    if !quote.isEmpty {
                        label = "\(prefix): \(quote)"
                        label += Self.underlineSuffix(for: annotation.quote)
                    } else {
                        label = prefix
                    }
                    if !comment.isEmpty {
                        label += ". Your note: \(comment)"
                    }
                } else if let page {
                    label = "Highlight, \(page): \(quote)"
                    label += Self.underlineSuffix(for: annotation.quote)
                } else {
                    label = "Highlight: \(quote)"
                    label += Self.underlineSuffix(for: annotation.quote)
                }
            case .image:
                label = page.map { "Image highlight, \($0)" } ?? "Image highlight"
                if !comment.isEmpty {
                    label += ". Your note: \(comment)"
                }
            case .note:
                label = page.map { "Note, \($0)" } ?? "Note"
                if !comment.isEmpty {
                    label += ": \(comment)"
                }
            }

            let availableAttached = attachedImages.filter {
                availableImages.contains($0)
            }
            let failedAttached = attachedImages.filter {
                !availableImages.contains($0)
            }
            if !availableAttached.isEmpty {
                label += ", \(Self.imageCountPhrase(availableAttached.count, prefix: "attached "))"
            }
            if !failedAttached.isEmpty {
                let failedPhrase = Self.imageCountPhrase(
                    failedAttached.count,
                    prefix: "attached ",
                    suffix: " unavailable"
                )
                label += ", \(failedPhrase)"
            }
            var unavailable = unresolvedImages.filter { path in
                !failedAttached.contains(path)
            }
            if let imagePath, !availableImages.contains(imagePath),
                !failedAttached.contains(imagePath),
                !unavailable.contains(imagePath)
            {
                unavailable.append(imagePath)
            }
            if !unavailable.isEmpty {
                label += ", \(Self.imageCountPhrase(unavailable.count, suffix: " unavailable"))"
            }
            return label
        }

        private var hasCommentText: Bool {
            guard let comment = annotation.comment?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) else {
                return false
            }
            return !comment.isEmpty
        }

        private static func imageCountPhrase(
            _ count: Int,
            prefix: String = "",
            suffix: String = ""
        ) -> String {
            let noun = count == 1 ? "image" : "images"
            return "\(count) \(prefix)\(noun)\(suffix)"
        }

        /// VoiceOver suffix for underlined words, placed after the
        /// quote and before `Your note`. A wholly underlined quote
        /// becomes `, underlined`; otherwise `. Underlined: …`.
        private static func underlineSuffix(for rawQuote: String?) -> String {
            guard let rawQuote else {
                return ""
            }
            if RefsQuoteUnderline.isWhollyUnderlined(rawQuote) {
                return ", underlined"
            }
            let phrases = RefsQuoteUnderline.phrases(rawQuote)
            guard !phrases.isEmpty else {
                return ""
            }
            return ". Underlined: " + phrases.joined(separator: "; ")
        }

        private var displayedQuote: String {
            guard let quote = annotation.quote, !quote.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                return ""
            }
            return RefsQuoteEmphasis.plainText(quote)
        }
    }

    /// The first `visible` entries in note order, clamped to
    /// `0...total`. `showsPageLabel` follows the page-run rule over
    /// the single stream and is false when `displayPageLabel` is nil.
    public func entries(visible: Int) -> [Entry] {
        let clamped = min(max(visible, 0), total)
        guard clamped > 0 else {
            return []
        }
        var result: [Entry] = []
        result.reserveCapacity(clamped)
        var previousLabel: String?
        for offset in 0..<clamped {
            let annotation = highlights[offset]
            let label = annotation.displayPageLabel
            let showsPageLabel: Bool
            if label == nil {
                showsPageLabel = false
            } else if offset == 0 {
                showsPageLabel = true
            } else {
                showsPageLabel = label != previousLabel
            }
            previousLabel = label
            result.append(Entry(
                index: offset,
                annotation: annotation,
                showsPageLabel: showsPageLabel,
                availableImages: availableImages
            ))
        }
        return result
    }

    /// The disclosure-row text for hidden entries, or nil when none
    /// are hidden. Hidden notes and images add clauses while image-free
    /// highlights retain the previous strings.
    public func moreText(visible: Int, nextBatch: Int) -> String? {
        let hidden = hiddenCount(visible: visible)
        guard hidden > 0 else {
            return nil
        }
        let noted = hiddenNotedCount(visible: visible)
        let images = hiddenImageCount(visible: visible)
        if noted == 0 && images == 0 {
            return RefsNotesPage.moreText(hidden: hidden, nextBatch: nextBatch)
        }
        var clauses: [String] = []
        if noted > 0 {
            clauses.append(Self.notedPhrase(noted))
        }
        if images > 0 {
            clauses.append(Self.imagePhrase(images))
        }
        return "+\(hidden) more · \(clauses.joined(separator: " · ")) · "
            + revealClause(hidden: hidden, nextBatch: nextBatch)
    }

    /// VoiceOver label for the disclosure row, or nil when nothing is
    /// hidden.
    public func hiddenAccessibilityLabel(visible: Int) -> String? {
        let hidden = hiddenCount(visible: visible)
        guard hidden > 0 else {
            return nil
        }
        let noun = hidden == 1 ? "highlight" : "highlights"
        let lead = "\(hidden) more \(noun)"
        let noted = hiddenNotedCount(visible: visible)
        let images = hiddenImageCount(visible: visible)
        if noted == 0 && images == 0 {
            return lead
        }
        var clauses: [String] = []
        if noted > 0 {
            clauses.append(Self.notedPhrase(noted))
        }
        if images > 0 {
            clauses.append(Self.imagePhrase(images))
        }
        return "\(lead), \(clauses.joined(separator: ", "))"
    }

    /// VoiceOver announcement after a reveal.
    public func revealAnnouncement(visible: Int) -> String {
        let clamped = min(max(visible, 0), total)
        return "Showing \(clamped) of \(total) highlights"
    }

    /// VoiceOver label for the HIGHLIGHTS header.
    public var headerAccessibilityLabel: String {
        if notedCount == 0 {
            return "Highlights, \(total)"
        }
        return "Highlights, \(total), \(Self.notedPhrase(notedCount))"
    }

    private func hiddenCount(visible: Int) -> Int {
        max(total - min(max(visible, 0), total), 0)
    }

    private func hiddenNotedCount(visible: Int) -> Int {
        let clamped = min(max(visible, 0), total)
        return entries(visible: total).dropFirst(clamped).filter(\.hasNoteCard).count
    }

    /// Number of available primary image highlights and attached image
    /// paths in hidden entries. Missing, unreadable, invalid, and
    /// unresolved paths are excluded because they have no image to
    /// reveal.
    public func hiddenImageCount(visible: Int) -> Int {
        let clamped = min(max(visible, 0), total)
        return entries(visible: total).dropFirst(clamped).reduce(into: 0) { count, entry in
            if let path = entry.imagePath, availableImages.contains(path) {
                count += 1
            }
            count += entry.attachedImages.filter { availableImages.contains($0) }.count
        }
    }

    private func revealClause(hidden: Int, nextBatch: Int) -> String {
        if hidden == 1 {
            return "⌃D shows it"
        }
        if hidden > nextBatch {
            return "⌃D shows \(nextBatch) more"
        }
        return "⌃D shows the rest"
    }

    private static func notedPhrase(_ count: Int) -> String {
        count == 1 ? "1 with a note" : "\(count) with notes"
    }

    private static func imagePhrase(_ count: Int) -> String {
        count == 1 ? "1 image" : "\(count) images"
    }
}

/// Splits a quote into plain and strong runs by pairing `**`
/// delimiters from left to right. Unpaired markers stay literal;
/// empty pairs disappear. Single `*`, `_`, `__`, and backticks are
/// never emphasis.
public enum RefsQuoteEmphasis {
    /// The quote with every paired `**` delimiter stripped, so
    /// tooltips and VoiceOver read the words without the markup.
    /// Unpaired markers stay literal, matching `runs`.
    public static func plainText(_ text: String) -> String {
        runs(text).map(\.text).joined()
    }

    public static func runs(_ text: String) -> [RefsTextRun] {
        guard !text.isEmpty else {
            return []
        }
        var collected: [RefsTextRun] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            if let close = pairedClose(in: text, openingAt: index) {
                if !current.isEmpty {
                    collected.append(RefsTextRun(text: current, isStrong: false))
                    current = ""
                }
                let innerStart = text.index(index, offsetBy: 2)
                let inner = String(text[innerStart..<close])
                if !inner.isEmpty {
                    collected.append(RefsTextRun(text: inner, isStrong: true))
                }
                index = text.index(close, offsetBy: 2)
                continue
            }
            if delimiterStart(in: text, at: index) != nil {
                current.append(contentsOf: text[index...])
                break
            }
            current.append(text[index])
            index = text.index(after: index)
        }
        if !current.isEmpty {
            collected.append(RefsTextRun(text: current, isStrong: false))
        }
        return compacted(collected)
    }

    private static func pairedClose(
        in text: String,
        openingAt index: String.Index
    ) -> String.Index? {
        guard delimiterStart(in: text, at: index) != nil else {
            return nil
        }
        return nextDelimiter(in: text, from: text.index(index, offsetBy: 2))
    }

    private static func delimiterStart(
        in text: String,
        at index: String.Index
    ) -> String.Index? {
        let next = text.index(after: index)
        guard next < text.endIndex, text[index] == "*", text[next] == "*" else {
            return nil
        }
        return index
    }

    private static func nextDelimiter(
        in text: String,
        from start: String.Index
    ) -> String.Index? {
        var index = start
        while index < text.endIndex {
            if let found = delimiterStart(in: text, at: index) {
                return found
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func compacted(_ runs: [RefsTextRun]) -> [RefsTextRun] {
        var result: [RefsTextRun] = []
        for run in runs where !run.text.isEmpty {
            if let last = result.last, last.isStrong == run.isStrong {
                result[result.count - 1] = RefsTextRun(
                    text: last.text + run.text,
                    isStrong: last.isStrong
                )
            } else {
                result.append(run)
            }
        }
        return result
    }

    /// The lower bound of the first opening `**` delimiter, or nil
    /// when no strong run starts. Uses the same pairing rule as
    /// `runs`, so the excerpt and the quote text builder agree on
    /// where the first run begins.
    static func firstStrongOpening(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            if pairedClose(in: text, openingAt: index) != nil {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }
}

/// A clip-friendly excerpt of a quote for the 4-line inspector
/// preview: when the first strong run starts late, the preview
/// opens with a short `…` lead-in so the emphasis stays visible.
/// Spacing and every delimiter are kept, so the quote text builder
/// still sees the runs.
public enum RefsQuoteExcerpt {
    /// A run starting within this many plain characters needs no
    /// lead-in.
    public static let leadThreshold = 140
    /// How many words before the run the lead-in keeps at most.
    public static let leadInWords = 8

    public static func preview(_ quote: String) -> String {
        guard let opening = RefsQuoteEmphasis.firstStrongOpening(in: quote) else {
            return quote
        }
        let plainPrefix = RefsQuoteEmphasis.plainText(String(quote[..<opening]))
        guard plainPrefix.count >= leadThreshold else {
            return quote
        }
        let lineStart: String.Index
        if let newline = quote[..<opening].lastIndex(of: "\n") {
            lineStart = quote.index(after: newline)
        } else {
            lineStart = quote.startIndex
        }
        let start = leadInStart(lineStart: lineStart, opening: opening, in: quote)
        return "… " + quote[start...]
    }

    private static func leadInStart(
        lineStart: String.Index,
        opening: String.Index,
        in quote: String
    ) -> String.Index {
        var starts: [String.Index] = []
        var index = lineStart
        while index < opening {
            while index < opening, quote[index].isWhitespace {
                index = quote.index(after: index)
            }
            guard index < opening else {
                break
            }
            starts.append(index)
            while index < opening, !quote[index].isWhitespace {
                index = quote.index(after: index)
            }
        }
        return starts.suffix(leadInWords).first ?? lineStart
    }
}

/// One run of quote text, with or without strong emphasis.
public struct RefsTextRun: Equatable, Sendable {
    public let text: String
    public let isStrong: Bool

    public init(text: String, isStrong: Bool) {
        self.text = text
        self.isStrong = isStrong
    }
}

/// One parsed `## Tasks` line: the checkbox state, its mark, and the
/// text with block links and inline fields stripped.
public struct RefsShowTask: Decodable, Equatable, Sendable {
    public let checked: Bool
    public let mark: String
    public let text: String

    public init(checked: Bool = false, mark: String = "", text: String = "") {
        self.checked = checked
        self.mark = mark
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case checked
        case mark
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checked = try container.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        mark = try container.decodeIfPresent(String.self, forKey: .mark) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

/// One `refs` array element that never fails: an undecodable row becomes
/// nil and is dropped, so a single bad row cannot fail the inspector.
private struct LossyShowRow: Decodable {
    let row: RefsShowRow?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        row = try? container.decode(RefsShowRow.self)
    }
}

/// A Bottom-line or Abstract excerpt: either one paragraph or up to 3
/// bullets. The view labels bottom-line excerpts `SUMMARY` and paper
/// excerpts `ABSTRACT`.
public struct RefsSummary: Equatable, Sendable {
    public let label: String
    public let paragraph: String?
    public let bullets: [String]

    public init(label: String, paragraph: String? = nil, bullets: [String] = []) {
        self.label = label
        self.paragraph = paragraph
        self.bullets = bullets
    }
}

/// Extracts Bottom-line and Abstract excerpts from PDF lead text (the
/// first pages' text the intrinsics loader reads with PDFKit). Pure
/// string work, so it stays in RefsCore and runs on Linux.
public enum RefsSummaryExtractor {
    /// Maximum characters of a Bottom-line paragraph.
    public static let bottomLineParagraphCap = 360
    /// Maximum bullets of a Bottom-line list.
    public static let bottomLineBulletCap = 3
    /// Maximum characters of one Bottom-line bullet.
    public static let bottomLineBulletCapChars = 140
    /// Maximum characters of an Abstract excerpt.
    public static let abstractCap = 420

    /// The first paragraph or up to 3 bullets under a Bottom line (or
    /// TL;DR, Summary, Executive summary, Key findings) heading, or nil
    /// when no such heading exists. The excerpt ends at the next blank
    /// line or the next heading-like line.
    public static func bottomLine(fromLeadText text: String) -> RefsSummary? {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { isBottomLineHeading($0) }) else {
            return nil
        }
        var excerpt: [String] = []
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if excerpt.isEmpty {
                    continue
                }
                break
            }
            if isHeadingLike(line) {
                break
            }
            excerpt.append(line)
        }
        let excerptLines = excerpt.drop(while: {
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        })
        guard !excerptLines.isEmpty else {
            return nil
        }
        if excerptLines.allSatisfy({ isBullet($0) }) {
            let bullets = excerptLines.prefix(bottomLineBulletCap).map {
                truncateAtWordBoundary(
                    stripBullet($0),
                    cap: bottomLineBulletCapChars
                )
            }.filter { !$0.isEmpty }
            guard !bullets.isEmpty else {
                return nil
            }
            return RefsSummary(label: "SUMMARY", bullets: bullets)
        }
        let paragraph = truncateAtWordBoundary(
            excerptLines.joined(separator: " "),
            cap: bottomLineParagraphCap
        )
        guard !paragraph.isEmpty else {
            return nil
        }
        return RefsSummary(label: "SUMMARY", paragraph: paragraph)
    }

    /// Up to 420 characters after an "Abstract" line, or nil when no
    /// Abstract heading exists. The heading is a line equal to
    /// "Abstract" or one beginning "Abstract:" or "Abstract—".
    public static func abstract(fromLeadText text: String) -> RefsSummary? {
        let lines = text.components(separatedBy: "\n")
        var startIndex: Int?
        var remainder = ""
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.caseInsensitiveCompare("Abstract") == .orderedSame {
                startIndex = index + 1
                break
            }
            let lowered = trimmed.lowercased()
            for marker in ["abstract:", "abstract—", "abstract–", "abstract-"] {
                if lowered.hasPrefix(marker) {
                    startIndex = index + 1
                    remainder = String(trimmed.dropFirst(marker.count)).trimmingCharacters(
                        in: .whitespaces
                    )
                    break
                }
            }
            if startIndex != nil {
                break
            }
        }
        guard let start = startIndex else {
            return nil
        }
        var parts: [String] = []
        if !remainder.isEmpty {
            parts.append(remainder)
        }
        if start < lines.count {
            for line in lines[start...] {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    if parts.count <= (remainder.isEmpty ? 0 : 1) {
                        continue
                    }
                    break
                }
                if isHeadingLike(line) {
                    break
                }
                parts.append(trimmed)
            }
        }
        guard !parts.isEmpty else {
            return nil
        }
        let paragraph = truncateAtWordBoundary(
            parts.joined(separator: " "),
            cap: abstractCap
        )
        guard !paragraph.isEmpty else {
            return nil
        }
        return RefsSummary(label: "ABSTRACT", paragraph: paragraph)
    }

    /// Whether a line opens a Bottom-line section: an optional numeric
    /// prefix (`1`, `2.1`) plus one of the known headings, case-
    /// insensitive, with an optional trailing colon.
    public static func isBottomLineHeading(_ line: String) -> Bool {
        let names = "bottom line|tl;?dr|summary|executive summary|key findings"
        let pattern = "^\\s*(\\d+(\\.\\d+)*\\s*)?(" + names + ")\\s*:?\\s*$"
        return line.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// Whether a line looks like a section heading: a Markdown `#`
    /// heading, or a short line (at most 8 words) with no period and no
    /// terminal punctuation. A backstop so excerpts stop at the next
    /// section instead of running into it.
    public static func isHeadingLike(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 80 else {
            return false
        }
        if trimmed.hasPrefix("#") {
            return true
        }
        if isBottomLineHeading(line) {
            return true
        }
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            return false
        }
        if trimmed.contains(".") {
            return false
        }
        let words = trimmed.split(separator: " ")
        guard words.count <= 8 else {
            return false
        }
        guard let first = trimmed.first, first.isUppercase || first.isNumber else {
            return false
        }
        return true
    }

    private static func isBullet(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return false
        }
        for marker in ["- ", "* ", "• "] {
            if trimmed.hasPrefix(marker) {
                return true
            }
        }
        if trimmed.first == "-" || trimmed.first == "*" || trimmed.first == "•" {
            return true
        }
        let pattern = #"^\d+[.)]\s+\S"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private static func stripBullet(_ line: String) -> String {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "• ", "-", "*", "•"] {
            if trimmed.hasPrefix(marker) {
                trimmed = String(trimmed.dropFirst(marker.count)).trimmingCharacters(
                    in: .whitespaces
                )
                break
            }
        }
        if let range = trimmed.range(
            of: #"^\d+[.)]\s+"#,
            options: .regularExpression
        ) {
            trimmed = String(trimmed[range.upperBound...]).trimmingCharacters(
                in: .whitespaces
            )
        }
        return trimmed
    }

    /// Cuts text at a word boundary with "…": the longest prefix within
    /// `cap` characters that ends on whitespace, plus "…". Text within
    /// the cap returns unchanged.
    public static func truncateAtWordBoundary(_ text: String, cap: Int) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > cap else {
            return collapsed
        }
        let prefix = String(collapsed.prefix(cap))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]) + "…"
        }
        return prefix + "…"
    }
}

/// A reading-time estimate: 230 words per minute, minimum 1 minute,
/// rounded to the nearest 5 at 20 minutes or more, plus Pomodoros at 25
/// minutes each. Always labeled as an estimate, never progress.
public struct RefsReadingTime: Equatable, Sendable {
    public let minutes: Int
    public let pomodoros: Int

    /// Words per minute.
    public static let wordsPerMinute = 230
    /// Pomodoro length in minutes.
    public static let pomodoroMinutes = 25
    /// Estimates at or above this long round to the nearest 5 minutes.
    public static let roundingThresholdMinutes = 20
    public static let roundingStepMinutes = 5

    public init(minutes: Int, pomodoros: Int) {
        self.minutes = minutes
        self.pomodoros = pomodoros
    }

    public static func estimate(words: Int) -> RefsReadingTime {
        let raw = max(1, Int((Double(max(words, 0)) / Double(wordsPerMinute)).rounded()))
        let minutes: Int
        if raw >= roundingThresholdMinutes {
            let step = roundingStepMinutes
            minutes = ((raw + step / 2) / step) * step
        } else {
            minutes = raw
        }
        let pomodoros = max(1, (minutes + pomodoroMinutes - 1) / pomodoroMinutes)
        return RefsReadingTime(minutes: minutes, pomodoros: pomodoros)
    }

    /// "≈ 17 min · 1 Pomodoro".
    public var formatted: String {
        let pomodoroWord = pomodoros == 1 ? "Pomodoro" : "Pomodoros"
        return "≈ \(minutes) min · \(pomodoros) \(pomodoroWord)"
    }
}

/// Cleans PDF outline headings for the inspector's Contents block and
/// for T3 heading matches: trims, drops empties and Contents/Table of
/// Contents, dedupes, and keeps at most 6.
public enum RefsOutline {
    /// Maximum headings kept.
    public static let maxHeadings = 6

    public static func clean(_ titles: [String]) -> [String] {
        var seen = Set<String>()
        var cleaned: [String] = []
        for raw in titles {
            let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                continue
            }
            let lowered = title.lowercased()
            guard lowered != "contents" && lowered != "table of contents" else {
                continue
            }
            guard seen.insert(title).inserted else {
                continue
            }
            cleaned.append(title)
            if cleaned.count == maxHeadings {
                break
            }
        }
        return cleaned
    }
}
