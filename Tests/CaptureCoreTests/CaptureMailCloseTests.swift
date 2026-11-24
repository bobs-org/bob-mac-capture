import CaptureCore
import XCTest

final class CaptureMailCloseTests: XCTestCase {
    private func decodeSuccess(_ text: String) throws -> CaptureCommandSuccess {
        try JSONDecoder().decode(CaptureCommandSuccess.self, from: Data(text.utf8))
    }

    private func decodeFailure(_ text: String) throws -> CaptureCommandFailure {
        try JSONDecoder().decode(CaptureCommandFailure.self, from: Data(text.utf8))
    }

    func testSuccessDecodesMailClose() throws {
        let json = """
        {"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"inbox.md","relative_target":"inbox.md","target":"inbox.md","text":"x!","task_line":"- [x] #task Do","kind":"task_toggle","created":"2026-11-24","placement":"inserted","mail_close":{"digest":"abc123def456","verb":"complete","title":"Complete this email task?","subtitle":"job.md · Ready → Done","tone":"warning","consequence":"Ada is waiting.","confirm":"bob capture --mail-close abc123def456 -- 'x!'","tasks":[{"path":"job.md","line":42,"block_id":"yogi","before":" ","after":"x","verb":"complete","label":"✉️ Title · Ada","turn_line":"↩ Ada · 2h — waiting on your reply","mails":[{"note":"mail/2026/a.md","title":"Title","who":"Ada","turn":"yours","turn_since":"2026-11-24T00:00:00","gmail_url":"https://mail.google.com/x"}]}]}}
        """
        let success = try decodeSuccess(json)
        let report = try XCTUnwrap(success.mailClose)
        XCTAssertEqual(report.digest, "abc123def456")
        XCTAssertEqual(report.tone, "warning")
        XCTAssertTrue(report.isWarning)
        XCTAssertEqual(report.tasks.count, 1)
        XCTAssertEqual(report.tasks.first?.label, "✉️ Title · Ada")
        XCTAssertEqual(report.tasks.first?.mails.first?.gmailURL, "https://mail.google.com/x")
    }

    func testSuccessWithoutMailCloseDecodesAsNil() throws {
        let json = """
        {"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"inbox.md","relative_target":"inbox.md","target":"inbox.md","text":"hi","task_line":"- [ ] #task hi","kind":"task","created":"2026-11-24","placement":"inserted"}
        """
        let success = try decodeSuccess(json)
        XCTAssertNil(success.mailClose)
    }

    func testFailureDecodesMailClose() throws {
        let json = """
        {"ok":false,"error":"closes email task","code":"mail_close_confirmation_required","mail_close":{"digest":"deadbeef1234","verb":"cancel","title":"Cancel this email task?","subtitle":"job.md · Ready → Cancelled","tone":"calm","consequence":"Another open task still watches this thread.","confirm":"bob capture --mail-close deadbeef1234 -- 'x!'","tasks":[]}}
        """
        let failure = try decodeFailure(json)
        XCTAssertEqual(failure.code, "mail_close_confirmation_required")
        let report = try XCTUnwrap(failure.mailClose)
        XCTAssertEqual(report.digest, "deadbeef1234")
        XCTAssertFalse(report.isWarning)
    }

    func testFailureWithoutMailCloseDecodesAsNil() throws {
        let failure = try decodeFailure(
            #"{"ok":false,"error":"nope","code":"move_choice_required","move_choice":{"supported":true,"slots":[]}}"#)
        XCTAssertNil(failure.mailClose)
    }

    func testMalformedMailCloseDegradesToNil() throws {
        let json = """
        {"ok":false,"error":"nope","code":"mail_close_confirmation_required","mail_close":"broken"}
        """
        let failure = try decodeFailure(json)
        XCTAssertNil(failure.mailClose)
    }
}
