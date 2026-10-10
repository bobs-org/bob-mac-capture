import XCTest

@testable import CaptureCore

final class CapturePanelPlacementTests: XCTestCase {
    private func frame(height: Double = 900) -> CapturePanelPlacement.VisibleFrame {
        CapturePanelPlacement.VisibleFrame(minX: 0, minY: 0, width: 1440, height: height)
    }

    func testStoresProvidedTop() {
        var placement = CapturePanelPlacement()
        XCTAssertNil(placement.cachedTop(for: frame()))
        // The controller reads this top back from the centred compact
        // panel; the placement only remembers it.
        placement.noteCompactTop(550, visibleFrame: frame())
        XCTAssertEqual(placement.cachedTop(for: frame()), 550)
    }

    func testCachesPerVisibleFrame() {
        var placement = CapturePanelPlacement()
        placement.noteCompactTop(550, visibleFrame: frame())
        // A new note on the same screen overwrites: every show puts
        // the input line in one place.
        placement.noteCompactTop(560, visibleFrame: frame())
        XCTAssertEqual(placement.cachedTop(for: frame()), 560)
        // A new screen has no recorded top until derived; noting it
        // replaces the single cached screen.
        XCTAssertNil(placement.cachedTop(for: frame(height: 1080)))
        placement.noteCompactTop(640, visibleFrame: frame(height: 1080))
        XCTAssertEqual(
            placement.cachedTop(for: frame(height: 1080)),
            640
        )
        XCTAssertNil(placement.cachedTop(for: frame()))
    }

    func testInvalidateForgetsCachedTop() {
        var placement = CapturePanelPlacement()
        XCTAssertNil(placement.lastCachedTop)
        placement.noteCompactTop(550, visibleFrame: frame())
        XCTAssertNotNil(placement.lastCachedTop)
        placement.invalidate()
        XCTAssertNil(placement.lastCachedTop)
        XCTAssertNil(placement.cachedTop(for: frame()))
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
