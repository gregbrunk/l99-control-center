import Foundation
import L99Core

/// Runs an upload or a slot check over the screen's serial port, using the bounds-checked
/// plans from `ScreenProtocol`. Stops at the first unexpected reply or CRC mismatch.
public enum ScreenTransfer {
    public struct Progress: Sendable {
        public let bytesDone: Int
        public let bytesTotal: Int
        public var fraction: Double { bytesTotal == 0 ? 0 : Double(bytesDone) / Double(bytesTotal) }
    }

    public enum Result: Sendable, Equatable {
        case completed
        /// Stopped between two writes because `shouldContinue` returned false. The slot is incomplete.
        case cancelled
    }

    /// Writes `payload` into `slot`. `shouldContinue` is called after every write with the progress so far;
    /// return false to stop safely between two writes. Throws on any device error or CRC mismatch.
    public static func upload(_ payload: [UInt8], to slot: ScreenProtocol.Slot, port: ScreenPort,
                              shouldContinue: (Progress) -> Bool) throws -> Result {
        let plan = try ScreenProtocol.uploadPlan(slot: slot, byteCount: payload.count)
        var done = 0
        for step in plan {
            switch step {
            case .write(let address, let range):
                _ = try port.request(ScreenProtocol.commandWrite, address: address, data: Array(payload[range]))
                done += range.count
                if !shouldContinue(Progress(bytesDone: done, bytesTotal: payload.count)) { return .cancelled }
            case .check(let address, let range):
                let got = try regionCRC(port: port, address: address, length: range.count)
                let expected = Checksum.crc32Screen(payload[range])
                guard got == expected else {
                    throw LinkError(String(format: "The screen stored different data than was sent (region 0x%08X: %08X, expected %08X). Stopped.",
                                           address, got, expected))
                }
            }
        }
        return .completed
    }

    /// Asks the screen for the CRC32 of each region `payload` would occupy and compares.
    /// Sends only 0x66 checks, never a write. True when every region matches.
    public static func verify(_ payload: [UInt8], in slot: ScreenProtocol.Slot, port: ScreenPort,
                              shouldContinue: (Progress) -> Bool = { _ in true }) throws -> Bool {
        var done = 0
        for case .check(let address, let range) in try ScreenProtocol.verifyPlan(slot: slot, byteCount: payload.count) {
            let got = try regionCRC(port: port, address: address, length: range.count)
            if got != Checksum.crc32Screen(payload[range]) { return false }
            done += range.count
            if !shouldContinue(Progress(bytesDone: done, bytesTotal: payload.count)) { return false }
        }
        return true
    }

    static func regionCRC(port: ScreenPort, address: UInt32, length: Int) throws -> UInt32 {
        let reply = try port.request(ScreenProtocol.commandCheck, address: address, data: ScreenProtocol.checkData(length: length))
        guard reply.count == 9 else { throw LinkError("Unexpected reply to a region check (\(reply.count) bytes). Stopped.") }
        return ScreenProtocol.beValue(reply[5..<9])
    }
}
