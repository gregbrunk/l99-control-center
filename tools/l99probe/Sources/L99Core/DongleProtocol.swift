import Foundation

/// 2.4 GHz dongle (05AC:024F) packets: 32-byte output reports, report ID 0,
/// layout `cmd len seq data… checksum` with checksum = sum(bytes 0...30) & 0xFF.
/// SAFETY: only read-only queries (0x02 session-init, 0x20 battery) and the volatile
/// clock packet (0x0C) exist here.
public enum DongleProtocol {
    public static let size = 32

    static func finalize(_ body: [UInt8]) -> [UInt8] {
        precondition(body.count == size - 1)
        return body + [Checksum.dongleSum(body)]
    }

    /// Read-only. Reply byte 11 is a build/version byte (0x29 on gavindi's L99 dongle).
    public static var sessionInit: [UInt8] {
        var b = [UInt8](repeating: 0, count: 31); b[0] = 0x02; return finalize(b)
    }
    /// Read-only. Reply `20 01 00 <battery %> …`. No reply = keyboard asleep/off.
    public static var batteryQuery: [UInt8] {
        var b = [UInt8](repeating: 0, count: 31); b[0] = 0x20; b[1] = 0x01; return finalize(b)
    }

    public enum ClockLayout: String, CaseIterable {
        /// Prior art (AULA F75 MAX / AulaToolkit), ACKed by the L99 dongle: clock only.
        /// Cable fields shifted +3, trailer AA 55 at 17–18.
        case prior
        /// Revisory676: cable block +3 throughout, stats at 16–24, trailer at 25–26.
        /// CONFIRMED on hardware Nov 17, 2026 (dongle build 0x31): clock, CPU %, GPU %, air temp and humidity all displayed.
        case plus3
        /// Vendor DeviceDriver.exe dongle path per gavindi: +4, stats at 17–25, trailer at 26–27. Untested.
        case plus4
    }

    public static func clock(_ r: Realtime, layout: ClockLayout) throws -> [UInt8] {
        let f = try r.cableFields()          // indices = cable offsets 0...21
        var b = [UInt8](repeating: 0, count: 31)
        b[0] = 0x0C; b[1] = 0x10; b[2] = 0x00
        switch layout {
        case .prior:
            for i in 1...10 { b[i + 3] = f[i] }   // view, tag, Y M D h m s, (9), weekday
            b[17] = 0xAA; b[18] = 0x55
        case .plus3, .plus4:
            let shift = layout == .plus3 ? 3 : 4
            for i in 1...21 { b[i + shift] = f[i] }
            b[22 + shift] = 0xAA; b[23 + shift] = 0x55
        }
        return finalize(b)
    }

    /// Music spectrum over the dongle, as built by AULA DeviceDriver.exe v1.0.1.6 (code at 0x43b818–0x43b888,
    /// taken when the connection type is 2 = dongle):
    /// `0B 1C 00 | fore-mode back-mode amplitude | 21 levels | 00 00 00 00 | checksum`.
    /// The vendor sends it without waiting for a reply. `levels` are 0...1, scaled to 0–99.
    public static let musicBands = 21
    public static func music(levels: [Double], foreMode: UInt8 = 2, backMode: UInt8 = 0, amplitude: UInt8 = 35) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 31)
        b[0] = 0x0B; b[1] = 0x1C; b[2] = 0x00
        b[3] = foreMode; b[4] = backMode; b[5] = amplitude
        for i in 0..<musicBands {
            let x = i < levels.count ? levels[i] : 0
            b[6 + i] = UInt8((Swift.min(1, Swift.max(0, x)) * 99).rounded())
        }
        return finalize(b)
    }

    /// Replies echo bytes 0–2 of the request.
    public static func isReply(_ reply: [UInt8], to request: [UInt8]) -> Bool {
        reply.count >= 3 && reply[0] == request[0] && reply[1] == request[1] && reply[2] == request[2]
    }
    public static func checksumOK(_ reply: [UInt8]) -> Bool {
        reply.count == size && reply[31] == Checksum.dongleSum(reply[0..<31])
    }
}
