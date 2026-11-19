// A redesigned top bar. Every piece is still one of the screen's own indicator slots (each with its
// states), just with new art, sizes and positions: connection, Num, Caps, Lock, OS mode, battery %, battery.
import AppKit

struct TBState { var num = true, caps = false, lock = false, mac = false, wired = false, pct = 82, charging = false }
var tbState = TBState()

func chip(_ s: SID, _ c: CGContext, _ label: String, x: CGFloat, on: Bool, lockGlyph: Bool = false) -> CGFloat {
    let f: NSFont = s == .cyber ? mono(8, .bold) : s == .midnight ? mono(8, .semibold) : sf(8.5, .bold)
    let tw = lockGlyph ? 9 : width(label, f, kern: 0.4)
    let w = tw + (s == .cyber ? 10 : s == .midnight ? 14 : 12), r = CGRect(x: x, y: 9, width: w, height: 15)
    let inkOn: NSColor, inkOff: NSColor
    switch s {
    case .glassNight:
        inkOn = hex(0x1A1430); inkOff = hex(0xFFFFFF, 0.38)
        if on { fill(c, rr(r, 7.5), hex(0xFFFFFF, 0.92)) } else { stroke(c, rr(r.insetBy(dx: 0.5, dy: 0.5), 7), hex(0xFFFFFF, 0.22), 1) }
    case .glassDay:
        inkOn = hex(0xFFFFFF); inkOff = hex(0x1C1930, 0.38)
        if on { fill(c, rr(r, 7.5), hex(0x5B3FD9)) } else { stroke(c, rr(r.insetBy(dx: 0.5, dy: 0.5), 7), hex(0x1C1930, 0.18), 1) }
    case .cyber:
        inkOn = hex(0x07060B); inkOff = hex(0x05D9E8, 0.35)
        if on { c.saveGState(); c.setShadow(offset: .zero, blur: 6, color: hex(0xFCEE0A, 0.8).cgColor); fill(c, chamfer(r, 4), hex(0xFCEE0A)); c.restoreGState() }
        else { stroke(c, chamfer(r.insetBy(dx: 0.5, dy: 0.5), 4), hex(0x05D9E8, 0.3), 1) }
    case .ceramic:
        inkOn = hex(0xFFFFFF); inkOff = hex(0x1F2025, 0.32)
        if on { fill(c, rr(r, 7.5), hex(0x1F2025)) } else { stroke(c, rr(r.insetBy(dx: 0.5, dy: 0.5), 7), hex(0x1F2025, 0.14), 1) }
    case .ember:
        inkOn = hex(0xFFFFFF); inkOff = hex(0xFFFFFF, 0.3)
        if on { fill(c, rr(r, 7.5), hex(0xFF7A1A)) } else { stroke(c, rr(r.insetBy(dx: 0.5, dy: 0.5), 7), hex(0xFFFFFF, 0.14), 1) }
    case .midnight:
        inkOn = hex(0x5CF2C9); inkOff = hex(0xFFFFFF, 0.28)
        fill(c, rr(r, 7.5), hex(0x0E2470, on ? 0.75 : 0.35))
        stroke(c, rr(r.insetBy(dx: 0.5, dy: 0.5), 7), on ? hex(0x5CF2C9, 0.6) : hex(0x8FB0FF, 0.2), 1)
        c.setFillColor((on ? hex(0x5CF2C9) : hex(0xFFFFFF, 0.15)).cgColor)
        if on { c.saveGState(); c.setShadow(offset: .zero, blur: 4, color: hex(0x5CF2C9).cgColor) }
        c.fillEllipse(in: CGRect(x: r.minX + 5, y: r.midY - 1.5, width: 3, height: 3)); if on { c.restoreGState() }
    }
    let ink = on ? inkOn : inkOff
    let cx = s == .midnight ? r.midX + 3 : r.midX
    if lockGlyph {
        let b = CGRect(x: cx - 3.5, y: r.midY - 1, width: 7, height: 5.5)
        fill(c, rr(b, 1), ink)
        c.addArc(center: CGPoint(x: cx, y: b.minY), radius: 2.4, startAngle: .pi, endAngle: 0, clockwise: false)
        c.setStrokeColor(ink.cgColor); c.setLineWidth(1.3); c.strokePath()
    } else {
        text(c, label, f, ink, center: CGPoint(x: cx, y: r.midY + 0.5), kern: 0.4)
    }
    return r.maxX
}

/// quantised565 for any-size context.
func quantised565c(_ c: CGContext) -> CGContext {
    let img = c.makeImage()!, w = img.width, h = img.height
    let out = newContext(w, h); draw(out, img, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = out.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<h { for x in 0..<w {
        let i = 4 * (y * w + x), t = (bayer[(y & 3) * 4 + (x & 3)] + 0.5) / 16 - 0.5
        for (k, bits) in [(0, 5), (1, 6), (2, 5)] {
            let levels = CGFloat((1 << bits) - 1), v = CGFloat(p[i + k]) / 255 * levels + t
            p[i + k] = UInt8(max(0, min(levels, v.rounded())) / levels * 255)
        }
    } }
    return out
}
