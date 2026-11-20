import AppKit
import SwiftUI

/// The L99 mark: a dark squircle holding the keyboard's portrait screen, with four equaliser bars in
/// the accent gradient. Given music levels, the bars move with them; otherwise they rest in a fixed shape.
struct L99Mark: View {
    var size: CGFloat = 44
    /// 0…1 levels (the keyboard's music bands). Empty: the resting shape.
    var levels: [Double] = []

    static let restingBars: [Double] = [0.42, 0.78, 0.58, 0.92]
    static let barGradient = LinearGradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.27), Color(red: 1.0, green: 0.34, blue: 0.40)],
                                            startPoint: .bottom, endPoint: .top)

    private var bars: [Double] {
        guard levels.count >= 8 else { return Self.restingBars }
        // Four bands from the spectrum, lifted a little so quiet music still shows.
        let picks = [1, 4, 8, min(13, levels.count - 1)]
        return picks.map { 0.22 + 0.78 * min(1, max(0, levels[$0])) }
    }

    var body: some View {
        let r = size * 0.28
        ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                              lineWidth: max(0.5, size / 90))
            // The screen: a portrait 2:3 panel.
            let sw = size * 0.44, sh = size * 0.62
            RoundedRectangle(cornerRadius: sw * 0.18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: sw * 0.18, style: .continuous)
                    .strokeBorder(.white.opacity(0.28), lineWidth: max(0.75, size / 60)))
                .frame(width: sw, height: sh)
            HStack(alignment: .bottom, spacing: sw * 0.09) {
                ForEach(bars.indices, id: \.self) { i in
                    Capsule()
                        .fill(Self.barGradient)
                        .frame(width: sw * 0.13, height: max(sw * 0.13, sh * 0.62 * bars[i]))
                }
            }
            .frame(width: sw, height: sh * 0.74, alignment: .bottom)
            .offset(y: sh * 0.04)
            .shadow(color: Color(red: 1, green: 0.45, blue: 0.3).opacity(0.55), radius: size / 14)
            .animation(.smooth(duration: 0.12), value: bars)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("L99 Control Center")
    }
}

#if DEBUG
/// Debug builds: `--render-icon <folder>` writes the app icon PNGs (macOS icon grid: an 824-point
/// squircle on a 1024 canvas, with a soft shadow) and quits.
enum IconRenderer {
    @MainActor static func renderIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count else { return }
        let folder = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let icon = ZStack {
            L99Mark(size: 824)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 12)
        }
        .frame(width: 1024, height: 1024)
        for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
            let renderer = ImageRenderer(content: icon)
            renderer.scale = CGFloat(points * scale) / 1024
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { continue }
            let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
            try? png.write(to: folder.appendingPathComponent(name))
        }
        exit(0)
    }
}
#endif
