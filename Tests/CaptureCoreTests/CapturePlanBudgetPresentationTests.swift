import Foundation
import XCTest

@testable import CaptureCore

final class CapturePlanBudgetPresentationTests: XCTestCase {
    // MARK: - Destination row

    func testCreatedRoleRendersNewPomodoroRow() {
        let endpoint = PomodoroLinkEndpoint(line: 3, name: "BOB", role: "created")

        XCTAssertEqual(
            CapturePlanBudgetPresentation.destinationRowText(for: endpoint),
            "→ new Pomodoro BOB"
        )
    }

    func testCurrentRoleRendersRunningRowWithEnDashRange() {
        let endpoint = PomodoroLinkEndpoint(
            line: 3,
            name: "GOALS",
            timeRange: "0945-1015",
            role: "current"
        )

        XCTAssertEqual(
            CapturePlanBudgetPresentation.destinationRowText(for: endpoint),
            "→ running GOALS 0945–1015"
        )
    }

    func testCurrentRoleWithoutRangeRendersBareRunningRow() {
        let endpoint = PomodoroLinkEndpoint(line: 3, name: "GOALS", role: "current")

        XCTAssertEqual(
            CapturePlanBudgetPresentation.destinationRowText(for: endpoint),
            "→ running GOALS"
        )
    }

    func testNextUpRoleRendersNextUpRow() {
        let endpoint = PomodoroLinkEndpoint(line: 3, name: "GOALS", role: "next_up")

        XCTAssertEqual(
            CapturePlanBudgetPresentation.destinationRowText(for: endpoint),
            "→ GOALS · next up"
        )
    }

    func testNamedRoleRendersNamedRow() {
        let endpoint = PomodoroLinkEndpoint(line: 3, name: "GOALS", role: "named")

        XCTAssertEqual(
            CapturePlanBudgetPresentation.destinationRowText(for: endpoint),
            "→ GOALS · named"
        )
    }

    func testMissingDestinationRendersNoRow() {
        XCTAssertNil(CapturePlanBudgetPresentation.destinationRowText(for: nil))
    }

    func testUnknownRoleFallsBackToBareName() {
        let endpoint = PomodoroLinkEndpoint(line: 3, name: "GOALS", role: "future_role")

        XCTAssertEqual(
            CapturePlanBudgetPresentation.destinationRowText(for: endpoint),
            "→ GOALS"
        )
    }

    func testMissingRoleFallsBackToBareName() {
        // Older Bob omits `role`; the row stays today's bare name.
        let endpoint = PomodoroLinkEndpoint(line: 5, name: "BUGS")

        XCTAssertEqual(
            CapturePlanBudgetPresentation.destinationRowText(for: endpoint),
            "→ BUGS"
        )
    }

    // MARK: - Meter row

    func testOverCapBudgetRendersCapsulesDeltaChipAndWarnings() throws {
        let success = try decodeCaptureSuccess(fixtureText("plan-budget-over.json"))
        let presentation = try XCTUnwrap(CapturePlanBudgetPresentation(capture: success))

        XCTAssertEqual(presentation.destinationRowText, "→ new Pomodoro NEWT")
        XCTAssertEqual(presentation.themesCapsuleText, "Themes 4/3")
        XCTAssertTrue(presentation.themesOverCap)
        XCTAssertEqual(presentation.linksCapsuleText, "Links 4/10")
        XCTAssertFalse(presentation.linksOverCap)
        XCTAssertEqual(presentation.deltaChipText, "+1 NEWT")
        XCTAssertEqual(presentation.warningTexts.count, 1)
        XCTAssertTrue(presentation.warningTexts[0].contains("4/3 themes (adds NEWT)"))
        // Both rows are in the accessibility summary.
        XCTAssertTrue(presentation.accessibilitySummary.contains("→ new Pomodoro NEWT"))
        XCTAssertTrue(presentation.accessibilitySummary.contains("Themes 4/3, Links 4/10"))
        XCTAssertTrue(presentation.accessibilitySummary.contains("+1 NEWT"))
    }

    func testQuietBudgetRendersNoDeltaChipOrWarnings() throws {
        let success = try decodeCaptureSuccess(
            fixtureText("plan-budget-destination-role.json")
        )
        let presentation = try XCTUnwrap(CapturePlanBudgetPresentation(capture: success))

        XCTAssertEqual(presentation.destinationRowText, "→ GOALS · named")
        XCTAssertEqual(presentation.themesCapsuleText, "Themes 3/3")
        XCTAssertFalse(presentation.themesOverCap)
        XCTAssertNil(presentation.deltaChipText)
        XCTAssertTrue(presentation.warningTexts.isEmpty)
    }

    func testInitReturnsNilWithoutPlanBudget() throws {
        let success = try decodeCaptureSuccess(
            """
            {"ok":true,"dry_run":true,"routed":true,"route":"cash","route_label":"cash.md",
             "relative_target":"cash.md","target":"/tmp/bob/cash.md","text":"Call bank",
             "task_line":"- [ ] #task Call bank [created::2026-08-14]","kind":"task",
             "created":"2026-08-14","scheduled":null,"placement":"inserted"}
            """
        )

        XCTAssertNil(CapturePlanBudgetPresentation(capture: success))
    }

    func testLinksDeltaWithoutThemeGrowthShowsNoDeltaChip() throws {
        let budget = CapturePlanBudget(
            status: "over",
            themes: CapturePlanBudgetMeter(count: 2, cap: 3, over: false, before: 2),
            links: CapturePlanBudgetMeter(count: 11, cap: 10, over: true, before: 10),
            warnings: [CapturePlanBudgetWarning(
                code: "plan_link_cap_exceeded",
                message: "today's plan now has 11/10 links"
            )]
        )

        let presentation = CapturePlanBudgetPresentation(budget: budget, destination: nil)

        XCTAssertNil(presentation.destinationRowText)
        XCTAssertEqual(presentation.linksCapsuleText, "Links 11/10")
        XCTAssertTrue(presentation.linksOverCap)
        XCTAssertNil(presentation.deltaChipText)
        XCTAssertEqual(
            presentation.accessibilitySummary,
            "Themes 2/3, Links 11/10, today's plan now has 11/10 links"
        )
    }

    // MARK: - Failure code

    func testStrictRefusalFixtureDecodesCode() throws {
        let data = Data(fixtureText("plan-budget-strict-refusal.json").utf8)
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: data
        )

        guard case .failure(let failure) = response else {
            return XCTFail("strict refusal should decode as a failure")
        }
        XCTAssertEqual(failure.code, "plan_theme_cap_exceeded")
        XCTAssertTrue(failure.error.contains("4/3 themes"))
    }

    func testOlderFailureWithoutCodeDecodesAsNil() throws {
        let data = Data(
            """
            {"ok":false,"error":"finish the current Pomodoro first"}
            """.utf8
        )
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: data
        )

        guard case .failure(let failure) = response else {
            return XCTFail("should decode as a failure")
        }
        XCTAssertNil(failure.code)
    }

    // MARK: - Completion cap badge

    func testCompletionCreateRowDecodesPlanThemes() throws {
        let data = Data(
            """
            {"ok":true,"schema_version":1,"cursor":20,
             "replacement":{"start":16,"end":20},"context":"pomodoro_name",
             "candidates":[{"replacement":"newt","name":"NEWT","requires_name":false,
             "creates_pomodoro":true,"plan_themes_after":4,"plan_themes_cap":3,
             "state":"open","status_symbol":" ","placeholder":true,"is_current":false,
             "child_count":0,"match_count":1}]}
            """.utf8
        )
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: data
        )

        let candidate = try XCTUnwrap(response.candidates.first)
        XCTAssertEqual(candidate.planThemesAfter, 4)
        XCTAssertEqual(candidate.planThemesCap, 3)

        let content = completionRowContent(
            for: candidate,
            context: "pomodoro_name",
            query: "NEW"
        )
        XCTAssertTrue(content.badges.contains("Create"))
        XCTAssertTrue(content.badges.contains("4/3"))
        XCTAssertTrue(content.accessibilityLabel.contains("4/3"))
    }

    func testCompletionCreateRowWithoutPlanThemesHasNoCapBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "newt",
            name: "NEWT",
            createsPomodoro: true
        )

        let content = completionRowContent(
            for: candidate,
            context: "pomodoro_name",
            query: ""
        )
        XCTAssertEqual(content.badges, ["Create"])
    }

    func testCompletionCreateRowWithinCapHasNoCapBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "goals",
            name: "GOALS",
            createsPomodoro: true,
            planThemesAfter: 3,
            planThemesCap: 3
        )

        let content = completionRowContent(
            for: candidate,
            context: "pomodoro_name",
            query: ""
        )
        XCTAssertEqual(content.badges, ["Create"])
    }

    // MARK: - Helpers

    private func decodeCaptureSuccess(_ json: String) throws -> CaptureCommandSuccess {
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: data
        )
        guard case .success(let success) = response else {
            throw PlanBudgetTestError.expectedSuccess
        }
        return success
    }

    private func fixtureText(_ name: String) throws -> String {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        return try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    }
}

private enum PlanBudgetTestError: Error {
    case expectedSuccess
}
