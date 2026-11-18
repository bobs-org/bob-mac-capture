import XCTest

@testable import CaptureCore

final class WalkAttentionToneTests: XCTestCase {
    func testEveryTierMatchesTheContractTable() {
        let expected: [String: (light: String, dark: String)] = [
            "pre": ("#00bfbc", "#53dfdd"),
            "new": ("#e93147", "#fb464c"),
            "projects": ("#7852ee", "#a882ff"),
            "pending": ("#e0ac00", "#e0de71"),
            "next": ("#08b94e", "#44cf6e"),
            "recurring": ("#d53984", "#fa99cd"),
            "tickler": ("#086ddd", "#027aff"),
            "over": ("#e93147", "#fb464c"),
            "waiting": ("#ec7500", "#e9973f"),
            "rotten": ("#ec7500", "#e9973f"),
            "post": ("#00bfbc", "#53dfdd"),
        ]
        for (tier, hexes) in expected {
            XCTAssertEqual(WalkAttentionTone.lightHex(for: tier), hexes.light, tier)
            XCTAssertEqual(WalkAttentionTone.darkHex(for: tier), hexes.dark, tier)
        }
    }

    func testCoincidentHuesReuseWorkBadgeTone() {
        XCTAssertEqual(
            WalkAttentionTone.lightHex(for: "post"),
            WalkAttentionTone.lightHex(for: "pre")
        )
        XCTAssertEqual(
            WalkAttentionTone.darkHex(for: "post"),
            WalkAttentionTone.darkHex(for: "pre")
        )
        XCTAssertEqual(WalkAttentionTone.lightHex(for: "new"), WorkBadgeTone.red.lightHex)
        XCTAssertEqual(WalkAttentionTone.darkHex(for: "new"), WorkBadgeTone.red.darkHex)
        XCTAssertEqual(WalkAttentionTone.lightHex(for: "over"), WorkBadgeTone.red.lightHex)
        XCTAssertEqual(WalkAttentionTone.darkHex(for: "over"), WorkBadgeTone.red.darkHex)
        XCTAssertEqual(
            WalkAttentionTone.lightHex(for: "pending"), WorkBadgeTone.yellow.lightHex)
        XCTAssertEqual(
            WalkAttentionTone.darkHex(for: "pending"), WorkBadgeTone.yellow.darkHex)
        XCTAssertEqual(
            WalkAttentionTone.lightHex(for: "next"), WorkBadgeTone.green.lightHex)
        XCTAssertEqual(WalkAttentionTone.darkHex(for: "next"), WorkBadgeTone.green.darkHex)
        XCTAssertEqual(
            WalkAttentionTone.lightHex(for: "tickler"), WorkBadgeTone.blue.lightHex)
        XCTAssertEqual(WalkAttentionTone.darkHex(for: "tickler"), WorkBadgeTone.blue.darkHex)
        XCTAssertEqual(
            WalkAttentionTone.lightHex(for: "waiting"), WorkBadgeTone.orange.lightHex)
        XCTAssertEqual(
            WalkAttentionTone.darkHex(for: "waiting"), WorkBadgeTone.orange.darkHex)
        XCTAssertEqual(
            WalkAttentionTone.lightHex(for: "rotten"), WorkBadgeTone.orange.lightHex)
        XCTAssertEqual(
            WalkAttentionTone.darkHex(for: "rotten"), WorkBadgeTone.orange.darkHex)
        XCTAssertEqual(WalkAttentionTone.lightHex(for: "post"), "#00bfbc")
        XCTAssertEqual(WalkAttentionTone.darkHex(for: "post"), "#53dfdd")
    }

    func testUnknownTierReturnsNil() {
        XCTAssertNil(WalkAttentionTone.lightHex(for: "nope"))
        XCTAssertNil(WalkAttentionTone.darkHex(for: "nope"))
        XCTAssertNil(WalkAttentionTone.lightHex(for: ""))
        XCTAssertNil(WalkAttentionTone.darkHex(for: ""))
    }
}
