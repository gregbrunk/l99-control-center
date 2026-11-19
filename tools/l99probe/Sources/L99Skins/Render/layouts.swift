// Page layouts: Home, Play, Real-time Data, Calculator. Each returns its panels and a content pass.
import AppKit

enum Page: String, CaseIterable { case home, homeHidden = "home-hidden", play, data, numpad, calculator }

func render(_ s: SID, _ page: Page) -> CGContext {
    let c = newContext()
    background(s, c)
    let (panels, content) = layout(s, page)
    drawPanels(s, c, panels)
    content(c)
    finish(s, c)
    return c
}

func layout(_ s: SID, _ page: Page) -> ([Panel], (CGContext) -> Void) {
    switch page {
    case .home: return home(s)
    case .homeHidden: return home(s, hidden: ["Photos", "Touchpad"])
    case .play: return play(s)
    case .data: return DataKit(s).layout()
    case .calculator: return calculator(s)
    case .numpad: return numpad(s)
    }
}

func tileRad(_ s: SID) -> CGFloat { s.glass ? 22 : s == .ember ? 18 : 16 }

// MARK: Home

let allTiles: [(Icon, String)] = [(.gear, "Settings"), (.screen, "Screen"), (.bulb, "Colour"), (.film, "GIFs"),
                                   (.photo, "Photos"), (.numpad, "Numpad"), (.calculator, "Calculator"), (.touchpad, "Touchpad")]

/// Tiles reflow to fill the grid area (y 200–364) when apps are hidden: 4 columns for 7–8, else 3.
func tileGrid(_ n: Int) -> [CGRect] {
    let cols = n > 6 ? 4 : 3, rows = (n + cols - 1) / cols, gap: CGFloat = 8
    let w = (296 - gap * CGFloat(cols - 1)) / CGFloat(cols), h = (164 - gap * CGFloat(rows - 1)) / CGFloat(rows)
    return (0..<n).map { i in CGRect(x: 12 + CGFloat(i % cols) * (w + gap), y: 200 + CGFloat(i / cols) * (h + gap), width: w, height: h) }
}

enum HomeSpec {
    static let heroes = [CGRect(x: 12, y: 94, width: 142, height: 96), CGRect(x: 166, y: 94, width: 142, height: 96)]
    static let bar = CGRect(x: 12, y: 380, width: 296, height: 78)
    /// The media bar's four touch zones: volume down, mute, volume up, alarm.
    static var zones: [CGRect] { (0..<4).map { CGRect(x: bar.minX + bar.width / 4 * CGFloat($0), y: bar.minY, width: bar.width / 4, height: bar.height) } }
}

func home(_ s: SID, hidden: Set<String> = [], mediaBar: Bool = true) -> ([Panel], (CGContext) -> Void) {
    let heroes = HomeSpec.heroes
    let tileInfo = allTiles.filter { !hidden.contains($0.1) }
    let tiles = tileGrid(tileInfo.count)
    let bar = HomeSpec.bar
    var panels = heroes.map { Panel(r: $0, rad: s.glass ? 26 : 20, role: .hero) }
    panels += tiles.map { Panel(r: $0, rad: tileRad(s), role: .tile) }
    panels.append(Panel(r: bar, rad: s.glass ? 39 : 24, role: .bar))
    let content: (CGContext) -> Void = { c in
        header(s, c, title: "L99", sub: s == .cyber ? "CONTROL_CENTER v1" : "Control Center", code: "//SYS.01  HOME", back: false)
        let heroInfo: [(Icon, String, String, Int)] = [(.note, "Play", "Music & volume", 18), (.chart, "Real-time Data", "Weather & system", 19)]
        for (r, h) in zip(heroes, heroInfo) {
            let iconCol = s == .glassNight ? hex(0xFFFFFF) : s.ink(.op)
            if s == .ember || s == .midnight || s == .ceramic {
                let disc = CGRect(x: r.minX + 12, y: r.minY + 12, width: 38, height: 38)
                c.addEllipse(in: disc)
                c.setFillColor((s == .ember ? hex(0xFF7A1A) : s == .ceramic ? hex(0xFF6A1A, 0.12) : hex(0x5CF2C9, 0.16)).cgColor); c.fillPath()
                ico(s, c, h.0, center: CGPoint(x: disc.midX, y: disc.midY), size: 20, s == .ember ? hex(0xFFFFFF) : iconCol)
            } else {
                ico(s, c, h.0, center: CGPoint(x: r.minX + 30, y: r.minY + 30), size: 26, iconCol, lw: 2)
            }
            chevron(c, at: CGPoint(x: r.maxX - 20, y: r.minY + 24), size: -5, s.sub(.hero), 1.8)
            var size: CGFloat = h.1.count > 10 ? 15 : 17
            while size > 11, width(s.caps(h.1), s.font(size, .semibold)) > r.width - 26 { size -= 0.5 }
            lbl(s, c, s.caps(h.1), s.font(size, .semibold), s.ink(.hero), left: CGPoint(x: r.minX + 14, y: r.maxY - 32))
            lbl(s, c, s.caps(h.2), s.font(10.5), s.sub(.hero), left: CGPoint(x: r.minX + 14, y: r.maxY - 14))
            tag(s, c, CGRect(x: r.maxX - 40, y: r.minY, width: 40, height: 20), h.3, hex(0xFCEE0A))
        }
        for (r, t) in zip(tiles, tileInfo) {
            ico(s, c, t.0, center: CGPoint(x: r.midX, y: r.midY - 9), size: 26, s.ink(.tile), lw: 1.7)
            let name = s.caps(t.1), f = s.font(name.count > 8 ? 9 : 10.5, .medium)
            lbl(s, c, name, f, s == .cyber ? hex(0xF5F5F5) : s.sub(.tile).withAlphaComponent(s.light ? 1 : 0.95), center: CGPoint(x: r.midX, y: r.maxY - 14))
        }
        // Media bar: four zones with hairline dividers.
        let zones: [(Icon, String, Int)] = [(.volDown, "Vol −", 0x22), (.mute, "Mute", 0x23), (.volUp, "Vol +", 0x24), (.alarm, "Alarm", 0xF1)]
        let zw = bar.width / 4
        for (i, z) in zones.enumerated() where mediaBar {
            let cx = bar.minX + zw * (CGFloat(i) + 0.5)
            let col = i == 3 ? s.ink(.op) : s.ink(.bar)
            ico(s, c, z.0, center: CGPoint(x: cx, y: bar.midY - 9), size: 24, col, lw: 1.8)
            lbl(s, c, s.caps(z.1), s.font(9.5, .medium), s.sub(.bar), center: CGPoint(x: cx, y: bar.maxY - 15))
            if i > 0 {
                let x = bar.minX + zw * CGFloat(i)
                let line = s.light ? hex(0x1C1930, 0.12) : s == .cyber ? hex(0x05D9E8, 0.35) : hex(0xFFFFFF, 0.14)
                c.setFillColor(line.cgColor); c.fill(CGRect(x: x - 0.5, y: bar.minY + 18, width: 1, height: bar.height - 36))
            }
        }
        if s == .cyber { text(c, "AUDIO_BUS //", mono(7, .medium), hex(0xFCEE0A, 0.7), left: CGPoint(x: bar.minX + 10, y: bar.minY - 6)) }
    }
    return (panels, content)
}

// MARK: Play

/// The keyboard's control program draws the visualiser bars itself (no artwork in the file), so they
/// look the same in every style. Shown here as a neutral stand-in; only the panel behind them is styled.
func vizBars(_ s: SID, _ c: CGContext, _ r: CGRect) {
    let n = 22, gap: CGFloat = 4, bw = (r.width - gap * CGFloat(n - 1)) / CGFloat(n)
    for i in 0..<n {
        let t = Double(i)
        let v = 0.18 + 0.82 * abs(sin(t * 0.55 + 0.4) * cos(t * 0.21 + 1.1)) * (1 - 0.35 * t / Double(n)) + 0.08 * sin(t * 2.3)
        let h = r.height * CGFloat(max(0.12, min(1, v)))
        let x = r.minX + CGFloat(i) * (bw + gap)
        let col = NSColor(calibratedHue: CGFloat(i) / CGFloat(n) * 0.8, saturation: 0.75, brightness: 0.95, alpha: 0.9)
        c.setFillColor(col.cgColor); c.fill(CGRect(x: x, y: r.maxY - h, width: bw, height: h))
    }
}

enum PlaySpec {
    static let prev = CGRect(x: 38, y: 106, width: 60, height: 60), next = CGRect(x: 222, y: 106, width: 60, height: 60)
    static let pp = CGRect(x: 114, y: 94, width: 92, height: 84)
    static let vol = CGRect(x: 12, y: 192, width: 296, height: 58)
    /// The keyboard draws the visualiser itself in a fixed black box: full width, from about y 300 to the
    /// bottom (measured from a photo, Nov 19). Everything from vizTop down is black so the exact edge doesn't show.
    static let vizTop: CGFloat = 288
}

func play(_ s: SID) -> ([Panel], (CGContext) -> Void) {
    let prev = PlaySpec.prev, next = PlaySpec.next, pp = PlaySpec.pp, vol = PlaySpec.vol, top = PlaySpec.vizTop
    var panels = headerPanels(s, back: true)
    panels += [Panel(r: prev, rad: 30, role: .tile), Panel(r: pp, rad: s == .cyber ? 20 : 42, role: .accent), Panel(r: next, rad: 30, role: .tile),
               Panel(r: vol, rad: s.glass ? 29 : 22, role: .bar)]
    let content: (CGContext) -> Void = { c in
        header(s, c, title: "Play", sub: "Media controls", code: "//SYS.18  MEDIA_CTRL", back: true)
        ico(s, c, .prev, center: CGPoint(x: prev.midX, y: prev.midY), size: 24, s.ink(.tile))
        ico(s, c, .next, center: CGPoint(x: next.midX, y: next.midY), size: 24, s.ink(.tile))
        ico(s, c, .playPause, center: CGPoint(x: pp.midX + 1, y: pp.midY), size: 38, s.ink(.accent))
        tag(s, c, prev, 0xB6, hex(0x05D9E8)); tag(s, c, next, 0xB5, hex(0x05D9E8)); tag(s, c, pp.insetBy(dx: 2, dy: 0), 0xCD, hex(0x07060B))
        // Volume capsule: − | mute + label | +
        ico(s, c, .volDown, center: CGPoint(x: vol.minX + 44, y: vol.midY), size: 24, s.ink(.bar))
        ico(s, c, .volUp, center: CGPoint(x: vol.maxX - 44, y: vol.midY), size: 24, s.ink(.bar))
        ico(s, c, .mute, center: CGPoint(x: vol.midX - 26, y: vol.midY), size: 20, s.ink(.op))
        lbl(s, c, s.caps("Volume"), s.font(13, .semibold), s.ink(.bar), left: CGPoint(x: vol.midX - 10, y: vol.midY - 6))
        lbl(s, c, s.caps("Tap to mute"), s.font(9), s.sub(.bar), left: CGPoint(x: vol.midX - 10, y: vol.midY + 10))
        for x in [vol.minX + 88, vol.maxX - 88] {
            let line = s.light ? hex(0x1C1930, 0.12) : s == .cyber ? hex(0x05D9E8, 0.35) : hex(0xFFFFFF, 0.14)
            c.setFillColor(line.cgColor); c.fill(CGRect(x: x - 0.5, y: vol.minY + 16, width: 1, height: vol.height - 32))
        }
        // Visualiser: a label row, then full-width black where the keyboard draws its bars.
        lbl(s, c, s.caps("Visualiser"), s.font(11, .semibold), s.sub(.tile), left: CGPoint(x: 16, y: top - 16))
        lblRight(s, c, s.caps("Moves while music plays"), s.font(8.5), s.sub(.tile), right: 304, y: top - 16)
        c.setFillColor(hex(0x000000).cgColor); c.fill(CGRect(x: 0, y: top, width: CGFloat(W), height: CGFloat(H) - top))
        let edge = s == .cyber ? hex(0x05D9E8, 0.6) : s == .midnight ? hex(0x5CF2C9, 0.5) : s.light ? hex(0x1C1930, 0.25) : hex(0xFFFFFF, 0.22)
        c.setFillColor(edge.cgColor); c.fill(CGRect(x: 0, y: top, width: CGFloat(W), height: 1))
        // Preview only: sample bars like the keyboard's.
        if !exportBG { vizBars(s, c, CGRect(x: 2, y: top + 40, width: CGFloat(W) - 4, height: CGFloat(H) - top - 44)) }
    }
    return (panels, content)
}

// MARK: Real-time Data

func meter(_ s: SID, _ c: CGContext, _ r: CGRect, _ frac: CGFloat, onDarkCard: Bool = true) {
    switch s {
    case .glassNight, .glassDay:
        fill(c, rr(r, r.height / 2), s == .glassNight ? hex(0xFFFFFF, 0.16) : hex(0x1C1930, 0.10))
        let f = CGRect(x: r.minX, y: r.minY, width: r.width * frac, height: r.height)
        c.saveGState(); c.setShadow(offset: .zero, blur: 6, color: hex(0xB79BFF, 0.7).cgColor)
        linear(c, rr(f, r.height / 2), [s == .glassNight ? hex(0xB79BFF) : hex(0x6B4FF0), hex(0xFF7EB6)], [0, 1], from: CGPoint(x: r.minX, y: 0), to: CGPoint(x: r.maxX, y: 0))
        c.restoreGState()
    case .cyber:
        let n = 18, gap: CGFloat = 2, w = (r.width - gap * CGFloat(n - 1)) / CGFloat(n)
        for i in 0..<n {
            let on = CGFloat(i) < frac * CGFloat(n)
            c.setFillColor((on ? (CGFloat(i) > 0.7 * CGFloat(n) ? hex(0xFF2A6D) : hex(0x05D9E8)) : hex(0x05D9E8, 0.12)).cgColor)
            c.fill(CGRect(x: r.minX + CGFloat(i) * (w + gap), y: r.minY, width: w, height: r.height))
        }
    case .ceramic:
        fill(c, rr(r, r.height / 2), hex(0xE6E5E0))
        fill(c, rr(CGRect(x: r.minX, y: r.minY, width: r.width * frac, height: r.height), r.height / 2), hex(0xFF6A1A))
    case .ember:
        fill(c, rr(r, r.height / 2), hex(0xFFFFFF, 0.08))
        linear(c, rr(CGRect(x: r.minX, y: r.minY, width: r.width * frac, height: r.height), r.height / 2), [hex(0xC2410C), hex(0xFF8A2A)], [0, 1],
               from: CGPoint(x: r.minX, y: 0), to: CGPoint(x: r.minX + r.width * frac, y: 0))
    case .midnight:
        let pitch: CGFloat = 7, n = Int(r.width / pitch)
        for i in 0..<n {
            let on = CGFloat(i) < frac * CGFloat(n)
            c.setFillColor((on ? hex(0x5CF2C9) : hex(0xFFFFFF, 0.08)).cgColor)
            c.fillEllipse(in: CGRect(x: r.minX + CGFloat(i) * pitch, y: r.midY - 2.5, width: 5, height: 5))
        }
    }
}

func data(_ s: SID) -> ([Panel], (CGContext) -> Void) {
    let hero = CGRect(x: 12, y: 94, width: 296, height: 112)
    let cards = [CGRect(x: 12, y: 216, width: 144, height: 112), CGRect(x: 164, y: 216, width: 144, height: 112),
                 CGRect(x: 12, y: 338, width: 144, height: 128), CGRect(x: 164, y: 338, width: 144, height: 128)]
    var panels = headerPanels(s, back: true)
    panels.append(Panel(r: hero, rad: s.glass ? 28 : 22, role: .hero))
    panels += cards.map { Panel(r: $0, rad: s.glass ? 26 : 20, role: .tile) }
    let content: (CGContext) -> Void = { c in
        header(s, c, title: "Real-time Data", sub: "Live from your Mac", code: "//SYS.19  TELEMETRY", back: true)
        // Clock hero.
        let timeSize: CGFloat = s == .midnight ? 54 : 58
        bigNum(s, c, "11:32", left: hero.minX + 18, midY: hero.minY + 50, size: timeSize, s.ink(.hero))
        lbl(s, c, s.caps("Wednesday"), s.font(14, .semibold), s.ink(.hero), left: CGPoint(x: hero.minX + 20, y: hero.maxY - 30))
        lbl(s, c, s.caps("18 November"), s.font(11), s.sub(.hero), left: CGPoint(x: hero.minX + 20, y: hero.maxY - 13))
        let dateX = hero.maxX - 18
        lblRight(s, c, s.caps("Wed"), s.font(12, .semibold), s.sub(.hero), right: dateX, y: hero.minY + 24)
        bigNum(s, c, "18", left: dateX - bigNumWidth(s, "18", size: 34), midY: hero.minY + 54, size: 34, s == .ember ? hex(0xFF7A1A) : s.ink(.op))
        // Weather, humidity, CPU, GPU.
        let info: [(String, Icon, String, CGFloat, String)] = [("Weather", .cloudSun, "23°C", 0, "Air temperature"), ("Humidity", .drop, "48%", 0.48, "Outside"),
                                                               ("CPU", .chip, "42%", 0.42, "Mac load"), ("GPU", .gpu, "17%", 0.17, "Mac load")]
        for (r, d) in zip(cards, info) {
            lbl(s, c, s.caps(d.0), s.font(12, .semibold), s.sub(.tile), left: CGPoint(x: r.minX + 14, y: r.minY + 20))
            ico(s, c, d.1, center: CGPoint(x: r.maxX - 24, y: r.minY + 22), size: d.1 == .cloudSun ? 26 : 20, s.ink(.op), lw: 1.7)
            let size: CGFloat = r.height > 120 ? 44 : 38
            bigNum(s, c, d.2, left: r.minX + 14, midY: r.minY + (r.height > 120 ? 64 : 58), size: size, s.ink(.tile))
            if d.3 > 0 {
                meter(s, c, CGRect(x: r.minX + 14, y: r.maxY - (r.height > 120 ? 30 : 22), width: r.width - 28, height: s == .midnight ? 6 : 6), d.3)
                if r.height > 120 { lbl(s, c, s.caps(d.4), s.font(9.5), s.sub(.tile), left: CGPoint(x: r.minX + 14, y: r.maxY - 12)) }
            } else {
                lbl(s, c, s.caps(d.4), s.font(9.5), s.sub(.tile), left: CGPoint(x: r.minX + 14, y: r.maxY - 18))
            }
        }
    }
    return (panels, content)
}

// MARK: Calculator

/// A touch key: its label, rectangle and panel role. The builder uses the same rectangles for the
/// touch areas, so art and taps always line up.
struct KeySpec { let label: String; let rect: CGRect; let role: Role }

func calculatorDisplay(_ s: SID) -> CGRect { exportBG ? CGRect(x: 12, y: 84, width: 296, height: 66) : CGRect(x: 12, y: 92, width: 296, height: 58) }

func calculatorKeys(_ s: SID) -> [KeySpec] {
    let top: CGFloat = 160, kh: CGFloat = 54, gap: CGFloat = 8, kw: CGFloat = 68
    func cell(_ col: Int, _ row: Int, _ cs: Int = 1, _ rs: Int = 1) -> CGRect {
        CGRect(x: 12 + CGFloat(col) * (kw + gap), y: top + CGFloat(row) * (kh + gap), width: kw * CGFloat(cs) + gap * CGFloat(cs - 1), height: kh * CGFloat(rs) + gap * CGFloat(rs - 1))
    }
    return [
        KeySpec(label: "C", rect: cell(0, 0), role: .op), KeySpec(label: "÷", rect: cell(1, 0), role: .op),
        KeySpec(label: "×", rect: cell(2, 0), role: .op), KeySpec(label: "⌫", rect: cell(3, 0), role: .op),
        KeySpec(label: "7", rect: cell(0, 1), role: .tile), KeySpec(label: "8", rect: cell(1, 1), role: .tile),
        KeySpec(label: "9", rect: cell(2, 1), role: .tile), KeySpec(label: "+", rect: cell(3, 1), role: .op),
        KeySpec(label: "4", rect: cell(0, 2), role: .tile), KeySpec(label: "5", rect: cell(1, 2), role: .tile),
        KeySpec(label: "6", rect: cell(2, 2), role: .tile), KeySpec(label: "−", rect: cell(3, 2), role: .op),
        KeySpec(label: "1", rect: cell(0, 3), role: .tile), KeySpec(label: "2", rect: cell(1, 3), role: .tile),
        KeySpec(label: "3", rect: cell(2, 3), role: .tile), KeySpec(label: "=", rect: cell(3, 3, 1, 2), role: .accent),
        KeySpec(label: "0", rect: cell(0, 4, 2), role: .tile), KeySpec(label: ".", rect: cell(2, 4), role: .tile),
    ]
}

/// The Numpad in the stock arrangement: tall + and Enter, wide 0, Del beside it.
func numpadKeys(_ s: SID) -> [KeySpec] {
    let top: CGFloat = 96, bottom: CGFloat = 470, m: CGFloat = 12, g: CGFloat = 8
    let cw = (CGFloat(W) - 2 * m - 3 * g) / 4, ch = (bottom - top - 4 * g) / 5
    func cell(_ col: Int, _ row: Int, _ cs: Int = 1, _ rs: Int = 1) -> CGRect {
        CGRect(x: (m + CGFloat(col) * (cw + g)).rounded(), y: (top + CGFloat(row) * (ch + g)).rounded(),
               width: (CGFloat(cs) * cw + CGFloat(cs - 1) * g).rounded(), height: (CGFloat(rs) * ch + CGFloat(rs - 1) * g).rounded())
    }
    return [
        KeySpec(label: "Num", rect: cell(0, 0), role: .op), KeySpec(label: "÷", rect: cell(1, 0), role: .op),
        KeySpec(label: "×", rect: cell(2, 0), role: .op), KeySpec(label: "−", rect: cell(3, 0), role: .op),
        KeySpec(label: "7", rect: cell(0, 1), role: .tile), KeySpec(label: "8", rect: cell(1, 1), role: .tile),
        KeySpec(label: "9", rect: cell(2, 1), role: .tile), KeySpec(label: "+", rect: cell(3, 1, 1, 2), role: .op),
        KeySpec(label: "4", rect: cell(0, 2), role: .tile), KeySpec(label: "5", rect: cell(1, 2), role: .tile),
        KeySpec(label: "6", rect: cell(2, 2), role: .tile),
        KeySpec(label: "1", rect: cell(0, 3), role: .tile), KeySpec(label: "2", rect: cell(1, 3), role: .tile),
        KeySpec(label: "3", rect: cell(2, 3), role: .tile), KeySpec(label: "Enter", rect: cell(3, 3, 1, 2), role: .accent),
        KeySpec(label: "0", rect: cell(0, 4, 2), role: .tile), KeySpec(label: "Del", rect: cell(2, 4), role: .op),
    ]
}

/// Draws key labels in the style's key face. `pressed` draws every key in its pressed look.
func drawKeyLabels(_ s: SID, _ c: CGContext, _ keys: [KeySpec], pressed: Bool, tags: [String: Int]) {
    for k in keys {
        let r = k.rect, role = k.role, label = k.label
        let col = s.ink(pressed ? .pressed : role)
        let wide = r.width > r.height * 2
        let ctr = wide && label == "0" ? CGPoint(x: r.minX + min(r.width, 68) / 2, y: r.midY) : CGPoint(x: r.midX, y: r.midY)
        if label == "⌫" { ico(s, c, .backspace, center: ctr, size: 24, col, lw: 1.8) }
        else if s == .midnight, label.allSatisfy({ dotTable[$0] != nil }) {
            let pitch: CGFloat = label.count > 1 ? 2.6 : 4.2
            dotString(c, label, left: ctr.x - dotWidth(label, pitch: pitch) / 2, midY: ctr.y, pitch: pitch, on: col, off: role == .accent ? hex(0x0A1A52, 0.08) : hex(0xFFFFFF, 0.07))
        } else if s == .cyber {
            let f = mono(label.count > 1 ? 14 : 28, .bold)
            if role == .tile {
                text(c, label, f, hex(0xFF2A6D, 0.75), center: CGPoint(x: ctr.x - 1.5, y: ctr.y + 2))
                text(c, label, f, hex(0x05D9E8, 0.75), center: CGPoint(x: ctr.x + 1.5, y: ctr.y + 2))
            }
            text(c, s.caps(label), f, col, center: CGPoint(x: ctr.x, y: ctr.y + 2))
            tag(s, c, r, tags[label] ?? Int(label) ?? 0, col)
        } else {
            let multi = label.count > 1
            let size: CGFloat = multi ? 16 : (label == "C" ? (s.glass ? 22 : 21) : (s.glass ? 28 : 26))
            let f: NSFont = s.glass ? sf(size, role == .tile ? .light : .regular) : sf(size, s == .ceramic || multi ? .medium : .regular)
            lbl(s, c, label, f, col, center: ctr)
        }
    }
}

func calculator(_ s: SID) -> ([Panel], (CGContext) -> Void) {
    let display = calculatorDisplay(s), keys = calculatorKeys(s)
    var panels = headerPanels(s, back: true)
    panels.append(Panel(r: display, rad: s.glass ? 29 : 18, role: .screen))
    panels += keys.map { Panel(r: $0.rect, rad: s.glass ? 27 : tileRad(s), role: calcPressed ? .pressed : $0.role) }
    let content: (CGContext) -> Void = { c in
        header(s, c, title: "Calculator", sub: "Standard", code: "//SYS.22  CALC", back: true)
        // The result is drawn by the screen in its built-in font; shown here in a plain face.
        if !exportBG {
            lbl(s, c, s.caps("Result"), s.font(9.5, .medium), s.sub(.screen), left: CGPoint(x: display.minX + 16, y: display.minY + 17))
            lblRight(s, c, "1,284.5", sf(30), s.ink(.screen), right: display.maxX - 18, y: display.midY + 4)
        }
        drawKeyLabels(s, c, keys, pressed: calcPressed, tags: ["C": 0x10, "÷": 0x11, "×": 0x12, "⌫": 0x13, "+": 0x14, "−": 0x15, "=": 0x16, ".": 0x17])
    }
    return (panels, content)
}

func numpad(_ s: SID) -> ([Panel], (CGContext) -> Void) {
    let keys = numpadKeys(s)
    var panels = headerPanels(s, back: true)
    panels += keys.map { Panel(r: $0.rect, rad: s.glass ? 24 : tileRad(s), role: calcPressed ? .pressed : $0.role) }
    let content: (CGContext) -> Void = { c in
        header(s, c, title: "Numpad", sub: "Number keys", code: "//SYS.21  NUMPAD", back: true)
        drawKeyLabels(s, c, keys, pressed: calcPressed, tags: ["Num": 0x30, "÷": 0x31, "×": 0x32, "−": 0x33, "+": 0x37, "Enter": 0x3E, "Del": 0x40])
    }
    return (panels, content)
}
