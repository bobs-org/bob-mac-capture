import CaptureCore
import Foundation

struct CapturePullInChoiceRow: Equatable, Identifiable {
  let offerRow: TaskCompleteUnblocked?
  let blockedRow: TaskCompleteStillBlocked?
  let group: String
  let project: String?

  var id: String {
    if let key = offerRow?.offer?.key, !key.isEmpty {
      return "offer|\(key)"
    }
    if let blockedRow {
      return "blocked|\(blockedRow.notePath)|\(blockedRow.blockID)|\(blockedRow.line)"
    }
    let row = offerRow
    return "unkeyed|\(row?.notePath ?? "")|\(row?.blockID ?? "")|\(row?.line ?? 0)"
  }

  var offerKey: String? {
    guard let key = offerRow?.offer?.key, !key.isEmpty else {
      return nil
    }
    return key
  }

  var isSelectable: Bool {
    offerKey != nil
  }

  var offerNumber: Int? {
    offerRow?.offer?.n
  }

  var text: String {
    offerRow?.text ?? blockedRow?.text ?? ""
  }

  var notePath: String {
    offerRow?.notePath ?? blockedRow?.notePath ?? ""
  }

  var blockID: String {
    offerRow?.blockID ?? blockedRow?.blockID ?? ""
  }

  var statusText: String {
    guard let offerRow else {
      return blockedRow.map { "[\($0.statusSymbol)] \($0.statusName)" } ?? ""
    }
    return "[\(offerRow.previousStatusSymbol)] → [\(offerRow.statusSymbol)]"
  }

  var destinationText: String? {
    guard let destination = offerRow?.offer?.destination else {
      return nil
    }
    let name = destination.entryName.isEmpty ? destination.dayFile : destination.entryName
    guard !name.isEmpty else {
      return nil
    }
    let role = destination.entryRole.replacingOccurrences(of: "_", with: " ")
    var suffix = role.isEmpty ? "" : " · \(role)"
    if destination.fallback {
      suffix += " · fallback"
    }
    return "→ \(name)\(suffix)"
  }

  var needsBlockID: Bool {
    offerRow?.offer?.blockIDNeeded == true
  }

  /// Presentation-only meta fragments for offer rows. Unlike `detailText`,
  /// this never includes the recovered "Ready · not pulled in" caption.
  var metaDetails: [String] {
    guard let offerRow else {
      return []
    }
    var details: [String] = []
    if offerRow.hideRemoved {
      details.append("removed #hide")
    }
    if let trigger = offerRow.trigger, !trigger.isEmpty {
      if trigger == "project_empty" {
        if group != "project_finished" {
          details.append("project finished")
        }
      } else {
        details.append("trigger: \(trigger)")
      }
    }
    return details
  }

  var detailText: String? {
    if let offerRow {
      let presentation = SuccessorRows.unblockedRows(
        from: [offerRow],
        transition: { _ in "" },
        locator: { _ in "" }
      ).first
      var details = [presentation?.captionText].compactMap { $0 }
      if offerRow.hideRemoved {
        details.append("removed #hide")
      }
      if offerRow.trigger == "project_empty" {
        details.append("project finished")
      } else if let trigger = offerRow.trigger, !trigger.isEmpty {
        details.append("trigger: \(trigger)")
      }
      return details.isEmpty ? nil : details.joined(separator: " · ")
    }
    guard let blockedRow else {
      return nil
    }
    return SuccessorRows.stillBlockedRows(
      from: [blockedRow],
      locator: { _ in "" }
    ).first?.captionText
  }

  var accessibilityLabel: String {
    var parts = [text]
    if let offerNumber {
      parts.insert("Offer \(offerNumber)", at: 0)
    }
    if !notePath.isEmpty {
      parts.append(notePath + (blockID.isEmpty ? "" : " ^\(blockID)"))
    }
    if let destinationText {
      parts.append(destinationText)
    }
    if needsBlockID {
      parts.append("needs block ID")
    }
    if let detailText {
      parts.append(detailText)
    }
    if !isSelectable {
      parts.append("not selectable")
    }
    return parts.joined(separator: ", ")
  }
}

struct CapturePullInChoiceSection: Equatable, Identifiable {
  let group: String
  let project: String?
  let folded: CapturePullInFolded?
  let rows: [CapturePullInChoiceRow]

  var id: String {
    Self.key(group: group, project: project)
  }

  var title: String {
    switch group {
    case "hand_off":
      return "Hand-offs"
    case "project":
      return project.map { "Project \(Self.projectLabel($0))" } ?? "Project"
    case "project_finished":
      return "Project finished"
    default:
      return group.isEmpty ? "Successor offers" : group
    }
  }

  private static func projectLabel(_ path: String) -> String {
    URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
  }

  static func key(group: String, project: String?) -> String {
    "\(group)\u{1F}\(project ?? "")"
  }
}

/// Transient in-panel choice state. This stores only Bob-returned identities
/// and metadata, plus local focus/filter state. It has no vault or eligibility
/// logic.
struct CapturePullInChoiceState: Equatable {
  let draftSnapshot: String
  let processClientIdentity: String
  var openAfterCapture: Bool
  let priorityRollSeed: String
  let generation: UInt64
  let requestID: UUID?
  let pullIn: CapturePullIn
  let planBudget: CapturePlanBudget?
  var rows: [CapturePullInChoiceRow]
  var highlightedKey: String?
  var markedKeys: Set<String> = []
  var filterText = ""
  var collapsedGroups: Set<String> = []
  var errorMessage: String?

  var selectableKeys: [String] {
    rows.compactMap(\.offerKey).sorted { lhs, rhs in
      let left = rows.first(where: { $0.offerKey == lhs })?.offerNumber ?? Int.max
      let right = rows.first(where: { $0.offerKey == rhs })?.offerNumber ?? Int.max
      if left == right {
        return lhs < rhs
      }
      return left < right
    }
  }

  var effectiveSelectionKeys: [String] {
    let validMarked = markedKeys.intersection(Set(selectableKeys))
    if !validMarked.isEmpty {
      return selectableKeys.filter(validMarked.contains)
    }
    guard let highlightedKey,
      visibleSelectableKeys.contains(highlightedKey)
    else {
      return []
    }
    return [highlightedKey]
  }

  var visibleSelectableKeys: [String] {
    sections.flatMap { section in
      visibleRows(in: section).compactMap(\.offerKey)
    }
  }

  var effectivePickCount: Int {
    effectiveSelectionKeys.count
  }

  var projectedLinkCount: Int? {
    guard let planBudget else {
      return nil
    }
    return planBudget.links.count + effectivePickCount
  }

  var projectedLinksOverCap: Bool {
    guard let planBudget, let projectedLinkCount else {
      return false
    }
    return projectedLinkCount > planBudget.links.cap
  }

  var projectedLinksText: String? {
    guard let planBudget, let projectedLinkCount else {
      return nil
    }
    return "Projected links \(projectedLinkCount)/\(planBudget.links.cap)"
  }

  /// Distinct `unblockedBy` causes across offer rows, in first-seen order.
  var causes: [TaskCompleteUnblockedCause] {
    var seen = Set<String>()
    var ordered: [TaskCompleteUnblockedCause] = []
    for row in rows {
      guard let offerRow = row.offerRow else {
        continue
      }
      for cause in offerRow.unblockedBy {
        let key = "\(cause.notePath)\u{1F}\(cause.blockID)"
        guard seen.insert(key).inserted else {
          continue
        }
        ordered.append(cause)
      }
    }
    return ordered
  }

  /// "Unblocked by X" / "Unblocked by X and N more" / nil.
  var contextText: String? {
    let all = causes
    guard let first = all.first, !first.text.isEmpty else {
      return nil
    }
    let head = SuccessorRows.truncate(first.text)
    guard all.count > 1 else {
      return "Unblocked by \(head)"
    }
    return "Unblocked by \(head) and \(all.count - 1) more"
  }

  /// True when rows should show their own "from ‹cause›" suffix.
  var showsRowCauses: Bool {
    causes.count > 1
  }

  /// "3 offers" / "1 offer" / "1 of 3" while filtering.
  var countText: String {
    let total = selectableKeys.count
    if !filterText.isEmpty {
      return "\(visibleSelectableKeys.count) of \(total)"
    }
    return total == 1 ? "1 offer" : "\(total) offers"
  }

  func isEffectivelySelected(_ key: String) -> Bool {
    effectiveSelectionKeys.contains(key)
  }

  /// Valid marks inside one section (stale keys never count).
  func markedCount(in section: CapturePullInChoiceSection) -> Int {
    let valid = markedKeys.intersection(Set(selectableKeys))
    guard !valid.isEmpty else {
      return 0
    }
    return section.rows.compactMap(\.offerKey).filter(valid.contains).count
  }

  /// "Pull In N" / "Pull In" when nothing would be picked.
  var pullInActionTitle: String {
    effectivePickCount == 0 ? "Pull In" : "Pull In \(effectivePickCount)"
  }

  /// "Links 6/10" when Bob supplied the budget.
  var projectedLinksCapsuleText: String? {
    guard let planBudget, let projectedLinkCount else {
      return nil
    }
    return "Links \(projectedLinkCount)/\(planBudget.links.cap)"
  }

  /// "+N" when the budget is present and something would be picked.
  var projectedLinksDeltaText: String? {
    guard planBudget != nil, effectivePickCount > 0 else {
      return nil
    }
    return "+\(effectivePickCount)"
  }

  /// Character offsets of the first case-insensitive filter match in
  /// `text`, or nil when the filter is empty or absent.
  func filterMatchRange(in text: String) -> Range<Int>? {
    guard !filterText.isEmpty else {
      return nil
    }
    guard let range = text.range(of: filterText, options: [.caseInsensitive]) else {
      return nil
    }
    let lower = text.distance(from: text.startIndex, to: range.lowerBound)
    let upper = text.distance(from: text.startIndex, to: range.upperBound)
    return lower..<upper
  }

  var sections: [CapturePullInChoiceSection] {
    let keys = Set(
      rows.map { CapturePullInChoiceSection.key(group: $0.group, project: $0.project) }
    )
    .union(
      pullIn.groups.map {
        CapturePullInChoiceSection.key(group: $0.group, project: $0.project)
      })
    return keys.compactMap { key in
      let parts = key.components(separatedBy: "\u{1F}")
      guard let group = parts.first else {
        return nil
      }
      let project = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
      let sectionRows = rows.filter {
        $0.group == group && $0.project == project
      }.sorted { left, right in
        switch (left.offerNumber, right.offerNumber) {
        case let (a?, b?):
          return a == b ? left.id < right.id : a < b
        case (_?, nil):
          return true
        case (nil, _?):
          return false
        case (nil, nil):
          return left.id < right.id
        }
      }
      let folded = pullIn.groups.first {
        $0.group == group && $0.project == (project ?? "")
      }?.folded
      return CapturePullInChoiceSection(
        group: group,
        project: project,
        folded: folded,
        rows: sectionRows
      )
    }.sorted { left, right in
      let rank: [String: Int] = ["hand_off": 0, "project": 1, "project_finished": 2]
      let l = rank[left.group] ?? 3
      let r = rank[right.group] ?? 3
      if l != r {
        return l < r
      }
      let ln = left.rows.compactMap(\.offerNumber).min() ?? Int.max
      let rn = right.rows.compactMap(\.offerNumber).min() ?? Int.max
      if ln != rn {
        return ln < rn
      }
      return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
  }

  func visibleRows(in section: CapturePullInChoiceSection) -> [CapturePullInChoiceRow] {
    guard !collapsedGroups.contains(section.id) || !filterText.isEmpty else {
      return []
    }
    guard !filterText.isEmpty else {
      return section.rows
    }
    let query = filterText.localizedLowercase
    let headerMatches = section.title.localizedLowercase.contains(query)
    return section.rows.filter { row in
      headerMatches
        || [row.text, row.notePath, row.blockID, row.destinationText ?? "", row.detailText ?? ""]
          .contains { $0.localizedLowercase.contains(query) }
    }
  }

  mutating func moveHighlight(by delta: Int) {
    let keys = visibleSelectableKeys
    guard !keys.isEmpty else {
      highlightedKey = nil
      return
    }
    guard let current = highlightedKey, let index = keys.firstIndex(of: current) else {
      highlightedKey = delta < 0 ? keys.last : keys.first
      return
    }
    highlightedKey = keys[min(max(index + delta, 0), keys.count - 1)]
  }

  mutating func toggleHighlighted() {
    guard let highlightedKey, visibleSelectableKeys.contains(highlightedKey) else {
      return
    }
    if markedKeys.contains(highlightedKey) {
      markedKeys.remove(highlightedKey)
    } else {
      markedKeys.insert(highlightedKey)
    }
  }

  mutating func markAll() {
    markedKeys = Set(selectableKeys)
  }

  mutating func updateFilter(_ text: String) {
    filterText = text
    if let highlightedKey, visibleSelectableKeys.contains(highlightedKey) {
      return
    }
    highlightedKey = visibleSelectableKeys.first
  }

  mutating func toggleGroup(_ id: String) {
    if collapsedGroups.contains(id) {
      collapsedGroups.remove(id)
    } else {
      collapsedGroups.insert(id)
    }
  }
}
