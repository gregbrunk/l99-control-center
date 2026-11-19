import XCTest
@testable import L99Core

/// Fixtures are exact packets from the Nov 18 USB capture of a PC restore (research/ISP_PROTOCOL.md).
final class ISPProtocolTests: XCTestCase {
    func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map {
            let i = hex.index(hex.startIndex, offsetBy: $0); return UInt8(hex[i..<hex.index(i, offsetBy: 2)], radix: 16)!
        }
    }
    func padded(_ hex: String, _ n: Int = 64) -> [UInt8] { let b = bytes(hex); return b + [UInt8](repeating: 0, count: n - b.count) }

    let factory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("research/factory/UartTFT-II_Flash.bin").path

    func testHandshakeMatchesCapture() {
        // Captured 4B 32 (select interface flash), nonce 00C72B6D.
        XCTAssertEqual(ISP.handshake(.interface, nonce: 0x00C7_2B6D),
                       padded("4b324c546d2bc700f8eeca60e81700007f"))
        XCTAssertEqual(ISP.handshake(.hello, nonce: 0x00C7_25A3),
                       padded("4b304c54a325c7006179b507e81700007f"))
    }

    func testHandshakeReplyAuthenticates() throws {
        let req = padded("4b324c546d2bc700f8eeca60e81700007f")
        let reply = padded("4bcacd7f8df8eeca60011609258100baee504f00000000000000000000007887", 63)
        XCTAssertEqual(ISP.replyKey(reply, request: req), 0x1971_168B)
        XCTAssertNoThrow(try ISP.checkHandshake(reply, request: req))
        // The tool's first guess (…168A) was answered with the …168B proof.
        let first = padded("4b304c54684ec7007a5d7411e817000008")
        let firstReply = padded("4b3131d99c1f3ac8a9011609258100baee504f00000000000000000000007887", 63)
        XCTAssertEqual(ISP.replyKey(firstReply, request: first), 0x1971_168B)
    }

    func testHandshakeRejectsChanges() {
        let req = padded("4b324c546d2bc700f8eeca60e81700007f")
        var reply = padded("4bcacd7f8df8eeca60011609258100baee504f00000000000000000000007887", 63)
        reply[17] = 0x56; reply[18] = 0x76      // alternate write format
        XCTAssertThrowsError(try ISP.checkHandshake(reply, request: req))
        var forged = padded("4bcacd7f8df8eeca60011609258100baee504f", 63)
        forged[2] ^= 1
        XCTAssertThrowsError(try ISP.checkHandshake(forged, request: req))
    }

    func testNoControlProgramTarget() {
        XCTAssertNil(ISP.Target(rawValue: 0x31))
    }

    func testSmallCommandsMatchCapture() throws {
        XCTAssertEqual(ISP.flashIDRequest, padded("6d0100"))
        XCTAssertNoThrow(try ISP.checkFlashID(padded("7dc8d1c800689700", 63)))
        XCTAssertThrowsError(try ISP.checkFlashID(padded("7dc8d1c800689800", 63)))
        XCTAssertEqual(ISP.addressModeRequest, padded("6f02"))
        XCTAssertNoThrow(try ISP.checkAddressMode(padded("7f", 63)))
        XCTAssertEqual(ISP.verifyRequest(size: 127_599_044, fileCRC: 0x4DEE_F87B),
                       padded("6e00000000c4019b077bf8ee4dbd4876a6"))
        XCTAssertEqual(ISP.restartRequest, padded("4f0080000800000000000000353a1777"))
    }

    func testVerifyRepliesParse() throws {
        XCTAssertEqual(try ISP.parseVerify(padded("7e30000004004cabb19d", 63)), .progress(position: 0x40000, runningCRC: 0x9DB1_AB4C))
        XCTAssertEqual(try ISP.parseVerify(padded("7e315fd209625fd20962", 63)), .done(value: 0x6209_D25F))
        XCTAssertThrowsError(try ISP.parseVerify(padded("7e32", 63)))
    }

    func testDataAckEchoesToggle() {
        XCTAssertTrue(ISP.dataAccepted(padded("7c01", 63), toggle: 1))
        XCTAssertFalse(ISP.dataAccepted(padded("7c00", 63), toggle: 1))
    }

    func testStockFileReproducesCapturedPackets() throws {
        guard let d = FileManager.default.contents(atPath: factory) else { throw XCTSkip("factory file missing") }
        let image = try ISP.Image(Array(d))
        XCTAssertEqual(image.crc, 0x4DEE_F87B)
        XCTAssertEqual(image.chunkCount, 62_305)
        let first = image.packet(0), second = image.packet(1), last = image.packet(image.chunkCount - 1)
        XCTAssertEqual(Array(first.prefix(8)), bytes("6c00000000000008")); XCTAssertEqual(Array(first.suffix(4)), bytes("eb94816f"))
        XCTAssertEqual(Array(second.prefix(8)), bytes("6c00080000010008")); XCTAssertEqual(Array(second.suffix(4)), bytes("b25b7e32"))
        XCTAssertEqual(Array(last.prefix(8)), bytes("6c00009b0700c401")); XCTAssertEqual(Array(last.suffix(4)), bytes("efb8d273"))
        XCTAssertEqual(last.count, 464)

        // Running read-back values from the capture.
        var t = ISP.VerifyTracker(image)
        try t.check(position: 0x40000, runningCRC: 0x9DB1_AB4C)
        try t.check(position: 0x60000, runningCRC: 0xB71B_9BCD)
        try t.check(position: 0x80000, runningCRC: 0x7149_DE47)
        XCTAssertThrowsError(try t.check(position: 0xA0000, runningCRC: 0))

        // The last progress report sits exactly one lag past the end and carries the final value.
        var tail = ISP.VerifyTracker(image)
        XCTAssertNoThrow(try tail.check(position: image.bytes.count + ISP.verifyLag, runningCRC: ISP.stockFinalValue))
    }

    func testRunningCRCContinues() {
        let a: [UInt8] = Array(0..<200)
        XCTAssertEqual(Checksum.crc32Screen(a[100...], initial: Checksum.crc32Screen(a[..<100])), Checksum.crc32Screen(a))
    }
}
