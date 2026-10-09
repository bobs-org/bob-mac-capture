import Foundation
import RefsCore

/// `refs-rank`: rank a `bob ref list` snapshot with the RefsCore ranker
/// for tuning against live output. Reads the list envelope on stdin;
/// never bundled (Scripts/bundle.sh copies only BobMacCapture).
///
/// Usage:
///   swift run refs-rank [--plan plan.json] [--opens open-log.json]
///     [--scope chats] [--now 2026-10-08T09:00:00] [query...] < ref-list.json
///
/// Browse mode prints sections; search mode prints ranked rows as
/// `rank  tier  score (m P W L F R)  state  kind  title`, each followed
/// by its why-here line.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("refs-rank: \(message)\n".utf8))
    exit(1)
}

var planPath: String?
var opensPath: String?
var scopeName = "all"
var nowOverride: String?
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
    default:
        if argument.hasPrefix("--") {
            fail("unknown flag \(argument)")
        }
        queryWords.append(argument)
    }
    arguments = arguments.dropFirst()
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
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    guard let date = iso.date(from: raw) else {
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
calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

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
            "\(rank + 1)  \(match.tier)  \(score)  \(stateName(item))  "
                + "\(item.kind.label)  \(item.title.text)"
        )
        print("    \(RefsExplanation.whyHere(item, listing: listing, signals: signals))")
    }
}
