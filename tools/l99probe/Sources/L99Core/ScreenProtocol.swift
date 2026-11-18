import Foundation

/// Screen (EEEF:268A, USB serial) upload protocol, firmware as captured from AULA driver v1.06.
/// See research/FINDINGS.md, Q8.
public enum ScreenProtocol {
    public static let width = 320
    public static let height = 480
    public static let pixelBytes = width * height * 2          // 307,200
    public static let imageBytes = pixelBytes + 11              // 307,211 incl. header

    public static let commandWrite: UInt8 = 0x64
    public static let commandCheck: UInt8 = 0x66
    public static let maxChunk = 2048
    public static let checkRegion = 0x20000                     // 128 KiB

    /// The three slots that may ever be written. Everything else on the screen's flash is off limits.
    public enum Slot: String, CaseIterable, Codable, Sendable {
        case background, photo, gif

        public var base: UInt32 {
            switch self {
            case .background: 0x0418_0000
            case .photo: 0x041E_0000
            case .gif: 0x0424_0000
            }
        }
        /// Hard upper bound for a write into this slot.
        public var capacity: Int {
            switch self {
            case .background, .photo: 0x60000
            case .gif: ScreenProtocol.gifMaxBytes
            }
        }
        public var displayName: String {
            switch self {
            case .background: "Background"
            case .photo: "Photo frame"
            case .gif: "GIF"
            }
        }
    }

    /// SAFETY: the factory animation's exact size (171-frame TOC + frames, ending at 0x05B0D07C),
    /// proven to fit and play. GIFs are capped here. (Its TOC size field, 26,002,208, counts frames only.)
    public static let gifMaxBytes = 26_005_628

    /// Kept for the probe tool and old tests.
    public static let photoSlot: UInt32 = Slot.photo.base
    public static let photoSlotLength = 0x60000

    public enum Failure: Error, CustomStringConvertible {
        case badImage(String)
        case outOfSlot(UInt32, Int)
        public var description: String {
            switch self {
            case .badImage(let s): return "Image rejected: \(s)"
            case .outOfSlot(let a, let n): return String(format: "Refusing write outside an allowed slot: 0x%08X + %d", a, n)
            }
        }
    }

    // MARK: Image container

    /// 11-byte header + RGB565 LE pixels, row-major.
    public static func imageContainer(rgb565 pixels: [UInt8]) throws -> [UInt8] {
        guard pixels.count == pixelBytes else { throw Failure.badImage("expected \(pixelBytes) pixel bytes, got \(pixels.count)") }
        var out = [UInt8]()
        out.reserveCapacity(imageBytes)
        out += le32(UInt32(pixels.count))
        out += le16(UInt16(width)) + le16(UInt16(height))
        out.append(0x00)
        out += le16(Checksum.crc16Modbus(pixels))
        out += pixels
        return out
    }

    /// Validates a finished 307,211-byte container (header fields and pixel CRC).
    public static func validateContainer(_ c: [UInt8]) throws {
        guard c.count == imageBytes else { throw Failure.badImage("container must be \(imageBytes) bytes, got \(c.count)") }
        let size = UInt32(c[0]) | UInt32(c[1]) << 8 | UInt32(c[2]) << 16 | UInt32(c[3]) << 24
        let w = Int(c[4]) | Int(c[5]) << 8, h = Int(c[6]) | Int(c[7]) << 8
        let crc = UInt16(c[9]) | UInt16(c[10]) << 8
        guard size == UInt32(pixelBytes), w == width, h == height, c[8] == 0 else { throw Failure.badImage("bad header") }
        guard Checksum.crc16Modbus(c[11...]) == crc else { throw Failure.badImage("pixel CRC mismatch") }
    }

    /// RGBA8 (premultiplied or not; alpha ignored) → RGB565 LE by truncation, like the vendor.
    public static func rgb565(fromRGBA rgba: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: rgba.count / 2)
        var o = 0
        var i = 0
        while i + 3 < rgba.count {
            let v = (UInt16(rgba[i] & 0xF8) << 8) | (UInt16(rgba[i + 1] & 0xFC) << 3) | UInt16(rgba[i + 2] >> 3)
            out[o] = UInt8(v & 0xFF); out[o + 1] = UInt8(v >> 8)
            o += 2; i += 4
        }
        return out
    }

    // MARK: Transfer plan

    public enum Step: Equatable {
        case write(address: UInt32, range: Range<Int>)
        case check(address: UInt32, range: Range<Int>)
    }

    /// The vendor sequence: 2048-byte writes; after every 128 KiB region and after the
    /// last chunk, a 0x66 region check whose reply carries the device's CRC32.
    /// Images must be exactly 307,211 bytes; GIF blobs at most the factory size.
    /// Every step is bounds-checked against its slot.
    public static func uploadPlan(slot: Slot, byteCount: Int) throws -> [Step] {
        switch slot {
        case .background, .photo:
            guard byteCount == imageBytes else { throw Failure.badImage("only full 320×480 images (\(imageBytes) bytes) are allowed") }
        case .gif:
            guard byteCount > 0, byteCount <= gifMaxBytes else {
                throw Failure.badImage("GIF data must be 1…\(gifMaxBytes) bytes, got \(byteCount)")
            }
        }
        var steps = [Step]()
        for regionStart in stride(from: 0, to: byteCount, by: checkRegion) {
            let regionEnd = min(regionStart + checkRegion, byteCount)
            for offset in stride(from: regionStart, to: regionEnd, by: maxChunk) {
                let end = min(offset + maxChunk, regionEnd)
                steps.append(.write(address: slot.base + UInt32(offset), range: offset..<end))
            }
            steps.append(.check(address: slot.base + UInt32(regionStart), range: regionStart..<regionEnd))
        }
        try assertInside(slot, steps)
        return steps
    }

    /// Only the 0x66 checks of an upload: asks the screen for the CRC32 of each region,
    /// so a library item can be compared with what the slot holds. Writes nothing.
    public static func verifyPlan(slot: Slot, byteCount: Int) throws -> [Step] {
        try uploadPlan(slot: slot, byteCount: byteCount).filter { if case .check = $0 { return true }; return false }
    }

    /// Probe-tool compatibility: photo slot only.
    public static func uploadPlan(byteCount: Int, base: UInt32 = photoSlot) throws -> [Step] {
        guard base == photoSlot else { throw Failure.outOfSlot(base, byteCount) }
        return try uploadPlan(slot: .photo, byteCount: byteCount)
    }

    private static func assertInside(_ slot: Slot, _ steps: [Step]) throws {
        for step in steps {
            let (a, r): (UInt32, Range<Int>)
            switch step { case .write(let x, let y), .check(let x, let y): (a, r) = (x, y) }
            guard a >= slot.base, Int(a - slot.base) + r.count <= slot.capacity else { throw Failure.outOfSlot(a, r.count) }
        }
    }

    // MARK: Framing

    /// 5A A5 | len u24 BE (= cmd + addr + data + crc) | cmd | addr u32 BE | data | CRC16/MODBUS LE over cmd..data
    public static func requestFrame(command: UInt8, address: UInt32, data: [UInt8]) -> [UInt8] {
        let body = [command] + be32(address) + data
        let length = body.count + 2
        let crc = Checksum.crc16Modbus(body)
        return [0x5A, 0xA5, UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
            + body + [UInt8(crc & 0xFF), UInt8(crc >> 8)]
    }

    public static func checkData(length: Int) -> [UInt8] { be32(UInt32(length)) }

    /// Incremental parser for replies: 5A A5 | len u8 (= body + 2) | body | CRC16 LE over body.
    public struct ResponseParser {
        public enum ParseError: Error, CustomStringConvertible {
            case badLength(Int), badCRC([UInt8])
            public var description: String {
                switch self {
                case .badLength(let n): return "reply has impossible length \(n)"
                case .badCRC(let f): return "reply CRC mismatch: \(f.hex)"
                }
            }
        }
        private var buffer = [UInt8]()
        public private(set) var discarded = 0
        public init() {}
        public mutating func feed(_ bytes: [UInt8]) { buffer += bytes }
        /// Returns the next complete reply body, or nil if more bytes are needed.
        public mutating func next() throws -> [UInt8]? {
            while buffer.count >= 3 {
                if buffer[0] != 0x5A || buffer[1] != 0xA5 { buffer.removeFirst(); discarded += 1; continue }
                let length = Int(buffer[2])
                guard (3...64).contains(length) else { throw ParseError.badLength(length) }
                guard buffer.count >= length + 3 else { return nil }
                let frame = Array(buffer.prefix(length + 3))
                buffer.removeFirst(length + 3)
                let body = Array(frame[3..<(frame.count - 2)])
                let crc = UInt16(frame[frame.count - 2]) | UInt16(frame[frame.count - 1]) << 8
                guard Checksum.crc16Modbus(body) == crc else { throw ParseError.badCRC(frame) }
                return body
            }
            return nil
        }
    }

    // MARK: Helpers
    public static func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
    public static func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }
    public static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    public static func beValue<C: Collection>(_ b: C) -> UInt32 where C.Element == UInt8 { b.reduce(0) { ($0 << 8) | UInt32($1) } }
}
