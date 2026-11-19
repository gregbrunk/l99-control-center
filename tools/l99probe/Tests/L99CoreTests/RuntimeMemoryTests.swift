import XCTest
@testable import L99Core

final class RuntimeMemoryTests: XCTestCase {
    func testReadFrameMatchesSoftceLayout() throws {
        // 5A A5 07 | 03 0638 0002 | CRC16 LE — softce's signature read.
        let f = try RuntimeMemory.readFrame(address: 0x0638, count: 2)
        XCTAssertEqual(Array(f.prefix(8)), [0x5A, 0xA5, 0x07, 0x03, 0x06, 0x38, 0x00, 0x02])
        let crc = Checksum.crc16Modbus(Array(f[3..<8]))
        XCTAssertEqual(Array(f.suffix(2)), [UInt8(crc & 0xFF), UInt8(crc >> 8)])
    }

    func testSampleProjectCRCFormulaAgrees() {
        // UI_Editor-II sample: "Switch Page" 5AA5 07 10 7000 0000 CRC FF03 — same CRC16, sent LE.
        XCTAssertEqual(Checksum.crc16Modbus([0x10, 0x70, 0x00, 0x00, 0x00]), 0x03FF)
    }

    func testRefusesReadsOutsideTheRanges() {
        XCTAssertThrowsError(try RuntimeMemory.readFrame(address: 0x1000, count: 1))
        XCTAssertThrowsError(try RuntimeMemory.readFrame(address: 0x0FF8, count: 16))   // runs past 0x0FFF
        XCTAssertThrowsError(try RuntimeMemory.readFrame(address: 0x7040, count: 1))
        XCTAssertThrowsError(try RuntimeMemory.readFrame(address: 0x0000, count: 0))
        XCTAssertThrowsError(try RuntimeMemory.readFrame(address: 0x0000, count: 17))
        XCTAssertNoThrow(try RuntimeMemory.readFrame(address: 0x7030, count: 16))
    }

    func testOnlyReadFramesExist() throws {
        for step in RuntimeMemory.plan() {
            let f = try RuntimeMemory.readFrame(address: step.address, count: step.count)
            XCTAssertEqual(f[3], 0x03)
        }
    }

    func testPlanCoversBothRangesExactly() {
        let plan = RuntimeMemory.plan()
        let covered = plan.flatMap { s in (0..<s.count).map { Int(s.address) + $0 } }
        XCTAssertEqual(covered, Array(0x0000...0x0FFF) + Array(0x7000...0x703F))
        XCTAssertEqual(plan.count, 256 + 4)
    }

    func testParsesReplyAndSkipsAck() throws {
        XCTAssertNil(try RuntimeMemory.words(fromReply: [0x03, 0xFF], address: 0, count: 2))
        let body: [UInt8] = [0x03, 0x06, 0x38, 0x00, 0x02, 0x45, 0x4E, 0x45, 0x31]
        XCTAssertEqual(try RuntimeMemory.words(fromReply: body, address: 0x0638, count: 2), [0x454E, 0x4531])
        XCTAssertThrowsError(try RuntimeMemory.words(fromReply: body, address: 0x0600, count: 2))
        XCTAssertThrowsError(try RuntimeMemory.words(fromReply: [0x03, 0x06, 0x38, 0x00], address: 0x0638, count: 2))
    }

    func testMarkersAreValidPackets() throws {
        var r = Realtime(year: 2026, month: 11, day: 18, hour: 12, minute: 0, second: 0, weekday: 3)
        RuntimeMemory.applyMarkers(&r, second: false)
        XCTAssertNoThrow(try KeyboardProtocol.realtime(r))
        RuntimeMemory.applyMarkers(&r, second: true)
        XCTAssertNoThrow(try KeyboardProtocol.realtime(r))
        XCTAssertEqual(r.cpuLoad, 81); XCTAssertEqual(r.condition, 4)
    }

    func testMatchesFindWordsAndBytes() {
        let a: [UInt16: UInt16] = [0x0103: 65, 0x0200: 0x3D00, 0x0300: 0x1144, 0x0400: 65]
        let b: [UInt16: UInt16] = [0x0103: 85, 0x0200: 0x5100, 0x0300: 0x1158, 0x0400: 65]
        let m = RuntimeMemory.matches(a: a, b: b)
        XCTAssertTrue(m.contains(.init(field: "air temperature", address: 0x0103, part: "word")))
        XCTAssertTrue(m.contains(.init(field: "CPU load %", address: 0x0200, part: "high byte")))
        XCTAssertTrue(m.contains(.init(field: "humidity %", address: 0x0300, part: "low byte")))
        XCTAssertFalse(m.contains { $0.address == 0x0400 })   // unchanged value is not a match
    }
}
