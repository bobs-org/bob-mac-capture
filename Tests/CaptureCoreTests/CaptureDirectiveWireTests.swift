import Foundation
import XCTest

@testable import CaptureCore

/// Decodes the captured directive wire, using fixtures that
/// `Scripts/generate-directive-fixtures.sh` captures from a real Bob (see
/// `Tests/Fixtures/directive-fixtures-README.md`).
final class CaptureDirectiveWireTests: XCTestCase {
    // MARK: - Parse: grammar

    func testParseGrammarStaysObservableWhenMissingLowerOrHigher() throws {
        func grammar(_ field: String) throws -> Int? {
            let json = """
                {"ok":true,"schema_version":1\(field),"input":"x","body":"x","mode":"task"}
                """
            let data = Data(json.utf8)
            return try JSONDecoder().decode(CaptureParseResponse.self, from: data).grammar
        }

        XCTAssertNil(try grammar(""))
        XCTAssertEqual(try grammar(#","grammar":1"#), 1)
        XCTAssertEqual(try grammar(#","grammar":2"#), 2)
        XCTAssertEqual(try grammar(#","grammar":3"#), 3)
        XCTAssertNil(try grammar(#","grammar":"2""#), "a mistyped revision is not a guessed one")
        XCTAssertNil(try grammar(#","grammar":null"#))
    }

    func testCompletionGrammarStaysObservableWhenMissingLowerOrHigher() throws {
        func grammar(_ field: String) throws -> Int? {
            let json = """
                {"ok":true,"schema_version":1\(field),"cursor":0,"replacement":{"start":0,"end":0},"context":null,"candidates":[]}
                """
            return try JSONDecoder().decode(CaptureCompletionResponse.self, from: Data(json.utf8))
                .grammar
        }

        XCTAssertNil(try grammar(""))
        XCTAssertEqual(try grammar(#","grammar":1"#), 1)
        XCTAssertEqual(try grammar(#","grammar":2"#), 2)
        XCTAssertEqual(try grammar(#","grammar":4"#), 4)
        XCTAssertNil(try grammar(#","grammar":"2""#))
    }

    func testRealBobDirectiveFixturesMeetGrammarGate() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: fixtures.path)
        let parseNames = names.filter {
            $0.hasPrefix("directive-parse-") && $0.hasSuffix(".json")
        }.sorted()
        let completeNames = names.filter {
            $0.hasPrefix("directive-complete-") && $0.hasSuffix(".json")
        }.sorted()
        XCTAssertFalse(parseNames.isEmpty, "expected directive-parse fixtures")
        XCTAssertFalse(completeNames.isEmpty, "expected directive-complete fixtures")
        for name in parseNames {
            let parse = try parseFixture(name)
            XCTAssertEqual(parse.schemaVersion, 1, name)
            let grammar = try XCTUnwrap(parse.grammar, name)
            XCTAssertGreaterThanOrEqual(grammar, CaptureGrammarGate.minimumRevision, name)
        }
        for name in completeNames {
            let complete = try completionFixture(name)
            XCTAssertEqual(complete.schemaVersion, 1, name)
            let grammar = try XCTUnwrap(complete.grammar, name)
            XCTAssertGreaterThanOrEqual(grammar, CaptureGrammarGate.minimumRevision, name)
        }
    }

    // MARK: - Parse: directive spans

    func testBareSigilsParseAsIncompleteMarkersWithoutADirective() throws {
        let percent = try parseFixture("directive-parse-bare-percent.json")
        XCTAssertEqual(percent.mode, "incomplete")
        XCTAssertEqual(percent.needs, ["directive"])
        XCTAssertEqual(
            percent.spans, [CaptureSpan(start: 9, end: 10, kind: "directive")])
        XCTAssertNil(percent.spans[0].directive)
        XCTAssertNil(percent.spans[0].count)

        let hash = try parseFixture("directive-parse-bare-hash.json")
        XCTAssertEqual(hash.needs, ["task_type"])
        XCTAssertEqual(hash.spans.map(\.kind), ["task_type"])
    }

    func testNamedDirectivesDecodeTheirNameAndCount() throws {
        let clip = try directiveSpan("directive-parse-clip.json")
        XCTAssertEqual(clip.directive, "clip")
        XCTAssertNil(clip.count)
        XCTAssertEqual(clip.start, 9)
        XCTAssertEqual(clip.end, 11)

        let one = try directiveSpan("directive-parse-clip-one.json")
        XCTAssertEqual(one.directive, "clip")
        XCTAssertNil(one.count, "%c1 reports no count")

        let counted = try directiveSpan("directive-parse-clip-count.json")
        XCTAssertEqual(counted.directive, "clip")
        XCTAssertEqual(counted.count, 3)

        let note = try parseFixture("directive-parse-note.json")
        XCTAssertEqual(note.mode, "pomodoro_note")
        XCTAssertEqual(try directiveSpan("directive-parse-note.json").directive, "note")

        let listen = try parseFixture("directive-parse-listen-url.json")
        XCTAssertEqual(listen.mode, "ref")
        XCTAssertTrue(listen.refListen)
        XCTAssertEqual(try directiveSpan("directive-parse-listen-url.json").directive, "listen")

        let template = try directiveSpan("directive-parse-template.json")
        XCTAssertEqual(template.directive, "template")
    }

    func testUnknownDirectiveKeepsItsSpanWithoutAName() throws {
        let parse = try parseFixture("directive-parse-unknown.json")

        XCTAssertNil(try directiveSpan("directive-parse-unknown.json").directive)
        XCTAssertEqual(parse.diagnostics.map(\.code), ["unknown_directive"])
    }

    func testEscapedAndLiteralPercentProduceNoDirectiveSpans() throws {
        let escaped = try parseFixture("directive-parse-escaped.json")
        XCTAssertEqual(escaped.body, "jot idea %c")
        XCTAssertEqual(escaped.spans, [])

        let literal = try parseFixture("directive-parse-literal-percent.json")
        XCTAssertEqual(literal.body, "100% done")
        XCTAssertEqual(literal.spans, [])
        XCTAssertEqual(literal.needs, [])
    }

    func testLaterBatchItemDirectiveSpanIsTopLevel() throws {
        let parse = try parseFixture("directive-parse-batch-later-item.json")

        XCTAssertEqual(parse.items.count, 2)
        let span = try directiveSpan("directive-parse-batch-later-item.json")
        XCTAssertEqual(span.directive, "clip")
        let secondItem = try XCTUnwrap(parse.items.last)
        XCTAssertTrue(secondItem.range.start <= span.start && span.end <= secondItem.range.end)
    }

    func testDirectiveSpanRangesAreUTF8OffsetsPastMultibyteText() throws {
        let parse = try parseFixture("directive-parse-unicode.json")
        let span = try directiveSpan("directive-parse-unicode.json")

        XCTAssertEqual(span.directive, "clip")
        XCTAssertEqual(span.count, 3)
        XCTAssertEqual(parse.input, "naïve 🧰 %c3")
        XCTAssertEqual(parse.input.count, 11, "characters, not bytes")
        XCTAssertEqual(span.start, 12)
        XCTAssertEqual(span.end, 15)
        let bytes = Array(parse.input.utf8)
        XCTAssertEqual(String(decoding: bytes[span.start..<span.end], as: UTF8.self), "%c3")
    }

    func testGlobalRouteClipCombinesRouteAndDirectiveSpans() throws {
        let parse = try parseFixture("directive-parse-global-route-clip.json")

        XCTAssertEqual(parse.spans.map(\.kind), ["global_route", "directive"])
        XCTAssertEqual(parse.spans.last?.directive, "clip")
        XCTAssertEqual(parse.globalDestination?.route, "dev")
    }

    // MARK: - Parse: template and global destination

    func testTemplateMetadataUsesDirectiveRangeAndLine() throws {
        let parse = try parseFixture("directive-parse-template.json")
        let template = try XCTUnwrap(parse.template)

        XCTAssertEqual(template.directive.range, CaptureRange(start: 20, end: 22))
        XCTAssertEqual(template.directive.line, 1)
        XCTAssertEqual(template.lineStart, 1)
        XCTAssertEqual(template.lineEnd, 1)
        XCTAssertEqual(template.fieldCount, 2)
        XCTAssertEqual(template.rows.map(\.line), [3, 4])
        XCTAssertEqual(
            template.rows.map(\.range),
            [CaptureRange(start: 24, end: 34), CaptureRange(start: 35, end: 42)])
        XCTAssertEqual(
            template.rows.flatMap(\.fields).map(\.range.start), [24, 31, 35, 39])
    }

    func testTemplateWithoutRowsAndWithClipKeepBobsRefusals() throws {
        let noRows = try parseFixture("directive-parse-template-no-rows.json")
        XCTAssertEqual(noRows.needs, ["template_row"])
        XCTAssertEqual(noRows.template?.rows, [])
        XCTAssertEqual(noRows.template?.directive.range, CaptureRange(start: 10, end: 12))
        XCTAssertEqual(noRows.diagnostics.map(\.code), ["template_missing_rows"])

        let clip = try parseFixture("directive-parse-template-clip.json")
        XCTAssertEqual(clip.diagnostics.map(\.code), ["template_clipboard"])
        XCTAssertEqual(clip.spans.compactMap(\.directive), ["clip", "template"])
    }

    func testGlobalDestinationIsRouteOnly() throws {
        let parse = try parseFixture("directive-parse-global-route.json")
        let destination = try XCTUnwrap(parse.globalDestination)

        XCTAssertEqual(destination.route, "dev")
        XCTAssertEqual(destination.line, 1)
        XCTAssertEqual(destination.range, CaptureRange(start: 0, end: 5))
        XCTAssertEqual(destination.needs, [])
        XCTAssertEqual(parse.items.map(\.route), ["dev", "dev"])

        let bare = try parseFixture("directive-parse-global-route-bare.json")
        XCTAssertNil(bare.globalDestination?.route)
        XCTAssertEqual(bare.globalDestination?.needs, ["route"])
    }

    func testGlobalDestinationDecodesWithoutModeOrBlockID() throws {
        let destination = try JSONDecoder().decode(
            CaptureGlobalDestination.self,
            from: Data(#"{"range":{"start":0,"end":5},"route":"dev","needs":[]}"#.utf8))

        XCTAssertEqual(
            destination,
            CaptureGlobalDestination(range: CaptureRange(start: 0, end: 5), route: "dev"))
    }

    // MARK: - Completion: directive rows

    func testBareDirectiveMenuOpensWithoutSelectionAndKeepsBobsOrderAndCopy() throws {
        let response = try completionFixture("directive-complete-bare.json")

        XCTAssertEqual(response.context, "directive")
        XCTAssertEqual(response.initialSelection, "none")
        XCTAssertTrue(response.opensWithoutSelection)
        XCTAssertEqual(response.query, "")
        XCTAssertEqual(response.replacement, CaptureRange(start: 9, end: 10))
        XCTAssertEqual(response.candidates.compactMap(\.token), ["%c", "%n", "%t"])
        XCTAssertEqual(
            response.candidates.compactMap(\.name), ["Clip", "Pomodoro note", "Template"])
        XCTAssertEqual(
            response.candidates.compactMap(\.summary),
            [
                "Paste clipboard content", "Add a note to a Pomodoro",
                "Expand this draft once per row",
            ])
        XCTAssertEqual(
            response.candidates[0].detail,
            "Add a count, such as `%c3`, to paste the last three clips.")
        XCTAssertEqual(response.candidates[1].detail, "→ 09:00–09:30 FIX · running")
        XCTAssertEqual(response.candidates.map(\.replacement), ["%c", "%n", "%t"])
        XCTAssertEqual(response.candidates.map(\.cursorAfter), [11, 11, 11])
        XCTAssertEqual(response.candidates.map(\.disabledReason), [nil, nil, nil])
    }

    func testDirectiveRowsDecodeWithoutTaskOrRouteFields() throws {
        let rows = try completionFixture("directive-complete-bare.json").candidates

        for row in rows {
            XCTAssertNil(row.route)
            XCTAssertNil(row.label)
            XCTAssertNil(row.kind)
            XCTAssertNil(row.taskRef)
            XCTAssertNil(row.blockID)
            XCTAssertFalse(row.requiresBlockID)
        }
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }

    func testTypedDirectivePrefixKeepsTheDefaultSelection() throws {
        for (name, token) in [
            ("directive-complete-typed-clip.json", "%c"),
            ("directive-complete-typed-note.json", "%n"),
            ("directive-complete-typed-template.json", "%t"),
        ] {
            let response = try completionFixture(name)
            XCTAssertEqual(response.context, "directive", name)
            XCTAssertNil(response.initialSelection, name)
            XCTAssertFalse(response.opensWithoutSelection, name)
            XCTAssertEqual(response.candidates.compactMap(\.token), [token], name)
            XCTAssertEqual(response.replacement.end - response.replacement.start, 2, name)
        }

        let counted = try completionFixture("directive-complete-counted-clip.json")
        XCTAssertEqual(counted.context, "directive")
        XCTAssertEqual(counted.candidates, [])
        XCTAssertEqual(counted.query, "c3")
    }

    func testDisabledDirectiveRowsCarryBobsReasonAndAnEmptyReplacement() throws {
        let later = try completionFixture("directive-complete-later-item.json")
        let template = try XCTUnwrap(later.candidates.first { $0.token == "%t" })
        XCTAssertEqual(template.disabledReason, "`%t` marks the first item as the template.")
        XCTAssertEqual(template.replacement, "")
        XCTAssertEqual(template.cursorAfter, 14)
        XCTAssertEqual(
            later.candidates.filter { $0.disabledReason == nil }.map(\.token), ["%c", "%n"])

        let templateClip = try completionFixture("directive-complete-template-clip.json")
        XCTAssertEqual(
            templateClip.candidates.first { $0.token == "%c" }?.disabledReason,
            "A template can't capture the clipboard: `%c` would repeat once per row.")

        let note = try completionFixture("directive-complete-note-disabled.json")
        let disabledNote = try XCTUnwrap(note.candidates.first { $0.token == "%n" })
        XCTAssertEqual(disabledNote.disabledReason, "Today's daily note has no eligible Pomodoro.")
        XCTAssertEqual(
            disabledNote.detail, "No Pomodoro · Today's daily note has no eligible Pomodoro.")
        XCTAssertEqual(Set(note.candidates.map(\.id)).count, note.candidates.count)
    }

    func testListenRowIsDisabledUntilACommandIsConfigured() throws {
        let off = try completionFixture("directive-complete-url-listen-disabled.json")
        XCTAssertEqual(off.candidates.compactMap(\.token), ["%c", "%n", "%t", "%l"])
        let disabled = try XCTUnwrap(off.candidates.last)
        XCTAssertEqual(disabled.name, "Listen")
        XCTAssertEqual(disabled.summary, "Queue this URL with companion audio")
        XCTAssertEqual(
            disabled.disabledReason,
            "Configure `highlights.listen_command` to enable companion audio.")
        XCTAssertEqual(disabled.replacement, "")

        let on = try completionFixture("directive-complete-url-listen.json")
        let listen = try XCTUnwrap(on.candidates.last)
        XCTAssertEqual(listen.token, "%l")
        XCTAssertNil(listen.disabledReason)
        XCTAssertEqual(listen.replacement, "%l")
        XCTAssertEqual(listen.detail, "A listen command is configured.")

        let typed = try completionFixture("directive-complete-url-listen-typed.json")
        XCTAssertEqual(typed.candidates.compactMap(\.token), ["%l"])
        XCTAssertNil(typed.initialSelection)
    }

    func testDirectiveCompletionRangesAreUTF8OffsetsPastMultibyteText() throws {
        let response = try completionFixture("directive-complete-unicode.json")

        XCTAssertEqual(response.replacement, CaptureRange(start: 12, end: 13))
        XCTAssertEqual(response.cursor, 13)
        XCTAssertEqual(response.candidates.map(\.cursorAfter), [14, 14, 14])
        XCTAssertTrue(response.opensWithoutSelection)
    }

    func testNonDirectivePercentSitesReportNoContext() throws {
        for name in [
            "directive-complete-mid-draft.json", "directive-complete-literal-percent.json",
        ] {
            let response = try completionFixture(name)
            XCTAssertNil(response.context, name)
            XCTAssertEqual(response.candidates, [], name)
            XCTAssertNil(response.initialSelection, name)
        }
    }

    func testBareHashOpensTheTypeMenuWithoutSelectionButTypedHashDoesNot() throws {
        let bare = try completionFixture("directive-complete-bare-hash.json")
        XCTAssertEqual(bare.context, "task_type")
        XCTAssertTrue(bare.opensWithoutSelection)
        XCTAssertEqual(bare.subject, "new")
        XCTAssertEqual(bare.candidates.compactMap(\.name), ["FIX"])

        let typed = try completionFixture("directive-complete-typed-hash.json")
        XCTAssertEqual(typed.context, "task_type")
        XCTAssertFalse(typed.opensWithoutSelection)
        XCTAssertEqual(typed.query, "f")
    }

    func testUnknownInitialSelectionKeepsTheDefaultSelection() throws {
        let json = """
            {"ok":true,"schema_version":1,"grammar":2,"cursor":1,"replacement":{"start":0,"end":1},
            "context":"directive","initial_selection":"last","candidates":[]}
            """
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.initialSelection, "last")
        XCTAssertFalse(response.opensWithoutSelection)
    }

    // MARK: - Capture: directive refusals and previews

    func testTemplateCaptureDecodesRowsWithoutTemplateHeader() throws {
        let success = try captureSuccessFixture("directive-capture-template.json")

        XCTAssertTrue(success.dryRun)
        XCTAssertEqual(success.normalizedCaptures.count, 2)
        XCTAssertEqual(success.normalizedCaptures.map { $0.templateRow?.row }, [1, 2])
        XCTAssertEqual(success.template?.fieldCount, 2)
        XCTAssertEqual(success.template?.rowCount, 2)
        XCTAssertNil(success.clip)
    }

    func testGlobalRouteCaptureDecodesBatchWithRouteOnlyDestination() throws {
        let success = try captureSuccessFixture("directive-capture-global-route.json")

        XCTAssertEqual(success.normalizedCaptures.map(\.text), ["First", "Second"])
        XCTAssertEqual(success.normalizedCaptures.map(\.relativeTarget), ["dev.md", "dev.md"])
        XCTAssertEqual(success.globalDestination, CaptureGlobalDestination(route: "dev"))
        XCTAssertTrue(
            success.normalizedCaptures.allSatisfy {
                captureUsesGlobalDestination($0, CaptureGlobalDestination(route: "dev"))
            })
        XCTAssertFalse(
            captureUsesGlobalDestination(
                success.normalizedCaptures[0], CaptureGlobalDestination(route: "other")))
        XCTAssertNil(success.clip)
    }

    func testPomodoroNoteRefusalExplainsTheMissingPomodoro() throws {
        let failure = try captureFailureFixture("directive-capture-note-refused.json")

        XCTAssertEqual(
            failure.error,
            "capture item 1 starting on line 1: Bob daily note has no eligible Pomodoro")
        XCTAssertNil(failure.code)
    }

    func testIncompleteMarkerRefusalsKeepBobsCodesAndCopy() throws {
        let percent = try captureFailureFixture("directive-capture-bare-percent-refused.json")
        XCTAssertEqual(percent.code, "incomplete_directive")
        XCTAssertTrue(percent.error.contains("`%` is incomplete"))

        let hash = try captureFailureFixture("directive-capture-bare-hash-refused.json")
        XCTAssertEqual(hash.code, "type_marker_needs_task")
        XCTAssertTrue(hash.error.contains("`#` is incomplete"))

        let unknown = try captureFailureFixture("directive-capture-unknown-refused.json")
        XCTAssertEqual(unknown.code, "unknown_directive")

        let templateClip = try captureFailureFixture("directive-capture-template-clip-refused.json")
        XCTAssertTrue(templateClip.error.contains("template can't capture the clipboard"))
    }

    // MARK: - Round trips

    func testCurrentWireModelsRoundTripThroughCodable() throws {
        let span = CaptureSpan(start: 9, end: 12, kind: "directive", directive: "clip", count: 3)
        XCTAssertEqual(try roundTrip(span), span)

        let notRead = CaptureClipOutput(status: "not_read", count: 3)
        XCTAssertEqual(try roundTrip(notRead), notRead)
        XCTAssertNil(try roundTrip(notRead).mode)

        let read = CaptureClipOutput(
            mode: "history",
            lines: ["\t- a"],
            entries: [CaptureClipOutput(mode: "inline", lines: ["\t- a"])]
        )
        XCTAssertEqual(try roundTrip(read), read)

        let destination = CaptureGlobalDestination(
            range: CaptureRange(start: 0, end: 5), line: 1, route: "dev")
        XCTAssertEqual(try roundTrip(destination), destination)

        let template = CaptureParseTemplate(
            directive: CaptureTemplateDirective(range: CaptureRange(start: 20, end: 22), line: 1),
            fieldCount: 2
        )
        XCTAssertEqual(try roundTrip(template), template)
    }

    // MARK: - Helpers

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name))
    }

    private func parseFixture(_ name: String) throws -> CaptureParseResponse {
        try JSONDecoder().decode(CaptureParseResponse.self, from: fixtureData(name))
    }

    private func completionFixture(_ name: String) throws -> CaptureCompletionResponse {
        try JSONDecoder().decode(CaptureCompletionResponse.self, from: fixtureData(name))
    }

    private func captureSuccessFixture(_ name: String) throws -> CaptureCommandSuccess {
        let data = try fixtureData(name)
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            throw FixtureError.expected("success", name)
        }
        return success
    }

    private func captureFailureFixture(_ name: String) throws -> CaptureCommandFailure {
        let data = try fixtureData(name)
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .failure(let failure) = response else {
            throw FixtureError.expected("failure", name)
        }
        return failure
    }

    /// The only `directive` span in a fixture.
    private func directiveSpan(_ name: String) throws -> CaptureSpan {
        let spans = try parseFixture(name).spans.filter { $0.kind == "directive" }
        guard spans.count == 1, let span = spans.first else {
            throw FixtureError.expected("exactly one directive span", name)
        }
        return span
    }

    private enum FixtureError: Error {
        case expected(String, String)
    }
}
