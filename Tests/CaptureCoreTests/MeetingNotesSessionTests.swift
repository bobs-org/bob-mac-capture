import Foundation
import XCTest

@testable import CaptureCore

@MainActor
final class MeetingNotesSessionTests: XCTestCase {
    private var testsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func list(_ name: String = "list.json") throws -> MeetingNotesListResponse {
        let data = try Data(
            contentsOf: testsRoot.appendingPathComponent("Fixtures/meeting-notes/\(name)"))
        return try JSONDecoder().decode(MeetingNotesListResponse.self, from: data)
    }

    private func response(_ name: String) throws -> MeetingNotesResponse {
        let data = try Data(
            contentsOf: testsRoot.appendingPathComponent("Fixtures/meeting-notes/\(name)"))
        return try JSONDecoder().decode(MeetingNotesResponse.self, from: data)
    }

    private func response(_ name: String, eventRef: String?) throws -> MeetingNotesResponse {
        let original = try JSONSerialization.jsonObject(with: fixtureData(name)) as! [String: Any]
        var payload = original
        if var meeting = payload["meeting"] as? [String: Any] {
            if let eventRef {
                meeting["ref"] = eventRef
            } else {
                meeting["ref"] = NSNull()
            }
            payload["meeting"] = meeting
        }
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(MeetingNotesResponse.self, from: encoded)
    }

    private func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: testsRoot.appendingPathComponent("Fixtures/meeting-notes/\(name)"))
    }

    private func makeSession(
        listHandler: @escaping FakeMeetingNotesProcess.ListHandler,
        previewHandler: @escaping FakeMeetingNotesProcess.PreviewHandler,
        fileHandler: @escaping FakeMeetingNotesProcess.FileHandler
    ) -> (MeetingNotesSession, FakeMeetingNotesProcess) {
        let process = FakeMeetingNotesProcess(
            listHandler: listHandler,
            previewHandler: previewHandler,
            fileHandler: fileHandler
        )
        return (MeetingNotesSession(process: process), process)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "Condition did not become true before timeout")
    }

    func testListAndPreviewSettleIndependentlyAndAutoMatchIsPinnedForOneWrite() async throws {
        let rows = try list()
        let preview = try response("preview.json")
        let filed = try response("filed.json")
        let (session, process) = makeSession(
            listHandler: {
                await delayIgnoringCancellation(0.2)
                return rows
            },
            previewHandler: { _ in preview },
            fileHandler: { _ in
                await delayIgnoringCancellation(0.05)
                return filed
            }
        )
        var refreshes = 0
        var receipts = 0
        session.onRefresh = { refreshes += 1 }
        session.onReceipt = { _ in receipts += 1 }

        session.enter()
        await waitUntil { session.state == .previewReady }
        XCTAssertEqual(session.listState, .loading)
        XCTAssertTrue(session.canFile)
        XCTAssertNil(process.previewRequests.first?.eventToken)

        session.file()
        session.file()
        await waitUntil { session.state == .filed }
        await waitUntil { session.listState == .loaded }

        XCTAssertEqual(session.state, .filed)
        XCTAssertEqual(process.fileRequests.count, 1)
        XCTAssertEqual(process.fileRequests.first?.options.eventToken, "20261124#^spruce-sync")
        XCTAssertEqual(process.fileRequests.first?.sha256, String(repeating: "a", count: 64))
        XCTAssertNil(process.fileRequests.first?.options.status)
        XCTAssertEqual(session.response?.outcome, .filed)
        XCTAssertTrue(session.canOpenFiledNote)
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(receipts, 1)
    }

    func testOutOfOrderPreviewCannotReplaceNewEventSelection() async throws {
        let rows = try list()
        let old = try response("preview.json", eventRef: "old#^event")
        let current = try response("explicit-preview.json", eventRef: "new#^event")
        let filed = try response("filed.json")
        let (session, process) = makeSession(
            listHandler: { rows },
            previewHandler: { options in
                if options.eventToken == "old#^event" {
                    await delayIgnoringCancellation(0.2)
                    return old
                }
                return current
            },
            fileHandler: { _ in filed }
        )

        session.enter(eventToken: "old#^event")
        session.selectMeeting(eventToken: "new#^event")
        await waitUntil { session.state == .previewReady }
        XCTAssertEqual(session.eventToken, "new#^event")
        XCTAssertEqual(session.response?.meeting?.eventRef, "new#^event")
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(session.response?.meeting?.eventRef, "new#^event")
        XCTAssertEqual(process.previewRequests.map(\.eventToken), ["old#^event", "new#^event"])
    }

    func testChangingStatusInvalidatesApprovalAndKeepsConfiguredDefaultInitially() async throws {
        let rows = try list()
        let preview = try response("preview.json")
        let filed = try response("filed.json")
        let (session, process) = makeSession(
            listHandler: { rows },
            previewHandler: { _ in preview },
            fileHandler: { _ in filed }
        )
        session.enter()
        await waitUntil { session.state == .previewReady }
        XCTAssertNil(process.previewRequests[0].status)
        XCTAssertTrue(session.canFile)

        session.chooseNext()
        await waitUntil { session.state == .previewReady && process.previewRequests.count == 2 }
        XCTAssertEqual(process.previewRequests.last?.status, .next)
        XCTAssertEqual(session.previewOptions?.status, .next)
        XCTAssertTrue(session.canFile)

        session.chooseRead()
        await waitUntil { session.state == .previewReady && process.previewRequests.count == 3 }
        XCTAssertEqual(process.previewRequests.last?.status, .read)
    }

    func testParentChoiceAndReplaceRequireFreshPreviewBeforeWriting() async throws {
        let rows = try list()
        let needsParent = try response("needs-parent.json")
        let alreadyFiled = try response("already-filed.json")
        let preview = try response("preview.json")
        let filed = try response("filed.json")
        let (session, process) = makeSession(
            listHandler: { rows },
            previewHandler: { options in
                if options.parent == nil { return needsParent }
                if !options.overwrite { return alreadyFiled }
                return preview
            },
            fileHandler: { _ in filed }
        )

        session.enter(eventToken: "20261124#^spruce-sync")
        await waitUntil { session.state == .choosingParent }
        XCTAssertEqual(session.parentChoices.map(\.route), ["team", "studio"])
        session.chooseParent(route: "studio")
        await waitUntil { session.state == .confirmingReplace }
        XCTAssertEqual(session.existing?.note, "ref/meetings/261124_juniper_systems_planning.md")
        XCTAssertFalse(session.canFile)

        session.confirmReplace()
        await waitUntil { session.state == .previewReady }
        XCTAssertEqual(process.previewRequests.map(\.parent), [nil, "studio", "studio"])
        XCTAssertEqual(process.previewRequests.last?.overwrite, true)
        XCTAssertTrue(session.canFile)
        session.file()
        await waitUntil { session.state == .filed }
        XCTAssertEqual(process.fileRequests.single?.options.parent, "studio")
        XCTAssertTrue(process.fileRequests.single?.options.overwrite == true)
    }

    func testRowsWithoutEventReferencesCannotBeSelected() async throws {
        let rows = try list()
        let ambiguous = try response("ambiguous.json")
        let preview = try response("preview.json")
        let filed = try response("filed.json")
        let (session, process) = makeSession(
            listHandler: { rows },
            previewHandler: { options in options.eventToken == nil ? ambiguous : preview },
            fileHandler: { _ in filed }
        )
        session.enter()
        await waitUntil { session.state == .choosingMeeting && session.meetingChoices.count == 2 }
        let tokenless = try XCTUnwrap(session.meetingChoices.first { $0.eventRef == nil })
        session.selectMeeting(tokenless)
        XCTAssertEqual(process.previewRequests.count, 1)
        XCTAssertNil(session.eventToken)
        XCTAssertEqual(process.previewRequests.first?.eventToken, nil)

        let selectable = try XCTUnwrap(session.meetingChoices.first { $0.eventRef != nil })
        session.selectMeeting(selectable)
        await waitUntil { session.state == .previewReady }
        XCTAssertEqual(session.eventToken, "20261124#^spruce-sync")
    }

    func testNotesChangedRepreviewsWithoutAutomaticallyFilingAgain() async throws {
        let rows = try list()
        let preview = try response("preview.json")
        let changed = try response("notes-changed.json")
        let replies = LockedCounter()
        let (session, process) = makeSession(
            listHandler: { rows },
            previewHandler: { _ in preview },
            fileHandler: { _ in
                replies.increment()
                return changed
            }
        )
        session.enter()
        await waitUntil { session.state == .previewReady }
        session.file()
        await waitUntil { session.state == .previewReady && process.previewRequests.count == 2 }

        XCTAssertEqual(replies.value, 1)
        XCTAssertEqual(process.fileRequests.count, 1)
        XCTAssertTrue(session.notice?.contains("clipboard changed") == true)
        XCTAssertTrue(session.canFile, "The new preview needs a separate Return")
    }

    func testNoNotesShowsCalmRetryState() async throws {
        let rows = try list()
        let noNotes = try response("empty.json")
        let filed = try response("filed.json")
        let (session, process) = makeSession(
            listHandler: { rows },
            previewHandler: { _ in noNotes },
            fileHandler: { _ in filed }
        )
        session.enter()
        await waitUntil { session.state == .empty }
        XCTAssertFalse(session.canFile)
        XCTAssertTrue(session.notice?.contains("copy notes and retry") == true)
        XCTAssertTrue(process.fileRequests.isEmpty)
    }

    func testQueuedReceiptIsNotPresentedAsFiledOrOpenable() async throws {
        let rows = try list()
        let preview = try response("preview.json")
        let queued = try response("queued.json")
        let (session, process) = makeSession(
            listHandler: { rows },
            previewHandler: { _ in preview },
            fileHandler: { _ in queued }
        )
        var refreshes = 0
        session.onRefresh = { refreshes += 1 }

        session.enter()
        await waitUntil { session.state == .previewReady }
        session.file()
        await waitUntil { session.state == .queued }
        XCTAssertEqual(session.response?.outcome, .queued)
        XCTAssertNotNil(session.response?.queued)
        XCTAssertNotNil(session.queuedNextStep)
        XCTAssertFalse(session.canOpenExisting)
        XCTAssertFalse(session.canOpenFiledNote)
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(process.fileRequests.count, 1)
    }

    func testMissingEventIdentityOrNotesHashNeverEnablesReturn() async throws {
        let rows = try list()
        let noIdentity = try response("preview.json", eventRef: nil)
        let noHash = try response("preview-missing-hash.json")
        let filed = try response("filed.json")
        for preview in [noIdentity, noHash] {
            let (session, process) = makeSession(
                listHandler: { rows },
                previewHandler: { _ in preview },
                fileHandler: { _ in filed }
            )
            session.enter()
            await waitUntil { if case .recoverableError = session.state { true } else { false } }
            XCTAssertFalse(session.canFile)
            session.file()
            XCTAssertTrue(process.fileRequests.isEmpty)
        }
    }

    func testCloseDuringWriteDefersUntilReceiptIsObservable() async throws {
        let rows = try list()
        let preview = try response("preview.json")
        let filed = try response("filed.json")
        let gate = MeetingNotesResponseGate()
        let (session, process) = makeSession(
            listHandler: { rows },
            previewHandler: { _ in preview },
            fileHandler: { _ in await gate.wait() }
        )
        var refreshes = 0
        var receipts = 0
        session.onRefresh = { refreshes += 1 }
        session.onReceipt = { _ in receipts += 1 }

        session.enter()
        await waitUntil { session.state == .previewReady }
        session.file()
        await waitUntil { session.state == .writing && process.fileRequests.count == 1 }
        let cancellationsBeforeLeave = process.cancelCount
        session.leave()
        XCTAssertEqual(session.state, .writing)
        XCTAssertEqual(process.cancelCount, cancellationsBeforeLeave + 1)

        await gate.resolve(filed)
        await waitUntil { session.state == .filed }
        XCTAssertTrue(session.notice?.contains("Review the receipt") == true)
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(receipts, 1)
        session.file()
        XCTAssertEqual(process.fileRequests.count, 1)
    }
}

private final class FakeMeetingNotesProcess: MeetingNotesProcess, @unchecked Sendable {
    typealias ListHandler = () async throws -> MeetingNotesListResponse
    typealias PreviewHandler = (MeetingNotesOptions) async throws -> MeetingNotesResponse
    typealias FileHandler = (MeetingNotesFileRequest) async throws -> MeetingNotesResponse

    let listHandler: ListHandler
    let previewHandler: PreviewHandler
    let fileHandler: FileHandler
    private let lock = NSLock()
    private var storedPreviewRequests: [MeetingNotesOptions] = []
    private var storedFileRequests: [MeetingNotesFileRequest] = []
    private var storedCancelCount = 0
    private var storedRecheckCount = 0

    var meetingNotesKnownUnsupported: Bool { false }

    var previewRequests: [MeetingNotesOptions] { withLock { storedPreviewRequests } }
    var fileRequests: [MeetingNotesFileRequest] { withLock { storedFileRequests } }
    var cancelCount: Int { withLock { storedCancelCount } }
    var recheckCount: Int { withLock { storedRecheckCount } }

    init(
        listHandler: @escaping ListHandler, previewHandler: @escaping PreviewHandler,
        fileHandler: @escaping FileHandler
    ) {
        self.listHandler = listHandler
        self.previewHandler = previewHandler
        self.fileHandler = fileHandler
    }

    func meetingNotesList() async throws -> MeetingNotesListResponse {
        try await listHandler()
    }

    func meetingNotesPreview(_ options: MeetingNotesOptions) async throws -> MeetingNotesResponse {
        withLock { storedPreviewRequests.append(options) }
        return try await previewHandler(options)
    }

    func meetingNotesFile(_ request: MeetingNotesFileRequest) async throws -> MeetingNotesResponse {
        withLock { storedFileRequests.append(request) }
        return try await fileHandler(request)
    }

    func cancelMeetingNotesReads() {
        withLock { storedCancelCount += 1 }
    }

    func recheckMeetingNotesCapability() {
        withLock { storedRecheckCount += 1 }
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private actor MeetingNotesResponseGate {
    private var continuation: CheckedContinuation<MeetingNotesResponse, Never>?
    private var result: MeetingNotesResponse?

    func wait() async -> MeetingNotesResponse {
        if let result { return result }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(_ response: MeetingNotesResponse) {
        result = response
        continuation?.resume(returning: response)
        continuation = nil
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}

private func delayIgnoringCancellation(_ seconds: TimeInterval) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            continuation.resume()
        }
    }
}

extension Collection {
    fileprivate var single: Element? { count == 1 ? first : nil }
}
