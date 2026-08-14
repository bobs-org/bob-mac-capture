import Foundation

public struct BobExecutableResolver: Sendable {
    public let fileManager: FileManager
    public let homeDirectory: URL
    public let candidates: [String]

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        candidates: [String]? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.candidates = candidates ?? Self.defaultCandidates(homeDirectory: homeDirectory)
    }

    public func resolve(configuredOverride: String?) throws -> String {
        if let configuredOverride,
           !configuredOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            guard configuredOverride.hasPrefix("/") else {
                throw BobClientError.executableOverrideNotAbsolute(configuredOverride)
            }
            guard fileManager.isExecutableFile(atPath: configuredOverride) else {
                throw BobClientError.executableNotRunnable(configuredOverride)
            }
            return configuredOverride
        }

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        throw BobClientError.executableNotFound(candidates)
    }

    public static func defaultCandidates(homeDirectory: URL) -> [String] {
        let home = homeDirectory.path
        return [
            "\(home)/.cargo/bin/bob",
            "\(home)/bin/bob",
            "/opt/homebrew/bin/bob",
            "/usr/local/bin/bob",
        ]
    }
}
