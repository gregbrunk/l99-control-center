import AppKit
import CoreGraphics
import CoreText
import L99Core

/// Draws key art with CoreGraphics and converts it to ARGB4444 words (top row first).
enum SkinArt {
    enum Kind { case number, symbol, accent }

    struct Style {
        var radius: CGFloat = 14, inset: CGFloat = 3
        var font = "Avenir Next", weight: CGFloat = 0.3
        var fill: (Kind, Bool) -> UInt32
        var text: (Kind, Bool) -> UInt32
    }

    /// Direction A, "soft dark": charcoal keys, violet accent and pressed state.
    static let softDark = Style(
        fill: { k, p in p ? 0x7C5CFF : (k == .number ? 0x2A2A31 : k == .accent ? 0x7C5CFF : 0x3A3A44) },
        text: { k, p in p || k == .accent ? 0xFFFFFF : (k == .number ? 0xF2F2F5 : 0xB9B4FF) })

    static func color(_ h: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
    }

    static func key(_ label: String, kind: Kind, pressed: Bool, width w: Int, height h: Int, style s: Style) -> [UInt16] {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let r = CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: s.inset, dy: s.inset)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: s.radius, cornerHeight: s.radius, transform: nil))
        ctx.setFillColor(color(s.fill(kind, pressed))); ctx.fillPath()
        let size: CGFloat = label.count > 1 ? 18 : 32
        let desc = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: s.font,
                                                         kCTFontTraitsAttribute: [kCTFontWeightTrait: s.weight]] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(desc, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: color(s.text(kind, pressed))]))
        let b = CTLineGetImageBounds(line, ctx)
        ctx.textPosition = CGPoint(x: (CGFloat(w) - b.width) / 2 - b.minX, y: (CGFloat(h) - b.height) / 2 - b.minY)
        CTLineDraw(line, ctx)
        return argb4444(ctx, w, h)
    }

    /// Bitmap-context memory is top row first. Unpremultiplies and rounds to 4 bits per channel.
    static func argb4444(_ ctx: CGContext, _ w: Int, _ h: Int) -> [UInt16] {
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<(w * h)).map { i in
            let a = Int(p[4 * i + 3]); guard a > 0 else { return 0 }
            let q = { (v: Int) in UInt16((min(255, v) * 15 + 127) / 255) }
            let c = (0..<3).map { q(Int(p[4 * i + $0]) * 255 / a) }
            return q(a) << 12 | c[0] << 8 | c[1] << 4 | c[2]
        }
    }
}
