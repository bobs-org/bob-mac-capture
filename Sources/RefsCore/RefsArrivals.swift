import Foundation

/// Tracks library ids the panel has already seen so a later first
/// appearance can reset the next ordinary show onto that reference.
///
/// The baseline only grows: an id that vanishes and later returns is
/// never pending again. `markSeen` never seeds the baseline; otherwise
/// a mark before the first snapshot would keep the next observe from
/// treating that snapshot as the first-run baseline.
public struct RefsArrivalTracker: Equatable, Sendable {
  /// Arrivals that land in this window of an untouched ordinary show
  /// reset the open panel and select the new reference.
  public static let visibleGraceSeconds: TimeInterval = 10

  private var baseline: Set<String>?
  private var pending: [String: Int] = [:]
  private var batch = 0

  /// Seeds the baseline when `knownIDs` is non-empty. An empty seed
  /// leaves the baseline unset so the first non-empty `observe` can
  /// establish it without pending ids.
  public init(knownIDs: some Sequence<String>) {
    let ids = Set(knownIDs)
    baseline = ids.isEmpty ? nil : ids
  }

  /// Records first-seen ids as one pending batch. The first non-empty
  /// observe against an unset baseline establishes it and marks
  /// nothing pending.
  public mutating func observe(_ ids: some Sequence<String>) {
    let observed = Set(ids)
    guard var known = baseline else {
      if !observed.isEmpty {
        baseline = observed
      }
      return
    }
    let newcomers = observed.subtracting(known)
    guard !newcomers.isEmpty else {
      return
    }
    batch += 1
    known.formUnion(newcomers)
    baseline = known
    for id in newcomers {
      pending[id] = batch
    }
  }

  /// Drops ids from pending and adds them to an already established
  /// baseline. It never seeds the baseline itself.
  public mutating func markSeen(_ ids: some Sequence<String>) {
    let seen = Array(ids)
    for id in seen {
      pending.removeValue(forKey: id)
    }
    guard var known = baseline else {
      return
    }
    known.formUnion(seen)
    baseline = known
  }

  /// Drops every pending id. The baseline is unchanged.
  public mutating func clearPending() {
    pending.removeAll()
  }

  /// True when any id is still waiting to reset a show.
  public var hasPending: Bool {
    !pending.isEmpty
  }

  /// True when a pending id is still in the library and its `added`
  /// day is inside the NEW window.
  public func hasQualifying(
    item: (String) -> RefItem?,
    signals: RefsSignals
  ) -> Bool {
    pending.keys.contains { id in
      guard let ref = item(id) else {
        return false
      }
      return RefsRanker.addedWithinNewWindow(ref, signals: signals)
    }
  }

  /// The pending id to select after an arrival reset: the latest batch
  /// that still qualifies and is listed, then the earliest listing
  /// position in that batch.
  public func target(
    orderedIDs: [String],
    item: (String) -> RefItem?,
    signals: RefsSignals
  ) -> String? {
    var best: (batch: Int, id: String)?
    for id in orderedIDs {
      guard let batch = pending[id],
        let ref = item(id),
        RefsRanker.addedWithinNewWindow(ref, signals: signals)
      else {
        continue
      }
      if let current = best {
        if batch > current.batch {
          best = (batch, id)
        }
      } else {
        best = (batch, id)
      }
    }
    return best?.id
  }
}
