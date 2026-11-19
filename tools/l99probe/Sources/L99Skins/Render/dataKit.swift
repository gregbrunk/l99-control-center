// Real-time Data as the screen builds it: a background without the live parts, plus digit sets,
// date/weekday glyphs, weather icons and bar images, all in the page's style.
import AppKit

struct DataKit {
    let s: SID
    init(_ s: SID) { self.s = s }

    static let hero = CGRect(x: 12, y: 94, width: 296, height: 112)
    static let cards = [CGRect(x: 12, y: 216, width: 144, height: 112), CGRect(x: 164, y: 216, width: 144, height: 112),
                        CGRect(x: 12, y: 338, width: 144, height: 128), CGRect(x: 164, y: 338, width: 144, height: 128)]
    // Live widget anchors: top-left for clock/date/weekday/icon/bars; right edge + top for numbers.
    static let time = (28, 104), weekday = (30, 160), date = (30, 182), weather = (244, 110)
    static let high = (282, 176)
    static let numberTop = (mid: 258, cpu: 376)
    /// Numbers are right-aligned at these edges; three digits fit between the card's left padding and the edge.
    func numberRight(_ card: CGRect, size: CGFloat) -> Int { Int(card.minX) + 14 + 3 * glyphW(size) }
    var temp: (Int, Int) { (numberRight(Self.cards[0], size: midSize), Self.numberTop.mid) }
    var hum: (Int, Int) { (numberRight(Self.cards[1], size: midSize), Self.numberTop.mid) }
    var cpu: (Int, Int) { (numberRight(Self.cards[2], size: cpuSize), Self.numberTop.cpu) }
    var gpu: (Int, Int) { (numberRight(Self.cards[3], size: cpuSize), Self.numberTop.cpu) }
    static let humBar = (178, 302), cpuBar = (26, 426), barW = 116, barH = 6

    // Number faces: time (HH:MM:SS) must fit left of the weather icon.
    /// Number sizes: the largest that fits "100" plus its unit inside a card.
    func fitting(_ start: CGFloat, unit: CGFloat) -> CGFloat {
        var size = start
        while size > 20, 14 + 3 * glyphW(size) + 3 + Int(ceil(width("%", s.font(unit)))) + 10 > Int(Self.cards[0].width) { size -= 1 }
        return size
    }
    var midSize: CGFloat { fitting(34, unit: 16) }
    var cpuSize: CGFloat { fitting(40, unit: 18) }
    var timeSize: CGFloat {
        var size: CGFloat = 40
        while size > 24, 6 * glyphW(size) + 2 * colonW(size) > 206 { size -= 1 }
        return size
    }
    func glyphW(_ size: CGFloat) -> Int { Int(ceil((0...9).map { bigNumWidth(s, "\($0)", size: size) }.max()!)) + (s == .cyber ? 4 : 2) }
    func colonW(_ size: CGFloat) -> Int { Int(ceil(bigNumWidth(s, ":", size: size))) + 4 }
    func glyphH(_ size: CGFloat) -> Int { Int(ceil(size * 0.78)) + 6 }

    private func numGlyph(_ str: String, size: CGFloat, width w: Int, _ col: NSColor) -> CGContext {
        let h = glyphH(size)
        return sprite(w, h) { c in
            let tw = bigNumWidth(s, str, size: size)
            bigNum(s, c, str, left: (CGFloat(w) - tw) / 2, midY: CGFloat(h) / 2, size: size, col)
        }
    }
    /// 10 digits, then (for the clock) 4 colon frames.
    func digits(size: CGFloat, colons: Bool, _ col: NSColor) -> [CGContext] {
        let w = glyphW(size)
        var out = (0...9).map { numGlyph("\($0)", size: size, width: w, col) }
        if colons { let c = numGlyph(":", size: size, width: colonW(size), col); out += Array(repeating: c, count: 4) }
        return out
    }
    func timeDigits() -> [CGContext] { digits(size: timeSize, colons: true, s.ink(.hero)) }
    func midDigits() -> [CGContext] { digits(size: midSize, colons: false, s.ink(.tile)) }
    func cpuDigits() -> [CGContext] { digits(size: cpuSize, colons: false, s.ink(.tile)) }

    /// The date/weekday run (21 icons, as the screen's clock records expect): digits 0–9, four "/",
    /// then Sun…Sat. The digits also show the day's high in the hero card.
    var smallFont: NSFont { s.font(12.5, .medium) }
    var dayFont: NSFont { s.font(14, .semibold) }
    func dateRun() -> [CGContext] {
        let f = smallFont, col = s.sub(.hero), h = 17
        let w = Int(ceil((0...9).map { width("\($0)", f) }.max()!)) + 1
        var out = (0...9).map { d in sprite(w, h) { c in lbl(s, c, "\(d)", f, col, center: CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) / 2)) } }
        let sw = Int(ceil(width("/", f))) + 3
        out += Array(repeating: sprite(sw, h) { c in lbl(s, c, "/", f, col, center: CGPoint(x: CGFloat(sw) / 2, y: CGFloat(h) / 2)) }, count: 4)
        for d in ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"] {
            let name = s.caps(d), dw = Int(ceil(width(name, dayFont))) + 2
            out.append(sprite(dw, 19) { c in lbl(s, c, name, dayFont, s.ink(.hero), left: CGPoint(x: 1, y: 9.5)) })
        }
        return out
    }

    /// Weather conditions as our Mac app sends them: 0 clear, 1 partly cloudy, 2 cloudy, 3 rain, 4 storm, 5 snow.
    func weather(_ k: Int) -> CGContext {
        let n = 56, ink = s.ink(.hero)
        let darkInk = ink.usingColorSpace(.sRGB).map { $0.redComponent + $0.greenComponent + $0.blueComponent < 1.2 } ?? false
        let sun = s == .cyber ? hex(0xFCEE0A) : s == .midnight ? hex(0x5CF2C9) : hex(darkInk ? 0xFF8A1F : 0xFFC86B)
        return sprite(n, n) { c in
            c.saveGState()
            if !darkInk { c.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: hex(0, 0.45).cgColor) }
            c.setLineWidth(2.4); c.setLineCap(.round); c.setLineJoin(.round)
            func cloud(_ r: CGRect, _ col: NSColor) {
                let p = CGMutablePath(), b = r.maxY
                p.move(to: CGPoint(x: r.minX + r.height * 0.45, y: b))
                p.addLine(to: CGPoint(x: r.maxX - r.height * 0.4, y: b))
                p.addArc(center: CGPoint(x: r.maxX - r.height * 0.4, y: b - r.height * 0.4), radius: r.height * 0.4, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
                p.addArc(center: CGPoint(x: r.midX, y: r.minY + r.height * 0.5), radius: r.height * 0.5, startAngle: -.pi * 0.08, endAngle: -.pi * 0.92, clockwise: true)
                p.addArc(center: CGPoint(x: r.minX + r.height * 0.45, y: b - r.height * 0.45), radius: r.height * 0.45, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
                p.closeSubpath()
                c.addPath(p); c.setFillColor(ink.withAlphaComponent(0.12).cgColor); c.fillPath()
                c.addPath(p); c.setStrokeColor(col.cgColor); c.strokePath()
            }
            func sunAt(_ p: CGPoint, _ r: CGFloat) {
                c.setStrokeColor(sun.cgColor); c.setFillColor(sun.cgColor)
                c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                for i in 0..<8 {
                    let a = CGFloat(i) * .pi / 4
                    c.move(to: CGPoint(x: p.x + (r + 4) * cos(a), y: p.y + (r + 4) * sin(a))); c.addLine(to: CGPoint(x: p.x + (r + 8) * cos(a), y: p.y + (r + 8) * sin(a)))
                }
                c.strokePath()
            }
            let rain = s.light || darkInk ? hex(0x2F86E0) : hex(0x8EC9FF), bolt = darkInk ? hex(0xF0A800) : hex(0xFFD24D)
            switch k {
            case 0: sunAt(CGPoint(x: 28, y: 28), 9)
            case 1: sunAt(CGPoint(x: 20, y: 20), 7); cloud(CGRect(x: 14, y: 24, width: 36, height: 20), ink)
            case 2: cloud(CGRect(x: 4, y: 14, width: 32, height: 18), ink.withAlphaComponent(0.55)); cloud(CGRect(x: 8, y: 18, width: 40, height: 22), ink)
            case 3:
                cloud(CGRect(x: 8, y: 10, width: 40, height: 22), ink)
                c.setStrokeColor(rain.cgColor)
                for x in [17, 27, 37] { c.move(to: CGPoint(x: x, y: 38)); c.addLine(to: CGPoint(x: x - 3, y: 48)) }; c.strokePath()
            case 4:
                cloud(CGRect(x: 8, y: 8, width: 40, height: 22), ink)
                let p = CGMutablePath(); p.move(to: CGPoint(x: 30, y: 31)); p.addLine(to: CGPoint(x: 23, y: 42)); p.addLine(to: CGPoint(x: 29, y: 42)); p.addLine(to: CGPoint(x: 25, y: 52))
                c.addPath(p); c.setStrokeColor(bolt.cgColor); c.strokePath()
            default:
                cloud(CGRect(x: 8, y: 8, width: 40, height: 22), ink)
                c.setFillColor(ink.cgColor)
                for (x, y) in [(17, 40), (28, 44), (39, 40), (22, 50), (34, 50)] { c.fillEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)) }
            }
            c.restoreGState()
        }
    }

    /// Bar images: the screen reveals the fill in proportion to the value, over the track.
    func barTrack() -> CGContext { sprite(Self.barW, Self.barH) { c in meter(s, c, CGRect(x: 0, y: 0, width: Self.barW, height: Self.barH), 0) } }
    func barFill() -> CGContext { sprite(Self.barW, Self.barH) { c in meter(s, c, CGRect(x: 0, y: 0, width: Self.barW, height: Self.barH), 1) } }

    // MARK: Page

    /// The page without its live parts (exportBG), or with sample values for previews.
    func layout() -> ([Panel], (CGContext) -> Void) {
        var panels = headerPanels(s, back: true)
        panels.append(Panel(r: Self.hero, rad: s.glass ? 28 : 22, role: .hero))
        panels += Self.cards.map { Panel(r: $0, rad: s.glass ? 26 : tileRad(s), role: .tile) }
        let live = !exportBG
        let content: (CGContext) -> Void = { c in
            header(s, c, title: "Real-time Data", sub: "Live from your Mac", code: "//SYS.19  TELEMETRY", back: true)
            let info: [(String, Icon, String)] = [("Air temp", .thermo, "Outside"), ("Humidity", .drop, ""), ("CPU", .chip, "Mac load"), ("GPU", .gpu, "Mac load")]
            for (r, d) in zip(Self.cards, info) {
                lbl(s, c, s.caps(d.0), s.font(12, .semibold), s.sub(.tile), left: CGPoint(x: r.minX + 14, y: r.minY + 20))
                ico(s, c, d.1, center: CGPoint(x: r.maxX - 24, y: r.minY + 22), size: 20, s.ink(.op), lw: 1.7)
                if !d.2.isEmpty { lbl(s, c, s.caps(d.2), s.font(9.5), s.sub(.tile), left: CGPoint(x: r.minX + 14, y: r.maxY - (r.height > 120 ? 17 : 18))) }
            }
            func unit(_ u: String, _ a: (Int, Int), size: CGFloat, glyph: CGFloat) {
                lbl(s, c, u, s.font(size), s.sub(.tile), left: CGPoint(x: CGFloat(a.0) + 3, y: CGFloat(a.1) + CGFloat(glyphH(glyph)) / 2))
            }
            unit(temperatureUnit, temp, size: 16, glyph: midSize); unit("%", hum, size: 16, glyph: midSize)
            unit("%", cpu, size: 18, glyph: cpuSize); unit("%", gpu, size: 18, glyph: cpuSize)
            // The day's high, beside the weather icon, in the date digits.
            lblRight(s, c, s.caps("High"), s.font(9.5, .medium), s.sub(.hero), right: CGFloat(Self.high.0) - 24, y: CGFloat(Self.high.1) + 9)
            lbl(s, c, "°", smallFont, s.sub(.hero), left: CGPoint(x: CGFloat(Self.high.0) + 1, y: CGFloat(Self.high.1) + 8.5))
            guard live else { return }
            // Sample values, drawn with the same sprites the screen will use.
            func put(_ sp: CGContext, _ x: Int, _ y: Int) { draw(c, sp.makeImage()!, in: CGRect(x: x, y: y, width: sp.width, height: sp.height)) }
            func row(_ glyphs: [CGContext], _ str: String, left x0: Int, top y: Int, map: (Character) -> Int) {
                var x = x0; for ch in str { let g = glyphs[map(ch)]; put(g, x, y); x += g.width }
            }
            func rightAligned(_ glyphs: [CGContext], _ str: String, right: Int, top: Int) {
                let w = str.reduce(0) { $0 + glyphs[Int(String($1))!].width }
                row(glyphs, str, left: right - w, top: top) { Int(String($0))! }
            }
            let digit: (Character) -> Int = { $0 == ":" ? 10 : Int(String($0))! }
            row(timeDigits(), "11:32:08", left: Self.time.0, top: Self.time.1, map: digit)
            let run = dateRun()
            put(run[17], Self.weekday.0, Self.weekday.1)
            row(run, "2026/11/18", left: Self.date.0, top: Self.date.1) { $0 == "/" ? 10 : Int(String($0))! }
            put(weather(1), Self.weather.0, Self.weather.1)
            rightAligned(run, "14", right: Self.high.0, top: Self.high.1)
            rightAligned(midDigits(), "23", right: temp.0, top: temp.1)
            rightAligned(midDigits(), "100", right: hum.0, top: hum.1)
            rightAligned(cpuDigits(), "42", right: cpu.0, top: cpu.1)
            rightAligned(cpuDigits(), "100", right: gpu.0, top: gpu.1)
            for (b, v) in [(Self.humBar, 0.48), (Self.cpuBar, 0.42)] {
                put(barTrack(), b.0, b.1)
                let f = barFill(), w = Int(Double(Self.barW) * v)
                draw(c, f.makeImage()!.cropping(to: CGRect(x: 0, y: 0, width: w, height: Self.barH))!, in: CGRect(x: b.0, y: b.1, width: w, height: Self.barH))
            }
        }
        return (panels, content)
    }
}
