import XCTest

@testable import CaptureCore

final class CaptureUnconfiguredThemePresentationTests: XCTestCase {
    func testVisibleWarningsHoldBackConfiguredPrefixesWhileCaretIsAtEnd() {
        let warning = CaptureWarning.structured(
            StructuredCaptureWarning(
                code: "theme_not_configured",
                label: "BUI",
                message: "BUI isn't one of your types; tasks here keep their own types"
            )
        )
        let span = CapturePomodoroThemeRef(
            key: "bui",
            name: "BUI",
            configured: false,
            start: 1,
            end: 4
        )

        let held = CaptureUnconfiguredThemePresentation.visibleWarnings(
            from: [warning],
            draft: "=BUI",
            caretUTF8: 4,
            themeSpans: [span],
            configuredNames: ["BUILD", "PLAN"]
        )
        XCTAssertTrue(held.isEmpty)

        let shown = CaptureUnconfiguredThemePresentation.visibleWarnings(
            from: [warning],
            draft: "=BUI",
            caretUTF8: 0,
            themeSpans: [span],
            configuredNames: ["BUILD", "PLAN"]
        )
        XCTAssertEqual(shown.map(\.label), ["BUI"])
    }

    func testSnackWarnsEvenWithCaretAtEnd() {
        let warning = CaptureWarning.structured(
            StructuredCaptureWarning(
                code: "theme_not_configured",
                label: "SNACK",
                message: "SNACK isn't one of your types; tasks here keep their own types"
            )
        )
        let span = CapturePomodoroThemeRef(
            key: "snack",
            name: "SNACK",
            configured: false,
            start: 1,
            end: 6
        )
        let visible = CaptureUnconfiguredThemePresentation.visibleWarnings(
            from: [warning],
            draft: "=SNACK",
            caretUTF8: 6,
            themeSpans: [span],
            configuredNames: ["BUILD", "PLAN"]
        )
        XCTAssertEqual(visible.map(\.label), ["SNACK"])
    }

    func testNameItWarningsSkipConfiguredPrefixes() {
        let configured = [
            CaptureConfiguredTheme(key: "build", name: "BUILD", color: .yellow),
            CaptureConfiguredTheme(key: "plan", name: "PLAN", color: .blue),
        ]
        XCTAssertTrue(
            CaptureUnconfiguredThemePresentation.nameItWarnings(
                authoredName: "BUI",
                configuredThemes: configured
            ).isEmpty
        )
        XCTAssertTrue(
            CaptureUnconfiguredThemePresentation.nameItWarnings(
                authoredName: "BUILD",
                configuredThemes: configured
            ).isEmpty
        )
        let snack = CaptureUnconfiguredThemePresentation.nameItWarnings(
            authoredName: "SNACK",
            configuredThemes: configured
        )
        XCTAssertEqual(snack.map(\.label), ["SNACK"])
        XCTAssertEqual(
            snack.first?.message,
            "SNACK isn't one of your types; tasks here keep their own types"
        )
    }

    func testNameItSuggestionsKeepConfiguredVisibleRowsInConfigOrder() {
        let configured = [
            CaptureConfiguredTheme(key: "plan", name: "PLAN", color: .blue),
            CaptureConfiguredTheme(key: "build", name: "BUILD", color: .yellow),
            CaptureConfiguredTheme(key: "chore", name: "CHORE", color: .red),
        ]
        let list = [
            CapturePomodoroTheme(
                key: "snack",
                name: "SNACK",
                hidden: false,
                configured: false
            ),
            CapturePomodoroTheme(
                key: "build",
                name: "BUILD",
                hue: .yellow,
                hueSource: "config",
                configured: true
            ),
            CapturePomodoroTheme(
                key: "plan",
                name: "PLAN",
                hue: .blue,
                hueSource: "config",
                configured: true
            ),
            CapturePomodoroTheme(
                key: "chore",
                name: "CHORE",
                hidden: true,
                configured: true
            ),
        ]
        let chips = CaptureUnconfiguredThemePresentation.nameItSuggestions(
            configuredThemes: configured,
            list: list
        )
        XCTAssertEqual(chips.map(\.name), ["PLAN", "BUILD"])
    }

    func testSpokenColorNamesConfigAndUnconfigured() {
        XCTAssertEqual(
            CaptureUnconfiguredThemePresentation.spokenColor(
                for: CapturePomodoroThemeRef(
                    key: "build",
                    name: "BUILD",
                    hue: .yellow,
                    hueSource: "config",
                    configured: true
                )
            ),
            "BUILD, yellow"
        )
        XCTAssertEqual(
            CaptureUnconfiguredThemePresentation.spokenColor(
                for: CapturePomodoroThemeRef(
                    key: "snack",
                    name: "SNACK",
                    hueSource: "unconfigured",
                    configured: false
                )
            ),
            "SNACK, muted, not in your types"
        )
    }
}
