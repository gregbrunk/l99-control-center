import CryptoKit
import Foundation

/// Builds a modified interface file (UartTFT-II_Flash.bin) from the stock one.
/// Install the result with `l99probe isp-flash <file> --direct`.
///
/// Layout (research/FINDINGS.md "Screen catalog"; softce docs/image-format.md):
/// - Header words 2/3: page table (30 × `u32 display_off, u16 display_len, u32 touch_off, u16 touch_len`).
/// - Header words 12/13: icon descriptor table and icon count per bank. Two banks (English, Chinese);
///   each descriptor is 12 bytes: address u32, width u16, height u16, size u24 | format u8 << 24.
/// - The active project ends at the LE32 size stored at 0x174 (stock 0xA355EC). Everything after it up
///   to 0x04000000 is zero padding inside the file. New art is placed there and the size is extended.
///
/// Every operation records the exact byte ranges it may change; `validate()` proves nothing else changed.
public struct InterfaceFile {
    /// The stock file from the 2026.5.25 reset package.
    public static let stockSHA256 = InterfaceBlockTest.stockSHA256
    /// Existing art lives here; in-place replacements must stay inside it.
    public static let artRange = 0x0062_5000..<0x00A3_55EC
    public static let projectSizeOffset = 0x174
    /// New art may go from the project's end up to the separate images at 0x04000000.
    public static let paddingEnd = 0x0400_0000
    public static let pageCount = 30

    public struct Icon: Equatable, Sendable {
        public let id: Int, address: Int, width: Int, height: Int, size: Int, format: Int
        public var byteRange: Range<Int> { address..<(address + size) }
    }

    /// A basic touch button: `x1 y1 x2 y2 code up down goto` (LE16 each).
    public struct TouchButton: Equatable, Sendable {
        public let offset: Int          // payload offset in the file
        public var x1, y1, x2, y2, code, up, down, goto: Int
    }

    public enum Failure: Error, CustomStringConvertible, Equatable {
        case notStock(String)
        case refused(String)
        public var description: String {
            switch self {
            case .notStock(let s): "Not the stock interface file: \(s)"
            case .refused(let s): s
            }
        }
    }

    public let stock: [UInt8]
    public private(set) var bytes: [UInt8]
    public let iconTable: Int, iconCount: Int, pageTable: Int
    /// Byte ranges the operations so far were allowed to change.
    public private(set) var allowed: [Range<Int>] = []
    /// One line per operation, for the build report.
    public private(set) var log: [String] = []

    public init(stockFile path: String) throws {
        guard let data = FileManager.default.contents(atPath: path) else { throw Failure.notStock("can't read \(path)") }
        try self.init(stockBytes: [UInt8](data))
    }

    public init(stockBytes: [UInt8]) throws {
        let digest = SHA256.hash(data: stockBytes).map { String(format: "%02x", $0) }.joined()
        guard digest == Self.stockSHA256 else { throw Failure.notStock("SHA-256 \(digest)") }
        stock = stockBytes; bytes = stockBytes
        pageTable = Int(Self.u32(stockBytes, 2 * 4))
        iconTable = Int(Self.u32(stockBytes, 12 * 4)); iconCount = Int(Self.u32(stockBytes, 13 * 4))
    }

    static func u32(_ b: [UInt8], _ o: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(b[o + $1]) << (8 * $1) } }
    static func u16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
    mutating func put16(_ o: Int, _ v: Int) { bytes[o] = UInt8(v & 0xFF); bytes[o + 1] = UInt8(v >> 8 & 0xFF) }
    mutating func put32(_ o: Int, _ v: Int) { for k in 0..<4 { bytes[o + k] = UInt8(v >> (8 * k) & 0xFF) } }

    /// The active project's current end (stock 0xA355EC).
    public var projectEnd: Int { Int(Self.u32(bytes, Self.projectSizeOffset)) }

    // MARK: Icons

    /// The icon's current descriptor in a bank (0 = English, 1 = Chinese).
    public func icon(_ id: Int, bank: Int = 0) throws -> Icon {
        guard (0..<iconCount).contains(id), (0...1).contains(bank) else { throw Failure.refused("No icon \(id) in bank \(bank)") }
        let o = descriptorOffset(id, bank: bank)
        let p = Self.u32(bytes, o + 8)
        return Icon(id: id, address: Int(Self.u32(bytes, o)), width: Self.u16(bytes, o + 4), height: Self.u16(bytes, o + 6),
                    size: Int(p & 0xFF_FFFF), format: Int(p >> 24))
    }

    func descriptorOffset(_ id: Int, bank: Int) -> Int { iconTable + (bank * iconCount + id) * 12 }

    /// The icon's current pixels (formats 0–2 only).
    public func pixels(_ id: Int, bank: Int = 0) throws -> [UInt16] {
        let ic = try icon(id, bank: bank)
        guard (0...2).contains(ic.format), ic.size == ic.width * ic.height * 2 else {
            throw Failure.refused("Icon \(id) is format \(ic.format); only raw 16-bit icons are supported")
        }
        return stride(from: ic.address, to: ic.address + ic.size, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
    }

    /// Replaces an icon's pixels in place, at the same size, in every bank that uses it.
    public mutating func replaceIcon(_ id: Int, pixels new: [UInt16]) throws {
        let ics = try (0...1).map { try icon(id, bank: $0) }
        for ic in ics {
            guard (0...2).contains(ic.format), ic.size == ic.width * ic.height * 2 else {
                throw Failure.refused("Icon \(id) is format \(ic.format); only raw 16-bit icons can be replaced")
            }
            guard new.count == ic.width * ic.height else { throw Failure.refused("Icon \(id) is \(ic.width)×\(ic.height); got \(new.count) pixels") }
            guard Self.artRange.contains(ic.address), Self.artRange.contains(ic.address + ic.size - 1) else {
                throw Failure.refused(String(format: "Refused: icon %d's data at 0x%08X is outside the art area", id, ic.address))
            }
            try checkNotShared(ic)
        }
        for a in Set(ics.map(\.address)) {
            for (i, v) in new.enumerated() { put16(a + 2 * i, Int(v)) }
            allowed.append(a..<(a + new.count * 2))
        }
        log.append("icon \(id): pixels replaced in place (\(ics[0].width)×\(ics[0].height))")
    }

    func checkNotShared(_ ic: Icon) throws {
        for bank in 0...1 {
            for other in 0..<iconCount where other != ic.id {
                let o = try icon(other, bank: bank)
                guard o.size > 0, o.byteRange.overlaps(ic.byteRange) else { continue }
                throw Failure.refused("Icon \(ic.id)'s bytes are shared with icon \(other); not replacing")
            }
        }
    }

    /// Gives an icon new ARGB4444 art at any size. The pixels go after the project's end (which is
    /// extended to cover them) and the icon's descriptor is pointed at them in both banks. The old
    /// pixels stay where they were, unreferenced. Refused if the two banks' descriptors differ.
    public mutating func placeIcon(_ id: Int, width: Int, height: Int, pixels new: [UInt16]) throws {
        guard width > 0, height > 0, width <= 320, height <= 480, new.count == width * height else {
            throw Failure.refused("Icon \(id): \(width)×\(height) needs \(width * height) pixels, got \(new.count)")
        }
        let b0 = try icon(id, bank: 0), b1 = try icon(id, bank: 1)
        guard b0 == b1 else { throw Failure.refused("Icon \(id) differs between the language banks; not relocating") }
        let start = (projectEnd + 3) & ~3, size = new.count * 2
        guard start + size <= Self.paddingEnd else { throw Failure.refused("No room left for icon \(id)") }
        guard bytes[start..<(start + size)].allSatisfy({ $0 == 0 }) else {
            throw Failure.refused(String(format: "Space at 0x%08X isn't empty padding. Stopped.", start))
        }
        for (i, v) in new.enumerated() { put16(start + 2 * i, Int(v)) }
        allowed.append(start..<(start + size))
        for bank in 0...1 {
            let o = descriptorOffset(id, bank: bank)
            put32(o, start); put16(o + 4, width); put16(o + 6, height); put32(o + 8, size | 2 << 24)
            allowed.append(o..<(o + 12))
        }
        put32(Self.projectSizeOffset, start + size)
        allowed.append(Self.projectSizeOffset..<(Self.projectSizeOffset + 4))
        log.append(String(format: "icon %d: new %d×%d art at 0x%08X (%d bytes), both banks", id, width, height, start, size))
    }

    // MARK: Pages and touch buttons

    public func touchButtons(page: Int) throws -> [TouchButton] {
        guard (0..<Self.pageCount).contains(page) else { throw Failure.refused("No page \(page)") }
        let e = pageTable + page * 12
        var p = Int(Self.u32(bytes, e + 6)); let end = p + Self.u16(bytes, e + 10)
        var out = [TouchButton]()
        while p < end {
            let type = Self.u16(bytes, p), len = Int(bytes[p + 2] & 0x7F), pay = p + 3
            if type & 0x3FFF == 1 && len == 16 {
                let w = (0..<8).map { Self.u16(bytes, pay + 2 * $0) }
                out.append(TouchButton(offset: pay, x1: w[0], y1: w[1], x2: w[2], y2: w[3], code: w[4], up: w[5], down: w[6], goto: w[7]))
            }
            p = pay + len
        }
        guard p == end else { throw Failure.refused("Page \(page)'s touch records don't add up. Stopped.") }
        return out
    }

    /// Moves and resizes the touch button with this action code on a page. Only the rectangle changes;
    /// the action, images and goto stay. The image is drawn at (x, y); keep w×h equal to its size.
    public mutating func moveButton(page: Int, code: Int, x: Int, y: Int, width: Int, height: Int) throws {
        let matches = try touchButtons(page: page).filter { $0.code == code }
        guard matches.count == 1, let b = matches.first else {
            throw Failure.refused("Page \(page) has \(try touchButtons(page: page).filter { $0.code == code }.count) buttons with code \(code); expected 1")
        }
        guard x >= 0, y >= 0, width > 0, height > 0, x + width <= 320, y + height <= 480 else {
            throw Failure.refused("Button \(code): \(width)×\(height) at (\(x), \(y)) is off the 320×480 screen")
        }
        put16(b.offset, x); put16(b.offset + 2, y); put16(b.offset + 4, x + width - 1); put16(b.offset + 6, y + height - 1)
        allowed.append(b.offset..<(b.offset + 8))
        log.append("page \(page) button \(code): (\(b.x1),\(b.y1))–(\(b.x2),\(b.y2)) → (\(x),\(y))–(\(x + width - 1),\(y + height - 1))")
    }

    // MARK: Checking and saving

    /// Every changed byte range, merged.
    public func changedRanges() -> [Range<Int>] {
        var out = [Range<Int>](), start: Int? = nil
        for i in 0..<bytes.count {
            if bytes[i] != stock[i] { if start == nil { start = i } }
            else if let s = start { out.append(s..<i); start = nil }
        }
        if let s = start { out.append(s..<bytes.count) }
        return out
    }

    /// Throws unless every changed byte lies inside a range an operation was allowed to change.
    public func validate() throws {
        for r in changedRanges() {
            if allowed.contains(where: { $0.contains(r.lowerBound) && $0.contains(r.upperBound - 1) }) { continue }
            // A merged range can span several adjacent allowed pieces: check each byte.
            for i in r where !allowed.contains(where: { $0.contains(i) }) {
                throw Failure.refused(String(format: "Byte 0x%08X changed outside the planned edits. Stopped.", i))
            }
        }
        guard bytes.count == stock.count else { throw Failure.refused("The file size changed. Stopped.") }
    }

    /// Validates, then writes the file. Returns its CRC32 (screen form) for the install log.
    @discardableResult
    public func write(to path: String) throws -> UInt32 {
        try validate()
        try Data(bytes).write(to: URL(fileURLWithPath: path), options: .atomic)
        return Checksum.crc32Screen(bytes)
    }
}

/// Small colour helpers for ARGB4444 art.
public enum Art4444 {
    /// Recolours toward blue, keeping alpha and shading (the Mac-install test's "blue 1 key").
    public static func tintBlue(_ v: UInt16) -> UInt16 {
        let a = v >> 12, r = (v >> 8) & 15, g = (v >> 4) & 15, b = v & 15
        let light = (r + g + b) / 3
        return (a << 12) | ((light / 4) << 8) | ((light / 2 + 2) << 4) | 15
    }
}
