import CryptoKit
import Foundation

/// The Mac skin-install test (research/MAC_INSTALL_TEST.md, approved by Alison Nov 18).
/// Rewrites ONE 128 KiB block of the interface art: block 0x3B, which holds only Mini Numpad key art.
/// The only change ever allowed inside it is the pixel data of icon 341 (the Numpad "1" key, normal state).
/// This is a separate allowlist from `ScreenProtocol.Slot`; nothing else in the interface area may be written.
public enum InterfaceBlockTest {
    public static let blockBase: UInt32 = 0x0076_0000
    public static let blockSize = ScreenProtocol.checkRegion                  // 0x20000, one check region
    /// The stock interface file this test is built from (the 2026.5.25 reset package).
    public static let stockSHA256 = "4cb3fa5c77eea973a2b62ca61873f071692694f4c9a1832507fe2c8c9ba582b4"

    /// Icon 341: 67×67 ARGB4444 at 0x0077C446, 8,978 bytes, the same in both language banks.
    public static let iconID = 341
    public static let iconAddress: UInt32 = 0x0077_C446
    public static let iconBytes = 67 * 67 * 2
    /// The icon's bytes as offsets inside the block.
    public static var iconRange: Range<Int> {
        let start = Int(iconAddress - blockBase)
        return start..<(start + iconBytes)
    }
    static let descriptorTable = 0x0062_2A84
    static let iconCount = 569
    /// The 12-byte descriptor icon 341 must have in both banks: offset, 67, 67, size 8978, format 2.
    static let expectedDescriptor: [UInt8] = [0x46, 0xC4, 0x77, 0x00, 0x43, 0x00, 0x43, 0x00, 0x12, 0x23, 0x00, 0x02]

    public enum Variant: String, CaseIterable, Sendable {
        /// A: the block exactly as in the stock file (no visible change). C: putting it back.
        case stock
        /// B: the "1" key tinted blue.
        case blue
    }

    public enum Failure: Error, CustomStringConvertible, Equatable {
        case wrongFile(String)
        case wrongLayout
        case badBlock(String)
        public var description: String {
            switch self {
            case .wrongFile(let s): "Not the stock interface file: \(s)"
            case .wrongLayout: "Icon 341's descriptor isn't where the test expects it. Stopped."
            case .badBlock(let s): "Block refused: \(s)"
            }
        }
    }

    /// Reads the stock block from the interface file after checking the file's SHA-256 and icon 341's descriptors.
    public static func stockBlock(flashFile path: String) throws -> [UInt8] {
        guard let data = FileManager.default.contents(atPath: path) else { throw Failure.wrongFile("can't read \(path)") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == stockSHA256 else { throw Failure.wrongFile("SHA-256 \(digest)") }
        let bytes = [UInt8](data)
        for bank in 0..<2 {
            let o = descriptorTable + (bank * iconCount + iconID) * 12
            guard Array(bytes[o..<(o + 12)]) == expectedDescriptor else { throw Failure.wrongLayout }
        }
        let start = Int(blockBase)
        return Array(bytes[start..<(start + blockSize)])
    }

    /// The block for a variant, already validated against the stock block.
    public static func block(_ variant: Variant, stock: [UInt8]) throws -> [UInt8] {
        guard stock.count == blockSize else { throw Failure.badBlock("stock block is \(stock.count) bytes") }
        var out = stock
        if variant == .blue {
            for i in stride(from: iconRange.lowerBound, to: iconRange.upperBound, by: 2) {
                let v = UInt16(out[i]) | UInt16(out[i + 1]) << 8
                let a = v >> 12, r = (v >> 8) & 15, g = (v >> 4) & 15, b = v & 15
                let light = (r + g + b) / 3
                // Keep alpha and shading; push the colour to blue.
                let t = (a << 12) | ((light / 4) << 8) | ((light / 2 + 2) << 4) | 15
                out[i] = UInt8(t & 0xFF); out[i + 1] = UInt8(t >> 8)
            }
        }
        try validate(out, stock: stock)
        return out
    }

    /// Throws unless `candidate` is a full block that differs from stock only inside icon 341.
    public static func validate(_ candidate: [UInt8], stock: [UInt8]) throws {
        guard candidate.count == blockSize, stock.count == blockSize else {
            throw Failure.badBlock("must be exactly \(blockSize) bytes, got \(candidate.count)")
        }
        let icon = iconRange
        for i in 0..<blockSize where candidate[i] != stock[i] && !icon.contains(i) {
            throw Failure.badBlock(String(format: "byte at 0x%08X differs from stock outside icon 341", Int(blockBase) + i))
        }
    }

    /// 64 writes of 2048 bytes, then one 0x66 check of the whole block, all inside block 0x3B.
    public static func plan() -> [ScreenProtocol.Step] {
        var steps = [ScreenProtocol.Step]()
        for offset in stride(from: 0, to: blockSize, by: ScreenProtocol.maxChunk) {
            steps.append(.write(address: blockBase + UInt32(offset), range: offset..<(offset + ScreenProtocol.maxChunk)))
        }
        steps.append(.check(address: blockBase, range: 0..<blockSize))
        for step in steps {
            switch step {
            case .write(let a, let r), .check(let a, let r):
                precondition(a >= blockBase && Int(a - blockBase) + r.count <= blockSize, "step outside block 0x3B")
            }
        }
        return steps
    }
}
