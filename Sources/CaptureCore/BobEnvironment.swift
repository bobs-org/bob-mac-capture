import Foundation

public struct BobEnvironmentBuilder: Sendable {
    public var homeDirectory: String
    public var bobDirectory: String?
    public var currentEnvironment: [String: String]

    public init(
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        bobDirectory: String? = nil,
        currentEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.homeDirectory = homeDirectory
        self.bobDirectory = bobDirectory
        self.currentEnvironment = currentEnvironment
    }

    public func build() -> [String: String] {
        var environment: [String: String] = [
            "HOME": homeDirectory,
            "PATH": [
                "/usr/bin",
                "/bin",
                "/usr/sbin",
                "/sbin",
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "\(homeDirectory)/.cargo/bin",
                "\(homeDirectory)/bin",
            ].joined(separator: ":"),
            "LANG": currentEnvironment["LANG"] ?? "en_US.UTF-8",
            "LC_CTYPE": currentEnvironment["LC_CTYPE"] ?? "UTF-8",
        ]

        if let lcAll = currentEnvironment["LC_ALL"], !lcAll.isEmpty {
            environment["LC_ALL"] = lcAll
        }

        if let bobDirectory, !bobDirectory.isEmpty {
            environment["BOB_DIR"] = bobDirectory
        }

        for key in Self.preservedOverrideKeys {
            if key == "BOB_DIR", bobDirectory != nil {
                continue
            }
            if let value = currentEnvironment[key], !value.isEmpty {
                environment[key] = value
            }
        }

        return environment
    }

    public static let preservedOverrideKeys: Set<String> = [
        "BOB_CAPTURE_DEBUG",
        "BOB_CONFIG",
        "BOB_DIR",
        "BOB_LOG",
        "BOB_LOG_LEVEL",
        "BOB_NO_COLOR",
        "NO_COLOR",
        "RUST_LOG",
    ]
}
