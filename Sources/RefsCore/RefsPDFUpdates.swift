import CaptureCore
import Foundation

/// The scan entries relevant to the open-PDF update presentation.
public struct RefsPDFUpdates: Equatable, Sendable {
  public let refreshedOpen: [RefsScanNote]
  public let refreshedQuiet: [RefsScanNote]
  public let readingHolds: [RefsScanHold]
  public let busyHolds: [RefsScanHold]
  public let changedHolds: [RefsScanHold]

  /// Stable per-PDF keys let the app notify once while a PDF remains busy.
  public var busyHoldDedupeKeys: Set<String> {
    Set(busyHolds.map(RefsPDFUpdatePresentation.busyHoldDedupeKey(for:)))
  }

  /// True when a coordinated write did not already prove the PDF was
  /// open (`editor_saved_first`). The app then consults Highlights tabs,
  /// and only if Accessibility is already trusted.
  public static func needsOpenTabCheck(_ response: RefsScanResponse) -> Bool {
    response.notes.contains { note in
      guard let write = note.markerWrite else {
        return false
      }
      return write.mode == "coordinated" && !write.editorSavedFirst
    }
  }

  /// Tab titles as Highlights exposes them, plus each title's last path
  /// component so a basename still matches `source_pdf`.
  public static func tabFileNames(from snapshot: HighlightsTabsSnapshot) -> Set<String> {
    var names = Set<String>()
    for window in snapshot.windows {
      for tab in window.tabs {
        names.insert(tab.fileName)
        let base = URL(fileURLWithPath: tab.fileName).lastPathComponent
        if !base.isEmpty {
          names.insert(base)
        }
      }
    }
    return names
  }

  public init(response: RefsScanResponse, openTabFileNames: Set<String>? = nil) {
    var open: [RefsScanNote] = []
    var quiet: [RefsScanNote] = []

    for note in response.notes where note.markerWrite != nil {
      let markerWrite = note.markerWrite!
      let openedBySavedFirst = markerWrite.editorSavedFirst
      let openedByTab =
        markerWrite.mode == "coordinated"
        && note.sourcePDF.map { pdfPath in
          openTabFileNames?.contains(Self.fileName(of: pdfPath)) ?? false
        } == true
      if openedBySavedFirst || openedByTab {
        open.append(note)
      } else {
        quiet.append(note)
      }
    }

    var reading: [RefsScanHold] = []
    var busy: [RefsScanHold] = []
    var changed: [RefsScanHold] = []
    for hold in response.held {
      switch hold.reason {
      case "editor_active":
        reading.append(hold)
      case "coordination_timeout":
        busy.append(hold)
      case "marker_changed":
        changed.append(hold)
      default:
        break
      }
    }

    refreshedOpen = open
    refreshedQuiet = quiet
    readingHolds = reading
    busyHolds = busy
    changedHolds = changed
  }

  private static func fileName(of path: String) -> String {
    URL(fileURLWithPath: path).lastPathComponent
  }
}

public struct RefsPDFUpdateNotification: Equatable, Sendable {
  public let title: String
  public let subtitle: String?
  public let body: String
  public let notePath: String
  public let dedupeKey: String?

  public init(
    title: String,
    subtitle: String? = nil,
    body: String,
    notePath: String,
    dedupeKey: String? = nil
  ) {
    self.title = title
    self.subtitle = subtitle
    self.body = body
    self.notePath = notePath
    self.dedupeKey = dedupeKey
  }
}

public struct RefsPDFUpdateBanner: Equatable, Sendable {
  public let title: String
  public let message: String
  public let actionTitle: String

  public init(title: String, message: String, actionTitle: String) {
    self.title = title
    self.message = message
    self.actionTitle = actionTitle
  }
}

/// What the app should show for one classified scan: footer clauses
/// always, a busy banner when Highlights did not answer, and hidden-panel
/// notifications only when they are enabled.
public struct RefsPDFUpdateSurface: Equatable, Sendable {
  public let footerClauses: [String]
  public let banner: RefsPDFUpdateBanner?
  public let notifications: [RefsPDFUpdateNotification]
  public let nextNotifiedBusyKeys: Set<String>

  public init(
    footerClauses: [String],
    banner: RefsPDFUpdateBanner?,
    notifications: [RefsPDFUpdateNotification],
    nextNotifiedBusyKeys: Set<String>
  ) {
    self.footerClauses = footerClauses
    self.banner = banner
    self.notifications = notifications
    self.nextNotifiedBusyKeys = nextNotifiedBusyKeys
  }
}

/// Exact copy for grouped open-PDF notifications, footer clauses, and the
/// coordination-timeout banner. State labels come from the Refs vocabulary.
public enum RefsPDFUpdatePresentation {
  public static func notifications(for updates: RefsPDFUpdates) -> [RefsPDFUpdateNotification] {
    var notices: [RefsPDFUpdateNotification] = []

    if let first = updates.refreshedOpen.first {
      if updates.refreshedOpen.count == 1 {
        notices.append(refreshNotification(for: first))
      } else {
        let count = updates.refreshedOpen.count
        notices.append(
          RefsPDFUpdateNotification(
            title: "Updated \(count) PDFs in Highlights",
            body: joinedRefreshTitles(updates.refreshedOpen),
            notePath: first.path
          )
        )
      }
    }

    for hold in updates.busyHolds {
      notices.append(
        RefsPDFUpdateNotification(
          title: "Highlights needs you",
          subtitle: displayTitle(for: hold),
          body:
            "Highlights didn't answer — a dialog may be open. Bob will update this PDF once it's free.",
          notePath: hold.note,
          dedupeKey: busyHoldDedupeKey(for: hold)
        )
      )
    }

    return notices
  }

  public static func footerClauses(for updates: RefsPDFUpdates) -> [String] {
    var clauses: [String] = []
    let refreshedCount = updates.refreshedOpen.count
    if refreshedCount > 0 {
      let noun = refreshedCount == 1 ? "PDF" : "PDFs"
      clauses.append("\(refreshedCount) \(noun) refreshed in Highlights")
    }

    let waitingCount = updates.readingHolds.count + updates.changedHolds.count
    if waitingCount > 0 {
      let noun = waitingCount == 1 ? "PDF" : "PDFs"
      clauses.append("\(waitingCount) \(noun) waiting while you read")
    }
    return clauses
  }

  public static func busyBanner(for updates: RefsPDFUpdates) -> RefsPDFUpdateBanner? {
    guard !updates.busyHolds.isEmpty else {
      return nil
    }
    return RefsPDFUpdateBanner(
      title: "Highlights needs you",
      message:
        "Highlights didn't answer — a dialog may be open. Bob will update this PDF once it's free.",
      actionTitle: "Scan Again"
    )
  }

  public static func busyHoldDedupeKey(for hold: RefsScanHold) -> String {
    "busy:\(hold.pdf)"
  }

  /// Hidden-panel notifications are suppressed when the panel is visible
  /// or the setting is off; footer clauses and the busy banner stay.
  /// Busy-hold notifications fire once per PDF until that PDF leaves
  /// `coordination_timeout`.
  public static func surface(
    for updates: RefsPDFUpdates,
    panelVisible: Bool,
    notificationsEnabled: Bool,
    previouslyNotifiedBusyKeys: Set<String>
  ) -> RefsPDFUpdateSurface {
    let currentBusy = updates.busyHoldDedupeKeys
    var notices: [RefsPDFUpdateNotification] = []
    if !panelVisible, notificationsEnabled {
      notices = notifications(for: updates).filter { notice in
        guard let key = notice.dedupeKey else {
          return true
        }
        return !previouslyNotifiedBusyKeys.contains(key)
      }
    }
    return RefsPDFUpdateSurface(
      footerClauses: footerClauses(for: updates),
      banner: busyBanner(for: updates),
      notifications: notices,
      nextNotifiedBusyKeys: currentBusy
    )
  }

  private static func refreshNotification(for note: RefsScanNote) -> RefsPDFUpdateNotification {
    let markerWrite = note.markerWrite ?? RefsScanMarkerWrite()
    let body: String
    if let status = markerWrite.status,
      let from = status.from,
      let to = status.to
    {
      body =
        "\(stateLabel(from)) → \(stateLabel(to))"
        + savedFirstClause(markerWrite.editorSavedFirst)
    } else {
      body = "Page-1 note updated" + savedFirstClause(markerWrite.editorSavedFirst)
    }

    return RefsPDFUpdateNotification(
      title: "Updated in Highlights",
      subtitle: RefsScanPresentation.displayTitle(for: note),
      body: body,
      notePath: note.path
    )
  }

  private static func savedFirstClause(_ savedFirst: Bool) -> String {
    savedFirst ? " · your unsaved highlights were saved first" : ""
  }

  private static func joinedRefreshTitles(_ notes: [RefsScanNote]) -> String {
    let titles = notes.prefix(3).map(RefsScanPresentation.displayTitle(for:))
    let remaining = notes.count - titles.count
    var parts = titles
    if remaining > 0 {
      parts.append("+\(remaining) more")
    }
    return parts.joined(separator: " · ")
  }

  private static func displayTitle(for hold: RefsScanHold) -> String {
    TaskDisplayText(parsing: hold.title).text
  }

  private static func stateLabel(_ status: String) -> String {
    switch RefState(status: status, readingState: nil) {
    case .reading:
      return "Reading"
    case .next:
      return "Next"
    case .ready:
      return "Ready"
    case .read:
      return "Read"
    case .dropped:
      return "Dropped"
    case .unknown:
      return "Unknown"
    }
  }
}
