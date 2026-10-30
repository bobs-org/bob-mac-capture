import Foundation
import XCTest

@testable import CaptureCore

final class PomodoroThemeSwatchesTests: XCTestCase {
    private func ref(
        key: String,
        name: String,
        hue: PomodoroHomeHue? = nil,
        hueSource: String? = nil,
        known: Bool = true
    ) -> CapturePomodoroThemeRef {
        CapturePomodoroThemeRef(
            key: key,
            name: name,
            hue: hue,
            hueSource: hueSource,
            known: known
        )
    }

    // MARK: - Resolver

    func testSwatchesResolveComponentsInOrder() {
        let swatches = PomodoroThemeSwatches.swatches(
            forName: "BOB + DECKS",
            refs: [
                ref(key: "bob", name: "BOB", hue: .magenta, hueSource: "hash"),
                ref(key: "decks", name: "DECKS", hue: .blue, hueSource: "hash"),
            ]
        )

        XCTAssertEqual(swatches, [
            CaptureThemeSwatch(hue: .magenta, known: true),
            CaptureThemeSwatch(hue: .blue, known: true),
        ])
    }

    func testSwatchesLeaveUnknownComponentsNeutral() {
        let swatches = PomodoroThemeSwatches.swatches(
            forName: "BOB + NEW",
            refs: [ref(key: "bob", name: "BOB", hue: .magenta, hueSource: "hash")]
        )

        XCTAssertEqual(swatches, [
            CaptureThemeSwatch(hue: .magenta, known: true),
            CaptureThemeSwatch(hue: nil, known: false),
        ])
    }

    func testSwatchesMatchKeysCaseInsensitively() {
        let swatches = PomodoroThemeSwatches.swatches(
            forName: "bob",
            refs: [ref(key: "bob", name: "BOB", hue: .magenta, hueSource: "hash")]
        )

        XCTAssertEqual(swatches, [CaptureThemeSwatch(hue: .magenta, known: true)])
    }

    func testSwatchesAreEmptyForBlankNames() {
        XCTAssertTrue(PomodoroThemeSwatches.swatches(forName: nil, refs: []).isEmpty)
        XCTAssertTrue(PomodoroThemeSwatches.swatches(forName: "  ", refs: []).isEmpty)
    }

    func testSwatchesKeepFirstRefWhenKeysRepeat() {
        let swatches = PomodoroThemeSwatches.swatches(
            forName: "FIX + fix",
            refs: [
                ref(key: "fix", name: "FIX", hue: .red, hueSource: "config"),
                ref(key: "fix", name: "fix", hue: .red, hueSource: "hash"),
            ]
        )

        XCTAssertEqual(swatches, [
            CaptureThemeSwatch(hue: .red, known: true),
            CaptureThemeSwatch(hue: .red, known: true),
        ])
    }

    func testSwatchesCarryUnconfiguredFlag() {
        let swatches = PomodoroThemeSwatches.swatches(
            forName: "SNACK",
            refs: [
                CapturePomodoroThemeRef(
                    key: "snack",
                    name: "SNACK",
                    hueSource: "unconfigured",
                    configured: false
                ),
            ]
        )

        XCTAssertEqual(
            swatches,
            [CaptureThemeSwatch(hue: nil, known: true, configured: false)]
        )
    }

    func testSpokenColorsNameHuesAndMuted() {
        let spoken = PomodoroThemeSwatches.spokenThemeColors(
            forName: "BOB + GTD",
            refs: [
                ref(key: "bob", name: "BOB", hue: .magenta, hueSource: "pin"),
                ref(key: "gtd", name: "GTD", hueSource: "exempt"),
            ]
        )

        XCTAssertEqual(spoken, ["BOB, magenta", "GTD, muted"])
    }

    func testSpokenColorsCallOutUnknownThemes() {
        let spoken = PomodoroThemeSwatches.spokenThemeColors(
            forName: "NEW",
            refs: []
        )

        XCTAssertEqual(spoken, ["NEW, unknown type"])
    }

    func testSpokenColorsCallOutUnconfiguredAndConfigSources() {
        let spoken = PomodoroThemeSwatches.spokenThemeColors(
            forName: "BUILD + SNACK",
            refs: [
                CapturePomodoroThemeRef(
                    key: "build",
                    name: "BUILD",
                    hue: .yellow,
                    hueSource: "config",
                    configured: true
                ),
                CapturePomodoroThemeRef(
                    key: "snack",
                    name: "SNACK",
                    hueSource: "unconfigured",
                    configured: false
                ),
            ]
        )

        XCTAssertEqual(
            spoken,
            ["BUILD, yellow", "SNACK, muted, not in your types"]
        )
    }

    // MARK: - Span themes decode

    func testSpanDecodesThemeRefs() throws {
        let data = Data(
            """
            {"start":3,"end":6,"kind":"pomodoro_name",
             "themes":[{"key":"bob","name":"BOB","hue":"magenta","hue_source":"hash",
             "start":3,"end":6}]}
            """.utf8
        )
        let span = try JSONDecoder().decode(CaptureSpan.self, from: data)

        XCTAssertEqual(span.themes.count, 1)
        XCTAssertEqual(span.themes.first?.hue, .magenta)
        XCTAssertEqual(span.themes.first?.start, 3)
        XCTAssertEqual(span.themes.first?.end, 6)
        XCTAssertNil(span.themes.first?.configured)
    }

    func testSpanDecodesConfiguredFlag() throws {
        let data = Data(
            """
            {"start":1,"end":6,"kind":"pomodoro_name",
             "themes":[{"key":"snack","name":"SNACK","hue":null,
             "hue_source":"unconfigured","configured":false,"start":1,"end":6}]}
            """.utf8
        )
        let span = try JSONDecoder().decode(CaptureSpan.self, from: data)

        XCTAssertEqual(span.themes.first?.configured, false)
        XCTAssertEqual(span.themes.first?.hueSource, "unconfigured")
        XCTAssertTrue(span.themes.first?.isUnconfigured ?? false)
    }

    func testSpanWithoutThemesDecodesEmpty() throws {
        let data = Data("{\"start\":0,\"end\":5,\"kind\":\"route\"}".utf8)
        let span = try JSONDecoder().decode(CaptureSpan.self, from: data)

        XCTAssertTrue(span.themes.isEmpty)
    }

    // MARK: - Budget added_theme_refs

    func testBudgetDecodesAddedThemeRefs() throws {
        let data = Data(
            """
            {"status":"ok","themes":{"count":2,"cap":5,"over":false,"before":1},
             "links":{"count":3,"cap":10,"over":false,"before":3},
             "added_themes":["BOB"],
             "added_theme_refs":[{"key":"bob","name":"BOB","hue":"magenta","hue_source":"hash"}]}
            """.utf8
        )
        let budget = try JSONDecoder().decode(CapturePlanBudget.self, from: data)

        XCTAssertEqual(budget.addedThemes, ["BOB"])
        XCTAssertEqual(
            budget.addedThemeRefs,
            [CapturePomodoroThemeRef(key: "bob", name: "BOB", hue: .magenta, hueSource: "hash")]
        )
    }

    func testOlderBudgetWithoutAddedRefsDecodesEmpty() throws {
        let data = Data(
            """
            {"status":"ok","themes":{"count":1,"cap":5,"over":false},
             "links":{"count":1,"cap":10,"over":false}}
            """.utf8
        )
        let budget = try JSONDecoder().decode(CapturePlanBudget.self, from: data)

        XCTAssertTrue(budget.addedThemeRefs.isEmpty)
    }

    func testDeltaSwatchesFollowAddedThemesInOrder() {
        let budget = CapturePlanBudget(
            status: "ok",
            themes: CapturePlanBudgetMeter(count: 2, cap: 5, over: false, before: 1),
            links: CapturePlanBudgetMeter(count: 1, cap: 10, over: false, before: 1),
            addedThemes: ["BOB"],
            addedThemeRefs: [
                ref(key: "bob", name: "BOB", hue: .magenta, hueSource: "hash"),
            ]
        )
        let presentation = CapturePlanBudgetPresentation(budget: budget, destination: nil)

        XCTAssertEqual(presentation.deltaChipText, "+1 BOB")
        XCTAssertEqual(
            presentation.deltaThemeSwatches,
            [CaptureThemeSwatch(hue: .magenta, known: true)]
        )
    }

    func testPreviewSwatchesAreEmptyWithoutABudget() {
        let endpoint = PomodoroLinkEndpoint(line: 3, name: "BOB", role: "created")

        XCTAssertTrue(
            CapturePlanBudgetPresentation.destinationThemeSwatches(
                destination: endpoint,
                budget: nil
            ).isEmpty
        )
        XCTAssertTrue(
            CapturePlanBudgetPresentation.swatches(forName: "BOB", budget: nil).isEmpty
        )
    }

    func testExistingDestinationResolvesNeutralWithoutBobRefs() {
        let budget = CapturePlanBudget(
            status: "ok",
            themes: CapturePlanBudgetMeter(count: 1, cap: 5, over: false, before: 1),
            links: CapturePlanBudgetMeter(count: 1, cap: 10, over: false, before: 1)
        )
        let endpoint = PomodoroLinkEndpoint(line: 3, name: "GOALS", role: "named")

        // Bob ships no endpoint refs, so the existing name degrades to a
        // neutral pill rather than a guessed hue.
        XCTAssertEqual(
            CapturePlanBudgetPresentation.swatches(forName: endpoint.name, budget: budget),
            [CaptureThemeSwatch(hue: nil, known: false)]
        )
    }

    // MARK: - Agenda entry themes

    func testAgendaEntryWithoutThemesDecodesEmpty() throws {
        let data = Data(
            """
            {"line":10,"name":"BOB","is_current":false,"role":"open",
             "retired_link_count":0,"notes":[],"items":[],"selectable":true}
            """.utf8
        )
        let entry = try JSONDecoder().decode(CaptureAgendaPomodoro.self, from: data)

        XCTAssertTrue(entry.themes.isEmpty)
    }

    func testHeaderRowCarriesThemeRefsAndHueWords() {
        let entry = CaptureAgendaPomodoro(
            line: 10,
            name: "BOB",
            role: .open,
            themes: [ref(key: "bob", name: "BOB", hue: .magenta, hueSource: "hash")]
        )
        let row = CaptureAgendaPresentation.makeHeaderRow(
            entry: entry,
            name: "BOB",
            spoken: "BOB",
            derived: false,
            homeChip: nil,
            homeHue: nil,
            themeRefs: entry.themes,
            now: nil
        )

        XCTAssertEqual(row.themeRefs.count, 1)
        XCTAssertEqual(row.themeSwatches, [CaptureThemeSwatch(hue: .magenta, known: true)])
        XCTAssertTrue(row.accessibilityLabel?.contains("BOB, magenta") ?? false)
    }

    func testHeaderRowWithoutRefsKeepsPlainLabel() {
        let entry = CaptureAgendaPomodoro(line: 10, name: "BOB", role: .open)
        let row = CaptureAgendaPresentation.makeHeaderRow(
            entry: entry,
            name: "BOB",
            spoken: "BOB",
            derived: false,
            homeChip: nil,
            homeHue: nil,
            now: nil
        )

        XCTAssertTrue(row.themeRefs.isEmpty)
        XCTAssertEqual(row.accessibilityLabel, "Header, BOB")
    }

}
