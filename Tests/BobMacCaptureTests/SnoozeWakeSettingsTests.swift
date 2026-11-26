import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class SnoozeWakeSettingsTests: XCTestCase {
    private func makeSettings() -> (AppSettings, UserDefaults, String) {
        let suiteName = "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (AppSettings(defaults: defaults), defaults, suiteName)
    }

    func testSnoozeWakeSettingsDefaultToTrue() {
        let (settings, _, _) = makeSettings()
        XCTAssertTrue(settings.snoozeWakeAnnounce)
        XCTAssertTrue(settings.snoozeWakeChime)
        XCTAssertTrue(settings.snoozeWakeHoldWhileAway)
        XCTAssertTrue(settings.snoozeWakeHoldDuringMeetings)
    }

    func testSnoozeWakeSettingsPersist() {
        let (settings, defaults, _) = makeSettings()
        settings.snoozeWakeAnnounce = false
        settings.snoozeWakeChime = false
        settings.snoozeWakeHoldWhileAway = false
        settings.snoozeWakeHoldDuringMeetings = false

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.snoozeWakeAnnounce)
        XCTAssertFalse(reloaded.snoozeWakeChime)
        XCTAssertFalse(reloaded.snoozeWakeHoldWhileAway)
        XCTAssertFalse(reloaded.snoozeWakeHoldDuringMeetings)
        XCTAssertFalse(reloaded.snoozeWakeNoticeSettings.announceWakes)
        XCTAssertFalse(reloaded.snoozeWakeNoticeSettings.holdWhileAway)
        XCTAssertFalse(reloaded.snoozeWakeNoticeSettings.holdDuringMeetings)
    }

    func testNoticeSettingsBridgeExcludesChime() {
        let (settings, _, _) = makeSettings()
        settings.snoozeWakeChime = false
        let bridged: SnoozeWakeNoticeSettings = settings.snoozeWakeNoticeSettings
        XCTAssertTrue(bridged.announceWakes)
        XCTAssertTrue(bridged.holdWhileAway)
        XCTAssertTrue(bridged.holdDuringMeetings)
    }
}
