import XCTest

@testable import CaptureCore

final class MeetingNotesAgendaTests: XCTestCase {
    private func makeRow(
        kind: CaptureAgendaEventKind = .task,
        blockID: String? = "standup",
        eventRef: String? = "20261123#^standup",
        state: String? = "missing",
        phase: CaptureAgendaEventPhase? = .running,
        statusSymbol: String? = " ",
        statusType: String? = "TODO"
    ) -> CaptureAgendaEventRow {
        CaptureAgendaEventRow(
            line: 10,
            blockID: blockID,
            kind: kind,
            qualifier: nil,
            title: "Standup",
            timeRange: "13:00–13:30",
            startsAt: "2026-11-23T13:00",
            endsAt: "2026-11-23T13:30",
            durationMinutes: 30,
            phase: phase,
            statusSymbol: statusSymbol,
            statusType: statusType,
            offClock: false,
            root: nil,
            home: nil,
            joinURL: nil,
            calendarURL: "calshow:evt",
            location: nil,
            pomodoro: nil,
            buffer: nil,
            eventRef: eventRef,
            meetingNotes: state.map { CaptureAgendaMeetingNotes(state: $0) }
        )
    }

    func testOldBobRowWithoutNewFieldsOffersNoAction() throws {
        let data = """
        {"line":10,"kind":"task","title":"Standup"}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(CaptureAgendaEventRow.self, from: data)
        XCTAssertNil(row.eventRef)
        XCTAssertNil(row.meetingNotes)
        XCTAssertFalse(row.offersMeetingNotesAction)
    }

    func testNewBobStartedRowOffersNotesAction() throws {
        let data = """
        {
          "line":10,
          "block_id":"standup",
          "kind":"task",
          "title":"Standup",
          "phase":"running",
          "status_symbol":" ",
          "status_type":"TODO",
          "event_ref":"20261123#^standup",
          "meeting_notes":{"state":"missing"}
        }
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(CaptureAgendaEventRow.self, from: data)
        XCTAssertEqual(row.eventRef, "20261123#^standup")
        XCTAssertEqual(row.meetingNotes?.state, "missing")
        XCTAssertTrue(row.offersMeetingNotesAction)
    }

    func testEndedStartedRowStillOffersNotesAction() {
        XCTAssertTrue(makeRow(phase: .ended).offersMeetingNotesAction)
    }

    func testFutureRowOffersNoAction() {
        XCTAssertFalse(makeRow(phase: .upcoming).offersMeetingNotesAction)
    }

    func testCancelledDashRowOffersNoAction() {
        XCTAssertFalse(
            makeRow(statusSymbol: "-", statusType: "CANCELLED").offersMeetingNotesAction)
    }

    func testDoneXRowStillOffersNotesAction() {
        XCTAssertTrue(makeRow(statusSymbol: "x", statusType: "DONE").offersMeetingNotesAction)
        XCTAssertTrue(
            makeRow(phase: .ended, statusSymbol: "X", statusType: "DONE")
                .offersMeetingNotesAction)
    }

    func testAbsentMeetingNotesStateOffersNoAction() throws {
        let data = """
        {
          "line":10,
          "block_id":"standup",
          "kind":"task",
          "title":"Standup",
          "phase":"running",
          "status_symbol":" ",
          "status_type":"TODO",
          "event_ref":"20261123#^standup",
          "meeting_notes":{}
        }
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(CaptureAgendaEventRow.self, from: data)
        XCTAssertEqual(row.meetingNotes?.state, "")
        XCTAssertFalse(row.offersMeetingNotesAction)
    }

    func testFiledRowOffersNoAction() {
        XCTAssertFalse(makeRow(state: "filed").offersMeetingNotesAction)
    }

    func testUnknownStateOffersNoAction() {
        XCTAssertFalse(makeRow(state: "queued").offersMeetingNotesAction)
    }

    func testMissingTokenOffersNoAction() {
        XCTAssertFalse(makeRow(eventRef: nil).offersMeetingNotesAction)
        XCTAssertFalse(makeRow(eventRef: "").offersMeetingNotesAction)
    }

    func testMissingBlockIDOffersNoAction() {
        XCTAssertFalse(makeRow(blockID: nil).offersMeetingNotesAction)
    }

    func testTimedContextKindOffersNoAction() {
        XCTAssertFalse(makeRow(kind: .timedContext).offersMeetingNotesAction)
    }

    func testPresentationCarriesMeetingRefAndEligibility() {
        let row = makeRow()
        let calendar = CaptureAgendaPresentation.makeCalendarEventRow(
            row, countdown: nil, startHint: nil)
        XCTAssertEqual(calendar.calendar?.eventMeetingRef, "20261123#^standup")
        XCTAssertEqual(calendar.calendar?.offersMeetingNotes, true)
    }

    func testEndedDonePresentationStillOffersNotes() {
        let row = makeRow(phase: .ended, statusSymbol: "x", statusType: "DONE")
        let calendar = CaptureAgendaPresentation.makeCalendarEventRow(
            row, countdown: nil, startHint: nil)
        XCTAssertEqual(calendar.calendar?.offersMeetingNotes, true)
    }

    func testPresentationDropsActionForOldBob() {
        let row = makeRow(eventRef: nil, state: nil)
        let calendar = CaptureAgendaPresentation.makeCalendarEventRow(
            row, countdown: nil, startHint: nil)
        XCTAssertNil(calendar.calendar?.eventMeetingRef)
        XCTAssertEqual(calendar.calendar?.offersMeetingNotes, false)
    }

    func testMeetingNotesPresentationFormats() {
        let meeting = try? JSONDecoder().decode(
            MeetingNotesMeeting.self,
            from: """
            {"ref":"20261123#^standup","path":"Meetings/standup.md","block_id":"standup","date":"2026-11-23","start":"13:00","end":"13:30","title":"Acme standup","root":null,"root_is_inbox":false,"status":"TODO","event_id":"evt-1"}
            """.data(using: .utf8)!
        )
        XCTAssertEqual(MeetingNotesPresentation.title(for: meeting), "Acme standup")
        XCTAssertEqual(
            MeetingNotesPresentation.dateSpan(for: meeting), "2026-11-23 · 13:00–13:30")
        XCTAssertTrue(MeetingNotesPresentation.filedRowMark(for: meeting!) == false)
    }

    func testTranscriptDispositionReadsTranscriptNotShape() throws {
        let preview = try JSONDecoder().decode(
            MeetingNotesResponse.self,
            from: Data(
                contentsOf: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Fixtures/meeting-notes/preview.json")
            )
        )
        XCTAssertEqual(preview.notes?.shape, "wispr_plain_text")
        XCTAssertEqual(
            MeetingNotesPresentation.transcriptDisposition(for: preview), "omitted")
        XCTAssertEqual(
            MeetingNotesPresentation.commitWarning(for: preview), nil)

        let filed = try JSONDecoder().decode(
            MeetingNotesResponse.self,
            from: Data(
                contentsOf: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Fixtures/meeting-notes/filed.json")
            )
        )
        XCTAssertEqual(
            MeetingNotesPresentation.transcriptDisposition(for: filed), "omitted")
        XCTAssertEqual(
            MeetingNotesPresentation.commitWarning(for: filed), "remote unavailable")
    }

    func testSamePathMeetingsKeepDistinctPresentationIdentities() throws {
        let list = try JSONDecoder().decode(
            MeetingNotesListResponse.self,
            from: Data(
                contentsOf: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Fixtures/meeting-notes/list-same-path.json")
            )
        )
        XCTAssertEqual(Set(list.meetings.map(\.path)).count, 1)
        let ids = list.meetings.enumerated().map { $0.element.presentationIdentity(at: $0.offset) }
        XCTAssertEqual(Set(ids).count, 3)
        XCTAssertEqual(ids[0], "ref:20261124#^spruce-sync")
        XCTAssertEqual(ids[1], "ref:20261124#^orchard")
        XCTAssertTrue(ids[2].hasPrefix("anon:2:"))
        XCTAssertTrue(list.meetings[0].canSelect)
        XCTAssertTrue(list.meetings[1].canSelect)
        XCTAssertFalse(list.meetings[2].canSelect)
    }
}
