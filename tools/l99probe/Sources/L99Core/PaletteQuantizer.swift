import Foundation

/// A best-fit palette of ≤256 RGB565 colours (median cut), then dithering onto it.
/// The factory animation proves the screen shows colours off the 252-colour ramp.
public struct PaletteQuantizer: Sendable {
    public let palette: [UInt16]
    /// Nearest palette entry for every RGB565 value.
    private let nearest: [UInt16]

    /// Median cut over a sample of all frames' pixels. `frames`: RGBA8, alpha ignored.
    public init(frames: [[UInt8]], maxColors: Int = 256, maxSamples: Int = 400_000) {
        precondition((1...256).contains(maxColors))
        let totalPixels = frames.reduce(0) { $0 + $1.count / 4 }
        let step = max(1, totalPixels / maxSamples)
        var samples = [SIMD3<Int32>]()
        samples.reserveCapacity(min(totalPixels, maxSamples) + frames.count)
        var counter = 0
        for frame in frames {
            var i = 0
            while i + 3 < frame.count {
                if counter % step == 0 { samples.append(SIMD3(Int32(frame[i]), Int32(frame[i + 1]), Int32(frame[i + 2]))) }
                counter += 1
                i += 4
            }
        }
        let colours = Self.medianCut(samples, maxColors: maxColors)
        var unique = [UInt16]()
        for c in colours {
            let v = ColorConversion.rgb565(Int(c.x), Int(c.y), Int(c.z))
            if !unique.contains(v) { unique.append(v) }
        }
        if unique.isEmpty { unique = [0] }
        palette = unique
        nearest = Self.buildNearest(unique)
    }

    /// Maps an RGBA8 frame onto the palette with serpentine Floyd–Steinberg error diffusion.
    public func dither(rgba: [UInt8], width: Int, height: Int) -> [UInt16] {
        nearest.withUnsafeBufferPointer { lookup in
            ColorConversion.errorDiffuse(rgba: rgba, width: width, height: height) { r, g, b in
                lookup[Int(ColorConversion.rgb565(r, g, b))]
            }
        }
    }

    /// The frame's own colours when it already has ≤256 of them (flat art, most real GIFs before
    /// scaling): no dithering needed, every pixel exact. Nil when it has more.
    public static func exactColors(rgba: [UInt8], limit: Int = 256) -> [UInt16]? {
        var seen = Set<UInt16>()
        var out = [UInt16]()
        out.reserveCapacity(rgba.count / 4)
        var i = 0
        while i + 3 < rgba.count {
            let v = ColorConversion.rgb565(Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2]))
            if seen.insert(v).inserted, seen.count > limit { return nil }
            out.append(v)
            i += 4
        }
        return out
    }

    /// Converts every frame of an animation for the GIF container: a frame that already has ≤256
    /// colours keeps them exactly; any other frame gets its own best-fit 256-colour palette.
    /// (One palette shared by all frames was tried first; with varied frames it left too few
    /// nearby colours and showed rows of dots on hardware.)
    public static func convertAnimation(_ frames: [[UInt8]], width: Int, height: Int,
                                        progress: (Int) -> Void = { _ in }) -> [[UInt16]] {
        frames.enumerated().map { index, rgba in
            defer { progress(index + 1) }
            if let exact = exactColors(rgba: rgba) { return exact }
            return PaletteQuantizer(frames: [rgba]).dither(rgba: rgba, width: width, height: height)
        }
    }

    // MARK: Internals

    private static func medianCut(_ samples: [SIMD3<Int32>], maxColors: Int) -> [SIMD3<Int32>] {
        guard !samples.isEmpty else { return [] }
        var boxes: [[SIMD3<Int32>]] = [samples]
        while boxes.count < maxColors {
            // Split the box with the widest channel range (weighted by population).
            var bestIndex = -1, bestScore: Int64 = 0, bestChannel = 0
            for (n, box) in boxes.enumerated() where box.count > 1 {
                var lo = SIMD3<Int32>(255, 255, 255), hi = SIMD3<Int32>(0, 0, 0)
                for p in box { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
                let range = hi &- lo
                let channel = range.x >= range.y && range.x >= range.z ? 0 : (range.y >= range.z ? 1 : 2)
                let score = Int64(range[channel]) * Int64(box.count)
                if score > bestScore { bestScore = score; bestIndex = n; bestChannel = channel }
            }
            guard bestIndex >= 0 else { break }
            var box = boxes.remove(at: bestIndex)
            box.sort { $0[bestChannel] < $1[bestChannel] }
            let mid = box.count / 2
            boxes.append(Array(box[..<mid]))
            boxes.append(Array(box[mid...]))
        }
        return boxes.map { box in
            var sum = SIMD3<Int64>(0, 0, 0)
            for p in box { sum &+= SIMD3<Int64>(Int64(p.x), Int64(p.y), Int64(p.z)) }
            let n = Int64(box.count)
            return SIMD3<Int32>(Int32(sum.x / n), Int32(sum.y / n), Int32(sum.z / n))
        }
    }

    /// 65,536-entry table: every RGB565 value → closest palette colour (squared RGB distance).
    private static func buildNearest(_ palette: [UInt16]) -> [UInt16] {
        let rgb = palette.map { ColorConversion.rgb888($0) }.map { (Int($0.0), Int($0.1), Int($0.2)) }
        var table = [UInt16](repeating: 0, count: 65536)
        table.withUnsafeMutableBufferPointer { out in
            rgb.withUnsafeBufferPointer { pal in
                for v in 0..<65536 {
                    let c = ColorConversion.rgb888(UInt16(v))
                    let (r, g, b) = (Int(c.0), Int(c.1), Int(c.2))
                    var best = 0, bestDistance = Int.max
                    for k in 0..<pal.count {
                        let dr = r - pal[k].0, dg = g - pal[k].1, db = b - pal[k].2
                        let d = dr * dr + dg * dg + db * db
                        if d < bestDistance { bestDistance = d; best = k; if d == 0 { break } }
                    }
                    out[v] = palette[best]
                }
            }
        }
        return table
    }
}
