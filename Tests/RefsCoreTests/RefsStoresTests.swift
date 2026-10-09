import Foundation
import XCTest

@testable import RefsCore

/// Store tests: snapshot round-trips, corruption quarantine, file modes, the
/// open-log prune rules, and frecency math.
final class RefsStoresTests: XCTestCase {
    private var tempDirectory: URL!
    private var snapshotURL: URL!
    private var snapshotQuarantineURL: URL!
    private var openLogURL: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("refs-stores-tests-\(UUID().uuidString)", isDirectory: true)
        let support = tempDirectory.appendingPathComponent("support", isDirectory: true)
        snapshotURL = support.appendingPathComponent(
            RefsSnapshotStore.fileName,
            isDirectory: false
        )
        snapshotQuarantineURL = support.appendingPathComponent(
            RefsSnapshotStore.quarantineFileName,
            isDirectory: false
        )
        openLogURL = support.appendingPathComponent(
            RefsOpenLogStore.fileName,
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let support = snapshotURL?.deletingLastPathComponent() {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: support.path
            )
        }
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testSnapshotRoundTripsSnapshotAndToday() throws {
        let response = try JSONDecoder().decode(
            RefsListResponse.self,
            from: RefsModelTests.fixtureData("refs-list.json")
        )
        let snapshot = RefsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_760_000_000),
            records: response.refs,
            gitAddedDates: ["ref/blogs/small_opened.md": "2026-09-11"]
        )
        let today = RefsToday(entries: [
            "ref/chat/small_reading.md": RefsTodayEntry(order: 0, pomodoroName: "BLOG"),
        ])
        let errors = RefsErrorLog()
        let store = RefsSnapshotStore(fileURL: snapshotURL, onError: { errors.append($0) })

        store.save(snapshot: snapshot, today: today)
        let loaded = store.load()

        XCTAssertEqual(loaded.snapshot, snapshot)
        XCTAssertEqual(loaded.today, today)
        XCTAssertTrue(errors.messages.isEmpty)
        XCTAssertEqual(try posixPermissions(at: snapshotURL), 0o600)
        XCTAssertEqual(
            try posixPermissions(at: snapshotURL.deletingLastPathComponent()),
            0o700
        )
    }

    func testSnapshotLoadMissingStartsEmptyWithoutCreatingDirectories() {
        let store = RefsSnapshotStore(
            fileURL: tempDirectory
                .appendingPathComponent("nope", isDirectory: true)
                .appendingPathComponent(RefsSnapshotStore.fileName, isDirectory: false)
        )

        let loaded = store.load()

        XCTAssertNil(loaded.snapshot)
        XCTAssertNil(loaded.today)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDirectory.appendingPathComponent("nope").path
            )
        )
    }

    func testSnapshotCorruptionQuarantinesAndReports() throws {
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not json".write(to: snapshotURL, atomically: true, encoding: .utf8)
        let errors = RefsErrorLog()
        let store = RefsSnapshotStore(fileURL: snapshotURL, onError: { errors.append($0) })

        let loaded = store.load()

        XCTAssertNil(loaded.snapshot)
        XCTAssertEqual(errors.messages, [RefsSnapshotStore.unreadableQuarantinedMessage])
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotQuarantineURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    }

    func testSnapshotSchemaMismatchQuarantines() throws {
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"schema_version":99}"#.write(to: snapshotURL, atomically: true, encoding: .utf8)
        let store = RefsSnapshotStore(fileURL: snapshotURL)

        XCTAssertNil(store.load().snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotQuarantineURL.path))
    }

    func testOpenLogAppendsLoadsAndResets() {
        let store = RefsOpenLogStore(fileURL: openLogURL)
        let first = RefsOpenEvent(path: "ref/chat/x.md", at: Date(timeIntervalSince1970: 100))
        let second = RefsOpenEvent(path: "ref/chat/y.md", at: Date(timeIntervalSince1970: 200))

        store.append(first)
        store.append(second)

        XCTAssertEqual(store.load(), [first, second])

        store.reset()

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: openLogURL.path))
    }

    func testOpenLogPrunesStaleEvents() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let store = RefsOpenLogStore(fileURL: openLogURL, now: { now })
        let stale = RefsOpenEvent(
            path: "ref/chat/old.md",
            at: now.addingTimeInterval(TimeInterval(-366 * 24 * 3_600))
        )
        let fresh = RefsOpenEvent(
            path: "ref/chat/new.md",
            at: now.addingTimeInterval(-100)
        )

        store.append(stale)
        store.append(fresh)

        XCTAssertEqual(store.load(), [fresh])
    }

    func testOpenLogKeepsOnlyTheNewestTwoThousand() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let store = RefsOpenLogStore(fileURL: openLogURL, now: { now })
        for index in 0..<2_005 {
            store.append(
                RefsOpenEvent(
                    path: "ref/chat/\(index).md",
                    at: now.addingTimeInterval(TimeInterval(index))
                )
            )
        }

        let loaded = store.load()

        XCTAssertEqual(loaded.count, 2_000)
        XCTAssertEqual(loaded.first?.path, "ref/chat/5.md")
        XCTAssertEqual(loaded.last?.path, "ref/chat/2004.md")
    }

    func testOpenLogCorruptionQuarantines() throws {
        try FileManager.default.createDirectory(
            at: openLogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not json".write(to: openLogURL, atomically: true, encoding: .utf8)
        let errors = RefsErrorLog()
        let store = RefsOpenLogStore(fileURL: openLogURL, onError: { errors.append($0) })

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertEqual(errors.messages, [RefsOpenLogStore.unreadableQuarantinedMessage])
    }

    func testGoldenOpenLogMatchesTheStoreCodec() throws {
        let data = try RefsModelTests.fixtureData("refs-open-log-golden.json")
        let file = try RefsStoreCodecs.decoder().decode(RefsOpenLogFile.self, from: data)

        XCTAssertEqual(file.schemaVersion, 1)
        XCTAssertEqual(file.opens.count, 9)
        XCTAssertEqual(
            file.opens.filter { $0.path == "ref/chat/omnigent_launch_review.md" }.count,
            3
        )
    }

    func testOpenStatsLastOpenedCountAndFrecency() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let day: TimeInterval = 86_400
        let stats = RefsOpenStats(
            events: [
                RefsOpenEvent(path: "ref/chat/x.md", at: now),
                RefsOpenEvent(path: "ref/chat/x.md", at: now.addingTimeInterval(-14 * day)),
                RefsOpenEvent(path: "ref/chat/y.md", at: now.addingTimeInterval(-28 * day)),
            ],
            now: now
        )

        XCTAssertEqual(stats.lastOpened("ref/chat/x.md"), now)
        XCTAssertEqual(stats.count("ref/chat/x.md"), 2)
        XCTAssertEqual(stats.count("ref/chat/missing.md"), 0)
        XCTAssertNil(stats.lastOpened("ref/chat/missing.md"))
        XCTAssertEqual(stats.frecency("ref/chat/x.md"), 1.5, accuracy: 1e-9)
        XCTAssertEqual(stats.frecency("ref/chat/y.md"), 0.25, accuracy: 1e-9)
        XCTAssertEqual(stats.frecency("ref/chat/missing.md"), 0)
        XCTAssertEqual(stats.maxFrecency, 1.5, accuracy: 1e-9)
        XCTAssertEqual(RefsOpenStats(events: [], now: now).maxFrecency, 0)
    }

    private func posixPermissions(at url: URL) throws -> UInt16 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let value = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return value.uint16Value
    }
}

private final class RefsErrorLog: @unchecked Sendable {
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
