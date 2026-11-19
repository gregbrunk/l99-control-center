import CryptoKit
import Foundation

/// Builds a modified interface file (UartTFT-II_Flash.bin) from the stock one by replacing icon
/// artwork in place: same size, same format, same address. Nothing else in the file moves, so every
/// page, touch record and descriptor stays valid. Install the result with `l99probe isp-flash <file> --direct`.
///
/// Layout (research/FINDINGS.md, "Screen catalog"): header words 12 and 13 give the icon descriptor
/// table and the icon count per bank. Two banks (English, Chinese) follow each other; each descriptor
/// is 12 bytes: address u32, width u16, height u16, size u24 | format u8 << 24 (all little-endian).
public struct InterfaceFile {
    /// The stock file from the 2026.5.25 reset package.
    public static let stockSHA256 = InterfaceBlockTest.stockSHA256
    /// Art lives between the end of the descriptor tables and the photo slot; never patch outside it.
    public static let artRange = 0x0062_5000..<0x0400_0000

    public struct Icon: Equatable, Sendable {
        public let id: Int, address: Int, width: Int, height: Int, size: Int, format: Int
        public var byteRange: Range<Int> { address..<(address + size) }
    }

    public enum Failure: Error, CustomStringConvertible, Equatable {
        case notStock(String)
        case badIcon(String)
        case outsideArt(Int)
        public var description: String {
            switch self {
            case .notStock(let s): "Not the stock interface file: \(s)"
            case .badIcon(let s): s
            case .outsideArt(let a): String(format: "Refused: icon data at 0x%08X is outside the art area", a)
            }
        }
    }

    public let stock: [UInt8]
    public private(set) var bytes: [UInt8]
    public let iconTable: Int, iconCount: Int
    /// Icons replaced so far, so the diff check knows exactly what may differ.
    public private(set) var replaced: [Int] = []

    /// Loads the stock file and checks its SHA-256.
    public init(stockFile path: String) throws {
        guard let data = FileManager.default.contents(atPath: path) else { throw Failure.notStock("can't read \(path)") }
        try self.init(stockBytes: [UInt8](data))
    }

    public init(stockBytes: [UInt8]) throws {
        let digest = SHA256.hash(data: stockBytes).map { String(format: "%02x", $0) }.joined()
        guard digest == Self.stockSHA256 else { throw Failure.notStock("SHA-256 \(digest)") }
        stock = stockBytes; bytes = stockBytes
        iconTable = Int(Self.u32(stockBytes, 12 * 4)); iconCount = Int(Self.u32(stockBytes, 13 * 4))
    }

    static func u32(_ b: [UInt8], _ o: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(b[o + $1]) << (8 * $1) } }
    static func u16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }

    /// The icon's descriptor in a bank (0 = English, 1 = Chinese).
    public func icon(_ id: Int, bank: Int = 0) throws -> Icon {
        guard (0..<iconCount).contains(id), (0...1).contains(bank) else { throw Failure.badIcon("No icon \(id) in bank \(bank)") }
        let o = iconTable + (bank * iconCount + id) * 12
        let p = Self.u32(stock, o + 8)
        return Icon(id: id, address: Int(Self.u32(stock, o)), width: Self.u16(stock, o + 4), height: Self.u16(stock, o + 6),
                    size: Int(p & 0xFF_FFFF), format: Int(p >> 24))
    }

    /// The icon's current pixels as ARGB4444 or RGB565 words (formats 0–2 only).
    public func pixels(_ id: Int, bank: Int = 0) throws -> [UInt16] {
        let ic = try icon(id, bank: bank)
        guard (0...2).contains(ic.format), ic.size == ic.width * ic.height * 2 else {
            throw Failure.badIcon("Icon \(id) is format \(ic.format); only raw 16-bit icons can be replaced")
        }
        return stride(from: ic.address, to: ic.address + ic.size, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
    }

    /// Replaces an icon's pixels in place, in every bank that uses it. The new pixels must be the
    /// same count and in the icon's own format (format 2 = ARGB4444, 0/1 = RGB565).
    public mutating func replaceIcon(_ id: Int, pixels new: [UInt16]) throws {
        let ics = try (0...1).map { try icon(id, bank: $0) }
        for ic in ics {
            guard (0...2).contains(ic.format), ic.size == ic.width * ic.height * 2 else {
                throw Failure.badIcon("Icon \(id) is format \(ic.format); only raw 16-bit icons can be replaced")
            }
            guard new.count == ic.width * ic.height else {
                throw Failure.badIcon("Icon \(id) is \(ic.width)×\(ic.height); got \(new.count) pixels")
            }
            guard Self.artRange.contains(ic.address), Self.artRange.contains(ic.address + ic.size - 1) else {
                throw Failure.outsideArt(ic.address)
            }
        }
        // Refuse if another icon shares any of these bytes (an overlap would change that icon too).
        for ic in ics { try checkNotShared(ic) }
        for ic in Set(ics.map(\.address)).compactMap({ a in ics.first { $0.address == a } }) {
            for (i, v) in new.enumerated() {
                bytes[ic.address + 2 * i] = UInt8(v & 0xFF); bytes[ic.address + 2 * i + 1] = UInt8(v >> 8)
            }
        }
        if !replaced.contains(id) { replaced.append(id) }
    }

    func checkNotShared(_ ic: Icon) throws {
        for bank in 0...1 {
            for other in 0..<iconCount where other != ic.id {
                let o = try icon(other, bank: bank)
                guard o.size > 0, o.byteRange.overlaps(ic.byteRange) else { continue }
                throw Failure.badIcon("Icon \(ic.id)'s bytes are shared with icon \(other); not replacing")
            }
        }
    }

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

    /// Throws unless every changed byte lies inside a replaced icon's pixels.
    public func validate() throws {
        let allowed = try replaced.flatMap { id in try (0...1).map { try icon(id, bank: $0).byteRange } }
        for r in changedRanges() where !allowed.contains(where: { $0.contains(r.lowerBound) && $0.contains(r.upperBound - 1) }) {
            throw Failure.badIcon(String(format: "Bytes 0x%08X–0x%08X changed outside the replaced icons. Stopped.", r.lowerBound, r.upperBound - 1))
        }
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
