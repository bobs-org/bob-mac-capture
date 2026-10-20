import CaptureCore
import Combine
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class CapturePanelPublishTests: XCTestCase {
    func testIdenticalTargetSnapshotDoesNotPublish() {
        let model = CapturePanelModel()
        let snapshot = CaptureTargetsSnapshot(
            targets: CaptureTargetsResponse(
                ok: true,
                targets: [
                    CaptureTarget(
                        route: "today",
                        name: "today",
                        label: "today.md",
                        kind: "daily",
                        relativePath: "daily/today.md"
                    )
                ]
            ),
            refreshedAt: Date(timeIntervalSince1970: 1),
            stale: false,
            errorDescription: nil
        )
        model.updateTargetCacheSnapshot(snapshot)

        var published = 0
        let cancellable = model.objectWillChange.sink { published += 1 }
        model.updateTargetCacheSnapshot(
            CaptureTargetsSnapshot(
                targets: snapshot.targets,
                refreshedAt: Date(timeIntervalSince1970: 2),
                stale: false,
                errorDescription: nil
            )
        )
        XCTAssertEqual(published, 0)
        XCTAssertEqual(model.targetCacheSnapshot.refreshedAt, snapshot.refreshedAt)
        XCTAssertNotNil(cancellable)
    }

    func testIdenticalTemplateRefreshDoesNotPublishModel() async throws {
        let shelf = SavedTemplateShelf(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
            )
        )
        shelf.refresh(reason: .launch)
        await waitUntil { shelf.availability == .available }

        let model = CapturePanelModel(savedTemplateShelf: shelf)
        var published = 0
        let cancellable = model.objectWillChange.sink { published += 1 }
        let firstRefresh = shelf.lastRefreshedAt
        shelf.refresh(reason: .submit)
        await waitUntil { shelf.lastRefreshedAt != firstRefresh }
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(published, 0)
        XCTAssertNotNil(cancellable)
    }

    func testIdenticalAgendaRefreshDoesNotPublishModel() async throws {
        let store = CaptureAgendaStore(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
            ),
            vaultRootPath: "/vault",
            today: { "2026-08-28" },
            defaultCenter: NotificationCenter()
        )
        let model = CapturePanelModel()
        model.agendaStore = store
        store.refresh(reason: .show)
        await waitUntil { store.status == .ready }

        var published = 0
        let cancellable = model.objectWillChange.sink { published += 1 }
        let firstRefresh = store.lastRefreshedAt
        store.refresh(reason: .show)
        await waitUntil { store.lastRefreshedAt != firstRefresh }
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(published, 0)
        XCTAssertNotNil(cancellable)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }
}
