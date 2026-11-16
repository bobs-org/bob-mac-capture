import Foundation
import XCTest

@testable import CaptureCore

final class NoteGotoOpenLogStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var supportDirectory: URL!
    private var fileURL: URL!
    private var quarantineURL: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "note-goto-open-log-tests-\(UUID().uuidString)", isDirectory: true)
        supportDirectory = tempDirectory.appendingPathComponent("support", isDirectory: true)
        fileURL = supportDirectory.appendingPathComponent(
            NoteGotoOpenLogStore.fileName,
            isDirectory: false
        )
        quarantineURL = supportDirectory.appendingPathComponent(
            NoteGotoOpenLogStore.quarantineFileName,
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let supportDirectory {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: supportDirectory.path
            )
        }
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testVaultHashIsStableAndHexWithoutPath() {
        let first = NoteGotoOpenLogStore.vaultHash(for: "/tmp/vault")
        let second = NoteGotoOpenLogStore.vaultHash(for: "/tmp/vault")
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(first.allSatisfy(\.isHexDigit))
        XCTAssertNotEqual(first, NoteGotoOpenLogStore.vaultHash(for: "/tmp/other"))
        // Same FNV-1a scheme as the inbox route key.
        let expected = "/tmp/vault".utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        XCTAssertEqual(first, String(expected, radix: 16))
    }

    func testAppendLoadsPrunesAndSavesAtomically() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let store = NoteGotoOpenLogStore(fileURL: fileURL, now: { now })
        let vault = NoteGotoOpenLogStore.vaultHash(for: "/vault")
        store.append(NoteGotoOpenEvent(vault: vault, notePath: "a.md", at: now))
        store.append(
            NoteGotoOpenEvent(
                vault: vault,
                notePath: "b.md",
                at: now.addingTimeInterval(10)
            )
        )

        let loaded = store.load()
        XCTAssertEqual(loaded.map(\.notePath), ["a.md", "b.md"])
        XCTAssertEqual(loaded.map(\.vault), [vault, vault])
    }

    func testLoadMissingReturnsEmptyWithoutCreatingAnything() {
        let missingParent = tempDirectory.appendingPathComponent("absent", isDirectory: true)
        let missingFile = missingParent.appendingPathComponent(
            NoteGotoOpenLogStore.fileName,
            isDirectory: false
        )
        let errors = NoteGotoErrorLog()
        let store = NoteGotoOpenLogStore(fileURL: missingFile, onError: { errors.append($0) })

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertTrue(errors.messages.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingParent.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingFile.path))
    }

    func testFirstAppendCreatesDirectory0700AndFile0600() throws {
        let store = NoteGotoOpenLogStore(fileURL: fileURL)
        store.append(
            NoteGotoOpenEvent(
                vault: "abc",
                notePath: "a.md",
                at: Date(timeIntervalSince1970: 100)
            )
        )

        XCTAssertEqual(try posixPermissions(at: supportDirectory), 0o700)
        XCTAssertEqual(try posixPermissions(at: fileURL), 0o600)
    }

    func testPrunesEventsOlderThan365DaysThenKeepsNewest500() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let store = NoteGotoOpenLogStore(fileURL: fileURL, now: { now })
        let vault = NoteGotoOpenLogStore.vaultHash(for: "/vault")
        let stale = NoteGotoOpenEvent(
            vault: vault,
            notePath: "old.md",
            at: now.addingTimeInterval(TimeInterval(-366 * 24 * 3_600))
        )
        store.append(stale)
        XCTAssertTrue(store.load().isEmpty)

        for index in 0..<505 {
            store.append(
                NoteGotoOpenEvent(
                    vault: vault,
                    notePath: "n\(index).md",
                    at: now.addingTimeInterval(TimeInterval(index))
                )
            )
        }
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 500)
        XCTAssertEqual(loaded.first?.notePath, "n5.md")
        XCTAssertEqual(loaded.last?.notePath, "n504.md")
    }

    func testMalformedJSONIsQuarantined() throws {
        try FileManager.default.createDirectory(
            at: supportDirectory, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: fileURL)
        let errors = NoteGotoErrorLog()
        let store = NoteGotoOpenLogStore(fileURL: fileURL, onError: { errors.append($0) })

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertEqual(try String(contentsOf: quarantineURL, encoding: .utf8), "{not-json")
        XCTAssertEqual(errors.messages, [NoteGotoOpenLogStore.unreadableQuarantinedMessage])
    }

    func testWrongSchemaIsQuarantined() throws {
        try FileManager.default.createDirectory(
            at: supportDirectory, withIntermediateDirectories: true)
        try Data(#"{"schema_version":2,"opens":[]}"#.utf8).write(to: fileURL)
        let errors = NoteGotoErrorLog()
        let store = NoteGotoOpenLogStore(fileURL: fileURL, onError: { errors.append($0) })

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertEqual(errors.messages, [NoteGotoOpenLogStore.unreadableQuarantinedMessage])
    }

    func testFileUsesISO8601DatesAndVaultHashes() throws {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let store = NoteGotoOpenLogStore(fileURL: fileURL, now: { date })
        store.append(NoteGotoOpenEvent(vault: "deadbeef", notePath: "a.md", at: date))

        let raw = try Data(contentsOf: fileURL)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: raw) as? [String: Any]
        )
        XCTAssertEqual(json["schema_version"] as? Int, 1)
        let opens = try XCTUnwrap(json["opens"] as? [[String: Any]])
        XCTAssertEqual(opens.count, 1)
        XCTAssertEqual(opens[0]["vault"] as? String, "deadbeef")
        XCTAssertEqual(opens[0]["note_path"] as? String, "a.md")
        let at = try XCTUnwrap(opens[0]["at"] as? String)
        XCTAssertTrue(at.contains("T"), at)
    }

    func testResetDeletesFileAndQuarantine() throws {
        let now = Date()
        let store = NoteGotoOpenLogStore(fileURL: fileURL, now: { now })
        store.append(NoteGotoOpenEvent(vault: "v", notePath: "a.md", at: now))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        try FileManager.default.createDirectory(
            at: supportDirectory, withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: quarantineURL)
        store.reset()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertTrue(store.load().isEmpty)
    }

    func testDefaultFileURLUsesLiteralBundleIdentifier() throws {
        let url = try NoteGotoOpenLogStore.defaultFileURL()
        XCTAssertEqual(url.lastPathComponent, NoteGotoOpenLogStore.fileName)
        XCTAssertEqual(
            url.deletingLastPathComponent().lastPathComponent,
            NoteGotoOpenLogStore.bundleIdentifier
        )
    }

    private func posixPermissions(at url: URL) throws -> UInt16 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let value = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return value.uint16Value
    }
}

private final class NoteGotoErrorLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ message: String) {
        lock.lock()
        storage.append(message)
        lock.unlock()
    }
}
