import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureEditorHighlightTests: XCTestCase {
    func testDrawerBulletSpanUsesDrawerPalette() throws {
        let draft = "- REQUIREMENTS"
        let span = CaptureSpan(start: 2, end: 14, kind: "drawer_bullet")
        let parse = Self.parse(draft: draft, spans: [span])
        var text = AttributedString(draft)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: [span]))

        XCTAssertEqual(captureSemanticCategory(forSpan: span), .section)
        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        let drawerColor = NSColor(CaptureEditorPalette.color(for: .section))
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                guard let color = run.foregroundColor else {
                    return false
                }
                return NSColor(color) == drawerColor
            }),
            ["REQUIREMENTS"]
        )
    }

    func testThemeTintDoesNotLeakPastNameDuringRepaint() throws {
        let draft = "Add bar @bob:theme-day-strip-bar#vibe=\n\nFix theme highlighting! @bob"
        let theme = CapturePomodoroThemeRef(
            key: "vibe",
            name: "vibe",
            hue: .orange,
            hueSource: "hash",
            start: 33,
            end: 37
        )
        let spans = Self.screenshotSpans(theme: theme)
        var text = AttributedString(draft)
        try Self.setAttributes(on: &text, start: 33, end: 37) {
            $0.backgroundColor = .orange
            $0.inlinePresentationIntent = .emphasized
        }
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertEqual(Self.strings(in: text, where: { $0.backgroundColor != nil }), ["vibe"])
        XCTAssertTrue(Self.strings(in: text, where: { $0.inlinePresentationIntent != nil }).isEmpty)
    }

    func testUnknownThemeHasNoTint() throws {
        let draft = "Add bar @bob:theme-day-strip-bar#vibe=\n\nFix theme highlighting! @bob"
        let theme = CapturePomodoroThemeRef(
            key: "vibe",
            name: "vibe",
            hue: .orange,
            hueSource: "hash",
            known: false,
            start: 33,
            end: 37
        )
        let spans = Self.screenshotSpans(theme: theme)
        var text = AttributedString(draft)
        try Self.setAttributes(on: &text, start: 33, end: 37) {
            $0.backgroundColor = .orange
        }
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertTrue(Self.strings(in: text, where: { $0.backgroundColor != nil }).isEmpty)
    }

    func testRelationLabelItalicDoesNotLeakIntoFollowingText() throws {
        let draft = "Use this @mac_inbox+owner ~tasks:target|follow next"
        let spans = [
            CaptureSpan(start: 9, end: 19, kind: "sub_bullet_route"),
            CaptureSpan(start: 20, end: 25, kind: "sub_bullet_block_id"),
            CaptureSpan(start: 26, end: 27, kind: "relation_sigil"),
            CaptureSpan(start: 27, end: 32, kind: "relation_note"),
            CaptureSpan(start: 33, end: 39, kind: "relation_block_id"),
            CaptureSpan(start: 39, end: 40, kind: "relation_label_separator"),
            CaptureSpan(start: 40, end: 46, kind: "relation_label"),
        ]
        var text = AttributedString(draft)
        try Self.setAttributes(on: &text, start: 46, end: draft.utf8.count) {
            $0.inlinePresentationIntent = .emphasized
        }
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertEqual(Self.strings(in: text, where: { $0.inlinePresentationIntent != nil }), ["follow"])
    }

    func testCancelLabelSpanUsesCancelledTintAndItalic() throws {
        let draft = "Use this @cash+sell ~invest:now|\"duplicate of\" next"
        let spans = [
            CaptureSpan(start: 9, end: 14, kind: "sub_bullet_route"),
            CaptureSpan(start: 15, end: 19, kind: "sub_bullet_block_id"),
            CaptureSpan(start: 20, end: 21, kind: "relation_sigil"),
            CaptureSpan(start: 21, end: 27, kind: "relation_note"),
            CaptureSpan(start: 28, end: 31, kind: "relation_block_id"),
            CaptureSpan(start: 31, end: 32, kind: "relation_label_separator"),
            CaptureSpan(
                start: 33,
                end: 45,
                kind: "relation_label",
                cancelsSource: true
            ),
        ]
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertEqual(
            captureSemanticCategory(forSpan: spans[6]),
            .relationCancelLabel
        )
        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.inlinePresentationIntent != nil }),
            ["duplicate of"]
        )
        let cancelColor = NSColor(CaptureEditorPalette.color(for: .relationCancelLabel))
        let labelColor = NSColor(CaptureEditorPalette.color(for: .relationLabel))
        XCTAssertNotEqual(cancelColor, labelColor)
        let painted = Self.strings(in: text, where: { run in
            guard let color = run.foregroundColor else {
                return false
            }
            return NSColor(color) == cancelColor
        })
        XCTAssertEqual(painted, ["duplicate of"])
    }

    func testCreateFormProjectNoteMarkerWearsOneManilaChip() throws {
        let draft = "Finish it @cash^goog-exit@#admin"
        let spans = [
            CaptureSpan(start: 10, end: 15, kind: "task_block_id_route", projectNote: "create"),
            CaptureSpan(start: 15, end: 16, kind: "project_note_separator", projectNote: "create"),
            CaptureSpan(start: 16, end: 25, kind: "task_block_id", projectNote: "create"),
            CaptureSpan(start: 25, end: 26, kind: "project_note_marker", projectNote: "create"),
            CaptureSpan(start: 27, end: 32, kind: "pomodoro_name"),
        ]
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )

        // One contiguous chip over the whole marker; the `#` and the Pomodoro
        // name after it stay unwashed so `#admin` reads as a separate object.
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor != nil }).joined(),
            "@cash^goog-exit@"
        )
        let wash = CaptureEditorPalette.projectNoteWash(increaseContrast: false)
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor == wash }).joined(),
            "@cash^goog-exit@"
        )
        let route = NSColor(CaptureEditorPalette.color(for: .route))
        let brown = NSColor(CaptureEditorPalette.color(for: .projectNoteName))
        XCTAssertNotEqual(route, brown)
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == route } ?? false
            }),
            ["@cash"]
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == brown } ?? false
            }).joined(),
            "^goog-exit@"
        )
        XCTAssertEqual(
            NSColor(CaptureEditorPalette.color(for: .projectNoteSeal)),
            brown
        )
    }

    func testOfferFormProjectNoteMarkerKeepsBrownNameAndGreenSeals() throws {
        let draft = "Finish it @cash:goog-exit@#admin"
        let spans = [
            CaptureSpan(start: 10, end: 15, kind: "pomodoro_route", projectNote: "offer"),
            CaptureSpan(start: 15, end: 16, kind: "project_note_separator", projectNote: "offer"),
            CaptureSpan(start: 16, end: 25, kind: "pomodoro_block_id", projectNote: "offer"),
            CaptureSpan(
                start: 25,
                end: 26,
                kind: "project_note_offer_marker",
                projectNote: "offer"
            ),
            CaptureSpan(start: 27, end: 32, kind: "pomodoro_name"),
        ]
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )

        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor != nil }).joined(),
            "@cash:goog-exit@"
        )
        let green = NSColor(CaptureEditorPalette.color(for: .projectNoteOfferSeal))
        let brown = NSColor(CaptureEditorPalette.color(for: .projectNoteName))
        XCTAssertNotEqual(green, brown)
        // The `:` and `@` go green ("will be linked"); the name stays brown.
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == green } ?? false
            }),
            [":", "@"]
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == brown } ?? false
            }),
            ["goog-exit"]
        )
    }

    func testGeneratedOfferParseWashesOnlyTheMarkerAndLeavesTheNamePlain() throws {
        // Real bob output (Scripts/generate-project-note-offer-fixtures.sh): the
        // named offer parse carries `pomodoro_name.themes`. Bob reports `admin` as
        // an unknown hash-hued theme, so the name wears neither the manila wash
        // nor a theme tint; the `:` and `@` keep the offer seal color.
        let parse = try Self.fixtureParse("capture-parse-project-note-offer.json")
        let draft = parse.input
        XCTAssertEqual(draft, "Finish it @cash:goog-exit@#admin")
        let nameSpan = try XCTUnwrap(parse.spans.first { $0.kind == "pomodoro_name" })
        XCTAssertNil(nameSpan.projectNote)
        let theme = try XCTUnwrap(nameSpan.themes.first)
        XCTAssertEqual(theme.key, "admin")
        XCTAssertFalse(theme.known)
        XCTAssertEqual(theme.hueSource, "hash")
        XCTAssertEqual(theme.start, nameSpan.start)
        XCTAssertEqual(theme.end, nameSpan.end)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: parse.spans))
        var text = AttributedString(draft)

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )

        let wash = CaptureEditorPalette.projectNoteWash(increaseContrast: false)
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor != nil }).joined(),
            "@cash:goog-exit@"
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor == wash }).joined(),
            "@cash:goog-exit@"
        )
        let green = NSColor(CaptureEditorPalette.color(for: .projectNoteOfferSeal))
        let greenRuns = Self.strings(in: text) { run in
            run.foregroundColor.map { NSColor($0) == green } ?? false
        }
        XCTAssertEqual(greenRuns, [":", "@"])
    }

    func testProjectNoteChipDoesNotWashThemeNameAndKeepsItsTint() throws {
        let draft = "Finish it @cash^goog-exit@#admin"
        let theme = CapturePomodoroThemeRef(
            key: "admin",
            name: "admin",
            hue: .orange,
            hueSource: "hash",
            start: 27,
            end: 32
        )
        let spans = [
            CaptureSpan(start: 10, end: 15, kind: "task_block_id_route", projectNote: "create"),
            CaptureSpan(start: 15, end: 16, kind: "project_note_separator", projectNote: "create"),
            CaptureSpan(start: 16, end: 25, kind: "task_block_id", projectNote: "create"),
            CaptureSpan(start: 25, end: 26, kind: "project_note_marker", projectNote: "create"),
            CaptureSpan(start: 27, end: 32, kind: "pomodoro_name", themes: [theme]),
        ]
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )

        // The theme pill is its own tint, not the manila wash.
        let wash = CaptureEditorPalette.projectNoteWash(increaseContrast: false)
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor == wash }).joined(),
            "@cash^goog-exit@"
        )
        XCTAssertEqual(
            Self.strings(in: text, where: {
                $0.backgroundColor != nil && $0.backgroundColor != wash
            }),
            ["admin"]
        )
    }

    func testSpansWithoutProjectNoteModifierGetNoWash() throws {
        // An older bob sends the seal span with no modifier: no chip. The
        // kind-only seal color still applies; the ID stays an ordinary ID.
        let draft = "Finish it @cash^goog-exit@"
        let spans = [
            CaptureSpan(start: 10, end: 15, kind: "task_block_id_route"),
            CaptureSpan(start: 16, end: 25, kind: "task_block_id"),
            CaptureSpan(start: 25, end: 26, kind: "project_note_marker"),
        ]
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )

        XCTAssertTrue(Self.strings(in: text, where: { $0.backgroundColor != nil }).isEmpty)
        let seal = NSColor(CaptureEditorPalette.color(for: .projectNoteSeal))
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == seal } ?? false
            }),
            ["@"]
        )
    }

    func testUnknownProjectNoteModifierWashesWithoutRecoloring() throws {
        let draft = "Finish it @cash^goog-exit@"
        let spans = [
            CaptureSpan(start: 10, end: 15, kind: "task_block_id_route", projectNote: "future"),
            CaptureSpan(start: 15, end: 16, kind: "project_note_separator", projectNote: "future"),
            CaptureSpan(start: 16, end: 25, kind: "task_block_id", projectNote: "future"),
            CaptureSpan(start: 25, end: 26, kind: "project_note_marker", projectNote: "future"),
        ]
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )

        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor != nil }).joined(),
            "@cash^goog-exit@"
        )
        let indigo = NSColor(CaptureEditorPalette.color(for: .blockID))
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == indigo } ?? false
            }),
            ["goog-exit"]
        )
    }

    func testIncreaseContrastRaisesTheManilaWash() {
        XCTAssertNotEqual(
            CaptureEditorPalette.projectNoteWash(increaseContrast: false),
            CaptureEditorPalette.projectNoteWash(increaseContrast: true)
        )
    }

    func testRepaintClearsTheChipWhenTheSealIsDeleted() throws {
        // Typed text inherits attributes, so a repaint for a draft whose marker
        // lost its seal must drop every background the chip left behind.
        let sealed = "Finish it @cash^goog-exit@"
        let sealedSpans = [
            CaptureSpan(start: 10, end: 15, kind: "task_block_id_route", projectNote: "create"),
            CaptureSpan(start: 15, end: 16, kind: "project_note_separator", projectNote: "create"),
            CaptureSpan(start: 16, end: 25, kind: "task_block_id", projectNote: "create"),
            CaptureSpan(start: 25, end: 26, kind: "project_note_marker", projectNote: "create"),
        ]
        var text = AttributedString(sealed)
        let sealedRanges = try XCTUnwrap(validatedSpanRanges(in: sealed, spans: sealedSpans))
        CapturePanelModel.paintHighlighting(
            &text,
            parse: Self.parse(draft: sealed, spans: sealedSpans),
            draft: sealed,
            ranges: sealedRanges
        )
        XCTAssertFalse(Self.strings(in: text, where: { $0.backgroundColor != nil }).isEmpty)

        let bare = "Finish it @cash^goog-exit"
        text = AttributedString(bare)
        // Simulate the inherited wash on the new draft before the repaint.
        try Self.setAttributes(on: &text, start: 10, end: 25) {
            $0.backgroundColor = CaptureEditorPalette.projectNoteWash(increaseContrast: false)
        }
        let bareSpans = [
            CaptureSpan(start: 10, end: 15, kind: "task_block_id_route"),
            CaptureSpan(start: 16, end: 25, kind: "task_block_id"),
        ]
        let bareRanges = try XCTUnwrap(validatedSpanRanges(in: bare, spans: bareSpans))
        CapturePanelModel.paintHighlighting(
            &text,
            parse: Self.parse(draft: bare, spans: bareSpans),
            draft: bare,
            ranges: bareRanges
        )
        XCTAssertTrue(Self.strings(in: text, where: { $0.backgroundColor != nil }).isEmpty)
    }

    func testWhitespaceOnlyDraftClearsInheritedTint() throws {
        let model = CapturePanelModel()
        var text = AttributedString("  ")
        try Self.setAttributes(on: &text, start: 0, end: 2) {
            $0.backgroundColor = .orange
        }
        model.attributedDraft = text

        model.editorTextDidChange(cursorUTF8Offset: 2)

        XCTAssertTrue(Self.strings(in: model.attributedDraft, where: { $0.backgroundColor != nil }).isEmpty)
    }

    func testUnconfiguredThemeGetsDashedUnderlineOnceCaretLeavesTheName() throws {
        let draft = "Add bar @bob:theme-day-strip-bar#vibe=\n\nFix theme highlighting! @bob"
        let theme = CapturePomodoroThemeRef(
            key: "vibe",
            name: "vibe",
            hueSource: "unconfigured",
            configured: false,
            start: 33,
            end: 37
        )
        let spans = Self.screenshotSpans(theme: theme)
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))
        let dashed = NSUnderlineStyle([.single, .patternDash])

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(
                &text,
                parse: parse,
                draft: draft,
                ranges: ranges,
                cursorUTF8: 0
            )
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.underlineStyle == dashed }),
            ["vibe"]
        )
        XCTAssertTrue(Self.strings(in: text, where: { $0.backgroundColor != nil }).isEmpty)
    }

    func testTaskTypeNameTintLeavesSigilTertiary() throws {
        let draft = "Fix it #fix"
        let theme = CapturePomodoroThemeRef(
            key: "fix",
            name: "FIX",
            hue: .blue,
            hueSource: "config",
            configured: true,
            start: 8,
            end: 11
        )
        let spans = [
            CaptureSpan(start: 7, end: 11, kind: "task_type", themes: [theme])
        ]
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertEqual(Self.strings(in: text, where: { $0.backgroundColor != nil }), ["fix"])
        let tertiary = NSColor(CaptureEditorPalette.color(for: .taskType))
        let sigil = Self.strings(in: text, where: { run in
            guard let color = run.foregroundColor else {
                return false
            }
            return NSColor(color) == tertiary
        })
        XCTAssertTrue(sigil.contains("#"))
        XCTAssertFalse(sigil.contains("fix"))
    }

    func testTaskTypeUnicodeOffsetsPaintNameOnly() throws {
        let draft = "Fix 🧰 it #fix"
        let theme = CapturePomodoroThemeRef(
            key: "fix",
            name: "FIX",
            hue: .blue,
            hueSource: "config",
            configured: true,
            start: 13,
            end: 16
        )
        let spans = [
            CaptureSpan(start: 12, end: 16, kind: "task_type", themes: [theme])
        ]
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertEqual(Self.strings(in: text, where: { $0.backgroundColor != nil }), ["fix"])
    }

    func testUnknownTaskTypeDashedWhenCaretLeavesName() throws {
        let draft = "Fix it #nope"
        let theme = CapturePomodoroThemeRef(
            key: "nope",
            name: "NOPE",
            hueSource: "unconfigured",
            known: false,
            configured: false,
            start: 8,
            end: 12
        )
        let spans = [
            CaptureSpan(start: 7, end: 12, kind: "task_type", themes: [theme])
        ]
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))
        let dashed = NSUnderlineStyle([.single, .patternDash])

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(
                &text, parse: parse, draft: draft, ranges: ranges, cursorUTF8: 0)
        )
        XCTAssertEqual(Self.strings(in: text, where: { $0.underlineStyle == dashed }), ["nope"])
        XCTAssertTrue(Self.strings(in: text, where: { $0.backgroundColor != nil }).isEmpty)
    }

    func testUnknownTaskTypeHasNoMarkWhileCaretIsInTheName() throws {
        let draft = "Fix it #nope"
        let theme = CapturePomodoroThemeRef(
            key: "nope",
            name: "NOPE",
            hueSource: "unconfigured",
            known: false,
            configured: false,
            start: 8,
            end: 12
        )
        let spans = [
            CaptureSpan(start: 7, end: 12, kind: "task_type", themes: [theme])
        ]
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(
                &text, parse: parse, draft: draft, ranges: ranges, cursorUTF8: 11)
        )
        XCTAssertTrue(Self.strings(in: text, where: { $0.underlineStyle != nil }).isEmpty)
        XCTAssertTrue(Self.strings(in: text, where: { $0.backgroundColor != nil }).isEmpty)
    }

    func testMalformedTaskTypeThemeRangeIsSkipped() throws {
        let draft = "#fix"
        let theme = CapturePomodoroThemeRef(
            key: "fix",
            name: "FIX",
            hue: .blue,
            hueSource: "config",
            configured: true,
            start: 9,
            end: 2
        )
        let spans = [
            CaptureSpan(start: 0, end: 4, kind: "task_type", themes: [theme])
        ]
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertTrue(Self.strings(in: text, where: { $0.backgroundColor != nil }).isEmpty)
    }

    func testUnconfiguredThemeHasNoMarkWhileCaretIsInTheName() throws {
        let draft = "Add bar @bob:theme-day-strip-bar#vibe=\n\nFix theme highlighting! @bob"
        let theme = CapturePomodoroThemeRef(
            key: "vibe",
            name: "vibe",
            hueSource: "unconfigured",
            configured: false,
            start: 33,
            end: 37
        )
        let spans = Self.screenshotSpans(theme: theme)
        var text = AttributedString(draft)
        try Self.setAttributes(on: &text, start: 33, end: 37) {
            $0.underlineStyle = NSUnderlineStyle([.single, .patternDash])
            $0.underlineColor = NSColor.systemOrange.withAlphaComponent(0.7)
        }
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(
                &text,
                parse: parse,
                draft: draft,
                ranges: ranges,
                cursorUTF8: 35
            )
        )
        XCTAssertTrue(Self.strings(in: text, where: { $0.underlineStyle != nil }).isEmpty)
        XCTAssertTrue(Self.strings(in: text, where: { $0.underlineColor != nil }).isEmpty)
    }

    private static func screenshotSpans(theme: CapturePomodoroThemeRef) -> [CaptureSpan] {
        [
            CaptureSpan(start: 8, end: 12, kind: "pomodoro_route"),
            CaptureSpan(start: 13, end: 32, kind: "pomodoro_block_id"),
            CaptureSpan(start: 33, end: 37, kind: "pomodoro_name", themes: [theme]),
            CaptureSpan(start: 37, end: 38, kind: "pomodoro_start"),
            CaptureSpan(start: 64, end: 68, kind: "route"),
        ]
    }

    private static func fixtureParse(_ name: String) throws -> CaptureParseResponse {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
        return try JSONDecoder().decode(CaptureParseResponse.self, from: Data(contentsOf: url))
    }

    func testGmailUrlSpanPaintsLikeRefUrl() throws {
        let draft =
            "Follow up https://mail.google.com/mail/u/0/#inbox/FMfcgzQhWTsNRgxMhQNwhZDfgqwXpPsx"
        let url = String(draft.dropFirst("Follow up ".count))
        let span = CaptureSpan(
            start: 10,
            end: 82,
            kind: "gmail_url",
            key: "1a0b9eb2cc26ab96",
            gmail: CaptureGmailSpanMetadata(
                verdict: "decoded", dateHint: "2026-09-19T13:46:32.514+00:00")
        )
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: [span])
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: [span]))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )

        let link = NSColor(CaptureEditorPalette.color(for: .link))
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == link } ?? false
            }),
            [url]
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.underlineStyle == .single }),
            [url]
        )
    }

    func testRecordSpansPaintRouteChipKeysAndValuesWithoutInsertingEmoji() throws {
        let parse = try Self.fixtureParse("record-parse-complete.json")
        let draft = parse.input
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: parse.spans))
        var text = AttributedString(draft)

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertEqual(String(text.characters), draft)

        let routeColor = NSColor(CaptureEditorPalette.color(for: .recordRoute))
        let keyColor = NSColor(CaptureEditorPalette.color(for: .recordFieldKey))
        let setColor = NSColor(
            CaptureEditorPalette.recordFieldValueColor(state: "set")
        )
        let wash = CaptureEditorPalette.recordRouteWash(increaseContrast: false)
        XCTAssertNotEqual(routeColor, setColor)

        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == routeColor } ?? false
            }),
            ["@eat/"]
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor == wash }).joined(),
            "@eat/"
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == keyColor } ?? false
            }),
            ["status", "category", "location"]
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == setColor } ?? false
            }),
            ["liked", "Ramen", "Clark"]
        )
    }

    func testTwoRecordTypesKeepCopyOffsetsAndPaintBothRouteWashes() throws {
        let parse = try Self.fixtureParse("record-parse-two-records.json")
        let draft = parse.input
        XCTAssertEqual(draft, "Ramen Nagi @eat/\n\nTalk Python @podcasts/")
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: parse.spans))
        var text = AttributedString(draft)

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertEqual(String(text.characters), draft)
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor != nil }),
            ["@eat/", "@podcasts/"]
        )
        let adornments = CaptureRecordRouteAdornment.all(in: parse)
        XCTAssertEqual(adornments.map(\.emoji), ["🍽️", "🎙️"])
        XCTAssertFalse(draft.contains("🍽️"))
        XCTAssertFalse(draft.contains("🎙️"))
    }

    func testRecordRouteStartGlyphIsClearWhenAdorned() throws {
        let parse = try Self.fixtureParse("record-parse-complete.json")
        let draft = parse.input
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: parse.spans))
        var text = AttributedString(draft)
        let routeColor = NSColor(CaptureEditorPalette.color(for: .recordRoute))
        let wash = CaptureEditorPalette.recordRouteWash(increaseContrast: false)

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(
                &text,
                parse: parse,
                draft: draft,
                ranges: ranges,
                concealRouteStartGlyphs: true
            )
        )
        XCTAssertEqual(String(text.characters), draft)
        XCTAssertEqual(
            Self.strings(in: text, where: Self.isClearForeground),
            ["@"]
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == routeColor } ?? false
            }),
            ["eat/"]
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor == wash }).joined(),
            "@eat/"
        )
    }

    func testRecordRouteStartGlyphStaysVisibleWithoutEmojiMetadata() throws {
        let parse = try Self.fixtureParse("record-parse-old-bob.json")
        let draft = parse.input
        XCTAssertEqual(draft, "Ramen Nagi @eat/")
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: parse.spans))
        var text = AttributedString(draft)

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(
                &text,
                parse: parse,
                draft: draft,
                ranges: ranges,
                concealRouteStartGlyphs: true
            )
        )
        XCTAssertEqual(String(text.characters), draft)
        XCTAssertTrue(Self.strings(in: text, where: Self.isClearForeground).isEmpty)
        XCTAssertTrue(draft.contains("@"))
    }

    func testRecordRouteStartGlyphStaysVisibleWhileSubmittingOrLocked() throws {
        let parse = try Self.fixtureParse("record-parse-complete.json")
        let draft = parse.input
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: parse.spans))
        var text = AttributedString(draft)
        let routeColor = NSColor(CaptureEditorPalette.color(for: .recordRoute))

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(
                &text,
                parse: parse,
                draft: draft,
                ranges: ranges,
                concealRouteStartGlyphs: false
            )
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == routeColor } ?? false
            }),
            ["@eat/"]
        )
        XCTAssertTrue(Self.strings(in: text, where: Self.isClearForeground).isEmpty)

        let model = CapturePanelModel()
        XCTAssertTrue(model.showsRecordRouteEmoji)
        model.isSubmitting = true
        XCTAssertFalse(model.showsRecordRouteEmoji)
        model.isSubmitting = false
        model.setEditorInputLockedForTests(true)
        XCTAssertFalse(model.showsRecordRouteEmoji)
    }

    func testTwoRecordTypesConcealBothRouteStartGlyphsWithoutChangingCopy() throws {
        let parse = try Self.fixtureParse("record-parse-two-records.json")
        let draft = parse.input
        XCTAssertEqual(draft, "Ramen Nagi @eat/\n\nTalk Python @podcasts/")
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: parse.spans))
        var text = AttributedString(draft)

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(
                &text,
                parse: parse,
                draft: draft,
                ranges: ranges,
                concealRouteStartGlyphs: true
            )
        )
        XCTAssertEqual(String(text.characters), draft)
        XCTAssertEqual(
            Self.strings(in: text, where: Self.isClearForeground),
            ["@", "@"]
        )
        // Concealing the start glyph splits the wash run at `@`, matching
        // testRecordRouteStartGlyphIsClearWhenAdorned.
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor != nil }),
            ["@", "eat/", "@", "podcasts/"]
        )
        XCTAssertFalse(draft.contains("🍽️"))
        XCTAssertFalse(draft.contains("🎙️"))
    }

    func testRecordUnicodeOffsetsPaintTheRouteNotASlicedGrapheme() throws {
        let parse = try Self.fixtureParse("record-parse-unicode.json")
        let draft = parse.input
        XCTAssertEqual(draft, "Café Møø @eat/")
        XCTAssertEqual(("Café Møø " as String).utf8.count, 12)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: parse.spans))
        var text = AttributedString(draft)

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertEqual(String(text.characters), draft)
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor != nil }),
            ["@eat/"]
        )
    }

    func testRecordMultilineValueRangesFollowByteOffsets() throws {
        let draft = "Café Møø @eat/\n- status:: liked"
        XCTAssertEqual(("Café Møø " as String).utf8.count, 12)
        let routeStart = ("Café Møø " as String).utf8.count
        let valueStart = draft.utf8.count - "liked".utf8.count
        let spans = [
            CaptureSpan(start: routeStart, end: routeStart + 5, kind: "record_route"),
            CaptureSpan(
                start: valueStart,
                end: valueStart + 5,
                kind: "record_field_value",
                key: "status"
            ),
        ]
        let record = CaptureRecord(
            action: "create",
            label: "Restaurant",
            fields: [
                CaptureRecordField(
                    key: "status",
                    label: "Status",
                    kind: "choices",
                    required: true,
                    state: "set",
                    display: "Liked",
                    range: CaptureRange(start: valueStart, end: valueStart + 5),
                    valueRanges: [CaptureRange(start: valueStart, end: valueStart + 5)]
                )
            ]
        )
        let parse = CaptureParseResponse(
            ok: true,
            schemaVersion: 1,
            input: draft,
            body: "Café Møø",
            mode: "record_note",
            spans: spans,
            record: record
        )
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))
        var text = AttributedString(draft)

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )
        XCTAssertEqual(String(text.characters), draft)
        let setColor = NSColor(CaptureEditorPalette.recordFieldValueColor(state: "set"))
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == setColor } ?? false
            }),
            ["liked"]
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.backgroundColor != nil }),
            ["@eat/"]
        )
    }

    func testRecordFieldValueUsesTheOwningItemsStateNotTheFirstRecord() throws {
        let draft = "One @eat/\n- status:: liked\n\nTwo @eat/\n- status:: nope"
        let firstValue = CaptureSpan(
            start: 21,
            end: 26,
            kind: "record_field_value",
            key: "status"
        )
        let secondValue = CaptureSpan(
            start: 49,
            end: 53,
            kind: "record_field_value",
            key: "status"
        )
        let firstRecord = CaptureRecord(
            action: "create",
            label: "Restaurant",
            missing: [],
            fields: [
                CaptureRecordField(
                    key: "status",
                    label: "Status",
                    kind: "choices",
                    required: true,
                    state: "set",
                    display: "Liked",
                    range: CaptureRange(start: 21, end: 26)
                )
            ]
        )
        let secondRecord = CaptureRecord(
            action: "create",
            label: "Restaurant",
            missing: [],
            fields: [
                CaptureRecordField(
                    key: "status",
                    label: "Status",
                    kind: "choices",
                    required: true,
                    state: "invalid",
                    range: CaptureRange(start: 49, end: 53)
                )
            ]
        )
        let parse = CaptureParseResponse(
            ok: true,
            schemaVersion: 1,
            input: draft,
            body: "One",
            mode: "record_note",
            spans: [firstValue, secondValue],
            items: [
                CaptureParseItem(
                    index: 1,
                    range: CaptureRange(start: 0, end: 26),
                    lineStart: 1,
                    lineEnd: 2,
                    body: "One",
                    mode: "record_note",
                    record: firstRecord
                ),
                CaptureParseItem(
                    index: 2,
                    range: CaptureRange(start: 28, end: 53),
                    lineStart: 4,
                    lineEnd: 5,
                    body: "Two",
                    mode: "record_note",
                    record: secondRecord
                ),
            ],
            record: firstRecord
        )
        XCTAssertEqual(
            CaptureRecordPresentation.record(matching: firstValue, in: parse)?.fields.first?.state,
            "set"
        )
        XCTAssertEqual(
            CaptureRecordPresentation.record(matching: secondValue, in: parse)?.fields.first?.state,
            "invalid"
        )

        let ranges = try XCTUnwrap(
            validatedSpanRanges(in: draft, spans: [firstValue, secondValue])
        )
        var text = AttributedString(draft)
        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )

        let setColor = NSColor(CaptureEditorPalette.recordFieldValueColor(state: "set"))
        let invalidColor = NSColor(CaptureEditorPalette.recordFieldValueColor(state: "invalid"))
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == setColor } ?? false
            }),
            ["liked"]
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == invalidColor } ?? false
            }),
            ["nope"]
        )
    }

    func testMalformedSpansClearStaleRoutePaint() throws {
        let parse = try Self.fixtureParse("record-parse-complete.json")
        let draft = parse.input
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: parse.spans))
        var text = AttributedString(draft)

        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(
                &text,
                parse: parse,
                draft: draft,
                ranges: ranges,
                concealRouteStartGlyphs: true
            )
        )
        XCTAssertEqual(Self.strings(in: text, where: Self.isClearForeground), ["@"])
        XCTAssertFalse(Self.strings(in: text, where: { $0.backgroundColor != nil }).isEmpty)

        let route = try XCTUnwrap(parse.spans.first { $0.kind == "record_route" })
        let overlapping = [
            route,
            CaptureSpan(start: route.start + 1, end: route.end, kind: "record_stem"),
        ]
        XCTAssertNil(validatedSpanRanges(in: draft, spans: overlapping))
        let ignored = CapturePanelModel.applyEditorHighlighting(
            &text,
            parse: Self.parse(draft: draft, spans: overlapping),
            draft: draft,
            ranges: nil,
            concealRouteStartGlyphs: true
        )
        XCTAssertTrue(ignored)
        XCTAssertTrue(Self.strings(in: text, where: Self.isClearForeground).isEmpty)
        XCTAssertTrue(Self.strings(in: text, where: { $0.backgroundColor != nil }).isEmpty)
        XCTAssertEqual(String(text.characters), draft)
    }

    func testRecordStemAndUnknownKindsStayOnTheirPalettes() throws {
        let draft = "Ramen Nagi @eat/^custom-stem extra"
        let spans = [
            CaptureSpan(start: 11, end: 16, kind: "record_route"),
            CaptureSpan(start: 16, end: 28, kind: "record_stem"),
            CaptureSpan(start: 29, end: 34, kind: "record_future_kind"),
        ]
        var text = AttributedString(draft)
        let parse = Self.parse(draft: draft, spans: spans)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: spans))

        XCTAssertEqual(captureSemanticCategory(forSpanKind: "record_stem"), .recordStem)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "record_future_kind"), .neutral)
        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(&text, parse: parse, draft: draft, ranges: ranges)
        )

        let stemColor = NSColor(CaptureEditorPalette.color(for: .recordStem))
        let neutral = NSColor(CaptureEditorPalette.color(for: .neutral))
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == stemColor } ?? false
            }),
            ["^custom-stem"]
        )
        XCTAssertEqual(
            Self.strings(in: text, where: { run in
                run.foregroundColor.map { NSColor($0) == neutral } ?? false
            }),
            ["extra"]
        )
        XCTAssertEqual(String(text.characters), draft)
    }

    func testNotebookCreateSectionUsesDottedUnderlineAndExistingClearsIt() throws {
        let draft = "@dev_nvim#Wireguard"
        let start = "@dev_nvim#".utf8.count
        let create = CaptureSpan(
            start: start,
            end: draft.utf8.count,
            kind: "section",
            notebook: true,
            sectionAction: "create",
            title: "Wireguard"
        )
        var text = AttributedString(draft)
        let ranges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: [create]))
        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(
                &text,
                parse: Self.parse(draft: draft, spans: [create]),
                draft: draft,
                ranges: ranges
            )
        )
        let dotted = NSUnderlineStyle([.single, .patternDot])
        XCTAssertEqual(
            Self.strings(in: text, where: { $0.underlineStyle == dotted }),
            ["Wireguard"]
        )

        let existing = CaptureSpan(
            start: start,
            end: draft.utf8.count,
            kind: "section",
            notebook: true,
            sectionAction: "existing",
            title: "Wireguard"
        )
        let existingRanges = try XCTUnwrap(validatedSpanRanges(in: draft, spans: [existing]))
        XCTAssertFalse(
            CapturePanelModel.paintHighlighting(
                &text,
                parse: Self.parse(draft: draft, spans: [existing]),
                draft: draft,
                ranges: existingRanges
            )
        )
        XCTAssertTrue(Self.strings(in: text, where: { $0.underlineStyle == dotted }).isEmpty)
        XCTAssertEqual(String(text.characters), draft)
    }

    func testIncreaseContrastRaisesTheRecordRouteWash() {
        XCTAssertNotEqual(
            CaptureEditorPalette.recordRouteWash(increaseContrast: false),
            CaptureEditorPalette.recordRouteWash(increaseContrast: true)
        )
    }

    private static func parse(draft: String, spans: [CaptureSpan]) -> CaptureParseResponse {
        CaptureParseResponse(
            ok: true,
            schemaVersion: 1,
            input: draft,
            body: draft,
            mode: "incomplete",
            spans: spans
        )
    }

    private static func setAttributes(
        on text: inout AttributedString,
        start: Int,
        end: Int,
        update: (inout AttributeContainer) -> Void
    ) throws {
        let range = try XCTUnwrap(stringRange(in: String(text.characters), start: start, end: end))
        guard let lower = AttributedString.Index(range.lowerBound, within: text),
              let upper = AttributedString.Index(range.upperBound, within: text)
        else {
            XCTFail("Unable to map byte range into attributed text")
            return
        }
        var attributes = AttributeContainer()
        update(&attributes)
        text[lower..<upper].mergeAttributes(attributes)
    }

    private static func strings(
        in text: AttributedString,
        where predicate: (AttributeContainer) -> Bool
    ) -> [String] {
        text.runs.compactMap { run in
            guard predicate(run.attributes) else {
                return nil
            }
            return String(text[run.range].characters)
        }
    }

    private static func isClearForeground(_ run: AttributeContainer) -> Bool {
        run.foregroundColor.map { NSColor($0).alphaComponent == 0 } ?? false
    }
}
