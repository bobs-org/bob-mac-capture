import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

final class RefsTodayLinkThemeTests: XCTestCase {
    func testRefsRowWithoutThemesRendersNoSwatches() throws {
        let data = Data(
            """
            {"ref":"note","name":"BOB","placeholder":false,"running":false,
             "default":false,"linked":false,"task_link_count":1}
            """.utf8
        )
        let row = try JSONDecoder().decode(RefsTodayLinkPomodoro.self, from: data)

        XCTAssertTrue(row.themes.isEmpty)
        XCTAssertTrue(RefsTodayLinkPresentation.themeSwatches(row).isEmpty)
        XCTAssertTrue(RefsTodayLinkPresentation.spokenThemeColors(row).isEmpty)
    }

    func testRefsRowWithThemesResolvesSwatches() {
        let row = RefsTodayLinkPomodoro(
            ref: "note",
            name: "BOB",
            themes: [
                CapturePomodoroThemeRef(
                    key: "bob",
                    name: "BOB",
                    hue: .magenta,
                    hueSource: "pin"
                ),
            ]
        )

        XCTAssertEqual(
            RefsTodayLinkPresentation.themeSwatches(row),
            [CaptureThemeSwatch(hue: .magenta, known: true)]
        )
        XCTAssertEqual(
            RefsTodayLinkPresentation.spokenThemeColors(row),
            ["BOB, magenta"]
        )
    }

    func testRefsRowAccessibilityNamesThemeHues() {
        let row = RefsTodayLinkPomodoro(
            ref: "note",
            name: "BOB",
            themes: [
                CapturePomodoroThemeRef(
                    key: "bob",
                    name: "BOB",
                    hue: .magenta,
                    hueSource: "pin"
                ),
            ]
        )

        let label = RefsTodayLinkPresentation.rowAccessibilityLabel(
            row,
            selected: false,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(label.contains("BOB, magenta"))
    }
}
