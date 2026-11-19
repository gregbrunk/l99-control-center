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

    // MARK: Display records (indicators and digit widgets)

    /// A display record: 5-byte header (`type u16, param u16, length u8`) then the payload.
    public struct DisplayRecord: Equatable, Sendable {
        public let offset: Int, type: Int, length: Int
    }

    public func displayRecords(page: Int) throws -> [DisplayRecord] {
        guard (0..<Self.pageCount).contains(page) else { throw Failure.refused("No page \(page)") }
        let e = pageTable + page * 12
        var p = Int(Self.u32(bytes, e)); let end = p + Self.u16(bytes, e + 4)
        var out = [DisplayRecord]()
        while p < end {
            let len = Int(bytes[p + 4] & 0x7F)
            out.append(DisplayRecord(offset: p + 5, type: Self.u16(bytes, p), length: len))
            p += 5 + len
        }
        guard p == end else { throw Failure.refused("Page \(page)'s display records don't add up. Stopped.") }
        return out
    }

    /// A state icon (type 3): `id, x, y, first icon, last icon, …`. One icon per state, first…last.
    public struct Indicator: Equatable, Sendable { public let offset: Int, id: Int, x: Int, y: Int, first: Int, last: Int }

    public func indicators(page: Int) throws -> [Indicator] {
        try displayRecords(page: page).filter { $0.type == 3 && $0.length == 14 }.map { r in
            let w = (0..<5).map { Self.u16(bytes, r.offset + 2 * $0) }
            return Indicator(offset: r.offset, id: w[0], x: w[1], y: w[2], first: w[3], last: w[4] == 0xFFFF ? w[3] : w[4])
        }
    }

    /// A number drawn from digit icons (type 4): `variable u16, flags u8, x u16 (right edge), y u16,
    /// digits u8, …, first digit icon u16 (0), last u16 (9)`.
    public struct DigitWidget: Equatable, Sendable { public let offset: Int, variable: Int, x: Int, y: Int, first: Int, last: Int }

    public func digitWidgets(page: Int) throws -> [DigitWidget] {
        try displayRecords(page: page).filter { $0.type == 4 && $0.length == 14 }.map { r in
            DigitWidget(offset: r.offset, variable: Self.u16(bytes, r.offset), x: Self.u16(bytes, r.offset + 3), y: Self.u16(bytes, r.offset + 5),
                        first: Self.u16(bytes, r.offset + 10), last: Self.u16(bytes, r.offset + 12))
        }
    }

    /// Icons a record may point at must already hold art (placed first).
    func checkHasArt(_ ids: ClosedRange<Int>) throws {
        for id in ids {
            let a = try icon(id, bank: 0), b = try icon(id, bank: 1)
            guard a.width > 0, a.height > 0, a == b else { throw Failure.refused("Icon \(id) has no art yet (or differs between banks); place it first") }
        }
    }

    /// Moves a page's state icon (found by the first icon it uses now, which is unique; ids repeat)
    /// and points it at new icons, keeping the same number of states.
    /// Only this page changes, so other pages keep the shared stock icons.
    public mutating func setIndicator(page: Int, using current: Int, x: Int, y: Int, first: Int) throws {
        let all = try indicators(page: page).filter { $0.first == current }
        guard all.count == 1, let r = all.first else { throw Failure.refused("Page \(page) has \(all.count) indicators using icon \(current); expected 1") }
        let id = r.id
        let n = r.last - r.first, last = first + n
        guard x >= 0, y >= 0, x < 320, y < 480 else { throw Failure.refused("Indicator \(id): (\(x), \(y)) is off screen") }
        try checkHasArt(first...last)
        let single = Self.u16(bytes, r.offset + 8) == 0xFFFF
        put16(r.offset + 2, x); put16(r.offset + 4, y); put16(r.offset + 6, first)
        if !single { put16(r.offset + 8, last) }
        allowed.append((r.offset + 2)..<(r.offset + 10))
        log.append("page \(page) indicator \(id): icons \(r.first)–\(r.last) at (\(r.x),\(r.y)) → \(first)–\(last) at (\(x),\(y))")
    }

    /// Moves a page's digit widget for `variable` and points it at ten new digit icons (0…9).
    public mutating func setDigits(page: Int, variable: Int, x: Int, y: Int, first: Int) throws {
        let all = try digitWidgets(page: page).filter { $0.variable == variable }
        guard all.count == 1, let r = all.first else { throw Failure.refused("Page \(page) has \(all.count) digit widgets for 0x\(String(variable, radix: 16)); expected 1") }
        guard r.last - r.first == 9 else { throw Failure.refused("Digit widget 0x\(String(variable, radix: 16)) doesn't use ten icons; not changing it") }
        guard x > 0, y >= 0, x < 320, y < 480 else { throw Failure.refused("Digits: (\(x), \(y)) is off screen") }
        try checkHasArt(first...(first + 9))
        put16(r.offset + 3, x); put16(r.offset + 5, y); put16(r.offset + 10, first); put16(r.offset + 12, first + 9)
        allowed.append((r.offset + 3)..<(r.offset + 7)); allowed.append((r.offset + 10)..<(r.offset + 14))
        log.append("page \(page) digits 0x\(String(variable, radix: 16)): icons \(r.first)–\(r.last) right edge (\(r.x),\(r.y)) → \(first)–\(first + 9) at (\(x),\(y))")
    }

    /// The top-bar clock (type 6): `x u16, y u16, first icon u16, last icon u16, glyphs u8`.
    /// Stock: (12, 10), icons 30–43 (digits 0–9 then four colon frames), 5 glyphs "HH:MM".
    public struct Clock: Equatable, Sendable { public let offset: Int, x: Int, y: Int, first: Int, last: Int, glyphs: Int }

    public func clocks(page: Int) throws -> [Clock] {
        try displayRecords(page: page).filter { $0.type == 6 && $0.length == 9 }.map { r in
            Clock(offset: r.offset, x: Self.u16(bytes, r.offset), y: Self.u16(bytes, r.offset + 2),
                  first: Self.u16(bytes, r.offset + 4), last: Self.u16(bytes, r.offset + 6), glyphs: Int(bytes[r.offset + 8]))
        }
    }

    /// Moves a page's clock and points it at a new run of icons (same count as now).
    public mutating func setClock(page: Int, x: Int, y: Int, first: Int) throws {
        let all = try clocks(page: page)
        guard all.count == 1, let r = all.first else { throw Failure.refused("Page \(page) has \(all.count) clocks; expected 1") }
        guard x >= 0, y >= 0, x < 320, y < 480 else { throw Failure.refused("Clock: (\(x), \(y)) is off screen") }
        let last = first + (r.last - r.first)
        try checkHasArt(first...last)
        put16(r.offset, x); put16(r.offset + 2, y); put16(r.offset + 4, first); put16(r.offset + 6, last)
        allowed.append(r.offset..<(r.offset + 8))
        log.append("page \(page) clock: icons \(r.first)–\(r.last) at (\(r.x),\(r.y)) → \(first)–\(last) at (\(x),\(y))")
    }

    /// Icon slots with no art (0×0) in both banks. Whether a record still refers to one is the caller's check.
    public func emptySlots() throws -> [Int] {
        try (0..<iconCount).filter { id in
            let a = try icon(id, bank: 0), b = try icon(id, bank: 1)
            return a.width == 0 && a.height == 0 && a.size == 0 && b == a
        }
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
