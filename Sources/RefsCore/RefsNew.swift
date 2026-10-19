import Foundation

/// The ⌥N mark stored for one reference: `new` or `seen`, plus the
/// instant it was written. Presentation state on this Mac only.
public struct RefsNewMark: Equatable, Sendable {
  public var state: RefsNewMarkState
  public var at: Date

  public init(state: RefsNewMarkState, at: Date) {
    self.state = state
    self.at = at
  }
}

/// Codable raw values `"new"` and `"seen"`.
public enum RefsNewMarkState: String, Codable, Equatable, Sendable {
  case new
  case seen
}

/// One on-disk mark row. An unknown `state` drops this entry, not the
/// file; see `RefsNewMarksFile`.
public struct RefsNewMarkEntry: Equatable, Sendable {
  public var path: String
  public var state: RefsNewMarkState
  public var at: Date

  public init(path: String, state: RefsNewMarkState, at: Date) {
    self.path = path
    self.state = state
    self.at = at
  }
}

/// Note path → mark. On a duplicate path, the latest `at` wins.
public struct RefsNewMarks: Equatable, Sendable {
  private let byPath: [String: RefsNewMark]

  public init(entries: [RefsNewMarkEntry] = []) {
    var map: [String: RefsNewMark] = [:]
    for entry in entries {
      if let existing = map[entry.path], existing.at > entry.at {
        continue
      }
      map[entry.path] = RefsNewMark(state: entry.state, at: entry.at)
    }
    byPath = map
  }

  public func mark(for path: String) -> RefsNewMark? {
    byPath[path]
  }

  public var isEmpty: Bool {
    byPath.isEmpty
  }
}

/// Why a row is NEW: it arrived unmarked inside the window, or an ⌥N
/// `new` mark is still in force.
public enum RefsNewness: Equatable, Sendable {
  case arrived
  case marked(Date)
}

/// The smallest mark that produces the flipped NEW state, or
/// ineligible when the row is not Ready or Next.
public enum RefsNewToggleResult: Equatable, Sendable {
  case ineligible
  /// `mark` is nil when the arrival rule alone already yields the
  /// flipped state, so the stored mark is removed.
  case apply(mark: RefsNewMark?, becomesNew: Bool)
}

/// ⌥N flips NEW and stores the smallest mark that produces that state.
public enum RefsNewToggle {
  public static func result(
    for item: RefItem,
    signals: RefsSignals,
    now: Date
  ) -> RefsNewToggleResult {
    guard item.state == .ready || item.state == .next else {
      return .ineligible
    }
    let wantedNew = !RefsRanker.isNew(item, signals: signals)
    let unmarkedNew = RefsRanker.arrivedNew(item, signals: signals)
    if wantedNew == unmarkedNew {
      return .apply(mark: nil, becomesNew: wantedNew)
    }
    let state: RefsNewMarkState = wantedNew ? .new : .seen
    return .apply(
      mark: RefsNewMark(state: state, at: now),
      becomesNew: wantedNew
    )
  }
}
