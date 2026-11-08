import CaptureCore
import XCTest

final class CaptureTypeAheadHoldTests: XCTestCase {
    func testBuffersInOrderAndOnlyFinishesMatchingGeneration() throws {
        var hold = CaptureTypeAheadHold<String>(deadline: 0.2, capacity: 32)
        XCTAssertTrue(hold.begin(generation: 7, at: 10))
        XCTAssertFalse(hold.begin(generation: 8, at: 10.01))

        assertBuffered(hold.append("1", at: 10.02))
        assertBuffered(hold.append("+", at: 10.04))
        XCTAssertNil(hold.finish(generation: 8, at: 10.05))

        let snapshot = try XCTUnwrap(hold.finish(generation: 7, at: 10.08))
        XCTAssertEqual(snapshot.generation, 7)
        XCTAssertEqual(snapshot.keys, ["1", "+"])
        XCTAssertEqual(snapshot.duration, 0.08, accuracy: 0.000_001)
        XCTAssertFalse(hold.isActive)
    }

    func testDeadlineIncludesTheKeyThatArrivesAtTheBoundary() throws {
        var hold = CaptureTypeAheadHold<String>(deadline: 0.15, capacity: 32)
        XCTAssertTrue(hold.begin(generation: 3, at: 1))
        assertBuffered(hold.append("2", at: 1.149))

        guard case .expired(let snapshot) = hold.append("\r", at: 1.15) else {
            return XCTFail("The boundary key should end the expired hold")
        }
        XCTAssertEqual(snapshot.keys, ["2", "\r"])
        XCTAssertEqual(snapshot.duration, 0.15, accuracy: 0.000_001)
        XCTAssertFalse(hold.isActive)
    }

    func testTimerExpiryReturnsBufferedKeysAndEmptyHoldsCanEnd() throws {
        var hold = CaptureTypeAheadHold<String>(deadline: 0.2, capacity: 32)
        XCTAssertTrue(hold.begin(generation: 4, at: 5))
        assertBuffered(hold.append("x", at: 5.02))

        let expired = try XCTUnwrap(hold.expire(generation: 4, at: 5.2))
        XCTAssertEqual(expired.keys, ["x"])
        XCTAssertNil(hold.expire(generation: 4, at: 5.21))

        XCTAssertTrue(hold.begin(generation: 5, at: 6))
        let empty = try XCTUnwrap(hold.end(at: 6.01))
        XCTAssertTrue(empty.keys.isEmpty)
        XCTAssertEqual(empty.generation, 5)
    }

    func testKeyBeyondCapacityEndsHoldWithTheWholeOrderedQueue() throws {
        var hold = CaptureTypeAheadHold<String>(deadline: 1, capacity: 2)
        XCTAssertTrue(hold.begin(generation: 2, at: 0))
        assertBuffered(hold.append("a", at: 0.1))
        assertBuffered(hold.append("b", at: 0.2))

        guard case .overflow(let snapshot) = hold.append("c", at: 0.3) else {
            return XCTFail("The key beyond capacity should flush the hold")
        }
        XCTAssertEqual(snapshot.keys, ["a", "b", "c"])
        XCTAssertEqual(snapshot.duration, 0.3, accuracy: 0.000_001)
        XCTAssertFalse(hold.isActive)
    }

    private func assertBuffered(
        _ result: CaptureTypeAheadHold<String>.AppendResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .buffered = result else {
            XCTFail("Expected key to stay buffered", file: file, line: line)
            return
        }
    }
}
