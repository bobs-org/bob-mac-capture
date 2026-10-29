import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

/// Task-theme suggestion rendering for the Refs Link to Today card
/// (phase mac-capture). Bob owns the suggestion; the card only preselects
/// and renders it.
final class RefsTodayLinkSuggestionTests: XCTestCase {
    func testListingDecodesSuggestionAndSuggestedRow() throws {
        let response = try JSONDecoder().decode(
            RefsTodayLinkResponse.self, from: Data(listingJSON(create: false).utf8))

        let suggestion = try XCTUnwrap(response.themeSuggestion)
        XCTAssertEqual(suggestion.theme.name, "WRITE")
        XCTAssertEqual(suggestion.label, "from sase_blog")
        XCTAssertFalse(suggestion.create)
        let suggested = response.pomodoros.filter(\.suggested)
        XCTAssertEqual(suggested.count, 1)
        XCTAssertEqual(suggested.first?.name, "WRITE")
        XCTAssertEqual(suggested.first?.suggestionLabel, "from sase_blog")
    }

    func testListingOmitsSuggestionForOlderBob() throws {
        let response = try JSONDecoder().decode(
            RefsTodayLinkResponse.self,
            from: Data(
                """
                {"schema_version":1,"ok":true,"mode":"link","changed":false,
                 "pomodoros":[{"ref":"1:abc","name":"WRITE","placeholder":false,
                  "running":false,"default":true,"linked":false,"task_link_count":0}]}
                """.utf8
            )
        )

        XCTAssertNil(response.themeSuggestion)
        XCTAssertTrue(response.pomodoros.allSatisfy { !$0.suggested })
    }

    func testCardPreselectsSuggestedRowAndSendsItsEntry() throws {
        let response = try JSONDecoder().decode(
            RefsTodayLinkResponse.self, from: Data(listingJSON(create: false).utf8))

        var card = makeCard()
        let effect = card.applyListing(response)

        // The suggested entry is not `.automatic`, so the card requests its preview.
        XCTAssertEqual(effect, .preview(.entry(ref: "2:def")))
        XCTAssertEqual(card.selectedPomodoro?.name, "WRITE")
        // The suggested row is not Bob's default; Return sends its entry
        // instead of falling into the `.automatic` trap.
        XCTAssertEqual(card.selector, .entry(ref: "2:def"))
        XCTAssertTrue(
            RefsTodayLinkPresentation.rowMeta(
                card.selectedPomodoro!, now: Date(timeIntervalSince1970: 0)
            ).contains("Suggested · from sase_blog"))
    }

    func testSuggestedRowThatIsDefaultKeepsAutomatic() throws {
        var response = try JSONDecoder().decode(
            RefsTodayLinkResponse.self, from: Data(listingJSON(create: false).utf8))
        // Mark the suggested row as Bob's default: Return stays automatic.
        let rows = response.pomodoros.map { row -> RefsTodayLinkPomodoro in
            if row.suggested {
                return RefsTodayLinkPomodoro(
                    ref: row.ref, line: row.line, name: row.name, slug: row.slug,
                    timeRange: row.timeRange, placeholder: row.placeholder,
                    startsAt: row.startsAt, endsAt: row.endsAt, running: row.running,
                    isDefault: true, linked: row.linked,
                    taskLinkCount: row.taskLinkCount, homes: row.homes,
                    themes: row.themes, suggested: true,
                    suggestionLabel: row.suggestionLabel)
            }
            return row
        }
        response = RefsTodayLinkResponse(
            schemaVersion: 1, ok: true, mode: "link", changed: false,
            pomodoros: rows, themeSuggestion: response.themeSuggestion)

        var card = makeCard()
        _ = card.applyListing(response)
        XCTAssertEqual(card.selector, .automatic)
    }

    func testCreatePreselectsSyntheticRowFirst() throws {
        let response = try JSONDecoder().decode(
            RefsTodayLinkResponse.self, from: Data(listingJSON(create: true).utf8))

        var card = makeCard()
        _ = card.applyListing(response)

        XCTAssertTrue(card.showsSuggestedCreate)
        XCTAssertEqual(card.suggestedCreateName, "READ")
        XCTAssertTrue(card.selectedSuggestedCreate)
        XCTAssertEqual(card.selector, .exactName("READ"))
        XCTAssertEqual(
            RefsTodayLinkPresentation.suggestedCreateTitle(name: "READ"),
            "New READ Pomodoro")
    }

    func testMovingOffSuggestedCreateLandsOnRows() throws {
        let response = try JSONDecoder().decode(
            RefsTodayLinkResponse.self, from: Data(listingJSON(create: true).utf8))

        var card = makeCard()
        _ = card.applyListing(response)
        _ = card.handle(.move(1))

        XCTAssertFalse(card.selectedSuggestedCreate)
        XCTAssertNotNil(card.selectedPomodoro)
        XCTAssertEqual(card.selector, .entry(ref: card.selectedPomodoro!.ref))
    }

    // MARK: - Helpers

    private func listingJSON(create: Bool) -> String {
        let suggestion = create
            ? """
              ,"theme_suggestion":{"theme":{"key":"read","name":"READ"},
               "source":"reading","label":"reading task","create":true}
              """
            : """
              ,"theme_suggestion":{"theme":{"key":"write","name":"WRITE"},
               "source":"note","label":"from sase_blog",
               "from":{"path":"sase_blog.md","stem":"sase_blog","kind":"project",
                       "hue":"blue","chain":["sase_blog.md"]}}
              """
        let rows = create
            ? """
              [{"ref":"1:abc","name":"WRITE","placeholder":false,
                "running":false,"default":true,"linked":false,"task_link_count":1}]
              """
            : """
              [{"ref":"1:abc","name":"WRITE","placeholder":false,
                "running":false,"default":true,"linked":false,"task_link_count":1},
               {"ref":"2:def","name":"WRITE","placeholder":false,
                "running":false,"default":false,"linked":false,"task_link_count":0,
                "suggested":true,"suggestion_label":"from sase_blog"}]
              """
        return """
        {"schema_version":1,"ok":true,"mode":"link","changed":false,
         "pomodoros":\(rows)\(suggestion)}
        """
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
}
