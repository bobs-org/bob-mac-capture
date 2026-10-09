import Foundation
import RefsCore

/// `refs-rank`: rank a `bob ref list` snapshot with the RefsCore ranker
/// for tuning against live output. Reads the list envelope on stdin;
/// never bundled (Scripts/bundle.sh copies only BobMacCapture).
///
/// Usage:
///   swift run refs-rank [--plan plan.json] [--opens open-log.json]
///     [--scope chats] [--now 2026-10-08T09:00:00] [--tz America/New_York]
///     [query...] < ref-list.json
///
/// `--now` accepts a full ISO 8601 time with an offset
/// (`2026-10-08T09:00:00-04:00`, `2026-10-08T13:00:00Z`) or a local
/// date-time without one (`2026-10-08T09:00:00`), interpreted in
/// `--tz` (default: the current time zone). That time zone's calendar
/// ranks the snapshot, so local-day sections match the panel.
///
/// Browse mode prints sections; search mode prints ranked rows as
/// `rank  tier  score (m P W L F R)  state  kind  title`, each followed
/// by its why-here line. Columns are padded so rows align: rank width
/// 4, tier width 9, state width 8, kind width 7.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("refs-rank: \(message)\n".utf8))
    exit(1)
}

var planPath: String?
var opensPath: String?
var scopeName = "all"
var nowOverride: String?
var tzName: String?
var queryWords: [String] = []

var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.first {
    switch argument {
    case "--plan":
        arguments = arguments.dropFirst()
        planPath = arguments.first
    case "--opens":
        arguments = arguments.dropFirst()
        opensPath = arguments.first
    case "--scope":
        arguments = arguments.dropFirst()
        scopeName = arguments.first ?? "all"
    case "--now":
        arguments = arguments.dropFirst()
        nowOverride = arguments.first
    case "--tz":
        arguments = arguments.dropFirst()
        tzName = arguments.first
    default:
        if argument.hasPrefix("--") {
            fail("unknown flag \(argument)")
        }
        queryWords.append(argument)
    }
    arguments = arguments.dropFirst()
}

let timeZone: TimeZone = {
    guard let tzName else {
        return TimeZone.current
    }
    guard let zone = TimeZone(identifier: tzName) else {
        fail("unknown time zone \(tzName)")
    }
    return zone
}()

func parseNow(_ raw: String, in zone: TimeZone) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: raw) {
        return date
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    for format in [
        "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd",
    ] {
        formatter.dateFormat = format
        if let date = formatter.date(from: raw) {
            return date
        }
    }
    return nil
}

let scope: RefScope = {
    switch scopeName.lowercased() {
    case "all":
        return .all
    case "chats":
        return .chats
    case "papers":
        return .papers
    case "articles":
        return .articles
    case "docs":
        return .docs
    default:
        fail("unknown scope \(scopeName)")
    }
}()

let now: Date = {
    guard let raw = nowOverride else {
        return Date()
    }
    guard let date = parseNow(raw, in: timeZone) else {
        fail("cannot parse --now \(raw)")
    }
    return date
}()

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
guard !stdinData.isEmpty else {
    fail("empty stdin: pipe `bob ref list -R all -A -f json` into refs-rank")
}
let listResponse: RefsListResponse = {
    do {
        return try JSONDecoder().decode(RefsListResponse.self, from: stdinData)
    } catch {
        fail("cannot decode ref list: \(error)")
    }
}()

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = timeZone

var today = RefsToday()
if let planPath {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: planPath))
        let plan = try JSONDecoder().decode(RefsPlanResponse.self, from: data)
        today = RefsToday(plan: plan)
    } catch {
        fail("cannot decode plan \(planPath): \(error)")
    }
}

var opens = RefsOpenStats(events: [], now: now)
if let opensPath {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: opensPath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let log = try decoder.decode(RefsOpenLogFile.self, from: data)
        opens = RefsOpenStats(events: log.opens, now: now)
    } catch {
        fail("cannot decode open log \(opensPath): \(error)")
    }
}

let signals = RefsSignals(
    today: today,
    opens: opens,
    now: now,
    calendar: calendar
)
let snapshot = RefsSnapshot(fetchedAt: now, records: listResponse.refs)
let items = RefsCatalog.items(from: snapshot)
let query = queryWords.joined(separator: " ")
let listing = RefsRanker.listing(items, query: query, scope: scope, signals: signals)
let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

func padRight(_ text: String, _ width: Int) -> String {
    text.count >= width
        ? text : text + String(repeating: " ", count: width - text.count)
}

func padLeft(_ text: String, _ width: Int) -> String {
    text.count >= width
        ? text : String(repeating: " ", count: width - text.count) + text
}

func stateName(_ item: RefItem) -> String {
    switch item.state {
    case .reading:
        return "reading"
    case .next:
        return "next"
    case .ready:
        return "ready"
    case .read:
        return "read"
    case .dropped:
        return "dropped"
    case .unknown:
        return "unknown"
    }
}

switch listing.mode {
case .browse:
    print("\(listing.openCount) open · \(listing.totalCount) total")
    for section in listing.sections {
        print("## \(section.kind?.title ?? "Results") (\(section.ids.count))")
        for id in section.ids {
            guard let item = byID[id] else {
                continue
            }
            print("  \(item.title.text)")
            print("    \(RefsCaption.caption(for: item, in: section.kind, signals: signals))")
            print(
            "    \(RefsExplanation.whyHere(item, listing: listing, signals: signals))"
        )
        }
    }
case .search:
    print("rank  tier  score (m P W L F R)  state  kind  title")
    for (rank, id) in listing.orderedIDs.enumerated() {
        guard let item = byID[id], let match = listing.matches[id] else {
            continue
        }
        let breakdown = match.breakdown
        let score = String(
            format: "%.3f (%5.3f %5.3f %5.3f %5.3f %5.3f %5.3f)",
            match.score, breakdown.m, breakdown.p, breakdown.w,
            breakdown.l, breakdown.f, breakdown.r
        )
        print(
            "\(padLeft(String(rank + 1), 4))  \(padRight("\(match.tier)", 9))  "
                + "\(score)  \(padRight(stateName(item), 8))  "
                + "\(padRight(item.kind.label, 7))  \(item.title.text)"
        )
        print("    \(RefsExplanation.whyHere(item, listing: listing, signals: signals))")
    }
}
