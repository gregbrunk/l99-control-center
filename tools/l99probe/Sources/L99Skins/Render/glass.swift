// Pixel-level liquid glass over a background: refraction, fringing, highlights, caustics, shadows.
import AppKit

struct V2 { var x: Double, y: Double }
func vlen(_ v: V2) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }

struct GShape {
    let cx: Double, cy: Double, hw: Double, hh: Double, r: Double
    var mag = 1.07, tintA = 0.0, tint = (1.0, 1.0, 1.0), glow = false
    init(_ rect: CGRect, radius: Double) {
        cx = rect.midX; cy = rect.midY; hw = rect.width / 2; hh = rect.height / 2; r = min(radius, min(hw, hh))
    }
    func sd(_ x: Double, _ y: Double) -> Double {
        let qx = abs(x - cx) - hw + r, qy = abs(y - cy) - hh + r
        return vlen(V2(x: max(qx, 0), y: max(qy, 0))) + min(max(qx, qy), 0) - r
    }
    func normal(_ x: Double, _ y: Double) -> V2 {
        let e = 0.5, gx = sd(x + e, y) - sd(x - e, y), gy = sd(x, y + e) - sd(x, y - e), l = max(1e-6, vlen(V2(x: gx, y: gy)))
        return V2(x: gx / l, y: gy / l)
    }
}

struct GlassLook {
    let night: Bool, baseTintA: Double, frost: Double, rim: Double, shadow: Double, caustic: Double, accent: (Double, Double, Double)
}

struct Buf {
    var p: [Double]
    init() { p = [Double](repeating: 0, count: W * H * 3) }
    init(_ img: CGImage) {
        let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
        let d = c.data!.assumingMemoryBound(to: UInt8.self)
        p = (0..<(W * H * 3)).map { i in Double(d[(i / 3) * 4 + i % 3]) / 255 }
    }
    func sample(_ x: Double, _ y: Double, _ ch: Int) -> Double {
        let xx = min(max(x, 0), Double(W - 1) - 0.001), yy = min(max(y, 0), Double(H - 1) - 0.001)
        let x0 = Int(xx), y0 = Int(yy), fx = xx - Double(x0), fy = yy - Double(y0)
        func at(_ a: Int, _ b: Int) -> Double { p[(b * W + a) * 3 + ch] }
        return (at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx) * (1 - fy) + (at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx) * fy
    }
    func image() -> CGImage {
        let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let d = c.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(W * H) {
            for k in 0..<3 { d[i * 4 + k] = UInt8(max(0, min(1, p[i * 3 + k])) * 255 + 0.5) }
            d[i * 4 + 3] = 255
        }
        return c.makeImage()!
    }
}

/// Composites glass shapes over `bg` (top-left-origin image) and returns the result.
func glassComposite(_ bg: CGImage, _ sh: [GShape], _ t: GlassLook) -> CGImage {
    let sharp = Buf(bg), soft = Buf(blurred(bg, 3.5))
    var out = Buf()
    let L = V2(x: -0.6, y: -0.8)
    for y in 0..<H { for x in 0..<W {
        let px = Double(x) + 0.5, py = Double(y) + 0.5, o = (y * W + x) * 3
        var outside = (sharp.p[o], sharp.p[o + 1], sharp.p[o + 2])
        var keep = 1.0, cr = 0.0, cg = 0.0, cb = 0.0, best = -1, bd = Double.infinity
        for (i, s) in sh.enumerated() {
            let d = s.sd(px, py)
            if d < bd { bd = d; best = i }
            keep *= 1 - t.shadow * exp(-max(0, s.sd(px, py - 6)) / 7)
            if d > 0 && d < 30 {
                let nn = s.normal(px, py)
                let k = t.caustic * max(0, -(nn.x * L.x + nn.y * L.y)) * exp(-d / 5)
                let tc = s.tintA > 0.1 ? s.tint : (sharp.sample(s.cx, s.cy, 0), sharp.sample(s.cx, s.cy, 1), sharp.sample(s.cx, s.cy, 2))
                cr += k * (0.5 + 0.5 * tc.0); cg += k * (0.5 + 0.5 * tc.1); cb += k * (0.5 + 0.5 * tc.2)
            }
        }
        outside.0 = outside.0 * keep + cr; outside.1 = outside.1 * keep + cg; outside.2 = outside.2 * keep + cb
        guard best >= 0 else { out.p[o] = outside.0; out.p[o + 1] = outside.1; out.p[o + 2] = outside.2; continue }
        let s = sh[best]
        let cover = max(0, min(1, 0.5 - bd))
        if cover == 0 { out.p[o] = outside.0; out.p[o + 1] = outside.1; out.p[o + 2] = outside.2; continue }
        let depth = max(0, -bd), bevel = min(13, s.r * 0.55 + 4)
        let edge = 1 - min(1, depth / bevel)
        let n = s.normal(px, py)
        let bend = 11.0 * pow(edge, 2.2)
        var g = [0.0, 0.0, 0.0]
        for (ch, k) in [(0, 0.82), (1, 1.0), (2, 1.25)] {
            let sx = s.cx + (px - s.cx) / s.mag + n.x * bend * k, sy = s.cy + (py - s.cy) / s.mag + n.y * bend * k
            g[ch] = soft.sample(sx, sy, ch) * t.frost + sharp.sample(sx, sy, ch) * (1 - t.frost)
        }
        let lift = t.night ? 0.05 : 0.07, tA = t.baseTintA + s.tintA
        let tc = [s.tint.0, s.tint.1, s.tint.2]
        for ch in 0..<3 { g[ch] = g[ch] * (1 - tA) + tc[ch] * tA + lift }
        let ndl = n.x * L.x + n.y * L.y
        let spec = pow(max(0, ndl), 2.5) * pow(edge, 2.6) * 0.95
        let bounce = pow(max(0, -ndl), 3) * pow(edge, 5) * 0.45
        let shade = pow(max(0, -ndl), 1.5) * pow(edge, 1.5) * (t.night ? 0.22 : 0.10)
        let rimLine = max(0, 1 - depth / 1.2) * t.rim
        let sheen = max(0, 1 - (py - (s.cy - s.hh)) / max(10, s.hh * 0.9)) * 0.07
        for ch in 0..<3 {
            g[ch] = g[ch] * (1 - shade) + spec + bounce + sheen
            g[ch] = g[ch] * (1 - rimLine * 0.6) + rimLine * (ndl > 0 ? 1 : 0.7)
        }
        if s.glow {
            let gl = (1 - min(1, vlen(V2(x: px - s.cx, y: py - s.cy)) / max(s.hw, s.hh))) * 0.35
            for ch in 0..<3 { g[ch] += gl * [t.accent.0, t.accent.1, t.accent.2][ch] }
        }
        let oc = [outside.0, outside.1, outside.2]
        for ch in 0..<3 { out.p[o + ch] = g[ch] * cover + oc[ch] * (1 - cover) }
    } }
    return out.image()
}
