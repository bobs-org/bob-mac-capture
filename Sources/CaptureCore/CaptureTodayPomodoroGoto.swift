import Foundation

/// Pure landing rule for Command-\: choose among the entries
/// `bob capture-pomodoros --format json --all` returned, then build a
/// read-only `obsidian://bob-goto-task` URL. The app never reads the daily
/// note.
public enum CaptureTodayPomodoroGoto {
    public enum Landing: Equatable, Sendable {
        case current
        case firstOpen
        case lastCompleted
        case noteTop
    }

    public struct Destination: Equatable, Sendable {
        public let url: URL
        public let landing: Landing

        public init(url: URL, landing: Landing) {
            self.url = url
            self.landing = landing
        }
    }

    public enum Refusal: Equatable, Sendable {
        case missingDayFile

        public var statusText: String {
            switch self {
            case .missingDayFile:
                return "bob sent no daily-note path — update bob"
            }
        }
    }

    public enum Resolution: Equatable, Sendable {
        case destination(Destination)
        case refused(Refusal)
    }

    public static func resolve(_ response: CapturePomodorosResponse) -> Resolution {
        guard let dayFile = response.dayFile, isAbsoluteDayFile(dayFile) else {
            return .refused(.missingDayFile)
        }

        if let current = response.pomodoros.first(where: { $0.isCurrent }),
            let url = url(dayFile: dayFile, entry: current)
        {
            return .destination(Destination(url: url, landing: .current))
        }

        if let open = response.pomodoros.first(where: { $0.state == .open }),
            let url = url(dayFile: dayFile, entry: open)
        {
            return .destination(Destination(url: url, landing: .firstOpen))
        }

        if let completed = response.pomodoros.last(where: { $0.state == .completed }),
            let url = url(dayFile: dayFile, entry: completed)
        {
            return .destination(Destination(url: url, landing: .lastCompleted))
        }

        guard let url = ObsidianOpenURL.taskGotoURL(path: dayFile, line: 1, ref: nil) else {
            return .refused(.missingDayFile)
        }
        return .destination(Destination(url: url, landing: .noteTop))
    }

    private static func isAbsoluteDayFile(_ dayFile: String) -> Bool {
        !dayFile.isEmpty && dayFile.hasPrefix("/")
    }

    private static func url(dayFile: String, entry: CapturePomodorosListEntry) -> URL? {
        guard entry.line > 0 else {
            return nil
        }
        if let ref = entry.ref,
            let url = ObsidianOpenURL.taskGotoURL(path: dayFile, line: entry.line, ref: ref)
        {
            return url
        }
        return ObsidianOpenURL.taskGotoURL(path: dayFile, line: entry.line, ref: nil)
    }
}
