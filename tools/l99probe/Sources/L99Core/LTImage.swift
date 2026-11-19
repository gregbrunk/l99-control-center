import Foundation

/// The screen's compressed image container ("LT"), used for full-page backgrounds.
/// Layout (our decode, checked by re-encoding the stock images: 7 of 10 come out byte-identical and
/// all decode back exactly):
///   "LT", width u16, height u16, chunk count u8, flags u8 (3), total length u32,
///   then per chunk: u32 (length | mode << 24) + a 256-entry RGB565 palette,
///   then the chunks' data. Mode 1 is run-length pairs (count − 1, index); mode 0 is raw indices.
/// The pixel stream (rows top to bottom) is cut into chunks of at most 256 distinct colours, so the
/// encoding is lossless for any RGB565 image.
public enum LTImage {
    public static func encode(_ px: [UInt16], width: Int, height: Int) throws -> [UInt8] {
        guard width > 0, height > 0, px.count == width * height else { throw InterfaceFile.Failure.refused("LT: pixel count doesn't match \(width)×\(height)") }
        var chunks: [(mode: UInt8, body: [UInt8], palette: [UInt16])] = []
        var i = 0
        while i < px.count {
            var pal = [UInt16: UInt8](), order = [UInt16](), idx = [UInt8]()
            var j = i
            while j < px.count {
                if let k = pal[px[j]] { idx.append(k) }
                else if order.count < 256 { pal[px[j]] = UInt8(order.count); order.append(px[j]); idx.append(UInt8(order.count - 1)) }
                else { break }
                j += 1
            }
            var rle = [UInt8](); var k = 0
            while k < idx.count {
                var r = 1
                while k + r < idx.count, r < 256, idx[k + r] == idx[k] { r += 1 }
                rle.append(UInt8(r - 1)); rle.append(idx[k]); k += r
            }
            let useRLE = rle.count <= idx.count
            chunks.append((useRLE ? 1 : 0, useRLE ? rle : idx, order + [UInt16](repeating: 0, count: 256 - order.count)))
            i = j
        }
        guard chunks.count < 256 else { throw InterfaceFile.Failure.refused("LT: the image needs \(chunks.count) chunks; the limit is 255. Use fewer colours.") }
        let total = 12 + chunks.count * 516 + chunks.reduce(0) { $0 + $1.body.count }
        var out = [UInt8]("LT".utf8)
        func p16(_ v: Int) { out.append(UInt8(v & 0xFF)); out.append(UInt8(v >> 8 & 0xFF)) }
        func p32(_ v: Int) { for s in stride(from: 0, to: 32, by: 8) { out.append(UInt8(v >> s & 0xFF)) } }
        p16(width); p16(height); out.append(UInt8(chunks.count)); out.append(3); p32(total)
        for c in chunks { p32(c.body.count | Int(c.mode) << 24); for v in c.palette { p16(Int(v)) } }
        for c in chunks { out += c.body }
        return out
    }

    public static func decode(_ b: [UInt8]) throws -> (width: Int, height: Int, pixels: [UInt16]) {
        guard b.count >= 12, b[0] == 0x4C, b[1] == 0x54 else { throw InterfaceFile.Failure.refused("LT: bad header") }
        let w = Int(b[2]) | Int(b[3]) << 8, h = Int(b[4]) | Int(b[5]) << 8, n = Int(b[6])
        func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        var cur = 12 + n * 516, px = [UInt16]()
        for c in 0..<n {
            let t = 12 + c * 516, hd = u32(t), len = hd & 0xFFFFFF, mode = hd >> 24
            let pal = (0..<256).map { UInt16(b[t + 4 + 2 * $0]) | UInt16(b[t + 5 + 2 * $0]) << 8 }
            guard cur + len <= b.count else { throw InterfaceFile.Failure.refused("LT: truncated") }
            if mode == 1 { for k in stride(from: cur, to: cur + len, by: 2) { px += [UInt16](repeating: pal[Int(b[k + 1])], count: Int(b[k]) + 1) } }
            else { for k in cur..<(cur + len) { px.append(pal[Int(b[k])]) } }
            cur += len
        }
        guard px.count == w * h else { throw InterfaceFile.Failure.refused("LT: decoded \(px.count) pixels, expected \(w * h)") }
        return (w, h, px)
    }
}
