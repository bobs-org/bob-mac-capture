import Foundation
import XCTest

@testable import CaptureCore

/// File-under picker rules for a bare-URL reference draft (`mode == "ref"`):
/// when the list opens on its own, how cached targets order (last-used
/// parent first, then `mac_inbox`), how typing filters with aliases
/// included, and what accepting splices into the draft.
final class CaptureRefFileUnderTests: XCTestCase {
    private func target(
        _ route: String,
        kind: String = "project",
        aliases: [String] = []
    ) -> CaptureTarget {
        CaptureTarget(
            route: route,
            name: route,
            label: "\(route).md",
            kind: kind,
            relativePath: "\(route).md",
            projectNameAliases: aliases
        )
    }

    private var targets: [CaptureTarget] {
        [
            target("mac_inbox", kind: "inbox"),
            target("bob", aliases: ["bob-cli"]),
            target("sase"),
        ]
    }

    // MARK: - Auto-open

    func testAutoOpensForABareURLThatWillQueueUnderTheDefault() {
        XCTAssertTrue(CaptureRefFileUnder.shouldAutoOpen(
            parseMode: "ref",
            refParentSource: "default",
            itemCount: 1,
            verdict: "not_found",
            urlChangedSinceDismissal: true
        ))
    }

    func testAutoOpensForLegacyAndUnknownVerdicts() {
        for verdict in ["legacy", "unknown"] {
            XCTAssertTrue(CaptureRefFileUnder.shouldAutoOpen(
                parseMode: "ref",
                refParentSource: "default",
                itemCount: 1,
                verdict: verdict,
                urlChangedSinceDismissal: true
            ), "verdict \(verdict)")
        }
    }

    func testNeverOpensForLibraryHits() {
        for verdict in ["in_library", "in_intake", "clipping", "duplicate"] {
            XCTAssertFalse(CaptureRefFileUnder.shouldAutoOpen(
                parseMode: "ref",
                refParentSource: "default",
                itemCount: 1,
                verdict: verdict,
                urlChangedSinceDismissal: true
            ), "verdict \(verdict)")
        }
    }

    func testNeverOpensWithoutADefaultParent() {
        for source: String? in ["explicit", "global", nil] {
            XCTAssertFalse(CaptureRefFileUnder.shouldAutoOpen(
                parseMode: "ref",
                refParentSource: source,
                itemCount: 1,
                verdict: "not_found",
                urlChangedSinceDismissal: true
            ), "source \(source ?? "nil")")
        }
    }

    func testNeverOpensForNonRefModesBatchesOrADismissedURL() {
        XCTAssertFalse(CaptureRefFileUnder.shouldAutoOpen(
            parseMode: "task",
            refParentSource: "default",
            itemCount: 1,
            verdict: "not_found",
            urlChangedSinceDismissal: true
        ))
        XCTAssertFalse(CaptureRefFileUnder.shouldAutoOpen(
            parseMode: "ref",
            refParentSource: "default",
            itemCount: 2,
            verdict: "not_found",
            urlChangedSinceDismissal: true
        ))
        XCTAssertFalse(CaptureRefFileUnder.shouldAutoOpen(
            parseMode: "ref",
            refParentSource: "default",
            itemCount: 1,
            verdict: nil,
            urlChangedSinceDismissal: true
        ))
        XCTAssertFalse(CaptureRefFileUnder.shouldAutoOpen(
            parseMode: "ref",
            refParentSource: "default",
            itemCount: 1,
            verdict: "not_found",
            urlChangedSinceDismissal: false
        ))
    }

    // MARK: - Ordering

    func testLastUsedParentComesFirstThenMacInbox() {
        let ordered = CaptureRefFileUnder.orderedTargets(targets, lastUsedParent: "sase")

        XCTAssertEqual(ordered.map(\.route), ["sase", "mac_inbox", "bob"])
    }

    func testMacInboxLeadsWithoutALastUsedParent() {
        let ordered = CaptureRefFileUnder.orderedTargets(targets, lastUsedParent: nil)

        XCTAssertEqual(ordered.map(\.route), ["mac_inbox", "bob", "sase"])
    }

    func testUnknownLastUsedParentFallsBackToMacInbox() {
        let ordered = CaptureRefFileUnder.orderedTargets(targets, lastUsedParent: "gone")

        XCTAssertEqual(ordered.map(\.route), ["mac_inbox", "bob", "sase"])
    }

    // MARK: - Filtering with aliases

    func testEmptyQueryKeepsInputOrder() {
        let ranked = CaptureRefFileUnder.rankedTargets(targets, query: "")

        XCTAssertEqual(ranked.map(\.route), ["mac_inbox", "bob", "sase"])
    }

    func testRankedTargetsPreservesInputOrderInsideBuckets() {
        let clippy = target("clippy")
        let ranked = CaptureRefFileUnder.rankedTargets(
            [clippy] + targets,
            query: "c"
        )

        // `clippy` leads by canonical route prefix; `mac_inbox` (route
        // containment) and `bob` (alias containment) follow in input order.
        XCTAssertEqual(ranked.map(\.route), ["clippy", "mac_inbox", "bob"])
    }

    func testAliasMatchesRankAfterPrefixRouteMatches() {
        let clippy = target("clippy")
        let ranked = CaptureRefFileUnder.rankedTargets(
            targets + [clippy],
            query: "cli"
        )

        // `clippy` matches by canonical route prefix; `bob` only by alias
        // containment, so the canonical match ranks first.
        XCTAssertEqual(ranked.map(\.route), ["clippy", "bob"])
        XCTAssertTrue(CaptureRefFileUnder.matches(target: targets[1], query: "bob-cli"))
        XCTAssertFalse(CaptureRefFileUnder.matches(target: targets[2], query: "bob-cli"))
    }

    func testAliasQueryFindsTheCanonicalTarget() {
        let ranked = CaptureRefFileUnder.rankedTargets(targets, query: "bob-cli")

        XCTAssertEqual(ranked.map(\.route), ["bob"])
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertTrue(CaptureRefFileUnder.matches(target: targets[1], query: "BOB-CLI"))
        XCTAssertTrue(CaptureRefFileUnder.matches(target: targets[2], query: "SASE"))
    }

    func testAliasOwnerResolvesAnExactAlias() {
        XCTAssertEqual(
            CaptureRefFileUnder.aliasOwner(targets, query: "bob-cli")?.route,
            "bob"
        )
        XCTAssertNil(CaptureRefFileUnder.aliasOwner(targets, query: "bob"))
        XCTAssertNil(CaptureRefFileUnder.aliasOwner(targets, query: ""))
        XCTAssertNil(CaptureRefFileUnder.aliasOwner(targets, query: "nope"))
    }

    // MARK: - Insertion and display

    func testInsertionAppendsTheCanonicalRoute() {
        XCTAssertEqual(CaptureRefFileUnder.insertionText(route: "sase"), " @sase")
        XCTAssertEqual(CaptureRefFileUnder.insertionText(route: "bob"), " @bob")
    }

    func testDisplayNameShowsTheAlias() {
        XCTAssertEqual(
            CaptureRefFileUnder.displayName(for: targets[1]),
            "bob · aka bob-cli"
        )
        XCTAssertEqual(CaptureRefFileUnder.displayName(for: targets[2]), "sase")
    }

    // MARK: - Decoding

    func testTargetsWithoutAliasesDecodeAsEmpty() throws {
        let response = try JSONDecoder().decode(
            CaptureTargetsResponse.self,
            from: Data(
                """
                {"ok":true,"schema_version":1,"bob_dir":"/tmp/bob","count":1,"targets":[{"route":"today","name":"today","label":"today.md","kind":"inbox","is_default":true,"status":null,"relative_path":"today.md"}]}
                """.utf8
            )
        )

        XCTAssertEqual(response.targets.map(\.projectNameAliases), [[]])
    }

    func testTargetsWithAliasesDecode() throws {
        let response = try JSONDecoder().decode(
            CaptureTargetsResponse.self,
            from: Data(
                """
                {"ok":true,"schema_version":1,"bob_dir":"/tmp/bob","count":1,"targets":[{"route":"bob","name":"bob","label":"bob.md","kind":"project","is_default":false,"status":"wip","relative_path":"bob.md","project_name_aliases":["bob-cli"]}]}
                """.utf8
            )
        )

        XCTAssertEqual(response.targets.map(\.projectNameAliases), [["bob-cli"]])
    }

    func testMistypedRefParentDegradesToNil() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": true,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "",
              "target": "",
              "text": "https://example.com/post",
              "task_line": "",
              "kind": "ref",
              "created": "2026-10-07",
              "scheduled": null,
              "placement": "queued",
              "ref": {
                "url": "https://example.com/post",
                "cleaned_url": "https://example.com/post",
                "dedupe_key": "https://example.com/post",
                "display": "example.com/post",
                "route_hint": "article",
                "library": {"verdict": "not_found"},
                "parent": {"route": 42}
              }
            }
            """
        )

        XCTAssertNil(success.ref?.parent)
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))
        XCTAssertEqual(presentation.parentRoute, "")
        XCTAssertNil(presentation.queueSummary)
        XCTAssertEqual(presentation.statusText, "Would queue for clipping → reading queue")
    }

    private enum CaptureFixtureError: Error {
        case expectedSuccess
    }

    private func decodeCaptureSuccess(_ json: String) throws -> CaptureCommandSuccess {
        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: Data(json.utf8))
        guard case .success(let success) = decoded else {
            throw CaptureFixtureError.expectedSuccess
        }
        return success
    }
}
