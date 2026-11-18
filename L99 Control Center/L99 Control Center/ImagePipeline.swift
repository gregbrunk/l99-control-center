import CoreGraphics
import Foundation
import ImageIO
import L99Core
import UniformTypeIdentifiers

/// How a picture is placed on the 320 × 480 screen.
nonisolated struct Framing: Equatable, Sendable {
    enum Mode: String, CaseIterable, Sendable {
        case fill = "Fill"
        case fit = "Fit"
    }
    var mode: Mode = .fill
    /// 1 = just covers (fill) or just fits (fit) the screen.
    var zoom: Double = 1
    /// Pan, in screen points from centred. Only matters when the picture is larger than the screen.
    var offset: CGSize = .zero
}

/// A picture or animation the user dropped, decoded once.
nonisolated struct SourceImage: Sendable {
    let url: URL
    let frames: [CGImage]
    /// Seconds per frame, as stored in the file (0 for stills).
    let delays: [Double]
    let pixelWidth: Int
    let pixelHeight: Int

    var isAnimated: Bool { frames.count > 1 }
    var duration: Double { delays.reduce(0, +) }

    static let supportedTypes: [UTType] = [.png, .jpeg, .heic, .gif, .tiff, .webP, .bmp, .image]

    static func load(_ url: URL) throws -> SourceImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PipelineError("Couldn't open \(url.lastPathComponent).")
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw PipelineError("\(url.lastPathComponent) has no image in it.") }
        var frames = [CGImage]()
        var delays = [Double]()
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        // Large stills are decoded at a sensible size; animations frame by frame.
        if count == 1 {
            let thumb = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400,
            ] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumb) else {
                throw PipelineError("Couldn't decode \(url.lastPathComponent).")
            }
            frames = [image]
            delays = [0]
        } else {
            for i in 0..<count {
                guard let image = CGImageSourceCreateImageAtIndex(source, i, options) else { continue }
                frames.append(image)
                delays.append(frameDelay(source, i))
            }
        }
        guard let first = frames.first else { throw PipelineError("Couldn't decode \(url.lastPathComponent).") }
        return SourceImage(url: url, frames: frames, delays: delays, pixelWidth: first.width, pixelHeight: first.height)
    }

    private static func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return 0.1 }
        for key in [kCGImagePropertyGIFDictionary, kCGImagePropertyPNGDictionary, kCGImagePropertyWebPDictionary] {
            guard let dict = props[key] as? [CFString: Any] else { continue }
            let unclamped = (dict[kCGImagePropertyGIFUnclampedDelayTime] ?? dict[kCGImagePropertyAPNGUnclampedDelayTime]
                ?? dict[kCGImagePropertyWebPUnclampedDelayTime]) as? Double
            let clamped = (dict[kCGImagePropertyGIFDelayTime] ?? dict[kCGImagePropertyAPNGDelayTime]
                ?? dict[kCGImagePropertyWebPDelayTime]) as? Double
            if let d = unclamped ?? clamped, d > 0 { return max(0.02, d) }
        }
        return 0.1
    }
}

nonisolated struct PipelineError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Turns pictures into exactly what the screen stores. Pure and thread-safe; runs off the main thread for GIFs.
nonisolated enum ImagePipeline {
    static let width = ScreenProtocol.width
    static let height = ScreenProtocol.height

    /// GIF delay field unit: milliseconds, confirmed on hardware Nov 17 (delay 100 ≈ 0.13 s, 400 ≈ 0.43 s
    /// per frame; drawing adds ~30 ms). Full-screen frames can't play faster than about 7.5 frames/s.
    static let gifDelayUnit = 0.001

    // MARK: Rendering

    /// Draws `image` onto a black 320 × 480 canvas and returns RGBA8 bytes, top row first.
    static func render(_ image: CGImage, framing: Framing) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.interpolationQuality = .high
            ctx.draw(image, in: drawRect(imageWidth: image.width, imageHeight: image.height, framing: framing))
        }
        return rgba
    }

    /// Where the picture lands on the screen, in CoreGraphics coordinates (origin bottom left).
    static func drawRect(imageWidth: Int, imageHeight: Int, framing: Framing) -> CGRect {
        let sx = Double(width) / Double(imageWidth), sy = Double(height) / Double(imageHeight)
        let base = framing.mode == .fill ? max(sx, sy) : min(sx, sy)
        let scale = base * max(0.1, framing.zoom)
        let w = Double(imageWidth) * scale, h = Double(imageHeight) * scale
        // Clamp the pan so a filled picture never shows its edge.
        var dx = framing.offset.width, dy = framing.offset.height
        if w > Double(width) { dx = min(max(dx, -(w - Double(width)) / 2), (w - Double(width)) / 2) } else { dx = 0 }
        if h > Double(height) { dy = min(max(dy, -(h - Double(height)) / 2), (h - Double(height)) / 2) } else { dy = 0 }
        // offset is in screen space (y down); CoreGraphics is y up.
        return CGRect(x: (Double(width) - w) / 2 + dx, y: (Double(height) - h) / 2 - dy, width: w, height: h)
    }

    // MARK: Stills

    struct Still: Sendable {
        let container: [UInt8]          // 307,211 bytes, ready to send
        let pixels: [UInt16]            // what the screen will show
    }

    static func makeStill(_ image: CGImage, framing: Framing, smoothGradients: Bool) throws -> Still {
        let rgba = render(image, framing: framing)
        let pixels = ColorConversion.convert(rgba: rgba, width: width, height: height,
                                             method: smoothGradients ? .dither565 : .truncate)
        let container = try ScreenProtocol.imageContainer(rgb565: ColorConversion.bytesLE(pixels))
        try ScreenProtocol.validateContainer(container)
        return Still(container: container, pixels: pixels)
    }

    // MARK: Animations

    enum GIFColors: String, CaseIterable, Sendable {
        /// Each frame keeps its exact colours if it has ≤256, otherwise gets its own best-fit palette
        /// (the factory animation shows the screen supports any RGB565 colour).
        case shared = "Best colours"
        /// gavindi's fixed 252-colour ramp, proven on hardware with from-scratch GIFs.
        case ramp = "Safe colours"
    }

    struct Animation: Sendable {
        let blob: [UInt8]
        let frameCount: Int
        let delayField: Int
        let sourceFrameCount: Int
        /// Automatic fixes applied, in plain words, for the GIF panel.
        let fixes: [String]
        /// A few decoded frames for the preview strip.
        let previewFrames: [[UInt16]]
        var seconds: Double { Double(frameCount * delayField) * gifDelayUnit }
    }

    /// Picks which source frames to keep and one equal delay, as the screen requires.
    static func plan(frameCount: Int, delays: [Double], keep: Int) -> (indices: [Int], delay: Int) {
        let keep = max(1, min(keep, frameCount))
        let indices = (0..<keep).map { Int((Double($0) * Double(frameCount) / Double(keep)).rounded(.down)) }
        let total = delays.reduce(0, +)
        let perFrame = total > 0 ? total / Double(keep) : 0.1
        let delay = max(1, min(0xFFFF, Int((perFrame / gifDelayUnit).rounded())))
        return (indices, delay)
    }

    /// Encodes the animation, dropping frames evenly until it fits the 200-frame and size limits.
    static func makeAnimation(_ source: SourceImage, framing: Framing, colors: GIFColors,
                              progress: @Sendable (Double) -> Void) throws -> Animation {
        var fixes = [String]()
        var keep = min(source.frames.count, GIFContainer.maxFrames)
        if source.frames.count > GIFContainer.maxFrames {
            fixes.append("Reduced \(source.frames.count) frames to \(GIFContainer.maxFrames), the screen's limit.")
        }
        if Set(source.delays.map { ($0 * 1000).rounded() }).count > 1 {
            fixes.append("Evened out the frame timing; the screen needs one delay for every frame.")
        }

        // Render every source frame once.
        var rendered = [[UInt8]]()
        rendered.reserveCapacity(source.frames.count)
        for (i, frame) in source.frames.enumerated() {
            rendered.append(render(frame, framing: framing))
            progress(0.3 * Double(i + 1) / Double(source.frames.count))
        }

        for attempt in 0..<6 {
            let (indices, delay) = plan(frameCount: rendered.count, delays: source.delays, keep: keep)
            let chosen = indices.map { rendered[$0] }
            let frames: [[UInt16]]
            switch colors {
            case .shared:
                frames = PaletteQuantizer.convertAnimation(chosen, width: width, height: height) { done in
                    progress(0.3 + 0.6 * Double(done) / Double(chosen.count))
                }
            case .ramp:
                frames = chosen.enumerated().map { i, rgba in
                    progress(0.3 + 0.6 * Double(i + 1) / Double(chosen.count))
                    return ColorConversion.convert(rgba: rgba, width: width, height: height, method: .ramp)
                }
            }
            do {
                let blob = try GIFContainer.encode(frames: frames, delay: delay)
                _ = try GIFContainer.info(blob)          // re-check what we built
                progress(1)
                if keep < min(source.frames.count, GIFContainer.maxFrames) {
                    fixes.append("Used \(keep) of the frames so the animation fits the screen's space; timing is kept.")
                }
                let previewIndices = stride(from: 0, to: frames.count, by: max(1, frames.count / 6)).prefix(6)
                return Animation(blob: blob, frameCount: frames.count, delayField: delay,
                                 sourceFrameCount: source.frames.count, fixes: fixes,
                                 previewFrames: previewIndices.map { frames[$0] })
            } catch GIFContainer.Failure.tooLarge(let size) where attempt < 5 && keep > 1 {
                keep = max(1, Int(Double(keep) * Double(ScreenProtocol.gifMaxBytes) / Double(size) * 0.97))
            }
        }
        throw PipelineError("This animation is too detailed to fit the screen, even with fewer frames.")
    }

    // MARK: Previews

    /// RGB565 pixels → a CGImage for SwiftUI.
    static func cgImage(fromRGB565 pixels: [UInt16], width: Int = width, height: Int = height) -> CGImage? {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<min(pixels.count, width * height) {
            let (r, g, b) = ColorConversion.rgb888(pixels[i])
            rgba[4 * i] = r; rgba[4 * i + 1] = g; rgba[4 * i + 2] = b
        }
        let data = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// The pixels a stored payload shows: an image container, or the first frame of an animation.
    static func pixels(ofPayload payload: [UInt8], slot: ScreenProtocol.Slot) -> [UInt16]? {
        switch slot {
        case .background, .photo:
            guard (try? ScreenProtocol.validateContainer(payload)) != nil else { return nil }
            return ColorConversion.pixels(fromLE: payload[11...])
        case .gif:
            return try? GIFContainer.decodeFrame(payload, index: 0)
        }
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
