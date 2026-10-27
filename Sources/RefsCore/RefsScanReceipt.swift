import Foundation

/// One decoded scan receipt and a stable digest of its exact bytes.
public struct RefsScanReceipt: Equatable, Sendable {
    public let response: RefsScanResponse
    public let contentHash: UInt64

    public init(response: RefsScanResponse, contentHash: UInt64) {
        self.response = response
        self.contentHash = contentHash
    }
}

public enum RefsScanReceiptError: Error, Equatable, Sendable {
    case tooLarge(maximumBytes: Int)
}

/// Reads bob's last scan receipt without loading an unbounded file into
/// memory. Unsupported schema versions are ignored.
public struct RefsScanReceiptReader: Sendable {
    public static let maximumBytes = 4 * 1024 * 1024

    /// Darwin notification posted after a writing `bob ref scan` rewrites
    /// the receipt. The Mac app observes this name and never polls.
    public static let darwinNotificationName = "org.bobs.bob.ref.scan-finished"

    public init() {}

    /// Resolves the same state root as bob: `XDG_STATE_HOME`, otherwise
    /// `$HOME/.local/state`, then `bob-cli/ref/last-scan.json`.
    public static func receiptURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let stateRoot: URL
        if let xdgStateHome = environment["XDG_STATE_HOME"], !xdgStateHome.isEmpty {
            stateRoot = URL(fileURLWithPath: xdgStateHome, isDirectory: true)
        } else {
            let home =
                environment["HOME"].flatMap { value in
                    value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
                } ?? homeDirectoryURL
            stateRoot = home.appendingPathComponent(".local/state", isDirectory: true)
        }

        return
            stateRoot
            .appendingPathComponent("bob-cli", isDirectory: true)
            .appendingPathComponent("ref", isDirectory: true)
            .appendingPathComponent("last-scan.json", isDirectory: false)
    }

    public func read(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> RefsScanReceipt? {
        try read(at: Self.receiptURL(environment: environment, homeDirectoryURL: homeDirectoryURL))
    }

    public func read(at url: URL) throws -> RefsScanReceipt? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var data = Data()
        while data.count <= Self.maximumBytes {
            let remaining = Self.maximumBytes + 1 - data.count
            guard remaining > 0,
                let chunk = try handle.read(upToCount: min(64 * 1024, remaining)),
                !chunk.isEmpty
            else {
                break
            }
            data.append(chunk)
        }

        guard data.count <= Self.maximumBytes else {
            throw RefsScanReceiptError.tooLarge(maximumBytes: Self.maximumBytes)
        }

        let response = try JSONDecoder().decode(RefsScanResponse.self, from: data)
        guard response.schemaVersion == 1 else {
            return nil
        }
        return RefsScanReceipt(response: response, contentHash: Self.fnv1a64(data))
    }

    /// The app compares this digest only with the last receipt it presented.
    /// FNV-1a is deterministic across platforms and avoids adding a crypto
    /// dependency to the portable RefsCore target.
    private static func fnv1a64(_ data: Data) -> UInt64 {
        data.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
    }
}
