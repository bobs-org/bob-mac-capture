import Foundation

/// The host surface a tipped alias lesson opens.
public enum CaptureAliasTipHost: String, Codable, Equatable, Sendable {
    case completionList
    case picker
}

/// One bob-proved typing lesson, keyed by bob's stable alias id.
public struct CaptureAliasLesson: Equatable, Sendable {
    public let id: String
    public let host: CaptureAliasTipHost

    public init(id: String, host: CaptureAliasTipHost) {
        self.id = id
        self.host = host
    }

    public static let routeAfterText = "route_after_text"
    public static let hashMenu = "hash_menu"
    public static let blockIDAfterRoute = "block_id_after_route"
    public static let linkAfterRoute = "link_after_route"
    public static let taskLinkItem = "task_link_item"
    public static let moveBulletCaret = "move_bullet_caret"
    public static let moveBulletColon = "move_bullet_colon"
    public static let parentTask = "parent_task"
    public static let relation = "relation"
    public static let dependency = "dependency"
    public static let blockedTask = "blocked_task"

    public static let all: [CaptureAliasLesson] = [
        CaptureAliasLesson(id: routeAfterText, host: .completionList),
        CaptureAliasLesson(id: hashMenu, host: .completionList),
        CaptureAliasLesson(id: blockIDAfterRoute, host: .picker),
        CaptureAliasLesson(id: linkAfterRoute, host: .picker),
        CaptureAliasLesson(id: taskLinkItem, host: .picker),
        CaptureAliasLesson(id: moveBulletCaret, host: .picker),
        CaptureAliasLesson(id: moveBulletColon, host: .picker),
        CaptureAliasLesson(id: parentTask, host: .picker),
        CaptureAliasLesson(id: relation, host: .picker),
        CaptureAliasLesson(id: dependency, host: .picker),
        CaptureAliasLesson(id: blockedTask, host: .picker),
    ]

    /// The host for a known tipped id, or nil for unknown ids.
    public static func host(for id: String) -> CaptureAliasTipHost? {
        all.first(where: { $0.id == id })?.host
    }

    /// True when bob's id is a known tipped lesson.
    public static func isKnown(id: String) -> Bool {
        host(for: id) != nil
    }
}

/// Presentation strings for one tip. Pure and host-agnostic.
public struct CaptureAliasTipPresentation: Equatable, Sendable {
    public static let leadText = "Next time"
    public static let helpText = "Typing tips can be turned off in Settings"

    public static let glyphNames: [String: String] = [
        ".": "period",
        ";": "semicolon",
        ",": "comma",
        "/": "slash",
        "\\": "backslash",
        "=": "equals sign",
        "@": "at sign",
        "#": "hash",
        "^": "caret",
        ":": "colon",
        "+": "plus",
        "~": "tilde",
        "&": "ampersand",
        "*": "asterisk",
    ]

    public let key: String
    public let sigil: String
    public let phrase: String?
    public let accessibilityLabel: String

    public init(tip: CaptureSigilAliasTip) {
        let key = tip.keys.first ?? ""
        self.key = key
        sigil = tip.sigil
        phrase = tip.positionPhrase
        accessibilityLabel = Self.accessibilityLabel(
            key: key,
            sigil: tip.sigil,
            phrase: tip.positionPhrase
        )
    }

    public var leadText: String { Self.leadText }
    public var helpText: String { Self.helpText }

    public static func glyphName(for text: String) -> String {
        if let name = glyphNames[text] {
            return name
        }
        if text.count == 1 {
            return text
        }
        return text
    }

    private static func accessibilityLabel(key: String, sigil: String, phrase: String?) -> String {
        let keyName = glyphName(for: key)
        let sigilName = glyphName(for: sigil)
        if let phrase, !phrase.isEmpty {
            return "Tip for next time: \(phrase), \(keyName) types \(sigilName)."
        }
        return "Tip for next time: \(keyName) types \(sigilName)."
    }
}

/// One recorded chance: a miss on a physically typed sigil, or a hit on a
/// surviving forward alias.
public enum AliasTipChance: String, Codable, Equatable, Sendable {
    case hit
    case miss
}

/// Why a bob-proved typing tip did not appear. Values are persisted in the
/// local ledger, so their raw strings are a stable diagnostics contract.
public enum AliasTipDropReason: String, Codable, CaseIterable, Equatable, Sendable {
    case lateReply = "late_reply"
    case sigilEdited = "sigil_edited"
    case unanchored
    case superseded
    case closed
    case notDue = "not_due"
    case session
    case host
    case budget
}

/// Thresholds for the fade-by-fluency policy. The values are hypotheses
/// kept as named constants.
public enum AliasTipPolicy: Sendable {
    public static let maxRecent = 8
    public static let fluencyMinChances = 4
    public static let fluencyEntryRate = 0.75
    public static let fluencyExitRate = 0.5
    public static let learningTipCount = 3
    public static let initialGap = 2
    public static let maxGap = 8
    public static let lapseGap = 4
    public static let maxWeeks = 12
    public static let ledgerVersion = 1

    public static func hitRate(for recent: [AliasTipChance]) -> Double {
        guard !recent.isEmpty else {
            return 0
        }
        let hits = recent.filter { $0 == .hit }.count
        return Double(hits) / Double(recent.count)
    }

    public static func entersFluency(recent: [AliasTipChance]) -> Bool {
        guard recent.count >= fluencyMinChances else {
            return false
        }
        return hitRate(for: recent) >= fluencyEntryRate
    }

    public static func leavesFluency(recent: [AliasTipChance]) -> Bool {
        hitRate(for: recent) < fluencyExitRate
    }

    public static func isDue(
        tipsShown: Int,
        missesSinceTip: Int,
        gap: Int,
        fluent: Bool
    ) -> Bool {
        guard !fluent else {
            return false
        }
        if tipsShown < learningTipCount {
            return true
        }
        return missesSinceTip >= gap
    }

    public static func nextGap(tipsShownBefore: Int, gap: Int) -> Int {
        guard tipsShownBefore >= learningTipCount else {
            return gap
        }
        return min(gap * 2, maxGap)
    }
}

/// Per-lesson learning state.
public struct AliasTipLessonState: Codable, Equatable, Sendable {
    public var recent: [AliasTipChance]
    public var tipsShown: Int
    public var missesSinceTip: Int
    public var gap: Int
    public var fluent: Bool

    public init(
        recent: [AliasTipChance] = [],
        tipsShown: Int = 0,
        missesSinceTip: Int = 0,
        gap: Int = AliasTipPolicy.initialGap,
        fluent: Bool = false
    ) {
        self.recent = recent
        self.tipsShown = tipsShown
        self.missesSinceTip = missesSinceTip
        self.gap = gap
        self.fluent = fluent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recent = try container.decodeIfPresent([AliasTipChance].self, forKey: .recent) ?? []
        tipsShown = try container.decodeIfPresent(Int.self, forKey: .tipsShown) ?? 0
        missesSinceTip = try container.decodeIfPresent(Int.self, forKey: .missesSinceTip) ?? 0
        gap = try container.decodeIfPresent(Int.self, forKey: .gap) ?? AliasTipPolicy.initialGap
        fluent = try container.decodeIfPresent(Bool.self, forKey: .fluent) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case recent
        case tipsShown
        case missesSinceTip
        case gap
        case fluent
    }

    public var isDue: Bool {
        AliasTipPolicy.isDue(
            tipsShown: tipsShown,
            missesSinceTip: missesSinceTip,
            gap: gap,
            fluent: fluent
        )
    }

    public mutating func recordMiss(shown: Bool) {
        recent.append(.miss)
        if recent.count > AliasTipPolicy.maxRecent {
            recent.removeFirst(recent.count - AliasTipPolicy.maxRecent)
        }
        if shown {
            gap = AliasTipPolicy.nextGap(tipsShownBefore: tipsShown, gap: gap)
            tipsShown += 1
            missesSinceTip = 0
        } else {
            missesSinceTip += 1
        }
        refreshFluency()
    }

    public mutating func recordHit() {
        recent.append(.hit)
        if recent.count > AliasTipPolicy.maxRecent {
            recent.removeFirst(recent.count - AliasTipPolicy.maxRecent)
        }
        refreshFluency()
    }

    /// Removes one recorded hit, newest first. Escaping an alias undoes it.
    public mutating func withdrawHit() {
        if let index = recent.lastIndex(of: .hit) {
            recent.remove(at: index)
        }
        refreshFluency()
    }

    private mutating func refreshFluency() {
        if fluent {
            if AliasTipPolicy.leavesFluency(recent: recent) {
                fluent = false
                gap = AliasTipPolicy.lapseGap
                missesSinceTip = 0
            }
        } else if AliasTipPolicy.entersFluency(recent: recent) {
            fluent = true
        }
    }
}

/// Weekly counts for one lesson, keyed by ISO week.
public struct AliasTipWeekEntry: Codable, Equatable, Sendable {
    public var hits: Int
    public var misses: Int
    public var shown: Int

    public init(hits: Int = 0, misses: Int = 0, shown: Int = 0) {
        self.hits = hits
        self.misses = misses
        self.shown = shown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hits = try container.decodeIfPresent(Int.self, forKey: .hits) ?? 0
        misses = try container.decodeIfPresent(Int.self, forKey: .misses) ?? 0
        shown = try container.decodeIfPresent(Int.self, forKey: .shown) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case hits
        case misses
        case shown
    }
}

/// In-memory identity for one alias adoption. The token is never serialized;
/// it lets Undo withdraw this exact hit once, even when another gesture used
/// the same lesson in the same week.
public struct AliasTipHitCredit: Equatable, Sendable {
    fileprivate let token: UUID
    fileprivate let lessonID: String
    fileprivate let weekKey: String

    fileprivate init(token: UUID = UUID(), lessonID: String, weekKey: String) {
        self.token = token
        self.lessonID = lessonID
        self.weekKey = weekKey
    }
}

/// The persisted typing-tips ledger. It never stores draft text, target
/// names, or keystroke history.
public struct AliasTipLedger: Codable, Equatable, Sendable {
    public static let currentVersion = AliasTipPolicy.ledgerVersion

    public var version: Int
    public var lessons: [String: AliasTipLessonState]
    public var ineligible: [String: Int]
    public var weeks: [String: [String: AliasTipWeekEntry]]
    public var dropped: [String: Int]
    private var liveHitCredits: Set<UUID> = []

    public init(
        version: Int = currentVersion,
        lessons: [String: AliasTipLessonState] = [:],
        ineligible: [String: Int] = [:],
        weeks: [String: [String: AliasTipWeekEntry]] = [:],
        dropped: [String: Int] = [:]
    ) {
        self.version = version
        self.lessons = lessons
        self.ineligible = ineligible
        self.weeks = weeks
        self.dropped = dropped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        lessons = try container.decodeIfPresent(
            [String: AliasTipLessonState].self,
            forKey: .lessons
        ) ?? [:]
        ineligible = try container.decodeIfPresent([String: Int].self, forKey: .ineligible) ?? [:]
        weeks = try container.decodeIfPresent(
            [String: [String: AliasTipWeekEntry]].self,
            forKey: .weeks
        ) ?? [:]
        dropped = try container.decodeIfPresent([String: Int].self, forKey: .dropped) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case lessons
        case ineligible
        case weeks
        case dropped
    }

    public static let empty = AliasTipLedger()

    public static func weekKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    public func isDue(id: String) -> Bool {
        lessons[id]?.isDue ?? true
    }

    public func isFluent(id: String) -> Bool {
        lessons[id]?.fluent ?? false
    }

    public mutating func recordMiss(
        id: String,
        shown: Bool,
        dropReason: AliasTipDropReason? = nil,
        date: Date
    ) {
        var lesson = lessons[id] ?? AliasTipLessonState()
        lesson.recordMiss(shown: shown)
        lessons[id] = lesson
        if !shown, let dropReason {
            dropped[dropReason.rawValue, default: 0] += 1
        }
        var entry = weeks[Self.weekKey(for: date)]?[id] ?? AliasTipWeekEntry()
        entry.misses += 1
        if shown {
            entry.shown += 1
        }
        storeWeekEntry(entry, id: id, date: date)
    }

    @discardableResult
    public mutating func recordHit(id: String, date: Date) -> AliasTipHitCredit {
        let weekKey = Self.weekKey(for: date)
        let credit = AliasTipHitCredit(lessonID: id, weekKey: weekKey)
        liveHitCredits.insert(credit.token)
        var lesson = lessons[id] ?? AliasTipLessonState()
        lesson.recordHit()
        lessons[id] = lesson
        var entry = weeks[weekKey]?[id] ?? AliasTipWeekEntry()
        entry.hits += 1
        storeWeekEntry(entry, id: id, date: date)
        return credit
    }

    public mutating func withdrawHit(_ credit: AliasTipHitCredit) {
        guard liveHitCredits.remove(credit.token) != nil else {
            return
        }
        withdrawHit(id: credit.lessonID, weekKey: credit.weekKey)
    }

    fileprivate mutating func withdrawHit(id: String, weekKey: String) {
        if var lesson = lessons[id] {
            lesson.withdrawHit()
            lessons[id] = lesson
        }

        guard var bucket = weeks[weekKey], var entry = bucket[id], entry.hits > 0 else {
            return
        }
        entry.hits -= 1
        if entry.hits == 0 && entry.misses == 0 && entry.shown == 0 {
            bucket.removeValue(forKey: id)
        } else {
            bucket[id] = entry
        }
        if bucket.isEmpty {
            weeks.removeValue(forKey: weekKey)
        } else {
            weeks[weekKey] = bucket
        }
    }

    public mutating func recordIneligible(sigil: String) {
        ineligible[sigil, default: 0] += 1
    }

    private mutating func storeWeekEntry(_ entry: AliasTipWeekEntry, id: String, date: Date) {
        let key = Self.weekKey(for: date)
        var bucket = weeks[key] ?? [:]
        bucket[id] = entry
        weeks[key] = bucket
        pruneWeeks()
    }

    private mutating func pruneWeeks() {
        guard weeks.count > AliasTipPolicy.maxWeeks else {
            return
        }
        let keep = Set(weeks.keys.sorted().suffix(AliasTipPolicy.maxWeeks))
        weeks = weeks.filter { keep.contains($0.key) }
    }
}

/// Reads and writes the ledger as a JSON string in UserDefaults, so
/// `defaults read` stays human-readable. A corrupt or unknown-version blob
/// resets to empty.
public struct AliasTipLedgerStore: @unchecked Sendable {
    public static let defaultsKey = "org.bobs.bob-mac-capture.typing-tips"

    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let hitCredits = AliasTipLedgerHitCreditRegistry()

    public init(
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.now = now
    }

    public func load() -> AliasTipLedger {
        guard let raw = defaults.string(forKey: Self.defaultsKey) else {
            return .empty
        }
        guard let data = raw.data(using: .utf8) else {
            return .empty
        }
        do {
            let ledger = try JSONDecoder().decode(AliasTipLedger.self, from: data)
            guard ledger.version == AliasTipLedger.currentVersion else {
                return .empty
            }
            return ledger
        } catch {
            return .empty
        }
    }

    public func save(_ ledger: AliasTipLedger) {
        do {
            let data = try JSONEncoder().encode(ledger)
            if let raw = String(data: data, encoding: .utf8) {
                defaults.set(raw, forKey: Self.defaultsKey)
            }
        } catch {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }

    public func reset() {
        defaults.removeObject(forKey: Self.defaultsKey)
        hitCredits.reset()
    }

    public func recordMiss(
        id: String,
        shown: Bool,
        dropReason: AliasTipDropReason? = nil
    ) {
        var ledger = load()
        ledger.recordMiss(id: id, shown: shown, dropReason: dropReason, date: now())
        save(ledger)
    }

    @discardableResult
    public func recordHit(id: String) -> AliasTipHitCredit {
        let date = now()
        var ledger = load()
        let credit = ledger.recordHit(id: id, date: date)
        save(ledger)
        hitCredits.register(credit)
        return credit
    }

    public func withdrawHit(_ credit: AliasTipHitCredit) {
        guard hitCredits.consume(credit) else {
            return
        }
        var ledger = load()
        ledger.withdrawHit(id: credit.lessonID, weekKey: credit.weekKey)
        save(ledger)
    }

    public func recordIneligible(sigil: String) {
        var ledger = load()
        ledger.recordIneligible(sigil: sigil)
        save(ledger)
    }

    public func isDue(id: String) -> Bool {
        load().isDue(id: id)
    }

    public func isFluent(id: String) -> Bool {
        load().isFluent(id: id)
    }
}

/// Process-local hit identities are bounded and never enter the ledger JSON.
private final class AliasTipLedgerHitCreditRegistry: @unchecked Sendable {
    private static let capacity = 256

    private let lock = NSLock()
    private var order: [UUID] = []
    private var active: Set<UUID> = []

    func register(_ credit: AliasTipHitCredit) {
        lock.lock()
        defer { lock.unlock() }
        order.append(credit.token)
        active.insert(credit.token)
        if order.count > Self.capacity {
            let expiredCount = order.count - Self.capacity
            let expired = Array(order.prefix(expiredCount))
            order.removeFirst(expiredCount)
            active.subtract(expired)
        }
    }

    func consume(_ credit: AliasTipHitCredit) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return active.remove(credit.token) != nil
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        order.removeAll()
        active.removeAll()
    }
}

/// The in-memory rules for one panel session: at most one tip per session,
/// and an escaped lesson stays silent for the rest of the session.
public struct AliasTipSession: Equatable, Sendable {
    public var didShowTip: Bool
    public var escapedLessons: Set<String>

    public init(didShowTip: Bool = false, escapedLessons: Set<String> = []) {
        self.didShowTip = didShowTip
        self.escapedLessons = escapedLessons
    }

    public func canShow(lessonId: String) -> Bool {
        !didShowTip && !escapedLessons.contains(lessonId)
    }

    public mutating func markShown() {
        didShowTip = true
    }

    public mutating func escape(lessonId: String) {
        escapedLessons.insert(lessonId)
    }
}
