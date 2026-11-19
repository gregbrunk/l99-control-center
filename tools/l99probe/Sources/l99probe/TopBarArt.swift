import AppKit
import CoreGraphics
import L99Core

/// Top-bar indicator art (ARGB4444, transparent background), "Ember" style: white ink, orange when on.
/// Drawn with y up; SkinArt.argb4444 reads the bitmap top row first.
enum TopBarArt {
    static let ink = SkinArt.color(0xFFFFFF), orange = SkinArt.color(0xFF7A1A)
    static func dim(_ a: CGFloat) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: a) }

    static func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> [UInt16] {
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(c)
        return SkinArt.argb4444(c, w, h)
    }

    static func font(_ size: CGFloat, bold: Bool = true) -> NSFont { NSFont.systemFont(ofSize: size, weight: bold ? .bold : .semibold) }

    /// Draws text centred in `r` (y-up coordinates).
    static func text(_ c: CGContext, _ s: String, _ f: NSFont, _ col: CGColor, in r: CGRect, kern: CGFloat = 0.4) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: col, .kern: kern]))
        let b = CTLineGetImageBounds(line, c)
        c.textPosition = CGPoint(x: r.midX - b.width / 2 - b.minX, y: r.midY - b.height / 2 - b.minY)
        CTLineDraw(line, c)
    }

    static func textWidth(_ s: String, _ f: NSFont) -> Int {
        Int(ceil(NSAttributedString(string: s, attributes: [.font: f, .kern: 0.4]).size().width))
    }

    static let chipH = 15
    static func chipWidth(_ labels: [String]) -> Int { labels.map { textWidth($0, font(8.5)) }.max()! + 12 }

    /// A lock-state chip: filled orange with white text when on, a faint outline with dim text when off.
    static func chip(_ label: String, on: Bool, width w: Int) -> [UInt16] {
        canvas(w, chipH) { c in
            let r = CGRect(x: 0.5, y: 0.5, width: CGFloat(w) - 1, height: CGFloat(chipH) - 1)
            let path = CGPath(roundedRect: r, cornerWidth: 7, cornerHeight: 7, transform: nil)
            c.addPath(path)
            if on { c.setFillColor(orange); c.fillPath() } else { c.setStrokeColor(dim(0.22)); c.setLineWidth(1); c.strokePath() }
            text(c, label, font(8.5), on ? ink : dim(0.4), in: r)
        }
    }

    /// The lock chip: a closed padlock (on) or an open one (off).
    static func lockChip(closed: Bool, width w: Int) -> [UInt16] {
        canvas(w, chipH) { c in
            let r = CGRect(x: 0.5, y: 0.5, width: CGFloat(w) - 1, height: CGFloat(chipH) - 1)
            c.addPath(CGPath(roundedRect: r, cornerWidth: 7, cornerHeight: 7, transform: nil))
            if closed { c.setFillColor(orange); c.fillPath() } else { c.setStrokeColor(dim(0.22)); c.setLineWidth(1); c.strokePath() }
            let col = closed ? ink : dim(0.4), cx = r.midX
            c.setFillColor(col)
            c.addPath(CGPath(roundedRect: CGRect(x: cx - 3.5, y: 3.5, width: 7, height: 5.5), cornerWidth: 1, cornerHeight: 1, transform: nil)); c.fillPath()
            c.setStrokeColor(col); c.setLineWidth(1.3)
            if closed { c.addArc(center: CGPoint(x: cx, y: 9), radius: 2.4, startAngle: 0, endAngle: .pi, clockwise: false) }
            else { c.addArc(center: CGPoint(x: cx + 2.5, y: 9.5), radius: 2.4, startAngle: 0, endAngle: .pi, clockwise: false) }
            c.strokePath()
        }
    }

    static let connW = 50, connH = 18
    /// Connection modes in the screen's order: cable, receiver, then three paired channels.
    static func connection(_ mode: Int) -> [UInt16] {
        canvas(connW, connH) { c in
            let cy: CGFloat = 9
            c.setStrokeColor(ink); c.setFillColor(ink); c.setLineWidth(1.4); c.setLineCap(.round)
            let label: String
            switch mode {
            case 0:
                c.addPath(CGPath(roundedRect: CGRect(x: 2, y: cy - 4, width: 8, height: 8), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)); c.strokePath()
                c.move(to: CGPoint(x: 10, y: cy)); c.addCurve(to: CGPoint(x: 18, y: cy + 3), control1: CGPoint(x: 14, y: cy), control2: CGPoint(x: 15, y: cy + 3)); c.strokePath()
                label = "USB"
            case 1:
                c.addPath(CGPath(roundedRect: CGRect(x: 2, y: cy - 5, width: 11, height: 7), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)); c.strokePath()
                c.fill(CGRect(x: 13, y: cy - 3.5, width: 3.5, height: 4))
                for (i, rad) in [2.8, 5.3].enumerated() {
                    c.setStrokeColor(dim(i == 0 ? 1 : 0.6))
                    c.addArc(center: CGPoint(x: 7.5, y: cy + 1.5), radius: rad, startAngle: .pi * 0.2, endAngle: .pi * 0.8, clockwise: false); c.strokePath()
                }
                label = "2.4G"
            default:
                for (i, rad) in [2.5, 5.0, 7.5].enumerated() {
                    c.setStrokeColor(dim(1 - CGFloat(i) * 0.25))
                    c.addArc(center: CGPoint(x: 3, y: cy), radius: rad, startAngle: -.pi * 0.3, endAngle: .pi * 0.3, clockwise: false); c.strokePath()
                }
                label = "\(mode - 1)"
            }
            text(c, label, font(9.5, bold: false), ink, in: CGRect(x: 20, y: 0, width: CGFloat(textWidth(label, font(9.5, bold: false))) + 2, height: CGFloat(connH)), kern: 0)
        }
    }

    static let batW = 26, batH = 14
    /// Battery states in the screen's order: empty, low, then rising levels, then charging.
    static func battery(_ state: Int) -> [UInt16] {
        let levels: [CGFloat] = [0, 0.15, 0.35, 0.55, 0.78, 1.0, 0.6]
        let red = SkinArt.color(0xFF4D5E), green = SkinArt.color(0x41E2A0)
        return canvas(batW, batH) { c in
            let cell = CGRect(x: 0.5, y: 1.5, width: 22, height: 11)
            c.addPath(CGPath(roundedRect: cell, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
            c.setStrokeColor(state <= 1 ? red : dim(0.5)); c.setLineWidth(1); c.strokePath()
            c.setFillColor(dim(0.5)); c.fill(CGRect(x: 23.5, y: 5, width: 1.5, height: 4))
            let lvl = levels[state], inner = cell.insetBy(dx: 2, dy: 2)
            if lvl > 0 {
                c.setFillColor(state == 6 ? green : state == 1 ? red : ink)
                c.addPath(CGPath(roundedRect: CGRect(x: inner.minX, y: inner.minY, width: max(2.5, inner.width * lvl), height: inner.height),
                                 cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)); c.fillPath()
            }
            if state == 6 {
                let bx = cell.midX, by = cell.midY, p = CGMutablePath()
                p.move(to: CGPoint(x: bx + 1.5, y: by + 5)); p.addLine(to: CGPoint(x: bx - 2.5, y: by - 0.8)); p.addLine(to: CGPoint(x: bx, y: by - 0.8))
                p.addLine(to: CGPoint(x: bx - 1.5, y: by - 5)); p.addLine(to: CGPoint(x: bx + 2.5, y: by + 0.8)); p.addLine(to: CGPoint(x: bx, y: by + 0.8)); p.closeSubpath()
                c.addPath(p); c.setFillColor(SkinArt.color(0x0A0A0A)); c.fillPath()
            }
        }
    }

    static let digitW = 8, digitH = 14
    static func digit(_ d: Int) -> [UInt16] {
        canvas(digitW, digitH) { c in text(c, "\(d)", font(11.5), ink, in: CGRect(x: 0, y: 0, width: digitW, height: digitH), kern: 0) }
    }
    /// The clock's colon (the screen has four colon frames; all drawn the same).
    static func colon() -> [UInt16] {
        canvas(digitW, digitH) { c in
            c.setFillColor(ink)
            c.fillEllipse(in: CGRect(x: 2.6, y: 3, width: 2.6, height: 2.6)); c.fillEllipse(in: CGRect(x: 2.6, y: 8.2, width: 2.6, height: 2.6))
        }
    }
    /// A fully transparent 1×1 icon: hides an indicator without removing its record.
    static func blank() -> [UInt16] { [0] }
    static let pctW = 10
    static func percent() -> [UInt16] {
        canvas(pctW, digitH) { c in text(c, "%", font(10), ink, in: CGRect(x: 0, y: 0, width: pctW, height: digitH), kern: 0) }
    }
}
