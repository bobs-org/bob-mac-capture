import XCTest

@testable import BobMacCapture
@testable import RefsCore

@MainActor
final class RefsScanReceiptObserverTests: XCTestCase {
    func testStartDoesNotReadAReceipt() {
        var registered = 0
        var cancelled: [Int32] = []
        let observer = RefsScanReceiptObserver(
            register: { _ in
                registered += 1
                return 7
            },
            cancel: { cancelled.append($0) }
        )
        var presented = 0
        observer.onSurface = { _, _ in presented += 1 }

        observer.start()
        XCTAssertEqual(registered, 1)
        XCTAssertEqual(presented, 0)

        observer.stop()
        XCTAssertEqual(cancelled, [7])
    }

    func testDuplicateContentHashIsDropped() async {
        let observer = RefsScanReceiptObserver(
            register: { _ in nil },
            cancel: { _ in }
        )
        var surfaces: [RefsPDFUpdateSurface] = []
        observer.onSurface = { _, surface in surfaces.append(surface) }
        observer.isPanelVisible = { false }
        observer.notificationsEnabled = { true }

        let first = RefsScanReceipt(
            response: RefsScanResponse(
                notes: [
                    RefsScanNote(
                        action: "update",
                        path: "ref/papers/a.md",
                        title: "A",
                        sourcePDF: "lib/a.pdf",
                        markerWrite: RefsScanMarkerWrite(
                            mode: "coordinated",
                            editorSavedFirst: true
                        )
                    )
                ]
            ),
            contentHash: 11
        )
        await observer.processForTests(first)
        await observer.processForTests(
            RefsScanReceipt(response: first.response, contentHash: 11)
        )
        await observer.processForTests(
            RefsScanReceipt(response: first.response, contentHash: 12)
        )

        XCTAssertEqual(surfaces.count, 2)
        XCTAssertEqual(surfaces[0].notifications.count, 1)
        XCTAssertEqual(surfaces[1].notifications.count, 1)
    }

    func testTabCheckRunsOnlyWhenNeededAndTrusted() async {
        let observer = RefsScanReceiptObserver(
            register: { _ in nil },
            cancel: { _ in }
        )
        var tabChecks = 0
        observer.openTabFileNames = {
            tabChecks += 1
            return ["tab-open.pdf"]
        }
        observer.isAccessibilityTrusted = { true }
        observer.isPanelVisible = { true }
        observer.notificationsEnabled = { true }
        var clauses: [String] = []
        observer.onSurface = { _, surface in clauses = surface.footerClauses }

        let savedFirst = RefsScanReceipt(
            response: RefsScanResponse(
                notes: [
                    RefsScanNote(
                        action: "update",
                        path: "ref/papers/a.md",
                        sourcePDF: "lib/a.pdf",
                        markerWrite: RefsScanMarkerWrite(
                            mode: "coordinated",
                            editorSavedFirst: true
                        )
                    )
                ]
            ),
            contentHash: 1
        )
        await observer.processForTests(savedFirst)
        XCTAssertEqual(tabChecks, 0)

        observer.isAccessibilityTrusted = { false }
        let coordinated = RefsScanReceipt(
            response: RefsScanResponse(
                notes: [
                    RefsScanNote(
                        action: "update",
                        path: "ref/papers/tab_open.md",
                        title: "Tab Open",
                        sourcePDF: "lib/tab-open.pdf",
                        markerWrite: RefsScanMarkerWrite(mode: "coordinated")
                    )
                ]
            ),
            contentHash: 2
        )
        await observer.processForTests(coordinated)
        XCTAssertEqual(tabChecks, 0)

        observer.isAccessibilityTrusted = { true }
        await observer.processForTests(
            RefsScanReceipt(response: coordinated.response, contentHash: 3)
        )
        XCTAssertEqual(tabChecks, 1)
        XCTAssertEqual(clauses, ["1 PDF refreshed in Highlights"])
    }

    func testBusyHoldIsNotifiedOnceUntilItStops() async {
        let observer = RefsScanReceiptObserver(
            register: { _ in nil },
            cancel: { _ in }
        )
        observer.isPanelVisible = { false }
        observer.notificationsEnabled = { true }
        var titles: [[String]] = []
        observer.onSurface = { _, surface in
            titles.append(surface.notifications.map(\.title))
        }

        let busy = RefsScanHold(
            pdf: "lib/busy.pdf",
            note: "ref/papers/busy.md",
            title: "Deep Work",
            reason: "coordination_timeout",
            message: "busy"
        )
        await observer.processForTests(
            RefsScanReceipt(response: RefsScanResponse(held: [busy]), contentHash: 1)
        )
        await observer.processForTests(
            RefsScanReceipt(response: RefsScanResponse(held: [busy]), contentHash: 2)
        )
        await observer.processForTests(
            RefsScanReceipt(response: RefsScanResponse(), contentHash: 3)
        )
        await observer.processForTests(
            RefsScanReceipt(response: RefsScanResponse(held: [busy]), contentHash: 4)
        )

        XCTAssertEqual(
            titles,
            [
                ["Highlights needs you"],
                [],
                [],
                ["Highlights needs you"],
            ]
        )
    }
}
