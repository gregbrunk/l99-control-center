import Foundation

/// READ-ONLY access to the screen's runtime variables over its serial port (research/FINDINGS.md,
/// "Mac-driven screen research"; approved by Alison Nov 18 as the one-time memory-map test).
/// Short frame: 5A A5 | len u8 (= body + 2) | body | CRC16/MODBUS LE. Read body: 03 | word addr BE16 | count BE16.
/// SAFETY: this type can only build read frames. There is deliberately no write (0x10) builder.
public enum RuntimeMemory {
    public static let commandRead: UInt8 = 0x03
    /// Words per read, so a reply stays well inside the parser's 64-byte frame limit.
    public static let maxWords = 16
    /// The only word ranges the map reads: user variables and the editor's system variables.
    public static let readable: [ClosedRange<UInt16>] = [0x0000...0x0FFF, 0x7000...0x703F]

    public enum Failure: Error, CustomStringConvertible, Equatable {
        case outOfRange(UInt16, Int)
        case badReply([UInt8])
        public var description: String {
            switch self {
            case .outOfRange(let a, let n): String(format: "Refusing a read outside the allowed ranges: 0x%04X + %d words", a, n)
            case .badReply(let b): "Unexpected reply to a memory read: \(b.map { String(format: "%02x", $0) }.joined(separator: " "))"
            }
        }
    }

    static func allowed(_ address: UInt16, _ count: Int) -> Bool {
        guard (1...maxWords).contains(count), Int(address) + count - 1 <= 0xFFFF else { return false }
        let last = address + UInt16(count - 1)
        return readable.contains { $0.contains(address) && $0.contains(last) }
    }

    public static func readFrame(address: UInt16, count: Int) throws -> [UInt8] {
        guard allowed(address, count) else { throw Failure.outOfRange(address, count) }
        let body: [UInt8] = [commandRead, UInt8(address >> 8), UInt8(address & 0xFF), UInt8(count >> 8), UInt8(count & 0xFF)]
        let crc = Checksum.crc16Modbus(body)
        return [0x5A, 0xA5, UInt8(body.count + 2)] + body + [UInt8(crc & 0xFF), UInt8(crc >> 8)]
    }

    /// The reply body echoes the command and address, then carries `count` BE16 words at its end.
    /// Returns nil for an ACK-only body (`03 FF`), which the caller skips.
    public static func words(fromReply body: [UInt8], address: UInt16, count: Int) throws -> [UInt16]? {
        if body == [commandRead, 0xFF] { return nil }
        guard body.count >= 3 + 2 * count, body[0] == commandRead,
              UInt16(body[1]) << 8 | UInt16(body[2]) == address else { throw Failure.badReply(body) }
        let data = Array(body.suffix(2 * count))
        return stride(from: 0, to: data.count, by: 2).map { UInt16(data[$0]) << 8 | UInt16(data[$0 + 1]) }
    }

    /// Every read of a full map, in order.
    public static func plan() -> [(address: UInt16, count: Int)] {
        var out = [(address: UInt16, count: Int)]()
        for r in readable {
            var a = Int(r.lowerBound)
            while a <= Int(r.upperBound) {
                let n = min(maxWords, Int(r.upperBound) - a + 1)
                out.append((UInt16(a), n)); a += n
            }
        }
        return out
    }

    // MARK: Marker matching

    /// A stats field sent with two distinctive values, A then B.
    public struct Field: Equatable, Sendable {
        public let name: String
        public let a: Int, b: Int
    }

    public static let fields: [Field] = [
        Field(name: "CPU load %", a: 61, b: 81), Field(name: "CPU °C", a: 62, b: 82),
        Field(name: "GPU load %", a: 63, b: 83), Field(name: "GPU °C", a: 64, b: 84),
        Field(name: "air temperature", a: 65, b: 85), Field(name: "day high", a: 66, b: 86),
        Field(name: "night low", a: 67, b: 87), Field(name: "weather code", a: 3, b: 4),
        Field(name: "humidity %", a: 68, b: 88),
    ]

    /// Sets the stats fields of `r` to marker set A (`second == false`) or B.
    public static func applyMarkers(_ r: inout Realtime, second: Bool) {
        let v = fields.map { second ? $0.b : $0.a }
        r.cpuLoad = v[0]; r.cpuTemp = v[1]; r.gpuLoad = v[2]; r.gpuTemp = v[3]
        r.airTemp = v[4]; r.dayHigh = v[5]; r.nightLow = v[6]; r.condition = v[7]; r.humidity = v[8]
    }

    public struct Match: Equatable, Sendable {
        public let field: String
        public let address: UInt16
        /// "word", "high byte" or "low byte".
        public let part: String
    }

    /// Addresses whose value is field.a in snapshot A and field.b in snapshot B.
    public static func matches(a: [UInt16: UInt16], b: [UInt16: UInt16]) -> [Match] {
        var out = [Match]()
        for f in fields {
            for address in a.keys.sorted() {
                guard let wa = a[address], let wb = b[address] else { continue }
                if Int(wa) == f.a && Int(wb) == f.b { out.append(Match(field: f.name, address: address, part: "word")) }
                else if Int(wa >> 8) == f.a && Int(wb >> 8) == f.b { out.append(Match(field: f.name, address: address, part: "high byte")) }
                else if Int(wa & 0xFF) == f.a && Int(wb & 0xFF) == f.b { out.append(Match(field: f.name, address: address, part: "low byte")) }
            }
        }
        return out
    }
}
