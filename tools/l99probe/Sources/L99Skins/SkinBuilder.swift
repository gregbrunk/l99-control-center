import AppKit
import L99Core

/// The apps on Home, in grid order.
public enum HomeApp: String, CaseIterable, Sendable {
    case settings, screen, colour, effects, photos, numpad, calculator, touchpad
    public var displayName: String { rawValue == "colour" ? "Colour" : rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// The touch record that opens it: action code, and the page it goes to (nil for Effects, which is an action).
    var touch: (code: Int, goto: Int?) {
        switch self {
        case .settings: (32, 4)
        case .screen: (32, 16)
        case .colour: (32, 17)
        case .effects: (96, nil)
        case .photos: (32, 20)
        case .numpad: (32, 21)
        case .calculator: (32, 22)
        case .touchpad: (32, 23)
        }
    }
}

/// What to install: a style per section (sections left out stay stock) and the Home apps to hide.
public struct SkinPlan: Sendable, Equatable {
    public var styles: [SkinSection: SkinStyle]
    public var hiddenApps: Set<HomeApp>
    public init(styles: [SkinSection: SkinStyle] = [:], hiddenApps: Set<HomeApp> = []) { self.styles = styles; self.hiddenApps = hiddenApps }

    var pages: [SkinSection] { [.home, .play, .data, .numpad, .calculator].filter { styles[$0] != nil } }
    /// One top bar is shared by every restyled page. Without a choice it follows Home (or the first page).
    public var topBarStyle: SkinStyle? { styles[.topBar] ?? styles[.home] ?? pages.first.flatMap { styles[$0] } }
}

public struct SkinBuildResult {
    public let file: InterfaceFile
    /// Plain-language notes on what the build did.
    public let notes: [String]
    public let slotsUsed: Int, bytesAdded: Int
}

/// Turns a plan into an installable interface file, starting from the stock file every time.
public enum SkinBuilder {
    // Icon slots for new art. Picked from the slots no page refers to; 368 is avoided because page 0's
    // animation record mentions it. The others were checked by hand: where a record mentions them it's
    // as a screen coordinate (a y value in a touch rectangle or text box), not an icon.
    static let blank = 497                      // a transparent 1×1, shared (497–498 are also the hidden Num indicator)
    static let homePicture = 371
    static let timerPicture = 369
    static let weather = 372...377
    static let dateRun = 378...398
    static let topBar = (digits: 481, colons: 491, connection: 541, num: 497, battery: 450, caps: 458, lock: 460, os: 462, percent: 466)
    static let checkedByHand: Set<Int> = [378, 379, 380, 381, 383, 384, 385, 389, 399, 438, 464, 479, 480, 496, 544]

    static let page = (home: 1, play: 18, data: 19, numpad: 21, calculator: 22)

    public static func build(_ plan: SkinPlan, stockBytes: [UInt8]) throws -> SkinBuildResult {
        var f = try InterfaceFile(stockBytes: stockBytes)
        let projectStart = f.projectEnd
        var notes: [String] = [], used = Set<Int>()
        let safe = Set(try f.freeSlots()).union(checkedByHand)
        func claim(_ ids: [Int], _ what: String) throws {
            for id in ids {
                guard safe.contains(id) else { throw InterfaceFile.Failure.refused("Icon slot \(id) (\(what)) isn't free. Stopped.") }
                guard !used.contains(id) else { throw InterfaceFile.Failure.refused("Icon slot \(id) (\(what)) is claimed twice. Stopped.") }
                used.insert(id)
            }
        }
        /// Slots restyled in place must belong to one page only.
        let refs = try f.decodedReferences()
        func owned(_ ids: ClosedRange<Int>, by page: Int) throws {
            for id in ids where refs[id, default: []] != [page] {
                throw InterfaceFile.Failure.refused("Icon \(id) is used by pages \(refs[id, default: []].sorted()), not only page \(page). Stopped.")
            }
            used.formUnion(ids)
        }
        guard !plan.pages.isEmpty else { throw InterfaceFile.Failure.refused("The plan restyles no pages.") }

        try claim([blank, blank + 1], "blank")
        try f.placeIcon(blank, width: 1, height: 1, pixels: [0]); try f.placeIcon(blank + 1, width: 1, height: 1, pixels: [0])

        let tb = plan.topBarStyle!
        try placeTopBar(&f, TopBarKit(tb.sid), claim: claim)
        if plan.styles[.topBar] == nil { notes.append("Top bar: \(tb.displayName), following \(plan.styles[.home] != nil ? "Home" : "the first restyled page").") }

        for section in plan.pages {
            let s = plan.styles[section]!.sid
            exportBG = true; defer { exportBG = false; calcPressed = false }
            switch section {
            case .calculator: try calculatorPage(&f, s, owned: owned)
            case .numpad: try numpadPage(&f, s, owned: owned)
            case .data: try dataPage(&f, s, owned: owned, claim: claim)
            case .home:
                try homePage(&f, s, hidden: plan.hiddenApps, claim: claim)
                try timerPages(&f, s, hidden: plan.hiddenApps, topBar: TopBarKit(tb.sid), owned: owned, claim: claim)
            case .play: try playPage(&f, s, owned: owned)
            case .topBar: break
            }
            exportBG = false
            try applyTopBar(&f, TopBarKit(tb.sid), page: pageNumber(section))
            notes.append("\(section.displayName): \(plan.styles[section]!.displayName).")
        }
        if !plan.hiddenApps.isEmpty, plan.styles[.home] != nil {
            notes.append("Hidden on Home: " + HomeApp.allCases.filter { plan.hiddenApps.contains($0) }.map(\.displayName).joined(separator: ", ") + ".")
        }
        try f.validate()
        return SkinBuildResult(file: f, notes: notes, slotsUsed: used.count, bytesAdded: f.projectEnd - projectStart)
    }

    static func pageNumber(_ s: SkinSection) -> Int {
        switch s {
        case .home, .topBar: page.home
        case .play: page.play
        case .data: page.data
        case .numpad: page.numpad
        case .calculator: page.calculator
        }
    }

    // MARK: Top bar

    static func placeTopBar(_ f: inout InterfaceFile, _ k: TopBarKit, claim: ([Int], String) throws -> Void) throws {
        let t = topBar
        try claim(Array(t.digits..<(t.digits + 10)) + Array(t.colons..<(t.colons + 4)) + Array(t.connection..<(t.connection + 5))
                  + Array(t.battery..<(t.battery + 7)) + [t.caps, t.caps + 1, t.lock, t.lock + 1, t.os, t.os + 1, t.percent], "top bar")
        func put(_ id: Int, _ c: CGContext) throws { try f.placeIcon(id, width: c.width, height: c.height, pixels: argb4444(c)) }
        // Stock state order: Caps off/on, Lock locked/unlocked, OS WIN/MAC. Num never turns on from a Mac,
        // so its indicator shows the blank pair (497–498).
        try put(t.caps, k.chipSprite(k.capsLabel, on: false, width: k.capsW)); try put(t.caps + 1, k.chipSprite(k.capsLabel, on: true, width: k.capsW))
        try put(t.lock, k.lockSprite(closed: true)); try put(t.lock + 1, k.lockSprite(closed: false))
        try put(t.os, k.chipSprite("WIN", on: false, width: k.osW)); try put(t.os + 1, k.chipSprite("MAC", on: false, width: k.osW))
        for m in 0..<5 { try put(t.connection + m, k.connection(m)) }
        for b in 0..<7 { try put(t.battery + b, k.battery(b)) }
        for d in 0..<10 { try put(t.digits + d, k.digit(d)) }
        for i in 0..<4 { try put(t.colons + i, k.colon()) }
        try put(t.percent, k.percent())
    }

    static func applyTopBar(_ f: inout InterfaceFile, _ k: TopBarKit, page: Int) throws {
        let t = topBar, K = TopBarKit.self
        try f.setClock(page: page, format: 5, x: K.clock.x, y: K.clock.y, first: t.digits)
        try f.setIndicator(page: page, using: 9, x: K.conn.x, y: K.conn.y, first: t.connection)
        try f.setIndicator(page: page, using: 1, x: 0, y: 0, first: t.num)
        var x = K.chipsX
        try f.setIndicator(page: page, using: 3, x: x, y: K.chipY, first: t.caps); x += k.capsW + 4
        try f.setIndicator(page: page, using: 5, x: x, y: K.chipY, first: t.lock); x += K.lockW + 4
        try f.setIndicator(page: page, using: 7, x: x, y: K.chipY, first: t.os)
        try f.setDigits(page: page, variable: 6, x: K.pctRight, y: K.pctY, first: t.digits)
        try f.setIndicator(page: page, using: 21, x: K.pctSign.x, y: K.pctSign.y, first: t.percent)
        try f.setIndicator(page: page, using: 14, x: K.battery.x, y: K.battery.y, first: t.battery)
    }

    // MARK: Pages

    /// Keys: the up image is a crop of the page background, the down image a crop of the pressed render.
    static func placeKeys(_ f: inout InterfaceFile, page: Int, _ keys: [KeySpec], codes: [String: Int], bg: CGContext, down: CGContext) throws {
        let buttons = try f.touchButtons(page: page).filter { $0.up != 0xFFFF }
        guard Set(codes.values) == Set(buttons.map(\.code)), keys.count == codes.count else {
            throw InterfaceFile.Failure.refused("Page \(page)'s keys aren't the \(codes.count) expected. Stopped.")
        }
        for k in keys {
            let code = codes[k.label]!, b = buttons.first { $0.code == code }!
            let (x, y, w, h) = (Int(k.rect.minX), Int(k.rect.minY), Int(k.rect.width), Int(k.rect.height))
            try f.moveButton(page: page, code: code, x: x, y: y, width: w, height: h)
            try f.placeIcon(b.up, width: w, height: h, pixels: rgb565(bg, x: x, y: y, w: w, h: h), format: InterfaceFile.formatRGB565)
            try f.placeIcon(b.down, width: w, height: h, pixels: rgb565(down, x: x, y: y, w: w, h: h), format: InterfaceFile.formatRGB565)
        }
    }

    static func calculatorPage(_ f: inout InterfaceFile, _ s: SID, owned: (ClosedRange<Int>, Int) throws -> Void) throws {
        let p = page.calculator
        try owned(400...435, p)
        calcPressed = false; let bg = quantised565(render(s, .calculator))
        calcPressed = true; let down = quantised565(render(s, .calculator)); calcPressed = false
        try f.setBackground(page: p, pixels: rgb565(bg))
        var codes: [String: Int] = ["C": 0x7F7F, "÷": 0x2F2F, "×": 0x2A2A, "⌫": 0x0808, "+": 0x2B2B, "−": 0x2D2D, "=": 0x3D3D, ".": 0x2E2E]
        for d in 0...9 { codes["\(d)"] = 0x3030 + d * 0x0101 }
        try placeKeys(&f, page: p, calculatorKeys(s), codes: codes, bg: bg, down: down)
        // The title and back arrow are in the background.
        try f.setIndicator(page: p, using: 353, x: 0, y: 0, first: blank)
        try f.setIndicator(page: p, using: 119, x: 0, y: 0, first: blank)
        // The result line is drawn by the screen in its own 32-px font. Keep it inside the display with
        // some padding, centred vertically, in the style's display colour.
        let d = calculatorDisplay(s)
        try f.setTextBox(page: p, variable: 0x0218, x1: Int(d.minX) + 16, y1: Int(d.midY) - 16, x2: Int(d.maxX) - 18, y2: Int(d.midY) + 16)
        try f.setTextColor(page: p, variable: 0x0218, color: color565(s.ink(.screen)))
    }

    static func numpadPage(_ f: inout InterfaceFile, _ s: SID, owned: (ClosedRange<Int>, Int) throws -> Void) throws {
        let p = page.numpad
        try owned(319...352, p)
        calcPressed = false; let bg = quantised565(render(s, .numpad))
        calcPressed = true; let down = quantised565(render(s, .numpad)); calcPressed = false
        try f.setBackground(page: p, pixels: rgb565(bg))
        let codes: [String: Int] = ["Num": 48, "÷": 49, "×": 50, "−": 51, "7": 52, "8": 53, "9": 54, "+": 55, "4": 56, "5": 57, "6": 58,
                                    "1": 59, "2": 60, "3": 61, "Enter": 62, "0": 63, "Del": 64]
        try placeKeys(&f, page: p, numpadKeys(s), codes: codes, bg: bg, down: down)
        try f.setIndicator(page: p, using: 318, x: 0, y: 0, first: blank)
        try f.setIndicator(page: p, using: 119, x: 0, y: 0, first: blank)
    }

    static func dataPage(_ f: inout InterfaceFile, _ s: SID, owned: (ClosedRange<Int>, Int) throws -> Void, claim: ([Int], String) throws -> Void) throws {
        let p = page.data, k = DataKit(s), D = DataKit.self
        try owned(213...226, p); try owned(260...269, p); try owned(280...289, p); try owned(314...316, p)
        try claim(Array(weather), "weather"); try claim(Array(dateRun), "date and weekday")
        try f.setBackground(page: p, pixels: rgb565(quantised565(render(s, .data))))
        func put(_ first: Int, _ sprites: [CGContext]) throws {
            for (i, c) in sprites.enumerated() { try f.placeIcon(first + i, width: c.width, height: c.height, pixels: argb4444(c)) }
        }
        try put(213, k.timeDigits()); try put(260, k.midDigits()); try put(280, k.cpuDigits())
        try put(dateRun.lowerBound, k.dateRun()); try put(weather.lowerBound, (0..<6).map { k.weather($0) })
        try f.setClock(page: p, format: 4, x: D.time.0, y: D.time.1, first: 213)
        try f.setClock(page: p, format: 7, x: D.weekday.0, y: D.weekday.1, first: dateRun.lowerBound)
        try f.setClock(page: p, format: 1, x: D.date.0, y: D.date.1, first: dateRun.lowerBound)
        try f.setDigits(page: p, variable: 0x0103, x: k.temp.0, y: k.temp.1, first: 260)
        try f.setDigits(page: p, variable: 0x0104, x: k.hum.0, y: k.hum.1, first: 260)
        try f.setDigits(page: p, variable: 0x0106, occurrence: 0, x: k.cpu.0, y: k.cpu.1, first: 280)
        // The second CPU number becomes the day's high (0x0102), beside the weather icon.
        try f.setDigits(page: p, variable: 0x0106, occurrence: 1, newVariable: 0x0102, x: D.high.0, y: D.high.1, first: dateRun.lowerBound)
        try f.setDigits(page: p, variable: 0x0108, x: k.gpu.0, y: k.gpu.1, first: 280)
        try f.setStateIcon(page: p, using: 254, variable: 0x0101, x: D.weather.0, y: D.weather.1, first: weather.lowerBound, count: weather.count)
        // Units and labels are in the background.
        for id in [310, 310, 312, 313, 119] { try f.setIndicator(page: p, using: id, occurrence: id == 310 ? 0 : nil, x: 0, y: 0, first: blank) }
        let track = k.barTrack(), fill = k.barFill()
        try f.placeIcon(314, width: track.width, height: track.height, pixels: argb4444(track))
        for id in [315, 316] { try f.placeIcon(id, width: fill.width, height: fill.height, pixels: argb4444(fill)) }
        try f.setProgressBar(page: p, variable: 0x0104, x: D.humBar.0, y: D.humBar.1, trackX: D.humBar.0, trackY: D.humBar.1, max: 100)
        try f.setProgressBar(page: p, variable: 0x0102, newVariable: 0x0106, x: D.cpuBar.0, y: D.cpuBar.1, trackX: D.cpuBar.0, trackY: D.cpuBar.1, max: 100)
    }

    static func homePage(_ f: inout InterfaceFile, _ s: SID, hidden: Set<HomeApp>, claim: ([Int], String) throws -> Void) throws {
        let p = page.home
        try claim([homePicture], "Home picture")
        let shown = HomeApp.allCases.filter { !hidden.contains($0) }
        let (panels, content) = home(s, hidden: Set(hidden.map(\.displayName)))
        let c = newContext(); background(s, c); drawPanels(s, c, panels); content(c); finish(s, c)
        let px = rgb565(quantised565(c))
        // Home ignores the background table (it shows the wallpaper picked in Screen settings), so the
        // picture is also a full-screen image drawn first. The table copy lets top-bar widgets repaint their patches.
        try f.setBackground(page: p, pixels: px)
        try f.placeIcon(homePicture, width: 320, height: 480, pixels: px, format: InterfaceFile.formatRGB565)
        func move(_ code: Int, goto: Int? = nil, _ r: CGRect) throws {
            try f.moveButton(page: p, code: code, goto: goto, x: Int(r.minX.rounded()), y: Int(r.minY.rounded()), width: Int(r.width.rounded()), height: Int(r.height.rounded()))
        }
        try move(32, goto: 18, HomeSpec.heroes[0]); try move(32, goto: 19, HomeSpec.heroes[1])
        for (app, r) in zip(shown, tileGrid(shown.count)) { try move(app.touch.code, goto: app.touch.goto, r) }
        for app in hidden { try move(app.touch.code, goto: app.touch.goto, CGRect(x: 0, y: 479, width: 1, height: 1)) }
        let z = HomeSpec.zones
        try move(0x22, z[0]); try move(0x23, z[1]); try move(0x24, z[2]); try move(0xF120, z[3])
        try f.setIndicator(page: p, using: 0, x: 0, y: 0, first: homePicture)
        try f.moveIndicatorToFront(page: p, using: homePicture)
        try f.setIndicator(page: p, using: 560, x: 0, y: 0, first: blank)
    }

    /// The timer pages (2 work, 3 rest) replace Home while a timer runs. They only hold the timer pill,
    /// its countdown, the top bar and Home's app-grid image, and don't clear the screen. So the grid's record
    /// shows Home's picture instead (with an empty media bar), moved to the front so it's drawn first.
    /// The pill images (561, 562) become the bar in the page's style; the countdown is drawn by the screen in white.
    static func timerPages(_ f: inout InterfaceFile, _ s: SID, hidden: Set<HomeApp>, topBar k: TopBarKit,
                           owned: (ClosedRange<Int>, Int) throws -> Void, claim: ([Int], String) throws -> Void) throws {
        try claim([timerPicture], "timer picture")
        try owned(561...561, 2); try owned(562...562, 3)
        let (panels, content) = home(s, hidden: Set(hidden.map(\.displayName)), mediaBar: false)
        let bar = HomeSpec.bar
        func picture(_ label: String?) -> CGContext {
            let c = newContext(); background(s, c); drawPanels(s, c, panels); content(c)
            if let label {
                var ink = s.ink(.bar)
                if s.light { fill(c, rr(bar.insetBy(dx: 6, dy: 6), s.glass ? 33 : 18), hex(0x1F2025)); ink = hex(0xFFFFFF) }
                ico(s, c, .alarm, center: CGPoint(x: bar.minX + 34, y: bar.midY), size: 24, s.ink(.op), lw: 1.8)
                lbl(s, c, s.caps(label), s.font(13, .semibold), ink, left: CGPoint(x: bar.minX + 56, y: bar.midY))
            }
            finish(s, c)
            return quantised565(c)
        }
        let base = picture(nil)
        try f.placeIcon(timerPicture, width: 320, height: 480, pixels: rgb565(base), format: InterfaceFile.formatRGB565)
        let (bx, by, bw, bh) = (Int(bar.minX), Int(bar.minY), Int(bar.width), Int(bar.height))
        for (page, pill, label, code) in [(2, 561, "Focus", 0xF121), (3, 562, "Break", 32)] {
            try f.setBackground(page: page, pixels: rgb565(base))
            try f.placeIcon(pill, width: bw, height: bh, pixels: rgb565(picture(label), x: bx, y: by, w: bw, h: bh), format: InterfaceFile.formatRGB565)
            try f.setIndicator(page: page, using: pill, x: bx, y: by, first: pill)
            try f.moveButton(page: page, code: code, goto: 1, x: bx, y: by, width: bw, height: bh)
            try applyTopBar(&f, k, page: page)
            try f.setIndicator(page: page, using: 0, x: 0, y: 0, first: timerPicture)
            try f.moveIndicatorToFront(page: page, using: timerPicture)
        }
    }

    static func playPage(_ f: inout InterfaceFile, _ s: SID, owned: (ClosedRange<Int>, Int) throws -> Void) throws {
        let p = page.play, P = PlaySpec.self
        try owned(206...211, p)
        let bg = quantised565(render(s, .play))
        try f.setBackground(page: p, pixels: rgb565(bg))
        func ir(_ r: CGRect) -> (Int, Int, Int, Int) { (Int(r.minX), Int(r.minY), Int(r.width), Int(r.height)) }
        // Previous/next: touch buttons whose up image is drawn; give them crops of the background.
        for (code, id, r) in [(32, 208, P.prev), (33, 209, P.next)] {
            let (x, y, w, h) = ir(r)
            try f.moveButton(page: p, code: code, goto: 0xFFFF, x: x, y: y, width: w, height: h)
            try f.placeIcon(id, width: w, height: h, pixels: rgb565(bg, x: x, y: y, w: w, h: h), format: InterfaceFile.formatRGB565)
        }
        // Play/pause: a toggle area plus a two-state icon; both states show the same play/pause art.
        let (x, y, w, h) = ir(P.pp)
        try f.moveToggle(page: p, x: x, y: y, width: w, height: h)
        for id in [210, 211] { try f.placeIcon(id, width: w, height: h, pixels: rgb565(bg, x: x, y: y, w: w, h: h), format: InterfaceFile.formatRGB565) }
        try f.setIndicator(page: p, using: 210, x: x, y: y, first: 210)
        // Volume: three touch zones over the capsule.
        let v = P.vol
        try f.moveButton(page: p, code: 34, x: Int(v.minX), y: Int(v.minY), width: 88, height: Int(v.height))
        try f.moveButton(page: p, code: 35, x: Int(v.minX) + 88, y: Int(v.minY), width: Int(v.width) - 176, height: Int(v.height))
        try f.moveButton(page: p, code: 36, x: Int(v.maxX) - 88, y: Int(v.minY), width: 88, height: Int(v.height))
        // Title, volume pill and back arrow are in the background.
        for id in [206, 207, 119] { try f.setIndicator(page: p, using: id, x: 0, y: 0, first: blank) }
    }

    // MARK: Pixels

    static func color565(_ c: NSColor) -> UInt16 {
        let k = c.usingColorSpace(.sRGB)!
        return UInt16(Int((k.redComponent * 31).rounded()) << 11 | Int((k.greenComponent * 63).rounded()) << 5 | Int((k.blueComponent * 31).rounded()))
    }
}

/// Opaque RGB565 of a region of a context (top row first). Contexts from quantised565 convert exactly.
func rgb565(_ c: CGContext, x: Int = 0, y: Int = 0, w: Int? = nil, h: Int? = nil) -> [UInt16] {
    let w = w ?? c.width, h = h ?? c.height, p = c.data!.assumingMemoryBound(to: UInt8.self), stride = c.bytesPerRow
    var out = [UInt16](); out.reserveCapacity(w * h)
    for yy in y..<(y + h) { for xx in x..<(x + w) {
        let i = yy * stride + 4 * xx
        let r = (Int(p[i]) * 31 + 127) / 255, g = (Int(p[i + 1]) * 63 + 127) / 255, b = (Int(p[i + 2]) * 31 + 127) / 255
        out.append(UInt16(r << 11 | g << 5 | b))
    } }
    return out
}

/// ARGB4444 with straight (unpremultiplied) colour, top row first.
func argb4444(_ c: CGContext) -> [UInt16] {
    let p = c.data!.assumingMemoryBound(to: UInt8.self), stride = c.bytesPerRow
    var out = [UInt16](); out.reserveCapacity(c.width * c.height)
    for y in 0..<c.height { for x in 0..<c.width {
        let i = y * stride + 4 * x, a = Int(p[i + 3])
        guard a > 0 else { out.append(0); continue }
        let q = { (v: Int) in UInt16((min(255, v) * 15 + 127) / 255) }
        out.append(q(a) << 12 | q(Int(p[i]) * 255 / a) << 8 | q(Int(p[i + 1]) * 255 / a) << 4 | q(Int(p[i + 2]) * 255 / a))
    } }
    return out
}
