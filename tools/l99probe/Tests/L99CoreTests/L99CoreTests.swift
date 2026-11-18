import XCTest
@testable import L99Core

private func bytes(_ hex: String) -> [UInt8] {
    let h = hex.replacingOccurrences(of: " ", with: "")
    return stride(from: 0, to: h.count, by: 2).map {
        let s = h.index(h.startIndex, offsetBy: $0)
        return UInt8(h[s..<h.index(s, offsetBy: 2)], radix: 16)!
    }
}

final class ChecksumTests: XCTestCase {
    func testCRC16Modbus() {
        XCTAssertEqual(Checksum.crc16Modbus(Array("123456789".utf8)), 0x4B37)   // standard check value
    }
    func testCRC32Screen() {
        // reflected 0xEDB88320, init 0, no xorout (reference value computed independently in Python)
        XCTAssertEqual(Checksum.crc32Screen(Array("123456789".utf8)), 0x2DFD_2D88)
    }
    func testGavindiCRCTableCollapsesToModbus() {
        // gavindi encodes the write frame as 5A A5 00 | BE16(N+7) | 64 … — our u24 length must equal that.
        let f = ScreenProtocol.requestFrame(command: 0x64, address: 0x041E_0000, data: [UInt8](repeating: 0, count: 2048))
        XCTAssertEqual(Array(f.prefix(10)), bytes("5a a5 00 08 07 64 04 1e 00 00"))
        XCTAssertEqual(f.count, 5 + 0x807)
    }
}

final class ScreenTests: XCTestCase {
    func testUploadPlanMatchesVendorCapture() throws {
        let plan = try ScreenProtocol.uploadPlan(byteCount: ScreenProtocol.imageBytes)
        let writes = plan.compactMap { s -> (UInt32, Int)? in if case .write(let a, let r) = s { return (a, r.count) }; return nil }
        let checks = plan.compactMap { s -> (UInt32, Int)? in if case .check(let a, let r) = s { return (a, r.count) }; return nil }
        XCTAssertEqual(writes.count, 151)                               // 150 × 2048 + one 11-byte tail
        XCTAssertEqual(writes.last!.0, 0x0422_B000); XCTAssertEqual(writes.last!.1, 11)
        XCTAssertEqual(checks.map(\.0), [0x041E_0000, 0x0420_0000, 0x0422_0000])
        XCTAssertEqual(checks.map(\.1), [0x20000, 0x20000, 0xB00B])
        XCTAssertEqual(plan.last, .check(address: 0x0422_0000, range: 0x40000..<0x4B00B))
    }
    func testPlanRefusesAnythingElse() {
        XCTAssertThrowsError(try ScreenProtocol.uploadPlan(byteCount: ScreenProtocol.imageBytes + 1))
        XCTAssertThrowsError(try ScreenProtocol.uploadPlan(byteCount: 1000))
        XCTAssertThrowsError(try ScreenProtocol.uploadPlan(byteCount: ScreenProtocol.imageBytes, base: 0x0418_0000))   // probe API stays photo-only
        XCTAssertThrowsError(try ScreenProtocol.uploadPlan(byteCount: ScreenProtocol.imageBytes, base: 0x0424_0000))
    }
    func testContainerHeaderMatchesCapture() throws {
        let c = try ScreenProtocol.imageContainer(rgb565: [UInt8](repeating: 0, count: ScreenProtocol.pixelBytes))
        XCTAssertEqual(Array(c.prefix(9)), bytes("00 b0 04 00 40 01 e0 01 00"))  // as seen in Salamor's capture
        XCTAssertNoThrow(try ScreenProtocol.validateContainer(c))
        var bad = c; bad[500] ^= 1
        XCTAssertThrowsError(try ScreenProtocol.validateContainer(bad))
    }
    func testRGB565Truncation() {
        XCTAssertEqual(ScreenProtocol.rgb565(fromRGBA: [255, 255, 255, 255]), [0xFF, 0xFF])
        XCTAssertEqual(ScreenProtocol.rgb565(fromRGBA: [255, 0, 0, 255]), [0x00, 0xF8])
        XCTAssertEqual(ScreenProtocol.rgb565(fromRGBA: [0, 0, 255, 255]), [0x1F, 0x00])
    }
    func testResponseParser() throws {
        var p = ScreenProtocol.ResponseParser()
        func frame(_ body: [UInt8]) -> [UInt8] {
            let c = Checksum.crc16Modbus(body)
            return [0x5A, 0xA5, UInt8(body.count + 2)] + body + [UInt8(c & 0xFF), UInt8(c >> 8)]
        }
        let ack = frame([0x64, 0xFF]), result = frame([0x64, 0x04, 0x1E, 0x38, 0x00, 0x4F, 0x4B])
        p.feed([0x00, 0x13] + ack + Array(result.prefix(4)))
        XCTAssertEqual(try p.next(), [0x64, 0xFF])
        XCTAssertNil(try p.next())
        p.feed(Array(result.dropFirst(4)))
        XCTAssertEqual(try p.next(), [0x64, 0x04, 0x1E, 0x38, 0x00, 0x4F, 0x4B])
        var q = ScreenProtocol.ResponseParser()
        var corrupt = ack; corrupt[4] = 0xFE
        q.feed(corrupt)
        XCTAssertThrowsError(try q.next())
    }
    /// Uses the verified factory interface file when present.
    func testFactoryPhotoSlot() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("research/factory/UartTFT-II_Flash.bin").path
        guard let fh = FileHandle(forReadingAtPath: path) else { throw XCTSkip("factory file not present") }
        try fh.seek(toOffset: UInt64(ScreenProtocol.photoSlot))
        let c = [UInt8](try fh.read(upToCount: ScreenProtocol.imageBytes)!)
        XCTAssertNoThrow(try ScreenProtocol.validateContainer(c))
        XCTAssertEqual(Checksum.crc32Screen(c[0..<0x20000]), 0x5819_88BE)
        XCTAssertEqual(Checksum.crc32Screen(c[0x20000..<0x40000]), 0xDE62_925D)
        XCTAssertEqual(Checksum.crc32Screen(c[0x40000...]), 0x627C_10A9)
    }
}

final class KeyboardTests: XCTestCase {
    func testRealtimeMatchesAxiraDevFixture() throws {
        var r = Realtime(year: 2026, month: 10, day: 20, hour: 14, minute: 25, second: 30, weekday: 2)
        r.cpuLoad = 37; r.cpuTemp = 62; r.gpuLoad = 18; r.gpuTemp = 55
        r.airTemp = 61; r.dayHigh = 61; r.nightLow = 61
        let reports = try KeyboardProtocol.realtime(r)
        XCTAssertEqual(reports.map(\.expectsAck), [true, true, false, true])
        let fixture = bytes(
            "0418" + String(repeating: "00", count: 62) +
            "0428000000000000" + "01" + String(repeating: "00", count: 55) +
            "00015a1a0a140e191e00020000253e12373d3d3d" + String(repeating: "00", count: 42) + "aa55" +
            "0402" + String(repeating: "00", count: 62))
        XCTAssertEqual(reports.flatMap(\.bytes), fixture)
    }
    func testMusicAxiraMatchesFixture() {
        let ints = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 99, 95, 75, 55, 35, 15, 5, 0]
        let reports = KeyboardProtocol.music(levels: ints.map { Double($0) / 99 }, layout: .axira)
        XCTAssertEqual(reports.count, 4)
        XCTAssertEqual(Array(reports[2].bytes.prefix(21)), bytes("020023000a141e28323c46505a635f4b37230f0500"))
        XCTAssertEqual(Array(reports[1].bytes.prefix(9)), bytes("047800000000000001"))
    }
    func testMusicGavindiLayout() {
        let reports = KeyboardProtocol.music(levels: [1, 0.5], layout: .gavindi)
        XCTAssertEqual(reports.map { $0.bytes[1] }, [0x02, 0x78, 0x08])   // commit, music, data block (byte 1 = bg mode)
        XCTAssertEqual(Array(reports[2].bytes.prefix(6)), [0x04, 0x08, 0x64, 100, 50, 0])
        XCTAssertFalse(reports[2].expectsAck)
    }
    func testOnlyVolatileOpcodes() throws {
        var r = Realtime(date: Date()); r.applyTestStats()
        let all = try KeyboardProtocol.realtime(r) + KeyboardProtocol.music(levels: [], layout: .gavindi) + KeyboardProtocol.music(levels: [], layout: .axira)
        for rep in all where rep.expectsAck { XCTAssertTrue(KeyboardProtocol.allowedOpcodes.contains(rep.bytes[1])) }
        XCTAssertFalse(KeyboardProtocol.allowedOpcodes.contains(0xF0))
    }
    func testRejectsBadValues() {
        var r = Realtime(year: 2026, month: 13, day: 1, hour: 0, minute: 0, second: 0, weekday: 0)
        XCTAssertThrowsError(try KeyboardProtocol.realtime(r))
        r.month = 1; r.cpuLoad = 101
        XCTAssertThrowsError(try KeyboardProtocol.realtime(r))
    }
}

final class DongleTests: XCTestCase {
    func testQueriesMatchGavindiCaptures() {
        XCTAssertEqual(DongleProtocol.sessionInit, bytes("0200000000000000000000000000000000000000000000000000000000000002"))
        XCTAssertEqual(DongleProtocol.batteryQuery, bytes("2001000000000000000000000000000000000000000000000000000000000021"))
        XCTAssertTrue(DongleProtocol.checksumOK(bytes("02000040300000450c0a802901ffff0000000000000000000000000000000075")))
        XCTAssertTrue(DongleProtocol.checksumOK(bytes("2001006400000000000000000000000000000000000000000000000000000085")))
        XCTAssertTrue(DongleProtocol.checksumOK(bytes("0c1000000000000000000000000000000000000000000000000000000000001c")))
    }
    func testPriorArtClockMatchesGavindiBuilder() throws {
        // Friday 2026-11-20 10:30:00 → gavindi's prior-art body (weekday byte 13 = 05)
        let r = Realtime(year: 2026, month: 11, day: 20, hour: 10, minute: 30, second: 0, weekday: 5)
        let body = bytes("0c1000" + "00015a1a0b140a1e00" + "00" + "05" + "000000" + "aa55" + String(repeating: "00", count: 12))
        XCTAssertEqual(try DongleProtocol.clock(r, layout: .prior), body + [Checksum.dongleSum(body)])
    }
    func testMusicMatchesVendorLayout() {
        let f = DongleProtocol.music(levels: [1, 0.5, 0])
        XCTAssertEqual(f.count, 32)
        XCTAssertEqual(Array(f[0...8]), [0x0B, 0x1C, 0x00, 2, 0, 35, 99, 50, 0])
        XCTAssertEqual(Array(f[27...30]), [0, 0, 0, 0])
        XCTAssertTrue(DongleProtocol.checksumOK(f))
    }
    func testStatsLayouts() throws {
        var r = Realtime(year: 2026, month: 11, day: 20, hour: 10, minute: 30, second: 0, weekday: 5)
        r.applyTestStats()
        let p3 = try DongleProtocol.clock(r, layout: .plus3), p4 = try DongleProtocol.clock(r, layout: .plus4)
        XCTAssertEqual(Array(p3[4...6]), [0x01, 0x5A, 26]); XCTAssertEqual(Array(p4[5...7]), [0x01, 0x5A, 26])
        XCTAssertEqual(p3[16], 42); XCTAssertEqual(p4[17], 42)          // CPU load
        XCTAssertEqual(Array(p3[25...26]), [0xAA, 0x55]); XCTAssertEqual(Array(p4[26...27]), [0xAA, 0x55])
        XCTAssertTrue(DongleProtocol.checksumOK(p3)); XCTAssertTrue(DongleProtocol.checksumOK(p4))
    }
}
