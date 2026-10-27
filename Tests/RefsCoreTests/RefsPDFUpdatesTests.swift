import Foundation
import XCTest

@testable import RefsCore

final class RefsPDFUpdatesTests: XCTestCase {
    func testNewScanFieldsDecodeLossilyAndOlderBobDefaultsEmpty() throws {
        let response = try decode(scanJSON)

        XCTAssertEqual(response.generatedAt, "2026-10-23T10:15:00Z")
    XCTAssertEqual(response.summary.held, 4)
    XCTAssertEqual(response.held.count, 4)
        XCTAssertEqual(
      response.held.map(\.reason), [
        "editor_active", "coordination_timeout", "marker_changed", "dirty_targets",
      ])
        XCTAssertEqual(response.notes.count, 4)
        XCTAssertEqual(response.notes[0].markerWrite?.mode, "coordinated")
        XCTAssertTrue(try XCTUnwrap(response.notes[0].markerWrite).editorSavedFirst)
        XCTAssertEqual(
            response.notes[0].markerWrite?.status, RefsScanStatusChange(from: "ready", to: "next"))
        XCTAssertNil(response.notes[3].markerWrite)

        let old = try decode("{\"schema_version\":1}")
        XCTAssertNil(old.generatedAt)
        XCTAssertEqual(old.summary.held, 0)
        XCTAssertTrue(old.held.isEmpty)
        XCTAssertNil(old.notes.first?.markerWrite)
    }

    func testClassifierSeparatesOpenQuietAndHoldReasons() throws {
        let response = try decode(scanJSON)
        let updates = RefsPDFUpdates(
            response: response,
            openTabFileNames: ["tab-open.pdf"]
        )

        XCTAssertEqual(
            updates.refreshedOpen.map(\.path),
            [
                "ref/papers/saved_first.md",
                "ref/papers/tab_open.md",
            ])
        XCTAssertEqual(updates.refreshedQuiet.map(\.path), ["ref/papers/quiet.md"])
        XCTAssertEqual(updates.readingHolds.map(\.pdf), ["lib/reading.pdf"])
        XCTAssertEqual(updates.busyHolds.map(\.pdf), ["lib/busy.pdf"])
        XCTAssertEqual(updates.changedHolds.map(\.pdf), ["lib/changed.pdf"])
    XCTAssertEqual(updates.dirtyHolds.map(\.pdf), ["lib/local.pdf"])
        XCTAssertEqual(updates.busyHoldDedupeKeys, ["busy:lib/busy.pdf"])
    }

    func testSingleRefreshCopyUsesRefsStateVocabularyAndSavedFirstClause() throws {
        let response = try decode(scanJSON)
        let updates = RefsPDFUpdates(response: response)
        let notice = try XCTUnwrap(RefsPDFUpdatePresentation.notifications(for: updates).first)

        XCTAssertEqual(notice.title, "Updated in Highlights")
        XCTAssertEqual(notice.subtitle, "Saved First")
        XCTAssertEqual(notice.body, "Ready → Next · your unsaved highlights were saved first")
        XCTAssertEqual(notice.notePath, "ref/papers/saved_first.md")
    }

    func testSingleRefreshWithoutStatusChangeUsesPageNoteCopy() throws {
        let note = RefsScanNote(
            action: "update",
            path: "ref/papers/paper.md",
            title: "Paper",
            sourcePDF: "lib/paper.pdf",
            markerWrite: RefsScanMarkerWrite(mode: "coordinated")
        )
        let updates = RefsPDFUpdates(
            response: RefsScanResponse(notes: [note]),
            openTabFileNames: ["paper.pdf"]
        )
        let notice = try XCTUnwrap(RefsPDFUpdatePresentation.notifications(for: updates).first)

        XCTAssertEqual(notice.body, "Page-1 note updated")
    }

    func testStatusCopyUsesEveryRefsStateLabel() {
        let transitions = [
            ("wip", "next", "Reading → Next"),
            ("next", "ready", "Next → Ready"),
            ("ready", "read", "Ready → Read"),
            ("read", "abandoned", "Read → Dropped"),
            ("abandoned", "wip", "Dropped → Reading"),
        ]

        for (from, to, expected) in transitions {
            let note = RefsScanNote(
                action: "update",
                path: "ref/papers/paper.md",
                title: "Paper",
                sourcePDF: "lib/paper.pdf",
                markerWrite: RefsScanMarkerWrite(
                    mode: "coordinated",
                    status: RefsScanStatusChange(from: from, to: to)
                )
            )
            let updates = RefsPDFUpdates(
                response: RefsScanResponse(notes: [note]),
                openTabFileNames: ["paper.pdf"]
            )
            let notice = RefsPDFUpdatePresentation.notifications(for: updates)[0]

            XCTAssertEqual(notice.body, expected)
        }
    }

    func testSeveralRefreshesGroupTitlesAndFooterClauses() throws {
        let first = RefsScanNote(
            action: "update",
            path: "ref/papers/a.md",
            title: "Paper A",
            sourcePDF: "lib/a.pdf",
            markerWrite: RefsScanMarkerWrite(mode: "coordinated", editorSavedFirst: true)
        )
        let second = RefsScanNote(
            action: "update",
            path: "ref/papers/b.md",
            title: "Paper B",
            sourcePDF: "lib/b.pdf",
            markerWrite: RefsScanMarkerWrite(mode: "coordinated", editorSavedFirst: true)
        )
        let updates = RefsPDFUpdates(
            response: RefsScanResponse(
                notes: [first, second],
                held: [
                    hold("lib/reading.pdf", reason: "editor_active"),
                    hold("lib/changed.pdf", reason: "marker_changed"),
                ])
        )
        let notice = RefsPDFUpdatePresentation.notifications(for: updates)[0]

        XCTAssertEqual(notice.title, "Updated 2 PDFs in Highlights")
        XCTAssertEqual(notice.subtitle, nil)
        XCTAssertEqual(notice.body, "Paper A · Paper B")
        XCTAssertEqual(
            RefsPDFUpdatePresentation.footerClauses(for: updates),
            ["2 PDFs refreshed in Highlights", "2 PDFs waiting while you read"]
        )
    }

    func testGroupedRefreshTitlesShowThreeAndRemainder() {
        let notes = (1...4).map { index in
            RefsScanNote(
                action: "update",
                path: "ref/papers/paper\(index).md",
                title: "Paper \(index)",
                sourcePDF: "lib/paper\(index).pdf",
                markerWrite: RefsScanMarkerWrite(mode: "coordinated", editorSavedFirst: true)
            )
        }
        let updates = RefsPDFUpdates(response: RefsScanResponse(notes: notes))
        let notice = RefsPDFUpdatePresentation.notifications(for: updates)[0]

        XCTAssertEqual(notice.title, "Updated 4 PDFs in Highlights")
        XCTAssertEqual(notice.body, "Paper 1 · Paper 2 · Paper 3 · +1 more")
    }

    func testBusyHoldCopyAndPerPDFDedupeKey() {
        let busy = hold("lib/busy.pdf", reason: "coordination_timeout", title: "Deep Work")
        let updates = RefsPDFUpdates(response: RefsScanResponse(held: [busy]))
        let notice = RefsPDFUpdatePresentation.notifications(for: updates)[0]
        let banner = RefsPDFUpdatePresentation.busyBanner(for: updates)

        XCTAssertEqual(notice.title, "Highlights needs you")
        XCTAssertEqual(notice.subtitle, "Deep Work")
        XCTAssertEqual(
            notice.body,
            "Highlights didn't answer — a dialog may be open. Bob will update this PDF once it's free."
        )
        XCTAssertEqual(notice.notePath, "ref/papers/busy.md")
        XCTAssertEqual(notice.dedupeKey, "busy:lib/busy.pdf")
        XCTAssertEqual(
            banner,
            RefsPDFUpdateBanner(
                title: "Highlights needs you",
                message:
                    "Highlights didn't answer — a dialog may be open. Bob will update this PDF once it's free.",
                actionTitle: "Scan Again"
            )
        )
    }

    func testNeedsOpenTabCheckOnlyForCoordinatedWritesWithoutSavedFirst() {
        XCTAssertFalse(RefsPDFUpdates.needsOpenTabCheck(RefsScanResponse()))
        let savedFirst = RefsScanNote(
            action: "update",
            path: "ref/a.md",
            sourcePDF: "lib/a.pdf",
            markerWrite: RefsScanMarkerWrite(mode: "coordinated", editorSavedFirst: true)
        )
        XCTAssertFalse(
            RefsPDFUpdates.needsOpenTabCheck(RefsScanResponse(notes: [savedFirst]))
        )
        let coordinated = RefsScanNote(
            action: "update",
            path: "ref/b.md",
            sourcePDF: "lib/b.pdf",
            markerWrite: RefsScanMarkerWrite(mode: "coordinated")
        )
        XCTAssertTrue(
            RefsPDFUpdates.needsOpenTabCheck(RefsScanResponse(notes: [coordinated]))
        )
    }

    func testTabFileNamesIncludeBasenames() {
        let snapshot = HighlightsTabsSnapshot(
            windows: [
                .init(
                    isMain: true,
                    tabs: [
                        .init(fileName: "paper.pdf", isSelected: true),
                        .init(fileName: "/tmp/lib/other.pdf", isSelected: false),
                    ]
                )
            ],
            highlightsIsFrontmost: true
        )
        XCTAssertEqual(
            RefsPDFUpdates.tabFileNames(from: snapshot),
            ["paper.pdf", "/tmp/lib/other.pdf", "other.pdf"]
        )
    }

    func testSurfaceHidesNotificationsWhenVisibleOrDisabledAndDedupesBusyHolds() {
        let busy = hold("lib/busy.pdf", reason: "coordination_timeout", title: "Deep Work")
        let saved = RefsScanNote(
            action: "update",
            path: "ref/papers/saved_first.md",
            title: "Saved First",
            sourcePDF: "lib/saved_first.pdf",
            markerWrite: RefsScanMarkerWrite(mode: "coordinated", editorSavedFirst: true)
        )
        let updates = RefsPDFUpdates(
            response: RefsScanResponse(notes: [saved], held: [busy])
        )

        let visible = RefsPDFUpdatePresentation.surface(
            for: updates,
            panelVisible: true,
            notificationsEnabled: true,
            previouslyNotifiedBusyKeys: []
        )
        XCTAssertTrue(visible.notifications.isEmpty)
        XCTAssertEqual(visible.footerClauses, ["1 PDF refreshed in Highlights"])
        XCTAssertNotNil(visible.banner)
        XCTAssertEqual(visible.nextNotifiedBusyKeys, ["busy:lib/busy.pdf"])

        let disabled = RefsPDFUpdatePresentation.surface(
            for: updates,
            panelVisible: false,
            notificationsEnabled: false,
            previouslyNotifiedBusyKeys: []
        )
        XCTAssertTrue(disabled.notifications.isEmpty)
        XCTAssertEqual(disabled.footerClauses, ["1 PDF refreshed in Highlights"])

        let firstHidden = RefsPDFUpdatePresentation.surface(
            for: updates,
            panelVisible: false,
            notificationsEnabled: true,
            previouslyNotifiedBusyKeys: []
        )
        XCTAssertEqual(firstHidden.notifications.count, 2)
        XCTAssertEqual(
            firstHidden.notifications.map(\.title),
            ["Updated in Highlights", "Highlights needs you"]
        )

        let secondHidden = RefsPDFUpdatePresentation.surface(
            for: updates,
            panelVisible: false,
            notificationsEnabled: true,
            previouslyNotifiedBusyKeys: firstHidden.nextNotifiedBusyKeys
        )
        XCTAssertEqual(secondHidden.notifications.map(\.title), ["Updated in Highlights"])
    }

    func testQuietRefreshAndNonBusyHoldsDoNotNotify() {
        let quiet = RefsScanNote(
            action: "update",
            path: "ref/papers/quiet.md",
            sourcePDF: "lib/quiet.pdf",
            markerWrite: RefsScanMarkerWrite(mode: "direct")
        )
        let updates = RefsPDFUpdates(
            response: RefsScanResponse(
                notes: [quiet],
                held: [
                    hold("lib/reading.pdf", reason: "editor_active"),
                    hold("lib/changed.pdf", reason: "marker_changed"),
                ]))

        XCTAssertTrue(RefsPDFUpdatePresentation.notifications(for: updates).isEmpty)
        XCTAssertNil(RefsPDFUpdatePresentation.busyBanner(for: updates))
        XCTAssertEqual(
            RefsPDFUpdatePresentation.footerClauses(for: updates),
            ["2 PDFs waiting while you read"]
        )
    }

  func testDirtyHoldsHaveRetryFooterWithoutBusyWarningOrNotification() {
    let one = hold("lib/local.pdf", reason: "dirty_targets")
    let two = hold("lib/other-local.pdf", reason: "dirty_targets")
    let updates = RefsPDFUpdates(response: RefsScanResponse(held: [one, two]))
    let surface = RefsPDFUpdatePresentation.surface(
      for: updates,
      panelVisible: false,
      notificationsEnabled: true,
      previouslyNotifiedBusyKeys: []
    )

    XCTAssertEqual(updates.dirtyHolds.map(\.pdf), ["lib/local.pdf", "lib/other-local.pdf"])
    XCTAssertEqual(
      surface.footerClauses,
      ["2 PDFs held for local changes · retrying next scan"]
    )
    XCTAssertNil(surface.banner)
    XCTAssertTrue(surface.notifications.isEmpty)

    let single = RefsPDFUpdates(response: RefsScanResponse(held: [one]))
    XCTAssertEqual(
      RefsPDFUpdatePresentation.footerClauses(for: single),
      ["1 PDF held for local changes · retrying next scan"]
    )
  }

    private func hold(
        _ pdf: String,
        reason: String,
        title: String = "Hold"
    ) -> RefsScanHold {
        RefsScanHold(
            pdf: pdf,
            note: "ref/papers/\(URL(fileURLWithPath: pdf).deletingPathExtension().lastPathComponent).md",
            title: title,
            reason: reason,
            message: "retrying"
        )
    }

    private func decode(_ json: String) throws -> RefsScanResponse {
        try JSONDecoder().decode(RefsScanResponse.self, from: Data(json.utf8))
    }

    private var scanJSON: String {
        #"""
        {
          "ok": true,
          "schema_version": 1,
          "generated_at": "2026-10-23T10:15:00Z",
          "summary": { "held": 4 },
          "notes": [
            {
              "action": "update", "path": "ref/papers/saved_first.md",
              "title": "Saved First", "source_pdf": "lib/saved_first.pdf", "marker": true,
              "marker_write": {
                "mode": "coordinated", "editor_saved_first": true,
                "status": { "from": "ready", "to": "next" }
              }
            },
            {
              "action": "update", "path": "ref/papers/tab_open.md",
              "title": "Tab Open", "source_pdf": "lib/tab-open.pdf", "marker": true,
              "marker_write": { "mode": "coordinated", "editor_saved_first": false }
            },
            {
              "action": "update", "path": "ref/papers/quiet.md",
              "title": "Quiet", "source_pdf": "lib/quiet.pdf", "marker": true,
              "marker_write": { "mode": "direct", "editor_saved_first": false }
            },
            { "action": "update", "path": "ref/papers/no_marker_write.md" }
          ],
          "held": [
            {
              "pdf": "lib/reading.pdf", "note": "ref/papers/reading.md",
              "title": "Reading", "reason": "editor_active", "message": "reading"
            },
            {
              "pdf": "lib/busy.pdf", "note": "ref/papers/busy.md",
              "title": "Busy", "reason": "coordination_timeout", "message": "busy"
            },
            {
              "pdf": "lib/changed.pdf", "note": "ref/papers/changed.md",
              "title": "Changed", "reason": "marker_changed", "message": "changed"
            },
        {
          "pdf": "lib/local.pdf", "note": "ref/papers/local.md",
          "title": "Local", "reason": "dirty_targets",
          "message": "dirty vault targets: ref/papers/local.md · retrying next scan"
        },
            { "pdf": "lib/malformed.pdf", "reason": "coordination_timeout" }
          ]
        }
        """#
    }
}
