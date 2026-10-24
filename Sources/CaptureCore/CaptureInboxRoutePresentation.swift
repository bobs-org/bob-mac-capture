import Foundation

/// One deliberate route answer, keyed by Bob's opaque candidate identity.
/// `.keep` leaves the task in its inbox; `.move` files it under the given
/// vault-relative destination. Keys stay opaque.
public enum CaptureInboxRouteDecision: Equatable, Sendable {
  case keep
  case move(destination: String)
}

/// Pure route-choice state for the inbox-route card, plus its presentation
/// helpers. It holds Bob-returned candidates and destinations, the cursor,
/// answers by key, filter text with fuzzy filtering, and the refusal message.
/// It has no vault or eligibility logic: Bob owns the destination set.
public struct CaptureInboxRouteChoiceState: Equatable, Sendable {
  public var candidates: [CaptureInboxRouteCandidate]
  public var destinations: [CaptureInboxRouteDestination]
  /// Index into `candidates` of the card's current candidate.
  public var cursor: Int
  /// Answers by opaque candidate key.
  public var answers: [String: CaptureInboxRouteDecision]
  public var filterText: String
  /// Opaque key of the highlighted destination row, or nil for the first row.
  public var highlightedDestination: String?
  /// Refusal message from `inbox_route_refused`, shown in place of the
  /// context line, plus the refused candidate key.
  public var refusalMessage: String?
  public var refusedKey: String?

  public init(
    candidates: [CaptureInboxRouteCandidate] = [],
    destinations: [CaptureInboxRouteDestination] = [],
    cursor: Int = 0,
    answers: [String: CaptureInboxRouteDecision] = [:],
    filterText: String = "",
    highlightedDestination: String? = nil,
    refusalMessage: String? = nil,
    refusedKey: String? = nil
  ) {
    self.candidates = candidates
    self.destinations = destinations
    self.cursor = min(max(cursor, 0), max(candidates.count - 1, 0))
    self.answers = answers
    self.filterText = filterText
    self.highlightedDestination = highlightedDestination
    self.refusalMessage = refusalMessage
    self.refusedKey = refusedKey
  }

  /// The candidate the card currently shows, or nil when there are none.
  public var currentCandidate: CaptureInboxRouteCandidate? {
    guard !candidates.isEmpty, cursor >= 0, cursor < candidates.count else {
      return nil
    }
    return candidates[cursor]
  }

  public var hasCandidates: Bool {
    !candidates.isEmpty
  }

  /// Destinations matching `filterText`, in Bob's order. An empty filter
  /// returns every destination.
  public var filteredDestinations: [CaptureInboxRouteDestination] {
    let query = FuzzyQuery(filterText, leadingSigil: "")
    if query.isEmpty {
      return destinations
    }

    let scored: [(CaptureInboxRouteDestination, Int)] = destinations.compactMap {
      destination in
      guard
        let score = Self.matchScore(tokens: query.tokens, destination: destination)
      else {
        return nil
      }
      return (destination, score)
    }
    return
      scored
      .sorted { lhs, rhs in
        if lhs.1 != rhs.1 {
          return lhs.1 > rhs.1
        }
        return destinations.firstIndex(where: { $0.relativePath == lhs.0.relativePath })
          ?? 0
          < destinations.firstIndex(where: { $0.relativePath == rhs.0.relativePath }) ?? 0
      }
      .map(\.0)
  }

  /// The highlighted row in `filteredDestinations`, resolving the
  /// initial-highlight rule: the stored highlight when it survives filtering,
  /// else the first row.
  public var highlightedRow: CaptureInboxRouteDestination? {
    let filtered = filteredDestinations
    if let highlightedDestination,
      filtered.contains(where: { $0.relativePath == highlightedDestination })
    {
      return filtered.first(where: { $0.relativePath == highlightedDestination })
    }
    return filtered.first
  }

  /// Applies the initial-highlight rule for the current candidate: the
  /// destination answered for the previous candidate in this card, otherwise
  /// `lastUsedDestination`, otherwise the first filtered row. Callers pass
  /// the previous answer's destination (or nil) and the per-vault last-used
  /// destination.
  public mutating func applyInitialHighlight(
    previousAnswerDestination: String?,
    lastUsedDestination: String?
  ) {
    if let previousAnswerDestination,
      filteredDestinations.contains(where: { $0.relativePath == previousAnswerDestination })
    {
      highlightedDestination = previousAnswerDestination
      return
    }
    if let lastUsedDestination,
      filteredDestinations.contains(where: { $0.relativePath == lastUsedDestination })
    {
      highlightedDestination = lastUsedDestination
      return
    }
    highlightedDestination = filteredDestinations.first?.relativePath
  }

  public mutating func moveHighlightForward() {
    let filtered = filteredDestinations
    guard !filtered.isEmpty else {
      highlightedDestination = nil
      return
    }
    if let current = highlightedDestination,
      let index = filtered.firstIndex(where: { $0.relativePath == current })
    {
      highlightedDestination = filtered[(index + 1) % filtered.count].relativePath
    } else {
      highlightedDestination = filtered.first?.relativePath
    }
  }

  public mutating func moveHighlightBackward() {
    let filtered = filteredDestinations
    guard !filtered.isEmpty else {
      highlightedDestination = nil
      return
    }
    if let current = highlightedDestination,
      let index = filtered.firstIndex(where: { $0.relativePath == current })
    {
      highlightedDestination = filtered[(index - 1 + filtered.count) % filtered.count].relativePath
    } else {
      highlightedDestination = filtered.last?.relativePath
    }
  }

  /// Records a move answer for the current candidate and advances. Returns
  /// true when more candidates remain.
  @discardableResult
  public mutating func answerMoveCurrent(destination: String) -> Bool {
    guard let candidate = currentCandidate else {
      return false
    }
    answers[candidate.key] = .move(destination: destination)
    refusalMessage = nil
    refusedKey = nil
    return goForward()
  }

  /// Records a keep answer for the current candidate and advances. Returns
  /// true when more candidates remain.
  @discardableResult
  public mutating func answerKeepCurrent() -> Bool {
    guard let candidate = currentCandidate else {
      return false
    }
    answers[candidate.key] = .keep
    refusalMessage = nil
    refusedKey = nil
    return goForward()
  }

  /// Goes back one candidate. Returns false when already on the first.
  @discardableResult
  public mutating func goBack() -> Bool {
    guard cursor > 0 else {
      return false
    }
    cursor -= 1
    filterText = ""
    refusalMessage = nil
    refusedKey = nil
    return true
  }

  /// Goes forward one candidate. Returns false when already on the last.
  @discardableResult
  public mutating func goForward() -> Bool {
    guard cursor + 1 < candidates.count else {
      return false
    }
    cursor += 1
    filterText = ""
    refusalMessage = nil
    refusedKey = nil
    return true
  }

  /// Reopens the card on the refused candidate, keeping every other answer
  /// and showing the refusal message in place of the context line.
  public mutating func reopenAtRefusedKey(_ key: String, message: String) {
    if let index = candidates.firstIndex(where: { $0.key == key }) {
      cursor = index
    }
    refusedKey = key
    refusalMessage = message
    let answered = answers[key]
    if case .move(let destination) = answered {
      highlightedDestination = destination
    }
  }

  /// Re-seeds the state from a new candidate set, keeping answers for keys
  /// that are still present and clamping the cursor.
  public mutating func reseed(
    candidates newCandidates: [CaptureInboxRouteCandidate],
    destinations newDestinations: [CaptureInboxRouteDestination]
  ) {
    candidates = newCandidates
    destinations = newDestinations
    let surviving = Set(newCandidates.map(\.key))
    answers = answers.filter { surviving.contains($0.key) }
    if cursor >= newCandidates.count {
      cursor = max(newCandidates.count - 1, 0)
    }
    if let refusedKey, !surviving.contains(refusedKey) {
      self.refusedKey = nil
      refusalMessage = nil
    }
    if let highlightedDestination,
      !newDestinations.contains(where: { $0.relativePath == highlightedDestination })
    {
      self.highlightedDestination = nil
    }
  }

  /// Answers for submit: one `--inbox-route` element per candidate, in card
  /// order. Unanswered candidates are callers' responsibility; this returns
  /// only recorded answers.
  public var answersForSubmit: [CaptureInboxRouteSubmission] {
    candidates.compactMap { candidate in
      guard let decision = answers[candidate.key] else {
        return nil
      }
      switch decision {
      case .keep:
        return CaptureInboxRouteSubmission(key: candidate.key, destination: nil)
      case .move(let destination):
        return CaptureInboxRouteSubmission(key: candidate.key, destination: destination)
      }
    }
  }

  /// True when every candidate has an answer.
  public var isComplete: Bool {
    !candidates.isEmpty && candidates.allSatisfy { answers[$0.key] != nil }
  }

  private static func matchScore(
    tokens: [String],
    destination: CaptureInboxRouteDestination
  ) -> Int? {
    let fields = [
      FuzzyField(destination.label),
      FuzzyField(destination.route),
      FuzzyField(destination.relativePath),
    ]
    var total = 0
    for token in tokens {
      var best: Int?
      for field in fields {
        if let match = FuzzyMatcher.match(token: token, in: field) {
          if best == nil || match.score > best! {
            best = match.score
          }
        }
      }
      guard let tokenBest = best else {
        return nil
      }
      total += tokenBest
    }
    return total
  }
}

// MARK: - Presentation helpers

public enum CaptureInboxRoutePresentation {
  /// `"<text> · <previous_status_name> → <status_name>"`, plus
  /// `"Task k of M"` when there are several candidates. After
  /// `inbox_route_refused` the refusal message replaces the line.
  public static func contextLine(
    candidate: CaptureInboxRouteCandidate,
    index: Int,
    total: Int,
    refusalMessage: String? = nil
  ) -> String {
    if let refusalMessage, !refusalMessage.isEmpty {
      return refusalMessage
    }
    var line = "\(candidate.text) · \(candidate.previousStatusName) → \(candidate.statusName)"
    if total > 1 {
      line += " · Task \(index + 1) of \(total)"
    }
    return line
  }

  /// One destination row: `"label"`, with `"relative_path · parent"` as
  /// secondary text, plus `"wip"`/`"waiting"` and `"Blocked"` badges.
  public static func rowText(destination: CaptureInboxRouteDestination) -> String {
    destination.label
  }

  public static func rowDetail(destination: CaptureInboxRouteDestination) -> String {
    var detail = destination.relativePath
    if let parent = destination.parent, !parent.isEmpty {
      detail += " · \(parent)"
    }
    var badges: [String] = []
    if destination.status == "wip" || destination.status == "waiting" {
      badges.append(destination.status ?? "")
    }
    if destination.blocked {
      badges.append("Blocked")
    }
    if !badges.isEmpty {
      detail += " · \(badges.joined(separator: " · "))"
    }
    return detail
  }

  /// Preview summary under the matching live preview, in the style of the
  /// pull-in summary row: one candidate shows
  /// `"Inbox · <text> · Ready → Next · ↩ choose where it goes"`, several
  /// show `"<N> inbox tasks · ↩ choose where they go"`.
  public static func previewSummary(candidates: [CaptureInboxRouteCandidate]) -> String? {
    guard !candidates.isEmpty else {
      return nil
    }
    if candidates.count == 1, let candidate = candidates.first {
      return
        "Inbox · \(candidate.text) · \(candidate.previousStatusName) → \(candidate.statusName) · ↩ choose where it goes"
    }
    return "\(candidates.count) inbox tasks · ↩ choose where they go"
  }

  /// Success-notice suffix built from `inbox_route`: `"· moved to <label>"`
  /// for one routed task, `"· <N> tasks routed"` for several,
  /// `"· kept in <inbox>"` when everything was kept, or nil when nothing
  /// was answered.
  public static func successNoticeSuffix(route: CaptureInboxRoute?) -> String? {
    guard let route, !route.candidates.isEmpty else {
      return nil
    }
    let moved = route.candidates.filter { $0.outcome == "moved" }
    let kept = route.candidates.filter { $0.outcome == "kept" }
    if moved.count == 1, kept.isEmpty, route.candidates.count == 1 {
      let label = movedLabel(for: moved[0], destinations: route.destinations ?? [])
      return "· moved to \(label)"
    }
    if !moved.isEmpty {
      return "· \(moved.count) task\(moved.count == 1 ? "" : "s") routed"
    }
    if !kept.isEmpty, moved.isEmpty {
      let inboxes = Set(kept.map(\.inbox)).sorted()
      if inboxes.count == 1, let inbox = inboxes.first {
        return "· kept in \(inbox)"
      }
      return "· kept in inbox"
    }
    return nil
  }

  private static func movedLabel(
    for candidate: CaptureInboxRouteCandidate,
    destinations: [CaptureInboxRouteDestination]
  ) -> String {
    if let destination = candidate.moved?.destination, !destination.isEmpty {
      let stem = URL(fileURLWithPath: destination).deletingPathExtension().lastPathComponent
      if !stem.isEmpty {
        return stem
      }
    }
    if let answerDestination = candidate.answer?.destination, !answerDestination.isEmpty {
      if let match = destinations.first(where: { $0.relativePath == answerDestination }) {
        return match.label
      }
      let stem = URL(fileURLWithPath: answerDestination).deletingPathExtension().lastPathComponent
      if !stem.isEmpty {
        return stem
      }
      return answerDestination
    }
    return candidate.inbox
  }
}
