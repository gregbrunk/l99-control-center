// Numpad style exploration: renders full 320×480 pages, quantised to RGB565 (what opaque key art
// would carry), with the stock status-bar icons tinted per style. Mockups only; nothing is sent.
import AppKit
import CoreImage

let W = 320, H = 480

// MARK: Helpers

func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
func newContext(_ w: Int = W, _ h: Int = H) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)   // top-left origin
    return c
}
func withNS(_ c: CGContext, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
    body()
    NSGraphicsContext.restoreGraphicsState()
}
func draw(_ c: CGContext, _ img: CGImage, in r: CGRect) {
    c.saveGState(); c.translateBy(x: r.minX, y: r.maxY); c.scaleBy(x: 1, y: -1)
    c.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height)); c.restoreGState()
}
/// The UI face: Inter (SIL Open Font License), standing in for the system font in every style.
func sf(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { SkinFonts.inter(s, w) }
/// The monospaced face: JetBrains Mono (SIL Open Font License), for Cyberpunk and small labels.
func mono(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { SkinFonts.mono(s, w) }

/// Draws text centred on a point (by cap height, so digits sit visually centred).
func text(_ c: CGContext, _ s: String, _ f: NSFont, _ col: NSColor, center p: CGPoint, kern: CGFloat = 0) {
    let s = s == "*" ? "∗" : s
    withNS(c) {
        let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: col, .kern: kern])
        let w = a.size().width
        a.draw(at: CGPoint(x: p.x - w / 2, y: p.y - f.ascender + f.capHeight / 2))
    }
}
func text(_ c: CGContext, _ s: String, _ f: NSFont, _ col: NSColor, left p: CGPoint, kern: CGFloat = 0) {
    withNS(c) {
        NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: col, .kern: kern])
            .draw(at: CGPoint(x: p.x, y: p.y - f.ascender + f.capHeight / 2))
    }
}
func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: min(rad, r.width / 2), cornerHeight: min(rad, r.height / 2), transform: nil) }
func chamfer(_ r: CGRect, _ k: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.minX + k, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - k)); p.addLine(to: CGPoint(x: r.maxX - k, y: r.maxY))
    p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.minY + k)); p.closeSubpath()
    return p
}
func fill(_ c: CGContext, _ p: CGPath, _ col: NSColor) { c.addPath(p); c.setFillColor(col.cgColor); c.fillPath() }
func stroke(_ c: CGContext, _ p: CGPath, _ col: NSColor, _ w: CGFloat) { c.addPath(p); c.setStrokeColor(col.cgColor); c.setLineWidth(w); c.strokePath() }
func linear(_ c: CGContext, _ p: CGPath?, _ cols: [NSColor], _ locs: [CGFloat], from a: CGPoint, to b: CGPoint) {
    c.saveGState(); if let p { c.addPath(p); c.clip() }
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cols.map(\.cgColor) as CFArray, locations: locs)!
    c.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]); c.restoreGState()
}
func radial(_ c: CGContext, _ center: CGPoint, _ r: CGFloat, _ cols: [NSColor], _ locs: [CGFloat], clip: CGPath? = nil) {
    c.saveGState(); if let clip { c.addPath(clip); c.clip() }
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cols.map(\.cgColor) as CFArray, locations: locs)!
    c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [.drawsAfterEndLocation]); c.restoreGState()
}
let ci = CIContext()
func blurred(_ img: CGImage, _ radius: Double) -> CGImage {
    let i = CIImage(cgImage: img).clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: CIImage(cgImage: img).extent)
    return ci.createCGImage(i, from: CIImage(cgImage: img).extent)!
}

// MARK: Keys and layouts

enum Kind { case num, op, enter, zero, num0 }
struct Key { let label: String; let r: CGRect; let kind: Kind }

/// The stock arrangement (tall + and Enter, wide 0), on a cell grid inside y 100…474.
func stockLayout(margin m: CGFloat = 10, gap g: CGFloat = 8, top: CGFloat = 100, bottom: CGFloat = 474) -> [Key] {
    let cw = (CGFloat(W) - 2 * m - 3 * g) / 4, ch = (bottom - top - 4 * g) / 5
    func cell(_ col: Int, _ row: Int, _ cs: Int = 1, _ rs: Int = 1) -> CGRect {
        CGRect(x: m + CGFloat(col) * (cw + g), y: top + CGFloat(row) * (ch + g),
               width: CGFloat(cs) * cw + CGFloat(cs - 1) * g, height: CGFloat(rs) * ch + CGFloat(rs - 1) * g)
    }
    return [Key(label: "Num", r: cell(0, 0), kind: .op), Key(label: "/", r: cell(1, 0), kind: .op),
            Key(label: "*", r: cell(2, 0), kind: .op), Key(label: "−", r: cell(3, 0), kind: .op),
            Key(label: "7", r: cell(0, 1), kind: .num), Key(label: "8", r: cell(1, 1), kind: .num),
            Key(label: "9", r: cell(2, 1), kind: .num), Key(label: "+", r: cell(3, 1, 1, 2), kind: .op),
            Key(label: "4", r: cell(0, 2), kind: .num), Key(label: "5", r: cell(1, 2), kind: .num), Key(label: "6", r: cell(2, 2), kind: .num),
            Key(label: "1", r: cell(0, 3), kind: .num), Key(label: "2", r: cell(1, 3), kind: .num),
            Key(label: "3", r: cell(2, 3), kind: .num), Key(label: "Enter", r: cell(3, 3, 1, 2), kind: .enter),
            Key(label: "0", r: cell(0, 4, 2), kind: .zero), Key(label: "Del", r: cell(2, 4), kind: .op)]
}
/// The proven test grid: 4×4 plus a full-width 0.
func gridLayout(margin m: CGFloat = 10, gap g: CGFloat = 8, top: CGFloat = 100, bottom: CGFloat = 474) -> [Key] {
    let cw = (CGFloat(W) - 2 * m - 3 * g) / 4, ch = (bottom - top - 4 * g) / 5
    let rows: [[(String, Kind)]] = [[("Num", .op), ("/", .op), ("*", .op), ("−", .op)],
                                    [("7", .num), ("8", .num), ("9", .num), ("+", .op)],
                                    [("4", .num), ("5", .num), ("6", .num), ("Del", .op)],
                                    [("1", .num), ("2", .num), ("3", .num), ("Enter", .enter)]]
    var out = [Key]()
    for (ri, row) in rows.enumerated() { for (ci, k) in row.enumerated() {
        out.append(Key(label: k.0, r: CGRect(x: m + CGFloat(ci) * (cw + g), y: top + CGFloat(ri) * (ch + g), width: cw, height: ch), kind: k.1))
    } }
    out.append(Key(label: "0", r: CGRect(x: m, y: top + 4 * (ch + g), width: CGFloat(W) - 2 * m, height: ch), kind: .zero))
    return out
}

func chevron(_ c: CGContext, at p: CGPoint, size s: CGFloat, _ col: NSColor, _ w: CGFloat) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: p.x + s / 2, y: p.y - s)); path.addLine(to: CGPoint(x: p.x - s / 2, y: p.y)); path.addLine(to: CGPoint(x: p.x + s / 2, y: p.y + s))
    c.addPath(path); c.setStrokeColor(col.cgColor); c.setLineWidth(w); c.setLineCap(.round); c.setLineJoin(.round); c.strokePath()
}

// MARK: Dot-matrix glyphs (5×7)

let dots: [Character: [String]] = [
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"], "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"], "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"], "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"], "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"], "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "/": ["00001", "00001", "00010", "00100", "01000", "10000", "10000"], "*": ["00000", "10101", "01110", "11111", "01110", "10101", "00000"],
    "−": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"], "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
]
func dotGlyph(_ c: CGContext, _ ch: Character, center p: CGPoint, pitch: CGFloat, dot: CGFloat, on: NSColor, off: NSColor?) {
    guard let g = dots[ch] else { return }
    let x0 = p.x - pitch * 2, y0 = p.y - pitch * 3
    for (ry, row) in g.enumerated() { for (rx, v) in row.enumerated() {
        let r = CGRect(x: x0 + CGFloat(rx) * pitch - dot / 2, y: y0 + CGFloat(ry) * pitch - dot / 2, width: dot, height: dot)
        if v == "1" { c.setFillColor(on.cgColor); c.fill(r) } else if let off { c.setFillColor(off.cgColor); c.fill(r) }
    } }
}

// MARK: Quantise to RGB565 with ordered dithering (what opaque key art carries)

let bayer: [CGFloat] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
func quantised565(_ c: CGContext) -> CGContext {
    let src = c.makeImage()!
    let out = newContext(); draw(out, src, in: CGRect(x: 0, y: 0, width: W, height: H))
    let p = out.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<H { for x in 0..<W {
        let i = 4 * (y * W + x), t = (bayer[(y & 3) * 4 + (x & 3)] + 0.5) / 16 - 0.5
        for (k, bits) in [(0, 5), (1, 6), (2, 5)] {
            let levels = CGFloat((1 << bits) - 1)
            let v = CGFloat(p[i + k]) / 255 * levels + t
            p[i + k] = UInt8(max(0, min(levels, v.rounded())) / levels * 255)
        }
        p[i + 3] = 255
    } }
    return out
}
func savePNG(_ c: CGContext, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func scaled(_ c: CGContext, _ s: Int) -> CGContext {
    let img = c.makeImage()!, w = img.width * s, h = img.height * s
    let o = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    o.interpolationQuality = .none; o.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return o
}

