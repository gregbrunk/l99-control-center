import XCTest
@testable import L99Core

final class InterfaceFileTests: XCTestCase {
    let factory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("research/factory/UartTFT-II_Flash.bin").path

    func load() throws -> InterfaceFile {
        guard FileManager.default.fileExists(atPath: factory) else { throw XCTSkip("factory file missing") }
        return try InterfaceFile(stockFile: factory)
    }

    func testReadsIcon341Descriptor() throws {
        let f = try load()
        XCTAssertEqual(f.iconCount, 569)
        for bank in 0...1 {
            XCTAssertEqual(try f.icon(341, bank: bank),
                           InterfaceFile.Icon(id: 341, address: 0x0077_C446, width: 67, height: 67, size: 8978, format: 2))
        }
    }

    func testReplaceChangesOnlyTheIcon() throws {
        var f = try load()
        try f.replaceIcon(341, pixels: try f.pixels(341).map(Art4444.tintBlue))
        let ranges = f.changedRanges()
        XCTAssertFalse(ranges.isEmpty)
        let icon = try f.icon(341).byteRange
        XCTAssertTrue(ranges.allSatisfy { icon.contains($0.lowerBound) && icon.contains($0.upperBound - 1) })
        XCTAssertNoThrow(try f.validate())
        XCTAssertEqual(f.bytes.count, f.stock.count)
    }

    func testRefusesWrongSizeAndBadIDs() throws {
        var f = try load()
        XCTAssertThrowsError(try f.replaceIcon(341, pixels: [0, 1, 2]))
        XCTAssertThrowsError(try f.replaceIcon(9999, pixels: []))
        XCTAssertTrue(f.changedRanges().isEmpty)
    }

    func testRefusesNonStockFile() {
        XCTAssertThrowsError(try InterfaceFile(stockBytes: [1, 2, 3]))
    }
}
