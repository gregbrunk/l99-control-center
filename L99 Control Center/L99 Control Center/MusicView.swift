import SwiftUI

/// Music and key lighting: a live visualiser up top, then the choices as large tiles.
struct MusicView: View {
    let model: AppModel

    private var settings: LiveSettings { model.settings }
    private var status: LiveStatus { model.keyboard.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            hero

            // Side by side; a grid row gives both cards the same height.
            Grid(horizontalSpacing: 20, verticalSpacing: 20) {
                GridRow {
                    sensitivityCard
                    listeningCard
                }
            }

            SectionCard(icon: "keyboard", title: "Key lights",
                        subtitle: "The keys light up like the screen's bars, then go back to your own lighting when the sound stops.") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(Self.directions, id: \.value) { d in
                        OptionTile(selected: settings.direction == d.value, action: { settings.direction = d.value }) {
                            HStack(spacing: 12) {
                                Image(systemName: d.icon)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(settings.direction == d.value ? Studio.accent : Color.secondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                                    Text(d.detail).font(.l99Note).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                TileCheck(on: settings.direction == d.value)
                            }
                        }
                    }
                }
            }

            SectionCard(icon: "paintpalette", title: "Colours",
                        subtitle: settings.direction == 0 ? "Turn on the key lights to pick their colours."
                                                          : "Each burst of music starts with a second of green and red, then these take over.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(LiveSettings.palettes.indices, id: \.self) { i in
                        OptionTile(selected: settings.palette == i, action: { settings.palette = i }) {
                            VStack(alignment: .leading, spacing: 10) {
                                PaletteBars(colors: Self.swatch(i))
                                HStack {
                                    Text(LiveSettings.palettes[i].name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if settings.palette == i { TileCheck(on: true) }
                                }
                            }
                        }
                    }
                }
                .disabled(settings.direction == 0)
            }

            Text("Stops on its own when the sound stops. Open the Play page on the keyboard's screen to see the bars. Over the cable the bars update about 4 times a second; over 2.4 GHz about 60.")
                .font(.l99Note).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Visualiser

    private var hero: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show music on the keyboard").font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                    Text("The Play page's bars and the key lights move with whatever your Mac is playing.")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Toggle("", isOn: Binding(get: { settings.music }, set: { settings.music = $0 }))
                    .toggleStyle(.switch).controlSize(.large).labelsHidden()
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<21, id: \.self) { i in
                    let level = i < status.levels.count ? status.levels[i] : 0
                    Capsule()
                        .fill(L99Mark.barGradient)
                        .frame(height: max(6, 170 * level))
                        .frame(maxWidth: .infinity)
                        .opacity(settings.music ? 1 : 0.35)
                }
            }
            .frame(height: 170, alignment: .bottom)
            .shadow(color: Studio.accent.opacity(0.5), radius: 14)
            .animation(.linear(duration: 1.0 / 15), value: status.levels)
            .accessibilityHidden(true)
            HStack(spacing: 8) {
                StatusPill(text: previewCaption, tint: status.musicPlaying ? .green : .white.opacity(0.7), live: status.musicPlaying)
                StatusPill(text: routeCaption, tint: status.route == .none ? .orange : .white.opacity(0.7), dot: false)
                Spacer()
            }
        }
        .padding(24)
        .background {
            ZStack {
                shape.fill(LinearGradient(colors: [Color(white: 0.14), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
                shape.fill(RadialGradient(colors: [Studio.accent.opacity(0.28), .clear], center: .bottom, startRadius: 0, endRadius: 420))
            }
        }
        .overlay(shape.strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
    }

    private var sensitivityCard: some View {
        SectionCard(icon: "dial.medium", title: "Sensitivity", subtitle: "Higher makes quiet music fill the bars.") {
            VStack(spacing: 6) {
                Slider(value: Binding(get: { settings.sensitivity }, set: { settings.sensitivity = $0 }), in: 0...1)
                HStack {
                    Text("Calm"); Spacer()
                    Text("\(Int((settings.sensitivity * 100).rounded()))%").monospacedDigit().foregroundStyle(Studio.ink)
                    Spacer(); Text("Lively")
                }
                .font(.l99Note).foregroundStyle(.secondary)
            }
        }
    }

    private var listeningCard: some View {
        SectionCard(icon: "ear", title: "Listening to all Mac sound",
                    subtitle: "Measured in memory only, never saved or sent.") {
            VStack(alignment: .leading, spacing: 10) {
                if let problem = status.audioProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").font(.l99Note).foregroundStyle(.red)
                }
                Text("If the bars stay flat while music plays, allow L99 Control Center in Screen & System Audio Recording.")
                    .font(.l99Note).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                } label: { Label("Open Privacy settings", systemImage: "lock.shield") }
            }
        }
    }

    private var previewCaption: String {
        if !settings.music { return "Off" }
        if !status.listening { return "Not listening" }
        return status.musicPlaying ? "Playing" : "Waiting for sound"
    }

    private var routeCaption: String {
        switch status.route {
        case .dongle: status.asleep ? "Keyboard asleep" : "Over 2.4 GHz"
        case .cable: "Over the cable"
        case .none: "Keyboard not connected"
        }
    }

    // MARK: Choices

    private static let directions: [(value: Int, name: String, detail: String, icon: String)] = [
        (1, "Rise from the bottom", "AULA's default", "arrow.up.to.line"),
        (2, "Fall from the top", "Upside down", "arrow.down.to.line"),
        (0, "Off", "Screen bars only", "lightbulb.slash"),
    ]

    /// Approximate colours for each palette, for the tile swatches.
    private static func swatch(_ i: Int) -> [Color] {
        let rainbow: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]
        switch LiveSettings.palettes[i].name {
        case "Rainbow": return rainbow
        case "Unicorn rainbow": return [.pink, .purple, .indigo, .blue, .cyan, .mint]
        case "Rotating rainbow": return rainbow.reversed()
        case "Pulsing colour cycle": return [.red, .purple, .blue, .cyan, .green, .yellow]
        case "Green, yellow and red": return [.green, .green, .yellow, .yellow, .orange, .red]
        case "Lavender": return [Color(red: 0.75, green: 0.65, blue: 1.0), Color(red: 0.55, green: 0.45, blue: 0.95)]
        case "Red": return [Color(red: 1, green: 0.25, blue: 0.2), Color(red: 0.75, green: 0.05, blue: 0.1)]
        case "Amber": return [Color(red: 1, green: 0.75, blue: 0.2), Color(red: 1, green: 0.5, blue: 0.05)]
        case "Yellow": return [Color(red: 1, green: 0.95, blue: 0.4), Color(red: 1, green: 0.82, blue: 0.1)]
        default: return rainbow
        }
    }
}

/// A tiny equaliser in a palette's colours.
private struct PaletteBars: View {
    let colors: [Color]
    private let heights: [CGFloat] = [0.45, 0.8, 0.6, 1.0, 0.7, 0.5, 0.85]
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                    .frame(height: 34 * heights[i])
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 34, alignment: .bottom)
        .padding(8)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
