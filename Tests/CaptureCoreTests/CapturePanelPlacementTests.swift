import XCTest

@testable import CaptureCore

final class CapturePanelPlacementTests: XCTestCase {
    private func frame(height: Double = 900) -> CapturePanelPlacement.VisibleFrame {
        CapturePanelPlacement.VisibleFrame(minX: 0, minY: 0, width: 1440, height: height)
    }

    func testEyeLineIsCenteredCompactTop() {
        var placement = CapturePanelPlacement()
        // A 200 pt compact panel on a 900 pt screen centers at
        // y = 350 with height 200, so the top is 550.
        let top = placement.eyeLineTop(
            compactContentHeight: 180,
            chromeHeight: 20,
            visibleFrame: frame()
        )
        XCTAssertEqual(top, 550)
    }

    func testEyeLineCachesPerVisibleFrame() {
        var placement = CapturePanelPlacement()
        let first = placement.eyeLineTop(
            compactContentHeight: 180,
            chromeHeight: 20,
            visibleFrame: frame()
        )
        // A different compact height on the same screen reuses the
        // cached top: every show puts the input line in one place.
        let second = placement.eyeLineTop(
            compactContentHeight: 400,
            chromeHeight: 20,
            visibleFrame: frame()
        )
        XCTAssertEqual(first, second)
        // A new screen re-derives the line.
        let moved = placement.eyeLineTop(
            compactContentHeight: 400,
            chromeHeight: 20,
            visibleFrame: frame(height: 1080)
        )
        XCTAssertNotEqual(moved, second)
    }

    func testInvalidateForgetsCachedTop() {
        var placement = CapturePanelPlacement()
        XCTAssertNil(placement.lastCachedTop)
        _ = placement.eyeLineTop(
            compactContentHeight: 180,
            chromeHeight: 20,
            visibleFrame: frame()
        )
        XCTAssertNotNil(placement.lastCachedTop)
        placement.invalidate()
        XCTAssertNil(placement.lastCachedTop)
    }

    func testOriginYPreservesTopEdge() {
        // A 550 pt eye line with a 300 pt panel lands the origin at
        // 250 regardless of the target height.
        XCTAssertEqual(
            CapturePanelPlacement.originY(
                topEdge: 550,
                contentHeight: 280,
                chromeHeight: 20
            ),
            250
        )
        XCTAssertEqual(
            CapturePanelPlacement.originY(
                topEdge: 550,
                contentHeight: 100,
                chromeHeight: 20
            ),
            430
        )
    }
}

final class CaptureAgendaVisibilityTests: XCTestCase {
    func testVisibleOnlyWhenEveryConditionHolds() {
        XCTAssertTrue(
            CaptureAgendaVisibility.isVisible(
                settingOn: true,
                draftBlank: true,
                regionFree: true,
                previewIdle: true,
                hasPlan: true
            )
        )
    }

    func testEachConditionHidesTheAgenda() {
        let visible = (
            settingOn: true,
            draftBlank: true,
            regionFree: true,
            previewIdle: true,
            hasPlan: true
        )
        XCTAssertFalse(
            CaptureAgendaVisibility.isVisible(
                settingOn: false,
                draftBlank: visible.draftBlank,
                regionFree: visible.regionFree,
                previewIdle: visible.previewIdle,
                hasPlan: visible.hasPlan
            )
        )
        XCTAssertFalse(
            CaptureAgendaVisibility.isVisible(
                settingOn: visible.settingOn,
                draftBlank: false,
                regionFree: visible.regionFree,
                previewIdle: visible.previewIdle,
                hasPlan: visible.hasPlan
            )
        )
        XCTAssertFalse(
            CaptureAgendaVisibility.isVisible(
                settingOn: visible.settingOn,
                draftBlank: visible.draftBlank,
                regionFree: false,
                previewIdle: visible.previewIdle,
                hasPlan: visible.hasPlan
            )
        )
        XCTAssertFalse(
            CaptureAgendaVisibility.isVisible(
                settingOn: visible.settingOn,
                draftBlank: visible.draftBlank,
                regionFree: visible.regionFree,
                previewIdle: false,
                hasPlan: visible.hasPlan
            )
        )
        XCTAssertFalse(
            CaptureAgendaVisibility.isVisible(
                settingOn: visible.settingOn,
                draftBlank: visible.draftBlank,
                regionFree: visible.regionFree,
                previewIdle: visible.previewIdle,
                hasPlan: false
            )
        )
    }
}
