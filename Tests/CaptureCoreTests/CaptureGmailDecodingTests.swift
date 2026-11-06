import Foundation
import XCTest

@testable import CaptureCore

final class CaptureGmailDecodingTests: XCTestCase {
    private func fixtureData(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/\(name)"))
    }

    private func decodeSuccess(_ data: Data) throws -> CaptureCommandSuccess {
        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = decoded else {
            throw CaptureFixtureError.expectedSuccess
        }
        return success
    }

    private func fakeBobPath() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Tests/Fixtures/fake-bob").path
    }

    func testParseFixtureReportsGmailUrlSpanWithThreadKeyAndVerdict() throws {
        let parse = try JSONDecoder().decode(
            CaptureParseResponse.self, from: fixtureData("capture-parse-gmail.json"))

        XCTAssertEqual(parse.mode, "task")
        XCTAssertEqual(parse.spans.count, 1)
        let span = try XCTUnwrap(parse.spans.first)
        XCTAssertEqual(span.kind, "gmail_url")
        XCTAssertEqual(span.start, 10)
        XCTAssertEqual(span.end, 82)
        XCTAssertEqual(span.key, "1a0b9eb2cc26ab96")
        XCTAssertNil(span.title)
        XCTAssertEqual(
            span.gmail,
            CaptureGmailSpanMetadata(
                verdict: "decoded", dateHint: "2026-09-19T13:46:32.514+00:00"))
    }

    func testGmailUrlPaintsExactlyLikeRefUrl() {
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "gmail_url"), .link)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "ref_url"), .link)
        let span = CaptureSpan(start: 0, end: 8, kind: "gmail_url")
        XCTAssertEqual(captureSemanticCategory(forSpan: span), .link)
        XCTAssertTrue(captureSemanticCategory(forSpanKind: "gmail_url").isUnderlined)
    }

    func testOlderSpanWithoutGmailFieldsDecodesAsNil() throws {
        let span = try JSONDecoder().decode(
            CaptureSpan.self,
            from: Data(
                """
                {"start":0,"end":24,"kind":"gmail_url"}
                """.utf8
            )
        )

        XCTAssertEqual(span.kind, "gmail_url")
        XCTAssertNil(span.key)
        XCTAssertNil(span.title)
        XCTAssertNil(span.gmail)
    }

    func testKnownSpanKeepsThreadKeyTitleAndVerdict() throws {
        let span = try JSONDecoder().decode(
            CaptureSpan.self,
            from: Data(
                """
                {"start":0,"end":24,"kind":"gmail_url","key":"1a0b9eb2cc26ab96",
                 "title":"✉️ Lease renewal for 14 Elm St · Dana Whitfield",
                 "gmail":{"verdict":"known"}}
                """.utf8
            )
        )

        XCTAssertEqual(span.key, "1a0b9eb2cc26ab96")
        XCTAssertEqual(span.title, "✉️ Lease renewal for 14 Elm St · Dana Whitfield")
        XCTAssertEqual(span.gmail, CaptureGmailSpanMetadata(verdict: "known"))
    }

    func testDryRunFixtureReportsPerItemGmailPreviewLine() throws {
        let success = try decodeSuccess(fixtureData("capture-gmail-dry-run.json"))
        let captures = success.normalizedCaptures

        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(
            captures[0].gmail,
            [
                CaptureGmailPreview(
                    url: "https://mail.google.com/mail/u/0/#inbox/FMfcgzQhWTsNRgxMhQNwhZDfgqwXpPsx",
                    verdict: "decoded",
                    threadID: "1a0b9eb2cc26ab96",
                    dateHint: "2026-09-19T13:46:32.514+00:00",
                    message: "✉️ Gmail thread · Sep 19, 2026 · will link after capture")
            ])
    }

    func testOlderDryRunWithoutGmailDecodesAsEmpty() throws {
        let success = try decodeSuccess(
            """
            {"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"",
             "relative_target":"mac_inbox.md","target":"/tmp/vault/mac_inbox.md",
             "text":"Buy milk","task_line":"- [ ] #task Buy milk","kind":"task",
             "created":"2026-11-06","placement":"created"}
            """.data(using: .utf8)!
        )

        XCTAssertTrue(success.gmail.isEmpty)
    }

    func testPeekResolvedFixtureDecodesSubjectSenderAndMessage() throws {
        let peek = try JSONDecoder().decode(
            CaptureGmailPeekResponse.self, from: fixtureData("gmail-peek-resolved.json"))

        XCTAssertTrue(peek.ok)
        XCTAssertEqual(peek.schemaVersion, 1)
        XCTAssertEqual(peek.verdict, "resolved")
        XCTAssertEqual(peek.threadID, "1a0b9eb2cc26ab96")
        XCTAssertEqual(peek.subject, "Lease renewal for 14 Elm St")
        XCTAssertEqual(peek.who, "Dana Whitfield")
        XCTAssertEqual(peek.messages, 3)
        XCTAssertEqual(
            peek.message, "✉️ Lease renewal for 14 Elm St · Dana Whitfield · 3 messages · Nov 3")
    }

    func testPeekUnresolvableFixtureKeepsOfflineLine() throws {
        let peek = try JSONDecoder().decode(
            CaptureGmailPeekResponse.self, from: fixtureData("gmail-peek-unresolvable.json"))

        XCTAssertTrue(peek.ok)
        XCTAssertEqual(peek.verdict, "unresolvable")
        XCTAssertNil(peek.threadID)
        XCTAssertEqual(peek.message, "Gmail link could not be resolved")
    }

    func testGmailPeekRunsOnItsOwnLaneAndDecodesJSON() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_GMAIL_PEEK_FIXTURE": "gmail-peek-resolved.json",
            ]
        )

        let url = "https://mail.google.com/mail/u/0/#inbox/FMfcgzQhWTsNRgxMhQNwhZDfgqwXpPsx"
        let response = try await client.gmailPeek(url)

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.verdict, "resolved")
        XCTAssertEqual(
            response.message,
            "✉️ Lease renewal for 14 Elm St · Dana Whitfield · 3 messages · Nov 3")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=gmail peek \(url) -f json"))
    }

    func testGmailPeekUnsupportedCommandIsRememberedForThisBobIdentity() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_GMAIL_PEEK_UNSUPPORTED": "1",
            ]
        )

        for _ in 0..<2 {
            do {
                _ = try await client.gmailPeek("https://mail.google.com/mail/u/0/#all/abc123")
                XCTFail("Expected unsupported command")
            } catch BobClientError.unsupportedCommand(let command) {
                XCTAssertEqual(command, "gmail peek")
            }
        }

        XCTAssertTrue(client.gmailPeekKnownUnsupported)
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=gmail peek").count - 1, 1)
    }

    func testUnsupportedPeekFailureMatchesClapSpelling() {
        XCTAssertTrue(BobProcessClient.isUnsupportedGmailPeekFailure(
            exitStatus: 2, stderr: "error: unrecognized subcommand 'peek'"))
        XCTAssertTrue(BobProcessClient.isUnsupportedGmailPeekFailure(
            exitStatus: 2, stderr: "error: unrecognized subcommand 'gmail'"))
        XCTAssertFalse(BobProcessClient.isUnsupportedGmailPeekFailure(
            exitStatus: 1, stderr: "error: unrecognized subcommand 'peek'"))
        XCTAssertFalse(BobProcessClient.isUnsupportedGmailPeekFailure(
            exitStatus: 2, stderr: "gog could not complete a read-only Gmail request"))
    }
}

private enum CaptureFixtureError: Error {
    case expectedSuccess
}
