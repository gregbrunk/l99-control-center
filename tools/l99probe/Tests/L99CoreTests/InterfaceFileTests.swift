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

    func testNumpadButtonsParse() throws {
        let f = try load()
        let b = try f.touchButtons(page: 21)
        XCTAssertEqual(b.count, 18)
        XCTAssertEqual(Set(b.map(\.code)).intersection(48...64).count, 17)
        let one = b.first { $0.code == 59 }!
        XCTAssertEqual([one.x1, one.y1, one.x2, one.y2, one.up, one.down], [13, 337, 79, 403, 341, 342])
    }

    func testMoveAndPlaceChangeOnlyPlannedBytes() throws {
        var f = try load()
        try f.moveButton(page: 21, code: 59, x: 3, y: 328, width: 74, height: 70)
        try f.placeIcon(341, width: 74, height: 70, pixels: [UInt16](repeating: 0xF123, count: 74 * 70))
        let one = try f.touchButtons(page: 21).first { $0.code == 59 }!
        XCTAssertEqual([one.x1, one.y1, one.x2, one.y2, one.code, one.up], [3, 328, 76, 397, 59, 341])
        for bank in 0...1 {
            XCTAssertEqual(try f.icon(341, bank: bank), InterfaceFile.Icon(id: 341, address: 0x00A3_55EC, width: 74, height: 70, size: 10360, format: 2))
        }
        XCTAssertEqual(f.projectEnd, 0x00A3_55EC + 10360)
        XCTAssertEqual(try f.pixels(341).first, 0xF123)
        XCTAssertNoThrow(try f.validate())
        // A second placement goes after the first.
        try f.placeIcon(342, width: 2, height: 2, pixels: [1, 2, 3, 4])
        XCTAssertEqual(try f.icon(342).address, 0x00A3_55EC + 10360)
    }

    func testRefusesOffscreenAndUnknownButtons() throws {
        var f = try load()
        XCTAssertThrowsError(try f.moveButton(page: 21, code: 59, x: 300, y: 0, width: 74, height: 70))
        XCTAssertThrowsError(try f.moveButton(page: 21, code: 999, x: 0, y: 0, width: 10, height: 10))
        XCTAssertThrowsError(try f.placeIcon(341, width: 10, height: 10, pixels: [1]))
        XCTAssertTrue(f.changedRanges().isEmpty)
    }

    func testRefusesNonStockFile() {
        XCTAssertThrowsError(try InterfaceFile(stockBytes: [1, 2, 3]))
    }

    func testTopBarRecordsParse() throws {
        let f = try load()
        let bat = try f.indicators(page: 22).first { $0.id == 8 }!
        XCTAssertEqual([bat.x, bat.y, bat.first, bat.last], [277, 11, 14, 20])
        let pct = try f.indicators(page: 22).first { $0.id == 7 && $0.x == 256 }!
        XCTAssertEqual([pct.first, pct.last], [21, 21])
        let d = try f.digitWidgets(page: 22).first { $0.variable == 6 }!
        XCTAssertEqual([d.x, d.y, d.first, d.last], [253, 12, 30, 39])
        XCTAssertTrue(try f.emptySlots().contains(450))
    }

    func testIndicatorRetargetTouchesOnlyThatPage() throws {
        var f = try load()
        XCTAssertThrowsError(try f.setIndicator(page: 22, using: 14, x: 283, y: 10, first: 450))   // no art yet
        for id in 450...456 { try f.placeIcon(id, width: 26, height: 14, pixels: [UInt16](repeating: 0xFFFF, count: 26 * 14)) }
        try f.setIndicator(page: 22, using: 14, x: 283, y: 10, first: 450)
        let bat = try f.indicators(page: 22).first { $0.id == 8 }!
        XCTAssertEqual([bat.x, bat.y, bat.first, bat.last], [283, 10, 450, 456])
        let home = try f.indicators(page: 1).first { $0.id == 8 }!
        XCTAssertEqual([home.x, home.first, home.last], [277, 14, 20])
        for id in 481...490 { try f.placeIcon(id, width: 8, height: 14, pixels: [UInt16](repeating: 0xFFFF, count: 8 * 14)) }
        try f.setDigits(page: 22, variable: 6, x: 268, y: 11, first: 481)
        let d = try f.digitWidgets(page: 22).first { $0.variable == 6 }!
        XCTAssertEqual([d.x, d.y, d.first, d.last], [268, 11, 481, 490])
        XCTAssertEqual(try f.digitWidgets(page: 1).first { $0.variable == 6 }!.first, 30)
        XCTAssertNoThrow(try f.validate())
    }

    func testClockParsesAndRetargets() throws {
        var f = try load()
        let c = try f.clocks(page: 22).first!
        XCTAssertEqual([c.x, c.y, c.first, c.last, c.glyphs], [12, 10, 30, 43, 5])
        XCTAssertThrowsError(try f.setClock(page: 22, x: 12, y: 9, first: 481))   // no art yet
        for id in 481...494 { try f.placeIcon(id, width: 8, height: 14, pixels: [UInt16](repeating: 0xFFFF, count: 8 * 14)) }
        try f.setClock(page: 22, x: 12, y: 9, first: 481)
        let n = try f.clocks(page: 22).first!
        XCTAssertEqual([n.x, n.y, n.first, n.last, n.glyphs], [12, 9, 481, 494, 5])
        XCTAssertEqual(try f.clocks(page: 1).first!.first, 30)
        XCTAssertNoThrow(try f.validate())
    }
}
