import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Compact task-type menu geometry and gated PNG review.
final class CaptureTaskTypeDesignTests: XCTestCase {
    func testTaskTypeViewportFitsSevenRowsAndCapsAtEight() {
        XCTAssertEqual(CapturePanelLayout.taskTypeVisibleRows, 8)
        XCTAssertEqual(CapturePanelLayout.taskTypeRowHeight, 30)
        XCTAssertEqual(CapturePanelLayout.taskTypeHeaderHeight, 22)
        XCTAssertEqual(CapturePanelLayout.taskTypeFooterHeight, 28)
        // 12 + 22 + rows*30 + 28
        XCTAssertEqual(CapturePanelLayout.taskTypeViewportHeight(rowCount: 1), 92)
        XCTAssertEqual(CapturePanelLayout.taskTypeViewportHeight(rowCount: 7), 272)
        XCTAssertEqual(CapturePanelLayout.taskTypeViewportHeight(rowCount: 8), 302)
        XCTAssertEqual(
            CapturePanelLayout.taskTypeViewportHeight(rowCount: 9),
            CapturePanelLayout.taskTypeViewportHeight(rowCount: 8)
        )
        XCTAssertEqual(
            CapturePanelLayout.taskTypeViewportHeight(rowCount: 0),
            CapturePanelLayout.taskTypeViewportHeight(rowCount: 1)
        )
        XCTAssertNotEqual(
            CapturePanelLayout.taskTypeViewportHeight(rowCount: 7),
            CapturePanelLayout.completionViewportHeight
        )
    }

    @MainActor
    func testRenderTaskTypeMenuAndRelocationPreview() throws {
        let empty = try decodeCompletion("task-type-complete-empty.json")
        let menu = CaptureTaskTypeMenuPresentation(response: empty, today: "2026-10-30")
        let typed = try decodeCompletion("task-type-complete-typed-unknown.json")
        let typedMenu = CaptureTaskTypeMenuPresentation(response: typed, today: "2026-10-30")
        let set = try decodeSuccess("task-type-capture-set.json")
        let move = CaptureCommandSuccess(
            ok: true, dryRun: false, routed: true, route: "sase",
            routeLabel: "sase.md", relativeTarget: "sase.md",
            target: "/tmp/bob/sase.md", text: "Fix parser",
            taskLine: "- [ ] #task Fix parser [type:: FIX] ^fix-x",
            kind: "pomodoro_link", created: "2026-10-30", placement: "linked",
            taskTheme: set.taskTheme,
            typeRelocation: CaptureTypeRelocation(
                outcome: "move_to", from: "BUILD", to: "FIX")
        )

        for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
            try RenderFixtureWriter.write(
                CaptureTaskTypeMenuView(
                    presentation: menu, selectedIndex: 0, onSelect: { _ in }),
                name: "capture-task-type-menu",
                width: 520,
                appearance: appearance
            )
            try RenderFixtureWriter.write(
                CaptureTaskTypeMenuView(
                    presentation: typedMenu, selectedIndex: 0, onSelect: { _ in }),
                name: "capture-task-type-menu-typed",
                width: 520,
                appearance: appearance
            )
            let preview = taskTypePreviewCard(move)
            try RenderFixtureWriter.write(
                preview,
                name: "capture-task-type-relocation-preview",
                width: 520,
                appearance: appearance
            )
        }
    }

    @MainActor
    private func taskTypePreviewCard(_ success: CaptureCommandSuccess) -> some View {
        let line = CaptureTaskThemePresentation.line(
            for: success.taskTheme, isDryRun: success.dryRun)
        let relocation = CaptureTaskThemePresentation.relocationLine(
            for: success.typeRelocation)
        return VStack(alignment: .leading, spacing: 8) {
            if let line {
                HStack(spacing: 6) {
                    Text("Type")
                        .foregroundStyle(.secondary)
                    if let theme = success.taskTheme?.theme {
                        PomodoroThemePillView(
                            name: theme.name, swatch: CaptureThemeSwatch(theme))
                    }
                    Text(line)
                        .font(.system(.callout, design: .monospaced))
                }
            }
            if let relocation {
                Text(relocation)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func decodeCompletion(_ name: String) throws -> CaptureCompletionResponse {
        try JSONDecoder().decode(CaptureCompletionResponse.self, from: fixtureData(name))
    }

    private func decodeSuccess(_ name: String) throws -> CaptureCommandSuccess {
        let decoded = try JSONDecoder().decode(
            CaptureCommandResponse.self, from: fixtureData(name))
        guard case .success(let success) = decoded else {
            throw NSError(domain: "CaptureTaskTypeDesignTests", code: 1)
        }
        return success
    }

    private func fixtureData(_ name: String) throws -> Data {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        return try Data(contentsOf: fixtures.appendingPathComponent(name))
    }
}
