import XCTest

@testable import CaptureCore

/// Task-type completion, preview, and relocation rendering. Bob owns the
/// rule; Swift only decodes additive fields and paints them.
final class CaptureTaskTypeTests: XCTestCase {
    private let today = "2026-10-30"

    // MARK: - Decode

    func testEmptyCompletionDecodesConfiguredOrderAndKeepRow() throws {
        let response = try decodeCompletion("task-type-complete-empty.json")
        XCTAssertEqual(response.context, "task_type")
        XCTAssertEqual(response.subject, "new")
        XCTAssertEqual(response.query, "")
        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(
            response.candidates.map(\.name),
            ["BUILD", "FIX", "FIXUP", "PREFIX", "DEEP WORK", "WRITE"]
        )
        XCTAssertEqual(
            response.candidates.map(\.origin),
            Array(repeating: "configured", count: 6)
        )
        let write = try XCTUnwrap(response.candidates.last)
        XCTAssertEqual(write.effect, "keep")
        XCTAssertTrue(write.current)
        XCTAssertTrue(write.inherited)
        XCTAssertEqual(write.suggestionLabel, "from mac_inbox")
        XCTAssertEqual(response.themeSuggestion?.source, "note")
        XCTAssertEqual(response.themeSuggestion?.theme.name, "WRITE")
    }

    func testExistingCurrentCompletionDecodesCurrentKeepAndInheritedClear() throws {
        let response = try decodeCompletion("task-type-complete-existing-current.json")
        XCTAssertEqual(response.subject, "existing")
        XCTAssertEqual(response.themeSuggestion?.source, "task")
        XCTAssertEqual(response.themeSuggestion?.theme.name, "FIX")
        XCTAssertEqual(response.themeSuggestion?.inherited?.value.theme.name, "BUILD")
        let current = try XCTUnwrap(response.candidates.first(where: \.current))
        XCTAssertEqual(current.name, "FIX")
        XCTAssertEqual(current.effect, "keep")
        let inherited = try XCTUnwrap(response.candidates.first(where: \.inherited))
        XCTAssertEqual(inherited.name, "BUILD")
        XCTAssertEqual(inherited.effect, "clear")
    }

    func testTypedUnknownCompletionDecodesWarningAndSimilarity() throws {
        let response = try decodeCompletion("task-type-complete-typed-unknown.json")
        XCTAssertEqual(response.query, "fixs")
        let typed = try XCTUnwrap(response.candidates.first(where: { $0.origin == "typed" }))
        XCTAssertEqual(typed.name, "FIXS")
        XCTAssertEqual(typed.similarTo, ["FIX"])
        XCTAssertEqual(typed.effect, "set")
        XCTAssertNil(typed.refused)
        XCTAssertEqual(typed.themes.first?.configured, false)
    }

    func testHistoryCompletionUsesHistoryOrigin() throws {
        let response = try decodeCompletion("task-type-complete-history.json")
        XCTAssertFalse(response.candidates.isEmpty)
        XCTAssertTrue(response.candidates.allSatisfy { $0.origin == "history" })
    }

    func testHiddenExactKeepsFIXWhileEmptyHidesIt() throws {
        let hiddenEmpty = try decodeCompletion("task-type-complete-empty-hidden.json")
        XCTAssertFalse(hiddenEmpty.candidates.contains(where: { $0.name == "FIX" }))
        let exact = try decodeCompletion("task-type-complete-hidden-exact.json")
        XCTAssertEqual(exact.candidates.first?.name, "FIX")
    }

    func testOlderCompletionOmitsTaskTypeFields() throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(
                """
                {"ok":true,"schema_version":1,"cursor":0,
                 "replacement":{"start":0,"end":2},"context":"task_type",
                 "candidates":[{"replacement":"t:fix","name":"FIX"}]}
                """.utf8
            )
        )
        XCTAssertNil(response.subject)
        XCTAssertNil(response.query)
        XCTAssertNil(response.themeSuggestion)
        let candidate = try XCTUnwrap(response.candidates.first)
        XCTAssertFalse(candidate.current)
        XCTAssertFalse(candidate.inherited)
        XCTAssertNil(candidate.effect)
        XCTAssertNil(candidate.refused)
        XCTAssertFalse(candidate.hidden)
    }

    func testParseEmptyAndLiteralAndUnicodeAndMidline() throws {
        let empty = try decodeParse("task-type-parse-empty.json")
        XCTAssertEqual(empty.needs, ["task_type"])
        XCTAssertEqual(empty.spans.map(\.kind), ["task_type"])
        XCTAssertEqual(empty.spans.first?.start, 0)
        XCTAssertEqual(empty.spans.first?.end, 2)

        let literal = try decodeParse("task-type-parse-literal.json")
        let literalSpan = try XCTUnwrap(literal.spans.first(where: { $0.kind == "task_type" }))
        XCTAssertEqual(literalSpan.themes.first?.name, "DEEP WORK")

        let unicode = try decodeParse("task-type-parse-unicode.json")
        let name = try XCTUnwrap(unicode.spans.first(where: { $0.kind == "task_type" }))
        XCTAssertEqual(name.themes.first?.name, "FIX")
        let start = try XCTUnwrap(name.themes.first?.start)
        let end = try XCTUnwrap(name.themes.first?.end)
        let bytes = Array(unicode.input.utf8)
        XCTAssertEqual(String(decoding: bytes[start..<end], as: UTF8.self), "fix")

        let midline = try decodeParse("task-type-parse-midline.json")
        XCTAssertFalse(midline.spans.contains(where: { $0.kind == "task_type" }))
    }

    func testCaptureSetKeptClearedAndExisting() throws {
        let set = try decodeSuccess("task-type-capture-set.json")
        XCTAssertEqual(set.taskTheme?.action, "set")
        XCTAssertEqual(set.taskTheme?.theme?.name, "FIX")

        let kept = try decodeSuccess("task-type-capture-kept-inherited.json")
        XCTAssertEqual(kept.taskTheme?.action, "kept")
        XCTAssertEqual(kept.taskTheme?.theme?.name, "WRITE")

        let cleared = try decodeSuccess("task-type-capture-cleared.json")
        XCTAssertEqual(cleared.taskTheme?.action, "cleared")
        XCTAssertNil(cleared.taskTheme?.theme)

        let existing = try decodeSuccess("task-type-capture-set-existing.json")
        XCTAssertEqual(existing.taskTheme?.action, "set")
        XCTAssertEqual(existing.taskTheme?.theme?.name, "FIX")
        let commit = try decodeSuccess("task-type-capture-set-existing-commit.json")
        XCTAssertEqual(commit.taskTheme?.action, existing.taskTheme?.action)
        XCTAssertEqual(commit.dryRun, false)
    }

    func testRelocationFixturesDecodeOutcomes() throws {
        let cases: [(String, String, String?, String)] = [
            ("task-type-capture-rename-entry.json", "rename_entry", "BUILD", "FIX"),
            ("task-type-capture-append-component.json", "append_component", "BUILD", "BUILD + FIX"),
            ("task-type-capture-move-to.json", "move_to", "BUILD", "FIX"),
            ("task-type-capture-rename-placeholder.json", "rename_placeholder", "BUILD", "FIX"),
            ("task-type-capture-create-below.json", "create_below", nil, "FIX"),
        ]
        for (name, outcome, from, to) in cases {
            let success = try decodeSuccess(name)
            let relocation = try XCTUnwrap(success.typeRelocation, name)
            XCTAssertEqual(relocation.outcome, outcome, name)
            XCTAssertEqual(relocation.to, to, name)
            if let from {
                XCTAssertEqual(relocation.from, from, name)
            }
        }
    }

    func testOlderCaptureOmitsRelocation() throws {
        let success = try decodeSuccessJSON(
            """
            {"ok":true,"dry_run":true,"routed":true,"route":"sase",
             "route_label":"sase.md","relative_target":"sase.md",
             "target":"/tmp/bob/sase.md","text":"t","task_line":"- [ ] #task t ^t",
             "kind":"task","created":"2026-10-30","placement":"inserted"}
            """
        )
        XCTAssertNil(success.typeRelocation)
        XCTAssertNil(success.taskTheme)
    }

    // MARK: - Menu presentation

    func testHeaderCoversSubjectSources() throws {
        let existing = try decodeCompletion("task-type-complete-existing-current.json")
        let existingMenu = CaptureTaskTypeMenuPresentation(
            response: existing, today: today)
        XCTAssertEqual(existingMenu.title, "TASK TYPE")
        XCTAssertEqual(existingMenu.headerCaption, "this task is FIX")

        let inherited = try decodeCompletion("task-type-complete-existing-inherited.json")
        let inheritedMenu = CaptureTaskTypeMenuPresentation(
            response: inherited, today: today)
        XCTAssertTrue(inheritedMenu.headerCaption.contains("suggests"))

        let empty = CaptureTaskTypeMenuPresentation.header(subject: "new", suggestion: nil)
        XCTAssertEqual(empty.caption, "no default here")

        let reading = CaptureTaskTypeMenuPresentation.header(
            subject: "new",
            suggestion: CaptureThemeSuggestion(
                theme: CapturePomodoroThemeRef(key: "read", name: "READ"),
                source: "reading", label: "reading task")
        )
        XCTAssertEqual(reading.caption, "reading tasks suggest READ")

        let fallback = CaptureTaskTypeMenuPresentation.header(
            subject: "new",
            suggestion: CaptureThemeSuggestion(
                theme: CapturePomodoroThemeRef(key: "build", name: "BUILD"),
                source: "default", label: "default type")
        )
        XCTAssertEqual(fallback.caption, "default type suggests BUILD")
    }

    func testFooterSetClearKeepAndRefused() throws {
        let existing = try decodeCompletion("task-type-complete-existing-current.json")
        let current = try XCTUnwrap(existing.candidates.first(where: \.current))
        XCTAssertEqual(
            CaptureTaskTypeMenuPresentation.footer(
                for: current, subject: existing.subject,
                suggestion: existing.themeSuggestion),
            "stays FIX · from dev"
        )
        let clear = try XCTUnwrap(existing.candidates.first(where: { $0.effect == "clear" }))
        XCTAssertEqual(
            CaptureTaskTypeMenuPresentation.footer(
                for: clear, subject: existing.subject,
                suggestion: existing.themeSuggestion),
            "task type cleared · dev suggests BUILD"
        )
        let set = try XCTUnwrap(existing.candidates.first(where: { $0.name == "FIXUP" }))
        XCTAssertEqual(
            CaptureTaskTypeMenuPresentation.footer(
                for: set, subject: existing.subject,
                suggestion: existing.themeSuggestion),
            "this task becomes FIXUP · dev suggests BUILD"
        )

        let refused = CaptureCompletionCandidate(
            replacement: "t:fixs", name: "FIXS", origin: "typed",
            effect: "set", refused: "type_not_configured")
        XCTAssertEqual(
            CaptureTaskTypeMenuPresentation.footer(
                for: refused, subject: "new", suggestion: nil),
            "Add it under types: to use it"
        )
    }

    func testRowsPreserveOrderBadgesUsageAndQuotedQuery() throws {
        let empty = try decodeCompletion("task-type-complete-empty.json")
        let menu = CaptureTaskTypeMenuPresentation(response: empty, today: today)
        XCTAssertEqual(menu.rows.map(\.name), empty.candidates.map { $0.name ?? "" })
        XCTAssertEqual(
            menu.selectedFooter,
            "this task becomes BUILD · mac_inbox suggests WRITE"
        )
        let write = try XCTUnwrap(menu.rows.last)
        XCTAssertTrue(write.badges.contains("from mac_inbox"))
        XCTAssertEqual(write.usageCaption, "never used")

        let todayRow = try XCTUnwrap(menu.rows.first(where: { $0.name == "BUILD" }))
        XCTAssertEqual(todayRow.usageCaption, "today")

        let prefix = try decodeCompletion("task-type-complete-prefix.json")
        let prefixMenu = CaptureTaskTypeMenuPresentation(response: prefix, today: today)
        let fix = try XCTUnwrap(prefixMenu.rows.first(where: { $0.name == "FIX" }))
        XCTAssertEqual(fix.queryMatchRange, 0..<3)

        let literal = CaptureTaskTypeMenuPresentation(
            response: CaptureCompletionResponse(
                ok: true, cursor: 14,
                replacement: CaptureRange(start: 7, end: 14),
                context: "task_type",
                candidates: [
                    CaptureCompletionCandidate(
                        replacement: "t:\"DEEP WORK\" ",
                        name: "DEEP WORK",
                        themes: [
                            CapturePomodoroThemeRef(
                                key: "deep work", name: "DEEP WORK", hue: .violet,
                                hueSource: "config", configured: true)
                        ],
                        origin: "configured",
                        key: "deep work",
                        effect: "set"
                    )
                ],
                query: "deep"
            ),
            today: today
        )
        XCTAssertEqual(literal.rows.first?.queryMatchRange, 0..<4)

        let typed = try decodeCompletion("task-type-complete-typed-unknown.json")
        let typedMenu = CaptureTaskTypeMenuPresentation(response: typed, today: today)
        let typedRow = try XCTUnwrap(typedMenu.rows.first(where: \.isTyped))
        XCTAssertEqual(typedRow.similarCaption, "did you mean FIX?")
        XCTAssertTrue(typedRow.badges.contains(CaptureUnconfiguredThemePresentation.createBadge))
        XCTAssertEqual(typedMenu.listAccessibilityLabel, "Task type suggestions, 1 result")
        XCTAssertTrue(typedRow.accessibilityLabel.contains("FIXS"))
    }

    func testPinnedExemptHiddenAndCurrentBadges() {
        let pinned = CaptureCompletionCandidate(
            replacement: "t:fix ",
            name: "FIX",
            themes: [
                CapturePomodoroThemeRef(
                    key: "fix", name: "FIX", hue: .blue, hueSource: "pin",
                    configured: true)
            ],
            origin: "configured",
            key: "fix",
            current: true,
            effect: "keep"
        )
        let hidden = CaptureCompletionCandidate(
            replacement: "t:write ",
            name: "WRITE",
            themes: [
                CapturePomodoroThemeRef(
                    key: "write", name: "WRITE", hue: .magenta, hueSource: "exempt",
                    configured: true)
            ],
            origin: "history",
            hidden: true,
            key: "write",
            effect: "set"
        )
        let response = CaptureCompletionResponse(
            ok: true, cursor: 2, replacement: CaptureRange(start: 0, end: 2),
            context: "task_type", candidates: [pinned, hidden], query: "",
            subject: "existing"
        )
        let menu = CaptureTaskTypeMenuPresentation(response: response, today: today)
        XCTAssertTrue(menu.rows[0].badges.contains("Current"))
        XCTAssertTrue(menu.rows[0].badges.contains("Pinned"))
        XCTAssertTrue(menu.rows[1].badges.contains("Hidden"))
        XCTAssertTrue(menu.rows[1].badges.contains("Exempt"))
        XCTAssertEqual(menu.hideKeycap, "⌃D hide")
        let shown = CaptureTaskTypeMenuPresentation(
            response: response, selectedIndex: 1, today: today)
        XCTAssertEqual(shown.hideKeycap, "⌃D show")
    }

    func testUsageCaptionAndHideOverride() {
        XCTAssertEqual(
            CaptureTaskTypeMenuPresentation.usageCaption(
                lastUsed: today, daysUsed: 1, today: today),
            "today"
        )
        XCTAssertEqual(
            CaptureTaskTypeMenuPresentation.usageCaption(
                lastUsed: "2026-10-21", daysUsed: 1, today: today),
            "1 day"
        )
        XCTAssertEqual(
            CaptureTaskTypeMenuPresentation.usageCaption(
                lastUsed: "2026-10-21", daysUsed: 7, today: today),
            "7 days"
        )
        XCTAssertEqual(
            CaptureTaskTypeMenuPresentation.usageCaption(
                lastUsed: nil, daysUsed: nil, today: today),
            "never used"
        )

        let hidden = CaptureCompletionCandidate(
            replacement: "t:write ",
            name: "WRITE",
            themes: [
                CapturePomodoroThemeRef(key: "write", name: "WRITE", configured: true)
            ],
            origin: "history",
            hidden: true,
            key: "write",
            effect: "set"
        )
        XCTAssertTrue(
            captureThemeCurrentlyHidden(candidate: hidden, temporarilyHiddenThemeKey: nil))
        XCTAssertFalse(
            captureThemeCurrentlyHidden(
                candidate: hidden, temporarilyHiddenThemeKey: "write"))
        XCTAssertTrue(
            isTypedTaskTypeRow(
                CaptureCompletionCandidate(
                    replacement: "t:fixs", name: "FIXS", origin: "typed")))
    }

    func testRowContentUsesTaskTypeCategory() {
        let candidate = CaptureCompletionCandidate(
            replacement: "t:fix ", name: "FIX", origin: "configured", effect: "set")
        let content = completionRowContent(
            for: candidate, context: "task_type", query: "fi")
        XCTAssertEqual(content.category, .taskType)
        XCTAssertEqual(content.primaryText, "FIX")
        XCTAssertEqual(content.primaryMatchRange, 0..<2)
        XCTAssertEqual(content.contextLabel, "Task type")
    }

    // MARK: - Kept copy and relocation

    func testKeptCopyUsesSourceLabel() {
        let kept = CaptureTaskThemeChange(
            action: "kept",
            theme: CapturePomodoroThemeRef(key: "write", name: "WRITE"),
            inherited: CaptureThemeSuggestion(
                theme: CapturePomodoroThemeRef(key: "write", name: "WRITE"),
                source: "note", label: "from sase")
        )
        XCTAssertEqual(
            CaptureTaskThemePresentation.line(for: kept, isDryRun: false),
            "type WRITE · from sase"
        )
        XCTAssertEqual(
            CaptureTaskThemePresentation.line(for: kept, isDryRun: true),
            "would keep type WRITE · from sase"
        )
        let thisTask = CaptureTaskThemeChange(
            action: "kept",
            theme: CapturePomodoroThemeRef(key: "fix", name: "FIX"),
            previous: CapturePomodoroThemeRef(key: "fix", name: "FIX")
        )
        XCTAssertEqual(
            CaptureTaskThemePresentation.keptSourceLabel(for: thisTask),
            "this task"
        )
    }

    func testRelocationCopyCoversEveryOutcomeAndUnknown() {
        XCTAssertEqual(
            CaptureTaskThemePresentation.relocationLine(
                for: CaptureTypeRelocation(outcome: "rename_entry", from: "BUILD", to: "FIX")),
            "BUILD → FIX · running entry renamed"
        )
        XCTAssertEqual(
            CaptureTaskThemePresentation.relocationLine(
                for: CaptureTypeRelocation(
                    outcome: "append_component", from: "BUILD", to: "BUILD + FIX")),
            "BUILD → BUILD + FIX · running entry shared"
        )
        XCTAssertEqual(
            CaptureTaskThemePresentation.relocationLine(
                for: CaptureTypeRelocation(outcome: "move_to", from: "BUILD", to: "FIX")),
            "moved under FIX"
        )
        XCTAssertEqual(
            CaptureTaskThemePresentation.relocationLine(
                for: CaptureTypeRelocation(
                    outcome: "rename_placeholder", from: "BUILD", to: "FIX")),
            "BUILD → FIX · planned entry renamed"
        )
        XCTAssertEqual(
            CaptureTaskThemePresentation.relocationLine(
                for: CaptureTypeRelocation(outcome: "create_below", to: "FIX")),
            "moved under new FIX"
        )
        XCTAssertNil(
            CaptureTaskThemePresentation.relocationLine(
                for: CaptureTypeRelocation(outcome: "future_outcome", to: "FIX"))
        )
        XCTAssertNil(CaptureTaskThemePresentation.relocationLine(for: nil))
    }

    func testLinkPresentationIncludesRelocationLine() throws {
        let capture = CaptureCommandSuccess(
            ok: true, dryRun: true, routed: true, route: "sase",
            routeLabel: "sase.md", relativeTarget: "sase.md",
            target: "/tmp/bob/sase.md", text: "", taskLine: "- [*] #task Fix ^fix",
            kind: "pomodoro_link", created: "2026-10-30", placement: "linked",
            blockID: "fix", dayFile: "/tmp/bob/2026/20261030.md",
            blockLink: "[[sase#^fix]]",
            statusSymbol: "*", statusName: "Next",
            previousStatusSymbol: " ", previousStatusName: "Ready",
            pomodoroName: "FIX", statusChanged: true,
            pomodoroLinkAction: "linked",
            pomodoroLinkDestination: PomodoroLinkEndpoint(line: 5, name: "FIX"),
            taskTheme: CaptureTaskThemeChange(
                action: "set",
                theme: CapturePomodoroThemeRef(key: "fix", name: "FIX")),
            typeRelocation: CaptureTypeRelocation(
                outcome: "move_to", from: "BUILD", to: "FIX")
        )
        let link = try XCTUnwrap(CapturePomodoroLinkPresentation(capture: capture))
        XCTAssertEqual(link.typeRelocationLine, "moved under FIX")
        XCTAssertTrue(link.previewAccessibilitySummary.contains("moved under FIX"))
    }

    // MARK: - Helpers

    private func fixtureData(_ name: String) throws -> Data {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        return try Data(contentsOf: fixtures.appendingPathComponent(name))
    }

    private func decodeCompletion(_ name: String) throws -> CaptureCompletionResponse {
        try JSONDecoder().decode(CaptureCompletionResponse.self, from: fixtureData(name))
    }

    private func decodeParse(_ name: String) throws -> CaptureParseResponse {
        try JSONDecoder().decode(CaptureParseResponse.self, from: fixtureData(name))
    }

    private func decodeSuccess(_ name: String) throws -> CaptureCommandSuccess {
        try decodeSuccessData(fixtureData(name))
    }

    private func decodeSuccessJSON(_ json: String) throws -> CaptureCommandSuccess {
        try decodeSuccessData(Data(json.utf8))
    }

    private func decodeSuccessData(_ data: Data) throws -> CaptureCommandSuccess {
        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = decoded else {
            throw NSError(domain: "CaptureTaskTypeTests", code: 1)
        }
        return success
    }
}
