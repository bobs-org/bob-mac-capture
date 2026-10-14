import AppKit
import Combine
import Foundation
import XCTest

@testable import BobMacCapture
@testable import CaptureCore
@testable import RefsCore

/// Panel model tests against fake-bob plus a fake opener, locator, and
/// Spotlight provider: presentation, query and scope edits, frozen
/// listings under late library updates, open dispatch and banners,
/// navigation and editing, and open history.
@MainActor
final class RefsPanelModelTests: XCTestCase {
    func testPrepareSelectsFirstRowOfFirstSection() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()

        harness.model.prepareForPresentation()

        XCTAssertEqual(harness.model.query, "")
        XCTAssertEqual(harness.model.scope, .all)
        XCTAssertEqual(harness.model.selectedID, harness.model.listing.orderedIDs.first)
        XCTAssertNotNil(harness.model.selectedID)
        XCTAssertNil(harness.model.banner)
    }

    func testPrepareCountsEveryPresentation() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()

        XCTAssertEqual(harness.model.presentationCount, 0)
        harness.model.prepareForPresentation()
        harness.model.selectedRowRect = CGRect(x: 1, y: 2, width: 3, height: 4)
        XCTAssertEqual(harness.model.presentationCount, 1)
        harness.model.prepareForPresentation()
        XCTAssertEqual(harness.model.presentationCount, 2)
        // A fresh presentation clears the previous show's row anchor so
        // the ⌘K menu cannot pop at a stale frame before layout lands.
        XCTAssertNil(harness.model.selectedRowRect)
    }

    func testShowCopyCardConsumesTheCommandWithoutASelection() async throws {
        let harness = try makeHarness()
        harness.model.installForPreviews(
            items: [],
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: nil,
            banner: nil,
            refreshState: .idle
        )

        XCTAssertTrue(harness.model.perform(.showCopyCard))
        XCTAssertNil(harness.model.copyCard)
    }

    func testCopyCardKeepsItsFrozenItemAndCompletesAfterOneWrite() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let original = Self.twoPreviewItems()[0]
        harness.model.installForPreviews(
            items: [original],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: original.id,
            banner: nil,
            refreshState: .idle
        )
        var completions: [RefsCopyRow] = []
        harness.model.copyCompletion = { completions.append($0) }

        XCTAssertTrue(harness.model.perform(.showCopyCard))
        XCTAssertEqual(harness.model.copyCard?.item.rawTitle, "Alpha")
        let changed = RefItem(
            id: original.id,
            link: original.link,
            rawTitle: "Changed after opening",
            stem: original.stem,
            kind: original.kind,
            state: original.state,
            isBlocked: original.isBlocked,
            pdfPath: original.pdfPath
        )
        harness.model.installForPreviews(
            items: [changed],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: original.id,
            banner: nil,
            refreshState: .idle
        )

        harness.model.handleCopyCardKey(
            characters: "t",
            keyCode: 17,
            modifiers: []
        )

        XCTAssertEqual(harness.pasteboard.strings, ["Alpha"])
        XCTAssertEqual(completions.map(\.confirmationTitle), ["Copied Title"])
        XCTAssertNil(harness.model.copyCard)
    }

    func testCopyCardWriteFailureKeepsCardOpenAndEscapeClosesOnlyCard() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let item = Self.twoPreviewItems()[0]
        harness.model.installForPreviews(
            items: [item],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: item.id,
            banner: nil,
            refreshState: .idle
        )
        harness.pasteboard.failWrites = true
        var completions = 0
        harness.model.copyCompletion = { _ in completions += 1 }
        harness.model.openCopyCard()
        harness.model.handleCopyCardKey(
            characters: "w",
            keyCode: 13,
            modifiers: []
        )

        XCTAssertNotNil(harness.model.copyCard)
        XCTAssertEqual(
            harness.model.copyCard?.message?.text,
            "Couldn't copy — ↵ tries again"
        )
        XCTAssertEqual(harness.pasteboard.strings, [])
        XCTAssertEqual(completions, 0)
        let dismissedBefore = harness.dismissed
        harness.model.handleCopyCardKey(
            characters: nil,
            keyCode: 53,
            modifiers: []
        )
        XCTAssertNil(harness.model.copyCard)
        XCTAssertEqual(harness.dismissed, dismissedBefore)
    }

    func testCopyCardIsRevokedByHideAndSelectionChange() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let items = Self.twoPreviewItems()
        harness.model.installForPreviews(
            items: items,
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle
        )
        harness.model.openCopyCard()
        harness.model.handleCopyCardKey(
            characters: "1",
            keyCode: 18,
            modifiers: []
        )
        XCTAssertEqual(harness.model.copyCard?.pending, .note(1))

        harness.model.panelDidHide()
        XCTAssertNil(harness.model.copyCard)
        harness.model.openCopyCard()

        harness.model.handleCopyCardKey(
            characters: "1",
            keyCode: 18,
            modifiers: []
        )
        harness.model.prepareForPresentation()
        XCTAssertNil(harness.model.copyCard)

        harness.model.installForPreviews(
            items: items,
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle
        )
        harness.model.openCopyCard()
        XCTAssertTrue(harness.model.perform(.select(id: items[1].id)))
        XCTAssertNil(harness.model.copyCard)
    }

    func testControllerConsumesCardKeysAndCopiesTheRequestedRow() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let item = Self.twoPreviewItems()[0]
        harness.model.installForPreviews(
            items: [item],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: item.id,
            banner: nil,
            refreshState: .idle
        )
        harness.model.openCopyCard()
        // Keep the test focused on event routing; the live controller's
        // copy callback is covered by the app's HUD path.
        harness.model.copyCompletion = { _ in }
        let controller = RefsPanelController(model: harness.model)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))

        XCTAssertNil(controller.processKeyEvent(event))
        XCTAssertEqual(harness.pasteboard.strings, ["[[ref/chat/alpha]]"])
    }

    func testCopyAlternatesSeedFlagsClickAndResetOnHide() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let item = try XCTUnwrap(harness.model.selectedItem)
        harness.model.openCopyCard(optionHeld: true)
        XCTAssertTrue(harness.model.copyAlternatesActive)
        let card = try XCTUnwrap(harness.model.copyCard)
        let row = try XCTUnwrap(card.catalog.row(for: .wikiLink))
        let keys = card.rows.map(\.key)
        harness.model.updateCopyModifiers([])
        XCTAssertFalse(harness.model.copyAlternatesActive)
        harness.model.updateCopyModifiers([.option, .shift])
        XCTAssertEqual(harness.model.copyCard?.rows.map(\.key), keys)
        XCTAssertEqual(harness.model.copyCard?.selectedKey, card.selectedKey)
        var copied: RefsCopyRow?
        harness.model.copyCompletion = { copied = $0 }
        harness.model.copyCardRowTapped(row)
        XCTAssertEqual(copied, row.resolved(alternate: true))
        XCTAssertEqual(
            harness.pasteboard.strings,
            [RefsCopyFormat.titledWikiLink(link: item.link, title: item.rawTitle)])
        XCTAssertFalse(harness.model.copyAlternatesActive)
        harness.model.updateCopyModifiers(.option)
        XCTAssertFalse(harness.model.copyAlternatesActive)
        harness.model.openCopyCard(optionHeld: true)
        harness.model.panelDidHide()
        XCTAssertFalse(harness.model.copyAlternatesActive)
    }

    func testControllerFlagsAreGatedAndFailedAlternateRetriesAfterRelease() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.openCopyCard(optionHeld: false)
        let controller = RefsPanelController(model: harness.model)
        // No key panel: a flags event must pass through without changing the model.
        let flags = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged, location: .zero, modifierFlags: .option,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58
            ))
        XCTAssertTrue(controller.handleKeyDown(flags) === flags)
        XCTAssertFalse(harness.model.copyAlternatesActive)
        XCTAssertTrue(controller.processKeyEvent(flags) === flags)
        XCTAssertTrue(harness.model.copyAlternatesActive)
        let row = try XCTUnwrap(harness.model.copyCard?.catalog.row(for: .wikiLink))
        harness.pasteboard.failWrites = true
        harness.model.handleCopyCardKey(characters: "w", keyCode: 13, modifiers: .option)
        harness.model.updateCopyModifiers([])
        harness.pasteboard.failWrites = false
        var copied: RefsCopyRow?
        harness.model.copyCompletion = { copied = $0 }
        harness.model.handleCopyCardKey(characters: nil, keyCode: 36, modifiers: [])
        XCTAssertEqual(copied, row.resolved(alternate: true))
        XCTAssertEqual(harness.pasteboard.strings.count, 1)
        XCTAssertNil(harness.model.copyCard)
    }

    func testOptionPickerClickCopiesQuote() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let item = try XCTUnwrap(harness.model.selectedItem)
        harness.model.inspectorLoader.installShowRowForPreviews(
            RefsShowRow(
                path: item.id,
                annotations: [
                    RefsShowAnnotation(
                        kind: "highlight", quote: "Raw\nquote", comment: "My comment")
                ]), for: item
        )
        harness.model.openCopyCard(optionHeld: false)
        harness.model.handleCopyCardKey(characters: "h", keyCode: 4, modifiers: [])
        harness.model.updateCopyModifiers(.option)
        harness.model.copyCardPickerRowTapped(1)
        XCTAssertEqual(harness.pasteboard.strings, ["Raw\nquote"])
    }

    func testCardFreezesResolvedNoteAndExistingNarrationPaths() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let item = RefItem(
            id: "ref/chat/alpha.md", link: "[[ref/chat/alpha]]", rawTitle: "Alpha",
            stem: "alpha", kind: .chat, state: .ready, isBlocked: false,
            pdfPath: "lib/alpha.pdf", audioPath: "lib/alpha.m4a"
        )
        harness.model.installForPreviews(
            items: [item], signals: harness.model.signals, query: "", scope: .all,
            selectedID: item.id, banner: nil, refreshState: .idle
        )
        let pdf = harness.vault.appendingPathComponent(item.pdfPath)
        let audio = harness.vault.appendingPathComponent("lib/alpha.m4a")
        try Data("pdf".utf8).write(to: pdf)
        harness.model.openCopyCard(optionHeld: false)
        XCTAssertNil(harness.model.copyCard?.catalog.row(for: .pdfFile)?.alternate)
        try Data("audio".utf8).write(to: audio)
        // Late filesystem changes do not change the frozen card.
        XCTAssertNil(harness.model.copyCard?.catalog.row(for: .pdfFile)?.alternate)
        harness.model.openCopyCard(optionHeld: true)
        let card = try XCTUnwrap(harness.model.copyCard)
        XCTAssertEqual(
            card.catalog.row(for: .notePath)?.alternate?.payload,
            .text(harness.vault.appendingPathComponent(item.id).path))
        XCTAssertEqual(
            card.catalog.row(for: .obsidianLink)?.payload,
            ObsidianOpenURL.url(forAbsolutePath: harness.vault.appendingPathComponent(item.id).path)
                .map { .text($0.absoluteString) })
        XCTAssertEqual(card.catalog.row(for: .pdfFile)?.alternate?.payload, .fileURL(audio))
        try FileManager.default.removeItem(at: audio)
        var copies = 0
        harness.model.copyCompletion = { _ in copies += 1 }
        harness.model.handleCopyCardKey(characters: "f", keyCode: 3, modifiers: .option)
        XCTAssertEqual(copies, 0)
        XCTAssertTrue(harness.model.copyCard?.message?.isError == true)
        XCTAssertNotNil(harness.model.copyCard)
    }

    func testCopyCardHOpensPickerAndEscapeReturnsToCard() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let item = Self.twoPreviewItems()[0]
        harness.model.installForPreviews(
            items: [item],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: item.id,
            banner: nil,
            refreshState: .idle
        )
        harness.model.inspectorLoader.installShowRowForPreviews(
            RefsShowRow(path: item.id, annotations: Self.pickerAnnotations()),
            for: item
        )
        harness.model.openCopyCard()

        harness.model.handleCopyCardKey(characters: "h", keyCode: 4, modifiers: [])
        XCTAssertEqual(harness.model.copyCard?.highlightPicker?.entries.count, 3)
        XCTAssertNotNil(harness.model.copyCard)

        harness.model.handleCopyCardKey(characters: nil, keyCode: 53, modifiers: [])
        XCTAssertNil(harness.model.copyCard?.highlightPicker)
        XCTAssertNotNil(harness.model.copyCard)
        XCTAssertEqual(harness.pasteboard.strings, [])
    }

    func testCopyCardPickerDigitAndAllCopy() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let item = Self.twoPreviewItems()[0]
        harness.model.installForPreviews(
            items: [item],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: item.id,
            banner: nil,
            refreshState: .idle
        )
        harness.model.inspectorLoader.installShowRowForPreviews(
            RefsShowRow(path: item.id, annotations: Self.pickerAnnotations()),
            for: item
        )
        var completions: [RefsCopyRow] = []
        harness.model.copyCompletion = { completions.append($0) }
        harness.model.openCopyCard()
        harness.model.handleCopyCardKey(characters: "h", keyCode: 4, modifiers: [])
        harness.model.handleCopyCardKey(characters: "1", keyCode: 18, modifiers: [])

        XCTAssertEqual(completions.map(\.confirmationTitle), ["Copied Highlight · p. 11"])
        XCTAssertEqual(harness.pasteboard.strings.count, 1)
        XCTAssertTrue(harness.pasteboard.strings[0].contains("> Uncommented quote"))
        XCTAssertNil(harness.model.copyCard)

        harness.model.installForPreviews(
            items: [item],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: item.id,
            banner: nil,
            refreshState: .idle
        )
        harness.model.inspectorLoader.installShowRowForPreviews(
            RefsShowRow(path: item.id, annotations: Self.pickerAnnotations()),
            for: item
        )
        completions = []
        harness.model.copyCompletion = { completions.append($0) }
        harness.model.openCopyCard()
        harness.model.handleCopyCardKey(characters: "h", keyCode: 4, modifiers: [])
        harness.model.handleCopyCardKey(characters: "a", keyCode: 0, modifiers: [])

        XCTAssertEqual(completions.map(\.confirmationTitle), ["Copied 3 Highlights"])
        XCTAssertEqual(harness.pasteboard.strings.count, 2)
        XCTAssertTrue(harness.pasteboard.strings[1].contains("Note: Standalone"))
        XCTAssertTrue(harness.pasteboard.strings[1].contains("Comment: Keep this"))
        XCTAssertNil(harness.model.copyCard)
    }

    func testQueryEditRanksAndSelectsFirst() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()

        harness.model.query = "reading"
        harness.model.queryDidChange()

        guard case .search = harness.model.listing.mode else {
            XCTFail("expected search mode")
            return
        }
        XCTAssertEqual(harness.model.selectedID, harness.model.listing.orderedIDs.first)
        XCTAssertEqual(harness.model.selectedID, "ref/chat/small_reading.md")
    }

    func testScopeFiltersAndSelectsFirst() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()

        XCTAssertTrue(harness.model.perform(.setScope(.chats)))
        XCTAssertEqual(harness.model.listing.orderedIDs, ["ref/chat/small_reading.md"])
        XCTAssertEqual(harness.model.selectedID, "ref/chat/small_reading.md")
    }

    func testPresentedRefreshUpdatesContentWithoutReordering() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let before = harness.model.listing.orderedIDs
        XCTAssertTrue(before.contains("ref/papers/small_ready.md"))

        XCTAssertTrue(harness.model.perform(.select(id: "ref/papers/small_ready.md")))
        try harness.retireFixtureRow(path: "ref/papers/small_ready.md")
        harness.library.refresh(reason: .manual)
        await harness.waitForSnapshot(ids: Set(before).subtracting(["ref/papers/small_ready.md"]))

        await harness.waitForModel { model in
            model.unavailableIDs.contains("ref/papers/small_ready.md")
        }
        // A vanished id keeps its index in the frozen listing, marked
        // unavailable (§5.5); a fresh listing drops it.
        XCTAssertEqual(harness.model.listing.orderedIDs, before)
        XCTAssertTrue(
            harness.model.listing.unavailableIDs.contains(
                "ref/papers/small_ready.md"
            )
        )
        XCTAssertEqual(harness.model.selectedID, "ref/papers/small_ready.md")

        let dismissedBefore = harness.dismissed
        XCTAssertTrue(harness.model.perform(.open(.highlights)))
        XCTAssertEqual(harness.dismissed, dismissedBefore)
        XCTAssertTrue(harness.opener.highlightsOpens.isEmpty)
        XCTAssertNotNil(harness.model.banner)
    }

    func testOpenHidesDispatchesAndRecords() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.select(id: "ref/chat/small_reading.md")))

        XCTAssertTrue(harness.model.perform(.open(.highlights)))

        XCTAssertEqual(harness.dismissed, 1)
        XCTAssertEqual(harness.opener.highlightsOpens.count, 1)
        XCTAssertEqual(
            harness.opener.highlightsOpens.first?.pdf.path,
            harness.vault.appendingPathComponent("lib/chat/small_reading.pdf").path
        )
        XCTAssertEqual(harness.opener.highlightsOpens.first?.app, harness.highlightsURL)
        await harness.waitForOpens(id: "ref/chat/small_reading.md", count: 1)
        XCTAssertNil(harness.model.banner)
    }

    func testTypingInSearchFieldReachesModel() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()

        // The field exactly as the search bar wires it: typing must set
        // the query before the re-rank, or the next update wipes it.
        let field = RefsSearchBar(model: harness.model).makeFilterField()
        let coordinator = field.makeCoordinator()
        coordinator.controlTextDidChange(
            Notification(
                name: NSControl.textDidChangeNotification,
                object: NSTextField(string: "omni")
            )
        )

        XCTAssertEqual(harness.model.query, "omni")
        guard case .search = harness.model.listing.mode else {
            XCTFail("expected search mode after typing")
            return
        }
    }

    func testHighlightsErrorRepresentsWithBannerAndKeepsQuery() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.query = "reading"
        harness.model.queryDidChange()
        harness.opener.highlightsError = NSError(
            domain: "RefsPanelModelTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "busy"]
        )

        XCTAssertTrue(harness.model.perform(.open(.highlights)))

        XCTAssertEqual(harness.dismissed, 1)
        await harness.waitForModel { $0.banner != nil }
        // The error re-shows through the representer, which keeps the
        // query, scope, frozen listing, selection, and pending open; the
        // plain presenter (a full reset) must not run.
        XCTAssertEqual(harness.represented, 1)
        XCTAssertEqual(harness.presented, 0)
        XCTAssertEqual(harness.model.query, "reading")
        XCTAssertEqual(harness.model.selectedID, "ref/chat/small_reading.md")
        XCTAssertTrue(harness.model.banner?.message.contains("busy") ?? false)
        XCTAssertEqual(harness.model.banner?.actions, [.tryAgain, .openInDefaultApp])
        XCTAssertEqual(harness.library.signals.opens.count("ref/chat/small_reading.md"), 0)

        // Try Again re-dispatches the surviving pending open.
        harness.model.performBannerAction(.tryAgain)
        XCTAssertEqual(harness.opener.highlightsOpens.count, 2)
    }

    func testDefaultAppErrorRepresentsAndTryAgainRedispatches() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.query = "reading"
        harness.model.queryDidChange()
        harness.opener.defaultAppError = NSError(
            domain: "RefsPanelModelTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "copy-me-busy"]
        )
        XCTAssertTrue(harness.model.perform(.select(id: "ref/chat/small_reading.md")))

        XCTAssertTrue(harness.model.perform(.open(.defaultApp)))

        XCTAssertEqual(harness.dismissed, 1)
        await harness.waitForModel { $0.banner != nil }
        XCTAssertEqual(harness.represented, 1)
        XCTAssertEqual(harness.presented, 0)
        XCTAssertEqual(harness.model.query, "reading")
        XCTAssertEqual(harness.model.selectedID, "ref/chat/small_reading.md")
        XCTAssertTrue(harness.model.banner?.message.contains("copy-me-busy") ?? false)
        XCTAssertEqual(harness.model.banner?.actions, [.tryAgain, .copyDiagnostic])

        harness.model.performBannerAction(.tryAgain)
        XCTAssertEqual(harness.opener.defaultAppOpens.count, 2)

        harness.model.performBannerAction(.copyDiagnostic)
        XCTAssertEqual(harness.pasteboard.strings.count, 1)
        XCTAssertTrue(harness.pasteboard.strings[0].contains("copy-me-busy"))
    }

    func testUnavailableRowKeepsTitleRefusesOpensAndKeepsNavigation() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let before = harness.model.listing.orderedIDs
        let vanished = "ref/papers/small_ready.md"
        XCTAssertTrue(before.contains(vanished))
        let vanishedIndex = before.firstIndex(of: vanished)!

        XCTAssertTrue(harness.model.perform(.select(id: vanished)))
        try harness.retireFixtureRow(path: vanished)
        harness.library.refresh(reason: .manual)
        await harness.waitForModel { $0.unavailableIDs.contains(vanished) }

        // The vanished id keeps its index with its last known title.
        XCTAssertEqual(harness.model.listing.orderedIDs, before)
        let content = try XCTUnwrap(harness.model.rowContent(for: vanished))
        XCTAssertTrue(content.isUnavailable)
        XCTAssertEqual(content.title, "Small Ready Paper")
        XCTAssertEqual(content.caption, "No longer in your library")

        // Every open target refuses with the message and opens nothing.
        for target in [RefsOpenTarget.highlights, .note, .reveal, .defaultApp] {
            XCTAssertTrue(harness.model.perform(.open(target)))
        }
        XCTAssertTrue(harness.model.perform(.activate(id: vanished)))
        XCTAssertTrue(harness.opener.highlightsOpens.isEmpty)
        XCTAssertTrue(harness.opener.noteOpens.isEmpty)
        XCTAssertTrue(harness.opener.reveals.isEmpty)
        XCTAssertTrue(harness.opener.defaultAppOpens.isEmpty)
        XCTAssertEqual(harness.dismissed, 0)
        XCTAssertTrue(
            harness.model.banner?.message.contains("no longer in your library") ?? false
        )

        // Navigation keeps the selection, and down moves to the next row.
        XCTAssertEqual(harness.model.selectedID, vanished)
        XCTAssertTrue(harness.model.perform(.move(.next)))
        XCTAssertEqual(
            harness.model.selectedID,
            before[(vanishedIndex + 1) % before.count]
        )
    }

    func testRefreshReordersFromNewDataKeepingSelection() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let kept = "ref/chat/small_reading.md"
        XCTAssertTrue(harness.model.perform(.select(id: kept)))
        let bumped = "ref/papers/small_ready.md"
        let beforeIndex = harness.model.listing.orderedIDs.firstIndex(of: bumped)!
        XCTAssertGreaterThan(beforeIndex, 0)

        // New data: the paper was added today, so it joins Just added.
        try harness.serveAddedVariant(path: bumped, added: todayDateString())
        harness.model.perform(.refresh)
        await harness.waitForModel { $0.listing.orderedIDs.first == bumped }

        XCTAssertEqual(harness.model.selectedID, kept)
        XCTAssertTrue(harness.model.unavailableIDs.isEmpty)
    }

    func testOpenRefreshesTodayWithoutRefreshingSnapshot() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let harness = try makeHarness(environment: [
            "FAKE_BOB_RECORD_PATH": recordURL.path,
        ])
        await harness.waitForSnapshot()
        await harness.waitForModel { _ in
            harness.library.signals.today.taskEntries.count == 4
        }
        // Settle the `-g` lane before the baseline, so no late git-date
        // call can land between the counts below.
        await harness.waitForModel { _ in
            harness.library.items.contains {
                $0.id == "ref/blogs/small_opened.md" && $0.added != nil
            }
        }
        let listsBefore = argvCount(recordURL, prefix: "argv=ref list")
        let plansBefore = argvCount(recordURL, prefix: "argv=plan -f json")

        harness.model.refreshForOpen()
        await harness.waitForModel { _ in
            argvCount(recordURL, prefix: "argv=plan -f json") > plansBefore
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        harness.model.refreshForOpen()
        await harness.waitForModel { _ in
            argvCount(recordURL, prefix: "argv=plan -f json") > plansBefore + 1
        }

        // Two opens ran two Today refreshes and no new snapshot refresh.
        XCTAssertEqual(argvCount(recordURL, prefix: "argv=ref list"), listsBefore)
    }

    func testCopyDiagnosticOnLoadFailedCopiesRefreshFailure() async throws {
        let harness = try makeHarness(environment: ["FAKE_BOB_EXIT": "1"])
        await harness.waitForModel { _ in
            if case .failed = harness.library.refreshState {
                return true
            }
            return false
        }

        harness.model.performBannerAction(.copyDiagnostic)

        guard case .failed(let message, _) = harness.library.refreshState else {
            XCTFail("expected a failed refresh")
            return
        }
        XCTAssertEqual(harness.pasteboard.strings, [message])
    }

    func testMissingPDFOpensNoteAndRecordsNothing() async throws {
        let harness = try makeHarness(missing: ["lib/chat/small_reading.pdf"])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.select(id: "ref/chat/small_reading.md")))

        XCTAssertTrue(harness.model.perform(.open(.highlights)))

        XCTAssertEqual(harness.opener.noteOpens.count, 1)
        XCTAssertTrue(harness.opener.highlightsOpens.isEmpty)
        XCTAssertEqual(harness.library.signals.opens.count("ref/chat/small_reading.md"), 0)
    }

    func testHighlightsNotFoundShowsBannerAndStays() async throws {
        let harness = try makeHarness(highlightsURL: nil)
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.query = "reading"
        harness.model.queryDidChange()

        XCTAssertTrue(harness.model.perform(.open(.highlights)))

        XCTAssertEqual(harness.dismissed, 0)
        XCTAssertNotNil(harness.model.banner)
        XCTAssertTrue(harness.model.banner?.message.contains("Highlights") ?? false)
        XCTAssertEqual(harness.model.banner?.actions, [.openInDefaultApp, .chooseHighlights])
        XCTAssertEqual(harness.model.query, "reading")
    }

    func testNoteAndRevealNeverRecord() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.select(id: "ref/chat/small_reading.md")))

        XCTAssertTrue(harness.model.perform(.open(.note)))
        XCTAssertTrue(harness.model.perform(.open(.reveal)))

        XCTAssertEqual(harness.opener.noteOpens.count, 1)
        XCTAssertEqual(harness.opener.reveals.count, 1)
        XCTAssertEqual(harness.dismissed, 0)
        XCTAssertEqual(harness.library.signals.opens.count("ref/chat/small_reading.md"), 0)
    }

    func testDefaultAppOpenRecords() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.select(id: "ref/chat/small_reading.md")))

        XCTAssertTrue(harness.model.perform(.open(.defaultApp)))

        XCTAssertEqual(harness.dismissed, 1)
        XCTAssertEqual(harness.opener.defaultAppOpens.count, 1)
        await harness.waitForOpens(id: "ref/chat/small_reading.md", count: 1)
    }

    func testEscChainOrder() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.query = "reading"
        harness.model.queryDidChange()
        XCTAssertTrue(harness.model.perform(.setScope(.chats)))
        harness.model.installForPreviews(
            items: harness.library.items,
            signals: harness.library.signals,
            query: "re",
            scope: .chats,
            selectedID: harness.model.selectedID,
            banner: RefsBanner(kind: .error, message: "boom", actions: [.tryAgain]),
            refreshState: .idle
        )

        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertNil(harness.model.banner)
        XCTAssertEqual(harness.model.query, "re")

        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertEqual(harness.model.query, "")

        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertEqual(harness.model.scope, .all)

        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertEqual(harness.dismissed, 1)
    }

    func testDeleteBackwardOnEmptyRemovesScope() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.setScope(.chats)))

        XCTAssertTrue(harness.model.perform(.deleteBackwardOnEmpty))
        XCTAssertEqual(harness.model.scope, .all)
        XCTAssertFalse(harness.model.perform(.deleteBackwardOnEmpty))

        harness.model.query = "x"
        XCTAssertTrue(harness.model.perform(.setScope(.chats)))
        XCTAssertFalse(harness.model.perform(.deleteBackwardOnEmpty))
    }

    func testNavigationWrapsAndClamps() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let ids = harness.model.listing.orderedIDs
        XCTAssertGreaterThan(ids.count, 2)

        XCTAssertTrue(harness.model.perform(.select(id: ids.last!)))
        XCTAssertTrue(harness.model.perform(.move(.next)))
        XCTAssertEqual(harness.model.selectedID, ids.first)
        XCTAssertTrue(harness.model.perform(.move(.previous)))
        XCTAssertEqual(harness.model.selectedID, ids.last)

        XCTAssertTrue(harness.model.perform(.move(.first)))
        XCTAssertEqual(harness.model.selectedID, ids.first)
        XCTAssertTrue(harness.model.perform(.move(.last)))
        XCTAssertEqual(harness.model.selectedID, ids.last)

        harness.model.visibleRowBudget = 3
        XCTAssertTrue(harness.model.perform(.move(.first)))
        XCTAssertTrue(harness.model.perform(.move(.pageDown)))
        XCTAssertEqual(harness.model.selectedID, ids[2])
        XCTAssertTrue(harness.model.perform(.move(.pageDown)))
        XCTAssertEqual(harness.model.selectedID, ids[4])
        XCTAssertTrue(harness.model.perform(.move(.pageDown)))
        XCTAssertEqual(harness.model.selectedID, ids.last)
    }

    func testSectionJumpsWorkInBrowseAndRestInSearch() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertGreaterThan(harness.model.listing.sections.count, 1)

        XCTAssertTrue(harness.model.perform(.move(.first)))
        let first = harness.model.selectedID
        XCTAssertTrue(harness.model.perform(.move(.nextSection)))
        XCTAssertNotEqual(harness.model.selectedID, first)
        let secondSectionFirst = harness.model.listing.sections[1].ids.first
        XCTAssertEqual(harness.model.selectedID, secondSectionFirst)

        harness.model.query = "small"
        harness.model.queryDidChange()
        let searchSelected = harness.model.selectedID
        XCTAssertTrue(harness.model.perform(.move(.nextSection)))
        XCTAssertEqual(harness.model.selectedID, searchSelected)
    }

    func testResetOpenHistoryClearsStats() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.select(id: "ref/chat/small_reading.md")))
        XCTAssertTrue(harness.model.perform(.open(.highlights)))
        await harness.waitForOpens(id: "ref/chat/small_reading.md", count: 1)

        harness.library.resetOpenHistory()
        XCTAssertEqual(harness.library.signals.opens.count("ref/chat/small_reading.md"), 0)
    }

    func testRowContent() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let id = harness.model.listing.orderedIDs.first!

        let content = harness.model.rowContent(for: id)
        XCTAssertNotNil(content?.item)
        XCTAssertFalse(content?.caption.isEmpty ?? true)
        XCTAssertFalse(content?.whyHere.isEmpty ?? true)
        XCTAssertFalse(content?.isUnavailable ?? true)
        XCTAssertNil(harness.model.rowContent(for: "ref/chat/missing.md"))
    }

    func testRefreshReranks() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.query = "reading"
        harness.model.queryDidChange()

        XCTAssertTrue(harness.model.perform(.refresh))
    }

    func testScanConsumedWhileRunning() async throws {
        let harness = try makeHarness(environment: [
            "FAKE_BOB_DELAY_SECONDS": "2",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }

        XCTAssertTrue(harness.model.perform(.scan))
        XCTAssertTrue(harness.model.isScanning)
        XCTAssertTrue(harness.model.perform(.scan))
        XCTAssertTrue(harness.model.isScanning)
        await harness.waitForScan()
        XCTAssertNotNil(harness.model.scanNotice)
    }

    func testVisibleBrowseSelectsFirstCreated() async throws {
        let markerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: markerDir,
            withIntermediateDirectories: true
        )
        let harness = try makeHarness(environment: [
            "FAKE_BOB_SCAN_MARKER_DIR": markerDir.path,
            "FAKE_BOB_REFS_LIST_AFTER_SCAN_FIXTURE": "refs-list-after-scan.json",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        guard let notice = harness.model.scanNotice else {
            XCTFail("expected scan notice")
            return
        }
        XCTAssertEqual(notice.kind, .succeeded)
        XCTAssertFalse(notice.created.isEmpty)
        let firstSection = harness.model.listing.sections.first
        XCTAssertEqual(firstSection?.kind, .justScanned)
        XCTAssertEqual(
            harness.model.selectedID,
            "ref/chat/omni_report.md"
        )
        XCTAssertTrue(harness.model.listing.orderedIDs.contains(
            "ref/papers/harness_notes.md"
        ))
    }

    func testScrollInspectorPublishesRepeatedAndAlternatingCommands() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let snapshot = PanelSnapshot(harness.model)
        var received: [RefsInspectorScrollDirection] = []
        let cancellable = harness.model.inspectorScrolls.sink {
            received.append($0)
        }

        XCTAssertTrue(harness.model.perform(.scrollInspector(.down)))
        XCTAssertTrue(harness.model.perform(.scrollInspector(.down)))
        XCTAssertTrue(harness.model.perform(.scrollInspector(.up)))
        XCTAssertTrue(harness.model.perform(.scrollInspector(.down)))

        XCTAssertEqual(received, [.down, .down, .up, .down])
        snapshot.assertUnchanged(harness.model)
        XCTAssertEqual(harness.dismissed, 0)
        XCTAssertTrue(harness.opener.highlightsOpens.isEmpty)
        _ = cancellable
    }

    func testRevealReturnsFalseWithoutHydratedContent() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let items = Self.twoPreviewItems()
        harness.model.installForPreviews(
            items: items,
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle,
            inspector: [:]
        )
        XCTAssertFalse(harness.model.revealMoreInspectorNotes())
    }

    func testRevealReturnsFalseWhenNothingHidden() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let items = Self.twoPreviewItems()
        harness.model.installForPreviews(
            items: items,
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle,
            inspector: [items[0].id: RefsInspectorContent(
                notes: Self.twoNotes()
            )]
        )
        XCTAssertFalse(harness.model.revealMoreInspectorNotes())
    }

    func testRevealEmitsRangeAndGeneration() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let items = Self.twoPreviewItems()
        harness.model.installForPreviews(
            items: items,
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle,
            inspector: [items[0].id: RefsInspectorContent(
                notes: Self.eightNotes()
            )]
        )
        var received: [RefsInspectorNotesReveal] = []
        let cancellable = harness.model.inspectorNoteReveals.sink {
            received.append($0)
        }
        XCTAssertTrue(harness.model.revealMoreInspectorNotes())
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].id, items[0].id)
        XCTAssertEqual(received[0].generation, 1)
        XCTAssertEqual(received[0].range, 3..<6)
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: items[0].id).visibleCount(total: 8),
            6
        )
        XCTAssertTrue(harness.model.revealMoreInspectorNotes())
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[1].range, 6..<8)
        XCTAssertEqual(received[1].generation, 2)
        XCTAssertFalse(harness.model.revealMoreInspectorNotes())
        _ = cancellable
    }

    func testRevealResetsOnSelectionChangeAndPresentation() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let items = Self.twoPreviewItems()
        harness.model.installForPreviews(
            items: items,
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle,
            inspector: [
                items[0].id: RefsInspectorContent(notes: Self.eightNotes()),
                items[1].id: RefsInspectorContent(notes: Self.eightNotes()),
            ]
        )
        XCTAssertTrue(harness.model.revealMoreInspectorNotes())
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: items[0].id).generation,
            1
        )
        XCTAssertTrue(harness.model.perform(.move(.next)))
        XCTAssertEqual(harness.model.selectedID, items[1].id)
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: items[1].id).generation,
            0
        )
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: items[0].id).visibleCount(total: 8),
            3
        )
        XCTAssertTrue(harness.model.perform(.move(.previous)))
        XCTAssertEqual(harness.model.selectedID, items[0].id)
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: items[0].id).generation,
            0
        )
        XCTAssertTrue(harness.model.revealMoreInspectorNotes())
        harness.model.prepareForPresentation()
        let current = harness.model.selectedID!
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: current).generation,
            0
        )
    }

    func testNotesPageSizeClampsAndSeedsFreshPages() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.notesPageSize = 0
        XCTAssertEqual(harness.model.notesPageSize, 1)
        harness.model.notesPageSize = 99
        XCTAssertEqual(harness.model.notesPageSize, 20)
        harness.model.notesPageSize = 5
        let items = Self.twoPreviewItems()
        harness.model.installForPreviews(
            items: items,
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle,
            inspector: [items[0].id: RefsInspectorContent(
                notes: Self.eightNotes()
            )]
        )
        // installForPreviews keeps the explicitly set page size: a fresh
        // page shows 5, not the default 3.
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: items[0].id).visibleCount(total: 8),
            5
        )
    }

    func testScrollInspectorConsumesWithoutSubscriberOrSelection() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.installForPreviews(
            items: [],
            signals: RefsSignals(),
            query: "keep",
            scope: .papers,
            selectedID: nil,
            banner: RefsBanner(
                kind: .warning,
                message: "stay",
                actions: [.copyDiagnostic]
            ),
            refreshState: .idle
        )
        let snapshot = PanelSnapshot(harness.model)

        XCTAssertNil(harness.model.selectedID)
        XCTAssertTrue(harness.model.perform(.scrollInspector(.down)))
        XCTAssertTrue(harness.model.perform(.scrollInspector(.up)))
        snapshot.assertUnchanged(harness.model)
        XCTAssertEqual(harness.dismissed, 0)
    }

    func testVisibleSelectionMovedKeepsUserSelection() async throws {
        let markerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: markerDir,
            withIntermediateDirectories: true
        )
        let harness = try makeHarness(environment: [
            "FAKE_BOB_SCAN_MARKER_DIR": markerDir.path,
            "FAKE_BOB_REFS_LIST_AFTER_SCAN_FIXTURE": "refs-list-after-scan.json",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }

        XCTAssertTrue(harness.model.perform(.scan))
        XCTAssertTrue(harness.model.perform(.select(id: "ref/papers/small_ready.md")))
        await harness.waitForScan()
        XCTAssertEqual(harness.model.selectedID, "ref/papers/small_ready.md")
    }

    func testVisibleSearchKeepsQueryAndSelection() async throws {
        let markerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: markerDir,
            withIntermediateDirectories: true
        )
        let harness = try makeHarness(environment: [
            "FAKE_BOB_SCAN_MARKER_DIR": markerDir.path,
            "FAKE_BOB_REFS_LIST_AFTER_SCAN_FIXTURE": "refs-list-after-scan.json",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }
        harness.model.query = "reading"
        harness.model.queryDidChange()
        let selectedBefore = harness.model.selectedID

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        XCTAssertEqual(harness.model.query, "reading")
        XCTAssertEqual(harness.model.selectedID, selectedBefore)
        guard let notice = harness.model.scanNotice else {
            XCTFail("expected notice")
            return
        }
        let footer = RefsScanPresentation.footerText(notice, searchMode: true)
        XCTAssertTrue(footer.contains(" · esc shows them"))
    }

    func testHiddenNotifierAndPrepareShowsPending() async throws {
        let markerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: markerDir,
            withIntermediateDirectories: true
        )
        let harness = try makeHarness(environment: [
            "FAKE_BOB_SCAN_MARKER_DIR": markerDir.path,
            "FAKE_BOB_REFS_LIST_AFTER_SCAN_FIXTURE": "refs-list-after-scan.json",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { false }
        var notified: [RefsScanOutcome] = []
        harness.model.scanNotifier = { notified.append($0) }

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        XCTAssertEqual(notified.count, 1)
        XCTAssertNil(harness.model.banner)
        harness.model.prepareForPresentation()
        XCTAssertEqual(
            harness.model.selectedID,
            "ref/chat/omni_report.md"
        )
        XCTAssertEqual(harness.model.listing.sections.first?.kind, .justScanned)
    }

    func testHiddenNothingNewDoesNotNotify() async throws {
        let nothingURL = try harnessFixtureURL("refs-scan-nothing.json").path
        let harness = try makeHarness(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": nothingURL,
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { false }
        var notified = 0
        harness.model.scanNotifier = { _ in notified += 1 }

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        XCTAssertEqual(notified, 0)
    }

    func testNoticeClearsOnHideAfterSeen() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        XCTAssertNotNil(harness.model.scanNotice)
        harness.model.panelDidHide()
        XCTAssertNil(harness.model.scanNotice)
    }

    func testPartialAndFailedBanners() async throws {
        let partialURL = try harnessFixtureURL("refs-scan-partial.json").path
        let partial = try makeHarness(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": partialURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ])
        await partial.waitForSnapshot()
        partial.model.prepareForPresentation()
        partial.model.panelIsVisible = { true }

        XCTAssertTrue(partial.model.perform(.scan))
        await partial.waitForScan()
        XCTAssertEqual(partial.model.banner?.kind, .warning)
        XCTAssertEqual(partial.model.banner?.actions, [.copyDiagnostic])
        XCTAssertTrue(partial.model.banner?.message.contains("couldn't be scanned") ?? false)
        partial.model.performBannerAction(.copyDiagnostic)
        XCTAssertFalse(partial.pasteboard.strings.isEmpty)
        XCTAssertTrue(partial.pasteboard.strings[0].contains("bob ref scan"))

        let dirtyURL = try harnessFixtureURL("refs-scan-dirty.json").path
        let failed = try makeHarness(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": dirtyURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ])
        await failed.waitForSnapshot()
        failed.model.prepareForPresentation()
        failed.model.panelIsVisible = { true }

        XCTAssertTrue(failed.model.perform(.scan))
        await failed.waitForScan()
        XCTAssertEqual(failed.model.banner?.kind, .error)
        XCTAssertEqual(failed.model.banner?.actions, [.scanAgain, .copyDiagnostic])
        XCTAssertTrue(failed.model.banner?.message.contains("couldn't scan") ?? false)
    }

    func testScanAgainStartsScanAndEscDismissesFirst() async throws {
        let dirtyURL = try harnessFixtureURL("refs-scan-dirty.json").path
        let harness = try makeHarness(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": dirtyURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        XCTAssertNotNil(harness.model.banner)
        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertNil(harness.model.banner)
        harness.model.performBannerAction(.scanAgain)
        await harness.waitForScanStart()
        XCTAssertTrue(harness.model.isScanning)
        await harness.waitForScan()
    }

    func testHiddenPartialAndFailedNotify() async throws {
        let partialURL = try harnessFixtureURL("refs-scan-partial.json").path
        let partial = try makeHarness(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": partialURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ])
        await partial.waitForSnapshot()
        partial.model.prepareForPresentation()
        partial.model.panelIsVisible = { false }
        var partialNotified = 0
        partial.model.scanNotifier = { _ in partialNotified += 1 }
        XCTAssertTrue(partial.model.perform(.scan))
        await partial.waitForScan()
        XCTAssertEqual(partialNotified, 1)
        partial.model.prepareForPresentation()
        XCTAssertEqual(partial.model.banner?.kind, .warning)

        let dirtyURL = try harnessFixtureURL("refs-scan-dirty.json").path
        let failed = try makeHarness(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": dirtyURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ])
        await failed.waitForSnapshot()
        failed.model.prepareForPresentation()
        failed.model.panelIsVisible = { false }
        var failedNotified = 0
        failed.model.scanNotifier = { _ in failedNotified += 1 }
        XCTAssertTrue(failed.model.perform(.scan))
        await failed.waitForScan()
        XCTAssertEqual(failedNotified, 1)
        failed.model.prepareForPresentation()
        XCTAssertEqual(failed.model.banner?.kind, .error)
        XCTAssertEqual(failed.model.banner?.actions, [.scanAgain, .copyDiagnostic])
    }

    @MainActor
    private struct PanelSnapshot {
        let query: String
        let scope: RefScope
        let selectedID: String?
        let listing: RefsListing
        let banner: RefsBanner?

        init(_ model: RefsPanelModel) {
            query = model.query
            scope = model.scope
            selectedID = model.selectedID
            listing = model.listing
            banner = model.banner
        }

        func assertUnchanged(_ model: RefsPanelModel) {
            XCTAssertEqual(model.query, query)
            XCTAssertEqual(model.scope, scope)
            XCTAssertEqual(model.selectedID, selectedID)
            XCTAssertEqual(model.listing, listing)
            XCTAssertEqual(model.banner, banner)
        }
    }

    private static func twoPreviewItems() -> [RefItem] {
        [
            RefItem(
                id: "ref/chat/alpha.md",
                link: "[[ref/chat/alpha]]",
                rawTitle: "Alpha",
                stem: "alpha",
                kind: .chat,
                state: .ready,
                isBlocked: false,
                pdfPath: "lib/chat/alpha.pdf"
            ),
            RefItem(
                id: "ref/chat/beta.md",
                link: "[[ref/chat/beta]]",
                rawTitle: "Beta",
                stem: "beta",
                kind: .chat,
                state: .ready,
                isBlocked: false,
                pdfPath: "lib/chat/beta.pdf"
            ),
        ]
    }

    private static func eightNotes() -> [RefsShowAnnotation] {
        (1...8).map { index in
            RefsShowAnnotation(
                pageLabel: "\(index)",
                kind: "highlight",
                quote: "Quote \(index)",
                comment: "Comment \(index)"
            )
        }
    }

    private static func pickerAnnotations() -> [RefsShowAnnotation] {
        [
            RefsShowAnnotation(
                pageLabel: "Page 11",
                kind: "highlight",
                quote: "Uncommented quote",
                link: "[[ref/chat/alpha#^h-1]]"
            ),
            RefsShowAnnotation(
                pageLabel: "Page 12",
                kind: "highlight",
                quote: "Commented quote",
                comment: "Keep this",
                link: "[[ref/chat/alpha#^h-2]]"
            ),
            RefsShowAnnotation(
                pageLabel: "Page 13",
                kind: "note",
                comment: "Standalone",
                link: "[[ref/chat/alpha#^n-1]]"
            ),
        ]
    }

    private static func twoNotes() -> [RefsShowAnnotation] {
        (1...2).map { index in
            RefsShowAnnotation(
                pageLabel: "\(index)",
                kind: "highlight",
                quote: "Quote \(index)",
                comment: "Comment \(index)"
            )
        }
    }

    // MARK: - Harness

    @MainActor
    fileprivate final class Harness {
        let library: RefsLibrary
        let model: RefsPanelModel
        let opener: FakeOpener
        let pasteboard: FakePasteboard
        let vault: URL
        let highlightsURL: URL?
        nonisolated(unsafe) var dismissed = 0
        nonisolated(unsafe) var presented = 0
        nonisolated(unsafe) var represented = 0

        init(
            library: RefsLibrary,
            model: RefsPanelModel,
            opener: FakeOpener,
            pasteboard: FakePasteboard,
            vault: URL,
            highlightsURL: URL?
        ) {
            self.library = library
            self.model = model
            self.opener = opener
            self.pasteboard = pasteboard
            self.vault = vault
            self.highlightsURL = highlightsURL
        }

        func waitForSnapshot(ids: Set<String>? = nil) async {
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                if library.hasSnapshot, library.lastSuccessAt != nil {
                    if let ids {
                        if Set(library.items.map(\.id)) == ids {
                            return
                        }
                    } else if !library.items.isEmpty {
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTFail("snapshot not ready before timeout")
        }

        func waitForOpens(id: String, count: Int) async {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if library.signals.opens.count(id) == count {
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTFail("open not recorded before timeout")
        }

        func waitForModel(_ condition: @MainActor (RefsPanelModel) -> Bool) async {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if condition(model) {
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTFail("model condition not met before timeout")
        }

        func waitForScan() async {
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                if model.scanNotice != nil, !model.isScanning {
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTFail("scan did not finish before timeout")
        }

        func waitForScanStart() async {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if model.isScanning {
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTFail("scan did not start before timeout")
        }
    }

    private func makeHarness(
        highlightsURL: URL? = URL(fileURLWithPath: "/Applications/Highlights.app"),
        missing: Set<String> = [],
        environment: [String: String] = [:]
    ) throws -> Harness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("ref"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("lib"),
            withIntermediateDirectories: true
        )
        let library = RefsLibrary(
            fetcher: BobRefsFetcher(client: try bobClient(environment: environment)),
            snapshotStore: RefsSnapshotStore(
                fileURL: root.appendingPathComponent("refs-snapshot.json")
            ),
            openLogStore: RefsOpenLogStore(
                fileURL: root.appendingPathComponent("refs-open-log.json")
            ),
            vaultRoot: { vault },
            fileExists: { url in !missing.contains(where: { url.path.hasSuffix($0) }) },
            spotlight: FakeSpotlight(),
            now: { Date() }
        )
        let opener = FakeOpener()
        let pasteboard = FakePasteboard()
        let locator = FakeLocator(appURL: highlightsURL)
        let model = RefsPanelModel(
            library: library,
            opener: opener,
            highlights: locator,
            pasteboard: pasteboard
        )
        let harness = Harness(
            library: library,
            model: model,
            opener: opener,
            pasteboard: pasteboard,
            vault: vault,
            highlightsURL: highlightsURL
        )
        model.panelDismisser = { [weak harness] in harness?.dismissed += 1 }
        model.panelPresenter = { [weak harness] in harness?.presented += 1 }
        // The error re-show path keeps every bit of panel state, like the
        // real coordinator-backed representer.
        model.panelRepresenter = { [weak harness] in harness?.represented += 1 }
        // Kick off the snapshot refresh every test waits for: nothing in the
        // model triggers one on its own.
        library.refresh(reason: .manual)
        return harness
    }

    private func bobClient(environment: [String: String]) throws -> BobProcessClient {
        BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
                .merging(environment) { _, override in override }
        )
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }
}

private extension RefsPanelModelTests.Harness {
    func retireFixtureRow(path: String) throws {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: packageRoot.appendingPathComponent("Tests/Fixtures/refs-list.json")
        )
        var document = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let refs = (document["refs"] as! [[String: Any]]).filter {
            ($0["path"] as! String) != path
        }
        document["refs"] = refs
        let retired = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try JSONSerialization.data(withJSONObject: document).write(to: retired)
        library.setFetcher(
            BobRefsFetcher(client: try client(environment: [
                "FAKE_BOB_REFS_LIST_FIXTURE": retired.path,
            ]))
        )
    }

    func client(environment: [String: String]) throws -> BobProcessClient {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return BobProcessClient(
            executablePath: packageRoot
                .appendingPathComponent("Tests/Fixtures/fake-bob")
                .path,
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
                .merging(environment) { _, override in override }
        )
    }

    /// Serves a `refs-list.json` variant with one row's `added` rewritten,
    /// so a refresh re-ranks from visibly new data.
    func serveAddedVariant(path: String, added: String) throws {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: packageRoot.appendingPathComponent("Tests/Fixtures/refs-list.json")
        )
        var document = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let refs = (document["refs"] as! [[String: Any]]).map { row -> [String: Any] in
            guard (row["path"] as! String) == path else {
                return row
            }
            var edited = row
            edited["added"] = added
            edited["added_source"] = "created"
            return edited
        }
        document["refs"] = refs
        let variant = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try JSONSerialization.data(withJSONObject: document).write(to: variant)
        library.setFetcher(
            BobRefsFetcher(client: try client(environment: [
                "FAKE_BOB_REFS_LIST_FIXTURE": variant.path,
            ]))
        )
    }
}

private func harnessFixtureURL(_ name: String) throws -> URL {
    let source = URL(fileURLWithPath: #filePath)
    let packageRoot = source
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let direct = packageRoot.appendingPathComponent("Tests/Fixtures/\(name)")
    guard FileManager.default.fileExists(atPath: direct.path) else {
        throw NSError(
            domain: "RefsPanelModelTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"]
        )
    }
    return direct
}

/// Today's date as `YYYY-MM-DD`, the `added` form `bob` emits.
private func todayDateString() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

/// How many fake-bob invocations start with `prefix` in a record file.
private func argvCount(_ recordURL: URL, prefix: String) -> Int {
    let record = (try? String(contentsOf: recordURL)) ?? ""
    return record.components(separatedBy: prefix).count - 1
}

final class FakeOpener: RefsOpening, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var highlightsOpens: [(pdf: URL, app: URL)] = []
    private(set) var noteOpens: [URL] = []
    private(set) var reveals: [URL] = []
    private(set) var defaultAppOpens: [URL] = []
    var highlightsError: Error?
    var defaultAppError: Error?

    func openInHighlights(
        _ pdf: URL,
        app: URL,
        completion: @escaping (Error?) -> Void
    ) {
        lock.withLock { highlightsOpens.append((pdf, app)) }
        completion(highlightsError)
    }

    func openNote(_ url: URL) {
        lock.withLock { noteOpens.append(url) }
    }

    func reveal(_ url: URL) {
        lock.withLock { reveals.append(url) }
    }

    func openWithDefaultApp(_ url: URL, completion: @escaping (Error?) -> Void) {
        lock.withLock { defaultAppOpens.append(url) }
        completion(defaultAppError)
    }
}

struct FakeLocator: RefsHighlightsLocating, Sendable {
    var appURL: URL?

    func highlightsAppURL() -> URL? {
        appURL
    }
}
