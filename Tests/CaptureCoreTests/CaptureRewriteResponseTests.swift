import Foundation
import XCTest

@testable import CaptureCore

final class CaptureRewriteResponseTests: XCTestCase {
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
