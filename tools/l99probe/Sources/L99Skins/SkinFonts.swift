import AppKit
import CoreText

/// The two open-licence fonts bundled with the skins (SIL Open Font License 1.1; licence texts in
/// Fonts/). Both are variable fonts, so any weight comes from one file.
/// - Inter: the UI face for every style (stands in for the system font).
/// - JetBrains Mono: the monospaced face (Cyberpunk, small codes).
enum SkinFonts {
    private static func load(_ name: String) -> CGFont {
        guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts"),
              let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) else {
            fatalError("Bundled font \(name).ttf is missing from L99Skins")
        }
        return font
    }
    private static let interFont = load("Inter-Variable")
    private static let monoFont = load("JetBrainsMono-Variable")
    private static var cache: [String: NSFont] = [:]

    private static let wght = 0x7767_6874, opsz = 0x6F70_737A

    static func weightValue(_ w: NSFont.Weight) -> Double {
        switch w {
        case .ultraLight: 200
        case .thin: 100
        case .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 900
        default: 400
        }
    }

    private static func make(_ base: CGFont, key: String, _ size: CGFloat, _ w: NSFont.Weight, opticalSize: Bool) -> NSFont {
        let k = "\(key)-\(size)-\(w.rawValue)"
        if let f = cache[k] { return f }
        var axes: [Int: Double] = [wght: weightValue(w)]
        if opticalSize { axes[opsz] = Double(min(32, max(14, size))) }
        let desc = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: axes as CFDictionary] as CFDictionary)
        let font = CTFontCreateWithGraphicsFont(base, size, nil, desc) as NSFont
        cache[k] = font
        return font
    }

    static func inter(_ size: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { make(interFont, key: "inter", size, w, opticalSize: true) }
    static func mono(_ size: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { make(monoFont, key: "mono", size, w, opticalSize: false) }
}
