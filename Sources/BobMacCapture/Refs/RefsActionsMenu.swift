import AppKit
import Foundation
import RefsCore

/// One ⌘K action, in menu order. Titles live here so tests assert the
/// menu shape — which items appear for which rows — without building
/// an `NSMenu`.
public enum RefsAction: Equatable, Sendable {
  case openHighlights
  case closeTab
  case openNote
  case openTask
  case reveal
  case copy
  case rename
  case linkToday
  case markSeen
  case markNew
  case openSourceURL(URL)
  case openNarration(URL)
  case openDefaultApp
  case refreshLibrary
  case scanLibrary

  public var title: String {
    switch self {
    case .openHighlights:
      return "Open in Highlights"
    case .closeTab:
      return "Close Tab"
    case .openNote:
      return "Open Note"
    case .openTask:
      return "Open Reading Task"
    case .reveal:
      return "Reveal in Finder"
    case .copy:
      return "Copy…"
    case .rename:
      return "Rename…"
    case .linkToday:
      return "Link to Today…"
    case .markSeen:
      return "Mark as Seen"
    case .markNew:
      return "Mark as New"
    case .openSourceURL:
      return "Open Source URL"
    case .openNarration:
      return "Open Narration"
    case .openDefaultApp:
      return "Open in Default App"
    case .refreshLibrary:
      return "Refresh Library"
    case .scanLibrary:
      return "Scan for New References"
    }
  }

  /// The shortcut hint the menu shows, mirroring the panel keys:
  /// the opens carry ↵, ⌘↵, ⌃↵, and ⌥↵, Close Tab carries ⌃X, Refresh
  /// carries ⌘R, and Scan carries ⌘S.
  public var keyEquivalent: String {
    switch self {
    case .openHighlights, .openNote, .openTask, .reveal:
      return "\r"
    case .closeTab:
      return "x"
    case .refreshLibrary:
      return "r"
    case .scanLibrary:
      return "s"
    case .copy:
      return "y"
    case .rename:
      return "r"
    case .linkToday, .markSeen, .markNew:
      return "n"
    case .openSourceURL, .openNarration, .openDefaultApp:
      return ""
    }
  }

  public var keyEquivalentModifierMask: NSEvent.ModifierFlags {
    switch self {
    case .openNote, .refreshLibrary, .scanLibrary:
      return .command
    case .reveal, .markSeen, .markNew:
      return .option
    case .copy:
      return .command
    case .rename:
      return [.command, .shift]
    case .linkToday:
      return .command
    case .closeTab, .openTask:
      return .control
    case .openHighlights, .openSourceURL, .openNarration, .openDefaultApp:
      return []
    }
  }
}

/// Whether the ⌘K menu offers a NEW toggle for the selected row.
public enum RefsNewMenuState: Equatable, Sendable {
  case none
  case isNew
  case isNotNew
}

/// The ⌘K actions menu: an `NSMenu` popped up over the panel for the
/// selected row. Sections render with separators between them.
public enum RefsActionsMenu {
  /// The menu sections for an item: opens, copies and sources, then
  /// the default-app open, refresh, and scan. "Open Source URL"
  /// appears only when `urls` is non-empty; "Open Narration" only
  /// when `audio` is set and resolves. "Open Reading Task" appears only
  /// when bob reports a reading task. Scan comes last in the closing
  /// section, after Refresh Library.
  public static func sections(
    for item: RefItem,
    audioURL: URL?,
    canCloseTab: Bool = false,
    newState: RefsNewMenuState = .none
  ) -> [[RefsAction]] {
    var opens: [RefsAction] = [.openHighlights]
    if canCloseTab {
      opens.append(.closeTab)
    }
    opens.append(.openNote)
    if item.readingTaskPath != nil {
      opens.append(.openTask)
    }
    opens.append(.reveal)
    var middle: [RefsAction] = [.copy, .rename, .linkToday]
    switch newState {
    case .none:
      break
    case .isNew:
      middle.append(.markSeen)
    case .isNotNew:
      middle.append(.markNew)
    }
    if let source = item.urls.compactMap(URL.init(string:)).first {
      middle.append(.openSourceURL(source))
    }
    if let audioURL {
      middle.append(.openNarration(audioURL))
    }
    let closing: [RefsAction] = [.openDefaultApp, .refreshLibrary, .scanLibrary]
    return [opens, middle, closing]
  }
}

/// The pasteboard behind the copy actions, so tests inject a fake.
public protocol RefsPasteboardWriting: Sendable {
  func write(_ payload: RefsClipboardPayload) -> Bool
}

extension RefsPasteboardWriting {
  /// Diagnostic and legacy copy sites write a plain string.
  public func copy(_ string: String) {
    _ = write(.text(string))
  }
}

/// The live pasteboard: one clear, then a checked text or file-URL write.
public struct SystemRefsPasteboard: RefsPasteboardWriting, Sendable {
  public static let sourceType = NSPasteboard.PasteboardType(
    "org.nspasteboard.source"
  )

  public init() {}

  public func write(_ payload: RefsClipboardPayload) -> Bool {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let wrote: Bool
    switch payload {
    case .text(let string):
      wrote = pasteboard.setString(string, forType: .string)
    case .fileURL(let url):
      wrote = pasteboard.writeObjects([url as NSURL])
    }
    pasteboard.setString(
      Bundle.main.bundleIdentifier ?? "org.bobs.bob-mac-capture",
      forType: Self.sourceType
    )
    return wrote
  }
}
