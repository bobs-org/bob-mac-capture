import XCTest

@testable import CaptureCore

/// Task-theme suggestion rendering for capture completion and capture
/// previews (phase mac-capture). Bob owns the rule; Swift only decodes the
/// additive fields and renders them.
final class CaptureTaskThemeTests: XCTestCase {
    // MARK: - Decode

    func testCompletionResponseDecodesThemeSuggestionAndSuggestedRow() throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(completionJSON.utf8)
        )

        XCTAssertEqual(response.context, "pomodoro_name")
        let suggestion = try XCTUnwrap(response.themeSuggestion)
        XCTAssertEqual(suggestion.theme.name, "WRITE")
        XCTAssertEqual(suggestion.source, "note")
        XCTAssertEqual(suggestion.label, "from sase_blog")
        XCTAssertEqual(suggestion.from?.stem, "sase_blog")
        XCTAssertEqual(suggestion.from?.hue, .magenta)
        XCTAssertNil(suggestion.fallback)
        XCTAssertFalse(suggestion.create)
        let suggested = response.candidates.filter(\.suggested)
        XCTAssertEqual(suggested.count, 1)
        XCTAssertEqual(suggested.first?.name, "WRITE")
        XCTAssertEqual(suggested.first?.suggestionLabel, "from sase_blog")
    }

    func testCompletionResponseOmitsThemeSuggestionForOlderBob() throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(
                """
                {"ok":true,"schema_version":1,"cursor":0,
                 "replacement":{"start":0,"end":0},"context":"pomodoro_name",
                 "candidates":[{"replacement":"build","name":"BUILD"}]}
                """.utf8
            )
        )

        XCTAssertNil(response.themeSuggestion)
        XCTAssertTrue(response.candidates.allSatisfy { !$0.suggested })
        XCTAssertTrue(response.candidates.allSatisfy { $0.suggestionLabel == nil })
    }

    func testCaptureDecodesTaskThemeSetAndCleared() throws {
        let set = try decodeSuccess(taskThemeJSON(action: "set"))
        XCTAssertEqual(set.taskTheme?.action, "set")
        XCTAssertEqual(set.taskTheme?.theme?.name, "FIX")
        XCTAssertEqual(set.taskTheme?.previous?.name, "WRITE")
        XCTAssertEqual(set.taskTheme?.inherited?.label, "from sase_blog")

        let cleared = try decodeSuccess(taskThemeJSON(action: "cleared"))
        XCTAssertEqual(cleared.taskTheme?.action, "cleared")
        XCTAssertNil(cleared.taskTheme?.theme)
    }

    func testCaptureOmitsTaskThemeForOlderBob() throws {
        let success = try decodeSuccess(
            """
            {"ok":true,"dry_run":true,"routed":true,"route":"sase",
             "route_label":"sase.md","relative_target":"sase.md",
             "target":"/tmp/bob/sase.md","text":"t","task_line":"- [ ] #task t ^t",
             "kind":"pomodoro_link","created":"2026-07-10","placement":"linked"}
            """
        )
        XCTAssertNil(success.taskTheme)
    }

    // MARK: - Completion row content

    func testSuggestedRowRendersReasonInSecondarySlot() throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(completionJSON.utf8)
        )
        let candidate = try XCTUnwrap(response.candidates.first(where: \.suggested))

        let content = completionRowContent(
            for: candidate,
            context: response.context,
            query: "",
            themeSuggestion: response.themeSuggestion
        )

        XCTAssertEqual(content.secondaryText, "Suggested · from ● sase_blog")
        XCTAssertEqual(content.suggestedFromHue, .magenta)
        XCTAssertTrue(content.badges.contains("Suggested"))
        XCTAssertTrue(
            content.accessibilityLabel.contains(
                "Pomodoro WRITE, suggested, from sase_blog"))
    }

    func testSuggestedRowFallsBackToLabelWithoutDot() {
        let candidate = CaptureCompletionCandidate(
            replacement: "read", name: "READ", suggested: true,
            suggestionLabel: "reading task")
        let content = completionRowContent(
            for: candidate, context: "pomodoro_name", query: "")

        XCTAssertEqual(content.secondaryText, "Suggested · reading task")
        XCTAssertNil(content.suggestedFromHue)
    }

    // MARK: - Preview line

    func testTaskThemeLineSetAndCleared() {
        let set = CaptureTaskThemeChange(
            action: "set",
            theme: CapturePomodoroThemeRef(key: "fix", name: "FIX"),
            previous: CapturePomodoroThemeRef(key: "write", name: "WRITE"),
            inherited: noteSuggestion())
        XCTAssertEqual(
            CaptureTaskThemePresentation.line(for: set, isDryRun: false),
            "task theme → FIX · sase_blog suggests WRITE")
        XCTAssertEqual(
            CaptureTaskThemePresentation.line(for: set, isDryRun: true),
            "would set task theme → FIX · sase_blog suggests WRITE")

        let cleared = CaptureTaskThemeChange(
            action: "cleared", inherited: noteSuggestion())
        XCTAssertEqual(
            CaptureTaskThemePresentation.line(for: cleared, isDryRun: false),
            "task theme cleared · sase_blog suggests WRITE")
        XCTAssertNil(CaptureTaskThemePresentation.line(for: nil, isDryRun: false))
    }

    func testTaskThemeInheritedPhraseCoversSources() {
        XCTAssertEqual(
            CaptureTaskThemePresentation.inheritedPhrase(nil), "no default here")
        // A task-source suggestion unwraps to the inherited note suggestion.
        let task = CaptureThemeSuggestion(
            theme: CapturePomodoroThemeRef(key: "fix", name: "FIX"),
            source: "task", label: "this task",
            inherited: CaptureThemeSuggestionBox(noteSuggestion()))
        XCTAssertEqual(
            CaptureTaskThemePresentation.inheritedPhrase(task),
            "sase_blog suggests WRITE")
        // A bare task-source suggestion reads as Bob's `this task suggests X`.
        let bareTask = CaptureThemeSuggestion(
            theme: CapturePomodoroThemeRef(key: "fix", name: "FIX"),
            source: "task", label: "this task")
        XCTAssertEqual(
            CaptureTaskThemePresentation.inheritedPhrase(bareTask),
            "this task suggests FIX")
    }

    func testLinkAndTogglePresentationsIncludeTaskThemeLine() throws {
        let theme = CaptureTaskThemeChange(
            action: "set",
            theme: CapturePomodoroThemeRef(key: "fix", name: "FIX"),
            inherited: noteSuggestion())
        // The test helpers build dry-run captures, so the line reads `would set`.
        let link = try XCTUnwrap(
            CapturePomodoroLinkPresentation(capture: linkCapture(taskTheme: theme)))
        XCTAssertEqual(
            link.taskThemeLine,
            "would set task theme → FIX · sase_blog suggests WRITE")
        XCTAssertTrue(
            link.notificationBody.contains(
                "would set task theme → FIX · sase_blog suggests WRITE"))
        XCTAssertTrue(
            link.previewAccessibilitySummary.contains("would set task theme → FIX"))

        let toggle = try XCTUnwrap(
            CaptureTogglePresentation(capture: toggleCapture(taskTheme: theme)))
        XCTAssertEqual(
            toggle.taskThemeLine,
            "would set task theme → FIX · sase_blog suggests WRITE")
        XCTAssertTrue(toggle.notificationBody.contains("would set task theme"))
        XCTAssertTrue(toggle.previewAccessibilitySummary.contains("would set task theme"))
        XCTAssertTrue(toggle.voiceOverAnnouncement.contains("would set task theme"))
    }

    // MARK: - Helpers

    private var completionJSON: String {
        """
        {"ok":true,"schema_version":1,"cursor":9,
         "replacement":{"start":0,"end":9},"context":"pomodoro_name",
         "candidates":[
           {"replacement":"write","name":"WRITE","suggested":true,
            "suggestion_label":"from sase_blog",
            "state":"open","status_symbol":" ","time_range":null,
            "placeholder":false,"is_current":false,"child_count":0,"match_count":1},
           {"replacement":"build","name":"BUILD",
            "state":"open","status_symbol":" ","time_range":null,
            "placeholder":false,"is_current":false,"child_count":0,"match_count":1}],
         "theme_suggestion":{
           "theme":{"key":"write","name":"WRITE","hue":"magenta","hue_source":"hash"},
           "source":"note","label":"from sase_blog",
           "from":{"path":"sase_blog.md","stem":"sase_blog","kind":"project",
                   "hue":"magenta","chain":["sase_pre_blog.md","sase_blog.md"]}}}
        """
    }

    private func taskThemeJSON(action: String) -> String {
        let theme = action == "set"
            ? "\"theme\":{\"key\":\"fix\",\"name\":\"FIX\"},"
                + "\"previous\":{\"key\":\"write\",\"name\":\"WRITE\"},"
            : "\"theme\":null,"
        return """
        {"ok":true,"dry_run":true,"routed":true,"route":"sase",
         "route_label":"sase.md","relative_target":"sase.md",
         "target":"/tmp/bob/sase.md","text":"t","task_line":"- [ ] #task t ^t",
         "kind":"pomodoro_link","created":"2026-07-10","placement":"linked",
         "task_theme":{"action":"\(action)",\(theme)
          "inherited":{"theme":{"key":"write","name":"WRITE"},
           "source":"note","label":"from sase_blog",
           "from":{"path":"sase_blog.md","stem":"sase_blog","kind":"project",
                   "hue":"blue","chain":["sase_blog.md"]}}}}
        """
    }

    private func decodeSuccess(_ json: String) throws -> CaptureCommandSuccess {
        let decoded = try JSONDecoder().decode(
            CaptureCommandResponse.self, from: Data(json.utf8))
        guard case .success(let success) = decoded else {
            throw NSError(domain: "test", code: 1)
        }
        return success
    }

    private func noteSuggestion() -> CaptureThemeSuggestion {
        CaptureThemeSuggestion(
            theme: CapturePomodoroThemeRef(key: "write", name: "WRITE"),
            source: "note",
            label: "from sase_blog",
            from: CaptureThemeSuggestionFrom(
                path: "sase_blog.md", stem: "sase_blog", kind: "project",
                hue: .blue, chain: ["sase_blog.md"]))
    }

    private func linkCapture(taskTheme: CaptureTaskThemeChange) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true, dryRun: true, routed: true, route: "sase",
            routeLabel: "sase.md", relativeTarget: "sase.md",
            target: "/tmp/bob/sase.md", text: "", taskLine: "- [*] #task Fix ^fix",
            kind: "pomodoro_link", created: "2026-07-10", placement: "linked",
            blockID: "fix", dayFile: "/tmp/bob/2026/20260710.md",
            blockLink: "[[sase#^fix]]",
            statusSymbol: "*", statusName: "Next",
            previousStatusSymbol: " ", previousStatusName: "Todo",
            pomodoroName: "FIX", statusChanged: true,
            pomodoroLinkAction: "linked",
            pomodoroLinkDestination: PomodoroLinkEndpoint(line: 5, name: "FIX"),
            taskTheme: taskTheme)
    }

    private func toggleCapture(taskTheme: CaptureTaskThemeChange) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true, dryRun: true, routed: true, route: "sase",
            routeLabel: "sase.md", relativeTarget: "sase.md",
            target: "/tmp/bob/sase.md", text: "", taskLine: "- [*] #task Fix ^fix",
            kind: "task_toggle", created: "2026-07-10", placement: "toggled",
            blockID: "fix", dayFile: "/tmp/bob/2026/20260710.md",
            toggleDirection: "next",
            statusSymbol: "*", statusName: "Next",
            previousStatusSymbol: " ", previousStatusName: "Todo",
            taskTheme: taskTheme)
    }
}
