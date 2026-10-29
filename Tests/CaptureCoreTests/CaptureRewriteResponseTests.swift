import Foundation
import XCTest

@testable import CaptureCore

final class CaptureRewriteResponseTests: XCTestCase {
    func testCoveringEditLeavesSingleEditUnchanged() {
        let edit = CaptureRewriteEdit(
            range: CaptureRange(start: 0, end: 3),
            replacement: "@@template:\n"
        )
        let response = response(
            input: "@@@",
            text: "@@template:\n",
            edits: [edit]
        )

        XCTAssertEqual(response.coveringEdit(in: "@@@"), edit)
    }

    func testCoveringEditCombinesHeaderInsertionAndTriggerErasure() {
        let response = response(
            input: "Read {0} @@@",
            text: "@@template:\nRead {0}",
            edits: [
                CaptureRewriteEdit(
                    range: CaptureRange(start: 0, end: 0),
                    replacement: "@@template:\n"
                ),
                CaptureRewriteEdit(
                    range: CaptureRange(start: 8, end: 12),
                    replacement: ""
                ),
            ]
        )

        XCTAssertEqual(
            response.coveringEdit(in: response.input),
            CaptureRewriteEdit(
                range: CaptureRange(start: 0, end: 12),
                replacement: "@@template:\nRead {0}"
            )
        )
    }

    func testCoveringEditPreservesMultibyteTextBeforeTheErasure() {
        let response = response(
            input: "🧪 Read {0} @@@",
            text: "@@template:\n🧪 Read {0}",
            edits: [
                CaptureRewriteEdit(
                    range: CaptureRange(start: 0, end: 0),
                    replacement: "@@template:\n"
                ),
                CaptureRewriteEdit(
                    range: CaptureRange(start: 13, end: 17),
                    replacement: ""
                ),
            ]
        )

        XCTAssertEqual(
            response.coveringEdit(in: response.input),
            CaptureRewriteEdit(
                range: CaptureRange(start: 0, end: 17),
                replacement: "@@template:\n🧪 Read {0}"
            )
        )
    }

    func testCoveringEditRejectsInvalidEditLists() {
        let unsorted = response(
            input: "abcdef",
            text: "abXdYf",
            edits: [edit(4, 5, "Y"), edit(2, 3, "X")]
        )
        let overlapping = response(
            input: "abcdef",
            text: "aXf",
            edits: [edit(1, 4, "X"), edit(3, 5, "")]
        )
        let outOfRange = response(
            input: "abc",
            text: "abc",
            edits: [edit(0, 4, "")]
        )
        let nonBoundary = response(
            input: "🧪",
            text: "x",
            edits: [edit(1, 4, "x")]
        )
        let nonReproducing = response(
            input: "abc",
            text: "different",
            edits: [edit(0, 1, "x")]
        )

        for value in [unsorted, overlapping, outOfRange, nonBoundary, nonReproducing] {
            XCTAssertNil(value.coveringEdit(in: value.input))
        }
    }

    private func response(
        input: String,
        text: String,
        edits: [CaptureRewriteEdit]
    ) -> CaptureRewriteResponse {
        CaptureRewriteResponse(
            ok: true,
            schemaVersion: 1,
            input: input,
            text: text,
            changed: true,
            edits: edits
        )
    }

    private func edit(_ start: Int, _ end: Int, _ replacement: String) -> CaptureRewriteEdit {
        CaptureRewriteEdit(
            range: CaptureRange(start: start, end: end),
            replacement: replacement
        )
    }
}
