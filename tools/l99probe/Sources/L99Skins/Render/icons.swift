// Simple line icons on a 24-unit grid, drawn with CoreGraphics (no icon fonts).
import AppKit

enum Icon { case gear, screen, bulb, sparkles, note, chart, photo, numpad, calculator, touchpad
            case volDown, mute, volUp, alarm, play, pause, playPause, prev, next, backspace
            case thermo, drop, chip, gpu, sun, cloudSun }

func icon(_ c: CGContext, _ k: Icon, _ r: CGRect, _ col: NSColor, _ lw: CGFloat = 1.8) {
    c.saveGState()
    c.translateBy(x: r.minX, y: r.minY); let s = min(r.width, r.height) / 24; c.scaleBy(x: s, y: s)
    c.setStrokeColor(col.cgColor); c.setFillColor(col.cgColor)
    c.setLineWidth(lw / s); c.setLineCap(.round); c.setLineJoin(.round)
    func line(_ pts: [(CGFloat, CGFloat)]) { c.move(to: CGPoint(x: pts[0].0, y: pts[0].1)); for p in pts.dropFirst() { c.addLine(to: CGPoint(x: p.0, y: p.1)) }; c.strokePath() }
    func circ(_ x: CGFloat, _ y: CGFloat, _ rr: CGFloat, fill f: Bool = false) {
        c.addEllipse(in: CGRect(x: x - rr, y: y - rr, width: 2 * rr, height: 2 * rr)); f ? c.fillPath() : c.strokePath()
    }
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat) { c.addPath(rr(CGRect(x: x, y: y, width: w, height: h), rad)); c.strokePath() }
    func speaker() { line([(3, 9.5), (6.5, 9.5), (11, 5.5), (11, 18.5), (6.5, 14.5), (3, 14.5), (3, 9.5)]) }
    switch k {
    case .gear:
        circ(12, 12, 3.2)
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            line([(12 + 6.2 * cos(a), 12 + 6.2 * sin(a)), (12 + 9.2 * cos(a), 12 + 9.2 * sin(a))])
        }
        circ(12, 12, 6.4)
    case .screen: box(3, 4.5, 18, 12, 2); line([(9, 20), (15, 20)]); line([(12, 16.5), (12, 20)]); line([(7, 13), (11, 9), (13, 11), (17, 7.5)])
    case .bulb:
        c.addArc(center: CGPoint(x: 12, y: 10), radius: 6, startAngle: .pi * 0.8, endAngle: .pi * 0.2, clockwise: false); c.strokePath()
        line([(7.2, 13.6), (9.2, 16.5), (14.8, 16.5), (16.8, 13.6)]); line([(9.5, 19.5), (14.5, 19.5)])
    case .sparkles:
        func star(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
            c.move(to: CGPoint(x: x, y: y - s))
            c.addQuadCurve(to: CGPoint(x: x + s, y: y), control: CGPoint(x: x + s * 0.2, y: y - s * 0.2))
            c.addQuadCurve(to: CGPoint(x: x, y: y + s), control: CGPoint(x: x + s * 0.2, y: y + s * 0.2))
            c.addQuadCurve(to: CGPoint(x: x - s, y: y), control: CGPoint(x: x - s * 0.2, y: y + s * 0.2))
            c.addQuadCurve(to: CGPoint(x: x, y: y - s), control: CGPoint(x: x - s * 0.2, y: y - s * 0.2)); c.strokePath()
        }
        star(10, 13, 7); star(18.5, 5.5, 3)
    case .note: line([(9, 17), (9, 5), (19, 3), (19, 15)]); circ(6.5, 17.5, 2.6); circ(16.5, 15.5, 2.6); line([(9, 8.5), (19, 6.5)])
    case .chart: line([(3, 3), (3, 21), (21, 21)]); line([(6.5, 16), (10.5, 11), (14, 14), (20, 6)]); line([(16.5, 6), (20, 6), (20, 9.5)])
    case .photo: box(3, 5, 18, 14, 2.5); circ(8.5, 10, 1.7); line([(4, 17), (9.5, 13), (13, 15.5), (16.5, 12), (20.5, 15.5)])
    case .numpad: for row in 0..<3 { for col in 0..<3 { circ(6 + CGFloat(col) * 6, 6 + CGFloat(row) * 6, 1.6, fill: true) } }; circ(12, 21, 1.6, fill: true)
    case .calculator: box(5, 3, 14, 18, 2.5); box(8, 6, 8, 4, 1); for row in 0..<2 { for col in 0..<3 { circ(8.5 + CGFloat(col) * 3.5, 13.5 + CGFloat(row) * 3.5, 0.9, fill: true) } }
    case .touchpad: box(3, 5, 18, 14, 3); line([(12, 14.5), (12, 19)]); line([(3.5, 14.5), (20.5, 14.5)])
    case .volDown: speaker(); line([(15, 12), (21, 12)])
    case .volUp: speaker(); line([(15, 12), (21, 12)]); line([(18, 9), (18, 15)])
    case .mute: speaker(); line([(15, 9), (21, 15)]); line([(21, 9), (15, 15)])
    case .alarm: circ(12, 13, 7.5); line([(12, 9), (12, 13), (15, 15)]); line([(3.5, 6.5), (6.5, 3.5)]); line([(17.5, 3.5), (20.5, 6.5)])
    case .play: c.move(to: CGPoint(x: 8, y: 5)); c.addLine(to: CGPoint(x: 19, y: 12)); c.addLine(to: CGPoint(x: 8, y: 19)); c.closePath(); c.fillPath()
    case .pause: c.fill(CGRect(x: 7, y: 5, width: 3.5, height: 14)); c.fill(CGRect(x: 13.5, y: 5, width: 3.5, height: 14))
    case .playPause:
        c.move(to: CGPoint(x: 4, y: 6)); c.addLine(to: CGPoint(x: 12, y: 12)); c.addLine(to: CGPoint(x: 4, y: 18)); c.closePath(); c.fillPath()
        c.fill(CGRect(x: 14, y: 6, width: 2.4, height: 12)); c.fill(CGRect(x: 18.4, y: 6, width: 2.4, height: 12))
    case .prev:
        c.fill(CGRect(x: 4, y: 6, width: 2.2, height: 12))
        c.move(to: CGPoint(x: 13, y: 6)); c.addLine(to: CGPoint(x: 6.5, y: 12)); c.addLine(to: CGPoint(x: 13, y: 18)); c.closePath(); c.fillPath()
        c.move(to: CGPoint(x: 20, y: 6)); c.addLine(to: CGPoint(x: 13.5, y: 12)); c.addLine(to: CGPoint(x: 20, y: 18)); c.closePath(); c.fillPath()
    case .next:
        c.fill(CGRect(x: 17.8, y: 6, width: 2.2, height: 12))
        c.move(to: CGPoint(x: 11, y: 6)); c.addLine(to: CGPoint(x: 17.5, y: 12)); c.addLine(to: CGPoint(x: 11, y: 18)); c.closePath(); c.fillPath()
        c.move(to: CGPoint(x: 4, y: 6)); c.addLine(to: CGPoint(x: 10.5, y: 12)); c.addLine(to: CGPoint(x: 4, y: 18)); c.closePath(); c.fillPath()
    case .backspace: line([(8, 5), (21, 5), (21, 19), (8, 19), (2.5, 12), (8, 5)]); line([(11, 9), (17, 15)]); line([(17, 9), (11, 15)])
    case .thermo: line([(10, 14), (10, 5)]); c.addArc(center: CGPoint(x: 12, y: 5), radius: 2, startAngle: .pi, endAngle: 0, clockwise: false); c.strokePath()
        line([(14, 5), (14, 14)]); circ(12, 17.5, 4); line([(12, 9), (12, 17)])
    case .drop:
        c.move(to: CGPoint(x: 12, y: 3)); c.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 3, y: 13), control2: CGPoint(x: 5, y: 21))
        c.addCurve(to: CGPoint(x: 12, y: 3), control1: CGPoint(x: 19, y: 21), control2: CGPoint(x: 21, y: 13)); c.strokePath()
    case .chip: box(6, 6, 12, 12, 2); box(9.5, 9.5, 5, 5, 0.5)
        for i in 0..<3 { let p = 8.5 + CGFloat(i) * 3.5; line([(p, 3), (p, 6)]); line([(p, 18), (p, 21)]); line([(3, p), (6, p)]); line([(18, p), (21, p)]) }
    case .gpu: box(2.5, 7, 19, 11, 2); circ(9, 12.5, 3); line([(15, 10.5), (18.5, 10.5)]); line([(15, 14.5), (18.5, 14.5)]); line([(5, 18), (5, 21)])
    case .sun: circ(12, 12, 4.5); for i in 0..<8 { let a = CGFloat(i) * .pi / 4; line([(12 + 7 * cos(a), 12 + 7 * sin(a)), (12 + 9.5 * cos(a), 12 + 9.5 * sin(a))]) }
    case .cloudSun:
        circ(9, 9, 3.5); for i in 0..<5 { let a = CGFloat(i) * .pi / 4 + .pi; line([(9 + 5.5 * cos(a), 9 + 5.5 * sin(a)), (9 + 7.5 * cos(a), 9 + 7.5 * sin(a))]) }
        c.move(to: CGPoint(x: 8, y: 20)); c.addLine(to: CGPoint(x: 18, y: 20))
        c.addArc(center: CGPoint(x: 18, y: 16.5), radius: 3.5, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        c.addArc(center: CGPoint(x: 13.5, y: 13.5), radius: 4.2, startAngle: -.pi * 0.1, endAngle: -.pi * 0.95, clockwise: true)
        c.addArc(center: CGPoint(x: 8.5, y: 17), radius: 3, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true); c.strokePath()
    }
    c.restoreGState()
}
