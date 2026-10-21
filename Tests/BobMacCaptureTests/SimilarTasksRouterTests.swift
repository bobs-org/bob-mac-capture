import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class SimilarTasksRouterTests: XCTestCase {
  private func keyEvent(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags = [],
    characters: String = "",
    ignoring: String? = nil
  ) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: ignoring ?? characters,
      isARepeat: false,
      keyCode: keyCode
    )!
  }

  private func digit(_ number: Int) -> NSEvent {
    let code: UInt16 = [18, 19, 20, 21, 23][number - 1]
    return keyEvent(keyCode: code, modifiers: .command, characters: "\(number)")
  }

  func testCommandDigitsFocusVisibleRows() {
    let router = CaptureKeyCommandRouter()
    for number in 1...5 {
      XCTAssertEqual(
        router.command(
          for: digit(number),
          context: CaptureKeyRoutingContext(similarRowsVisible: true)
        ),
        .focusSimilarRow(number)
      )
    }
  }

  func testCommandDigitsMatchByIgnoringModifiers() {
    let router = CaptureKeyCommandRouter()
    // Non-US layout: key code differs, ignoring-modifiers carries the digit.
    let event = keyEvent(keyCode: 50, modifiers: .command, characters: "@", ignoring: "2")
    XCTAssertEqual(
      router.command(
        for: event,
        context: CaptureKeyRoutingContext(similarRowsVisible: true)
      ),
      .focusSimilarRow(2)
    )
  }

  func testCommandDigitsNeedVisibleRows() {
    let router = CaptureKeyCommandRouter()
    XCTAssertNil(
      router.command(
        for: digit(1),
        context: CaptureKeyRoutingContext()
      )
    )
  }

  func testModalBranchesShadowCommandDigits() {
    let router = CaptureKeyCommandRouter()
    let event = digit(1)
    XCTAssertNotEqual(
      router.command(
        for: event,
        context: CaptureKeyRoutingContext(
          similarRowsVisible: true,
          pickerVisible: true
        )
      ),
      .focusSimilarRow(1)
    )
    XCTAssertNotEqual(
      router.command(
        for: event,
        context: CaptureKeyRoutingContext(
          similarRowsVisible: true,
          similarRowFocused: true,
          taskIDPromptVisible: true
        )
      ),
      .focusSimilarRow(1)
    )
  }

  func testFocusedStripKeys() {
    let router = CaptureKeyCommandRouter()
    let focused = CaptureKeyRoutingContext(
      similarRowsVisible: true,
      similarRowFocused: true
    )
    XCTAssertEqual(
      router.command(for: keyEvent(keyCode: 123, characters: ""), context: focused),
      .similarPreviousAction
    )
    XCTAssertEqual(
      router.command(for: keyEvent(keyCode: 124, characters: ""), context: focused),
      .similarNextAction
    )
    XCTAssertEqual(
      router.command(for: keyEvent(keyCode: 126, characters: ""), context: focused),
      .similarPreviousRow
    )
    XCTAssertEqual(
      router.command(for: keyEvent(keyCode: 125, characters: ""), context: focused),
      .similarNextRow
    )
    XCTAssertEqual(
      router.command(for: keyEvent(keyCode: 36, characters: "\r"), context: focused),
      .similarApplyDefault
    )
    XCTAssertEqual(
      router.command(for: keyEvent(keyCode: 53, characters: ""), context: focused),
      .similarUnfocus
    )
    XCTAssertEqual(
      router.command(
        for: keyEvent(keyCode: 33, modifiers: .control, characters: ""),
        context: focused
      ),
      .similarUnfocus
    )
    XCTAssertEqual(
      router.command(for: keyEvent(keyCode: 51, characters: ""), context: focused),
      .similarApply(.discard)
    )
  }

  func testFocusedSigilsApplyDirectly() {
    let router = CaptureKeyCommandRouter()
    let focused = CaptureKeyRoutingContext(
      similarRowsVisible: true,
      similarRowFocused: true
    )
    let cases: [(String, CaptureRelatedAction)] = [
      ("~", .relate), ("+", .note), ("&", .needs), ("*", .blocks), ("/", .open),
    ]
    for (character, action) in cases {
      XCTAssertEqual(
        router.command(
          for: keyEvent(keyCode: 42, characters: character),
          context: focused
        ),
        .similarApply(action)
      )
    }
  }

  func testFocusedModifiedReturnAndCommandZPassThrough() {
    let router = CaptureKeyCommandRouter()
    let focused = CaptureKeyRoutingContext(
      similarRowsVisible: true,
      similarRowFocused: true
    )
    XCTAssertNil(
      router.command(
        for: keyEvent(keyCode: 36, modifiers: .command, characters: "\r"),
        context: focused
      )
    )
    XCTAssertNil(
      router.command(
        for: keyEvent(keyCode: 6, modifiers: .command, characters: "z"),
        context: focused
      )
    )
    XCTAssertNil(
      router.command(
        for: keyEvent(keyCode: 0, characters: "a"),
        context: focused
      )
    )
  }

  func testUnfocusedReturnKeepsSubmit() {
    let router = CaptureKeyCommandRouter()
    XCTAssertEqual(
      router.command(
        for: keyEvent(keyCode: 36, characters: "\r"),
        context: CaptureKeyRoutingContext(similarRowsVisible: true)
      ),
      .submit
    )
  }
}
