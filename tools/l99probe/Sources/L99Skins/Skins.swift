import AppKit

/// The six skin styles.
public enum SkinStyle: String, CaseIterable, Sendable, Codable {
    case liquidGlassNight = "liquid-glass-night", liquidGlassDay = "liquid-glass-day", cyberpunk, ceramic, ember, midnightLED = "midnight-led"

    public var displayName: String {
        switch self {
        case .liquidGlassNight: "Liquid Glass Night"
        case .liquidGlassDay: "Liquid Glass Day"
        case .cyberpunk: "Cyberpunk"
        case .ceramic: "Ceramic"
        case .ember: "Ember"
        case .midnightLED: "Midnight LED"
        }
    }
    var sid: SID { SID(rawValue: rawValue)! }
}

/// The parts of the screen that can each take their own style.
public enum SkinSection: String, CaseIterable, Sendable, Codable {
    case home, play, data, numpad, calculator, topBar = "top-bar"

    public var displayName: String {
        switch self {
        case .home: "Home"
        case .play: "Play"
        case .data: "Real-time Data"
        case .numpad: "Numpad"
        case .calculator: "Calculator"
        case .topBar: "Top bar"
        }
    }
}

public enum SkinPreview {
    /// How readable the top bar is over a page: the WCAG contrast ratio between the bar's ink and the
    /// average colour of the page behind it (the top 34 rows). Under about 3 reads poorly.
    public static func topBarContrast(page style: SkinStyle, topBar: SkinStyle) -> Double {
        let c = newContext(W, 34)
        background(style.sid, c)
        let p = c.data!.assumingMemoryBound(to: UInt8.self)
        var sum = 0.0, n = 0
        for y in 0..<34 { for x in 0..<W { let i = y * c.bytesPerRow + 4 * x; sum += luminance(Double(p[i]) / 255, Double(p[i + 1]) / 255, Double(p[i + 2]) / 255); n += 1 } }
        let ink = TopBarKit(topBar.sid).colors.ink.usingColorSpace(.sRGB)!
        let a = ink.alphaComponent, bg = sum / Double(n)
        // Ink drawn with alpha over the page: blend in linear light (close enough for a warning).
        let inkL = a * luminance(ink.redComponent, ink.greenComponent, ink.blueComponent) + (1 - a) * bg
        let (hi, lo) = (max(inkL, bg), min(inkL, bg))
        return (hi + 0.05) / (lo + 0.05)
    }
    static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// A 320×480 preview of one page, as it will look on the screen (565 colour, with sample values).
    /// `topBar` is the style of the top bar drawn over it; by default the page's own.
    /// The top bar section on its own previews on the Home page.
    public static func render(_ section: SkinSection, style: SkinStyle, topBar: SkinStyle? = nil, hidden: Set<String> = [], fahrenheit: Bool = false) -> CGImage {
        temperatureUnit = fahrenheit ? "°F" : "°C"; defer { temperatureUnit = "°C" }
        let page: Page
        switch section {
        case .home, .topBar: page = .home
        case .play: page = .play
        case .data: page = .data
        case .numpad: page = .numpad
        case .calculator: page = .calculator
        }
        let s = style.sid
        let c = newContext()
        background(s, c)
        let (panels, content) = page == .home && !hidden.isEmpty ? home(s, hidden: hidden) : layout(s, page)
        drawPanels(s, c, panels)
        content(c)
        topBarStyle = (topBar ?? style).sid
        finish(s, c)
        topBarStyle = nil
        return quantised565(c).makeImage()!
    }

    public static func writePNG(_ img: CGImage, to path: String) throws {
        let rep = NSBitmapImageRep(cgImage: img)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: URL(fileURLWithPath: path))
    }
}
