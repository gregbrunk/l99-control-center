import AppKit
import CoreGraphics
import L99Core
import L99Link
import L99Skins

/// Loads PNG art exported by the mockup renderer (top row first).
struct PNGArt {
    let width: Int, height: Int
    let rgba: [UInt8]   // premultiplied, top row first

    init(_ path: String) throws {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw LinkError("Can't read \(path)") }
        width = img.width; height = img.height
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        rgba = [UInt8](UnsafeBufferPointer(start: c.data!.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
    }

    /// Opaque RGB565 of a region (the renderer already quantised to 565, so this is exact).
    func rgb565(x: Int = 0, y: Int = 0, w: Int? = nil, h: Int? = nil) -> [UInt16] {
        let w = w ?? width, h = h ?? height
        var out = [UInt16](); out.reserveCapacity(w * h)
        for yy in y..<(y + h) { for xx in x..<(x + w) {
            let i = 4 * (yy * width + xx)
            let r = (Int(rgba[i]) * 31 + 127) / 255, g = (Int(rgba[i + 1]) * 63 + 127) / 255, b = (Int(rgba[i + 2]) * 31 + 127) / 255
            out.append(UInt16(r << 11 | g << 5 | b))
        } }
        return out
    }

    /// ARGB4444 with alpha (unpremultiplied).
    func argb4444() -> [UInt16] {
        (0..<(width * height)).map { p in
            let i = 4 * p, a = Int(rgba[i + 3]); guard a > 0 else { return 0 }
            let q = { (v: Int) in UInt16((min(255, v) * 15 + 127) / 255) }
            return q(a) << 12 | q(Int(rgba[i]) * 255 / a) << 8 | q(Int(rgba[i + 1]) * 255 / a) << 4 | q(Int(rgba[i + 2]) * 255 / a)
        }
    }
}

/// Step-2 hardware test: three pages in three styles, on top of the custom Numpad and top bar.
/// - Calculator (22), Cyberpunk: full-page background, keys re-laid out, RGB565 up/down key art.
/// - Real-time Data (19), Glass Night: new background, restyled digits, a weather icon (condition 0–5),
///   restyled bars (one re-bound to CPU), and a probe re-binding the spare CPU number to 0x0107.
/// - Home (1), Ember: Photos and Touchpad hidden, tiles and media buttons re-laid out.
/// The custom top bar is on all three pages.
func skinStep2Test() throws {
    let out = option("--out") ?? projectRoot.appendingPathComponent("build/UartTFT-II_Flash-step2-test.bin").path
    guard let dir = option("--art") else { throw LinkError("step2-test needs --art <folder exported by the mockup renderer>") }
    func art(_ name: String) throws -> PNGArt { try PNGArt("\(dir)/\(name).png") }
    guard let mdata = FileManager.default.contents(atPath: "\(dir)/manifest.json"),
          let manifest = try JSONSerialization.jsonObject(with: mdata) as? [String: Any] else { throw LinkError("No manifest.json in \(dir)") }

    var file = try InterfaceFile(stockFile: factoryFile)
    try applyLayoutTest(&file)
    try placeTopBarArt(&file)
    let blank = topBarSlots.num          // a transparent 1×1 icon, shared
    let free = Set(try file.emptySlots())
    let weatherSlots = 365...370
    for id in weatherSlots where !free.contains(id) { throw LinkError("Icon slot \(id) isn't empty. Stopped.") }

    // MARK: Calculator (22)
    do {
        let page = 22
        let bg = try art("calc-bg"), down = try art("calc-down")
        try file.setBackground(page: page, pixels: bg.rgb565())
        let keys = manifest["calcKeys"] as! [String: [Int]]
        var codes: [String: Int] = ["C": 0x7F7F, "÷": 0x2F2F, "×": 0x2A2A, "⌫": 0x0808, "+": 0x2B2B, "−": 0x2D2D, "=": 0x3D3D, ".": 0x2E2E]
        for d in 0...9 { codes["\(d)"] = 0x3030 + d * 0x0101 }
        let buttons = try file.touchButtons(page: page)
        guard keys.count == 18, Set(codes.values) == Set(buttons.filter { $0.up != 0xFFFF }.map(\.code)) else {
            throw LinkError("The Calculator's keys aren't the 18 expected. Stopped.")
        }
        for (label, r) in keys {
            let code = codes[label]!, b = buttons.first { $0.code == code }!
            let (x, y, w, h) = (r[0], r[1], r[2], r[3])
            try file.moveButton(page: page, code: code, x: x, y: y, width: w, height: h)
            try file.placeIcon(b.up, width: w, height: h, pixels: bg.rgb565(x: x, y: y, w: w, h: h), format: InterfaceFile.formatRGB565)
            try file.placeIcon(b.down, width: w, height: h, pixels: down.rgb565(x: x, y: y, w: w, h: h), format: InterfaceFile.formatRGB565)
        }
        // Title and back arrow are in the background now.
        try file.setIndicator(page: page, using: 353, x: 0, y: 0, first: blank)
        try file.setIndicator(page: page, using: 119, x: 0, y: 0, first: blank)
        try applyTopBar(&file, page: page)
    }

    // MARK: Real-time Data (19)
    do {
        let page = 19
        let m = manifest["data"] as! [String: [Int]]
        try file.setBackground(page: page, pixels: try art("data-bg").rgb565())
        func glyphs(_ prefix: String, _ names: [String], into first: Int) throws {
            for (i, n) in names.enumerated() {
                let g = try art("\(prefix)-\(n)")
                try file.placeIcon(first + i, width: g.width, height: g.height, pixels: g.argb4444())
            }
        }
        let digits = (0...9).map { "\($0)" }
        // These digit sets are used by this page only, so they're restyled in place.
        try glyphs("time", digits + (0..<4).map { "colon\($0)" }, into: 213)
        try glyphs("mid", digits, into: 260)
        try glyphs("cpu", digits, into: 280)
        try glyphs("weather", (0..<6).map { "\($0)" }, into: weatherSlots.lowerBound)
        try file.setClock(page: page, format: 4, x: m["time"]![0], y: m["time"]![1], first: 213)
        try file.setClock(page: page, format: 7, x: m["weekday"]![0], y: m["weekday"]![1], first: 227)
        try file.setClock(page: page, format: 1, x: m["date"]![0], y: m["date"]![1], first: 227)
        try file.setDigits(page: page, variable: 0x0103, x: m["temp"]![0], y: m["temp"]![1], first: 260)
        try file.setDigits(page: page, variable: 0x0104, x: m["hum"]![0], y: m["hum"]![1], first: 260)
        try file.setDigits(page: page, variable: 0x0106, occurrence: 0, x: m["cpu"]![0], y: m["cpu"]![1], first: 280)
        try file.setDigits(page: page, variable: 0x0106, occurrence: 1, newVariable: 0x0107, x: m["cpuTemp"]![0], y: m["cpuTemp"]![1], first: 227)
        try file.setDigits(page: page, variable: 0x0108, x: m["gpu"]![0], y: m["gpu"]![1], first: 280)
        // Weather: the old title record becomes a 6-state icon on the condition variable.
        try file.setStateIcon(page: page, using: 254, variable: 0x0101, x: m["weather"]![0], y: m["weather"]![1],
                              first: weatherSlots.lowerBound, count: weatherSlots.count)
        // Units and labels are in the background; hide the old static ones.
        try file.setIndicator(page: page, using: 310, occurrence: 0, x: 0, y: 0, first: blank)
        try file.setIndicator(page: page, using: 310, x: 0, y: 0, first: blank)
        try file.setIndicator(page: page, using: 312, x: 0, y: 0, first: blank)
        try file.setIndicator(page: page, using: 313, x: 0, y: 0, first: blank)
        try file.setIndicator(page: page, using: 119, x: 0, y: 0, first: blank)
        // Bars: one track image (314) shared by both; fills 315 (humidity) and 316 (now CPU).
        let track = try art("bar-track"), fill = try art("bar-fill")
        try file.placeIcon(314, width: track.width, height: track.height, pixels: track.argb4444())
        for id in [315, 316] { try file.placeIcon(id, width: fill.width, height: fill.height, pixels: fill.argb4444()) }
        let hb = m["humBar"]!, cb = m["cpuBar"]!
        try file.setProgressBar(page: page, variable: 0x0104, x: hb[0], y: hb[1], trackX: hb[0], trackY: hb[1], max: 100)
        try file.setProgressBar(page: page, variable: 0x0102, newVariable: 0x0106, x: cb[0], y: cb[1], trackX: cb[0], trackY: cb[1], max: 100)
        try applyTopBar(&file, page: page)
    }

    // MARK: Home (1)
    do {
        let page = 1
        let h = manifest["home"] as! [String: Any]
        // Home ignores the background table (it shows the wallpaper chosen in Screen customisations),
        // so the whole page is also a full-screen image record drawn first. The table copy stays so
        // the top-bar widgets repaint their patches from the same picture.
        let homeBG = try art("home-bg").rgb565()
        try file.setBackground(page: page, pixels: homeBG)
        let homeSlot = 371
        guard free.contains(homeSlot) else { throw LinkError("Icon slot \(homeSlot) isn't empty. Stopped.") }
        try file.placeIcon(homeSlot, width: 320, height: 480, pixels: homeBG, format: InterfaceFile.formatRGB565)
        func move(_ code: Int, goto: Int? = nil, _ r: [Int]) throws {
            try file.moveButton(page: page, code: code, goto: goto, x: r[0], y: r[1], width: r[2], height: r[3])
        }
        try move(32, goto: 18, h["play"] as! [Int]); try move(32, goto: 19, h["data"] as! [Int])
        let tiles = h["tiles"] as! [String: [Int]]
        try move(32, goto: 4, tiles["settings"]!); try move(32, goto: 16, tiles["screen"]!); try move(32, goto: 17, tiles["colour"]!)
        try move(96, tiles["gifs"]!); try move(32, goto: 21, tiles["numpad"]!); try move(32, goto: 22, tiles["calculator"]!)
        // Hidden apps: Photos (20) and Touchpad (23) shrink to a 1×1 spot in the bottom-left corner.
        try move(32, goto: 20, [0, 479, 1, 1]); try move(32, goto: 23, [0, 479, 1, 1])
        let media = h["media"] as! [String: [Int]]
        try move(0x22, media["volDown"]!); try move(0x23, media["mute"]!); try move(0x24, media["volUp"]!); try move(0xF120, media["alarm"]!)
        // The app grid image and the media bar are in the background now.
        try file.setIndicator(page: page, using: 0, x: 0, y: 0, first: homeSlot)
        try file.moveIndicatorToFront(page: page, using: homeSlot)
        try file.setIndicator(page: page, using: 560, x: 0, y: 0, first: blank)
        try applyTopBar(&file, page: page)
    }
    try save(file, to: out)
}

/// Renders every section in every style to PNGs, plus one contact sheet per style.
func skinPreviewAll() throws {
    guard let dir = option("--out") else { throw LinkError("preview needs --out <folder>") }
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let sections: [SkinSection] = [.home, .play, .data, .numpad, .calculator]
    for style in SkinStyle.allCases {
        let sheet = CGContext(data: nil, width: 320 * sections.count + 8 * (sections.count - 1), height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (i, sec) in sections.enumerated() {
            let img = SkinPreview.render(sec, style: style)
            try SkinPreview.writePNG(img, to: "\(dir)/\(style.rawValue)-\(sec.rawValue).png")
            sheet.draw(img, in: CGRect(x: i * 328, y: 0, width: 320, height: 480))
        }
        try SkinPreview.writePNG(sheet.makeImage()!, to: "\(dir)/sheet-\(style.rawValue).png")
    }
    print("Wrote previews to \(dir)")
}

/// Lists a page's display records and touch buttons, and which pages use the icons given with --icons a-b.
func skinDump() throws {
    let file = try InterfaceFile(stockFile: factoryFile)
    for page in (option("--pages") ?? "").split(separator: ",").compactMap({ Int($0) }) {
        print("== page \(page)")
        for r in try file.displayRecords(page: page) {
            let words = stride(from: 0, to: r.length - 1, by: 2).map { String(format: "%d", Int(file.bytes[r.offset + $0]) | Int(file.bytes[r.offset + $0 + 1]) << 8) }
            print("  type \(r.type) len \(r.length): \(words.joined(separator: " "))")
        }
        for b in try file.touchButtons(page: page) { print("  touch \(b)") }
    }
    if let spec = option("--icons") {
        let parts = spec.split(separator: "-").compactMap { Int($0) }
        let ids = Set(parts[0]...(parts.count > 1 ? parts[1] : parts[0]))
        for page in 0..<64 {
            guard let recs = try? file.displayRecords(page: page) else { continue }
            var hits = Set<Int>()
            for r in recs {
                let w = stride(from: 0, to: r.length - 1, by: 2).map { Int(file.bytes[r.offset + $0]) | Int(file.bytes[r.offset + $0 + 1]) << 8 }
                for v in w where ids.contains(v) { hits.insert(r.type) }
            }
            if let bs = try? file.touchButtons(page: page) { for b in bs where ids.contains(b.up) || ids.contains(b.down) { hits.insert(-1) } }
            if !hits.isEmpty { print("page \(page): record types \(hits.sorted())") }
        }
    }
}

/// Writes icons a…b (both banks) as one PNG strip per bank: skin-file icons --icons a-b --out file-prefix
func skinIconStrip() throws {
    let file = try InterfaceFile(stockFile: factoryFile)
    let parts = (option("--icons") ?? "").split(separator: "-").compactMap { Int($0) }
    guard let a = parts.first, let out = option("--out") else { throw LinkError("icons needs --icons a-b --out prefix") }
    let ids = a...(parts.count > 1 ? parts[1] : a)
    for bank in 0..<2 {
        let icons = try ids.map { try file.icon($0, bank: bank) }
        for (id, ic) in zip(ids, icons) { print("bank \(bank) icon \(id): \(ic.width)×\(ic.height) format \(ic.format)") }
        let W = icons.reduce(0) { $0 + $1.width + 4 }, H = icons.map(\.height).max() ?? 1
        let c = CGContext(data: nil, width: max(W, 1), height: max(H, 1), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
        var x = 0
        for (id, ic) in zip(ids, icons) where ic.width > 0 {
            let px = try file.pixels(id, bank: bank)
            var rgba = [UInt8](repeating: 0, count: ic.width * ic.height * 4)
            for (i, v) in px.enumerated() where i < ic.width * ic.height {
                let v = Int(v)
                if ic.format == InterfaceFile.formatARGB4444 {
                    let al = (v >> 12) * 17
                    rgba[4*i] = UInt8(((v >> 8) & 15) * 17 * al / 255); rgba[4*i+1] = UInt8(((v >> 4) & 15) * 17 * al / 255); rgba[4*i+2] = UInt8((v & 15) * 17 * al / 255); rgba[4*i+3] = UInt8(al)
                } else {
                    rgba[4*i] = UInt8((v >> 11) * 255 / 31); rgba[4*i+1] = UInt8(((v >> 5) & 63) * 255 / 63); rgba[4*i+2] = UInt8((v & 31) * 255 / 31); rgba[4*i+3] = 255
                }
            }
            let img = CGContext(data: &rgba, width: ic.width, height: ic.height, bitsPerComponent: 8, bytesPerRow: ic.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
            c.draw(img, in: CGRect(x: x, y: H - ic.height, width: ic.width, height: ic.height)); x += ic.width + 4
        }
        let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)-bank\(bank).png"))
    }
}

func skinFreeSlots() throws {
    let file = try InterfaceFile(stockFile: factoryFile)
    let free = try file.freeSlots()
    var runs: [ClosedRange<Int>] = []
    for id in free { if let l = runs.last, l.upperBound == id - 1 { runs[runs.count - 1] = l.lowerBound...id } else { runs.append(id...id) } }
    print("\(free.count) free slots of \(try file.emptySlots().count) empty: " + runs.map { $0.count == 1 ? "\($0.lowerBound)" : "\($0.lowerBound)–\($0.upperBound)" }.joined(separator: ", "))
}

/// Builds a mixed skin: skin-file mix --home ember --play liquid-glass-night --data … --numpad … --calculator …
/// [--top-bar style] [--hide photos,touchpad] [--out file] [--preview sheet.png]
func skinMix() throws {
    var plan = SkinPlan()
    for section in SkinSection.allCases {
        guard let v = option("--\(section.rawValue)") else { continue }
        guard let style = SkinStyle(rawValue: v) else {
            throw LinkError("Unknown style \(v). Styles: " + SkinStyle.allCases.map(\.rawValue).joined(separator: ", "))
        }
        plan.styles[section] = style
    }
    for name in (option("--hide") ?? "").split(separator: ",") {
        guard let app = HomeApp(rawValue: String(name)) else { throw LinkError("Unknown app \(name). Apps: " + HomeApp.allCases.map(\.rawValue).joined(separator: ", ")) }
        plan.hiddenApps.insert(app)
    }
    let out = option("--out") ?? projectRoot.appendingPathComponent("build/UartTFT-II_Flash-mix.bin").path
    guard let stock = FileManager.default.contents(atPath: factoryFile) else { throw LinkError("Can't read \(factoryFile)") }
    let result = try SkinBuilder.build(plan, stockBytes: [UInt8](stock))
    for n in result.notes { print(n) }
    print("\(result.slotsUsed) icon slots, \(result.bytesAdded / 1024) KB of art.")
    try save(result.file, to: out)
    if let sheetPath = option("--preview") {
        let pages = [SkinSection.home, .play, .data, .numpad, .calculator].filter { plan.styles[$0] != nil }
        let sheet = CGContext(data: nil, width: 328 * pages.count - 8, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (i, sec) in pages.enumerated() {
            let img = SkinPreview.render(sec, style: plan.styles[sec]!, topBar: plan.topBarStyle,
                                         hidden: sec == .home ? Set(plan.hiddenApps.map(\.displayName)) : [])
            sheet.draw(img, in: CGRect(x: i * 328, y: 0, width: 320, height: 480))
        }
        try SkinPreview.writePNG(sheet.makeImage()!, to: sheetPath)
        print("Preview: \(sheetPath)")
    }
}

/// Prints the top-bar contrast for every page style × top-bar style.
func skinContrast() {
    print("page \\ bar   " + SkinStyle.allCases.map { String($0.rawValue.prefix(8)).padding(toLength: 9, withPad: " ", startingAt: 0) }.joined())
    for p in SkinStyle.allCases {
        print(String(p.rawValue.prefix(12)).padding(toLength: 13, withPad: " ", startingAt: 0) + SkinStyle.allCases.map { String(format: "%-9.1f", SkinPreview.topBarContrast(page: p, topBar: $0)) }.joined())
    }
}
