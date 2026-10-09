import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

/// Decoding, outcome, and presentation tests for the `bob ref scan`
/// JSON report. Fixtures are synthetic but keep the live key set.
final class RefsScanTests: XCTestCase {
    // MARK: Decoding

    func testCreatedFixtureDecodes() throws {
        let response = try decode("refs-scan-created.json")

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.mode, "write")
        XCTAssertTrue(response.writePDFs)
        XCTAssertEqual(
            response.intake,
            [RefsScanIntakeMove(from: "xlib/chat/omni_report.pdf", to: "lib/chat/omni_report.pdf")]
        )
        XCTAssertEqual(response.summary.created, 2)
        XCTAssertEqual(response.summary.updated, 1)
        XCTAssertEqual(response.summary.pdfs, 348)
        XCTAssertEqual(response.notes.count, 3)
        XCTAssertEqual(response.notes[0].action, "create")
        XCTAssertEqual(response.notes[0].path, "ref/chat/omni_report.md")
        XCTAssertEqual(response.notes[0].title, "Omni Report")
        XCTAssertEqual(response.notes[0].refType, "chat")
        XCTAssertEqual(response.notes[0].sourcePDF, "lib/chat/omni_report.pdf")
        XCTAssertFalse(response.notes[0].marker)
        XCTAssertTrue(response.failures.isEmpty)
        XCTAssertNil(response.error)
    }

    func testNothingFixtureDecodes() throws {
        let response = try decode("refs-scan-nothing.json")

        XCTAssertTrue(response.ok)
        XCTAssertTrue(response.notes.isEmpty)
        XCTAssertTrue(response.failures.isEmpty)
        XCTAssertNil(response.error)
        XCTAssertEqual(response.summary.unchanged, 348)
    }

    func testSyncedFixtureDecodes() throws {
        let response = try decode("refs-scan-synced.json")

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.notes.count, 2)
        XCTAssertTrue(response.notes.allSatisfy { $0.action == "update" })
        XCTAssertTrue(response.notes[1].marker)
    }

    func testPartialFixtureDecodes() throws {
        let response = try decode("refs-scan-partial.json")

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.notes.count, 1)
        XCTAssertEqual(response.failures.count, 2)
        XCTAssertEqual(response.failures[0].pdf, "lib/papers/blank_scan.pdf")
        XCTAssertEqual(response.failures[0].stage, "plan")
        XCTAssertEqual(response.failures[1].stage, "write")
        XCTAssertNil(response.error)
    }

    func testDirtyFixtureDecodes() throws {
        let response = try decode("refs-scan-dirty.json")

        XCTAssertFalse(response.ok)
        XCTAssertTrue(response.notes.isEmpty)
        let problem = try XCTUnwrap(response.error)
        XCTAssertEqual(problem.code, "dirty_targets")
        XCTAssertEqual(problem.message, "refusing to modify dirty vault files")
        XCTAssertEqual(
            problem.hint,
            "commit, stash, or clean those paths, then scan again"
        )
        XCTAssertEqual(problem.paths.count, 4)
    }

    func testSchema2FixtureDecodesWithVersion2() throws {
        let response = try decode("refs-scan-schema2.json")

        // The envelope decodes; the caller rejects it: `scan()` expects
        // schema 1, so this version never becomes an outcome.
        XCTAssertEqual(response.schemaVersion, 2)
        XCTAssertNotEqual(response.schemaVersion, 1)
    }

    func testLossyNotesSkipEntriesWithoutActionOrPath() throws {
        let response = try JSONDecoder().decode(
            RefsScanResponse.self,
            from: Data("""
            {"ok":true,"schema_version":1,"notes":\
            [{"action":"create","path":"ref/chat/kept.md"},\
            {"action":"create"},\
            {"path":"ref/chat/no_action.md"},\
            {"title":"Neither"}]}
            """.utf8)
        )

        XCTAssertEqual(response.notes.map(\.path), ["ref/chat/kept.md"])
    }

    func testLossyFailuresSkipEntriesWithoutPDFOrMessage() throws {
        let response = try JSONDecoder().decode(
            RefsScanResponse.self,
            from: Data("""
            {"ok":false,"schema_version":1,"failures":\
            [{"pdf":"lib/a.pdf","message":"kept"},\
            {"pdf":"lib/b.pdf"},\
            {"message":"no pdf"}]}
            """.utf8)
        )

        XCTAssertEqual(response.failures.map(\.pdf), ["lib/a.pdf"])
    }

    func testMissingOptionalFieldsDefault() throws {
        let response = try JSONDecoder().decode(
            RefsScanResponse.self,
            from: Data("""
            {"schema_version":1}
            """.utf8)
        )

        XCTAssertFalse(response.ok)
        XCTAssertNil(response.mode)
        XCTAssertFalse(response.writePDFs)
        XCTAssertTrue(response.intake.isEmpty)
        XCTAssertEqual(response.summary, RefsScanSummary())
        XCTAssertTrue(response.notes.isEmpty)
        XCTAssertTrue(response.failures.isEmpty)
        XCTAssertNil(response.error)
    }

    func testMissingNoteOptionalsDefault() throws {
        let response = try JSONDecoder().decode(
            RefsScanResponse.self,
            from: Data("""
            {"schema_version":1,"notes":[{"action":"create","path":"ref/chat/x.md"}]}
            """.utf8)
        )

        let note = try XCTUnwrap(response.notes.first)
        XCTAssertNil(note.title)
        XCTAssertNil(note.refType)
        XCTAssertNil(note.sourcePDF)
        XCTAssertFalse(note.marker)
    }

    func testMissingProblemPathsDefaultToEmpty() throws {
        let response = try JSONDecoder().decode(
            RefsScanResponse.self,
            from: Data("""
            {"schema_version":1,\
            "error":{"code":"scan_busy","message":"another bob ref scan is still running"}}
            """.utf8)
        )

        XCTAssertEqual(response.error?.paths, [])
        XCTAssertNil(response.error?.hint)
    }

    func testUnknownFieldsAreIgnored() throws {
        let response = try JSONDecoder().decode(
            RefsScanResponse.self,
            from: Data("""
            {"ok":true,"schema_version":1,"future_flag":true,\
            "notes":[{"action":"create","path":"ref/chat/x.md","future":1}],\
            "summary":{"pdfs":1,"future":2}}
            """.utf8)
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.notes.count, 1)
        XCTAssertEqual(response.summary.pdfs, 1)
    }

    // MARK: Outcome

    func testCreatedOutcomeIsSucceeded() throws {
        let outcome = try outcomeFor("refs-scan-created.json")

        XCTAssertEqual(outcome.kind, .succeeded)
        XCTAssertEqual(outcome.created.map(\.path), [
            "ref/chat/omni_report.md",
            "ref/papers/harness_notes.md",
        ])
        XCTAssertEqual(outcome.syncedNoteCount, 1)
        XCTAssertEqual(outcome.intakeCount, 1)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertNil(outcome.problem)
    }

    func testNothingOutcomeIsSucceeded() throws {
        let outcome = try outcomeFor("refs-scan-nothing.json")

        XCTAssertEqual(outcome.kind, .succeeded)
        XCTAssertTrue(outcome.created.isEmpty)
        XCTAssertEqual(outcome.syncedNoteCount, 0)
    }

    func testPartialOutcomeKeepsCreatedOrder() throws {
        let outcome = try outcomeFor("refs-scan-partial.json")

        XCTAssertEqual(outcome.kind, .partial)
        XCTAssertEqual(outcome.created.map(\.path), ["ref/chat/fresh_report.md"])
        XCTAssertEqual(outcome.failures.count, 2)
        XCTAssertNil(outcome.problem)
    }

    func testFailedOutcomeCarriesTheProblem() throws {
        let outcome = try outcomeFor("refs-scan-dirty.json")

        XCTAssertEqual(outcome.kind, .failed)
        XCTAssertEqual(outcome.problem?.code, "dirty_targets")
        XCTAssertTrue(outcome.created.isEmpty)
    }

    func testTransportProblemOutcomeIsFailed() throws {
        let outcome = RefsScanOutcome(
            problem: RefsScanProblem(code: "timed_out", message: "stopped", hint: "retry"),
            finishedAt: Date()
        )

        XCTAssertEqual(outcome.kind, .failed)
        XCTAssertEqual(outcome.problem?.code, "timed_out")
        XCTAssertTrue(outcome.created.isEmpty)
        XCTAssertTrue(outcome.failures.isEmpty)
    }

    func testDiagnosticText() throws {
        let partial = try outcomeFor("refs-scan-partial.json")
        XCTAssertEqual(
            partial.diagnostic,
            """
            bob ref scan -w -f json
            kind: partial
            lib/papers/blank_scan.pdf [plan]: no extractable text on pages 1-3
            lib/chat/noisy_report.pdf [write]: reference note changed during sync; rerun
            """
        )

        let failed = try outcomeFor("refs-scan-dirty.json")
        XCTAssertEqual(
            failed.diagnostic,
            """
            bob ref scan -w -f json
            kind: failed
            dirty_targets: refusing to modify dirty vault files
            hint: commit, stash, or clean those paths, then scan again
            paths: ref/chat/omni_report.md, ref/papers/attention_review.md, \
            ref/chat/standup_notes.md, ref/papers/harness_notes.md
            """
        )

        let succeeded = try outcomeFor("refs-scan-nothing.json")
        XCTAssertEqual(succeeded.diagnostic, "bob ref scan -w -f json\nkind: succeeded")
    }

    // MARK: Presentation

    func testScanningText() {
        XCTAssertEqual(RefsScanPresentation.scanningText(elapsed: 0), "Scanning library…")
        XCTAssertEqual(RefsScanPresentation.scanningText(elapsed: 4.9), "Scanning library…")
        XCTAssertEqual(RefsScanPresentation.scanningText(elapsed: 5), "Scanning library… 5 s")
        XCTAssertEqual(RefsScanPresentation.scanningText(elapsed: 7.6), "Scanning library… 7 s")
    }

    func testFooterSucceeded() throws {
        let created = try outcomeFor("refs-scan-created.json")
        XCTAssertEqual(
            RefsScanPresentation.footerText(created, searchMode: false),
            "Added 2 references"
        )
        XCTAssertEqual(
            RefsScanPresentation.footerText(created, searchMode: true),
            "Added 2 references · esc shows them"
        )

        let one = RefsScanOutcome(
            response: RefsScanResponse(ok: true, notes: [
                RefsScanNote(action: "create", path: "ref/chat/only.md", title: "Only"),
            ]),
            finishedAt: Date()
        )
        XCTAssertEqual(
            RefsScanPresentation.footerText(one, searchMode: false),
            "Added 1 reference"
        )
        XCTAssertEqual(
            RefsScanPresentation.footerText(one, searchMode: true),
            "Added 1 reference · esc shows them"
        )

        let nothing = try outcomeFor("refs-scan-nothing.json")
        XCTAssertEqual(
            RefsScanPresentation.footerText(nothing, searchMode: false),
            "No new references"
        )

        let synced = try outcomeFor("refs-scan-synced.json")
        XCTAssertEqual(
            RefsScanPresentation.footerText(synced, searchMode: false),
            "No new references · 2 notes synced"
        )

        let oneSynced = RefsScanOutcome(
            response: RefsScanResponse(ok: true, notes: [
                RefsScanNote(action: "update", path: "ref/chat/x.md"),
            ]),
            finishedAt: Date()
        )
        XCTAssertEqual(
            RefsScanPresentation.footerText(oneSynced, searchMode: false),
            "No new references · 1 note synced"
        )
    }

    func testFooterPartialAndFailed() throws {
        let partial = try outcomeFor("refs-scan-partial.json")
        XCTAssertEqual(
            RefsScanPresentation.footerText(partial, searchMode: false),
            "Added 1 · 2 PDFs failed"
        )

        let partialAlone = RefsScanOutcome(
            response: RefsScanResponse(ok: false, failures: [
                RefsScanFailure(pdf: "lib/a.pdf", message: "boom"),
            ]),
            finishedAt: Date()
        )
        XCTAssertEqual(
            RefsScanPresentation.footerText(partialAlone, searchMode: false),
            "1 PDF failed to scan"
        )

        let partialMany = RefsScanOutcome(
            response: RefsScanResponse(ok: false, failures: [
                RefsScanFailure(pdf: "lib/a.pdf", message: "x"),
                RefsScanFailure(pdf: "lib/b.pdf", message: "y"),
                RefsScanFailure(pdf: "lib/c.pdf", message: "z"),
            ]),
            finishedAt: Date()
        )
        XCTAssertEqual(
            RefsScanPresentation.footerText(partialMany, searchMode: false),
            "3 PDFs failed to scan"
        )

        let oneEach = RefsScanOutcome(
            response: RefsScanResponse(ok: false, notes: [
                RefsScanNote(action: "create", path: "ref/chat/n.md", title: "N"),
            ], failures: [
                RefsScanFailure(pdf: "lib/a.pdf", message: "x"),
            ]),
            finishedAt: Date()
        )
        XCTAssertEqual(
            RefsScanPresentation.footerText(oneEach, searchMode: false),
            "Added 1 · 1 PDF failed"
        )

        let failed = try outcomeFor("refs-scan-dirty.json")
        XCTAssertEqual(
            RefsScanPresentation.footerText(failed, searchMode: false),
            "Scan failed · ⌘S to retry"
        )
    }

    func testBannerMessage() throws {
        let succeeded = try outcomeFor("refs-scan-created.json")
        XCTAssertNil(RefsScanPresentation.bannerMessage(succeeded))

        let partial = try outcomeFor("refs-scan-partial.json")
        XCTAssertEqual(
            RefsScanPresentation.bannerMessage(partial),
            """
            2 PDFs couldn't be scanned.
            lib/papers/blank_scan.pdf — no extractable text on pages 1-3
            +1 more · Copy Diagnostic lists them all
            """
        )

        let single = RefsScanOutcome(
            response: RefsScanResponse(ok: false, failures: [
                RefsScanFailure(pdf: "lib/a.pdf", stage: "plan", message: "boom"),
            ]),
            finishedAt: Date()
        )
        XCTAssertEqual(
            RefsScanPresentation.bannerMessage(single),
            "1 PDF couldn't be scanned.\nlib/a.pdf — boom"
        )

        let failed = try outcomeFor("refs-scan-dirty.json")
        XCTAssertEqual(
            RefsScanPresentation.bannerMessage(failed),
            """
            Bob couldn't scan your library.
            refusing to modify dirty vault files
            ref/chat/omni_report.md, ref/papers/attention_review.md, \
            ref/chat/standup_notes.md, +1 more
            commit, stash, or clean those paths, then scan again
            """
        )

        let bare = RefsScanOutcome(
            problem: RefsScanProblem(code: "transport", message: "lost"),
            finishedAt: Date()
        )
        XCTAssertEqual(
            RefsScanPresentation.bannerMessage(bare),
            "Bob couldn't scan your library.\nlost"
        )
    }

    func testNotification() throws {
        let succeeded = try outcomeFor("refs-scan-created.json")
        let createdNote = try XCTUnwrap(RefsScanPresentation.notification(succeeded))
        XCTAssertEqual(createdNote.title, "Added 2 references")
        XCTAssertEqual(createdNote.body, "Omni Report · What harness buys you")

        let nothing = try outcomeFor("refs-scan-nothing.json")
        XCTAssertNil(RefsScanPresentation.notification(nothing))

        let synced = try outcomeFor("refs-scan-synced.json")
        XCTAssertNil(RefsScanPresentation.notification(synced))

        let partial = try outcomeFor("refs-scan-partial.json")
        let partialNote = try XCTUnwrap(RefsScanPresentation.notification(partial))
        XCTAssertEqual(partialNote.title, "Added 1 reference · 2 PDFs failed")
        XCTAssertEqual(
            partialNote.body,
            "lib/papers/blank_scan.pdf — no extractable text on pages 1-3"
        )

        let partialAlone = RefsScanOutcome(
            response: RefsScanResponse(ok: false, failures: [
                RefsScanFailure(pdf: "lib/a.pdf", message: "boom"),
                RefsScanFailure(pdf: "lib/b.pdf", message: "bam"),
                RefsScanFailure(pdf: "lib/c.pdf", message: "bat"),
            ]),
            finishedAt: Date()
        )
        let aloneNote = try XCTUnwrap(RefsScanPresentation.notification(partialAlone))
        XCTAssertEqual(aloneNote.title, "3 PDFs couldn't be scanned")
        XCTAssertEqual(aloneNote.body, "lib/a.pdf — boom")

        let failed = try outcomeFor("refs-scan-dirty.json")
        let failedNote = try XCTUnwrap(RefsScanPresentation.notification(failed))
        XCTAssertEqual(failedNote.title, "Bob Refs scan failed")
        XCTAssertEqual(failedNote.body, "refusing to modify dirty vault files")
    }

    func testNotificationBodyTruncatesTitles() {
        let outcome = RefsScanOutcome(
            response: RefsScanResponse(ok: true, notes: (1...5).map {
                RefsScanNote(action: "create", path: "ref/chat/n\($0).md", title: "Note \($0)")
            }),
            finishedAt: Date()
        )

        let note = try? XCTUnwrap(RefsScanPresentation.notification(outcome))
        XCTAssertEqual(note?.title, "Added 5 references")
        XCTAssertEqual(note?.body, "Note 1 · Note 2 · Note 3 · +2 more")
    }

    func testAnnouncement() throws {
        let succeeded = try outcomeFor("refs-scan-created.json")
        XCTAssertEqual(
            RefsScanPresentation.announcement(succeeded),
            "Scan added 2 references"
        )

        let nothing = try outcomeFor("refs-scan-nothing.json")
        XCTAssertEqual(RefsScanPresentation.announcement(nothing), "No new references")

        let partial = try outcomeFor("refs-scan-partial.json")
        XCTAssertEqual(
            RefsScanPresentation.announcement(partial),
            "Scan added 1 reference; 2 PDFs failed"
        )

        let partialAlone = RefsScanOutcome(
            response: RefsScanResponse(ok: false, failures: [
                RefsScanFailure(pdf: "lib/a.pdf", message: "boom"),
            ]),
            finishedAt: Date()
        )
        XCTAssertEqual(
            RefsScanPresentation.announcement(partialAlone),
            "1 PDF failed to scan"
        )

        let failed = try outcomeFor("refs-scan-dirty.json")
        XCTAssertEqual(RefsScanPresentation.announcement(failed), "Scan failed")
    }

    func testDisplayTitleFallsBackToStem() {
        XCTAssertEqual(
            RefsScanPresentation.displayTitle(
                for: RefsScanNote(
                    action: "create",
                    path: "ref/chat/omni_report.md",
                    title: "Omni `Report`"
                )
            ),
            "Omni Report"
        )
        XCTAssertEqual(
            RefsScanPresentation.displayTitle(
                for: RefsScanNote(action: "create", path: "ref/chat/omni_report.md")
            ),
            "omni_report"
        )
    }

    // MARK: Helpers

    private func decode(_ name: String) throws -> RefsScanResponse {
        try JSONDecoder().decode(RefsScanResponse.self, from: fixtureData(name))
    }

    private func outcomeFor(_ name: String) throws -> RefsScanOutcome {
        RefsScanOutcome(response: try decode(name), finishedAt: Date())
    }

    private func fixtureData(_ name: String) throws -> Data {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(
            contentsOf: packageRoot.appendingPathComponent("Tests/Fixtures/\(name)")
        )
    }
}
