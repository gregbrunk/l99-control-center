// Step-2 hardware test art: page backgrounds without the live parts, pressed keys, glyph sprites,
// weather icons, bar sprites, and a manifest of where the screen's live widgets go.
import AppKit

var exportBG = false
var calcPressed = false

// MARK: Real-time Data, export layout (Glass Night)

struct DataSpec {
    static let hero = CGRect(x: 12, y: 94, width: 296, height: 112)
    static let cards = [CGRect(x: 12, y: 216, width: 144, height: 112), CGRect(x: 164, y: 216, width: 144, height: 112),
                        CGRect(x: 12, y: 338, width: 144, height: 128), CGRect(x: 164, y: 338, width: 144, height: 128)]
    // Glyph faces (light SF, as the mockup's bigNum for glass).
    static let timeFont = sf(40, .light), midFont = sf(34, .light), cpuFont = sf(40, .light)
    // Live widget anchors: top-left for the clock/date/weekday/icon/bars; right edge + top for numbers.
    static let time = (28, 104), weekday = (30, 160), date = (30, 182), weather = (244, 112)
    static let temp = (64, 258), hum = (226, 258), cpu = (84, 376), gpu = (236, 376), cpuTemp = (88, 440)
    static let humBar = (178, 302), cpuBar = (26, 426), barW = 116, barH = 6
}

func glyphH(_ f: NSFont) -> Int { Int(ceil(f.capHeight)) + 6 }
func advance(_ f: NSFont) -> Int { Int(ceil(width("0", f))) }

func dataExport(_ s: SID) -> ([Panel], (CGContext) -> Void) {
    var panels = headerPanels(s, back: true)
    panels.append(Panel(r: DataSpec.hero, rad: 28, role: .hero))
    panels += DataSpec.cards.map { Panel(r: $0, rad: 26, role: .tile) }
    let content: (CGContext) -> Void = { c in
        header(s, c, title: "Real-time Data", sub: "Live from your Mac", code: "", back: true)
        let cards = DataSpec.cards
        let info: [(String, Icon?, String)] = [("Air temp", .thermo, "Outside"), ("Humidity", .drop, ""), ("CPU", .chip, ""), ("GPU", .gpu, "Mac load")]
        for (r, d) in zip(cards, info) {
            lbl(s, c, d.0, s.font(12, .semibold), s.sub(.tile), left: CGPoint(x: r.minX + 14, y: r.minY + 20))
            if let i = d.1 { ico(s, c, i, center: CGPoint(x: r.maxX - 24, y: r.minY + 22), size: 20, s.ink(.op), lw: 1.7) }
            if !d.2.isEmpty { lbl(s, c, d.2, s.font(9.5), s.sub(.tile), left: CGPoint(x: r.minX + 14, y: r.maxY - (r.height > 120 ? 17 : 18))) }
        }
        // Units sit just right of each right-aligned number.
        func unit(_ u: String, _ a: (Int, Int), _ f: NSFont, size: CGFloat) {
            lbl(s, c, u, sf(size, .regular), s.sub(.tile), left: CGPoint(x: CGFloat(a.0) + 3, y: CGFloat(a.1) + f.capHeight / 2 + 3))
        }
        unit("°C", DataSpec.temp, DataSpec.midFont, size: 16); unit("%", DataSpec.hum, DataSpec.midFont, size: 16)
        unit("%", DataSpec.cpu, DataSpec.cpuFont, size: 18); unit("%", DataSpec.gpu, DataSpec.cpuFont, size: 18)
        // CPU temperature probe (variable 0x0107 is our guess), in the stock small digits (11×17).
        lbl(s, c, "Temp", s.font(9.5), s.sub(.tile), left: CGPoint(x: 26, y: 449))
        lbl(s, c, "°C", s.font(9.5), s.sub(.tile), left: CGPoint(x: CGFloat(DataSpec.cpuTemp.0) + 3, y: 449))
        // Bar tracks are drawn by the screen (they are part of the bar widget), so not here.
    }
    return (panels, content)
}

// MARK: Sprites

func sprite(_ w: Int, _ h: Int, _ body: (CGContext) -> Void) -> CGContext { let c = newContext(w, h); body(c); return c }

func glyphSprites(_ s: SID, _ f: NSFont, colon: Bool) -> [(String, CGContext)] {
    let h = glyphH(f), w = advance(f)
    var out = (0...9).map { d in ("\(d)", sprite(w, h) { c in lbl(s, c, "\(d)", f, s.ink(.tile), center: CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) / 2)) }) }
    if colon {
        let cw = Int(ceil(width(":", f))) + 2
        let col = sprite(cw, h) { c in lbl(s, c, ":", f, s.ink(.tile), center: CGPoint(x: CGFloat(cw) / 2, y: CGFloat(h) / 2 - 1)) }
        out += (0..<4).map { ("colon\($0)", col) }
    }
    return out
}

/// Weather conditions as our Mac app will send them: 0 clear, 1 partly cloudy, 2 cloudy, 3 rain, 4 storm, 5 snow.
func weatherSprite(_ s: SID, _ k: Int) -> CGContext {
    let n = 56
    return sprite(n, n) { c in
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: hex(0, 0.45).cgColor)
        let ink = hex(0xFFFFFF), sun = hex(0xFFC86B)
        c.setLineWidth(2.4); c.setLineCap(.round); c.setLineJoin(.round)
        func cloud(_ r: CGRect, _ col: NSColor) {
            let p = CGMutablePath(), b = r.maxY
            p.move(to: CGPoint(x: r.minX + r.height * 0.45, y: b))
            p.addLine(to: CGPoint(x: r.maxX - r.height * 0.4, y: b))
            p.addArc(center: CGPoint(x: r.maxX - r.height * 0.4, y: b - r.height * 0.4), radius: r.height * 0.4, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
            p.addArc(center: CGPoint(x: r.midX, y: r.minY + r.height * 0.5), radius: r.height * 0.5, startAngle: -.pi * 0.08, endAngle: -.pi * 0.92, clockwise: true)
            p.addArc(center: CGPoint(x: r.minX + r.height * 0.45, y: b - r.height * 0.45), radius: r.height * 0.45, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
            p.closeSubpath()
            c.addPath(p); c.setFillColor(hex(0xFFFFFF, 0.12).cgColor); c.fillPath()
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
        let cl = CGRect(x: 8, y: 18, width: 40, height: 22)
        switch k {
        case 0: sunAt(CGPoint(x: 28, y: 28), 9)
        case 1: sunAt(CGPoint(x: 20, y: 20), 7); cloud(CGRect(x: 14, y: 24, width: 36, height: 20), ink)
        case 2: cloud(CGRect(x: 4, y: 14, width: 32, height: 18), hex(0xFFFFFF, 0.55)); cloud(cl, ink)
        case 3:
            cloud(CGRect(x: 8, y: 10, width: 40, height: 22), ink)
            c.setStrokeColor(hex(0x8EC9FF).cgColor)
            for x in [17, 27, 37] { c.move(to: CGPoint(x: x, y: 38)); c.addLine(to: CGPoint(x: x - 3, y: 48)) }; c.strokePath()
        case 4:
            cloud(CGRect(x: 8, y: 8, width: 40, height: 22), ink)
            let p = CGMutablePath(); p.move(to: CGPoint(x: 30, y: 31)); p.addLine(to: CGPoint(x: 23, y: 42)); p.addLine(to: CGPoint(x: 29, y: 42)); p.addLine(to: CGPoint(x: 25, y: 52))
            c.addPath(p); c.setStrokeColor(hex(0xFFD24D).cgColor); c.strokePath()
        default:
            cloud(CGRect(x: 8, y: 8, width: 40, height: 22), ink)
            c.setFillColor(ink.cgColor)
            for (x, y) in [(17, 40), (28, 44), (39, 40), (22, 50), (34, 50)] { c.fillEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)) }
        }
        c.restoreGState()
    }
}

func barSprites() -> (track: CGContext, fill: CGContext) {
    let w = DataSpec.barW, h = DataSpec.barH, r = CGRect(x: 0, y: 0, width: w, height: h)
    let track = sprite(w, h) { c in fill(c, rr(r, CGFloat(h) / 2), hex(0xFFFFFF, 0.16)) }
    let fillS = sprite(w, h) { c in linear(c, rr(r, CGFloat(h) / 2), [hex(0xB79BFF), hex(0xFF7EB6)], [0, 1], from: .zero, to: CGPoint(x: CGFloat(w), y: 0)) }
    return (track, fillS)
}

// MARK: Export

func rectJSON(_ r: CGRect) -> [Int] { [Int(r.minX.rounded()), Int(r.minY.rounded()), Int(r.width.rounded()), Int(r.height.rounded())] }

func exportStep2(_ dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    exportBG = true
    func save(_ c: CGContext, _ name: String) { savePNG(c, "\(dir)/\(name).png") }
    // Calculator, Cyberpunk: up (background) and pressed renders; keys are cropped from these.
    calcPressed = false; save(quantised565(render(.cyber, .calculator)), "calc-bg")
    calcPressed = true; save(quantised565(render(.cyber, .calculator)), "calc-down"); calcPressed = false
    // Home, Ember, Photos and Touchpad hidden.
    save(quantised565(render(.ember, .homeHidden)), "home-bg")
    // Real-time Data, Glass Night.
    save(quantised565(render(.glassNight, .data)), "data-bg")
    for (n, g) in glyphSprites(.glassNight, DataSpec.timeFont, colon: true) { save(g, "time-\(n)") }
    for (n, g) in glyphSprites(.glassNight, DataSpec.midFont, colon: false) { save(g, "mid-\(n)") }
    for (n, g) in glyphSprites(.glassNight, DataSpec.cpuFont, colon: false) { save(g, "cpu-\(n)") }
    for k in 0..<6 { save(weatherSprite(.glassNight, k), "weather-\(k)") }
    let bars = barSprites(); save(bars.track, "bar-track"); save(bars.fill, "bar-fill")
    // Home touch areas (from the same layout the background used).
    let heroes = [CGRect(x: 12, y: 94, width: 142, height: 96), CGRect(x: 166, y: 94, width: 142, height: 96)]
    let tiles = tileGrid(6)
    let zw: CGFloat = 296 / 4
    let zones = (0..<4).map { CGRect(x: 12 + zw * CGFloat($0), y: 380, width: zw, height: 78) }
    let p = { (a: (Int, Int)) in [a.0, a.1] }
    let manifest: [String: Any] = [
        "calcKeys": Dictionary(uniqueKeysWithValues: calculatorKeys(.cyber).map { ($0.label, rectJSON($0.rect)) }),
        "home": ["play": rectJSON(heroes[0]), "data": rectJSON(heroes[1]),
                 "tiles": ["settings", "screen", "colour", "gifs", "numpad", "calculator"].enumerated().reduce(into: [String: [Int]]()) { $0[$1.1] = rectJSON(tiles[$1.0]) },
                 "media": ["volDown": rectJSON(zones[0]), "mute": rectJSON(zones[1]), "volUp": rectJSON(zones[2]), "alarm": rectJSON(zones[3])]],
        "data": ["time": p(DataSpec.time), "weekday": p(DataSpec.weekday), "date": p(DataSpec.date), "weather": p(DataSpec.weather),
                 "temp": p(DataSpec.temp), "hum": p(DataSpec.hum), "cpu": p(DataSpec.cpu), "gpu": p(DataSpec.gpu), "cpuTemp": p(DataSpec.cpuTemp),
                 "humBar": p(DataSpec.humBar), "cpuBar": p(DataSpec.cpuBar)],
    ]
    let data = try! JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: URL(fileURLWithPath: "\(dir)/manifest.json"))
    exportBG = false
}
