import AppKit

/// The six skin styles.
public enum SkinStyle: String, CaseIterable, Sendable {
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
public enum SkinSection: String, CaseIterable, Sendable {
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
    /// A 320×480 preview of one page, as it will look on the screen (565 colour, with sample values).
    /// `topBar` is the style of the top bar drawn over it; by default the page's own.
    /// The top bar section on its own previews on the Home page.
    public static func render(_ section: SkinSection, style: SkinStyle, topBar: SkinStyle? = nil, hidden: Set<String> = []) -> CGImage {
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
