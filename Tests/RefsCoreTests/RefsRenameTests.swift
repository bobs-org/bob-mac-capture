import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

final class RefsRenameTests: XCTestCase {
  func testSuccessEnvelopeDecodesRenameReportAndIgnoresNewFields() throws {
    let response = try JSONDecoder().decode(
      RefsRenameResponse.self,
      from: RefsModelTests.fixtureData("refs-rename.json")
    )

    XCTAssertEqual(response.schemaVersion, 1)
    XCTAssertEqual(response.ok, true)
    XCTAssertEqual(response.from?.path, "ref/blogs/442a6bf555914893e9891c11519de94f.md")
    XCTAssertEqual(response.from?.pdf, "lib/blogs/442a6bf555914893e9891c11519de94f.pdf")
    XCTAssertEqual(response.from?.stem, "442a6bf555914893e9891c11519de94f")
    XCTAssertEqual(response.to?.path, "ref/blogs/karpathy_llm_wiki.md")
    XCTAssertEqual(response.to?.pdf, "lib/blogs/karpathy_llm_wiki.pdf")
    XCTAssertEqual(response.to?.stem, "karpathy_llm_wiki")
    XCTAssertEqual(response.moves.count, 2)
    XCTAssertEqual(response.moves[0].kind, "note")
    XCTAssertEqual(response.moves[0].from, "ref/blogs/442a6bf555914893e9891c11519de94f.md")
    XCTAssertEqual(response.moves[0].to, "ref/blogs/karpathy_llm_wiki.md")
    XCTAssertEqual(response.moves[1].kind, "pdf")
    XCTAssertEqual(response.moves[1].from, "lib/blogs/442a6bf555914893e9891c11519de94f.pdf")
    XCTAssertEqual(response.moves[1].to, "lib/blogs/karpathy_llm_wiki.pdf")
    XCTAssertEqual(response.links?.rewritten, 1)
    XCTAssertEqual(response.links?.files, ["sase.md"])
    XCTAssertEqual(response.outcome, "renamed")
    XCTAssertEqual(response.changed, true)
    XCTAssertEqual(
      response.commit,
      .object([
        "sha": .string("c4b6f81a2d4e4f8a1b3c5d6e7f8090a1b2c3d4e5"),
        "subject": .string(
          "bob ref rename: 442a6bf555914893e9891c11519de94f → karpathy_llm_wiki"
        ),
      ])
    )
    XCTAssertEqual(response.sync?.pre, "ok")
    XCTAssertEqual(response.sync?.post, "ok")
    XCTAssertEqual(response.warnings, [])
    XCTAssertNil(response.error)
  }

  func testUnchangedAndAlreadyRenamedOutcomesDecode() throws {
    for outcome in ["unchanged", "already_renamed"] {
      let response = try JSONDecoder().decode(
        RefsRenameResponse.self,
        from: Data(
          """
          {"schema_version":1,"ok":true,"mode":"write","changed":false,\
          "outcome":"\(outcome)",\
          "from":{"path":"ref/blogs/old_stem.md","stem":"old_stem"},\
          "to":{"path":"ref/blogs/old_stem.md","stem":"old_stem"}}
          """.utf8)
      )
      XCTAssertEqual(response.outcome, outcome)
      XCTAssertEqual(response.changed, false)
      XCTAssertEqual(response.to?.stem, "old_stem")
      XCTAssertNil(response.error)
    }
  }

  func testMissingOptionalFieldsAndUnknownFieldsDecode() throws {
    let response = try JSONDecoder().decode(
      RefsRenameResponse.self,
      from: Data(
        #"{"schema_version":1,"future":"field","commit":{"sha":"abc","generation":3}}"#.utf8)
    )

    XCTAssertNil(response.ok)
    XCTAssertNil(response.from)
    XCTAssertEqual(response.moves, [])
    XCTAssertNil(response.links)
    XCTAssertEqual(response.warnings, [])
    XCTAssertEqual(
      response.commit,
      .object(["sha": .string("abc"), "generation": .integer(3)])
    )
  }

  func testErrorEnvelopeDecodesTypedFailure() throws {
    let response = try JSONDecoder().decode(
      RefsRenameResponse.self,
      from: RefsModelTests.fixtureData("refs-rename-error.json")
    )

    XCTAssertEqual(response.ok, false)
    XCTAssertEqual(
      response.error,
      RefsRenameFailure(
        code: "unknown_reference",
        message: "no reference note matches missing_ref_xyz",
        hint: nil
      ))
    XCTAssertEqual(RefsRenameProblemMapping.responseProblem(response), response.error)
  }

  func testProblemMappingCoversTimeoutAndTransport() {
    XCTAssertEqual(
      RefsRenameProblemMapping.transportProblem(
        for: BobClientError.timedOut(
          command: ["bob", "ref", "rename"], seconds: 180
        )
      ).code,
      "timed_out"
    )
    XCTAssertEqual(
      RefsRenameProblemMapping.transportProblem(for: TestRenameError.broken).code,
      "transport"
    )
    XCTAssertEqual(
      RefsRenameProblemMapping.transportProblem(for: TestRenameError.broken).message,
      "broken"
    )
  }

  func testCardFreezesSelectionAndEditsOnlyWhenNotRunning() {
    var card = RefsRenameCard(item: item())

    XCTAssertEqual(card.frozenItemID, "ref/blogs/old_stem.md")
    XCTAssertEqual(card.notePath, "ref/blogs/old_stem.md")
    XCTAssertEqual(card.title, "A reference title")
    XCTAssertEqual(card.draftStem, "old_stem")
    XCTAssertEqual(card.fileName, "old_stem.pdf")
    XCTAssertEqual(card.phase, .idle)

    card.editDraftStem("new_stem")
    XCTAssertEqual(card.fileName, "new_stem.pdf")
    XCTAssertEqual(card.handle(.submit), .submit(name: "new_stem"))
    XCTAssertEqual(card.phase, .running)
    card.editDraftStem("ignored")
    XCTAssertEqual(card.draftStem, "new_stem")
    XCTAssertEqual(card.handle(.cancel), .none)

    card.fail(message: "Name is taken", hint: "Choose another stem.")
    XCTAssertEqual(card.phase, .failed(message: "Name is taken", hint: "Choose another stem."))
    XCTAssertTrue(card.isFailed)
    card.editDraftStem("available")
    XCTAssertEqual(card.phase, .idle)
    XCTAssertFalse(card.isFailed)
    XCTAssertEqual(card.handle(.cancel), .cancel)
  }

  func testKeyMapSubmitsCancelsAndLeavesOrdinaryEditingToField() {
    let noModifiers: RefsCopyKeyModifiers = []
    XCTAssertEqual(
      RefsRenameKeyMap.command(
        keyCode: 36, modifiers: noModifiers, isRunning: false
      ), .submit)
    XCTAssertEqual(
      RefsRenameKeyMap.command(
        keyCode: 76, modifiers: noModifiers, isRunning: true
      ), .ignore)
    XCTAssertNil(
      RefsRenameKeyMap.command(
        keyCode: 36, modifiers: noModifiers, isRunning: false, hasMarkedText: true
      ))
    XCTAssertNil(
      RefsRenameKeyMap.command(
        keyCode: 36, modifiers: noModifiers, isRunning: true, hasMarkedText: true
      ))
    XCTAssertNil(
      RefsRenameKeyMap.command(
        keyCode: 53, modifiers: noModifiers, isRunning: false, hasMarkedText: true
      ))
    XCTAssertNil(
      RefsRenameKeyMap.command(
        keyCode: 33, modifiers: .control, isRunning: false, hasMarkedText: true
      ))
    XCTAssertEqual(
      RefsRenameKeyMap.command(
        keyCode: 53, modifiers: noModifiers, isRunning: false
      ), .cancel)
    XCTAssertEqual(
      RefsRenameKeyMap.command(
        keyCode: 33, modifiers: .control, isRunning: false
      ), .cancel)
    XCTAssertEqual(
      RefsRenameKeyMap.command(
        keyCode: 53, modifiers: noModifiers, isRunning: true
      ), .ignore)
    XCTAssertNil(
      RefsRenameKeyMap.command(
        keyCode: 0, modifiers: noModifiers, isRunning: false
      ))
    XCTAssertNil(
      RefsRenameKeyMap.command(
        keyCode: 36, modifiers: .command, isRunning: false
      ))
  }

  func testPresentationStringsAndLinkPluralization() {
    XCTAssertEqual(
      RefsRenamePresentation.caption,
      "Also renames the note and updates links. Keeps the reading task."
    )
    XCTAssertEqual(
      RefsRenamePresentation.footerStatus(stem: "karpathy_llm_wiki", rewrittenLinks: 1),
      "Renamed → karpathy_llm_wiki.pdf · 1 link updated"
    )
    XCTAssertEqual(
      RefsRenamePresentation.footerStatus(stem: "paper", rewrittenLinks: 3),
      "Renamed → paper.pdf · 3 links updated"
    )
    XCTAssertEqual(
      RefsRenamePresentation.footerStatus(stem: "paper", rewrittenLinks: 0),
      "Renamed → paper.pdf · no links updated"
    )
    XCTAssertEqual(
      RefsRenamePresentation.alreadyNamedStatus(stem: "paper"),
      "Already named paper.pdf"
    )
    XCTAssertEqual(
      RefsRenamePresentation.alreadyRenamedStatus(stem: "paper"),
      "Already renamed → paper.pdf"
    )
    XCTAssertEqual(
      RefsRenamePresentation.status(stem: "paper", rewrittenLinks: 0, outcome: "unchanged"),
      "Already named paper.pdf"
    )
    XCTAssertEqual(
      RefsRenamePresentation.status(stem: "paper", rewrittenLinks: 0, outcome: "already_renamed"),
      "Already renamed → paper.pdf"
    )
    XCTAssertEqual(
      RefsRenamePresentation.status(stem: "paper", rewrittenLinks: 2, outcome: "renamed"),
      "Renamed → paper.pdf · 2 links updated"
    )
    XCTAssertEqual(
      RefsRenamePresentation.status(stem: "paper", rewrittenLinks: 2, outcome: nil),
      "Renamed → paper.pdf · 2 links updated"
    )
    XCTAssertEqual(
      RefsRenamePresentation.announcement(stem: "paper"),
      "Reference renamed to paper.pdf"
    )
    let notification = RefsRenamePresentation.notification(stem: "paper")
    XCTAssertEqual(notification.title, "Reference renamed")
    XCTAssertEqual(notification.body, "paper.pdf")
    let failure = RefsRenamePresentation.failureNotification(message: "Name is taken")
    XCTAssertEqual(failure.title, "Reference rename failed")
    XCTAssertEqual(failure.body, "Name is taken")
  }

  private func item() -> RefItem {
    RefItem(
      id: "ref/blogs/old_stem.md",
      link: "[[ref/blogs/old_stem]]",
      rawTitle: "A reference title",
      stem: "old_stem",
      kind: .article,
      state: .ready,
      isBlocked: false,
      pdfPath: "lib/blogs/old_stem.pdf"
    )
  }
}

private enum TestRenameError: Error {
  case broken
}
