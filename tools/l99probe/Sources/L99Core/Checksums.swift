import Foundation

public enum Checksum {
    /// CRC-16/MODBUS: reflected poly 0xA001, init 0xFFFF, no final XOR.
    /// Used by the screen's 5A A5 frames and by the 11-byte image header.
    public static func crc16Modbus<C: Collection>(_ bytes: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        if let fast: UInt16 = bytes.withContiguousStorageIfAvailable({ buffer in
            var c: UInt16 = 0xFFFF
            for b in buffer { c = (c >> 8) ^ crc16Table[Int((c ^ UInt16(b)) & 0xFF)] }
            return c
        }) { return fast }
        for b in bytes { crc = (crc >> 8) ^ crc16Table[Int((crc ^ UInt16(b)) & 0xFF)] }
        return crc
    }

    private static let crc16Table: [UInt16] = (0..<256).map { i in
        var c = UInt16(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xA001 : c >> 1 }
        return c
    }

    /// The screen's region checksum (reply to command 0x66):
    /// reflected poly 0xEDB88320, init 0, no final XOR.
    /// `initial` continues a running CRC over consecutive pieces.
    public static func crc32Screen<C: Collection>(_ bytes: C, initial: UInt32 = 0) -> UInt32 where C.Element == UInt8 {
        if let fast: UInt32 = bytes.withContiguousStorageIfAvailable({ buffer in
            var c: UInt32 = initial
            for b in buffer { c = (c >> 8) ^ crc32Table[Int((c ^ UInt32(b)) & 0xFF)] }
            return c
        }) { return fast }
        var crc: UInt32 = initial
        for b in bytes { crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(b)) & 0xFF)] }
        return crc
    }

    private static let crc32Table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
        return c
    }

    /// 2.4 GHz dongle frame checksum: sum of bytes 0...30, low byte.
    public static func dongleSum<C: Collection>(_ bytes: C) -> UInt8 where C.Element == UInt8 {
        UInt8(truncatingIfNeeded: bytes.reduce(0) { $0 &+ Int($1) })
    }
}

public extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}

public extension ArraySlice where Element == UInt8 {
    var hex: String { Array(self).hex }
}
