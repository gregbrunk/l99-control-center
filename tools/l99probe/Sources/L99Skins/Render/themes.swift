// The six kept styles, expressed as panel roles so any page layout can be drawn in any style.
import AppKit

enum SID: String, CaseIterable { case glassNight = "liquid-glass-night", glassDay = "liquid-glass-day", cyber = "cyberpunk", ceramic, ember, midnight = "midnight-led" }
enum Role { case tile, op, accent, hero, bar, round, pressed, screen }
struct Panel { let r: CGRect; let rad: CGFloat; let role: Role }

extension SID {
    var glass: Bool { self == .glassNight || self == .glassDay }
    var light: Bool { self == .glassDay || self == .ceramic }
    var accent: NSColor {
        switch self {
        case .glassNight: return hex(0xB79BFF)
        case .glassDay: return hex(0x5B3FD9)
        case .cyber: return hex(0xFCEE0A)
        case .ceramic: return hex(0xFF6A1A)
        case .ember: return hex(0xFF7A1A)
        case .midnight: return hex(0x5CF2C9)
        }
    }
    /// Main text and icon colour on a panel of this role.
    func ink(_ r: Role) -> NSColor {
        switch (self, r) {
        case (.glassNight, .op): return hex(0xD9CCFF)
        case (.glassNight, _): return hex(0xFFFFFF)
        case (.glassDay, .op): return hex(0x5B3FD9)
        case (.glassDay, .accent), (.glassDay, .pressed): return hex(0xFFFFFF)
        case (.glassDay, _): return hex(0x1C1930)
        case (.cyber, .op): return hex(0xFF2A6D)
        case (.cyber, .accent), (.cyber, .pressed): return hex(0x07060B)
        case (.cyber, .hero), (.cyber, .screen): return hex(0xF5F5F5)
        case (.cyber, _): return hex(0x05D9E8)
        case (.ceramic, .op): return hex(0xFF6A1A)
        case (.ceramic, .accent): return hex(0xFFFFFF)
        case (.ceramic, _): return hex(0x1F2025)
        case (.ember, .op): return hex(0xFF7A1A)
        case (.ember, .hero): return hex(0x111111)
        case (.ember, _): return hex(0xF4F4F4)
        case (.midnight, .op): return hex(0x5CF2C9)
        case (.midnight, .accent): return hex(0x0A1A52)
        case (.midnight, _): return hex(0xFFFFFF)
        }
    }
    /// Secondary (caption) colour on a panel of this role.
    func sub(_ r: Role) -> NSColor {
        switch (self, r) {
        case (.glassNight, _): return hex(0xFFFFFF, 0.62)
        case (.glassDay, _): return hex(0x1C1930, 0.58)
        case (.cyber, _): return hex(0xFCEE0A, 0.8)
        case (.ceramic, .accent): return hex(0xFFFFFF, 0.85)
        case (.ceramic, _): return hex(0x8A887F)
        case (.ember, .hero): return hex(0xFF7A1A)
        case (.ember, _): return hex(0x8C8C8C)
        case (.midnight, .accent): return hex(0x0A1A52, 0.7)
        case (.midnight, _): return hex(0x9DB8FF, 0.85)
        }
    }
    func font(_ size: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { self == .cyber ? mono(size * 0.92, w == .regular ? .medium : w) : sf(size, w) }
    func caps(_ s: String) -> String { self == .cyber || self == .midnight ? s.uppercased() : s }
}

// MARK: Backgrounds

let glassBlobs: [SID: [(Double, Double, Double, UInt32, Double)]] = [
    .glassNight: [(70, 400, 210, 0x6B3BFF, 0.95), (300, 220, 160, 0xE040FB, 0.75), (230, 510, 200, 0x2B6BFF, 0.9),
                  (25, 130, 110, 0xFF9E5E, 0.5), (175, 330, 95, 0xFF5C8A, 0.45), (250, 60, 120, 0x3D2BFF, 0.4)],
    .glassDay: [(60, 390, 210, 0x9A7BFF, 0.95), (295, 220, 170, 0xFF9A66, 0.9), (240, 510, 210, 0x5DB2FF, 0.95),
                (35, 130, 120, 0x6FE6B8, 0.85), (180, 320, 100, 0xFF7EB6, 0.7), (250, 50, 120, 0xB59CFF, 0.6)],
]

func background(_ s: SID, _ c: CGContext) {
    let full = CGPath(rect: CGRect(x: 0, y: 0, width: W, height: H), transform: nil)
    switch s {
    case .glassNight, .glassDay:
        fill(c, full, hex(s == .glassNight ? 0x07050F : 0xEEF1F8))
        for b in glassBlobs[s]! { radial(c, CGPoint(x: b.0, y: b.1), b.2, [hex(b.3, b.4), hex(b.3, b.4 * 0.45), hex(b.3, 0)], [0, 0.5, 1]) }
        c.saveGState(); c.translateBy(x: 160, y: 300); c.rotate(by: -0.55)
        c.scaleBy(x: 260, y: 26); radial(c, .zero, 1, [hex(0xFFFFFF, s == .glassNight ? 0.16 : 0.45), hex(0xFFFFFF, 0)], [0, 1])
        c.restoreGState()
    case .cyber:
        fill(c, full, hex(0x07060B))
        radial(c, CGPoint(x: 300, y: 470), 260, [hex(0xFF2A6D, 0.22), hex(0xFF2A6D, 0)], [0, 1])
        radial(c, CGPoint(x: 0, y: 120), 220, [hex(0x05D9E8, 0.16), hex(0x05D9E8, 0)], [0, 1])
        c.setStrokeColor(hex(0x05D9E8, 0.07).cgColor); c.setLineWidth(1)
        for x in stride(from: 0, through: W, by: 20) { c.move(to: CGPoint(x: x, y: 90)); c.addLine(to: CGPoint(x: x, y: H)) }
        for y in stride(from: 90, through: H, by: 20) { c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: W, y: y)) }
        c.strokePath()
    case .ceramic:
        linear(c, nil, [hex(0xF4F3F0), hex(0xE4E3DF)], [0, 1], from: .zero, to: CGPoint(x: 0, y: H))
    case .ember:
        fill(c, full, hex(0x050505))
        radial(c, CGPoint(x: 160, y: 600), 420, [hex(0xFF7A1A), hex(0xE2560C), hex(0x7A2A06), hex(0x1A0A03), hex(0x050505)], [0, 0.2, 0.45, 0.72, 1])
    case .midnight:
        linear(c, nil, [hex(0x0A1A52), hex(0x06103A), hex(0x050B2A)], [0, 0.5, 1], from: .zero, to: CGPoint(x: 0, y: H))
        radial(c, CGPoint(x: 160, y: 300), 260, [hex(0x2F6BFF, 0.55), hex(0x1C3FB8, 0.25), hex(0x0A1A52, 0)], [0, 0.45, 1])
        for (i, rad) in [70, 120, 175, 235].enumerated() {
            c.addEllipse(in: CGRect(x: 160 - rad, y: 300 - rad, width: 2 * rad, height: 2 * rad))
            c.setStrokeColor(hex(0x9DB8FF, 0.10 - Double(i) * 0.02).cgColor); c.setLineWidth(1); c.strokePath()
        }
        var seed: UInt64 = 7
        for _ in 0..<70 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let x = CGFloat((seed >> 33) % 320), y = CGFloat((seed >> 17) % 480)
            c.setFillColor(hex(0xC9D6FF, 0.35).cgColor); c.fillEllipse(in: CGRect(x: x, y: y, width: 1.4, height: 1.4))
        }
    }
}

// MARK: Panels

func panelPath(_ s: SID, _ p: Panel) -> CGPath {
    s == .cyber ? chamfer(p.r, min(10, p.r.height / 4)) : rr(p.r, p.rad)
}

func drawPanels(_ s: SID, _ c: CGContext, _ panels: [Panel]) {
    if s.glass {
        let night = s == .glassNight
        let look = GlassLook(night: night, baseTintA: night ? 0.07 : 0.12, frost: night ? 0.6 : 0.55, rim: night ? 0.55 : 0.85,
                             shadow: night ? 0.45 : 0.18, caustic: night ? 0.55 : 0.35, accent: night ? (0.62, 0.45, 1.0) : (0.55, 0.42, 1.0))
        let shapes: [GShape] = panels.map { p in
            var g = GShape(p.r, radius: Double(p.rad))
            switch p.role {
            case .accent: g.tintA = night ? 0.22 : 0.62; g.tint = night ? look.accent : (0.40, 0.28, 0.90); g.glow = true
            case .pressed: g.mag = 1.16; g.tintA = 0.18; g.tint = look.accent; g.glow = true
            case .hero: g.mag = 1.04; g.tintA = 0.03
            case .screen: g.mag = 1.0; g.tintA = 0.28; g.tint = night ? (0.02, 0.01, 0.06) : (1, 1, 1)
            default: break
            }
            return g
        }
        let img = glassComposite(c.makeImage()!, shapes, look)
        draw(c, img, in: CGRect(x: 0, y: 0, width: W, height: H))
        return
    }
    let midBG = s == .midnight ? blurred(c.makeImage()!, 6) : nil
    for p in panels {
        let r = p.r, path = panelPath(s, p)
        switch s {
        case .cyber:
            let col: NSColor = p.role == .op ? hex(0xFF2A6D) : p.role == .accent ? hex(0xFCEE0A) : p.role == .hero ? hex(0xFF2A6D) : hex(0x05D9E8)
            if p.role == .accent || p.role == .pressed {
                c.saveGState(); c.setShadow(offset: .zero, blur: 12, color: col.withAlphaComponent(0.8).cgColor); fill(c, path, col); c.restoreGState()
            } else if p.role == .screen {
                fill(c, path, hex(0x000000, 0.85)); stroke(c, path, col.withAlphaComponent(0.45), 1)
            } else {
                fill(c, path, hex(0x0D0B16, 0.92))
                c.saveGState(); c.setShadow(offset: .zero, blur: 8, color: col.withAlphaComponent(0.9).cgColor); stroke(c, path, col, 1.5); c.restoreGState()
                stroke(c, path, col, 1.5)
                if p.role == .hero {   // corner brackets
                    c.setFillColor(hex(0xFCEE0A).cgColor)
                    c.fill(CGRect(x: r.maxX - 22, y: r.minY + 4, width: 16, height: 2)); c.fill(CGRect(x: r.maxX - 8, y: r.minY + 4, width: 2, height: 10))
                }
            }
        case .ceramic:
            if p.role == .accent {
                c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: -7), blur: 16, color: hex(0xC2410C, 0.45).cgColor); fill(c, path, hex(0xFF6A1A)); c.restoreGState()
                linear(c, path, [hex(0xFF9A4D), hex(0xFF6A1A), hex(0xE5520C)], [0, 0.5, 1], from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.maxX, y: r.maxY))
            } else if p.role == .screen || p.role == .pressed {
                let base = p.role == .screen ? hex(0xE6E5E0) : hex(0xDAD8D3)
                fill(c, path, base)
                c.saveGState(); c.addPath(path); c.clip()
                c.setShadow(offset: CGSize(width: 0, height: -3), blur: 7, color: hex(0x000000, 0.22).cgColor)
                c.addRect(r.insetBy(dx: -20, dy: -20)); c.addPath(path); c.setFillColor(base.cgColor); c.fillPath(using: .evenOdd)
                c.restoreGState()
            } else {
                let big = p.role == .hero || p.role == .bar
                c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: big ? -9 : -7), blur: big ? 18 : 14, color: hex(0x55503F, 0.22).cgColor)
                fill(c, path, hex(0xFFFFFF)); c.restoreGState()
                linear(c, path, [hex(0xFFFFFF), p.role == .op ? hex(0xECEBE7) : hex(0xF6F5F2)], [0, 1], from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.minX, y: r.maxY))
                stroke(c, rr(r.insetBy(dx: 0.5, dy: 0.5), p.rad - 0.5), hex(0xFFFFFF), 1)
            }
        case .ember:
            switch p.role {
            case .hero: fill(c, path, hex(0xFFFFFF))
            case .accent: linear(c, path, [hex(0xFF8A2A), hex(0xE2560C)], [0, 1], from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.minX, y: r.maxY))
            case .round: fill(c, path, hex(0x1E1E1E))
            case .screen: fill(c, path, hex(0x0A0A0A, 0.95)); stroke(c, rr(r.insetBy(dx: 0.5, dy: 0.5), p.rad - 0.5), hex(0xFFFFFF, 0.06), 1)
            default:
                let down = p.role == .pressed
                fill(c, path, down ? hex(0x3A2416, 0.95) : hex(0x161616, 0.92))
                linear(c, path, [hex(0xFFFFFF, 0.07), hex(0xFFFFFF, 0)], [0, 0.5], from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.minX, y: r.maxY))
                stroke(c, rr(r.insetBy(dx: 0.5, dy: 0.5), p.rad - 0.5), down ? hex(0xFF7A1A, 0.8) : hex(0xFFFFFF, 0.08), 1)
            }
        case .midnight:
            if p.role == .accent {
                c.saveGState(); c.setShadow(offset: .zero, blur: 16, color: hex(0x6E9BFF, 0.6).cgColor); fill(c, path, hex(0xFFFFFF)); c.restoreGState()
            } else {
                c.saveGState(); c.addPath(path); c.clip(); draw(c, midBG!, in: CGRect(x: 0, y: 0, width: W, height: H)); c.restoreGState()
                let tintCol: NSColor = p.role == .pressed ? hex(0x2F6BFF, 0.55) : p.role == .screen ? hex(0x030820, 0.6) : p.role == .hero ? hex(0x14308C, 0.5) : hex(0x0E2470, 0.45)
                fill(c, path, tintCol)
                if p.role != .screen {
                    linear(c, path, [hex(0xFFFFFF, 0.10), hex(0xFFFFFF, 0)], [0, 0.6], from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.minX, y: min(r.maxY, r.minY + 90)))
                }
                stroke(c, rr(r.insetBy(dx: 0.5, dy: 0.5), p.rad - 0.5), hex(0x8FB0FF, p.role == .pressed ? 0.8 : p.role == .hero ? 0.4 : 0.28), 1)
            }
        default: break
        }
    }
}

// MARK: Text helpers

/// Text with the style's legibility treatment (soft shadow on glass).
func lbl(_ s: SID, _ c: CGContext, _ str: String, _ f: NSFont, _ col: NSColor, center p: CGPoint) {
    c.saveGState()
    if s.glass { c.setShadow(offset: CGSize(width: 0, height: s == .glassNight ? -1 : 1), blur: 3, color: (s == .glassNight ? hex(0, 0.45) : hex(0xFFFFFF, 0.6)).cgColor) }
    text(c, str, f, col, center: p); c.restoreGState()
}
func lbl(_ s: SID, _ c: CGContext, _ str: String, _ f: NSFont, _ col: NSColor, left p: CGPoint, kern: CGFloat = 0) {
    c.saveGState()
    if s.glass { c.setShadow(offset: CGSize(width: 0, height: s == .glassNight ? -1 : 1), blur: 3, color: (s == .glassNight ? hex(0, 0.45) : hex(0xFFFFFF, 0.6)).cgColor) }
    text(c, str, f, col, left: p, kern: kern); c.restoreGState()
}
func width(_ str: String, _ f: NSFont, kern: CGFloat = 0) -> CGFloat {
    NSAttributedString(string: str, attributes: [.font: f, .kern: kern]).size().width
}
func lblRight(_ s: SID, _ c: CGContext, _ str: String, _ f: NSFont, _ col: NSColor, right x: CGFloat, y: CGFloat) {
    lbl(s, c, str, f, col, left: CGPoint(x: x - width(str, f), y: y))
}
func ico(_ s: SID, _ c: CGContext, _ k: Icon, center p: CGPoint, size: CGFloat, _ col: NSColor, lw: CGFloat = 1.8) {
    c.saveGState()
    if s.glass { c.setShadow(offset: CGSize(width: 0, height: s == .glassNight ? -1 : 1), blur: 3, color: (s == .glassNight ? hex(0, 0.45) : hex(0xFFFFFF, 0.6)).cgColor) }
    if s == .cyber { c.setShadow(offset: .zero, blur: 5, color: col.withAlphaComponent(0.8).cgColor) }
    icon(c, k, CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size), col, lw); c.restoreGState()
}

// Extra 5×7 glyphs for the dot-matrix numbers.
var dotTable: [Character: [String]] = {
    var d = dots
    d["÷"] = ["00000", "00100", "00000", "11111", "00000", "00100", "00000"]
    d["×"] = ["00000", "10001", "01010", "00100", "01010", "10001", "00000"]
    d["="] = ["00000", "00000", "11111", "00000", "11111", "00000", "00000"]
    d["."] = ["00000", "00000", "00000", "00000", "00000", "01100", "01100"]
    d[":"] = ["00000", "01100", "01100", "00000", "01100", "01100", "00000"]
    d["%"] = ["11001", "11010", "00010", "00100", "01000", "01011", "10011"]
    d["°"] = ["01100", "10010", "10010", "01100", "00000", "00000", "00000"]
    d["C"] = ["01110", "10001", "10000", "10000", "10000", "10001", "01110"]
    return d
}()
func dotString(_ c: CGContext, _ str: String, left x: CGFloat, midY y: CGFloat, pitch: CGFloat, on: NSColor, off: NSColor?) {
    var cx = x + pitch * 2
    for ch in str {
        let narrow = ch == ":" || ch == "." || ch == "°"
        if narrow { cx -= pitch }
        if let g = dotTable[ch] {
            let x0 = cx - pitch * 2, y0 = y - pitch * 3
            for (ry, row) in g.enumerated() { for (rx, v) in row.enumerated() {
                let r = CGRect(x: x0 + CGFloat(rx) * pitch - pitch * 0.4, y: y0 + CGFloat(ry) * pitch - pitch * 0.4, width: pitch * 0.8, height: pitch * 0.8)
                if v == "1" { c.setFillColor(on.cgColor); c.fillEllipse(in: r) } else if let off, !narrow { c.setFillColor(off.cgColor); c.fillEllipse(in: r) }
            } }
        }
        cx += narrow ? pitch * 4 : pitch * 6
    }
}
func dotWidth(_ str: String, pitch: CGFloat) -> CGFloat {
    str.reduce(CGFloat(0)) { $0 + ((($1 == ":" || $1 == "." || $1 == "°") ? 3 : 6) * pitch) } - pitch
}

/// A large display number in the style's number face.
func bigNum(_ s: SID, _ c: CGContext, _ str: String, left x: CGFloat, midY y: CGFloat, size: CGFloat, _ col: NSColor) {
    switch s {
    case .midnight:
        dotString(c, str, left: x, midY: y, pitch: size / 9, on: col, off: hex(0xFFFFFF, 0.06))
    case .cyber:
        let f = mono(size * 0.9, .heavy)
        text(c, str, f, hex(0xFF2A6D, 0.75), left: CGPoint(x: x - 1.5, y: y))
        text(c, str, f, hex(0x05D9E8, 0.75), left: CGPoint(x: x + 1.5, y: y))
        text(c, str, f, col, left: CGPoint(x: x, y: y))
    case .ceramic, .ember: lbl(s, c, str, sf(size, .medium), col, left: CGPoint(x: x, y: y), kern: -size * 0.02)
    default: lbl(s, c, str, sf(size, .light), col, left: CGPoint(x: x, y: y), kern: -size * 0.02)
    }
}
func bigNumWidth(_ s: SID, _ str: String, size: CGFloat) -> CGFloat {
    switch s {
    case .midnight: return dotWidth(str, pitch: size / 9)
    case .cyber: return width(str, mono(size * 0.9, .heavy))
    case .ceramic, .ember: return width(str, sf(size, .medium), kern: -size * 0.02)
    default: return width(str, sf(size, .light), kern: -size * 0.02)
    }
}

// MARK: Header (app top bar)

func headerPanels(_ s: SID, back: Bool) -> [Panel] {
    guard back else { return [] }
    switch s {
    case .glassNight, .glassDay: return [Panel(r: CGRect(x: 14, y: 40, width: 40, height: 40), rad: 20, role: .round)]
    case .ceramic: return [Panel(r: CGRect(x: 12, y: 42, width: 74, height: 34), rad: 17, role: .round)]
    case .ember, .midnight: return [Panel(r: CGRect(x: 12, y: 42, width: 38, height: 38), rad: 19, role: .round)]
    case .cyber: return []
    }
}

func header(_ s: SID, _ c: CGContext, title: String, sub: String, code: String, back: Bool) {
    switch s {
    case .glassNight, .glassDay:
        let ink = s.ink(.tile)
        if back {
            chevron(c, at: CGPoint(x: 33, y: 60), size: 6.5, ink, 2.2)
            lbl(s, c, title, sf(22, .semibold), ink, left: CGPoint(x: 66, y: 54))
            lbl(s, c, sub, sf(11, .medium), s.sub(.tile), left: CGPoint(x: 67, y: 74))
        } else {
            lbl(s, c, title, sf(30, .bold), ink, left: CGPoint(x: 16, y: 58), kern: -0.5)
            lbl(s, c, sub, sf(11, .medium), s.sub(.tile), left: CGPoint(x: 17, y: 80))
        }
    case .cyber:
        let cyan = hex(0x05D9E8), pink = hex(0xFF2A6D), yellow = hex(0xFCEE0A)
        c.setFillColor(pink.cgColor); c.fill(CGRect(x: 12, y: 44, width: 3, height: 32))
        if back { text(c, "◂ HOME", mono(10, .bold), cyan, left: CGPoint(x: 22, y: 52)) }
        else { text(c, "SYS//ONLINE", mono(10, .bold), cyan, left: CGPoint(x: 22, y: 52)) }
        let t = title.uppercased()
        let f = mono(t.count > 10 ? 17 : 22, .heavy)
        text(c, t, f, hex(0xFF2A6D, 0.7), left: CGPoint(x: 20.5, y: 70))
        text(c, t, f, hex(0xF5F5F5), left: CGPoint(x: 22, y: 70))
        text(c, code, mono(7.5, .medium), yellow.withAlphaComponent(0.8), left: CGPoint(x: 196, y: 72))
        c.setFillColor(cyan.withAlphaComponent(0.6).cgColor); c.fill(CGRect(x: 196, y: 80, width: 112, height: 1))
    case .ceramic:
        let ink = hex(0x1F2025)
        if back {
            chevron(c, at: CGPoint(x: 30, y: 59), size: 5.5, ink, 2)
            text(c, "Home", sf(13, .medium), ink, left: CGPoint(x: 40, y: 59))
            lblRight(s, c, title, sf(22, .semibold), ink, right: 308, y: 54)
            let sw = width(sub, sf(10))
            c.setFillColor(hex(0xFF6A1A).cgColor); c.fillEllipse(in: CGRect(x: 308 - sw - 9, y: 70, width: 5, height: 5))
            text(c, sub, sf(10), hex(0x6B6A64), left: CGPoint(x: 308 - sw, y: 73))
        } else {
            text(c, title, sf(30, .bold), ink, left: CGPoint(x: 16, y: 58), kern: -0.5)
            c.setFillColor(hex(0xFF6A1A).cgColor); c.fillEllipse(in: CGRect(x: 16 + width(title, sf(30, .bold), kern: -0.5) + 2, y: 64, width: 7, height: 7))
            text(c, sub, sf(11), hex(0x6B6A64), left: CGPoint(x: 17, y: 80))
        }
    case .ember:
        if back {
            chevron(c, at: CGPoint(x: 30, y: 61), size: 6.5, hex(0xFFFFFF), 2)
            text(c, title, sf(22, .medium), hex(0xFFFFFF), left: CGPoint(x: 62, y: 55))
            text(c, sub, sf(11), hex(0xFF7A1A), left: CGPoint(x: 63, y: 74))
        } else {
            text(c, title, sf(30, .semibold), hex(0xFFFFFF), left: CGPoint(x: 16, y: 58), kern: -0.5)
            text(c, sub, sf(11), hex(0xFF7A1A), left: CGPoint(x: 17, y: 80))
        }
    case .midnight:
        if back {
            c.addEllipse(in: CGRect(x: 12.5, y: 42.5, width: 37, height: 37)); c.setStrokeColor(hex(0x8FB0FF, 0.4).cgColor); c.setLineWidth(1); c.strokePath()
            chevron(c, at: CGPoint(x: 30, y: 61), size: 6.5, hex(0xFFFFFF), 2)
            text(c, title, sf(20, .semibold), hex(0xFFFFFF), center: CGPoint(x: 166, y: 56))
            text(c, sub.uppercased(), mono(9, .medium), hex(0x5CF2C9), center: CGPoint(x: 166, y: 76), kern: 1.5)
        } else {
            text(c, title, sf(28, .bold), hex(0xFFFFFF), center: CGPoint(x: 160, y: 56))
            text(c, sub.uppercased(), mono(9, .medium), hex(0x5CF2C9), center: CGPoint(x: 160, y: 79), kern: 1.5)
        }
    }
}

/// When set, the top bar is drawn in this style instead of the page's.
nonisolated(unsafe) var topBarStyle: SID? = nil

func finish(_ s: SID, _ c: CGContext) {
    // In the screen art the top bar is left out: the screen draws it from its own records.
    if !exportBG { TopBarKit(topBarStyle ?? s).draw(into: c, tbState) }
    if s == .cyber { for y in stride(from: 0, to: H, by: 3) { c.setFillColor(hex(0x000000, 0.16).cgColor); c.fill(CGRect(x: 0, y: y, width: W, height: 1)) } }
}

/// Small touch-code tag (Cyberpunk only), e.g. "0x22".
func tag(_ s: SID, _ c: CGContext, _ r: CGRect, _ code: Int, _ col: NSColor) {
    guard s == .cyber else { return }
    text(c, String(format: "0x%02X", code), mono(7, .medium), col.withAlphaComponent(0.6), left: CGPoint(x: r.minX + 6, y: r.maxY - 7))
}
