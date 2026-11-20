import L99Core
import SwiftUI

/// The menu bar dropdown. Layout follows the "Menu bar dropdown" board in the design mockup.
struct MenuView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var open: WindowOpener { WindowOpener(openWindow: openWindow, model: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()

            if let interrupted = model.transfer.interrupted, !model.transfer.isBusy {
                Notice(systemImage: "exclamationmark.triangle", tint: .orange,
                       text: "“\(interrupted.name)” didn't finish uploading.") {
                    Button("Fix it…") { open(.recovery) }
                }
            }

            section("Live data on the screen") {
                LiveRow(title: "Clock sync", detail: clockStatus, isOn: settingBinding(\.clock))
                LiveRow(title: "CPU and GPU load", detail: loadStatus, isOn: settingBinding(\.load))
                LiveRow(title: "Weather", detail: weatherStatus, isOn: settingBinding(\.weather))
                LiveRow(title: "Music wave", detail: musicStatus, isOn: settingBinding(\.music))
                HStack {
                    Text("Units").font(.callout)
                    Spacer()
                    Picker("Units", selection: Binding(get: { model.settings.usUnits }, set: { model.setUSUnits($0) })) {
                        Text("US (12 h, °F)").tag(true)
                        Text("Metric (24 h, °C)").tag(false)
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small).fixedSize()
                }
                if let note = liveNote {
                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()

            section("Screen content") {
                HStack(spacing: 8) {
                    ForEach(ScreenProtocol.Slot.allCases, id: \.self) { slot in
                        SlotThumbnail(model: model, slot: slot)
                    }
                }
                Button {
                    open(.upload)
                } label: {
                    Label("Upload image or GIF…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                TransferStatus(transfer: model.transfer)
                if !model.devices.screen && !model.transfer.isBusy {
                    Notice(systemImage: "cable.connector", tint: .orange,
                           text: "Uploads need the USB cable. Plug it in when you're ready.")
                }
            }
            Divider()

            VStack(alignment: .leading, spacing: 2) {
                MenuLink("Library…", systemImage: "photo.on.rectangle") { open(.library) }
                MenuLink("Skins…", systemImage: "paintpalette") { open(.skins) }
                MenuLink("Recovery…", systemImage: "arrow.counterclockwise") { open(.recovery) }
                MenuLink("Effects…", systemImage: "waveform") { open(.music) }
            }

            Divider()
            Toggle("Open at login", isOn: Binding(
                get: { model.launchAtLogin.isEnabled },
                set: { model.launchAtLogin.set($0) }
            ))
            .toggleStyle(.switch)
            if model.launchAtLogin.needsApproval {
                Text("Approve it in System Settings > General > Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = model.launchAtLogin.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Divider()
            MenuLink("Quit L99 Control Center", systemImage: "power") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
            if model.settings.weather {
                WeatherAttribution(weather: model.weather)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func settingBinding(_ key: ReferenceWritableKeyPath<LiveSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: key] }, set: { model.settings[keyPath: key] = $0 })
    }

    private var status: LiveStatus { model.keyboard.status }

    private var clockStatus: String {
        guard model.settings.clock || model.settings.load || model.settings.weather else { return "Off" }
        if model.devices.connection == .none { return "Not connected" }
        if status.asleep { return "Keyboard asleep" }
        guard let date = status.lastSync else { return "Waiting…" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var loadStatus: String {
        guard model.settings.load else { return "Off" }
        guard let cpu = status.cpu else { return "…" }
        return "CPU \(cpu)% · GPU \(status.gpu.map { "\($0)%" } ?? "–")"
    }

    private var weatherStatus: String {
        guard model.settings.weather else { return "Off" }
        if let w = model.weather.snapshot {
            return model.settings.usUnits ? "\(w.temperatureF)°F · \(w.humidity)%" : "\(w.temperature)°C · \(w.humidity)%"
        }
        return model.weather.problem == nil ? model.weather.step : "Unavailable"
    }

    private var musicStatus: String {
        guard model.settings.music else { return "Off" }
        if status.audioProblem != nil { return "Can't listen" }
        return status.musicPlaying ? "Playing" : "Waiting for sound"
    }

    /// One line explaining anything that needs attention.
    private var liveNote: String? {
        if model.settings.weather, let problem = model.weather.problem { return problem }
        if model.settings.music, let problem = status.audioProblem { return problem }
        if let error = status.error { return error }
        if status.asleep { return "The keyboard isn't answering over 2.4 GHz. Press a key to wake it." }
        return nil
    }

    private var header: some View {
        HStack(spacing: 10) {
            L99Mark(size: 30, levels: model.keyboard.status.musicPlaying ? model.keyboard.status.levels : [])
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("AULA L99").font(.headline)
                Text(model.devices.connectionDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = model.keyboard.batteryPercent {
                Label("\(battery)%", systemImage: batterySymbol(battery))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(battery <= 15 ? Color.red : Color.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel("Battery \(battery) percent")
            }
        }
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// The cable's state, for the toolbar of every window that needs the cable (Upload, Library, Skins, Recovery).
struct CableStatus: View {
    let connected: Bool
    /// The screen is in bootloader mode for a skin install (it shows up as a different USB device then).
    var bootloader = false

    var body: some View {
        Group {
            if bootloader {
                Label("Bootloader mode", systemImage: "cable.connector").foregroundStyle(.blue)
            } else {
                Label(connected ? "Cable connected" : "Cable not connected",
                      systemImage: connected ? "cable.connector" : "cable.connector.slash")
                    .foregroundStyle(connected ? .green : .orange)
            }
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 10)   // breathing room inside the toolbar's pill
    }
}

/// What a slot holds, as far as the library knows.
struct SlotThumbnail: View {
    let model: AppModel
    let slot: ScreenProtocol.Slot

    var body: some View {
        let item = model.library.item(model.library.onScreen[slot])
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if slot == .background && model.skins.homeSkinInstalled {
                    Rectangle().fill(.quaternary)
                        .overlay(Label("Home skin", systemImage: "paintpalette").labelStyle(.iconOnly).foregroundStyle(.secondary))
                        .help("A Home skin is on the keyboard, so backgrounds aren't used.")
                } else if let item, let image = model.library.thumbnails[item.id] {
                    Image(nsImage: image).resizable().interpolation(.medium)
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay(Text("Unknown").font(.caption2).foregroundStyle(.secondary))
                }
            }
            .frame(width: 64, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            Text(slot.displayName).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.displayName): \(item?.name ?? "unknown")")
    }
}

/// Upload or check progress, with Cancel; or the last result.
struct TransferStatus: View {
    let transfer: ScreenTransferController

    var body: some View {
        switch transfer.state {
        case .idle:
            EmptyView()
        case .sending(let name, _, let fraction, let attempt):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(attempt > 1 ? "Retrying “\(name)”…" : "Uploading “\(name)”…").lineLimit(1)
                    Spacer()
                    Text(fraction, format: .percent.precision(.fractionLength(0))).foregroundStyle(.secondary)
                }
                .font(.callout)
                ProgressView(value: fraction)
                HStack {
                    Text("Keep the cable plugged in.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { transfer.cancel() }.controlSize(.small)
                }
            }
        case .done(let message):
            Notice(systemImage: "checkmark.circle", tint: .green, text: message) {
                Button("OK") { transfer.dismissResult() }
            }
        case .failed(let message):
            Notice(systemImage: "xmark.octagon", tint: .red, text: message) {
                Button("OK") { transfer.dismissResult() }
            }
        }
    }
}

struct Notice<Actions: View>: View {
    let systemImage: String
    let tint: Color
    let text: String
    /// The window's larger size; the menu keeps the compact one.
    var large = false
    @ViewBuilder var actions: () -> Actions

    init(systemImage: String, tint: Color, text: String, large: Bool = false, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.systemImage = systemImage
        self.tint = tint
        self.text = text
        self.large = large
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: large ? .center : .top, spacing: large ? 12 : 8) {
            Image(systemName: systemImage).font(large ? .system(size: 16, weight: .medium) : nil).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).font(large ? .system(size: 13.5) : .callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            actions().controlSize(large ? .regular : .small)
        }
        .padding(large ? 14 : 10)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct MenuLink: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

/// A live-data switch with its current value, as in the design's menu.
private struct LiveRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack {
                Text(title)
                Spacer()
                Text(detail).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.callout)
    }
}

/// Apple requires the Weather mark and a link to its data sources wherever WeatherKit data appears.
struct WeatherAttribution: View {
    let weather: WeatherModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            if let url = scheme == .dark ? weather.markDarkURL : weather.markURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(" Weather").font(.caption2)
                }
                .frame(height: 12)
                .accessibilityLabel("Apple Weather")
            } else {
                Text(" Weather").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let legal = weather.legalURL {
                Link("Data sources", destination: legal).font(.caption2)
            }
        }
    }
}
