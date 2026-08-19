import Foundation
import XCTest

@testable import CaptureCore

final class CanceledDraftStashStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var stashDirectory: URL!
    private var fileURL: URL!
    private var quarantineURL: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("canceled-draft-stash-tests-\(UUID().uuidString)", isDirectory: true)
        stashDirectory = tempDirectory.appendingPathComponent("support", isDirectory: true)
        fileURL = stashDirectory.appendingPathComponent(
            FileCanceledDraftStashStore.fileName,
            isDirectory: false
        )
        quarantineURL = stashDirectory.appendingPathComponent(
            FileCanceledDraftStashStore.quarantineFileName,
            isDirectory: false
        )
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let stashDirectory {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: stashDirectory.path
            )
        }
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testRoundTripsUnicodeTextIdsDatesAndNewestFirstOrder() {
        let newest = PersistedCanceledDraft(
            id: UUID(uuidString: "F0E1D2C3-B4A5-4678-9012-3456789ABCDE")!,
            text: "café\n- 子 task\n",
            createdAt: Date(timeIntervalSince1970: 1_755_561_234.5)
        )
        let oldest = PersistedCanceledDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            text: "older\nsecond line",
            createdAt: Date(timeIntervalSince1970: 1_755_561_000)
        )
        let errors = ErrorLog()
        let store = makeStore(onError: { errors.append($0) })

        store.save([newest, oldest])

        XCTAssertEqual(store.load(), [newest, oldest])
        XCTAssertTrue(errors.messages.isEmpty)
    }

    func testDuplicateTextsRoundTripAsDistinctEntries() {
        let first = PersistedCanceledDraft(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            text: "same draft",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let second = PersistedCanceledDraft(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            text: "same draft",
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let store = makeStore()

        store.save([second, first])
        let loaded = store.load()

        XCTAssertEqual(loaded, [second, first])
        XCTAssertEqual(loaded.map(\.text), ["same draft", "same draft"])
        XCTAssertNotEqual(loaded[0].id, loaded[1].id)
    }

    func testLoadOnMissingFileReturnsEmptyWithoutCreatingAnything() {
        let missingParent = tempDirectory.appendingPathComponent("absent", isDirectory: true)
        let missingFile = missingParent.appendingPathComponent(
            FileCanceledDraftStashStore.fileName,
            isDirectory: false
        )
        let errors = ErrorLog()
        let store = FileCanceledDraftStashStore(fileURL: missingFile, onError: { errors.append($0) })

        XCTAssertEqual(store.load(), [])
        XCTAssertTrue(errors.messages.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingParent.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingFile.path))
    }

    func testSaveEmptyDeletesStashAndQuarantineFiles() throws {
        try FileManager.default.createDirectory(at: stashDirectory, withIntermediateDirectories: true)
        try Data("stash".utf8).write(to: fileURL)
        try Data("corrupt".utf8).write(to: quarantineURL)
        let errors = ErrorLog()
        let store = makeStore(onError: { errors.append($0) })

        store.save([])

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stashDirectory.path))
        XCTAssertTrue(errors.messages.isEmpty)
    }

    func testMalformedJSONIsQuarantinedAndReportsOneError() throws {
        try FileManager.default.createDirectory(at: stashDirectory, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: fileURL)
        let errors = ErrorLog()
        let store = makeStore(onError: { errors.append($0) })

        XCTAssertEqual(store.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertEqual(try String(contentsOf: quarantineURL, encoding: .utf8), "{not-json")
        XCTAssertEqual(errors.messages, [FileCanceledDraftStashStore.unreadableQuarantinedMessage])
    }

    func testUnsupportedSchemaVersionIsQuarantined() throws {
        try FileManager.default.createDirectory(at: stashDirectory, withIntermediateDirectories: true)
        let future = """
            {
              "schemaVersion": 2,
              "drafts": [
                {
                  "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
                  "text": "keep me",
                  "createdAt": 100
                }
              ]
            }
            """
        try Data(future.utf8).write(to: fileURL)
        let errors = ErrorLog()
        let store = makeStore(onError: { errors.append($0) })

        XCTAssertEqual(store.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertEqual(errors.messages, [FileCanceledDraftStashStore.unreadableQuarantinedMessage])
    }

    func testFirstSaveCreatesDirectory0700AndFile0600() throws {
        let store = makeStore()

        store.save([sampleDraft(text: "first")])

        XCTAssertEqual(try posixPermissions(at: stashDirectory), 0o700)
        XCTAssertEqual(try posixPermissions(at: fileURL), 0o600)
    }

    func testSavingOverExistingFileReplacesContentsAndKeeps0600() throws {
        let store = makeStore()
        let replacement = sampleDraft(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            text: "replaced\n",
            createdAt: Date(timeIntervalSince1970: 50)
        )

        store.save([sampleDraft(text: "original")])
        store.save([replacement])

        XCTAssertEqual(store.load(), [replacement])
        XCTAssertEqual(try posixPermissions(at: fileURL), 0o600)
    }

    func testUnwritableParentReportsErrorWithoutTrapping() throws {
        try FileManager.default.createDirectory(at: stashDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: stashDirectory.path
        )
        let errors = ErrorLog()
        let store = makeStore(onError: { errors.append($0) })

        store.save([sampleDraft(text: "should not persist")])

        XCTAssertEqual(errors.messages.count, 1)
        XCTAssertTrue(
            errors.messages[0].hasPrefix("Canceled draft stash not saved: "),
            errors.messages[0]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDefaultFileURLUsesLiteralBundleIdentifier() throws {
        let url = try FileCanceledDraftStashStore.defaultFileURL()

        XCTAssertEqual(url.lastPathComponent, FileCanceledDraftStashStore.fileName)
        XCTAssertEqual(
            url.deletingLastPathComponent().lastPathComponent,
            FileCanceledDraftStashStore.bundleIdentifier
        )
    }

    private func makeStore(
        onError: @escaping @Sendable (String) -> Void = { _ in }
    ) -> FileCanceledDraftStashStore {
        FileCanceledDraftStashStore(fileURL: fileURL, onError: onError)
    }

    private func sampleDraft(
        id: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        text: String,
        createdAt: Date = Date(timeIntervalSince1970: 1)
    ) -> PersistedCanceledDraft {
        PersistedCanceledDraft(id: id, text: text, createdAt: createdAt)
    }

    private func posixPermissions(at url: URL) throws -> UInt16 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let value = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return value.uint16Value
    }
}

private final class ErrorLog: @unchecked Sendable {
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
