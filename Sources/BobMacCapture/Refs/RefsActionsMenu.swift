import AppKit
import Foundation
import RefsCore

/// One ⌘K action, in menu order. Titles live here so tests assert the
/// menu shape — which items appear for which rows — without building
/// an `NSMenu`.
public enum RefsAction: Equatable, Sendable {
    case openHighlights
    case openNote
    case reveal
    case copy
    case openSourceURL(URL)
    case openNarration(URL)
    case openDefaultApp
    case refreshLibrary
    case scanLibrary

    public var title: String {
        switch self {
        case .openHighlights:
            return "Open in Highlights"
        case .openNote:
            return "Open Note"
        case .reveal:
            return "Reveal in Finder"
        case .copy:
            return "Copy…"
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
    /// the opens carry ↵, ⌘↵, and ⌥↵, Refresh carries ⌘R, and Scan
    /// carries ⌘S.
    public var keyEquivalent: String {
        switch self {
        case .openHighlights, .openNote, .reveal:
            return "\r"
        case .refreshLibrary:
            return "r"
        case .scanLibrary:
            return "s"
        case .copy:
            return "y"
        case .openSourceURL, .openNarration, .openDefaultApp:
            return ""
        }
    }

    public var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        switch self {
        case .openNote, .refreshLibrary, .scanLibrary:
            return .command
        case .reveal:
            return .option
        case .copy:
            return .control
        case .openHighlights, .openSourceURL, .openNarration, .openDefaultApp:
            return []
        }
    }
}

/// The ⌘K actions menu: an `NSMenu` popped up over the panel for the
/// selected row. Sections render with separators between them.
public enum RefsActionsMenu {
    /// The menu sections for an item: opens, copies and sources, then
    /// the default-app open, refresh, and scan. "Open Source URL"
    /// appears only when `urls` is non-empty; "Open Narration" only
    /// when `audio` is set and resolves. Scan comes last in the closing
    /// section, after Refresh Library.
    public static func sections(
        for item: RefItem,
        audioURL: URL?
    ) -> [[RefsAction]] {
        let opens: [RefsAction] = [.openHighlights, .openNote, .reveal]
        var middle: [RefsAction] = [.copy]
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
