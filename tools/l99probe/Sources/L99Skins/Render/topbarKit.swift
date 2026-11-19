// The top bar as the screen draws it: one sprite per indicator state, placed by the screen's own
// records. The same sprites are composited for previews, so a preview shows exactly what gets installed.
import AppKit

struct TopBarKit {
    let s: SID
    init(_ s: SID) { self.s = s }

    static let digitW = 8, colonW = 5, digitH = 14, pctW = 10, connW = 50, connH = 18, batW = 28, batH = 14, chipH = 15, lockW = 22
    // Screen positions (top-left; the battery % is right-aligned at pctRight).
    static let clock = (x: 12, y: 10), conn = (x: 58, y: 8), chipsX = 110, chipY = 9, pctRight = 268, pctY = 10, pctSign = (x: 269, y: 10), battery = (x: 283, y: 10)

    var colors: (ink: NSColor, dim: NSColor, accent: NSColor) {
        switch s {
        case .glassNight: (hex(0xFFFFFF, 0.95), hex(0xFFFFFF, 0.4), hex(0xB79BFF))
        case .glassDay: (hex(0x1C1930), hex(0x1C1930, 0.35), hex(0x5B3FD9))
        case .cyber: (hex(0x05D9E8), hex(0x05D9E8, 0.3), hex(0xFCEE0A))
        case .ceramic: (hex(0x1F2025), hex(0x1F2025, 0.3), hex(0xFF6A1A))
        case .ember: (hex(0xFFFFFF, 0.95), hex(0xFFFFFF, 0.3), hex(0xFF7A1A))
        case .midnight: (hex(0xDDE6FF), hex(0xFFFFFF, 0.25), hex(0x5CF2C9))
        }
    }
    var digitFont: NSFont { s == .cyber || s == .midnight ? mono(10, .bold) : sf(11, .semibold) }
    var labelFont: NSFont { s == .cyber || s == .midnight ? mono(8.5, .bold) : sf(9.5, .semibold) }
    var capsLabel: String { s == .cyber ? "CAPS" : "Caps" }

    private func chipWidth(_ label: String) -> Int {
        let scratch = newContext(80, 30)
        return Int(ceil(chip(s, scratch, label, x: 0, on: false)))
    }
    var capsW: Int { chipWidth(capsLabel) }
    var osW: Int { max(chipWidth("WIN"), chipWidth("MAC")) }

    // MARK: Sprites (transparent, top-left origin)

    func digit(_ d: Int) -> CGContext { sprite(Self.digitW, Self.digitH) { c in text(c, "\(d)", digitFont, colors.ink, center: CGPoint(x: 4, y: 7.5)) } }
    func colon() -> CGContext { sprite(Self.colonW, Self.digitH) { c in text(c, ":", digitFont, colors.ink, center: CGPoint(x: 2.5, y: 7)) } }
    func percent() -> CGContext { sprite(Self.pctW, Self.digitH) { c in text(c, "%", digitFont, colors.ink, center: CGPoint(x: 5, y: 7.5)) } }

    func chipSprite(_ label: String, on: Bool, width: Int) -> CGContext {
        sprite(width, Self.chipH) { c in c.translateBy(x: 0, y: -CGFloat(Self.chipY)); _ = chip(s, c, label, x: 0, on: on) }
    }
    func lockSprite(closed: Bool) -> CGContext {
        sprite(Self.lockW, Self.chipH) { c in c.translateBy(x: 0, y: -CGFloat(Self.chipY)); _ = chip(s, c, "", x: 0, on: closed, lockGlyph: true) }
    }

    /// Connection modes in the screen's order: 0 cable, 1 receiver, 2–4 the other channels.
    func connection(_ mode: Int) -> CGContext {
        sprite(Self.connW, Self.connH) { c in
            let ink = colors.ink, cy: CGFloat = 9
            c.setStrokeColor(ink.cgColor); c.setFillColor(ink.cgColor); c.setLineWidth(1.4); c.setLineCap(.round)
            let label: String
            switch mode {
            case 0:
                c.addPath(rr(CGRect(x: 2, y: cy - 4, width: 8, height: 8), 1.5)); c.strokePath()
                c.move(to: CGPoint(x: 10, y: cy)); c.addCurve(to: CGPoint(x: 18, y: cy - 3), control1: CGPoint(x: 14, y: cy), control2: CGPoint(x: 15, y: cy - 3)); c.strokePath()
                label = "USB"
            case 1:
                c.addPath(rr(CGRect(x: 1, y: cy - 2, width: 11, height: 7), 1.5)); c.strokePath()
                c.fill(CGRect(x: 12, y: cy - 0.5, width: 3.5, height: 4))
                for (i, rad) in [2.8, 5.3].enumerated() {
                    c.addArc(center: CGPoint(x: 6.5, y: cy - 4.5), radius: rad, startAngle: -.pi * 0.8, endAngle: -.pi * 0.2, clockwise: false)
                    c.setStrokeColor(ink.withAlphaComponent(i == 0 ? 1 : 0.6).cgColor); c.strokePath()
                }
                label = "2.4G"
            default:
                for (i, rad) in [2.5, 5.0, 7.5].enumerated() {
                    c.addArc(center: CGPoint(x: 3, y: cy), radius: rad, startAngle: -.pi * 0.3, endAngle: .pi * 0.3, clockwise: false)
                    c.setStrokeColor(ink.withAlphaComponent(1 - CGFloat(i) * 0.25).cgColor); c.strokePath()
                }
                label = "\(mode - 1)"
            }
            text(c, label, labelFont, ink, left: CGPoint(x: mode == 0 ? 22 : 20, y: cy + 0.5))
        }
    }

    /// Battery states in the screen's order: empty, low, rising levels, then charging.
    static let batteryLevels = [0, 12, 35, 55, 78, 100, 60]
    func battery(_ state: Int) -> CGContext {
        let pct = Self.batteryLevels[state], charging = state == 6, low = state <= 1
        let (ink, dim, accent) = colors
        return sprite(Self.batW, Self.batH) { c in
            let cy: CGFloat = 7, cell = CGRect(x: 0, y: 1, width: 24, height: 12)
            let lvlCol = charging ? hex(0x41E2A0) : low ? hex(0xFF4D5E) : (s == .cyber || s == .midnight ? accent : ink)
            switch s {
            case .cyber:
                stroke(c, chamfer(cell.insetBy(dx: 0.5, dy: 0.5), 3), low && !charging ? hex(0xFF4D5E) : ink, 1)
                for i in 0..<5 where CGFloat(i) < CGFloat(max(pct, low && pct > 0 ? 20 : pct)) / 100 * 5 {
                    c.setFillColor(lvlCol.cgColor); c.fill(CGRect(x: cell.minX + 2.5 + CGFloat(i) * 4.1, y: cell.minY + 2.5, width: 3.2, height: cell.height - 5))
                }
                c.setFillColor(ink.cgColor); c.fill(CGRect(x: cell.maxX + 1, y: cy - 2.5, width: 2, height: 5))
            case .midnight:
                stroke(c, rr(cell.insetBy(dx: 0.5, dy: 0.5), 4), low && !charging ? hex(0xFF4D5E) : hex(0x8FB0FF, 0.5), 1)
                for i in 0..<5 {
                    let on = pct > 0 && CGFloat(i) < max(1, CGFloat(pct) / 100 * 5)
                    c.setFillColor((on ? lvlCol : hex(0xFFFFFF, 0.1)).cgColor); c.fillEllipse(in: CGRect(x: cell.minX + 3 + CGFloat(i) * 3.8, y: cy - 1.6, width: 3.2, height: 3.2))
                }
                c.setFillColor(hex(0x8FB0FF, 0.5).cgColor); c.fill(CGRect(x: cell.maxX + 1, y: cy - 2, width: 1.5, height: 4))
            default:
                let edge = dim.withAlphaComponent(min(1, dim.alphaComponent * 1.6))
                stroke(c, rr(cell.insetBy(dx: 0.5, dy: 0.5), 3.5), low && !charging ? hex(0xFF4D5E) : edge, 1)
                let inner = cell.insetBy(dx: 2, dy: 2)
                if pct > 0 { fill(c, rr(CGRect(x: inner.minX, y: inner.minY, width: max(2.5, inner.width * CGFloat(pct) / 100), height: inner.height), 2), lvlCol) }
                c.setFillColor(edge.cgColor); c.fill(CGRect(x: cell.maxX + 1, y: cy - 2, width: 1.5, height: 4))
            }
            if charging {
                let p = CGMutablePath(), bx = cell.midX, by = cy
                p.move(to: CGPoint(x: bx + 1.5, y: by - 5)); p.addLine(to: CGPoint(x: bx - 2.5, y: by + 0.8)); p.addLine(to: CGPoint(x: bx, y: by + 0.8))
                p.addLine(to: CGPoint(x: bx - 1.5, y: by + 5)); p.addLine(to: CGPoint(x: bx + 2.5, y: by - 0.8)); p.addLine(to: CGPoint(x: bx, y: by - 0.8)); p.closeSubpath()
                fill(c, p, s.light ? hex(0x1F2025) : hex(0x000000, 0.85))
            }
        }
    }

    // MARK: Preview: composite the sprites the way the screen places them.

    func draw(into c: CGContext, _ st: TBState) {
        func put(_ sp: CGContext, _ x: Int, _ y: Int) { L99Skins.draw(c, sp.makeImage()!, in: CGRect(x: x, y: y, width: sp.width, height: sp.height)) }
        var x = Self.clock.x
        for ch in "01:44" { put(ch == ":" ? colon() : digit(Int(String(ch))!), x, Self.clock.y); x += ch == ":" ? Self.colonW : Self.digitW }
        put(connection(st.wired ? 0 : 1), Self.conn.x, Self.conn.y)
        x = Self.chipsX
        put(chipSprite(capsLabel, on: st.caps, width: capsW), x, Self.chipY); x += capsW + 4
        put(lockSprite(closed: st.lock), x, Self.chipY); x += Self.lockW + 4
        put(chipSprite(st.mac ? "MAC" : "WIN", on: false, width: osW), x, Self.chipY)
        let pct = String(st.pct)
        x = Self.pctRight - Self.digitW * pct.count
        for ch in pct { put(digit(Int(String(ch))!), x, Self.pctY); x += Self.digitW }
        put(percent(), Self.pctSign.x, Self.pctSign.y)
        let state = st.charging ? 6 : st.pct < 8 ? 0 : st.pct <= 20 ? 1 : st.pct < 45 ? 2 : st.pct < 65 ? 3 : st.pct < 90 ? 4 : 5
        put(battery(state), Self.battery.x, Self.battery.y)
    }
}
