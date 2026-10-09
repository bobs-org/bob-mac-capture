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
    case copyWikiLink
    case copyPDFPath
    case openSourceURL(URL)
    case openNarration(URL)
    case openDefaultApp
    case refreshLibrary

    public var title: String {
        switch self {
        case .openHighlights:
            return "Open in Highlights"
        case .openNote:
            return "Open Note"
        case .reveal:
            return "Reveal in Finder"
        case .copyWikiLink:
            return "Copy Wiki Link"
        case .copyPDFPath:
            return "Copy PDF Path"
        case .openSourceURL:
            return "Open Source URL"
        case .openNarration:
            return "Open Narration"
        case .openDefaultApp:
            return "Open in Default App"
        case .refreshLibrary:
            return "Refresh Library"
        }
    }

    public var keyEquivalent: String {
        switch self {
        case .refreshLibrary:
            return "r"
        default:
            return ""
        }
    }

    public var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        switch self {
        case .refreshLibrary:
            return .command
        default:
            return []
        }
    }
}

/// The ⌘K actions menu: an `NSMenu` popped up over the panel for the
/// selected row. Sections render with separators between them.
public enum RefsActionsMenu {
    /// The menu sections for an item: opens, copies and sources, then
    /// the default-app open and refresh. "Open Source URL" appears only
    /// when `urls` is non-empty; "Open Narration" only when `audio` is
    /// set and resolves.
    public static func sections(
        for item: RefItem,
        audioURL: URL?
    ) -> [[RefsAction]] {
        let opens: [RefsAction] = [.openHighlights, .openNote, .reveal]
        var middle: [RefsAction] = [.copyWikiLink, .copyPDFPath]
        if let source = item.urls.compactMap(URL.init(string:)).first {
            middle.append(.openSourceURL(source))
        }
        if let audioURL {
            middle.append(.openNarration(audioURL))
        }
        let closing: [RefsAction] = [.openDefaultApp, .refreshLibrary]
        return [opens, middle, closing]
    }
}

/// The pasteboard behind the copy actions, so tests inject a fake.
public protocol RefsPasteboardWriting: Sendable {
    func copy(_ string: String)
}

/// The live pasteboard: the general pasteboard's string slot.
public struct SystemRefsPasteboard: RefsPasteboardWriting, Sendable {
    public init() {}

    public func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        _ = NSPasteboard.general.setString(string, forType: .string)
    }
}
