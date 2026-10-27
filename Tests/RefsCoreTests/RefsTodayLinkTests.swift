import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

final class RefsTodayLinkTests: XCTestCase {
    func testRealEnvelopesReuseCaptureDecoder() throws {
        for name in ["listing", "linked", "created", "moved", "already-current", "link-guard"] {
            let response = try fixture(name)
            XCTAssertEqual(response.schemaVersion, 1)
            XCTAssertEqual(response.ok, true)
            XCTAssertEqual(response.ref?.title, "Attention Is All You Need")
            XCTAssertEqual(response.task?.blockID, "ref-attention")
            XCTAssertEqual(response.capture?.blockID, "ref-attention")
            XCTAssertEqual(response.mode, name == "listing" ? "dry_run" : "write")
            XCTAssertFalse(response.pomodoros.isEmpty)
        }
        let error = try fixture("multiple-running")
        XCTAssertEqual(error.ok, false)
        XCTAssertEqual(error.error?.code, "multiple_running")
        XCTAssertNil(error.capture)
        XCTAssertEqual(error.pomodoros.count, 2)

        for (name, code) in [
            ("no-reading-task", "no_reading_task"),
            ("stale-pomodoro", "stale_pomodoro"),
            ("reading-task-closed", "reading_task_closed"),
        ] {
            let refusal = try fixture(name)
            XCTAssertEqual(refusal.ok, false)
            XCTAssertEqual(refusal.error?.code, code)
            XCTAssertNil(refusal.capture)
        }
    }

    func testOptionalAndUnknownFields() throws {
        let minimal = try decode(#"{"schema_version":1,"future":{"new":42}}"#)
        XCTAssertNil(minimal.ok)
        XCTAssertNil(minimal.mode)
        XCTAssertNil(minimal.changed)
        XCTAssertNil(minimal.capture)
        XCTAssertEqual(minimal.pomodoros, [])
        XCTAssertEqual(minimal.candidates, [])
        let additive = try decode(
            #"{"schema_version":1,"ok":false,"candidates":[{"path":"ref/a.md","title":"A","extra":0}],"pomodoros":[{"ref":"3:abc","extra":true}],"task":{"path":"a.md"},"ref":{"title":"A"},"error":{"code":"unknown_reference","message":"missing","extra":0}}"#
        )
        XCTAssertEqual(additive.candidates.first?.path, "ref/a.md")
        XCTAssertEqual(additive.pomodoros.first?.taskLinkCount, 0)
        XCTAssertEqual(additive.pomodoros.first?.running, false)
        XCTAssertNil(additive.error?.hint)
        XCTAssertThrowsError(try decode(#"{"ok":true}"#))
    }

    func testFrozenIdentityLoadingFastPathAndRunningGuards() throws {
        var card = makeCard()
        XCTAssertEqual(card.frozenItemID, "ref/papers/attention.md")
        XCTAssertEqual(card.notePath, card.frozenItemID)
        XCTAssertEqual(card.title, "Attention Is All You Need")
        XCTAssertEqual(card.taskCaption, "sase.md · ^ref-attention")
        XCTAssertEqual(card.phase, .loading)
        XCTAssertEqual(card.handle(.submit), .submit(.automatic))
        XCTAssertEqual(card.phase, .running)
        XCTAssertEqual(card.editQuery("READ"), .none)
        XCTAssertEqual(card.handle(.cancel), .none)
        XCTAssertEqual(card.handle(.move(1)), .none)
        XCTAssertEqual(card.handle(.submit), .none)
        XCTAssertEqual(card.select(index: 0), .none)
        XCTAssertEqual(card.applyListing(try fixture("listing")), .none)
        XCTAssertEqual(card.phase, .running)
        XCTAssertEqual(card.query, "")
    }

    func testTypedLoadingWaitsForListing() throws {
        var card = makeCard()
        XCTAssertEqual(card.editQuery("read"), .none)
        XCTAssertEqual(card.handle(.submit), .none)
        XCTAssertEqual(card.handle(.submitExactName), .none)
        XCTAssertEqual(card.applyListing(try fixture("listing")), .preview(.entry(ref: "4:ddf7159c")))
        XCTAssertEqual(card.query, "read")
        XCTAssertEqual(card.phase, .ready)
        XCTAssertEqual(card.handle(.submit), .submit(.entry(ref: "4:ddf7159c")))
    }

    func testDefaultSelectionArrowsClickAndCreateUseDistinctSelectors() throws {
        var card = makeCard()
        XCTAssertEqual(card.applyListing(try fixture("listing")), .none)
        XCTAssertEqual(card.selectedPomodoro?.name, "CURRENT")
        XCTAssertEqual(card.selector, .automatic)
        XCTAssertEqual(card.handle(.move(1)), .preview(.entry(ref: "4:ddf7159c")))
        XCTAssertEqual(card.handle(.move(1)), .preview(.entry(ref: "2:4e8b857b")))
        XCTAssertEqual(card.handle(.move(-1)), .preview(.entry(ref: "4:ddf7159c")))
        XCTAssertEqual(card.editQuery(" read "), .preview(.entry(ref: "4:ddf7159c")))
        XCTAssertTrue(card.offersCreate)
        XCTAssertEqual(card.handle(.move(1)), .preview(.exactName(" read ")))
        XCTAssertTrue(card.selectsCreate)
        XCTAssertEqual(card.handle(.submit), .submit(.exactName(" read ")))

        card = makeCard()
        card.applyListing(try fixture("listing"))
        card.editQuery("read")
        XCTAssertEqual(card.handle(.submitExactName), .submit(.exactName("read")))
        card = makeCard()
        card.applyListing(try fixture("listing"))
        card.editQuery(" reading ")
        XCTAssertFalse(card.offersCreate)
        XCTAssertEqual(card.select(index: 0), .preview(.entry(ref: "4:ddf7159c")))
        XCTAssertEqual(card.handle(.submit), .submit(.entry(ref: "4:ddf7159c")))
    }

    func testRankingTiersPreserveDocumentOrderAndUntitledMatchesOnlyTime() {
        var card = makeCard()
        let rows = [
            row("fuzzy1", "BREAD"), row("prefix1", "READING"), row("fuzzy2", "RED AND"),
            row("prefix2", "READ MORE"), row("exact", "READ"), row("empty", nil, time: "0920-0950"),
            row("timed", "WORK", time: "0920-0950"), row("numeric", "0920"),
        ]
        card.applyListing(RefsTodayLinkResponse(ok: true, pomodoros: rows))
        XCTAssertEqual(card.visiblePomodoros.map(\.ref), rows.map(\.ref))
        card.editQuery("read")
        XCTAssertEqual(
            card.visiblePomodoros.map(\.ref), ["exact", "prefix1", "prefix2", "fuzzy1", "fuzzy2"])
        XCTAssertFalse(card.offersCreate)
        card.editQuery("read m")
        XCTAssertEqual(card.visiblePomodoros.map(\.ref), ["prefix2"])
        for query in ["0920", "9:20", "09:20"] {
            card.editQuery(query)
            XCTAssertEqual(card.visiblePomodoros.suffix(2).map(\.ref), ["empty", "timed"])
        }
        card.editQuery("untitled")
        XCTAssertTrue(card.visiblePomodoros.isEmpty)
        XCTAssertTrue(card.selectsCreate)
    }

    func testHomesListingDecodesAndNeverRoutesOnDerivedLabel() throws {
        var card = makeCard()
        let homes = try fixture("homes")
        XCTAssertEqual(homes.schemaVersion, 1)
        XCTAssertEqual(homes.pomodoros.count, 2)
        XCTAssertNil(homes.pomodoros[0].name)
        XCTAssertEqual(homes.pomodoros[0].homes?.label, "sase")
        XCTAssertEqual(homes.pomodoros[0].homes?.chip, "sase")
        XCTAssertEqual(homes.pomodoros[0].homes?.parts.first?.key, "sase.md")
        XCTAssertEqual(homes.pomodoros[1].name, "HACK")
        XCTAssertNil(homes.pomodoros[1].homes, "Bob omits homes for named rows")
        card.applyListing(homes)
        // Derived homes are display-only (R7): typing a derived label matches
        // no authored row, so the Create row keeps its place for `SASE`.
        card.editQuery("sase")
        XCTAssertTrue(card.visiblePomodoros.isEmpty)
        XCTAssertTrue(card.offersCreate)
        XCTAssertTrue(card.selectsCreate)
        // Authored names still match; rows keep displaying the derived label.
        card.editQuery("hack")
        XCTAssertEqual(card.visiblePomodoros.map(\.ref), [homes.pomodoros[1].ref])
        XCTAssertEqual(
            RefsTodayLinkPresentation.rowTitle(
                try XCTUnwrap(card.visiblePomodoros.first)), "HACK")
    }

    func testPreviewTokensRejectOldSelectionsAndRepeatedSelectors() throws {
        var card = makeCard()
        card.applyListing(try fixture("listing"))
        card.editQuery("read")
        let old = try XCTUnwrap(card.previewRequest)
        card.editQuery("focus")
        XCTAssertFalse(card.applyPreview(try fixture("created"), for: old))
        card.editQuery("read")
        let current = try XCTUnwrap(card.previewRequest)
        XCTAssertEqual(old.selector, current.selector)
        XCTAssertNotEqual(old.generation, current.generation)
        XCTAssertFalse(card.applyPreview(try fixture("created"), for: old))
        XCTAssertTrue(card.previewPending)
        XCTAssertEqual(card.preview?.capture?.pomodoroName, "CURRENT")
        XCTAssertTrue(card.applyPreview(try fixture("moved"), for: current))
        XCTAssertFalse(card.previewPending)
        XCTAssertEqual(card.preview?.capture?.pomodoroName, "FOCUS")
        XCTAssertFalse(card.applyPreview(try fixture("created"), for: current))
        card.editQuery("focus")
        let running = try XCTUnwrap(card.previewRequest)
        card.handle(.submit)
        XCTAssertFalse(card.applyPreview(try fixture("created"), for: running))
    }

    func testRecoverableListingProblemsRequireExplicitSelection() throws {
        var card = makeCard()
        card.applyListing(try fixture("multiple-running"))
        XCTAssertEqual(card.phase, .ready)
        XCTAssertNil(card.selectedIndex)
        XCTAssertNil(card.selector)
        XCTAssertEqual(card.handle(.submit), .none)
        XCTAssertEqual(card.handle(.move(-1)), .preview(.entry(ref: "3:965d871a")))
        XCTAssertEqual(card.handle(.submit), .submit(.entry(ref: "3:965d871a")))

        card = makeCard()
        card.applyListing(RefsTodayLinkResponse(ok: false, error: problem("no_open_pomodoro")))
        XCTAssertEqual(card.phase, .ready)
        XCTAssertEqual(card.rowCount, 0)
        XCTAssertEqual(card.handle(.move(1)), .none)
        XCTAssertEqual(card.handle(.submit), .none)
        XCTAssertEqual(card.editQuery("  Deep   work  "), .preview(.exactName("  Deep   work  ")))
        XCTAssertEqual(card.rowCount, 1)
        XCTAssertEqual(card.handle(.submit), .submit(.exactName("  Deep   work  ")))
    }

    func testRefusalFailureRecoveryAndStaleReload() throws {
        for code in [
            "no_reading_task", "reading_task_closed", "v1_reading_task", "bob_too_old", "no_daily_note",
        ] {
            var card = makeCard()
            card.applyListing(RefsTodayLinkResponse(ok: false, error: problem(code)))
            XCTAssertEqual(card.phase, .refused(message: "Bob says \(code)", hint: "Try again"))
            XCTAssertEqual(card.editQuery("read"), .none)
            XCTAssertEqual(card.handle(.submit), .none)
            XCTAssertEqual(card.handle(.cancel), .cancel)
        }
        var card = makeCard()
        card.applyListing(try fixture("listing"))
        card.editQuery("read")
        card.handle(.submit)
        XCTAssertEqual(card.fail(problem("note_changed")), .none)
        XCTAssertEqual(card.phase, .failed(message: "Bob says note_changed", hint: "Try again"))
        card.editQuery("reading")
        XCTAssertEqual(card.phase, .ready)
        XCTAssertNil(card.failure)
        card.handle(.submit)
        XCTAssertEqual(card.fail(problem("stale_pomodoro")), .reload)
        XCTAssertEqual(card.query, "reading")
        XCTAssertEqual(card.phase, .reloading)
        XCTAssertEqual(card.pomodoros, [])
        XCTAssertEqual(card.handle(.submit), .none)
        XCTAssertEqual(card.editQuery("rea"), .none)
        XCTAssertEqual(card.query, "rea")
        XCTAssertEqual(card.applyListing(try fixture("linked")), .preview(.entry(ref: "5:ddf7159c")))
        XCTAssertEqual(card.query, "rea")
        XCTAssertEqual(card.handle(.submit), .submit(.entry(ref: "5:ddf7159c")))

        var cancellableReload = makeCard()
        cancellableReload.applyListing(try fixture("listing"))
        cancellableReload.handle(.submit)
        XCTAssertEqual(cancellableReload.fail(problem("stale_pomodoro")), .reload)
        XCTAssertEqual(cancellableReload.handle(.cancel), .cancel)
    }

    func testKeyMapAndIME() {
        let keys: [(UInt16, RefsCopyKeyModifiers, RefsTodayLinkKeyCommand)] = [
            (36, [], .submit), (76, .numericPad, .submit), (45, [.command, .capsLock], .submit),
            (36, .shift, .submitExactName), (76, .shift, .submitExactName),
            (125, .function, .move(1)), (126, [], .move(-1)),
            (35, .control, .move(-1)), (40, .control, .move(-1)),
            (45, .control, .move(1)), (38, .control, .move(1)),
            (53, [], .cancel), (33, .control, .cancel), (48, [], .ignore), (48, .shift, .ignore),
        ]
        for (code, flags, expected) in keys {
            XCTAssertEqual(
                RefsTodayLinkKeyMap.command(keyCode: code, modifiers: flags, isRunning: false), expected)
            XCTAssertEqual(
                RefsTodayLinkKeyMap.command(keyCode: code, modifiers: flags, isRunning: true), .ignore)
            if code != 48 {
                XCTAssertNil(
                    RefsTodayLinkKeyMap.command(
                        keyCode: code, modifiers: flags, isRunning: false, hasMarkedText: true))
            }
        }
        XCTAssertNil(RefsTodayLinkKeyMap.command(keyCode: 45, modifiers: [], isRunning: false))
        XCTAssertNil(RefsTodayLinkKeyMap.command(keyCode: 36, modifiers: .command, isRunning: false))
        XCTAssertEqual(RefsTodayLinkKeyMap.command(keyCode: 0, modifiers: [], isRunning: true), .ignore)
    }

    func testRowCopyAndTimeMath() throws {
        let rows = try fixture("listing").pomodoros
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-16T09:15:00Z"))
        XCTAssertEqual(RefsTodayLinkPresentation.placeholder(pomodoros: rows), "Pomodoro — ↵ CURRENT")
        XCTAssertEqual(RefsTodayLinkPresentation.placeholder(pomodoros: []), "Name a Pomodoro")
        XCTAssertEqual(
            RefsTodayLinkPresentation.rowMeta(rows[0], now: now, timeZone: zone),
            "09:00–09:30 · 15m left · empty")
        XCTAssertEqual(
            RefsTodayLinkPresentation.rowMeta(rows[0], now: now.addingTimeInterval(1200), timeZone: zone),
            "09:00–09:30 · 5m over · empty")
        XCTAssertEqual(
            RefsTodayLinkPresentation.rowMeta(rows[1], now: now, timeZone: zone), "planned · empty")
        XCTAssertEqual(RefsTodayLinkPresentation.progress(rows[0], now: now, timeZone: zone), 0.5)
        XCTAssertEqual(
            RefsTodayLinkPresentation.progress(
                rows[0], now: now.addingTimeInterval(-3600), timeZone: zone), 0)
        XCTAssertEqual(
            RefsTodayLinkPresentation.progress(
                rows[0], now: now.addingTimeInterval(3600), timeZone: zone), 1)
        XCTAssertNil(RefsTodayLinkPresentation.progress(rows[1], now: now, timeZone: zone))
        XCTAssertEqual(RefsTodayLinkPresentation.pills(rows[0]), ["Running"])
        let current = try fixture("already-current").pomodoros[1]
        XCTAssertEqual(RefsTodayLinkPresentation.pills(current), ["Next up", "Here"])
        XCTAssertEqual(RefsTodayLinkPresentation.rowMeta(current, now: now), "planned · 1 task")
        XCTAssertEqual(RefsTodayLinkPresentation.rowTitle(row("unnamed", nil)), "Untitled Pomodoro")
        let homes = try fixture("homes")
        XCTAssertEqual(homes.pomodoros.count, 2)
        XCTAssertEqual(RefsTodayLinkPresentation.rowTitle(homes.pomodoros[0]), "sase")
        XCTAssertTrue(RefsTodayLinkPresentation.rowTitleIsDerived(homes.pomodoros[0]))
        XCTAssertNil(RefsTodayLinkPresentation.namedHomeChip(homes.pomodoros[0]))
        XCTAssertNil(RefsTodayLinkPresentation.namedHomeHue(homes.pomodoros[0]))
        XCTAssertEqual(RefsTodayLinkPresentation.rowTitle(homes.pomodoros[1]), "HACK")
        XCTAssertNil(homes.pomodoros[1].homes, "Bob omits homes for named rows")
        XCTAssertNil(RefsTodayLinkPresentation.namedHomeChip(homes.pomodoros[1]))
        let namedWithHomes = RefsTodayLinkPomodoro(
            ref: "future-compatible-named",
            name: "HACK",
            homes: CaptureAgendaHomes(
                state: .forecast, kind: .work, label: "bob · dev", chip: "bob · dev", hue: .orange))
        XCTAssertEqual(RefsTodayLinkPresentation.rowTitle(namedWithHomes), "HACK")
        XCTAssertEqual(RefsTodayLinkPresentation.namedHomeChip(namedWithHomes), "bob · dev")
        XCTAssertEqual(RefsTodayLinkPresentation.namedHomeHue(namedWithHomes), .orange)
        XCTAssertEqual(
            RefsTodayLinkPresentation.rowAccessibilityLabel(
                homes.pomodoros[0], selected: false, now: now, timeZone: zone),
            "for sase, running, here, 09:00–09:30 · 15m left · 1 task")
        XCTAssertTrue(
            RefsTodayLinkPresentation.rowAccessibilityLabel(
                namedWithHomes, selected: false, now: now, timeZone: zone
            ).contains("for bob · dev"))
        XCTAssertEqual(
            RefsTodayLinkPresentation.createTitle(query: " deep   work "), "New Pomodoro DEEP WORK")
        XCTAssertEqual(RefsTodayLinkPresentation.hints(query: ""), "↑↓ select   ↵ link   esc cancel")
        XCTAssertEqual(
            RefsTodayLinkPresentation.hints(query: "read"),
            "↑↓ select   ↵ link   ⇧↵ new READ   esc cancel")
        XCTAssertEqual(
            RefsTodayLinkPresentation.rowAccessibilityLabel(
                rows[0], selected: true, now: now, timeZone: zone),
            "CURRENT, running, 09:00–09:30 · 15m left · empty, selected")
        let multiple = try fixture("multiple-running")
        XCTAssertEqual(
            RefsTodayLinkPresentation.defaultProblem(multiple.error, pomodoros: multiple.pomodoros),
            "2 Pomodoros are running — pick one")
    }

    func testPreviewToastNotificationAndAnnouncementVariants() throws {
        let title = "Attention Is All You Need"
        let listing = try fixture("listing")
        XCTAssertEqual(RefsTodayLinkPresentation.laneChip(capture: listing.capture), "Ready → Next")
        XCTAssertEqual(
            RefsTodayLinkPresentation.previewLine(listing), "Ready → Next · Linked under CURRENT")
        let variants: [(String, RefsTodayLinkToast.Style, String, String)] = [
            ("linked", .linked, "Linked under CURRENT", "Ready → Next"),
            ("created", .linked, "Linked under new FOCUS", "Ready → Next"),
            ("moved", .moved, "Moved to FOCUS", "from CURRENT · Ready → Next"),
            ("already-current", .already, "Already in READING", "already Next · no change"),
            (
                "link-guard", .guarded, "Not linked",
                "not linked (project waits on [[job.md#^prep]]) · promoted job.md#^prep"
            ),
        ]
        for (fixtureName, style, headline, detail) in variants {
            let response = try fixture(fixtureName)
            let toast = try XCTUnwrap(RefsTodayLinkPresentation.toast(response: response, title: title))
            XCTAssertEqual(toast.style, style)
            XCTAssertEqual(toast.title, headline)
            XCTAssertEqual(toast.value, title)
            XCTAssertEqual(toast.detail, detail)
            XCTAssertEqual(toast.glyphName, style == .guarded ? "lock.fill" : "timer")
            let notification = try XCTUnwrap(
                RefsTodayLinkPresentation.notification(response: response, title: title))
            XCTAssertEqual(notification.title, headline)
            XCTAssertEqual(notification.body, "\(title)\n\(detail)")
            XCTAssertTrue(
                try XCTUnwrap(RefsTodayLinkPresentation.announcement(response: response, title: title))
                    .contains(title))
        }
        XCTAssertEqual(
            RefsTodayLinkPresentation.announcement(response: try fixture("linked"), title: title),
            "Linked Attention Is All You Need under CURRENT. Ready to Next.")
        XCTAssertEqual(
            RefsTodayLinkPresentation.laneChip(capture: try fixture("link-guard").capture), "won't link")
        XCTAssertEqual(
            RefsTodayLinkPresentation.laneChip(capture: try fixture("already-current").capture),
            "stays Next")
        XCTAssertNil(
            RefsTodayLinkPresentation.toast(response: try fixture("multiple-running"), title: title))
        let failure = RefsTodayLinkPresentation.failureNotification(
            message: "Something changed", hint: "Try again")
        XCTAssertEqual(failure.title, "Reference link failed")
        XCTAssertEqual(failure.body, "Something changed\nTry again")
    }

    func testUnnamedDerivedLabelNamesToastDestination() throws {
        var json = try fixtureJSON("linked")
        var pomodoros = try XCTUnwrap(json["pomodoros"] as? [[String: Any]])
        XCTAssertGreaterThan(pomodoros.count, 0)
        pomodoros[0]["name"] = nil
        pomodoros[0]["homes"] = [
            "state": "forecast", "kind": "work", "label": "sase", "chip": "sase",
            "hue": "orange",
            "parts": [
                ["key": "sase.md", "label": "sase", "kind": "project", "hue": "orange",
                  "tasks": 1, "share": 100]
            ],
        ]
        json["pomodoros"] = pomodoros
        var capture = try XCTUnwrap(json["capture"] as? [String: Any])
        capture["pomodoro_name"] = nil
        var destination = try XCTUnwrap(capture["pomodoro_link_destination"] as? [String: Any])
        destination["name"] = nil
        capture["pomodoro_link_destination"] = destination
        json["capture"] = capture
        let response = try decodeJSON(json)
        let toast = try XCTUnwrap(
            RefsTodayLinkPresentation.toast(response: response, title: "Attention Is All You Need"))
        XCTAssertEqual(toast.title, "Linked under sase")
        XCTAssertTrue(
            try XCTUnwrap(
                RefsTodayLinkPresentation.announcement(response: response, title: "Paper"))
                .contains("under sase"))
    }

    func testSharedChipsGuardPreviewAndRetainedLanes() throws {
        var json = try fixtureJSON("linked")
        var capture = try XCTUnwrap(json["capture"] as? [String: Any])
        capture["removed_scheduled"] = "2026-11-01"
        capture["dropped_dependencies"] = [
            ["note_path": "job.md", "block_id": "prep", "text": "Prepare", "link": "[[job#^prep]]"]
        ]
        json["capture"] = capture
        let changed = try decodeJSON(json)
        XCTAssertTrue(
            try XCTUnwrap(RefsTodayLinkPresentation.previewLine(changed)).contains(
                "removed future schedule"))
        XCTAssertTrue(
            try XCTUnwrap(RefsTodayLinkPresentation.toast(response: changed, title: "A")).detail.contains(
                "removed future schedule"))
        XCTAssertTrue(
            try XCTUnwrap(RefsTodayLinkPresentation.previewLine(changed)).contains(
                "dropped dependency on Prepare"))
        XCTAssertTrue(
            try XCTUnwrap(RefsTodayLinkPresentation.toast(response: changed, title: "A")).detail.contains(
                "dropped dependency on Prepare"))
        capture["status_changed"] = false
        capture["status_name"] = "In Progress"
        capture["status_symbol"] = "/"
        json["capture"] = capture
        XCTAssertEqual(
            RefsTodayLinkPresentation.laneChip(capture: try decodeJSON(json).capture), "stays In Progress"
        )
        json = try fixtureJSON("link-guard")
        capture = try XCTUnwrap(json["capture"] as? [String: Any])
        capture["dry_run"] = true
        json["capture"] = capture
        XCTAssertTrue(
            try XCTUnwrap(RefsTodayLinkPresentation.previewLine(decodeJSON(json))).hasPrefix(
                "Would not link — "))
    }

    func testRefusalCopyKeepsBobMessageSeparate() {
        let titles = [
            "no_reading_task": "No reading task to plan",
            "ambiguous_reading_task": "Multiple reading tasks",
            "v1_reading_task": "Reading task needs migration",
            "reading_task_unroutable": "Reading task can't be linked",
            "no_daily_note": "Today's daily note doesn't exist yet",
            "no_pomodoros_section": "No Pomodoros section today",
            "bob_too_old": "Update bob to link references",
            "reading_task_closed": "Reading task is closed",
            "unknown": "Could not link reference",
        ]
        for (code, title) in titles {
            XCTAssertEqual(RefsTodayLinkPresentation.refusalTitle(problem(code)), title)
        }
        XCTAssertEqual(
            RefsTodayLinkPresentation.refusalTitle(
                .init(code: "reading_task_closed", message: "reading task is already read")), "Already read"
        )
    }

    func testAlreadyLinkedDefaultUntitledSelectionAndCancelInvalidatePreview() throws {
        var card = makeCard()
        card.applyListing(try fixture("already-current"))
        XCTAssertEqual(card.selectedPomodoro?.name, "READING")
        XCTAssertEqual(card.selectedPomodoro?.linked, true)
        XCTAssertEqual(card.handle(.submit), .submit(.automatic))
        card = makeCard()
        card.applyListing(RefsTodayLinkResponse(ok: true, pomodoros: [row("2:unnamed", nil)]))
        XCTAssertEqual(card.select(index: 0), .preview(.entry(ref: "2:unnamed")))
        let token = try XCTUnwrap(card.previewRequest)
        XCTAssertEqual(card.handle(.cancel), .cancel)
        XCTAssertFalse(card.applyPreview(try fixture("listing"), for: token))
        XCTAssertFalse(card.previewPending)
    }

    func testPreviewErrorAndMalformedListing() throws {
        var card = makeCard()
        card.applyListing(try fixture("listing"))
        card.editQuery("read")
        let token = try XCTUnwrap(card.previewRequest)
        let failure = RefsTodayLinkResponse(ok: false, error: problem("invalid_pomodoro_name"))
        XCTAssertTrue(card.applyPreview(failure, for: token))
        XCTAssertEqual(card.phase, .ready)
        XCTAssertEqual(
            RefsTodayLinkPresentation.previewLine(card.preview), "Bob says invalid_pomodoro_name")
        card.applyListing(RefsTodayLinkResponse())
        XCTAssertEqual(
            card.phase, .refused(message: RefsTodayLinkPresentation.invalidResponse, hint: nil))
    }

    private func makeCard() -> RefsTodayLinkCard {
        RefsTodayLinkCard(
            item: RefItem(
                id: "ref/papers/attention.md", link: "[[ref/papers/attention]]",
                rawTitle: "Attention Is All You Need",
                stem: "attention", kind: .article, state: .ready, isBlocked: false,
                pdfPath: "lib/papers/attention.pdf",
                task: RefTask(path: "sase.md", blockID: "ref-attention")))
    }

    private func row(_ ref: String, _ name: String?, time: String? = nil) -> RefsTodayLinkPomodoro {
        RefsTodayLinkPomodoro(ref: ref, name: name, timeRange: time)
    }

    private func problem(_ code: String) -> RefsTodayLinkFailure {
        RefsTodayLinkFailure(code: code, message: "Bob says \(code)", hint: "Try again")
    }

    private func fixture(_ name: String) throws -> RefsTodayLinkResponse {
        try JSONDecoder().decode(
            RefsTodayLinkResponse.self, from: RefsModelTests.fixtureData("refs-today-\(name).json"))
    }

    private func fixtureJSON(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: RefsModelTests.fixtureData("refs-today-\(name).json"))
                as? [String: Any])
    }

    private func decodeJSON(_ json: [String: Any]) throws -> RefsTodayLinkResponse {
        try JSONDecoder().decode(
            RefsTodayLinkResponse.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func decode(_ text: String) throws -> RefsTodayLinkResponse {
        try JSONDecoder().decode(RefsTodayLinkResponse.self, from: Data(text.utf8))
    }
}
