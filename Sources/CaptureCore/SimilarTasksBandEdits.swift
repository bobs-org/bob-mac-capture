import Foundation

/// Pure draft splices for the similar-tasks action strip. Bob owns the byte
/// anchors and replacement strings; these helpers only apply them to the
/// submitted draft so the model, the bridge, and the tests share one splice.
public enum SimilarTasksBandEdits {
  /// Fixed strip order. Bob lists only the valid subset; the UI paints them
  /// in this order and ignores anything else.
  public static let orderedActions: [CaptureRelatedAction] = [
    .relate, .note, .needs, .blocks, .open, .discard,
  ]

  /// Bob's valid actions in strip order.
  public static func orderedAvailableActions(
    for match: CaptureRelatedMatch
  ) -> [CaptureRelatedAction] {
    orderedActions.filter { match.actions.contains($0) }
  }

  public static func sigil(for action: CaptureRelatedAction) -> String {
    switch action {
    case .relate: return "~"
    case .note: return "+"
    case .needs: return "&"
    case .blocks: return "*"
    case .open: return "/"
    case .discard: return "⌫"
    case .unknown: return "?"
    }
  }

  public static func label(for action: CaptureRelatedAction) -> String {
    switch action {
    case .relate: return "Relate"
    case .note: return "Add as note"
    case .needs: return "Needs it"
    case .blocks: return "Blocks it"
    case .open: return "Open"
    case .discard: return "Discard mine"
    case .unknown: return "Unknown"
    }
  }

  /// Applies one strip action to `draft`. Returns the edited draft and the
  /// UTF-8 cursor offset after the edit, or nil when the anchors are stale.
  /// `open` never edits and returns nil; the caller dispatches the URL.
  public static func editedDraft(
    _ draft: String,
    item: CaptureRelatedItem,
    match: CaptureRelatedMatch,
    action: CaptureRelatedAction
  ) -> (text: String, cursorUTF8: Int)? {
    // Discard splices the item range and never needs a replacement string.
    if action == .discard {
      guard let range = item.discardRange else { return nil }
      return deleted(draft, range: range)
    }
    guard let replacement = replacementString(match: match, action: action) else { return nil }
    return editedDraftWithReplacement(draft, item: item, replacement: replacement, action: action)
  }

  /// Bob's splice string for one strip action, or nil when the match carries
  /// none (`open` and unknown actions never splice).
  public static func replacementString(
    match: CaptureRelatedMatch,
    action: CaptureRelatedAction
  ) -> String? {
    switch action {
    case .relate:
      return itemReplacement(match, keyPath: \.relationTo)
    case .needs:
      return itemReplacement(match, keyPath: \.dependency)
    case .blocks:
      return itemReplacement(match, keyPath: \.blockedTask)
    case .note:
      return itemReplacement(match, keyPath: \.parent)
    case .discard, .open, .unknown:
      return nil
    }
  }

  /// Applies one strip action with an explicit splice string. Used after the
  /// Add block ID prompt assigns an ID-less row: `capture-task-id` returns
  /// the same replacement strings Bob's contract carries, so the splice is
  /// identical to the direct path.
  public static func editedDraftWithReplacement(
    _ draft: String,
    item: CaptureRelatedItem,
    replacement: String,
    action: CaptureRelatedAction
  ) -> (text: String, cursorUTF8: Int)? {
    switch action {
    case .discard:
      guard let range = item.discardRange else { return nil }
      return deleted(draft, range: range)
    case .relate, .needs, .blocks, .note:
      guard !replacement.isEmpty else { return nil }
      if action == .note, let range = item.routeRange {
        return replaced(draft, range: range, with: replacement)
      }
      guard let at = item.markerAt else { return nil }
      return inserted(draft, text: " " + replacement, at: at)
    case .open, .unknown:
      return nil
    }
  }

  /// Status line and VoiceOver announcement after a successful action.
  public static func announcement(
    for action: CaptureRelatedAction,
    title: String
  ) -> String {
    switch action {
    case .relate:
      return title.isEmpty ? "Related" : "Related to \(title)"
    case .note:
      return title.isEmpty ? "Added as a note" : "Added as a note under \(title)"
    case .needs:
      return title.isEmpty ? "Added dependency" : "Depends on \(title)"
    case .blocks:
      return title.isEmpty ? "Added blocked task" : "Blocks \(title)"
    case .open:
      return title.isEmpty ? "Opened in Obsidian" : "Opened \(title) in Obsidian"
    case .discard:
      return "Removed your item — ⌘Z restores it"
    case .unknown:
      return title
    }
  }

  private static func itemReplacement(
    _ match: CaptureRelatedMatch,
    keyPath: KeyPath<CaptureRelatedReplacements, String>
  ) -> String? {
    guard let replacements = match.replacements else { return nil }
    let value = replacements[keyPath: keyPath]
    return value.isEmpty ? nil : value
  }

  private static func inserted(
    _ draft: String,
    text: String,
    at offset: Int
  ) -> (text: String, cursorUTF8: Int)? {
    guard let range = stringRange(in: draft, start: offset, end: offset) else { return nil }
    var edited = draft
    edited.replaceSubrange(range, with: text)
    return (edited, offset + text.utf8.count)
  }

  private static func replaced(
    _ draft: String,
    range: CaptureRange,
    with text: String
  ) -> (text: String, cursorUTF8: Int)? {
    guard let swiftRange = stringRange(in: draft, byteRange: range) else { return nil }
    var edited = draft
    edited.replaceSubrange(swiftRange, with: text)
    return (edited, range.start + text.utf8.count)
  }

  private static func deleted(
    _ draft: String,
    range: CaptureRange
  ) -> (text: String, cursorUTF8: Int)? {
    guard let swiftRange = stringRange(in: draft, byteRange: range) else { return nil }
    var edited = draft
    edited.replaceSubrange(swiftRange, with: "")
    return (edited, min(range.start, edited.utf8.count))
  }
}
