import Foundation

/// One row presented for a draft item. A linked row uses the last match
/// returned before the edit; its anchors are informational and must not be
/// used for another splice.
public struct SimilarTasksBandRow: Equatable, Sendable, Identifiable {
  public let itemIndex: Int
  public let rowNumber: Int
  public let match: CaptureRelatedMatch
  public let linkedBy: CaptureRelatedLinkKind?
  public let isHeld: Bool

  public var id: String { "\(itemIndex):\(match.key)" }

  public init(
    itemIndex: Int,
    rowNumber: Int,
    match: CaptureRelatedMatch,
    linkedBy: CaptureRelatedLinkKind? = nil,
    isHeld: Bool = false
  ) {
    self.itemIndex = itemIndex
    self.rowNumber = rowNumber
    self.match = match
    self.linkedBy = linkedBy
    self.isHeld = isHeld
  }
}

/// Rows and overflow count belonging to one Bob-reported task-creating item.
public struct SimilarTasksBandItem: Equatable, Sendable, Identifiable {
  public let index: Int
  public let mode: String
  public let rows: [SimilarTasksBandRow]
  public let overflowCount: Int
  public let showsHeader: Bool

  public var id: Int { index }
  public var isVisible: Bool { !rows.isEmpty }

  public init(
    index: Int,
    mode: String,
    rows: [SimilarTasksBandRow] = [],
    overflowCount: Int = 0,
    showsHeader: Bool = false
  ) {
    self.index = index
    self.mode = mode
    self.rows = rows
    self.overflowCount = overflowCount
    self.showsHeader = showsHeader
  }
}

/// One parse item's index and mode, used by the render gate so a band
/// never paints on a card whose latest parse no longer matches.
public struct SimilarTasksParseItem: Equatable, Sendable {
  public let index: Int
  public let mode: String

  public init(index: Int, mode: String) {
    self.index = index
    self.mode = mode
  }
}

/// The app-owned presentation snapshot. `pending` keeps the currently painted
/// rows stable while text changes and the next settled Bob result is in flight.
public struct SimilarTasksBandState: Equatable, Sendable {
  public let draft: String?
  public let items: [SimilarTasksBandItem]
  public let pending: Bool
  public let focusedRowID: String?
  /// Parse item count captured with this snapshot. A later parse whose
  /// count differs clears every held band until the next settle.
  public let parseItemCount: Int?
  /// Extra hidden rows revealed per item index via ↓ on the last visible
  /// row. Unfocusing the band collapses them back to zero.
  public let revealed: [Int: Int]

  public static let empty = SimilarTasksBandState()

  public init(
    draft: String? = nil,
    items: [SimilarTasksBandItem] = [],
    pending: Bool = false,
    focusedRowID: String? = nil,
    parseItemCount: Int? = nil,
    revealed: [Int: Int] = [:]
  ) {
    self.draft = draft
    self.items = items
    self.pending = pending
    self.focusedRowID = focusedRowID
    self.parseItemCount = parseItemCount
    self.revealed = revealed
  }

  public var rows: [SimilarTasksBandRow] {
    items.flatMap(\.rows)
  }
}

/// Pure display policy for Bob's related-task response. It applies only
/// presentation caps and hysteresis; it never scores or reorders candidates.
public enum SimilarTasksBandPolicy {
  public static let singleItemRowLimit = 2
  public static let bulkItemRowLimit = 1
  public static let draftRowLimit = 5

  private static let taskCreatingModes: Set<String> = [
    "task",
    "pomodoro_task",
    "project_note",
    "pomodoro_project_note",
  ]

  public static func markPending(_ state: SimilarTasksBandState) -> SimilarTasksBandState {
    SimilarTasksBandState(
      draft: state.draft,
      items: state.items,
      pending: true,
      focusedRowID: state.focusedRowID,
      parseItemCount: state.parseItemCount,
      revealed: state.revealed
    )
  }

  /// Reduces one settled response. `draftItemCount` comes from Bob's
  /// `capture-parse` result when available, so a bulk draft with one
  /// task-creating item still receives the bulk row cap.
  public static func reduce(
    _ response: CaptureRelatedResponse,
    previous: SimilarTasksBandState = .empty,
    draft: String? = nil,
    draftItemCount: Int? = nil
  ) -> SimilarTasksBandState {
    let sourceItems = response.items.sorted { $0.index < $1.index }
    let isBulk = max(draftItemCount ?? 0, sourceItems.count) > 1
    var remainingDraftRows = draftRowLimit
    var nextRowNumber = 1
    var resultItems: [SimilarTasksBandItem] = []
    // Hidden matches still available per item, so reveal counts that no
    // longer show extra rows collapse instead of going stale.
    var hiddenRemaining: [Int: Int] = [:]

    for item in sourceItems {
      guard taskCreatingModes.contains(item.mode) else { continue }

      let previousRows = previous.items.first(where: { $0.index == item.index })?.rows ?? []
      let previousByKey = Dictionary(previousRows.map { ($0.match.key, $0) }, uniquingKeysWith: { first, _ in first })
      let linkedByKey = Dictionary(item.linked.map { ($0.key, $0.link) }, uniquingKeysWith: { _, last in last })
      var candidates: [CandidateRow] = []
      var seenKeys = Set<String>()

      for match in item.matches {
        guard !seenKeys.contains(match.key) else { continue }
        if linkedByKey[match.key] != nil { continue }

        let held = match.band == .hold
        if held, previousByKey[match.key] == nil {
          continue
        }
        guard held || isDisplayBand(match.band) else { continue }

        seenKeys.insert(match.key)
        candidates.append(CandidateRow(match: match, linkedBy: nil, isHeld: held))
      }

      // Bob omits an already-related candidate from matches. Keep that row
      // in its previous position and mark the relationship from Bob's data.
      for oldRow in previousRows {
        guard let link = linkedByKey[oldRow.match.key],
              isDisplayLink(link),
              !seenKeys.contains(oldRow.match.key)
        else {
          continue
        }
        let insertionIndex = min(oldRow.rowNumber - 1, candidates.count)
        candidates.insert(
          CandidateRow(match: oldRow.match, linkedBy: link, isHeld: false),
          at: insertionIndex
        )
        seenKeys.insert(oldRow.match.key)
      }

      let perItemLimit = isBulk ? bulkItemRowLimit : singleItemRowLimit
      // Revealed extras survive settles, clamped to the hidden matches still
      // available; unfocusing resets them to zero in the model.
      let hiddenCount = max(0, candidates.count - perItemLimit)
      let revealedExtra = min(previous.revealed[item.index] ?? 0, hiddenCount)
      let count = min(candidates.count, min(perItemLimit + revealedExtra, remainingDraftRows))
      guard count > 0 else { continue }

      let visibleRows = candidates.prefix(count).map { candidate in
        defer { nextRowNumber += 1 }
        return SimilarTasksBandRow(
          itemIndex: item.index,
          rowNumber: nextRowNumber,
          match: candidate.match,
          linkedBy: candidate.linkedBy,
          isHeld: candidate.isHeld
        )
      }
      remainingDraftRows -= count
      hiddenRemaining[item.index] = candidates.count - count
      resultItems.append(
        SimilarTasksBandItem(
          index: item.index,
          mode: item.mode,
          rows: Array(visibleRows),
          overflowCount: isBulk ? 0 : max(0, candidates.count - count),
          showsHeader: !isBulk
        )
      )
    }

    let rowIDs = Set(resultItems.flatMap(\.rows).map(\.id))
    let focusedRowID = previous.focusedRowID.flatMap { rowIDs.contains($0) ? $0 : nil }
    // Keep only the reveal counts that still hide matches; settled swaps
    // that drop hidden matches collapse their reveal instead of going stale.
    var revealed: [Int: Int] = [:]
    for (index, extra) in previous.revealed {
      guard extra > 0,
            resultItems.contains(where: { $0.index == index }),
            (hiddenRemaining[index] ?? 0) > 0
      else { continue }
      revealed[index] = extra
    }
    return SimilarTasksBandState(
      draft: draft,
      items: resultItems,
      pending: false,
      focusedRowID: focusedRowID,
      parseItemCount: draftItemCount,
      revealed: revealed
    )
  }

  /// A band paints on capture index `i` only while the latest parse still
  /// reports item `i` with the same mode Bob matched, and only while the
  /// parse's item count is unchanged. An empty parse snapshot leaves the
  /// settled rows visible (preview can land before parse in tests).
  public static func visibleItem(
    in state: SimilarTasksBandState,
    captureIndex: Int,
    parseItems: [SimilarTasksParseItem]
  ) -> SimilarTasksBandItem? {
    guard let item = state.items.first(where: { $0.index == captureIndex }),
          item.isVisible
    else {
      return nil
    }
    guard passesRenderGate(state, parseItems: parseItems) else {
      return nil
    }
    guard parseItems.isEmpty || parseItems.contains(where: {
      $0.index == item.index && $0.mode == item.mode
    }) else {
      return nil
    }
    return item
  }

  public static func visibleItems(
    in state: SimilarTasksBandState,
    parseItems: [SimilarTasksParseItem]
  ) -> [SimilarTasksBandItem] {
    guard passesRenderGate(state, parseItems: parseItems) else {
      return []
    }
    return state.items.compactMap { item in
      visibleItem(in: state, captureIndex: item.index, parseItems: parseItems)
    }
  }

  private static func passesRenderGate(
    _ state: SimilarTasksBandState,
    parseItems: [SimilarTasksParseItem]
  ) -> Bool {
    guard !parseItems.isEmpty, let expected = state.parseItemCount else {
      return true
    }
    return expected == parseItems.count
  }

  private static func isDisplayBand(_ band: CaptureRelatedBand) -> Bool {
    switch band {
    case .sameTitle, .possibleDuplicate, .similar, .closedDuplicate:
      true
    case .hold, .unknown:
      false
    }
  }

  private static func isDisplayLink(_ link: CaptureRelatedLinkKind) -> Bool {
    switch link {
    case .relation, .dependency, .blockedTask, .parent:
      true
    case .unknown:
      false
    }
  }

  private struct CandidateRow {
    let match: CaptureRelatedMatch
    let linkedBy: CaptureRelatedLinkKind?
    let isHeld: Bool
  }
}
