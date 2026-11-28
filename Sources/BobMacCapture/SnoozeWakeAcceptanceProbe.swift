import AppKit
import CaptureCore
import Darwin
import Foundation
import notify

func probeJSONBox<T>(_ value: T?) -> Any {
    if let value {
        return value
    }
    return NSNull()
}

/// Injectable Reduce Motion / Reduce Transparency for the acceptance
/// probe. `nil` means "use the live system setting".
@MainActor
final class ProbeDisplayOverrides {
    var reduceMotion: Bool?
    var reduceTransparency: Bool?

    func motion() -> Bool {
        reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func transparency() -> Bool {
        reduceTransparency ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

/// Host the in-app probe drives. AppDelegate implements this so the
/// probe never reaches past the live objects the product already owns.
@MainActor
protocol SnoozeWakeAcceptanceProbeHost: AnyObject {
    func probeHandle(command: String, args: [String]) async throws -> [String: Any]
}

/// Acceptance-only HUD/beacon/record probe. Production never enables it:
/// `org.bobs.bob-mac-capture` does not prefix-match `.accept`. The
/// accept and accept-noauth scratch identities do. The probe never
/// parses or writes the vault.
@MainActor
final class SnoozeWakeAcceptanceProbe {
    static let bundlePrefix = "org.bobs.bob-mac-capture.accept"
    static let defaultsKey = "snoozeAcceptanceProbe"
    static let darwinName = "org.bobs.bob-mac-capture.accept.probe"
    static let maxRequestBytes = 64 * 1024
    static let maxResponseBytes = 1024 * 1024

    weak var host: SnoozeWakeAcceptanceProbeHost?
    private let defaults: UserDefaults
    private let bundleIdentifier: String?
    private let environment: [String: String]
    private let homeDirectoryURL: URL
    private let register: (@escaping @Sendable () -> Void) -> Int32?
    private let cancel: (Int32) -> Void
    private var token: Int32?
    private(set) var isStarted = false

    init(
        host: SnoozeWakeAcceptanceProbeHost?,
        defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        register: ((@escaping @Sendable () -> Void) -> Int32?)? = nil,
        cancel: ((Int32) -> Void)? = nil
    ) {
        self.host = host
        self.defaults = defaults
        self.bundleIdentifier = bundleIdentifier
        self.environment = environment
        self.homeDirectoryURL = homeDirectoryURL
        self.register = register ?? Self.registerLive
        self.cancel = cancel ?? { token in notify_cancel(token) }
    }

    static func isEnabled(
        bundleIdentifier: String?,
        defaults: UserDefaults
    ) -> Bool {
        guard let bundleIdentifier,
            bundleIdentifier.hasPrefix(bundlePrefix)
        else {
            return false
        }
        return defaults.bool(forKey: defaultsKey)
    }

    var isEnabled: Bool {
        Self.isEnabled(bundleIdentifier: bundleIdentifier, defaults: defaults)
    }

    static func probeDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let stateRoot: URL
        if let xdg = environment["XDG_STATE_HOME"], !xdg.isEmpty {
            stateRoot = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            let home =
                environment["HOME"].flatMap { value in
                    value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
                } ?? homeDirectoryURL
            stateRoot = home.appendingPathComponent(".local/state", isDirectory: true)
        }
        return
            stateRoot
            .appendingPathComponent("bob-mac-capture-accept", isDirectory: true)
            .appendingPathComponent("probe", isDirectory: true)
    }

    func start() {
        guard isEnabled, !isStarted else { return }
        let directory = Self.probeDirectory(
            environment: environment, homeDirectoryURL: homeDirectoryURL)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        guard
            let token = register({ [weak self] in
                Task { @MainActor in
                    await self?.processRequest()
                }
            })
        else {
            return
        }
        self.token = token
        isStarted = true
    }

    func stop() {
        if let token {
            cancel(token)
        }
        token = nil
        isStarted = false
    }

    /// Decode one request, run it on the host, and write `response-<seq>.json`.
    func processRequest() async {
        let directory = Self.probeDirectory(
            environment: environment, homeDirectoryURL: homeDirectoryURL)
        let requestURL = directory.appendingPathComponent("request.json")
        guard FileManager.default.fileExists(atPath: requestURL.path) else {
            return
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: requestURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let data: Data
        do {
            data = try Data(contentsOf: requestURL)
            try FileManager.default.removeItem(at: requestURL)
        } catch {
            await writeResponse(
                seq: 0, ok: false, error: "failed to read request", result: nil,
                directory: directory)
            return
        }
        if size > Self.maxRequestBytes || data.count > Self.maxRequestBytes {
            await writeResponse(
                seq: 0, ok: false, error: "request exceeds \(Self.maxRequestBytes) bytes",
                result: nil, directory: directory)
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            await writeResponse(
                seq: 0, ok: false, error: "request is not a JSON object", result: nil,
                directory: directory)
            return
        }
        let seq = (object["seq"] as? NSNumber)?.intValue ?? (object["seq"] as? Int) ?? 0
        let command = object["command"] as? String ?? ""
        let args = Self.parseArgs(object["args"])
        do {
            guard let host else {
                throw ProbeCommandError("probe host is not attached")
            }
            let result = try await host.probeHandle(command: command, args: args)
            await writeResponse(
                seq: seq, ok: true, error: nil, result: result, directory: directory)
        } catch {
            await writeResponse(
                seq: seq, ok: false, error: String(describing: error), result: nil,
                directory: directory)
        }
    }

    /// In-memory handle for unit tests that skip the Darwin transport.
    func handle(seq: Int, command: String, args: [String]) async -> [String: Any] {
        do {
            guard let host else {
                throw ProbeCommandError("probe host is not attached")
            }
            let result = try await host.probeHandle(command: command, args: args)
            return Self.responseObject(seq: seq, ok: true, error: nil, result: result)
        } catch {
            return Self.responseObject(
                seq: seq, ok: false, error: String(describing: error), result: nil)
        }
    }

    static func parseArgs(_ raw: Any?) -> [String] {
        if let values = raw as? [String] {
            return values
        }
        if let values = raw as? [Any] {
            return values.map { "\($0)" }
        }
        if let value = raw as? String, !value.isEmpty {
            return [value]
        }
        return []
    }

    static func responseObject(
        seq: Int, ok: Bool, error: String?, result: [String: Any]?
    ) -> [String: Any] {
        [
            "seq": seq,
            "ok": ok,
            "error": probeJSONBox(error),
            "result": probeJSONBox(result),
        ]
    }

    private func writeResponse(
        seq: Int, ok: Bool, error: String?, result: [String: Any]?, directory: URL
    ) async {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        var object = Self.responseObject(seq: seq, ok: ok, error: error, result: result)
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data()
        if data.count > Self.maxResponseBytes {
            object = Self.responseObject(
                seq: seq, ok: false, error: "response exceeds \(Self.maxResponseBytes) bytes",
                result: nil)
            data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data()
        }
        let url = directory.appendingPathComponent("response-\(seq).json")
        try? data.write(to: url, options: .atomic)
    }

    nonisolated private static func registerLive(
        _ handler: @escaping @Sendable () -> Void
    ) -> Int32? {
        var token: Int32 = 0
        let status = notify_register_dispatch(
            darwinName,
            &token,
            DispatchQueue.main
        ) { _ in
            handler()
        }
        return status == 0 ? token : nil
    }
}
