import XCTest
@testable import L99Core

final class InterfaceBlockTests: XCTestCase {
    private var factory: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("research/factory/UartTFT-II_Flash.bin").path
    }

    func testPlanStaysInsideBlock3B() {
        let plan = InterfaceBlockTest.plan()
        XCTAssertEqual(plan.count, 65)
        var written = 0
        for step in plan {
            switch step {
            case .write(let a, let r):
                XCTAssertEqual(r.count, 2048); XCTAssertEqual(a, 0x0076_0000 + UInt32(r.lowerBound)); written += r.count
            case .check(let a, let r):
                XCTAssertEqual(a, 0x0076_0000); XCTAssertEqual(r, 0..<0x20000)
            }
        }
        XCTAssertEqual(written, 0x20000)
        if case .check = plan.last! {} else { XCTFail("must end with the check") }
    }

    func testIconRangeIsInsideBlock() {
        XCTAssertEqual(InterfaceBlockTest.iconRange, 0x1C446..<(0x1C446 + 8978))
        XCTAssertLessThanOrEqual(InterfaceBlockTest.iconRange.upperBound, 0x20000)
    }

    func testValidateRefusesChangesOutsideTheIcon() {
        let stock = [UInt8](repeating: 0x5A, count: 0x20000)
        var bad = stock; bad[0x100] ^= 1
        XCTAssertThrowsError(try InterfaceBlockTest.validate(bad, stock: stock))
        var lastByte = stock; lastByte[InterfaceBlockTest.iconRange.upperBound] ^= 1
        XCTAssertThrowsError(try InterfaceBlockTest.validate(lastByte, stock: stock))
        XCTAssertThrowsError(try InterfaceBlockTest.validate(Array(stock.dropLast()), stock: stock))
        var ok = stock; ok[InterfaceBlockTest.iconRange.lowerBound] ^= 1; ok[InterfaceBlockTest.iconRange.upperBound - 1] ^= 1
        XCTAssertNoThrow(try InterfaceBlockTest.validate(ok, stock: stock))
    }

    func testRealFileVariants() throws {
        guard FileManager.default.fileExists(atPath: factory) else { throw XCTSkip("factory file not present") }
        let stock = try InterfaceBlockTest.stockBlock(flashFile: factory)
        XCTAssertEqual(try InterfaceBlockTest.block(.stock, stock: stock), stock)
        let blue = try InterfaceBlockTest.block(.blue, stock: stock)
        XCTAssertNotEqual(blue, stock)
        XCTAssertNotEqual(Checksum.crc32Screen(blue), Checksum.crc32Screen(stock))
        for i in 0..<stock.count where blue[i] != stock[i] { XCTAssertTrue(InterfaceBlockTest.iconRange.contains(i)) }
        // Alpha nibbles are untouched, so the key keeps its shape.
        for i in stride(from: InterfaceBlockTest.iconRange.lowerBound + 1, to: InterfaceBlockTest.iconRange.upperBound, by: 2) {
            XCTAssertEqual(blue[i] >> 4, stock[i] >> 4)
        }
    }

    func testWrongFileIsRefused() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("not-stock.bin")
        try Data(repeating: 0, count: 1024).write(to: tmp)
        XCTAssertThrowsError(try InterfaceBlockTest.stockBlock(flashFile: tmp.path))
    }
}
