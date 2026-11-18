import Foundation

/// The screen's animation format at the GIF slot (0x04240000). See FINDINGS.md, Q9.
///
///     TOC: one 20-byte LE entry per frame
///       [0:4] frame offset from blob start   [4:8] total bytes of all frames (TOC not included)
///       [8:10] w  [10:12] h  [12] = 3  [13] frame count  [14:16] = 0
///       [16:18] delay (same for every frame)  [18:20] CRC16/MODBUS over all frames
///     Frame: 528-byte prefix, then content
///       "LT" w h 01 03 | [8:12] frame size | [12:14] content length mod 65536
///       [14:16] mode 0x0100 RLE / 0x0002 raw | [16..] palette RGB565 LE (first appearance, ≤256), zero padded
///     RLE content: (run length − 1, palette index) pairs, runs split at 256.
///     Raw content: one palette index per pixel, used when RLE would exceed 0xFFFF bytes.
///
/// Validator rules found by experiment: every frame has the same delay; at most 255 frames;
/// adjacent runs never share a palette index (true by construction: runs merge equal colours,
/// and the 256-pixel split pieces of one run are what the vendor emits too).
public enum GIFContainer {
    public static let prefixSize = 528
    public static let tocEntrySize = 20
    public static let maxPaletteColors = (prefixSize - 16) / 2      // 256
    public static let formatMaxFrames = 255
    /// The vendor app's own cap; we follow it.
    public static let maxFrames = 200
    public static let modeRLE: UInt16 = 0x0100
    public static let modeRaw: UInt16 = 0x0002

    public enum Failure: Error, CustomStringConvertible, Equatable {
        case noFrames
        case tooManyFrames(Int)
        case wrongFrameSize(frame: Int, pixels: Int)
        case tooManyColors(frame: Int, colors: Int)
        case unequalDelays
        case badDelay(Int)
        case tooLarge(Int)
        case malformed(String)

        public var description: String {
            switch self {
            case .noFrames: "The animation has no frames."
            case .tooManyFrames(let n): "\(n) frames is more than the screen accepts (\(GIFContainer.maxFrames))."
            case .wrongFrameSize(let f, let p): "Frame \(f + 1) has \(p) pixels instead of 320 × 480."
            case .tooManyColors(let f, let c): "Frame \(f + 1) has \(c) colours; the screen allows \(GIFContainer.maxPaletteColors)."
            case .unequalDelays: "Every frame must use the same delay."
            case .badDelay(let d): "Frame delay \(d) is out of range."
            case .tooLarge(let n): "The animation is \(n) bytes; the limit is \(ScreenProtocol.gifMaxBytes)."
            case .malformed(let s): "Not a valid screen animation: \(s)"
            }
        }
    }

    /// One frame of RGB565 pixels, row-major, `ScreenProtocol.width × height`.
    public typealias Frame = [UInt16]

    // MARK: Encode

    /// Builds the slot blob. `delay` is in the TOC's own unit (the factory animation uses 50).
    public static func encode(frames: [Frame], delay: Int,
                              width: Int = ScreenProtocol.width, height: Int = ScreenProtocol.height) throws -> [UInt8] {
        guard !frames.isEmpty else { throw Failure.noFrames }
        guard frames.count <= maxFrames else { throw Failure.tooManyFrames(frames.count) }
        guard (1...0xFFFF).contains(delay) else { throw Failure.badDelay(delay) }
        let pixelCount = width * height

        var payload = [UInt8]()
        var frameOffsets = [Int]()
        for (index, frame) in frames.enumerated() {
            guard frame.count == pixelCount else { throw Failure.wrongFrameSize(frame: index, pixels: frame.count) }
            frameOffsets.append(payload.count)
            payload += try encodeFrame(frame, index: index, width: width, height: height)
        }

        let tocSize = tocEntrySize * frames.count
        let total = tocSize + payload.count
        guard total <= ScreenProtocol.gifMaxBytes else { throw Failure.tooLarge(total) }
        let crc = Checksum.crc16Modbus(payload)

        var blob = [UInt8]()
        blob.reserveCapacity(total)
        for offset in frameOffsets {
            blob += ScreenProtocol.le32(UInt32(tocSize + offset))
            blob += ScreenProtocol.le32(UInt32(payload.count))
            blob += ScreenProtocol.le16(UInt16(width))
            blob += ScreenProtocol.le16(UInt16(height))
            blob.append(3)
            blob.append(UInt8(frames.count))
            blob += [0, 0]
            blob += ScreenProtocol.le16(UInt16(delay))
            blob += ScreenProtocol.le16(crc)
        }
        blob += payload
        return blob
    }

    static func encodeFrame(_ pixels: Frame, index: Int, width: Int, height: Int) throws -> [UInt8] {
        // Runs in raster order, palette in order of first appearance.
        var palette = [UInt16]()
        var paletteIndex = [UInt16: UInt8]()
        var runs = [(length: Int, color: UInt16)]()
        var i = 0
        while i < pixels.count {
            let color = pixels[i]
            var j = i + 1
            while j < pixels.count && pixels[j] == color { j += 1 }
            runs.append((j - i, color))
            if paletteIndex[color] == nil {
                guard palette.count < maxPaletteColors else {
                    throw Failure.tooManyColors(frame: index, colors: Set(pixels).count)
                }
                paletteIndex[color] = UInt8(palette.count)
                palette.append(color)
            }
            i = j
        }

        let tokenCount = runs.reduce(0) { $0 + ($1.length + 255) / 256 }
        let raw = tokenCount * 2 > 0xFFFF
        var content = [UInt8]()
        if raw {
            content = pixels.map { paletteIndex[$0]! }
        } else {
            content.reserveCapacity(tokenCount * 2)
            for run in runs {
                let flag = paletteIndex[run.color]!
                var remaining = run.length
                while remaining > 0 {
                    let take = min(256, remaining)
                    content.append(UInt8(take - 1))
                    content.append(flag)
                    remaining -= take
                }
            }
        }

        var prefix = [UInt8](repeating: 0, count: prefixSize)
        prefix[0] = 0x4C; prefix[1] = 0x54                       // "LT"
        prefix.replaceSubrange(2..<4, with: ScreenProtocol.le16(UInt16(width)))
        prefix.replaceSubrange(4..<6, with: ScreenProtocol.le16(UInt16(height)))
        prefix[6] = 0x01; prefix[7] = 0x03
        prefix.replaceSubrange(8..<12, with: ScreenProtocol.le32(UInt32(prefixSize + content.count)))
        prefix.replaceSubrange(12..<14, with: ScreenProtocol.le16(UInt16(content.count % 65536)))
        prefix.replaceSubrange(14..<16, with: ScreenProtocol.le16(raw ? modeRaw : modeRLE))
        for (n, color) in palette.enumerated() {
            prefix.replaceSubrange((16 + 2 * n)..<(18 + 2 * n), with: ScreenProtocol.le16(color))
        }
        return prefix + content
    }

    // MARK: Decode

    public struct Info: Equatable, Sendable {
        public var frameCount: Int
        public var width: Int
        public var height: Int
        public var delay: Int
        public var byteCount: Int
    }

    /// Reads and checks the TOC (sizes, offsets, equal delays, CRC). Does not decode pixels.
    public static func info(_ blob: [UInt8]) throws -> Info {
        func u16(_ o: Int) -> Int { Int(blob[o]) | Int(blob[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard blob.count >= tocEntrySize else { throw Failure.malformed("too short") }
        let count = Int(blob[13])
        guard count > 0, count <= formatMaxFrames, blob.count >= count * tocEntrySize else { throw Failure.malformed("bad frame count") }
        let tocSize = count * tocEntrySize
        let total = u32(4)
        guard tocSize + total == blob.count else { throw Failure.malformed("size field \(total) doesn't match \(blob.count - tocSize)") }
        let delay = u16(16), crc = u16(18), width = u16(8), height = u16(10)
        for f in 0..<count {
            let e = f * tocEntrySize
            guard u32(e + 4) == total, u16(e + 8) == width, u16(e + 10) == height, blob[e + 12] == 3,
                  Int(blob[e + 13]) == count, u16(e + 18) == crc else { throw Failure.malformed("TOC entry \(f) disagrees") }
            guard u16(e + 16) == delay else { throw Failure.unequalDelays }
            let offset = u32(e)
            guard offset >= tocSize, offset + prefixSize <= blob.count,
                  blob[offset] == 0x4C, blob[offset + 1] == 0x54 else { throw Failure.malformed("frame \(f) header") }
        }
        guard Int(Checksum.crc16Modbus(blob[tocSize...])) == crc else { throw Failure.malformed("CRC mismatch") }
        return Info(frameCount: count, width: width, height: height, delay: delay, byteCount: blob.count)
    }

    /// Decodes one frame to RGB565 pixels, after checking the whole blob.
    public static func decodeFrame(_ blob: [UInt8], index: Int) throws -> Frame {
        let info = try info(blob)
        guard index >= 0, index < info.frameCount else { throw Failure.malformed("no frame \(index)") }
        return try frame(at: index, in: blob)
    }

    /// Decodes every frame, checking the blob once.
    public static func decodeAll(_ blob: [UInt8]) throws -> [Frame] {
        let info = try info(blob)
        return try (0..<info.frameCount).map { try frame(at: $0, in: blob) }
    }

    /// Assumes `info(blob)` already passed.
    static func frame(at index: Int, in blob: [UInt8]) throws -> Frame {
        func u16(_ o: Int) -> Int { Int(blob[o]) | Int(blob[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        let offset = u32(index * tocEntrySize)
        let width = u16(offset + 2), height = u16(offset + 4)
        let frameSize = u32(offset + 8)
        let mode = UInt16(u16(offset + 14))
        guard offset + frameSize <= blob.count else { throw Failure.malformed("frame \(index) runs past the end") }
        let palette = (0..<maxPaletteColors).map { UInt16(u16(offset + 16 + 2 * $0)) }
        let pixelCount = width * height
        let content = blob[(offset + prefixSize)..<(offset + frameSize)]
        var out = Frame()
        out.reserveCapacity(pixelCount)
        if mode == modeRaw {
            guard content.count >= pixelCount else { throw Failure.malformed("raw frame \(index) too short") }
            for b in content.prefix(pixelCount) { out.append(palette[Int(b)]) }
        } else {
            var i = content.startIndex
            while i + 1 < content.endIndex {
                let length = Int(content[i]) + 1
                let color = palette[Int(content[i + 1])]
                out.append(contentsOf: repeatElement(color, count: length))
                i += 2
            }
            guard out.count == pixelCount else { throw Failure.malformed("RLE frame \(index) has \(out.count) pixels") }
        }
        return out
    }
}
