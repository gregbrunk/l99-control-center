import Foundation

/// RGBA8 → RGB565 conversions for the screen. Pure functions, no AppKit.
public enum ColorConversion {
    /// The vendor's fixed GIF colour ramp, proven on hardware (gavindi). 6 × 7 × 6 = 252 colours.
    public static let rampR: [Int] = [0, 49, 99, 156, 206, 255]
    public static let rampG: [Int] = [0, 40, 85, 130, 170, 215, 255]
    public static let rampB: [Int] = rampR

    public enum Method: String, CaseIterable, Codable, Sendable {
        /// Plain truncation to 5/6/5 bits, like the vendor's still images.
        case truncate
        /// Floyd–Steinberg to the 5/6/5 levels: removes banding in gradients.
        case dither565
        /// Floyd–Steinberg onto the 252-colour ramp. Required for GIF frames.
        case ramp
    }

    @inline(__always)
    public static func rgb565(_ r: Int, _ g: Int, _ b: Int) -> UInt16 {
        UInt16(r & 0xF8) << 8 | UInt16(g & 0xFC) << 3 | UInt16(b >> 3)
    }

    /// Expands RGB565 to 8-bit channels (for previews).
    @inline(__always)
    public static func rgb888(_ v: UInt16) -> (UInt8, UInt8, UInt8) {
        let r = Int(v >> 11), g = Int((v >> 5) & 63), b = Int(v & 31)
        return (UInt8((r * 255 + 15) / 31), UInt8((g * 255 + 31) / 63), UInt8((b * 255 + 15) / 31))
    }

    /// `rgba`: width × height × 4 bytes, alpha ignored (draw over an opaque background first).
    public static func convert(rgba: [UInt8], width: Int, height: Int, method: Method) -> [UInt16] {
        precondition(rgba.count == width * height * 4)
        switch method {
        case .truncate:
            return (0..<(width * height)).map { i in rgb565(Int(rgba[4 * i]), Int(rgba[4 * i + 1]), Int(rgba[4 * i + 2])) }
        case .dither565:
            return floydSteinberg(rgba: rgba, width: width, height: height,
                                  quantize: [level(bits: 5), level(bits: 6), level(bits: 5)])
        case .ramp:
            return floydSteinberg(rgba: rgba, width: width, height: height,
                                  quantize: [nearestTable(rampR), nearestTable(rampG), nearestTable(rampB)])
        }
    }

    /// Little-endian byte stream for the image container.
    public static func bytesLE(_ pixels: [UInt16]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: pixels.count * 2)
        for (i, v) in pixels.enumerated() { out[2 * i] = UInt8(v & 0xFF); out[2 * i + 1] = UInt8(v >> 8) }
        return out
    }

    public static func pixels(fromLE bytes: ArraySlice<UInt8>) -> [UInt16] {
        var out = [UInt16]()
        out.reserveCapacity(bytes.count / 2)
        var i = bytes.startIndex
        while i + 1 < bytes.endIndex { out.append(UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8); i += 2 }
        return out
    }

    /// True when every pixel is on the 252-colour ramp.
    public static func isRampLegal(_ v: UInt16) -> Bool {
        let (r, g, b) = (Int(v >> 11), Int((v >> 5) & 63), Int(v & 31))
        return rampR.contains { $0 >> 3 == r } && rampG.contains { $0 >> 2 == g } && rampB.contains { $0 >> 3 == b }
    }

    // MARK: Internals

    /// 256-entry table: 8-bit value → nearest representable 8-bit value.
    private static func nearestTable(_ rungs: [Int]) -> [Int] {
        (0..<256).map { v in rungs.min { abs($0 - v) < abs($1 - v) }! }
    }

    /// Levels of an n-bit channel, expressed in 8-bit, with the same truncation the hardware applies.
    private static func level(bits: Int) -> [Int] {
        let max = (1 << bits) - 1
        let rungs = (0...max).map { ($0 * 255 + max / 2) / max }
        return nearestTable(rungs)
    }

    /// Floyd–Steinberg for per-channel quantizers (5/6/5 levels or the ramp).
    private static func floydSteinberg(rgba: [UInt8], width: Int, height: Int, quantize: [[Int]]) -> [UInt16] {
        let r = quantize[0], g = quantize[1], b = quantize[2]
        return errorDiffuse(rgba: rgba, width: width, height: height) { rgb565(r[$0], g[$1], b[$2]) }
    }

    /// Serpentine Floyd–Steinberg (7/16, 3/16, 5/16, 1/16), with the carried error damped and clamped.
    /// Plain left-to-right scanning on flat areas lines up isolated outlier pixels into visible
    /// rows of dots (seen on hardware, Nov 17); alternating direction and damping remove them.
    /// `quantize` maps clamped 8-bit RGB to the RGB565 value the screen will show.
    static func errorDiffuse(rgba: [UInt8], width: Int, height: Int, damping: Float = 0.85, maxError: Float = 40,
                             quantize: (Int, Int, Int) -> UInt16) -> [UInt16] {
        precondition(rgba.count == width * height * 4)
        var out = [UInt16](repeating: 0, count: width * height)
        let stride = width + 2                                      // one guard column each side
        var current = [Float](repeating: 0, count: stride * 3)
        var next = [Float](repeating: 0, count: stride * 3)
        rgba.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<height {
                    let leftToRight = y % 2 == 0
                    let step = leftToRight ? 1 : -1
                    current.withUnsafeMutableBufferPointer { cur in
                        next.withUnsafeMutableBufferPointer { nxt in
                            for k in 0..<nxt.count { nxt[k] = 0 }
                            var x = leftToRight ? 0 : width - 1
                            for _ in 0..<width {
                                let i = y * width + x
                                let col = x + 1
                                let wr = Float(src[4 * i]) + cur[col]
                                let wg = Float(src[4 * i + 1]) + cur[stride + col]
                                let wb = Float(src[4 * i + 2]) + cur[2 * stride + col]
                                let chosen = quantize(Int(min(255, max(0, wr)).rounded()),
                                                      Int(min(255, max(0, wg)).rounded()),
                                                      Int(min(255, max(0, wb)).rounded()))
                                dst[i] = chosen
                                let shown = rgb888(chosen)
                                let errors = (wr - Float(shown.0), wg - Float(shown.1), wb - Float(shown.2))
                                for c in 0..<3 {
                                    let raw = c == 0 ? errors.0 : (c == 1 ? errors.1 : errors.2)
                                    let e = min(maxError, max(-maxError, raw * damping))
                                    let base = c * stride + col
                                    cur[base + step] += e * (7 / 16)
                                    nxt[base - step] += e * (3 / 16)
                                    nxt[base] += e * (5 / 16)
                                    nxt[base + step] += e * (1 / 16)
                                }
                                x += step
                            }
                        }
                    }
                    swap(&current, &next)
                }
            }
        }
        return out
    }
}
