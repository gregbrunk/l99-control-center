import AppKit
import CoreGraphics
import Foundation
import ImageIO
import L99Core
import L99Link

enum Images {
    static let w = ScreenProtocol.width, h = ScreenProtocol.height

    private static func context() -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    private static func rgba(_ ctx: CGContext) -> [UInt8] {
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: p, count: w * h * 4))
    }

    /// Any image file → aspect-fill 320×480 over black → container.
    static func container(fromFile path: String) throws -> [UInt8] {
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1440,
              ] as CFDictionary)
        else { throw LinkError("Could not read image \(path)") }
        let ctx = context()
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let scale = max(Double(w) / Double(img.width), Double(h) / Double(img.height))
        let dw = Double(img.width) * scale, dh = Double(img.height) * scale
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: (Double(w) - dw) / 2, y: (Double(h) - dh) / 2, width: dw, height: dh))
        return try ScreenProtocol.imageContainer(rgb565: ScreenProtocol.rgb565(fromRGBA: rgba(ctx)))
    }

    /// A bold test card: colour bars, a gradient, a frame, and a timestamp so a stale image is obvious.
    static func testCard() throws -> [UInt8] {
        let ctx = context()
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        let bars: [NSColor] = [.white, .yellow, .cyan, .green, .magenta, .red, .blue]
        for (i, c) in bars.enumerated() {
            c.setFill(); NSRect(x: CGFloat(i) * CGFloat(w) / 7, y: 300, width: CGFloat(w) / 7 + 1, height: 140).fill()
        }
        NSGradient(starting: .black, ending: .white)!.draw(in: NSRect(x: 0, y: 250, width: w, height: 40), angle: 0)
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: NSRect(x: 2, y: 2, width: w - 4, height: h - 4)); border.lineWidth = 4; border.stroke()
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.white]
        ("L99 PROBE" as NSString).draw(at: NSPoint(x: 52, y: 160), withAttributes: attrs)
        (f.string(from: Date()) as NSString).draw(at: NSPoint(x: 78, y: 90),
            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 40, weight: .bold), .foregroundColor: NSColor.systemOrange])
        ("TOP" as NSString).draw(at: NSPoint(x: 140, y: 448), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState()
        return try ScreenProtocol.imageContainer(rgb565: ScreenProtocol.rgb565(fromRGBA: rgba(ctx)))
    }

    /// The factory photo-frame image, sliced from the verified factory interface file.
    static func factoryPhoto(flashFile: String) throws -> [UInt8] {
        guard let fh = FileHandle(forReadingAtPath: flashFile) else { throw LinkError("Factory file not found: \(flashFile)") }
        defer { try? fh.close() }
        try fh.seek(toOffset: UInt64(ScreenProtocol.photoSlot))
        let bytes = [UInt8](try fh.read(upToCount: ScreenProtocol.imageBytes) ?? Data())
        try ScreenProtocol.validateContainer(bytes)
        return bytes
    }

    /// Writes a PNG of exactly what the screen will show (after RGB565 conversion).
    static func preview(_ container: [UInt8], to path: String) throws {
        let ctx = context()
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(w * h) {
            let v = UInt16(container[11 + 2 * i]) | UInt16(container[12 + 2 * i]) << 8
            p[4 * i] = UInt8((v >> 11) * 255 / 31); p[4 * i + 1] = UInt8(((v >> 5) & 63) * 255 / 63)
            p[4 * i + 2] = UInt8((v & 31) * 255 / 31); p[4 * i + 3] = 255
        }
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    /// PNG of icon 341 (67×67 ARGB4444) from a block, over the black page, scaled 4×.
    static func iconPreview(_ block: [UInt8], to path: String) throws {
        let n = 67, s = 4
        let ctx = CGContext(data: nil, width: n * s, height: n * s, bitsPerComponent: 8, bytesPerRow: n * s * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let base = InterfaceBlockTest.iconRange.lowerBound
        for y in 0..<(n * s) {
            for x in 0..<(n * s) {
                let i = base + 2 * ((y / s) * n + x / s)
                let v = UInt16(block[i]) | UInt16(block[i + 1]) << 8
                let a = Int(v >> 12) * 17
                let c = [Int((v >> 8) & 15) * 17, Int((v >> 4) & 15) * 17, Int(v & 15) * 17]
                for k in 0..<3 { p[4 * (y * n * s + x) + k] = UInt8(c[k] * a / 255) }
                p[4 * (y * n * s + x) + 3] = 255
            }
        }
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    /// PNG of two ARGB4444 icons side by side (stock left, new right) over black, scaled 4×.
    static func iconPair(_ before: [UInt16], _ after: [UInt16], width n: Int, height m: Int, to path: String) throws {
        let s = 4, gap = 8, W = (2 * n) * s + gap, H = m * s
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<H {
            for x in 0..<W {
                let o = 4 * (y * W + x); p[o + 3] = 255
                let half = n * s + gap
                guard x < n * s || x >= half else { p[o] = 60; p[o + 1] = 60; p[o + 2] = 60; continue }
                let src = x < n * s ? before : after, xx = (x < n * s ? x : x - half) / s
                let v = src[(y / s) * n + xx]
                let a = Int(v >> 12) * 17
                let c = [Int((v >> 8) & 15) * 17, Int((v >> 4) & 15) * 17, Int(v & 15) * 17]
                for k in 0..<3 { p[o + k] = UInt8(c[k] * a / 255) }
            }
        }
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    /// The 171-frame factory animation, sliced from the verified factory file and checked.
    static func factoryGIF(flashFile: String) throws -> [UInt8] {
        guard let fh = FileHandle(forReadingAtPath: flashFile) else { throw LinkError("Factory file not found: \(flashFile)") }
        defer { try? fh.close() }
        try fh.seek(toOffset: UInt64(ScreenProtocol.Slot.gif.base))
        let bytes = [UInt8](try fh.read(upToCount: ScreenProtocol.gifMaxBytes) ?? Data())
        let info = try GIFContainer.info(bytes)
        guard info.frameCount == 171, bytes.count == ScreenProtocol.gifMaxBytes else { throw LinkError("Not the verified factory animation") }
        return bytes
    }

    /// Five frames: four smooth full-colour gradient (lots of off-ramp colours) with a big frame
    /// number. Per-frame palettes. With delay field 100 the numbers changed ~7.5×/s on hardware,
    /// so the unit isn't centiseconds; delay 400 tells milliseconds (2.5×/s) from "ignored" (no change).
    static func gifTest(delay: Int = 400, previewTo: String? = nil) throws -> [UInt8] {
        var frames = [[UInt8]]()
        for n in 1...4 {
            let ctx = context()
            let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
            let hue = CGFloat(n - 1) / 4
            NSGradient(colors: [NSColor(hue: hue, saturation: 0.8, brightness: 1, alpha: 1),
                                NSColor(hue: hue + 0.3, saturation: 0.7, brightness: 0.35, alpha: 1)])!
                .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
            NSGradient(starting: .black, ending: .white)!.draw(in: NSRect(x: 20, y: 40, width: w - 40, height: 30), angle: 0)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 220), .foregroundColor: NSColor.white]
            ("\(n)" as NSString).draw(at: NSPoint(x: 100, y: 150), withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
            frames.append(rgba(ctx))
        }
        // Frame 5: hue across, brightness down — tens of thousands of colours, so it takes the
        // dithered path (own 256-colour palette, damped serpentine diffusion).
        var field = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let c = NSColor(hue: CGFloat(x) / CGFloat(w), saturation: 0.75, brightness: 1 - 0.85 * CGFloat(y) / CGFloat(h), alpha: 1)
                .usingColorSpace(.sRGB)!
            let i = 4 * (y * w + x)
            field[i] = UInt8(c.redComponent * 255); field[i + 1] = UInt8(c.greenComponent * 255); field[i + 2] = UInt8(c.blueComponent * 255)
        } }
        let ctx5 = context()
        ctx5.data!.copyMemory(from: field, byteCount: field.count)
        let ns5 = NSGraphicsContext(cgContext: ctx5, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns5
        ("5" as NSString).draw(at: NSPoint(x: 100, y: 150), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 220), .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState()
        frames.append(rgba(ctx5))
        let encoded = PaletteQuantizer.convertAnimation(frames, width: w, height: h)
        for (n, frame) in encoded.enumerated() {
            let colours = Set(frame)
            print("Frame \(n + 1): \(colours.count) colours, \(colours.filter { !ColorConversion.isRampLegal($0) }.count) off the ramp.")
        }
        if let previewTo {
            for (n, frame) in encoded.enumerated() {
                try preview([0] + [UInt8](repeating: 0, count: 10) + ColorConversion.bytesLE(frame), to: "\(previewTo)/gif-frame\(n + 1).png")
            }
        }
        return try GIFContainer.encode(frames: encoded, delay: delay)
    }
}
