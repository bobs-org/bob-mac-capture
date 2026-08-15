import XCTest

@testable import CaptureCore

final class CompletionRowContentTests: XCTestCase {
    func testRouteContextPrefersRouteAsPrimaryAndSurfacesLabelKindStatusAsSecondaryBadges() {
        let candidate = CaptureCompletionCandidate(
            replacement: "today",
            route: "today",
            label: "today.md",
            kind: "inbox",
            status: "active"
        )

        let content = completionRowContent(for: candidate, context: "route", query: "tod")

        XCTAssertEqual(content.category, .route)
        XCTAssertEqual(content.contextLabel, "Destination")
        XCTAssertEqual(content.primaryText, "today")
        XCTAssertEqual(content.secondaryText, "today.md")
        XCTAssertEqual(content.badges, ["inbox", "active"])
        XCTAssertEqual(content.primaryMatchRange, 0..<3)
        XCTAssertEqual(content.accessibilityLabel, "Destination, today, today.md, inbox, active")
    }

    func testRouteContextOmitsSecondaryWhenLabelMatchesPrimary() {
        let candidate = CaptureCompletionCandidate(
            replacement: "today",
            route: "today",
            label: "today",
            kind: "inbox"
        )

        let content = completionRowContent(for: candidate, context: "route", query: "")

        XCTAssertNil(content.secondaryText)
        XCTAssertNil(content.primaryMatchRange)
    }

    func testSectionContextShowsTitleAndHeadingLevelBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "Design",
            title: "Design",
            level: 2
        )

        let content = completionRowContent(for: candidate, context: "section", query: "des")

        XCTAssertEqual(content.category, .section)
        XCTAssertEqual(content.contextLabel, "Section")
        XCTAssertEqual(content.primaryText, "Design")
        XCTAssertEqual(content.badges, ["H2"])
        XCTAssertEqual(content.primaryMatchRange, 0..<3)
    }

    func testTaskContextShowsTextSectionStatusAndBlockBadges() {
        let candidate = CaptureCompletionCandidate(
            replacement: "goog-exit",
            blockID: "goog-exit",
            statusSymbol: "x",
            statusName: "Done",
            text: "Ship the release",
            section: "Work"
        )

        let content = completionRowContent(for: candidate, context: "task", query: "")

        XCTAssertEqual(content.category, .blockID)
        XCTAssertEqual(content.contextLabel, "Parent Task")
        XCTAssertEqual(content.primaryText, "Ship the release")
        XCTAssertEqual(content.secondaryText, "Work")
        XCTAssertEqual(content.badges, ["[x] Done", "^goog-exit"])
    }

    func testPomodoroBlockIDContextUsesItsOwnLabel() {
        let candidate = CaptureCompletionCandidate(
            replacement: "goog-exit",
            blockID: "goog-exit",
            text: "Ship the release"
        )

        let content = completionRowContent(for: candidate, context: "pomodoro_block_id", query: "")

        XCTAssertEqual(content.contextLabel, "Pomodoro Task")
    }

    func testWikilinkNoteContextPrefersAliasAsPrimaryAndFlagsAliasBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "Artificial Intelligence|AI]]",
            path: "Artificial Intelligence.md",
            name: "Artificial Intelligence",
            alias: "AI",
            matchKind: "exact_alias"
        )

        let content = completionRowContent(for: candidate, context: "wikilink_note", query: "AI")

        XCTAssertEqual(content.category, .wikilinkTarget)
        XCTAssertEqual(content.contextLabel, "Note")
        XCTAssertEqual(content.primaryText, "AI")
        XCTAssertEqual(content.secondaryText, "Artificial Intelligence.md")
        XCTAssertEqual(content.badges, ["Alias"])
        XCTAssertEqual(content.primaryMatchRange, 0..<2)
    }

    func testWikilinkNoteContextFallsBackToNameWithoutAlias() {
        let candidate = CaptureCompletionCandidate(
            replacement: "sase",
            path: "sase.md",
            name: "sase",
            matchKind: "exact_stem"
        )

        let content = completionRowContent(for: candidate, context: "wikilink_note", query: "sas")

        XCTAssertEqual(content.primaryText, "sase")
        XCTAssertTrue(content.badges.isEmpty)
        XCTAssertEqual(content.primaryMatchRange, 0..<3)
    }

    func testWikilinkHeadingContextShowsHeadingTextAndLevelBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "Design]]",
            level: 3,
            path: "sase.md",
            name: "sase",
            heading: "Design"
        )

        let content = completionRowContent(for: candidate, context: "wikilink_heading", query: "des")

        XCTAssertEqual(content.category, .wikilinkHeading)
        XCTAssertEqual(content.contextLabel, "Heading")
        XCTAssertEqual(content.primaryText, "Design")
        XCTAssertEqual(content.secondaryText, "sase.md")
        XCTAssertEqual(content.badges, ["H3"])
    }

    func testWikilinkBlockContextShowsBlockIDAndPreviewBadge() {
        let candidate = CaptureCompletionCandidate(
            replacement: "goog-exit]]",
            blockID: "goog-exit",
            path: "sase.md",
            name: "sase",
            preview: "Paragraph"
        )

        let content = completionRowContent(for: candidate, context: "wikilink_block", query: "")

        XCTAssertEqual(content.category, .wikilinkBlock)
        XCTAssertEqual(content.contextLabel, "Block")
        XCTAssertEqual(content.primaryText, "^goog-exit")
        XCTAssertEqual(content.secondaryText, "sase.md")
        XCTAssertEqual(content.badges, ["Paragraph"])
    }

    func testUnknownContextFallsBackToNeutralCategoryAndReplacementText() {
        let candidate = CaptureCompletionCandidate(replacement: "fallback")

        let content = completionRowContent(for: candidate, context: nil, query: "")

        XCTAssertEqual(content.category, .neutral)
        XCTAssertEqual(content.symbolName, "text.cursor")
        XCTAssertEqual(content.contextLabel, "")
        XCTAssertEqual(content.primaryText, "fallback")
        XCTAssertEqual(content.accessibilityLabel, "fallback")
    }

    func testEmptyQueryProducesNoMatchRange() {
        let candidate = CaptureCompletionCandidate(replacement: "sase", path: "sase.md", name: "sase")

        let content = completionRowContent(for: candidate, context: "wikilink_note", query: "")

        XCTAssertNil(content.primaryMatchRange)
    }

    func testMatchRangeIsCaseInsensitive() {
        XCTAssertEqual(completionMatchRange(in: "Artificial Intelligence", query: "intel"), 11..<16)
        XCTAssertNil(completionMatchRange(in: "Artificial Intelligence", query: "xyz"))
        XCTAssertNil(completionMatchRange(in: "Artificial Intelligence", query: ""))
    }

    func testSpanKindCategoriesCoverExistingCaptureMarkerAndWikilinkKinds() {
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "route"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "task_block_id_route"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_route"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "sub_bullet_route"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "section"), .section)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "task_block_id"), .blockID)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_block_id"), .blockID)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "sub_bullet_block_id"), .blockID)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "schedule"), .schedule)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "priority"), .priority)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "clipboard"), .clipboard)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "wikilink_delimiter"), .wikilinkDelimiter)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "wikilink_target"), .wikilinkTarget)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "wikilink_heading"), .wikilinkHeading)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "wikilink_block_id"), .wikilinkBlock)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "wikilink_alias"), .wikilinkAlias)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "interactive_placeholder"), .interactivePlaceholder)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "unrecognized_future_kind"), .neutral)
    }

    func testCompletionContextParsesAllWireValuesAndRejectsUnknown() {
        XCTAssertEqual(CaptureCompletionContext(rawContext: "route"), .route)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "section"), .section)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "pomodoro_block_id"), .pomodoroBlockID)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "task"), .task)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "wikilink_note"), .wikilinkNote)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "wikilink_heading"), .wikilinkHeading)
        XCTAssertEqual(CaptureCompletionContext(rawContext: "wikilink_block"), .wikilinkBlock)
        XCTAssertNil(CaptureCompletionContext(rawContext: "future_context"))
        XCTAssertNil(CaptureCompletionContext(rawContext: nil))
    }

    func testMiddleTruncatedPathReturnsInputUnchangedWhenWithinBudget() {
        XCTAssertEqual(middleTruncatedPath("sase.md", maxLength: 40), "sase.md")
        XCTAssertEqual(middleTruncatedPath("Projects/Alpha.md", maxLength: 18), "Projects/Alpha.md")
    }

    func testMiddleTruncatedPathPreservesBasenameAndCollapsesDirectory() {
        let path = "Projects/Deeply/Nested/Structure/For/Testing/Truncation/Alpha.md"
        let result = middleTruncatedPath(path, maxLength: 30)

        XCTAssertEqual(result.count, 30)
        XCTAssertTrue(result.hasSuffix("/Alpha.md"))
        XCTAssertTrue(result.contains("\u{2026}"))
    }

    func testMiddleTruncatedPathCollapsesDirectoryEntirelyWhenBudgetIsTiny() {
        let path = "Projects/Deeply/Nested/Structure/Alpha.md"
        let result = middleTruncatedPath(path, maxLength: 10)

        XCTAssertEqual(result, "\u{2026}/Alpha.md")
        XCTAssertLessThanOrEqual(result.count, 10)
    }

    func testMiddleTruncatedPathShowsOneDirectoryCharacterWhenBudgetAllowsExactlyOne() {
        let path = "Projects/Deeply/Nested/Structure/Alpha.md"
        let result = middleTruncatedPath(path, maxLength: 11)

        XCTAssertEqual(result, "P\u{2026}/Alpha.md")
        XCTAssertEqual(result.count, 11)
    }

    func testMiddleTruncatedPathTruncatesBasenameItselfWhenLongerThanBudget() {
        let path = "Projects/an-extremely-long-note-name-that-cannot-fit.md"
        let result = middleTruncatedPath(path, maxLength: 20)

        XCTAssertEqual(result.count, 20)
        XCTAssertFalse(result.contains("/"))
        XCTAssertTrue(result.contains("\u{2026}"))
    }

    func testMiddleTruncatedPathWithoutSlashFallsBackToPlainMiddleTruncation() {
        let result = middleTruncatedPath("abcdefghijklmnopqrstuvwxyz", maxLength: 10)

        XCTAssertEqual(result.count, 10)
        XCTAssertTrue(result.hasPrefix("abcd"))
        XCTAssertTrue(result.hasSuffix("wxyz") || result.hasSuffix("vwxyz"))
    }

    func testMiddleTruncatedPathHandlesDegenerateTinyBudget() {
        XCTAssertEqual(middleTruncatedPath("abcdefghij", maxLength: 1), "\u{2026}")
        XCTAssertEqual(middleTruncatedPath("abcdefghij", maxLength: 0), "abcdefghij")
    }
}
