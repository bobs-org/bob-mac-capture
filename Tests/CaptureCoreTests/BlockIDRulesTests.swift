import XCTest

@testable import CaptureCore

final class BlockIDRulesTests: XCTestCase {
    private func colonRules() -> BlockIDRules {
        BlockIDRules(
            allowedCharacter: "[A-Za-z0-9_-]",
            description: "A-Z, a-z, 0-9, '_' or '-'"
        )!
    }

    private func caretRules() -> BlockIDRules {
        BlockIDRules(
            allowedCharacter: "[A-Za-z0-9-]",
            description: "A-Z, a-z, 0-9 or '-'"
        )!
    }

    // MARK: - Grammar compilation

    func testBothBobGrammarsCompile() {
        XCTAssertNotNil(colonRules())
        XCTAssertNotNil(caretRules())
    }

    func testMissingOrUnparsablePatternReturnsNil() {
        XCTAssertNil(BlockIDRules(allowedCharacter: "", description: "x"))
        XCTAssertNil(BlockIDRules(allowedCharacter: "abc", description: "x"))
        XCTAssertNil(BlockIDRules(allowedCharacter: "[A-Z", description: "x"))
        XCTAssertNil(BlockIDRules(allowedCharacter: "[\\w]", description: "x"))
        XCTAssertNil(BlockIDRules(allowedCharacter: "[]", description: "x"))
    }

    // MARK: - Character membership

    func testColonGrammarAllowsUnderscore() {
        let rules = colonRules()
        XCTAssertTrue(rules.isAllowed("a"))
        XCTAssertTrue(rules.isAllowed("Z"))
        XCTAssertTrue(rules.isAllowed("0"))
        XCTAssertTrue(rules.isAllowed("_"))
        XCTAssertTrue(rules.isAllowed("-"))
        XCTAssertFalse(rules.isAllowed(" "))
        XCTAssertFalse(rules.isAllowed("#"))
        XCTAssertFalse(rules.isAllowed("="))
        XCTAssertFalse(rules.isAllowed("+"))
        XCTAssertFalse(rules.isAllowed("."))
        XCTAssertFalse(rules.isAllowed("é"))
    }

    func testCaretGrammarRejectsUnderscore() {
        let rules = caretRules()
        XCTAssertTrue(rules.isAllowed("a"))
        XCTAssertTrue(rules.isAllowed("-"))
        XCTAssertFalse(rules.isAllowed("_"))
        XCTAssertFalse(rules.isAllowed(" "))
        XCTAssertFalse(rules.isAllowed("#"))
    }

    // MARK: - Whole-ID validation

    func testIsValidRequiresNonEmptyAllAllowed() {
        let colon = colonRules()
        XCTAssertFalse(colon.isValid(""))
        XCTAssertTrue(colon.isValid("tool"))
        XCTAssertTrue(colon.isValid("tool-2"))
        XCTAssertTrue(colon.isValid("a_b"))
        XCTAssertFalse(colon.isValid("x y"))
        XCTAssertFalse(colon.isValid("a#b"))

        let caret = caretRules()
        XCTAssertTrue(caret.isValid("tool-2"))
        XCTAssertFalse(caret.isValid("a_b"))
    }

    // MARK: - Type-through splits

    func testTypeThroughSplitsOnSpaceHashEqualsAndPlus() {
        let rules = caretRules()
        XCTAssertEqual(
            rules.typeThroughSplit(old: "flaky", new: "flaky test").map { [$0.id, $0.remainder] },
            ["flaky", " test"]
        )
        XCTAssertEqual(
            rules.typeThroughSplit(old: "flaky", new: "flaky#bugs").map { [$0.id, $0.remainder] },
            ["flaky", "#bugs"]
        )
        XCTAssertEqual(
            rules.typeThroughSplit(old: "flaky", new: "flaky=3").map { [$0.id, $0.remainder] },
            ["flaky", "=3"]
        )
        XCTAssertEqual(
            rules.typeThroughSplit(old: "flaky", new: "flaky+x").map { [$0.id, $0.remainder] },
            ["flaky", "+x"]
        )
    }

    func testTypeThroughSplitKeepsRemainderAfterFirstDisallowedCharacter() {
        let rules = caretRules()
        let split = rules.typeThroughSplit(old: "x", new: "x y-z")
        XCTAssertEqual(split?.id, "x")
        XCTAssertEqual(split?.remainder, " y-z")
    }

    func testTypeThroughSplitFromEmptyOldCommitsBeforeFirstDisallowedCharacter() {
        let rules = caretRules()
        let split = rules.typeThroughSplit(old: "", new: "a b")
        XCTAssertEqual(split?.id, "a")
        XCTAssertEqual(split?.remainder, " b")
    }

    func testTypeThroughReturnsNilWithoutForwardAllowedPrefixExtension() {
        let rules = caretRules()
        XCTAssertNil(rules.typeThroughSplit(old: "flak", new: "flaky"))
        XCTAssertNil(rules.typeThroughSplit(old: "flaky", new: "flaky"))
        XCTAssertNil(rules.typeThroughSplit(old: "flaky", new: "flak"))
        XCTAssertNil(rules.typeThroughSplit(old: "flaky", new: "flXaky"))
        XCTAssertNil(rules.typeThroughSplit(old: "flaky", new: "other"))
    }

    // MARK: - Next-free variants

    func testNextFreeVariantFindsFirstFreeSuffix() {
        let rules = caretRules()
        XCTAssertEqual(rules.nextFreeVariant(of: "tool", used: ["tool"]), "tool-2")
        XCTAssertEqual(
            rules.nextFreeVariant(of: "tool", used: ["tool", "tool-2", "tool-3"]),
            "tool-4"
        )
    }

    func testNextFreeVariantMembershipIsExactAndCaseSensitive() {
        let rules = caretRules()
        XCTAssertEqual(rules.nextFreeVariant(of: "tool", used: ["Tool"]), "tool-2")
        XCTAssertEqual(rules.nextFreeVariant(of: "Tool", used: ["tool"]), "Tool-2")
    }

    func testNextFreeVariantReturnsNilWhenDashIsDisallowed() {
        let rules = BlockIDRules(allowedCharacter: "[A-Za-z0-9]", description: "letters")!
        XCTAssertNil(rules.nextFreeVariant(of: "tool", used: ["tool"]))
    }

    func testNextFreeVariantReturnsNilWhenEverySuffixIsTaken() {
        let rules = caretRules()
        let used = Set((2...99).map { "t-\($0)" }.appending("t"))
        XCTAssertNil(rules.nextFreeVariant(of: "t", used: used))
    }
}

private extension Array {
    func appending(_ element: Element) -> [Element] {
        self + [element]
    }
}
