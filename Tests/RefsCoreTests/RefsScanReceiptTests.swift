import Foundation
import XCTest

@testable import RefsCore

final class RefsScanReceiptTests: XCTestCase {
  func testReceiptPathUsesXDGStateHomeOrHomeFallback() {
    XCTAssertEqual(
      RefsScanReceiptReader.receiptURL(
        environment: ["XDG_STATE_HOME": "/tmp/bob-state", "HOME": "/Users/bob"],
        homeDirectoryURL: URL(fileURLWithPath: "/fallback")
      ).path,
      "/tmp/bob-state/bob-cli/ref/last-scan.json"
    )
    XCTAssertEqual(
      RefsScanReceiptReader.receiptURL(
        environment: ["XDG_STATE_HOME": "", "HOME": "/Users/bob"]
      ).path,
      "/Users/bob/.local/state/bob-cli/ref/last-scan.json"
    )
    XCTAssertEqual(
      RefsScanReceiptReader.receiptURL(
        environment: [:],
        homeDirectoryURL: URL(fileURLWithPath: "/fallback")
      ).path,
      "/fallback/.local/state/bob-cli/ref/last-scan.json"
    )
  }

  func testReadDecodesSchemaOneAndHashesExactReceiptBytes() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let receiptURL = directory.appendingPathComponent("last-scan.json")
    let bytes = Data(#"{"schema_version":1,"generated_at":"2026-10-23T10:15:00Z"}"#.utf8)
    try bytes.write(to: receiptURL)

    let reader = RefsScanReceiptReader()
    let receipt = try XCTUnwrap(reader.read(at: receiptURL))
    let again = try XCTUnwrap(reader.read(at: receiptURL))

    XCTAssertEqual(receipt.response.schemaVersion, 1)
    XCTAssertEqual(receipt.response.generatedAt, "2026-10-23T10:15:00Z")
    XCTAssertEqual(receipt.contentHash, again.contentHash)
  }

  func testUnsupportedSchemaIsIgnored() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let receiptURL = directory.appendingPathComponent("last-scan.json")
    try Data(#"{"schema_version":2}"#.utf8).write(to: receiptURL)

    XCTAssertNil(try RefsScanReceiptReader().read(at: receiptURL))
  }

  func testReadRejectsAReceiptOverTheFourMegabyteLimit() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let receiptURL = directory.appendingPathComponent("last-scan.json")
    let tooLarge = Data(repeating: 0x20, count: RefsScanReceiptReader.maximumBytes + 1)
    try tooLarge.write(to: receiptURL)

    XCTAssertThrowsError(try RefsScanReceiptReader().read(at: receiptURL)) { error in
      XCTAssertEqual(
        error as? RefsScanReceiptError,
        .tooLarge(maximumBytes: RefsScanReceiptReader.maximumBytes)
      )
    }
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("RefsScanReceiptTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
