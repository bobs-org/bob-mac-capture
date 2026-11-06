import Foundation
import XCTest

@testable import CaptureCore

final class CapturePomodoroPastPresentationTests: XCTestCase {
    private func fixtureData(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    private func decodeParse(_ name: String) throws -> CaptureParseResponse {
        try JSONDecoder().decode(CaptureParseResponse.self, from: fixtureData(name))
    }

    private func decodeSuccess(_ name: String) throws -> CaptureCommandSuccess {
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: fixtureData(name)
        )
        guard case .success(let success) = response else {
            throw NSError(domain: "PastTests", code: 1)
        }
        return success
    }

    private func decodeJSON(_ text: String) throws -> CaptureCommandSuccess {
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(text.utf8)
        )
        guard case .success(let success) = response else {
            throw NSError(domain: "PastTests", code: 2)
        }
        return success
    }

    // MARK: - Wire models

    func testParseSingleDecodesPast() throws {
        let parse = try decodeParse("pomodoro-past-parse-single.json")
        XCTAssertEqual(parse.mode, "pomodoro_past")
        let past = try XCTUnwrap(parse.pomodoroPast)
        XCTAssertEqual(past.raw, "x=build")
        XCTAssertEqual(past.name, "BUILD")
        XCTAssertFalse(past.repair)
        XCTAssertEqual(past.blocks, 5)
        XCTAssertEqual(past.minutes, 25)
        XCTAssertEqual(past.stack.index, 1)
    }

    func testParseStackPreservesTypedOrderAndOffsets() throws {
        let parse = try decodeParse("pomodoro-past-parse-stack.json")
        XCTAssertEqual(parse.items.count, 2)
        let first = try XCTUnwrap(parse.items[0].pomodoroPast)
        let second = try XCTUnwrap(parse.items[1].pomodoroPast)
        XCTAssertEqual(first.stack.index, 1)
        XCTAssertEqual(first.stack.size, 2)
        XCTAssertEqual(first.stack.offsetBlocks, 3)
        XCTAssertEqual(second.stack.index, 2)
        XCTAssertEqual(second.stack.offsetBlocks, 0)
        XCTAssertEqual(parse.items.map(\.mode), ["pomodoro_past", "pomodoro_past"])
    }

    func testParseRepairSpansDistinguishFromCloseComplete() throws {
        let parse = try decodeParse("pomodoro-past-parse-repair.json")
        let kinds = Set(parse.spans.map(\.kind))
        XCTAssertTrue(kinds.contains("pomodoro_past"))
        XCTAssertTrue(kinds.contains("pomodoro_past_repair"))
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_past"), .pomodoroStart)
        XCTAssertEqual(
            captureSemanticCategory(forSpanKind: "pomodoro_past_repair"),
            .pomodoroPastRepair
        )
        // Close-selection `!` stays green; repair `!` is its own warning.
        XCTAssertEqual(
            captureSemanticCategory(forSpanKind: "pomodoro_close_complete"),
            .pomodoroCloseComplete
        )
        XCTAssertNotEqual(
            captureSemanticCategory(forSpanKind: "pomodoro_past_repair"),
            captureSemanticCategory(forSpanKind: "pomodoro_close_complete")
        )
    }

    func testSuccessSingleDecodesPastAndOmitsTopLevelClose() throws {
        let success = try decodeSuccess("pomodoro-past-preview-single.json")
        XCTAssertEqual(success.kind, "pomodoro_past")
        XCTAssertEqual(success.placement, "recorded")
        XCTAssertNil(success.pomodoroClose)
        let past = try XCTUnwrap(success.pomodoroPast)
        XCTAssertEqual(past.window.minutes, 25)
        XCTAssertNil(past.segment)
        XCTAssertNil(past.stack.pin)
        XCTAssertNil(past.window.requestedMinutes)
        XCTAssertNil(past.window.cut)
        XCTAssertTrue(past.trims.isEmpty)
    }

    func testSegmentPlacementAndCutDetailsAppearOnPastCard() throws {
        let placed = try decodeSuccess("pomodoro-past-preview-segment-repair.json")
        let placedPast = try XCTUnwrap(placed.pomodoroPast)
        XCTAssertEqual(placedPast.stack.pin, "start")
        XCTAssertEqual(placedPast.segment?.kind, "pomodoro")
        XCTAssertEqual(placedPast.segment?.index, 1)
        XCTAssertEqual(placedPast.segment?.edge, "start")
        XCTAssertEqual(placedPast.segment?.start, "0830")
        XCTAssertEqual(placedPast.segment?.end, "0900")
        XCTAssertEqual(placedPast.segment?.name, "BUILD")
        let placedMember = try XCTUnwrap(
            CapturePomodoroPastPresentation(capture: placed)?.groups.first?.members.first
        )
        XCTAssertEqual(
            placedMember.segmentLine,
            "at the start of ~1 BUILD 0830–0900"
        )
        XCTAssertTrue(
            try XCTUnwrap(placedMember.segmentAccessibilityLabel)
                .contains("Placement: at the start")
        )
        XCTAssertEqual(placedMember.past.trims.first?.name, "BUILD")

        let cut = try decodeSuccess("pomodoro-past-preview-segment-cut.json")
        let cutPast = try XCTUnwrap(cut.pomodoroPast)
        XCTAssertEqual(cutPast.window.requestedMinutes, 20)
        XCTAssertEqual(cutPast.window.minutes, 15)
        XCTAssertEqual(cutPast.window.cut, "now")
        let cutMember = try XCTUnwrap(
            CapturePomodoroPastPresentation(capture: cut)?.groups.first?.members.first
        )
        XCTAssertEqual(cutMember.cutNote, "15m · 20m cut at now")
        XCTAssertTrue(
            try XCTUnwrap(cutMember.cutAccessibilityLabel).contains("cut at now")
        )
        XCTAssertTrue(cutMember.accessibilityLabel.contains("cut at now"))
    }

    func testOlderPayloadWithoutPastStillDecodes() throws {
        let success = try decodeSuccess("pomodoro-close-worked.json")
        XCTAssertNil(success.pomodoroPast)
        XCTAssertNotNil(success.pomodoroClose)
        XCTAssertNil(CapturePomodoroPastPresentation(capture: success))
    }

    func testMalformedPastMetadataDegradesSafely() throws {
        let success = try decodeJSON(
            """
            {"ok":true,"dry_run":true,"routed":false,"route_label":"","relative_target":"day.md",\
            "target":"/tmp/day.md","text":"x=build","task_line":"","kind":"pomodoro_past",\
            "created":"2026-11-04","placement":"recorded",\
            "pomodoro_past":{"raw":"x=build","blocks":2,"repair":false,\
            "stack":"bad","window":{"start":"0900","end":"0910","minutes":10},\
            "closed_at":"0910","line":2,"trims":[],"close":{\
            "raw":"","task_links":[],"pomodoro_line":2,"entry_line":"",\
            "planned":{"start":"0900","end":"0910","duration_minutes":10,"time_range":"0900-0910"},\
            "closed":{"start":"0900","end":"0910","duration_minutes":10,"time_range":"0900-0910"},\
            "closed_at":"0910","remaining_minutes":0,"decremented_minutes":0,\
            "tasks":[],"carried":[],"notes":[]}}}
            """
        )
        // Malformed stack degrades to defaults; the capture still decodes.
        XCTAssertNotNil(success.pomodoroPast)
        XCTAssertEqual(success.pomodoroPast?.stack.index, 0)
    }

    // MARK: - Grouping

    func testTwoMemberStackGroupsTogether() throws {
        let success = try decodeSuccess("pomodoro-past-preview-stack.json")
        let groups = CapturePomodoroPastPresentation.groups(for: success.normalizedCaptures)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].members.count, 2)
        XCTAssertEqual(groups[0].totalMinutes, 25)
        XCTAssertEqual(groups[0].timelineText, "0900 ── BUILD 10m ── 0910 ── FIX 15m ── 0925")
    }

    func testSeparatedStacksNeverMerge() throws {
        let parse = try decodeParse("pomodoro-past-parse-separated.json")
        let items = parse.items
        XCTAssertEqual(items.filter { $0.mode == "pomodoro_past" }.count, 2)
        // Simulate success grouping: two size-1 stacks separated by a task.
        let first = try decodeSuccess("pomodoro-past-preview-single.json")
        let second = try decodeJSON(
            """
            {"ok":true,"dry_run":true,"routed":false,"route_label":"","relative_target":"day.md",\
            "target":"/tmp/day.md","text":"x=fix@3","task_line":"","kind":"pomodoro_past",\
            "created":"2026-11-04","placement":"recorded",\
            "pomodoro_past":{"raw":"x=fix@3","name":"FIX",\
            "target":{"source":"created","line":3},"blocks":3,"repair":false,\
            "stack":{"index":1,"size":1},"anchor":"0925",\
            "window":{"start":"0910","end":"0925","minutes":15},\
            "closed_at":"0925","line":3,"trims":[],\
            "close":{"raw":"","task_links":[],"pomodoro_line":3,"entry_line":"",\
            "planned":{"start":"0910","end":"0925","duration_minutes":15,"time_range":"0910-0925"},\
            "closed":{"start":"0910","end":"0925","duration_minutes":15,"time_range":"0910-0925"},\
            "closed_at":"0925","remaining_minutes":0,"decremented_minutes":0,\
            "tasks":[],"carried":[],"notes":[]}}}
            """
        )
        let task = try decodeJSON(
            """
            {"ok":true,"dry_run":true,"routed":false,"route_label":"","relative_target":"day.md",\
            "target":"/tmp/day.md","text":"Buy milk","task_line":"Buy milk",\
            "kind":"task","created":"2026-11-04","placement":"created"}
            """
        )
        let groups = CapturePomodoroPastPresentation.groups(
            for: [first, task, second]
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.members.count), [1, 1])
    }

    func testOrdinaryCloseDoesNotGroupWithPast() throws {
        let past = try decodeSuccess("pomodoro-past-preview-single.json")
        let close = try decodeSuccess("pomodoro-close-worked.json")
        let groups = CapturePomodoroPastPresentation.groups(for: [close, past])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].members.count, 1)
    }

    func testMidnightEndRendersFaithfullyInMemberOrder() throws {
        let first = try decodeJSON(
            """
            {"ok":true,"dry_run":true,"routed":false,"route_label":"","relative_target":"day.md",\
            "target":"/tmp/day.md","text":"x=build@2","task_line":"","kind":"pomodoro_past",\
            "created":"2026-11-04","placement":"recorded",\
            "pomodoro_past":{"raw":"x=build@2","name":"BUILD",\
            "target":{"source":"created","line":2},"blocks":2,"repair":false,\
            "stack":{"index":1,"size":2},"anchor":"0000",\
            "window":{"start":"2330","end":"2340","minutes":10},\
            "closed_at":"2340","line":2,"trims":[],\
            "close":{"raw":"","task_links":[],"pomodoro_line":2,"entry_line":"",\
            "planned":{"start":"2330","end":"2340","duration_minutes":10,"time_range":"2330-2340"},\
            "closed":{"start":"2330","end":"2340","duration_minutes":10,"time_range":"2330-2340"},\
            "closed_at":"2340","remaining_minutes":0,"decremented_minutes":0,\
            "tasks":[],"carried":[],"notes":[]}}}
            """
        )
        let second = try decodeJSON(
            """
            {"ok":true,"dry_run":true,"routed":false,"route_label":"","relative_target":"day.md",\
            "target":"/tmp/day.md","text":"x=fix@3","task_line":"","kind":"pomodoro_past",\
            "created":"2026-11-04","placement":"recorded",\
            "pomodoro_past":{"raw":"x=fix@3","name":"FIX",\
            "target":{"source":"created","line":3},"blocks":3,"repair":false,\
            "stack":{"index":2,"size":2},"anchor":"0000",\
            "window":{"start":"2340","end":"0000","minutes":20},\
            "closed_at":"2359","line":3,"trims":[],\
            "close":{"raw":"","task_links":[],"pomodoro_line":3,"entry_line":"",\
            "planned":{"start":"2340","end":"0000","duration_minutes":20,"time_range":"2340-0000"},\
            "closed":{"start":"2340","end":"0000","duration_minutes":20,"time_range":"2340-0000"},\
            "closed_at":"2359","remaining_minutes":0,"decremented_minutes":0,\
            "tasks":[],"carried":[],"notes":[]}}}
            """
        )
        let groups = CapturePomodoroPastPresentation.groups(for: [first, second])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].members.map(\.displayName), ["BUILD", "FIX"])
        XCTAssertTrue(groups[0].timelineText.hasSuffix("0000"))
    }

    // MARK: - Presentation

    func testRepairStackShowsOneDedupedTrim() throws {
        let success = try decodeSuccess("pomodoro-past-preview-repair.json")
        let presentation = try XCTUnwrap(CapturePomodoroPastPresentation(capture: success))
        XCTAssertTrue(presentation.isHomogeneous)
        XCTAssertEqual(presentation.primaryActionTitle, "Record")
        XCTAssertEqual(presentation.notificationTitle, "Recorded past Pomodoro")
        let group = try XCTUnwrap(presentation.groups.first)
        XCTAssertEqual(group.title, "Record past work")
        XCTAssertEqual(group.totalMinutes, 25)
        XCTAssertEqual(group.trimRows.count, 1)
        let trim = try XCTUnwrap(group.trimRows.first)
        XCTAssertEqual(trim.name, "PLAN")
        XCTAssertEqual(trim.before, "0855-0920")
        XCTAssertEqual(trim.after, "0855-0900")
        XCTAssertEqual(trim.minutes, 20)
        XCTAssertFalse(trim.calendar)
        XCTAssertTrue(trim.text.contains("gives 20m"))
        XCTAssertFalse(trim.text.contains("(calendar)"))
        XCTAssertTrue(group.accessibilitySummary.contains("Record past work"))
        XCTAssertTrue(group.accessibilitySummary.contains("gives 20 minutes"))
    }

    func testCalendarTrimFlagsCalendar() throws {
        let success = try decodeSuccess("pomodoro-past-preview-calendar.json")
        let group = try XCTUnwrap(
            CapturePomodoroPastPresentation(capture: success)?.groups.first
        )
        XCTAssertEqual(group.trimRows.count, 1)
        XCTAssertTrue(try XCTUnwrap(group.trimRows.first).calendar)
        XCTAssertTrue(try XCTUnwrap(group.trimRows.first).text.contains("(calendar)"))
    }

    func testTaskEffectsWorkLogAndContinuation() throws {
        let taskEffects = try decodeSuccess("pomodoro-past-preview-task-effects.json")
        let group = try XCTUnwrap(
            CapturePomodoroPastPresentation(capture: taskEffects)?.groups.first
        )
        let member = try XCTUnwrap(group.members.first)
        XCTAssertEqual(member.displayName, "BUILD")
        XCTAssertEqual(member.windowText, "0900-0925 · 25m")
        XCTAssertEqual(member.durationMinutes, 25)
        XCTAssertEqual(member.taskRows.count, 2)
        XCTAssertNotNil(member.closePresentation?.nextText)
        XCTAssertTrue(group.accessibilitySummary.contains("BUILD"))

        let worklog = try decodeSuccess("pomodoro-past-preview-worklog.json")
        let wmember = try XCTUnwrap(
            CapturePomodoroPastPresentation(capture: worklog)?.groups.first?.members.first
        )
        XCTAssertFalse(wmember.taskRows.isEmpty)
        let typed = wmember.taskRows.flatMap(\.typedWorkLogPreviews)
        XCTAssertFalse(typed.isEmpty)
    }

    func testSuccessorOffersFlowThroughHelpers() throws {
        let success = try decodeJSON(
            """
            {"ok":true,"dry_run":true,"routed":false,"route_label":"","relative_target":"day.md",\
            "target":"/tmp/day.md","text":"x=build","task_line":"","kind":"pomodoro_past",\
            "created":"2026-11-04","placement":"recorded",\
            "pomodoro_past":{"raw":"x=build","name":"BUILD",\
            "target":{"source":"created","line":2},"blocks":5,"repair":false,\
            "stack":{"index":1,"size":1},"anchor":"0925",\
            "window":{"start":"0900","end":"0925","minutes":25},\
            "closed_at":"0921","line":2,"trims":[],\
            "close":{"raw":"","task_links":[],"pomodoro_line":2,"entry_line":"",\
            "planned":{"start":"0900","end":"0925","duration_minutes":25,"time_range":"0900-0925"},\
            "closed":{"start":"0900","end":"0925","duration_minutes":25,"time_range":"0900-0925"},\
            "closed_at":"0921","remaining_minutes":4,"decremented_minutes":0,\
            "tasks":[],"carried":[],"notes":[],\
            "unblocked":[{"text":"Next task","note_path":"bob.md","block_id":"abc",\
            "status_symbol":" ","status_name":"Todo","offer":{"key":"k1","group":"unblocked"}}],\
            "keep_moving":[],"still_blocked":[],"unblocked_check":"checked"}}}
            """
        )
        XCTAssertEqual(success.allUnblockedRows.count, 1)
        XCTAssertEqual(success.allKeepMovingRows.count, 0)
        XCTAssertEqual(success.allUnblockedRows.first?.offer?.key, "k1")
    }

    func testCompletionReplacesOnlyName() throws {
        let data = try fixtureData("pomodoro-past-complete-name.json")
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: data
        )
        XCTAssertEqual(try XCTUnwrap(response.context), "pomodoro_past_name")
        XCTAssertEqual(response.replacement.start, 2)
        XCTAssertEqual(response.replacement.end, 4)
        // Bob's range covers only the typed name; Swift must not parse `x=`.
        XCTAssertFalse(response.candidates.isEmpty)
        // Replacement preserves the rest of the token: applying it to `x=bu`
        // names the session without touching `@D`, repair `!`, or `=X`.
        let candidate = try XCTUnwrap(response.candidates.first)
        XCTAssertEqual(candidate.replacement, "build")
    }

    func testSegmentCompletionDecodesBobAuthoredRowFields() throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: fixtureData("pomodoro-past-complete-segment.json")
        )
        XCTAssertEqual(response.context, "pomodoro_past_segment")
        XCTAssertEqual(response.replacement.start, 2)
        XCTAssertEqual(response.replacement.end, 3)
        let pomodoro = try XCTUnwrap(
            response.candidates.first(where: { $0.replacement == "~1" })
        )
        XCTAssertEqual(pomodoro.kind, "pomodoro")
        XCTAssertEqual(pomodoro.label, "~1 BUILD 0830-0900")
        XCTAssertEqual(pomodoro.start, "0830")
        XCTAssertEqual(pomodoro.end, "0900")
        XCTAssertEqual(pomodoro.minutes, 30)
        XCTAssertTrue(pomodoro.needsRepair)
    }

    func testRefusalDecodesAsFailure() throws {
        let data = try fixtureData("pomodoro-past-preview-refusal.json")
        // Refusals keep a nonzero status in the generator; the JSON stays an
        // error payload, never a stale success card.
        let text = String(decoding: data.asBytes(), as: UTF8.self)
        XCTAssertTrue(text.contains("add !"))
    }

    // MARK: - Boundary

    func testNextBoundaryFromExactBoundarySleepsFullInterval() {
        // 1_699_999_800 is an exact multiple of 300.
        let now = Date(timeIntervalSince1970: 1_699_999_800)
        let next = CapturePastBoundary.nextBoundary(after: now)
        XCTAssertEqual(next.timeIntervalSince1970, 1_700_000_100)
        XCTAssertEqual(
            CapturePastBoundary.sleepNanoseconds(now: now),
            300_000_000_000
        )
    }

    func testNextBoundaryFromMidInterval() {
        let now = Date(timeIntervalSince1970: 1_699_999_860)
        let next = CapturePastBoundary.nextBoundary(after: now)
        XCTAssertEqual(next.timeIntervalSince1970, 1_700_000_100)
    }

    func testShouldArmOnlyForVisiblePast() {
        XCTAssertTrue(CapturePastBoundary.shouldArm(panelVisible: true, hasPastGroups: true))
        XCTAssertFalse(CapturePastBoundary.shouldArm(panelVisible: false, hasPastGroups: true))
        XCTAssertFalse(CapturePastBoundary.shouldArm(panelVisible: true, hasPastGroups: false))
    }
}

private extension Data {
    func asBytes() -> [UInt8] {
        [UInt8](self)
    }
}
