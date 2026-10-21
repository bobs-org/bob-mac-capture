import Foundation

/// Fixed band geometry. Heights come from the visual spec so fold-before-scroll
/// can be computed without measuring the SwiftUI tree (which would oscillate).
public enum SimilarTasksBandMetrics {
  public static let hairlineSpacing: Double = 8
  public static let hairlineHeight: Double = 0.5
  public static let headerHeight: Double = 16
  public static let rowHeight: Double = 22
  public static let foldedHeight: Double = 22
  public static let crossFadeSeconds: Double = 0.12

  public static func fullHeight(item: SimilarTasksBandItem) -> Double {
    guard item.isVisible else { return 0 }
    let header = item.showsHeader ? headerHeight : 0
    return hairlineSpacing + hairlineHeight + header
      + rowHeight * Double(item.rows.count)
  }

  public static func currentHeight(item: SimilarTasksBandItem, folded: Bool) -> Double {
    guard item.isVisible else { return 0 }
    if folded {
      return hairlineSpacing + hairlineHeight + foldedHeight
    }
    return fullHeight(item: item)
  }

  public static func fullHeight<S: Sequence>(items: S) -> Double
  where S.Element == SimilarTasksBandItem {
    items.reduce(0) { $0 + fullHeight(item: $1) }
  }

  public static func currentHeight<S: Sequence>(items: S, folded: Bool) -> Double
  where S.Element == SimilarTasksBandItem {
    items.reduce(0) { $0 + currentHeight(item: $1, folded: folded) }
  }

  /// Fold every band when painting them at full height would make the
  /// auxiliary region taller than the screen budget. `measuredAuxiliaryHeight`
  /// is the currently rendered auxiliary (including today's band heights);
  /// the comparison always uses the full-height ideal so folding cannot
  /// oscillate.
  public static func shouldFold(
    items: [SimilarTasksBandItem],
    currentlyFolded: Bool,
    measuredAuxiliaryHeight: Double,
    availableAuxiliaryHeight: Double
  ) -> Bool {
    let visible = items.filter(\.isVisible)
    guard !visible.isEmpty else { return false }
    guard measuredAuxiliaryHeight.isFinite, measuredAuxiliaryHeight > 1,
          availableAuxiliaryHeight.isFinite
    else {
      return currentlyFolded
    }
    let full = fullHeight(items: visible)
    let current = currentHeight(items: visible, folded: currentlyFolded)
    let idealFull = measuredAuxiliaryHeight - current + full
    return idealFull > availableAuxiliaryHeight
  }
}

/// Copy, capsules, matched-title runs, and VoiceOver strings for the band.
/// The SwiftUI layer paints these; it never invents labels of its own.
public enum SimilarTasksBandPresentation {
  public struct TitleRun: Equatable, Sendable {
    public let text: String
    public let emphasized: Bool
  }

  public static func capsuleLabel(for row: SimilarTasksBandRow) -> String? {
    if let link = row.linkedBy {
      switch link {
      case .relation:
        return "Related"
      case .dependency:
        return "Prerequisite"
      case .blockedTask:
        return "Blocked by this"
      case .parent, .unknown:
        break
      }
    }
    if let closed = row.match.closed {
      let verb = closed.status == "canceled" ? "Canceled" : "Done"
      return "\(verb) \(closed.daysAgo)d ago"
    }
    switch row.match.band {
    case .sameTitle:
      return "Same title"
    case .possibleDuplicate:
      return "Possible duplicate"
    case .similar, .closedDuplicate, .hold, .unknown:
      return nil
    }
  }

  public static func overflowCapsule(count: Int) -> String? {
    count > 0 ? "+\(count)" : nil
  }

  public static func commandHint(rows: [SimilarTasksBandRow]) -> String {
    guard let first = rows.first?.rowNumber else { return "" }
    let last = rows.last?.rowNumber ?? first
    if first == last {
      return "⌘\(first)"
    }
    return "⌘\(first)–\(last)"
  }

  public static func locatorText(for row: SimilarTasksBandRow) -> String {
    let place = row.match.locator.isEmpty ? row.match.route : row.match.locator
    if row.match.closed != nil {
      return place
    }
    if row.match.statusName.isEmpty {
      return place
    }
    if place.isEmpty {
      return row.match.statusName
    }
    return "\(place) · \(row.match.statusName)"
  }

  public static func kindSymbolName(_ kind: String) -> String? {
    switch kind {
    case "project":
      return "folder"
    case "reading":
      return "book"
    default:
      return nil
    }
  }

  public static func kindAccessibilityLabel(_ kind: String) -> String? {
    switch kind {
    case "project":
      return "Project task"
    case "reading":
      return "Reading task"
    default:
      return nil
    }
  }

  public static func closedStatusName(_ closed: CaptureRelatedClosed) -> String {
    closed.status == "canceled" ? "Canceled" : "Done"
  }

  public static func rowAccessibilityLabel(_ row: SimilarTasksBandRow) -> String {
    var parts = [row.match.title]
    if let capsule = capsuleLabel(for: row) {
      parts.append(capsule)
    }
    let route = row.match.route.isEmpty ? row.match.locator : row.match.route
    if !route.isEmpty {
      parts.append(route)
    }
    if let closed = row.match.closed {
      parts.append(closedStatusName(closed))
    } else if !row.match.statusName.isEmpty {
      parts.append(row.match.statusName)
    }
    if let kind = kindAccessibilityLabel(row.match.kind) {
      parts.append(kind)
    }
    return parts.joined(separator: ", ")
  }

  public static func foldedLine(item: SimilarTasksBandItem) -> String {
    let count = item.rows.count + item.overflowCount
    let noun = count == 1 ? "similar task" : "similar tasks"
    let hint = commandHint(rows: item.rows)
    guard let row = item.rows.first else {
      return "⧉ \(count) \(noun)"
    }
    let title = row.match.title
    if let capsule = capsuleLabel(for: row) {
      return "⧉ \(count) \(noun) · \(capsule): \(title)   \(hint)"
    }
    return "⧉ \(count) \(noun) · \(title)   \(hint)"
  }

  public static func foldedAccessibilityLabel(item: SimilarTasksBandItem) -> String {
    let count = item.rows.count + item.overflowCount
    let noun = count == 1 ? "similar task" : "similar tasks"
    guard let row = item.rows.first else {
      return "\(count) \(noun)"
    }
    if let capsule = capsuleLabel(for: row) {
      return "\(count) \(noun), \(capsule), \(row.match.title)"
    }
    return "\(count) \(noun), \(row.match.title)"
  }

  public static func rowHelp(_ row: SimilarTasksBandRow) -> String {
    let path = row.match.notePath
    if path.isEmpty {
      return row.match.title
    }
    return "\(row.match.title)\n\(path)"
  }

  public static func identityKeys(items: [SimilarTasksBandItem]) -> [String] {
    items.flatMap { $0.rows.map(\.match.key) }
  }

  public static func settledAnnouncement(items: [SimilarTasksBandItem]) -> String? {
    let rows = items.flatMap(\.rows)
    guard !rows.isEmpty else { return nil }
    if rows.count == 1, let row = rows.first {
      return "Similar task: \(row.match.title)"
    }
    return "\(rows.count) similar tasks"
  }

  /// Splits `title` into contiguous emphasized / plain runs from Bob's
  /// UTF-8 `matched_ranges`. Invalid ranges are skipped.
  public static func titleRuns(
    title: String,
    ranges: [CaptureRange]
  ) -> [TitleRun] {
    let valid = ranges.compactMap { range -> Range<String.Index>? in
      stringRange(in: title, byteRange: range)
    }.sorted { $0.lowerBound < $1.lowerBound }

    guard !valid.isEmpty else {
      return title.isEmpty ? [] : [TitleRun(text: title, emphasized: false)]
    }

    var runs: [TitleRun] = []
    var cursor = title.startIndex
    for range in valid {
      let start = range.lowerBound < cursor ? cursor : range.lowerBound
      if cursor < start {
        runs.append(TitleRun(text: String(title[cursor..<start]), emphasized: false))
      }
      if start < range.upperBound {
        runs.append(TitleRun(text: String(title[start..<range.upperBound]), emphasized: true))
        cursor = range.upperBound
      }
    }
    if cursor < title.endIndex {
      runs.append(TitleRun(text: String(title[cursor...]), emphasized: false))
    }
    return runs.filter { !$0.text.isEmpty }
  }
}
