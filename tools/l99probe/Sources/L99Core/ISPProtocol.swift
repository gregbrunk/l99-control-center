// The screen's bootloader (ISP) protocol, interface-flash commands only.
// Source: research/ISP_PROTOCOL.md (AULA's reset tool, disassembled offline, and a
// USB capture of a real restore on Nov 18). Pure packet building and checking.
//
// Deliberately cannot build the control-program commands (4B 31, 4C, 4A, 4E) or the
// unused erase (68): the Mac never touches HFD_Code.

import Foundation

public enum ISP {
    /// The handshake target. There is no case for 0x31 (control program) on purpose.
    public enum Target: UInt8, Sendable { case hello = 0x30, interface = 0x32 }

    /// Alison's keyboard authenticated with this key in the capture (not …268A).
    public static let key: UInt32 = 0x1971_168B
    /// Every key AULA's tool knows, used only to name a mismatch in an error.
    public static let knownKeys: [UInt32] = [0x1971_168A, 0x1971_168B, 0x1971_268A, 0x1971_268B, 0x1971_2690,
                                             0x1971_268C, 0x1971_268D, 0x1971_7689, 0x1971_7760]
    /// Handshake reply bytes 9…18 in every captured reply: chip info, timing mode EEBA0081,
    /// and "not the alternate write format".
    public static let expectedInfo: [UInt8] = [0x01, 0x16, 0x09, 0x25, 0x81, 0x00, 0xBA, 0xEE, 0x50, 0x4F]
    /// `6D` reply bytes 1…6 (GD5F1GQ4).
    public static let expectedFlashID: [UInt8] = [0xC8, 0xD1, 0xC8, 0x00, 0x68, 0x97]
    /// 1 Gbit SPI NAND.
    public static let flashSize = 0x0800_0000
    public static let chunkSize = 2048
    /// The verify reply's running CRC lags the read position by one 128 KB block.
    public static let verifyLag = 0x2_0000
    /// The final `7E 31` value the screen reported for the stock UartTFT-II_Flash.bin.
    public static let stockFinalValue: UInt32 = 0x6209_D25F
    public static let replyLength = 63

    static func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
    static func le32(_ b: ArraySlice<UInt8>) -> UInt32 {
        b.enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) }
    }
    static func pad64(_ b: [UInt8]) -> [UInt8] { b + [UInt8](repeating: 0, count: 64 - b.count) }

    // MARK: Handshake (4B)

    /// `4B cc 4C 54 · nonce · CRC32(4B cc 4C 54 nonce key) · E8 17 00 00 · 7F`, padded to 64.
    /// Byte 16 follows the line speed, as in the capture: `08` at 115200, `7F` at 921600.
    public static func handshake(_ target: Target, nonce: UInt32, key: UInt32 = key, fast: Bool = true) -> [UInt8] {
        let head: [UInt8] = [0x4B, target.rawValue, 0x4C, 0x54] + le32(nonce)
        let auth = Checksum.crc32Screen(head + le32(key))
        return pad64(head + le32(auth) + [0xE8, 0x17, 0x00, 0x00, fast ? 0x7F : 0x08])
    }

    /// Which known key the reply proves, or nil if none.
    public static func replyKey(_ reply: [UInt8], request: [UInt8]) -> UInt32? {
        guard reply.count >= 19, reply[0] == 0x4B, request.count >= 8 else { return nil }
        let proof = le32(reply[1..<5])
        return knownKeys.first { Checksum.crc32Screen(Array(request[0..<8]) + le32($0) + Array("POTL".utf8)) == proof }
    }

    /// Throws unless the reply authenticates with `key` and carries exactly the captured info bytes.
    public static func checkHandshake(_ reply: [UInt8], request: [UInt8]) throws {
        guard reply.count >= 19, reply[0] == 0x4B else { throw ISPError("Handshake: unexpected reply \(reply.prefix(20).hex)") }
        guard let k = replyKey(reply, request: request) else { throw ISPError("Handshake: the reply does not authenticate with any known key") }
        guard k == key else { throw ISPError(String(format: "Handshake: screen uses key %08X, expected %08X. Stopped.", k, key)) }
        guard Array(reply[9..<19]) == expectedInfo else {
            throw ISPError("Handshake: screen info \(Array(reply[9..<19]).hex) differs from the captured \(expectedInfo.hex). Stopped.")
        }
    }

    // MARK: Flash ID (6D) and addressing mode (6F)

    public static let flashIDRequest = pad64([0x6D, 0x01, 0x00])
    public static func checkFlashID(_ reply: [UInt8]) throws {
        guard reply.count >= 7, reply[0] == 0x7D, Array(reply[1..<7]) == expectedFlashID else {
            throw ISPError("Flash ID reply \(reply.prefix(8).hex) is not the GD5F1GQ4 seen in the capture. Stopped.")
        }
    }

    public static let addressModeRequest = pad64([0x6F, 0x02])
    public static func checkAddressMode(_ reply: [UInt8]) throws {
        guard reply.first == 0x7F else { throw ISPError("Addressing mode 6F 02 was refused: \(reply.prefix(8).hex). Stopped.") }
    }

    // MARK: Data (6C)

    /// `6C · offset · toggle · len · data · CRC32`, not padded.
    public static func dataPacket(offset: Int, toggle: UInt8, data: ArraySlice<UInt8>) -> [UInt8] {
        precondition(!data.isEmpty && data.count <= chunkSize && offset >= 0 && offset + data.count <= flashSize)
        precondition(toggle <= 1)
        var p: [UInt8] = [0x6C] + le32(UInt32(offset)) + [toggle, UInt8(data.count & 0xFF), UInt8(data.count >> 8)]
        p += data
        return p + le32(Checksum.crc32Screen(p))
    }

    /// The reply echoes the toggle: `7C tt`.
    public static func dataAccepted(_ reply: [UInt8], toggle: UInt8) -> Bool {
        reply.count >= 2 && reply[0] == 0x7C && reply[1] == toggle
    }

    // MARK: Read-back check (6E)

    public static func verifyRequest(size: Int, fileCRC: UInt32) -> [UInt8] {
        let head: [UInt8] = [0x6E, 0, 0, 0, 0] + le32(UInt32(size)) + le32(fileCRC)
        return pad64(head + le32(Checksum.crc32Screen(head)))
    }

    public enum VerifyReply: Equatable, Sendable {
        case progress(position: Int, runningCRC: UInt32)
        case done(value: UInt32)
    }

    public static func parseVerify(_ reply: [UInt8]) throws -> VerifyReply {
        guard reply.count >= 10, reply[0] == 0x7E else { throw ISPError("Unexpected reply during the read-back check: \(reply.prefix(12).hex)") }
        switch reply[1] {
        case 0x30: return .progress(position: Int(le32(reply[2..<6])), runningCRC: le32(reply[6..<10]))
        case 0x31: return .done(value: le32(reply[2..<6]))
        default: throw ISPError("The screen reported a read-back failure: \(reply.prefix(12).hex)")
        }
    }

    // MARK: Restart (4F)

    /// `4F 08008000`, CRC32 of bytes 0…11 at byte 12. No reply; the screen restarts.
    public static var restartRequest: [UInt8] {
        let head: [UInt8] = [0x4F] + le32(0x0800_8000) + [UInt8](repeating: 0, count: 7)
        return pad64(head + le32(Checksum.crc32Screen(head)))
    }

    // MARK: Whole-file plan

    /// Validates an interface file and computes what the install needs.
    public struct Image: Sendable {
        public let bytes: [UInt8]
        public let crc: UInt32
        public var chunkCount: Int { (bytes.count + chunkSize - 1) / chunkSize }

        public init(_ bytes: [UInt8]) throws {
            guard !bytes.isEmpty else { throw ISPError("The interface file is empty") }
            guard bytes.count <= flashSize else { throw ISPError("The interface file is larger than the 128 MB flash") }
            self.bytes = bytes
            crc = Checksum.crc32Screen(bytes)
        }

        public func packet(_ index: Int) -> [UInt8] {
            let start = index * chunkSize
            return dataPacket(offset: start, toggle: UInt8(index & 1), data: bytes[start..<min(start + chunkSize, bytes.count)])
        }
    }

    /// Checks the read-back progress replies against the file as they arrive.
    /// `CRC32(file[0 ..< position − 128 KB])` must equal the running value; the
    /// last block is past the file's end, so it is not checked (see ISP_PROTOCOL.md).
    public struct VerifyTracker {
        let bytes: [UInt8]
        var done = 0
        var state: UInt32 = 0
        public private(set) var checked = 0

        public init(_ image: Image) { bytes = image.bytes }

        public mutating func check(position: Int, runningCRC: UInt32) throws {
            let end = position - verifyLag
            // The final report (position = size + 128 KB) carries the screen's own final value
            // (6209D25F for stock), not CRC32(file): not comparable. Seen on the Mac, Nov 18.
            guard end < bytes.count else { return }
            guard end >= done else { throw ISPError("Read-back went backwards (position \(position))") }
            state = Checksum.crc32Screen(bytes[done..<end], initial: state)
            done = end
            guard state == runningCRC else {
                throw ISPError(String(format: "Read-back mismatch before offset 0x%X: screen %08X, file %08X", end, runningCRC, state))
            }
            checked += 1
        }
    }
}

public struct ISPError: Error, CustomStringConvertible, LocalizedError {
    public let description: String
    public init(_ s: String) { description = s }
    public var errorDescription: String? { description }
}
