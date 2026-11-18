import Foundation

/// One 64-byte feature report on the wired keyboard (0C45:800A), plus whether
/// the keyboard answers it with an ACK (bytes 0–1 echo, byte 3 == 0x01).
public struct WiredReport: Equatable {
    public let bytes: [UInt8]
    public let expectsAck: Bool
}

/// Fields for the clock/stats block (op 0x28). All one byte each.
public struct Realtime: Equatable {
    public var year, month, day, hour, minute, second, weekday: Int   // weekday: Sunday = 0
    public var cpuLoad = 0, cpuTemp = 0, gpuLoad = 0, gpuTemp = 0
    public var airTemp = 0, dayHigh = 0, nightLow = 0, condition = 0, humidity = 0

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        year = c.year!; month = c.month!; day = c.day!
        hour = c.hour!; minute = c.minute!; second = c.second!
        weekday = c.weekday! - 1
    }
    public init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, weekday: Int) {
        self.year = year; self.month = month; self.day = day
        self.hour = hour; self.minute = minute; self.second = second; self.weekday = weekday
    }

    /// The smoke-test values: distinctive, easy to spot on the Real-time page.
    public mutating func applyTestStats() {
        cpuLoad = 42; cpuTemp = 61; gpuLoad = 17; gpuTemp = 55
        airTemp = 23; dayHigh = 27; nightLow = 12; condition = 1; humidity = 45
    }

    /// The 21 meaningful bytes, laid out as in the cable block (offsets 1...21).
    /// Index 0 of the returned array corresponds to cable offset 0.
    func cableFields() throws -> [UInt8] {
        guard (2000...2255).contains(year), (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second),
              (0...6).contains(weekday) else { throw KeyboardProtocol.Failure.invalid("date/time") }
        for (v, name) in [(cpuLoad, "cpu"), (gpuLoad, "gpu"), (humidity, "humidity")] where !(0...100).contains(v) {
            throw KeyboardProtocol.Failure.invalid(name)
        }
        for v in [cpuTemp, gpuTemp, airTemp, dayHigh, nightLow] where !(-128...255).contains(v) {
            throw KeyboardProtocol.Failure.invalid("temperature")
        }
        guard (0...5).contains(condition) else { throw KeyboardProtocol.Failure.invalid("condition") }
        var f = [UInt8](repeating: 0, count: 22)
        f[1] = 0x01            // view (must be ≥ 1)
        f[2] = 0x5A            // tag
        f[3] = UInt8(year - 2000); f[4] = UInt8(month); f[5] = UInt8(day)
        f[6] = UInt8(hour); f[7] = UInt8(minute); f[8] = UInt8(second)
        f[10] = UInt8(weekday)
        f[13] = UInt8(cpuLoad); f[14] = UInt8(truncatingIfNeeded: cpuTemp)
        f[15] = UInt8(gpuLoad); f[16] = UInt8(truncatingIfNeeded: gpuTemp)
        f[17] = UInt8(truncatingIfNeeded: airTemp); f[18] = UInt8(truncatingIfNeeded: dayHigh)
        f[19] = UInt8(truncatingIfNeeded: nightLow); f[20] = UInt8(condition); f[21] = UInt8(humidity)
        return f
    }
}

/// Wired keyboard packets. SAFETY: only volatile opcodes exist here —
/// 0x18 begin, 0x02 commit/end, 0x28 clock+stats, 0x78 music. No keymap, lighting,
/// settings or 0xF0 persistent writes.
public enum KeyboardProtocol {
    public enum Failure: Error, CustomStringConvertible {
        case invalid(String)
        public var description: String { if case .invalid(let s) = self { return "Invalid value: \(s)" }; return "" }
    }

    static let opBegin: UInt8 = 0x18, opCommit: UInt8 = 0x02, opRealtime: UInt8 = 0x28, opMusic: UInt8 = 0x78
    public static let allowedOpcodes: Set<UInt8> = [opBegin, opCommit, opRealtime, opMusic]

    static func command(_ op: UInt8, blocks: UInt8 = 0) -> WiredReport {
        precondition(allowedOpcodes.contains(op))
        var b = [UInt8](repeating: 0, count: 64)
        b[0] = 0x04; b[1] = op; b[8] = blocks
        return WiredReport(bytes: b, expectsAck: true)
    }

    /// 04 18 → 04 28 [8]=1 → data block (no ACK) → 04 02. Matches AxiraDev's captured fixture.
    public static func realtime(_ r: Realtime) throws -> [WiredReport] {
        var block = [UInt8](repeating: 0, count: 64)
        let f = try r.cableFields()
        block.replaceSubrange(0..<f.count, with: f)
        block[62] = 0xAA; block[63] = 0x55
        return [command(opBegin), command(opRealtime, blocks: 1), WiredReport(bytes: block, expectsAck: false), command(opCommit)]
    }

    public enum MusicLayout: String, CaseIterable { case gavindi, axira }

    /// One music frame. `levels` are 0...1 and get scaled per layout.
    /// - gavindi: 04 02 → 04 78 [8]=1 → [rhythm 4, bg 8, scale 0x64, 23 levels 0–100, …, [26]=0]
    /// - axira:   04 18 → 04 78 [8]=1 → [scheme 2, bg 0, brightness 35, 18 levels 0–99] → 04 02
    /// `foreMode`/`backMode` (axira layout): the key-light visualiser up from the bottom / down from the top, as over the dongle.
    public static func music(levels: [Double], layout: MusicLayout, foreMode: UInt8 = 2, backMode: UInt8 = 0) -> [WiredReport] {
        var block = [UInt8](repeating: 0, count: 64)
        func scaled(_ x: Double, _ max: Double) -> UInt8 { UInt8((Swift.min(1, Swift.max(0, x)) * max).rounded()) }
        switch layout {
        case .gavindi:
            block[0] = 0x04; block[1] = 0x08; block[2] = 0x64
            for i in 0..<23 { block[3 + i] = scaled(i < levels.count ? levels[i] : 0, 100) }
            return [command(opCommit), command(opMusic, blocks: 1), WiredReport(bytes: block, expectsAck: false)]
        case .axira:
            block[0] = foreMode; block[1] = backMode; block[2] = 35
            for i in 0..<18 { block[3 + i] = scaled(i < levels.count ? levels[i] : 0, 99) }
            return [command(opBegin), command(opMusic, blocks: 1), WiredReport(bytes: block, expectsAck: false), command(opCommit)]
        }
    }

    public static func isAck(_ reply: [UInt8], for report: WiredReport) -> Bool {
        reply.count >= 4 && reply[0] == report.bytes[0] && reply[1] == report.bytes[1] && reply[3] == 0x01
    }
    public static func isBusy(_ reply: [UInt8], for report: WiredReport) -> Bool {
        reply.count >= 4 && reply[0] == report.bytes[0] && reply[1] == report.bytes[1] && reply[3] == 0xFF
    }
}
