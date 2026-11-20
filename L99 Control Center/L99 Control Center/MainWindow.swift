import AppKit
import L99Core
import L99Skins
import SwiftUI

// MARK: Tabs

/// The single window's sections. The menu bar's links open the window on one of these.
enum AppTab: String, CaseIterable, Identifiable {
    case upload, library, skins, music, recovery
    var id: String { rawValue }

    var name: String {
        switch self {
        case .upload: "Upload"
        case .library: "Library"
        case .skins: "Skins"
        case .music: "Effects"
        case .recovery: "Recovery"
        }
    }
    /// The large page title.
    var headline: String {
        switch self {
        case .upload: "Send to the screen"
        case .library: "Your pictures"
        case .skins: "Skins"
        case .music: "Effects"
        case .recovery: "Recovery"
        }
    }
    /// One line under the title.
    var summary: String {
        switch self {
        case .upload: "Frame a photo, background or GIF and send it over the cable."
        case .library: "Everything you've sent, ready to send again."
        case .skins: "A style for each page of the screen, built and installed from your Mac."
        case .music: "Music bars on the screen and lights on the keys, following your Mac's sound."
        case .recovery: "Factory pictures, moving to another Mac, and help if the screen won't start."
        }
    }
    var icon: String {
        switch self {
        case .upload: "square.and.arrow.up"
        case .library: "photo.on.rectangle.angled"
        case .skins: "paintpalette"
        case .music: "waveform"
        case .recovery: "arrow.counterclockwise"
        }
    }
    /// Upload and Skins have their own big preview column, so they skip the keyboard panel.
    var showsKeyboardPanel: Bool { self == .library || self == .music || self == .recovery }
}

// MARK: Theme

/// "Studio" look: a softly lit canvas, frosted panels, capsule controls, a warm orange accent.
enum Studio {
    static let canvas = Color(light: 0xEDEDEF, dark: 0x111113)
    static let panel = Color(light: 0xFBFBFC, dark: 0x1B1B1E)
    static let card = Color(light: 0xFFFFFF, dark: 0x252529)
    static let stroke = Color(light: 0xE3E3E8, dark: 0x2F2F34)
    static let accent = Color(light: 0xE8692A, dark: 0xF5874A)
    static let accentSoft = Color(light: 0xFFEDE2, dark: 0x3A2418)
    static let ink = Color(light: 0x18181A, dark: 0xF4F4F5)
    static let secondaryFill = Color(light: 0xEFEFF2, dark: 0x303035)
    static let secondaryFillHover = Color(light: 0xE5E5EA, dark: 0x3A3A40)

    // 8-point spacing.
    static let gutter: CGFloat = 20
    static let panelPadding: CGFloat = 24
    static let panelRadius: CGFloat = 24
    static let cardRadius: CGFloat = 18

    static let motion = Animation.smooth(duration: 0.32)
    static let snap = Animation.snappy(duration: 0.22)
}

/// The window's type scale. macOS's text styles are small (caption is 10 pt), so the window uses its own.
extension Font {
    static let l99Small = Font.system(size: 11, weight: .medium)
    static let l99Note = Font.system(size: 12.5)
    static let l99Body = Font.system(size: 14)
    static let l99Headline = Font.system(size: 16, weight: .semibold)
    static let l99Title = Font.system(size: 20, weight: .semibold)
}

extension Color {
    /// A colour that follows light and dark mode.
    init(light: UInt32, dark: UInt32) {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light)
        })
    }
}

extension View {
    /// A large frosted panel on the canvas: the backdrop's light tints it faintly.
    func studioPanel(padding: CGFloat = Studio.panelPadding) -> some View {
        let shape = RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous)
        return self.padding(padding)
            .background { ZStack { shape.fill(.ultraThinMaterial); shape.fill(Studio.panel.opacity(0.86)) } }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Studio.stroke, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 18, y: 8)
    }

    /// A white card inside a panel.
    func studioCard(padding: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: Studio.cardRadius, style: .continuous)
        return self.padding(padding)
            .background(Studio.card, in: shape)
            .overlay(shape.strokeBorder(Studio.stroke, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
    }

    /// Lifts a little under the pointer.
    func hoverLift(_ amount: CGFloat = 1.015) -> some View { modifier(HoverLift(amount: amount)) }
}

private struct HoverLift: ViewModifier {
    let amount: CGFloat
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? amount : 1)
            .shadow(color: .black.opacity(hovering ? 0.10 : 0), radius: hovering ? 16 : 0, y: hovering ? 8 : 0)
            .onHover { h in withAnimation(Studio.snap) { hovering = h } }
    }
}

/// Capsule buttons: black for the one main action, soft grey for the rest. They brighten on hover.
/// `.controlSize(.large)` gives the tall full-width call to action.
struct StudioButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View { StudioButton(configuration: configuration, primary: primary) }
}

private struct StudioButton: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    @Environment(\.controlSize) private var size
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        let small = size == .small || size == .mini
        let large = size == .large || size == .extraLarge
        configuration.label
            .font(.system(size: small ? 12.5 : large ? 15 : 13.5, weight: large ? .semibold : .medium))
            .lineLimit(1)
            .fixedSize(horizontal: !large, vertical: false)
            .padding(.horizontal, small ? 12 : large ? 22 : 16)
            .frame(minHeight: small ? 28 : large ? 46 : 34)
            .foregroundStyle(primary ? Color(light: 0xFFFFFF, dark: 0x111113) : Studio.ink)
            .background {
                if primary {
                    Capsule().fill(Studio.ink).opacity(hovering ? 0.86 : 1)
                        .shadow(color: .black.opacity(hovering ? 0.20 : 0.10), radius: hovering ? 10 : 4, y: 3)
                } else {
                    Capsule().fill(hovering ? Studio.secondaryFillHover : Studio.secondaryFill)
                }
            }
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Studio.snap, value: configuration.isPressed)
            .animation(Studio.snap, value: hovering)
            .contentShape(Capsule())
            .onHover { hovering = enabled && $0 }
    }
}

extension ButtonStyle where Self == StudioButtonStyle {
    static var studio: StudioButtonStyle { StudioButtonStyle() }
    static var studioPrimary: StudioButtonStyle { StudioButtonStyle(primary: true) }
}

// MARK: Pill picker

struct PillOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var icon: String?
    var disabled = false
    var id: Value { value }
}

/// A roomy segmented control: a soft capsule track with a white thumb that slides to the choice.
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [PillOption<Value>]
    var large = false
    /// Stretch the segments to fill the width.
    var fill = false
    @Namespace private var thumb
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let on = option.value == selection
                Button { withAnimation(Studio.snap) { selection = option.value } } label: {
                    HStack(spacing: 7) {
                        if let icon = option.icon {
                            Image(systemName: icon)
                                .font(.system(size: large ? 13.5 : 12, weight: .semibold))
                                .foregroundStyle(on ? Studio.accent : Color.secondary)
                        }
                        Text(option.label).lineLimit(1)
                    }
                    .font(.system(size: large ? 14 : 13, weight: on ? .semibold : .medium))
                    .foregroundStyle(on ? Studio.ink : Color.secondary)
                    .padding(.horizontal, large ? 18 : 14)
                    .frame(height: large ? 38 : 32)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .background {
                        if on {
                            Capsule().fill(Studio.card)
                                .shadow(color: .black.opacity(0.12), radius: 5, y: 1)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        } else if hovered == option.value {
                            Capsule().fill(Studio.ink.opacity(0.05))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(option.disabled)
                .opacity(option.disabled ? 0.4 : 1)
                .onHover { h in hovered = h ? option.value : (hovered == option.value ? nil : hovered) }
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Studio.secondaryFill))
        .overlay(Capsule().strokeBorder(Studio.stroke, lineWidth: 0.5))
        .fixedSize(horizontal: !fill, vertical: true)
    }
}

/// A large selectable tile (radio-style): accent ring and tint when chosen, lift on hover.
struct OptionTile<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: { withAnimation(Studio.snap) { action() } }) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(selected ? Studio.accentSoft : (hovering ? Studio.secondaryFill : Studio.card), in: shape)
                .overlay(shape.strokeBorder(selected ? Studio.accent : Studio.stroke, lineWidth: selected ? 2 : 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .scaleEffect(hovering && enabled && !selected ? 1.01 : 1)
        .animation(Studio.snap, value: hovering)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A round accent check shown on chosen tiles.
struct TileCheck: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Studio.accent : Color.secondary.opacity(0.4), lineWidth: 1.5)
            if on { Circle().fill(Studio.accent); Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
        }
        .frame(width: 18, height: 18)
    }
}

/// A small coloured status capsule ("On screen", "Dongle"). `live` makes its dot pulse.
struct StatusPill: View {
    let text: String
    var tint: Color = .green
    var dot = true
    var live = false

    var body: some View {
        HStack(spacing: 6) {
            if dot { PulseDot(tint: tint, live: live) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(tint.opacity(0.13), in: Capsule())
        .fixedSize()
    }
}

/// A dot that sends out a soft ring every couple of seconds while something is live.
struct PulseDot: View {
    let tint: Color
    var live = true

    var body: some View {
        Circle().fill(tint).frame(width: 7, height: 7)
            .background {
                if live {
                    Circle().stroke(tint, lineWidth: 1.5)
                        .phaseAnimator([false, true]) { ring, expanded in
                            ring.scaleEffect(expanded ? 2.6 : 1).opacity(expanded ? 0 : 0.7)
                        } animation: { expanded in expanded ? .easeOut(duration: 1.6) : .linear(duration: 0.01).delay(0.6) }
                }
            }
    }
}

/// The section label used in every tab: small, spaced capitals.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11.5, weight: .semibold)).kerning(0.9).foregroundStyle(.secondary)
    }
}

/// A card with an icon badge, a title and an optional line under it.
struct SectionCard<Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color = Studio.accent
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.l99Headline)
                    if let subtitle { Text(subtitle).font(.l99Note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .studioCard()
    }
}

/// Two little colour stops for each skin style, for swatches in menus and rows.
extension SkinStyle {
    var swatch: [Color] {
        switch self {
        case .liquidGlassNight: [Color(red: 0.16, green: 0.20, blue: 0.42), Color(red: 0.45, green: 0.55, blue: 0.95)]
        case .liquidGlassDay: [Color(red: 0.80, green: 0.90, blue: 1.0), Color(red: 0.55, green: 0.72, blue: 0.98)]
        case .cyberpunk: [Color(red: 1.0, green: 0.18, blue: 0.55), Color(red: 0.10, green: 0.90, blue: 0.95)]
        case .ceramic: [Color(red: 0.96, green: 0.93, blue: 0.87), Color(red: 0.78, green: 0.70, blue: 0.60)]
        case .ember: [Color(red: 1.0, green: 0.55, blue: 0.15), Color(red: 0.75, green: 0.12, blue: 0.10)]
        case .midnightLED: [Color(red: 0.05, green: 0.06, blue: 0.10), Color(red: 0.20, green: 0.95, blue: 0.55)]
        }
    }
}

struct StyleSwatch: View {
    let style: SkinStyle?
    var size: CGFloat = 16
    var body: some View {
        Group {
            if let style {
                Circle().fill(LinearGradient(colors: style.swatch, startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                Circle().fill(Studio.secondaryFill).overlay(Circle().strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
            }
        }
        .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
        .frame(width: size, height: size)
    }
}

/// The canvas: soft coloured light behind the panels, so the frosted surfaces have something to catch.
private struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let d = scheme == .dark
            ZStack {
                Studio.canvas
                glow(Color(red: 1.0, green: 0.55, blue: 0.25), d ? 0.26 : 0.34, at: UnitPoint(x: 0.10, y: 0), radius: max(w, h) * 0.55)
                glow(Color(red: 1.0, green: 0.38, blue: 0.50), d ? 0.14 : 0.16, at: UnitPoint(x: 0.45, y: 0), radius: max(w, h) * 0.35)
                glow(Color(red: 0.45, green: 0.48, blue: 1.0), d ? 0.24 : 0.20, at: .bottomTrailing, radius: max(w, h) * 0.55)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func glow(_ color: Color, _ strength: Double, at center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [color.opacity(strength), color.opacity(strength * 0.45), color.opacity(0)],
                       center: center, startRadius: 0, endRadius: radius)
    }
}

// MARK: Window

struct MainWindow: View {
    let model: AppModel

    private var tab: AppTab { model.tab }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let compact = w < 1160
            let panel = tab.showsKeyboardPanel && w >= 1240
            HStack(alignment: .top, spacing: 18) {
                Rail(model: model)
                VStack(alignment: .leading, spacing: 20) {
                    header(compact: compact)
                    HStack(alignment: .top, spacing: 18) {
                        content
                            .id(tab)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)).combined(with: .scale(scale: 0.995)),
                                                    removal: .opacity))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        if panel {
                            KeyboardPanel(model: model)
                                .frame(width: w >= 1500 ? 300 : 268)
                                .frame(maxHeight: .infinity)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                .zIndex(1)
            }
            .padding(.leading, 14)
            .padding([.trailing, .bottom], Studio.gutter)
            .padding(.top, 40)   // clear of the window buttons
            .animation(Studio.motion, value: tab)
            .animation(Studio.motion, value: panel)
        }
        .frame(minWidth: 1000, minHeight: 680)
        .background(Backdrop())
        .buttonStyle(.studio)
        .tint(Studio.accent)
        .font(.l99Body)
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.headline)
                    .font(.system(size: compact ? 28 : 32, weight: .regular))
                    .kerning(compact ? -0.6 : -0.8)
                    .foregroundStyle(Studio.ink)
                Text(tab.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            accessory(compact: compact)
        }
        .frame(height: 84)   // the same height as the rail's logo row, so the title lines up with the mark
    }

    @ViewBuilder private func accessory(compact: Bool) -> some View {
        switch tab {
        case .upload:
            PillPicker(selection: Binding(get: { model.upload.slot }, set: { new in
                model.upload.slot = new == .background && model.skins.homeSkinInstalled ? .photo : new
                model.upload.slotChanged()
            }), options: ScreenProtocol.Slot.allCases.map { slot in
                PillOption(value: slot, label: slot.displayName, icon: slot.symbol,
                           disabled: slot == .background && model.skins.homeSkinInstalled)
            }, large: true)
        case .library:
            HStack(spacing: 12) {
                PillPicker(selection: Binding(get: { model.libraryFilter }, set: { new in withAnimation(Studio.motion) { model.libraryFilter = new } }),
                           options: [PillOption(value: ScreenProtocol.Slot?.none, label: "All", icon: "square.grid.2x2")]
                            + ScreenProtocol.Slot.allCases.map { PillOption(value: Optional($0), label: $0.displayName, icon: compact ? nil : $0.symbol) },
                           large: true)
                SearchField(text: Binding(get: { model.librarySearch }, set: { model.librarySearch = $0 }))
                    .frame(width: compact ? 150 : 220)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .upload: UploadView(model: model).studioPanel(padding: 0)
        case .library: LibraryView(model: model).studioPanel()
        case .skins: SkinsView(model: model).studioPanel(padding: 0)
        case .music: scrolling { MusicView(model: model) }
        case .recovery: scrolling { RecoveryView(model: model) }
        }
    }

    /// A panel that fills the space and scrolls its content.
    private func scrolling(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView { content().frame(maxWidth: .infinity, alignment: .leading).padding(Studio.panelPadding) }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .studioPanel(padding: 0)
    }
}

extension ScreenProtocol.Slot {
    var symbol: String {
        switch self {
        case .background: "photo"
        case .photo: "person.crop.square"
        case .gif: "play.rectangle"
        }
    }
}

/// A capsule search box that matches the pill controls.
struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $text).textFieldStyle(.plain).focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Studio.card, in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? Studio.accent.opacity(0.6) : Studio.stroke, lineWidth: focused ? 1.5 : 0.5))
        .animation(Studio.snap, value: focused)
    }
}

/// The rail: a glass column with the mark, then each tab as an icon with its name underneath.
/// The names are always there, so nothing has to open over the page to read them.
private struct Rail: View {
    static let width: CGFloat = 84
    let model: AppModel
    @Namespace private var selection
    @State private var hovered: AppTab?

    var body: some View {
        VStack(spacing: 6) {
            L99Mark(size: Rail.width - 16, levels: model.keyboard.status.musicPlaying ? model.keyboard.status.levels : [])
                .padding(.top, 8)   // the same as the side margins
                .padding(.bottom, 14)
                .help("L99 Control Center")
            ForEach(AppTab.allCases) { tab in item(tab) }
            Spacer(minLength: 12)
            cable
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 8)
        .frame(width: Rail.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = model.tab == tab
        return Button { withAnimation(Studio.motion) { model.tab = tab } } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Studio.accent : Color.secondary)
                    .symbolEffect(.bounce, value: selected)
                    .frame(height: 22)
                Text(tab.name)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Studio.ink : Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Studio.card)
                        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                        .matchedGeometryEffect(id: "selection", in: selection)
                } else if hovered == tab {
                    RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Studio.ink.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Studio.snap) { hovered = h ? tab : (hovered == tab ? nil : hovered) } }
        .accessibilityLabel(tab.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Green with the cable in, orange without; blue in bootloader mode during a skin install.
    private var cable: some View {
        let boot = model.skins.inBootloader, on = model.devices.screen
        let tint: Color = boot ? .blue : on ? .green : .orange
        let short = boot ? "Bootloader" : on ? "Cable in" : "No cable"
        let text = boot ? "Bootloader mode" : on ? "Cable connected" : "Cable not connected: uploads and skins need it"
        return VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "cable.connector.horizontal")
                    .font(.system(size: 15))
                    .foregroundStyle(on || boot ? tint : Color.secondary)
                    .frame(width: 40, height: 32)
                PulseDot(tint: tint, live: on || boot).offset(x: -4, y: 2)
            }
            Text(short).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(tint).fixedSize()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .help(text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// The keyboard at a glance: connection, what's on the screen, the skin, live data, shortcuts.
private struct KeyboardPanel: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Studio.accent.opacity(0.35)).frame(width: 48, height: 48).blur(radius: 10)
                    Image(systemName: "keyboard")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(LinearGradient(colors: [Color(red: 1, green: 0.6, blue: 0.3), Studio.accent], startPoint: .top, endPoint: .bottom), in: Circle())
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("AULA L99").font(.system(size: 17, weight: .semibold))
                    StatusPill(text: connection, tint: connected ? .green : .orange, live: connected)
                }
                Spacer(minLength: 0)
            }
            section("On the screen") {
                HStack(spacing: 10) {
                    ForEach(ScreenProtocol.Slot.allCases, id: \.self) { slot in PanelThumbnail(model: model, slot: slot) }
                }
            }
            section("Skin") {
                HStack(spacing: 10) {
                    StyleSwatch(style: model.skins.installedPlan?.topBarStyle, size: 22)
                    Text(model.skins.installedSummary).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !liveFacts.isEmpty {
                section("Live") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(liveFacts, id: \.0) { fact in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fact.1).font(.system(size: 22, weight: .semibold).monospacedDigit())
                                    .contentTransition(.numericText())
                                Text(fact.0).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Studio.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .animation(Studio.motion, value: liveFacts.map(\.1))
                }
            }
            section("Shortcuts") {
                VStack(spacing: 8) {
                    shortcut("Upload a picture", icon: "square.and.arrow.up", tab: .upload)
                    shortcut("Change the skin", icon: "paintpalette", tab: .skins)
                }
            }
            Spacer(minLength: 0)
            if model.skins.homeSkinInstalled {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text("Keep Screen › Background on Default while a Home skin is on.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Color(light: 0x8A3A12, dark: 0xF5B48A))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Studio.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .studioPanel(padding: 20)
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) { SectionLabel(title); content() }
    }

    private func shortcut(_ title: String, icon: String, tab: AppTab) -> some View {
        Button { withAnimation(Studio.motion) { model.tab = tab } } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(Studio.accent).frame(width: 20)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Studio.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Studio.stroke, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLift(1.02)
    }

    private var connected: Bool { model.devices.connection != .none }

    private var connection: String {
        let d = model.devices
        if d.dongle && d.screen { return "Dongle · cable in" }
        if d.screen { return "Cable" }
        if d.dongle { return "Dongle" }
        return connected ? "Connected" : "Not connected"
    }

    private var liveFacts: [(String, String)] {
        var facts: [(String, String)] = []
        if let w = model.weather.snapshot, model.settings.weather {
            facts.append(("Outside", model.settings.usUnits ? "\(w.temperatureF)°" : "\(w.temperature)°"))
        }
        if let cpu = model.keyboard.status.cpu { facts.append(("CPU", "\(cpu)%")) }
        if let battery = model.keyboard.batteryPercent { facts.append(("Battery", "\(battery)%")) }
        return facts
    }
}

/// A thumbnail of what's in one slot, sized to fill its share of the panel.
private struct PanelThumbnail: View {
    let model: AppModel
    let slot: ScreenProtocol.Slot

    var body: some View {
        let item = model.library.item(model.library.onScreen[slot])
        VStack(spacing: 6) {
            Group {
                if slot == .background && model.skins.homeSkinInstalled {
                    Rectangle().fill(Studio.secondaryFill)
                        .overlay(Image(systemName: "paintpalette").font(.system(size: 16)).foregroundStyle(.secondary))
                        .help("A Home skin is on the keyboard, so backgrounds aren't used.")
                } else if let item, let image = model.library.thumbnails[item.id] {
                    Image(nsImage: image).resizable().interpolation(.medium)
                } else {
                    Rectangle().fill(Studio.secondaryFill)
                        .overlay(Image(systemName: "questionmark").foregroundStyle(.secondary))
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Studio.stroke))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            Text(slot.displayName).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.displayName): \(item?.name ?? "unknown")")
    }
}
