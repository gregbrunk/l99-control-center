import SwiftUI

/// "Music & key lighting" window, following the design mockup's board.
struct MusicView: View {
    let model: AppModel

    private var settings: LiveSettings { model.settings }
    private var status: LiveStatus { model.keyboard.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: Binding(get: { settings.music }, set: { settings.music = $0 })) {
                Text("Show music on the keyboard").font(.headline)
            }
            .toggleStyle(.switch)

            preview

            VStack(alignment: .leading, spacing: 6) {
                label("Listen to")
                Text("All Mac sound. macOS asks once for permission to record system audio; the sound is only measured in memory, never saved or sent.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let problem = status.audioProblem {
                    Text(problem).font(.callout).foregroundStyle(.red)
                }
                Text("If the bars stay flat while music plays, allow L99 Control Center in System Settings › Privacy & Security › Screen & System Audio Recording.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                label("Look")
                HStack {
                    Text("Sensitivity").frame(width: 92, alignment: .leading)
                    Slider(value: Binding(get: { settings.sensitivity }, set: { settings.sensitivity = $0 }), in: 0...1)
                }
                HStack {
                    Text("Key lights").frame(width: 92, alignment: .leading)
                    Picker("Key lights", selection: Binding(get: { settings.direction }, set: { settings.direction = $0 })) {
                        ForEach(LiveSettings.directions, id: \.value) { Text($0.name).tag($0.value) }
                    }
                    .labelsHidden()
                }
                HStack {
                    Text("Colours").frame(width: 92, alignment: .leading)
                    Picker("Colours", selection: Binding(get: { settings.palette }, set: { settings.palette = $0 })) {
                        ForEach(LiveSettings.palettes.indices, id: \.self) { Text(LiveSettings.palettes[$0].name).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(settings.direction == 0)
                }
                Text("The keys light up like the screen's bars, rising from the bottom row or falling from the top. They go back to your own lighting when the sound stops, and each burst of music starts with a second of green and red before your colours take over. The screen's bars look the same whichever you pick.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Stops on its own when the sound stops. Open the Play page on the keyboard's screen to see the bars. Over the cable the bars update about 4 times a second; over 2.4 GHz about 60.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<21, id: \.self) { i in
                    let level = i < status.levels.count ? status.levels[i] : 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.18, green: 0.72, blue: 1))
                        .frame(height: max(2, 90 * level))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 90, alignment: .bottom)
            .animation(.linear(duration: 1.0 / 15), value: status.levels)
            .accessibilityHidden(true)
            HStack {
                Text(previewCaption)
                Spacer()
                Text(routeCaption)
            }
            .font(.caption)
            .foregroundStyle(Color(white: 0.78))
        }
        .padding(14)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08), in: RoundedRectangle(cornerRadius: 10))
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

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}
